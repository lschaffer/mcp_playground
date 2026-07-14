import 'dart:convert';
import '../models/models.dart';
import '../models/skill_manifest.dart';

/// Parses agentskills.io compatible SKILL.md content into [SkillManifest]
/// and converts it back to [SavedPlaygroundSetup].
class SkillImporter {
  /// Parses SKILL.md content into a [SkillManifest].
  SkillManifest parseSkillMd(String content) {
    final lines = content.split('\n');

    // Find YAML frontmatter boundaries
    int? yamlStart;
    int? yamlEnd;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line == '---') {
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

    final yamlLines = lines.sublist(yamlStart + 1, yamlEnd);
    final parsed = _parseYamlFrontmatter(yamlLines);

    // Extract body markdown after frontmatter
    final bodyLines = yamlEnd + 1 < lines.length
        ? lines.sublist(yamlEnd + 1)
        : <String>[];
    final bodyMarkdown = bodyLines.join('\n').trim().isEmpty
        ? null
        : bodyLines.join('\n').trim();

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

  /// Converts a [SkillManifest] to [SavedPlaygroundSetup].
  /// Filters tools to only those available in [availableToolNames].
  SavedPlaygroundSetup toSetup(
    SkillManifest manifest, {
    required Set<String> availableToolNames,
  }) {
    // Build the sub-prompt text from prompt steps
    final subPromptSteps = manifest.promptSteps.map((s) {
      return SubPromptStep(
        text: s.text,
        enabledToolNames: s.enabledToolNames,
        stopAfterToolCall: s.stopAfterToolCall,
      );
    }).toList();

    final initialPrompt = serializeSubPromptSteps(subPromptSteps);

    // Collect enabled tool names from all steps, filtered by availability
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

    // Also include tool names from tool declarations that match
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

  /// Returns tool names from the manifest that are not available locally.
  List<String> getUnresolvableTools(
    SkillManifest manifest,
    Set<String> availableToolNames,
  ) {
    if (availableToolNames.isEmpty) return [];
    final missing = <String>[];
    for (final tool in manifest.tools) {
      if (!availableToolNames.contains(tool.name)) {
        missing.add(tool.name);
      }
    }
    for (final step in manifest.promptSteps) {
      if (step.enabledToolNames != null) {
        for (final t in step.enabledToolNames!) {
          if (!availableToolNames.contains(t)) {
            missing.add(t);
          }
        }
      }
    }
    return missing.toSet().toList();
  }

  // ── YAML Frontmatter Parser ─────────────────────────────────────
  // A minimal YAML parser sufficient for SKILL.md frontmatter.
  // Handles: scalars, lists, nested mappings, block scalars (|).

  Map<String, dynamic> _parseYamlFrontmatter(List<String> lines) {
    final result = <String, dynamic>{};

    // Pre-process: join block scalar continuations
    final joined = _joinBlockScalars(lines);
    final joinedLines = joined.split('\n');

    int i = 0;
    while (i < joinedLines.length) {
      final line = joinedLines[i];
      if (line.trim().isEmpty || line.trim().startsWith('#')) {
        i++;
        continue;
      }

      final indent = _indentOf(line);
      if (indent > 0) {
        // This is a nested value belonging to the previous key
        // Skip — handled by block scalars join
        i++;
        continue;
      }

      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) {
        i++;
        continue;
      }

      final key = line.substring(0, colonIdx).trim();
      final afterColon = line.substring(colonIdx + 1);

      if (afterColon.trim().isEmpty) {
        // Value could be a block scalar, nested mapping, or list on next lines
        i++;
        if (i < joinedLines.length) {
          final nextLine = joinedLines[i];
          final nextTrim = nextLine.trim();

          if (nextTrim.startsWith('- ')) {
            // List
            final list = <dynamic>[];
            while (i < joinedLines.length &&
                (joinedLines[i].trim().startsWith('- ') ||
                    (joinedLines[i].trim().isNotEmpty &&
                        _indentOf(joinedLines[i]) >= 2))) {
              final li = joinedLines[i];
              if (li.trim().startsWith('- ')) {
                final itemStr = li.trim().substring(2);
                // Check if this list item contains nested sub-items
                final subItems = <String>[];
                i++;
                while (i < joinedLines.length &&
                    joinedLines[i].trim().startsWith('- ') == false &&
                    _indentOf(joinedLines[i]) >= 4) {
                  subItems.add(joinedLines[i].trim());
                  i++;
                }
                if (itemStr.contains(':') && subItems.isNotEmpty) {
                  // It's a mapping item
                  list.add(_parseListItemWithSub(itemStr, subItems));
                } else if (itemStr.contains(':')) {
                  list.add(_parseInlineMapping(itemStr));
                } else {
                  // Simple string or we check for nested keys
                  if (subItems.isNotEmpty &&
                      subItems.any((s) => s.contains(':'))) {
                    list.add(_parseListItemWithSub(itemStr, subItems));
                  } else {
                    final cleaned = itemStr.replaceAll(RegExp(r'^"|"$'), '');
                    list.add(cleaned);
                  }
                }
              } else {
                i++;
              }
            }
            result[key] = list;
          } else if (nextTrim == '|') {
            // Block scalar already handled by _joinBlockScalars
            i++;
          } else if (_indentOf(nextLine) >= 2) {
            // Nested mapping
            final nestedLines = <String>[];
            while (i < joinedLines.length &&
                (_indentOf(joinedLines[i]) >= 2 ||
                    joinedLines[i].trim().isEmpty)) {
              nestedLines.add(joinedLines[i]);
              i++;
            }
            result[key] = _parseYamlFrontmatter(nestedLines);
          }
        }
      } else {
        // Inline value
        final value = afterColon.trim();
        result[key] = _parseScalar(value);
        i++;
      }
    }

    return result;
  }

  /// Joins block scalar (|) continuations into single values.
  String _joinBlockScalars(List<String> lines) {
    final result = <String>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      result.add(line);
      if (line.trimRight().endsWith('|')) {
        // Block scalar — collect indented continuation lines
        final baseIndent = _indentOf(line) + 2;
        i++;
        final buffer = StringBuffer();
        while (i < lines.length && _indentOf(lines[i]) >= baseIndent) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(lines[i].substring(baseIndent));
          i++;
        }
        if (buffer.isNotEmpty) {
          result.add(' ' * baseIndent + buffer.toString());
        }
        continue;
      }
      i++;
    }
    return result.join('\n');
  }

  Map<String, dynamic> _parseListItemWithSub(
    String itemStr,
    List<String> subItems,
  ) {
    final result = <String, dynamic>{};
    // Parse the initial item string
    final colonIdx = itemStr.indexOf(':');
    if (colonIdx != -1) {
      final k = itemStr.substring(0, colonIdx).trim();
      final v = itemStr.substring(colonIdx + 1).trim();
      if (v.isNotEmpty) {
        result[k] = _parseScalar(v);
      }
    }
    // Parse sub-items
    final joined = _joinBlockScalars(subItems);
    for (final subLine in joined.split('\n')) {
      final trimmed = subLine.trim();
      final cIdx = trimmed.indexOf(':');
      if (cIdx != -1) {
        final k = trimmed.substring(0, cIdx).trim();
        final v = trimmed.substring(cIdx + 1).trim();
        if (v == '|') continue;
        result[k] = _parseScalar(v);
      }
    }
    return result;
  }

  Map<String, dynamic> _parseInlineMapping(String str) {
    final result = <String, dynamic>{};
    final colonIdx = str.indexOf(':');
    if (colonIdx != -1) {
      final k = str.substring(0, colonIdx).trim();
      final v = str.substring(colonIdx + 1).trim();
      if (v.isNotEmpty) {
        result[k] = _parseScalar(v);
      }
    }
    return result;
  }

  dynamic _parseScalar(String value) {
    if (value.isEmpty) return '';
    if (value == 'true') return true;
    if (value == 'false') return false;
    if (value == 'null' || value == '~') return null;

    // JSON array: [a, b, c]
    if (value.startsWith('[') && value.endsWith(']')) {
      final inner = value.substring(1, value.length - 1);
      return inner.split(',').map((s) => _parseScalar(s.trim())).toList();
    }

    // Quoted string
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }

  int _indentOf(String line) {
    var count = 0;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        count++;
      } else if (line[i] == '\t') {
        count += 2;
      } else {
        break;
      }
    }
    return count;
  }

  // ── Sub-parsers ─────────────────────────────────────────────────

  List<SkillPromptStep> _parsePromptSteps(dynamic prompts) {
    if (prompts == null) return [];
    if (prompts is! List) return [];

    return prompts.map((item) {
      if (item is Map) {
        final tools = item['tools'];
        List<String>? toolList;
        if (tools is List) {
          toolList = tools.map((t) => t.toString()).toList();
        }
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

          // Parse input_schema which may be nested YAML
          dynamic schema = item['input_schema'] ?? item['inputSchema'];
          if (schema is Map) {
            // Already parsed
          } else if (schema is String) {
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
}

/// Fallback UUID generator (avoids importing uuid package directly in dart core).
class _UuidFallback {
  String v4() {
    final r = List.generate(
      16,
      (_) => (DateTime.now().microsecondsSinceEpoch % 256),
    );
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    return r
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .replaceRange(12, 13, '4')
        .replaceRange(16, 17, '8');
  }
}
