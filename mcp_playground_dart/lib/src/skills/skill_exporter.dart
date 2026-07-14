import 'dart:convert';
import '../models/models.dart';
import '../models/skill_manifest.dart';
import '../mcp/local_tools.dart';

/// Converts [SavedPlaygroundSetup] or conversation history into
/// agentskills.io compatible [SkillManifest] and SKILL.md strings.
class SkillExporter {
  static const String _defaultAuthor = 'mcp_playground';
  static const String _defaultVersion = '1.0.0';

  /// Converts a [SavedPlaygroundSetup] with tool metadata to a [SkillManifest].
  SkillManifest fromSetup(
    SavedPlaygroundSetup setup, {
    required List<McpServerConfig> servers,
    required List<McpLocalTool> localTools,
    bool isMultiTurn = false,
  }) {
    final steps = parseSubPromptSteps(setup.initialPrompt);

    final promptSteps = steps.map((s) {
      return SkillPromptStep(
        text: s.text,
        enabledToolNames: s.enabledToolNames,
        stopAfterToolCall: s.stopAfterToolCall,
      );
    }).toList();

    final toolDeclarations = _buildToolDeclarations(
      enabledToolNames: setup.enabledToolNames.toSet(),
      servers: servers,
      localTools: localTools,
    );

    return SkillManifest(
      name: _sanitizeName(setup.name),
      description: setup.description,
      version: _defaultVersion,
      author: _defaultAuthor,
      systemPrompt: setup.systemPrompt,
      promptSteps: promptSteps,
      tools: toolDeclarations,
      mcpPlaygroundMeta: McpPlaygroundSkillMetadata(
        chatMode: setup.chatMode,
        stopAfterToolCall: setup.stopAfterToolCall,
        useCustomLlm: setup.useCustomLlm,
        customLlmConfig: setup.customLlmConfig?.toJson(),
        mcpInitParams: setup.mcpInitParams,
        createdAt: setup.createdAt,
        isMultiTurn: isMultiTurn,
      ),
      isMultiTurn: isMultiTurn,
    );
  }

  /// Converts conversation history to a [SkillManifest].
  ///
  /// Each user→assistant exchange becomes a [SkillPromptStep].
  /// Only user messages with tool context are captured as prompt steps.
  SkillManifest fromConversation({
    required String name,
    required String description,
    required String systemPrompt,
    required List<ChatMessage> conversation,
    required List<McpServerConfig> servers,
    required List<McpLocalTool> localTools,
    required Set<String> enabledToolNames,
  }) {
    final promptSteps = <SkillPromptStep>[];

    for (final msg in conversation) {
      if (msg.role == ChatRole.user && msg.content.trim().isNotEmpty) {
        promptSteps.add(
          SkillPromptStep(
            text: msg.content.trim(),
            // Use global enabled tools for conversation-based export
            enabledToolNames: enabledToolNames.isEmpty
                ? null
                : enabledToolNames.toList(),
          ),
        );
      }
    }

    final toolDeclarations = _buildToolDeclarations(
      enabledToolNames: enabledToolNames,
      servers: servers,
      localTools: localTools,
    );

    return SkillManifest(
      name: _sanitizeName(name),
      description: description,
      version: _defaultVersion,
      author: _defaultAuthor,
      systemPrompt: systemPrompt,
      promptSteps: promptSteps,
      tools: toolDeclarations,
      mcpPlaygroundMeta: McpPlaygroundSkillMetadata(
        createdAt: DateTime.now(),
        isMultiTurn: promptSteps.length > 1,
      ),
      isMultiTurn: promptSteps.length > 1,
    );
  }

