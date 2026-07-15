import 'dart:convert';
import 'package:yaml/yaml.dart';
import '../models/models.dart';
import '../models/skill_manifest.dart';

/// Parses agentskills.io compatible SKILL.md content into [SkillManifest]
/// and converts it back to [SavedPlaygroundSetup].
class SkillImporter {
  /// Parses SKILL.md content into a [SkillManifest].
  SkillManifest parseSkillMd(String content) {
    final lines = content.split('\n');

    int? yamlStart;
    int? yamlEnd;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        if (yamlStart == null) {
          yamlStart = i;
        } else if (yamlEnd == null) {
          yamlEnd = i;
          break;
        }
      }
    }

    if (yamlStart == null || yamlEnd == null) {
      throw const FormatException('Invalid SKILL.md: missing YAML frontmatter');
    }

    final yamlContent = lines.sublist(yamlStart + 1, yamlEnd).join('\n');
    final raw = loadYaml(yamlContent);
    if (raw == null || raw is! Map) {
      throw const FormatException('Failed to parse SKILL.md YAML frontmatter');
    }
    final parsed = _toMap(raw);

    final bodyLines = yamlEnd + 1 < lines.length
        ? lines.sublist(yamlEnd + 1)
        : <String>[];
    final bodyMarkdown = bodyLines.join('\n').trim().isEmpty
        ? null
        : bodyLines.join('\n').trim();

    final isTealKit = parsed['compatibility'] is String;

    if (isTealKit) {
      return _parseTealKitFormat(parsed, bodyMarkdown);
    }

    return SkillManifest(
      name: parsed['name'] as String? ?? 'unnamed-skill',
      description: parsed['description'] as String? ?? '',
      version: parsed['version'] as String? ?? '1.0.0',
      author: parsed['author'] as String?,
      systemPrompt: parsed['system_prompt'] as String? ?? '',
      promptSteps: _parsePromptSteps(parsed['prompts']),
      tools: _parseToolDeclarations(parsed['tools']),
      mcpPlaygroundMeta: _parseMcpPlaygroundMeta(parsed['mcp_playground']),
      isMultiTurn:
          (parsed['prompts'] as List?)?.length != null &&
          (parsed['prompts'] as List).length > 1,
      bodyMarkdown: bodyMarkdown,
    );
  }

  SkillManifest _parseTealKitFormat(
    Map<String, dynamic> parsed,
    String? bodyMarkdown,
  ) {
    final metadata = _toMap(parsed['metadata']);
    final workflow = _toMap(metadata['workflow']);
    final agents = _toMapList(metadata['agents']);
    final firstAgent = agents.isNotEmpty ? agents.first : <String, dynamic>{};
    final capabilities = _toStringList(metadata['required_capabilities']);
    final llmSettings = _toMap(metadata['llm_settings']);

    final systemPrompt = (firstAgent['system_prompt'] as String?) ?? '';
    final promptText =
        (workflow['prompt'] as String?) ??
        (firstAgent['prompt'] as String?) ??
        '';

    final subPrompts = parseSubPromptSteps(promptText);
    final promptSteps = subPrompts
        .map(
          (s) => SkillPromptStep(
            text: s.text,
            enabledToolNames: s.enabledToolNames,
            stopAfterToolCall: s.stopAfterToolCall,
          ),
        )
        .toList();

    final tools = capabilities
        .map(
          (c) =>
              SkillToolDeclaration(name: c, tier: 'capability', capability: c),
        )
        .toList();

    Map<String, dynamic>? customLlmConfig;
    if (llmSettings.isNotEmpty) {
      customLlmConfig = {
        'provider': llmSettings['provider'] ?? 'none',
        'model': llmSettings['model'] ?? '',
        'temperature': llmSettings['temperature'] ?? 0.2,
        'maxTokens': llmSettings['max_tokens'] ?? 0,
        'isSlm': llmSettings['is_slm'] ?? false,
        'isMultiModal': llmSettings['is_multi_modal'] ?? true,
        'thinking': llmSettings['thinking'] ?? false,
        'useNativeToolCall': llmSettings['use_native_tool_call'] ?? true,
      };
    }

    return SkillManifest(
      name: (parsed['name'] as String?) ?? 'imported-skill',
      description: (parsed['description'] as String?) ?? '',
      version: '1.0.0',
      author: metadata['author'] as String?,
      systemPrompt: systemPrompt,
      promptSteps: promptSteps,
      tools: tools,
      mcpPlaygroundMeta: McpPlaygroundSkillMetadata(
        chatMode: workflow['chat_mode'] == true,
        stopAfterToolCall: workflow['stop_after_tool_call'] == true,
        useCustomLlm: customLlmConfig != null,
        customLlmConfig: customLlmConfig,
        createdAt: DateTime.now(),
        isMultiTurn: promptSteps.length > 1,
      ),
      isMultiTurn: promptSteps.length > 1,
      bodyMarkdown: bodyMarkdown,
    );
  }

  /// Converts a [SkillManifest] to [SavedPlaygroundSetup].
  SavedPlaygroundSetup toSetup(
    SkillManifest manifest, {
    required Set<String> availableToolNames,
  }) {
    final subPromptSteps = manifest.promptSteps
        .map(
          (s) => SubPromptStep(
            text: s.text,
            enabledToolNames: s.enabledToolNames,
            stopAfterToolCall: s.stopAfterToolCall,
          ),
        )
        .toList();
    final initialPrompt = serializeSubPromptSteps(subPromptSteps);

    final enabledTools = <String>{};
    for (final step in manifest.promptSteps) {
      if (step.enabledToolNames != null) {
        for (final t in step.enabledToolNames!) {
          if (availableToolNames.isEmpty || availableToolNames.contains(t)) {
            enabledTools.add(t);
          }
        }
      }
    }
    for (final tool in manifest.tools) {
      if (availableToolNames.isEmpty ||
          availableToolNames.contains(tool.name)) {
        enabledTools.add(tool.name);
      }
    }

    return SavedPlaygroundSetup(
      id: _UuidFallback().v4(),
      name: manifest.name,
      description: manifest.description,
      createdAt: manifest.mcpPlaygroundMeta?.createdAt ?? DateTime.now(),
      systemPrompt: manifest.systemPrompt,
      initialPrompt: initialPrompt,
      enabledToolNames: enabledTools.toList(),
      chatMode: manifest.mcpPlaygroundMeta?.chatMode ?? false,
      stopAfterToolCall: manifest.mcpPlaygroundMeta?.stopAfterToolCall ?? false,
      useCustomLlm: manifest.mcpPlaygroundMeta?.useCustomLlm ?? false,
      customLlmConfig: manifest.mcpPlaygroundMeta?.customLlmConfig != null
          ? LlmConfig.fromJson(manifest.mcpPlaygroundMeta!.customLlmConfig!)
          : null,
      mcpInitParams: manifest.mcpPlaygroundMeta?.mcpInitParams,
    );
  }

  List<String> getUnresolvableTools(
    SkillManifest manifest,
    Set<String> availableToolNames,
  ) {
    if (availableToolNames.isEmpty) return [];
    final missing = <String>{};
    for (final tool in manifest.tools) {
      if (!availableToolNames.contains(tool.name)) missing.add(tool.name);
    }
    for (final step in manifest.promptSteps) {
      if (step.enabledToolNames != null) {
        for (final t in step.enabledToolNames!) {
          if (!availableToolNames.contains(t)) missing.add(t);
        }
      }
    }
    return missing.toList();
  }

  // ── Sub-parsers ─────────────────────────────────────────────────

  List<SkillPromptStep> _parsePromptSteps(dynamic prompts) {
    if (prompts == null) return [];
    if (prompts is! List) return [];
    return prompts.map((item) {
      if (item is Map) {
        final tools = item['tools'];
        List<String>? toolList;
        if (tools is List) toolList = tools.map((t) => t.toString()).toList();
        return SkillPromptStep(
          text: item['text']?.toString() ?? '',
          enabledToolNames: toolList,
          stopAfterToolCall:
              item['stop_after_tool_call'] == true ||
              item['stopAfterToolCall'] == true,
        );
      } else if (item is String) {
        return SkillPromptStep(text: item);
      }
      return const SkillPromptStep(text: '');
    }).toList();
  }

  List<SkillToolDeclaration> _parseToolDeclarations(dynamic tools) {
    if (tools == null) return [];
    if (tools is! List) return [];
    return tools
        .map((item) {
          if (item is! Map) return null;
          final name = item['name']?.toString() ?? '';
          if (name.isEmpty) return null;

          dynamic schema = item['input_schema'] ?? item['inputSchema'];
          if (schema is String) {
            try {
              schema = jsonDecode(schema);
            } catch (_) {
              schema = null;
            }
          }

          return SkillToolDeclaration(
            name: name,
            description: item['description']?.toString(),
            inputSchema: schema is Map<String, dynamic> ? schema : null,
            tier: item['tier']?.toString() ?? 'capability',
            runtime: item['runtime']?.toString(),
            installCmd:
                item['install']?.toString() ?? item['installCmd']?.toString(),
            registryUrl:
                item['registry']?.toString() ?? item['registryUrl']?.toString(),
            capability: item['capability']?.toString(),
          );
        })
        .whereType<SkillToolDeclaration>()
        .toList();
  }

  McpPlaygroundSkillMetadata? _parseMcpPlaygroundMeta(dynamic meta) {
    if (meta == null) return null;
    if (meta is! Map) return null;
    return McpPlaygroundSkillMetadata(
      chatMode: meta['chat_mode'] == true || meta['chatMode'] == true,
      stopAfterToolCall:
          meta['stop_after_tool_call'] == true ||
          meta['stopAfterToolCall'] == true,
      useCustomLlm:
          meta['use_custom_llm'] == true || meta['useCustomLlm'] == true,
      customLlmConfig: meta['custom_llm_config'] ?? meta['customLlmConfig'],
      mcpInitParams: meta['mcp_init_params'] ?? meta['mcpInitParams'],
      createdAt: meta['created_at'] != null
          ? DateTime.tryParse(meta['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isMultiTurn: meta['is_multi_turn'] == true || meta['isMultiTurn'] == true,
    );
  }

  // ── Helpers for YAML types ──────────────────────────────────────

  static Map<String, dynamic> _toMap(dynamic val) {
    if (val == null) return {};
    if (val is Map) {
      return val.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  static List<Map<String, dynamic>> _toMapList(dynamic val) {
    if (val == null) return [];
    if (val is List) {
      return val
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return [];
  }

  static List<String> _toStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }
}

/// Fallback UUID generator.
class _UuidFallback {
  String v4() {
    final r = List.generate(
      16,
      (_) => (DateTime.now().microsecondsSinceEpoch % 256),
    );
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    return r.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