  /// Generates a SKILL.md content string from a [SkillManifest].
  String toSkillMd(SkillManifest manifest) {
    final sb = StringBuffer();

    // YAML frontmatter
    sb.writeln('---');
    sb.writeln('name: ${manifest.name}');
    sb.writeln('description: ${_yamlString(manifest.description)}');
    sb.writeln('version: ${manifest.version}');
    if (manifest.author != null && manifest.author!.isNotEmpty) {
      sb.writeln('author: ${manifest.author}');
    }

    // System prompt
    if (manifest.systemPrompt.trim().isNotEmpty) {
      sb.writeln('system_prompt: |');
      for (final line in manifest.systemPrompt.split('\n')) {
        sb.writeln('  $line');
      }
    }

    // Prompt steps
    if (manifest.promptSteps.isNotEmpty) {
      sb.writeln('prompts:');
      for (final step in manifest.promptSteps) {
        sb.writeln('  - text: ${_yamlString(step.text)}');
        if (step.enabledToolNames != null) {
          sb.writeln('    tools: [${step.enabledToolNames!.join(', ')}]');
        }
        if (step.stopAfterToolCall) {
          sb.writeln('    stop_after_tool_call: true');
        }
      }
    }

    // Tools
    if (manifest.tools.isNotEmpty) {
      sb.writeln('tools:');
      for (final tool in manifest.tools) {
        sb.writeln('  - name: ${tool.name}');
        if (tool.description != null && tool.description!.isNotEmpty) {
          sb.writeln('    description: ${_yamlString(tool.description!)}');
        }
        if (tool.inputSchema != null) {
          sb.writeln('    input_schema:');
          final schemaLines = const JsonEncoder.withIndent(
            '      ',
          ).convert(tool.inputSchema!);
          // Indent the schema under input_schema:
          for (final line in schemaLines.split('\n')) {
            sb.writeln('    $line');
          }
        }
        sb.writeln('    tier: ${tool.tier}');
        if (tool.runtime != null) {
          sb.writeln('    runtime: ${tool.runtime}');
        }
        if (tool.installCmd != null) {
          sb.writeln('    install: ${tool.installCmd}');
        }
        if (tool.registryUrl != null) {
          sb.writeln('    registry: ${tool.registryUrl}');
        }
        if (tool.capability != null) {
          sb.writeln('    capability: ${tool.capability}');
        }
      }
    }

    // mcp_playground metadata
    if (manifest.mcpPlaygroundMeta != null) {
      final meta = manifest.mcpPlaygroundMeta!;
      sb.writeln('mcp_playground:');
      sb.writeln('  chat_mode: ${meta.chatMode}');
      sb.writeln('  stop_after_tool_call: ${meta.stopAfterToolCall}');
      sb.writeln('  use_custom_llm: ${meta.useCustomLlm}');
      if (meta.customLlmConfig != null) {
        sb.writeln('  custom_llm_config:');
        final cfgLines = const JsonEncoder.withIndent(
          '    ',
        ).convert(meta.customLlmConfig!);
        for (final line in cfgLines.split('\n')) {
          sb.writeln('  $line');
        }
      }
      if (meta.mcpInitParams != null) {
        sb.writeln('  mcp_init_params:');
        final paramLines = const JsonEncoder.withIndent(
          '    ',
        ).convert(meta.mcpInitParams!);
        for (final line in paramLines.split('\n')) {
          sb.writeln('  $line');
        }
      }
      sb.writeln(
        '  created_at: ${_yamlString(meta.createdAt.toIso8601String())}',
      );
      sb.writeln('  is_multi_turn: ${meta.isMultiTurn}');
    }

    sb.writeln('---');
    sb.writeln();

    // Body markdown
    if (manifest.bodyMarkdown != null && manifest.bodyMarkdown!.isNotEmpty) {
      sb.writeln(manifest.bodyMarkdown);
    } else {
      sb.writeln(toSkillBody(manifest));
    }

    return sb.toString();
  }

  /// Generates the markdown body for a skill.
  String toSkillBody(SkillManifest manifest) {
    final sb = StringBuffer();

    sb.writeln('# ${manifest.name}');
    sb.writeln();

    if (manifest.description.isNotEmpty) {
      sb.writeln(manifest.description);
      sb.writeln();
    }

    if (manifest.isMultiTurn && manifest.promptSteps.isNotEmpty) {
      sb.writeln('## Workflow Steps');
      sb.writeln();
      for (var i = 0; i < manifest.promptSteps.length; i++) {
        final step = manifest.promptSteps[i];
        sb.writeln('### Step ${i + 1}');
        sb.writeln(step.text);
        if (step.enabledToolNames != null &&
            step.enabledToolNames!.isNotEmpty) {
          sb.writeln();
          sb.writeln('**Tools**: ${step.enabledToolNames!.join(', ')}');
        }
        sb.writeln();
      }
    }

    return sb.toString();
  }

  // ── Helpers ──────────────────────────────────────────────────────

  List<SkillToolDeclaration> _buildToolDeclarations({
    required Set<String> enabledToolNames,
    required List<McpServerConfig> servers,
    required List<McpLocalTool> localTools,
  }) {
    final declarations = <SkillToolDeclaration>[];

    // Dart-native local tools → capability tier
    for (final tool in localTools) {
      if (enabledToolNames.isEmpty || enabledToolNames.contains(tool.name)) {
        final capability = _mapToCapability(tool.name);
        declarations.add(
          SkillToolDeclaration(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
            tier: 'capability',
            runtime: 'dart',
            capability: capability,
          ),
        );
      }
    }

    // MCP servers → local or external tier
    for (final server in servers) {
      if (!server.enabled) continue;
      // For local servers, we declare based on type
      if (server.isLocal) {
        declarations.add(
          SkillToolDeclaration(
            name: server.name,
            description: server.description ?? server.name,
            tier: 'local',
            runtime: server.localType ?? 'nodejs',
            installCmd: _buildInstallCmd(server),
          ),
        );
      } else {
        declarations.add(
          SkillToolDeclaration(
            name: server.name,
            description: server.description ?? server.url,
            tier: 'external',
            registryUrl: server.url.isNotEmpty ? server.url : null,
          ),
        );
      }
    }

    return declarations;
  }

  String? _buildInstallCmd(McpServerConfig server) {
    final method = server.localInstallMethod;
    final package = server.localPackage;
    final command = server.localCommand ?? server.customLaunchCommand;

    if (command != null && command.isNotEmpty) return command;
    if (package == null || package.isEmpty) return null;

    switch (method) {
      case 'pip':
        return 'pip install $package';
      case 'uvx':
        return 'uvx $package';
      case 'npm':
        return 'npm install $package';
      case 'npx':
        return 'npx $package';
      default:
        if (server.localType == 'python') return 'pip install $package';
        if (server.localType == 'nodejs') return 'npx $package';
        return null;
    }
  }

  /// Maps a tool name to a generic capability identifier.
  String _mapToCapability(String toolName) {
    // Weather tools
    if (toolName == 'get_current_weather' ||
        toolName == 'get_hourly_forecast' ||
        toolName == 'get_daily_forecast' ||
        toolName == 'geocode_weather_city') {
      return 'weather_retrieval';
    }
    // Chart tools
    if (toolName == 'create_chart_png' || toolName == 'chart2png') {
      return 'chart_generation';
    }
    // SSH tools
    if (toolName.startsWith('ssh_') || toolName.startsWith('sftp_')) {
      return 'ssh_execution';
    }
    // Fallback: use tool name as capability
    return toolName;
  }

  /// Sanitizes a name for use as a skill identifier (lowercase, hyphens).
  String _sanitizeName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Wraps a string for YAML single-line or multi-line output.
  String _yamlString(String value) {
    // If the string contains newlines, use block scalar
    if (value.contains('\n')) {
      return value;
    }
    // If it contains special YAML chars, quote it
    if (value.contains(':') ||
        value.contains('#') ||
        value.contains('{') ||
        value.contains('}') ||
        value.contains('[') ||
        value.contains(']') ||
        value.contains('&') ||
        value.contains('*') ||
        value.contains('!') ||
        value.contains('|') ||
        value.contains('>') ||
        value.contains('%') ||
        value.contains('@') ||
        value.contains('`')) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }
}
