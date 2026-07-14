import 'dart:convert';
import 'dart:typed_data';

/// Represents a parsed agentskills.io compatible SKILL.md manifest.
class SkillManifest {
  final String name;
  final String description;
  final String version;
  final String? author;

  /// System prompt / instructions for the assistant.
  final String systemPrompt;

  /// Multi-step prompts with per-step tool bindings.
  final List<SkillPromptStep> promptSteps;

  /// Tools declared with runtime/install info for portability.
  final List<SkillToolDeclaration> tools;

  /// mcp_playground custom metadata.
  final McpPlaygroundSkillMetadata? mcpPlaygroundMeta;

  /// Whether this skill represents a multi-turn workflow.
  final bool isMultiTurn;

  /// Raw markdown body content after the YAML frontmatter.
  final String? bodyMarkdown;

  /// Extra files bundled in the ZIP (filename → bytes).
  final Map<String, Uint8List> extraFiles;

  const SkillManifest({
    required this.name,
    this.description = '',
    this.version = '1.0.0',
    this.author,
    this.systemPrompt = '',
    this.promptSteps = const [],
    this.tools = const [],
    this.mcpPlaygroundMeta,
    this.isMultiTurn = false,
    this.bodyMarkdown,
    this.extraFiles = const {},
  });

  SkillManifest copyWith({
    String? name,
    String? description,
    String? version,
    String? author,
    String? systemPrompt,
    List<SkillPromptStep>? promptSteps,
    List<SkillToolDeclaration>? tools,
    McpPlaygroundSkillMetadata? mcpPlaygroundMeta,
    bool? isMultiTurn,
    String? bodyMarkdown,
    Map<String, Uint8List>? extraFiles,
  }) {
    return SkillManifest(
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      promptSteps: promptSteps ?? this.promptSteps,
      tools: tools ?? this.tools,
      mcpPlaygroundMeta: mcpPlaygroundMeta ?? this.mcpPlaygroundMeta,
      isMultiTurn: isMultiTurn ?? this.isMultiTurn,
      bodyMarkdown: bodyMarkdown ?? this.bodyMarkdown,
      extraFiles: extraFiles ?? this.extraFiles,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'version': version,
    if (author != null) 'author': author,
    'systemPrompt': systemPrompt,
    'promptSteps': promptSteps.map((s) => s.toJson()).toList(),
    'tools': tools.map((t) => t.toJson()).toList(),
    if (mcpPlaygroundMeta != null)
      'mcpPlaygroundMeta': mcpPlaygroundMeta!.toJson(),
    'isMultiTurn': isMultiTurn,
    if (bodyMarkdown != null) 'bodyMarkdown': bodyMarkdown,
  };

  factory SkillManifest.fromJson(Map<String, dynamic> json) => SkillManifest(
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '1.0.0',
    author: json['author'] as String?,
    systemPrompt: json['systemPrompt'] as String? ?? '',
    promptSteps:
        (json['promptSteps'] as List<dynamic>?)
            ?.map((e) => SkillPromptStep.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    tools:
        (json['tools'] as List<dynamic>?)
            ?.map(
              (e) => SkillToolDeclaration.fromJson(e as Map<String, dynamic>),
            )
            .toList() ??
        [],
    mcpPlaygroundMeta: json['mcpPlaygroundMeta'] != null
        ? McpPlaygroundSkillMetadata.fromJson(
            json['mcpPlaygroundMeta'] as Map<String, dynamic>,
          )
        : null,
    isMultiTurn: json['isMultiTurn'] as bool? ?? false,
    bodyMarkdown: json['bodyMarkdown'] as String?,
  );
}

/// A single step in a multi-prompt skill workflow.
class SkillPromptStep {
  /// The prompt text for this step.
  final String text;

  /// Tool names enabled for this step. `null` means all tools.
  final List<String>? enabledToolNames;

  /// Whether to stop the agent loop after the first tool call.
  final bool stopAfterToolCall;

  const SkillPromptStep({
    required this.text,
    this.enabledToolNames,
    this.stopAfterToolCall = false,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    if (enabledToolNames != null) 'enabledToolNames': enabledToolNames,
    'stopAfterToolCall': stopAfterToolCall,
  };

  factory SkillPromptStep.fromJson(Map<String, dynamic> json) =>
      SkillPromptStep(
        text: json['text'] as String? ?? '',
        enabledToolNames: (json['enabledToolNames'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        stopAfterToolCall: json['stopAfterToolCall'] as bool? ?? false,
      );
}

/// Declaration of a tool in the SKILL.md manifest.
///
/// Supports three portability tiers:
/// - `external`: Remote MCP server referenced by registry URL.
/// - `local`: Runtime-specific install command (pip/npm/npx/uvx).
/// - `capability`: Generic capability name for host substitution.
class SkillToolDeclaration {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  /// Portability tier: `external`, `local`, or `capability`.
  final String tier;

  /// Runtime identifier: `python`, `nodejs`, or `dart`.
  final String? runtime;

  /// Install command: `pip install ...`, `npm install ...`, `npx ...`, `uvx ...`.
  final String? installCmd;

  /// Registry URL for external MCP servers.
  final String? registryUrl;

  /// Generic capability name (e.g. `weather_retrieval`, `chart_generation`).
  final String? capability;

  const SkillToolDeclaration({
    required this.name,
    this.description,
    this.inputSchema,
    this.tier = 'capability',
    this.runtime,
    this.installCmd,
    this.registryUrl,
    this.capability,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (inputSchema != null)
      'inputSchema': const JsonEncoder().convert(inputSchema),
    'tier': tier,
    if (runtime != null) 'runtime': runtime,
    if (installCmd != null) 'installCmd': installCmd,
    if (registryUrl != null) 'registryUrl': registryUrl,
    if (capability != null) 'capability': capability,
  };

  factory SkillToolDeclaration.fromJson(Map<String, dynamic> json) =>
      SkillToolDeclaration(
        name: json['name'] as String,
        description: json['description'] as String?,
        inputSchema: json['inputSchema'] != null
            ? (json['inputSchema'] is String
                  ? jsonDecode(json['inputSchema'] as String)
                        as Map<String, dynamic>
                  : json['inputSchema'] as Map<String, dynamic>)
            : null,
        tier: json['tier'] as String? ?? 'capability',
        runtime: json['runtime'] as String?,
        installCmd: json['installCmd'] as String?,
        registryUrl: json['registryUrl'] as String?,
        capability: json['capability'] as String?,
      );
}

/// mcp_playground-specific metadata embedded in SKILL.md.
class McpPlaygroundSkillMetadata {
  final bool chatMode;
  final bool stopAfterToolCall;
  final bool useCustomLlm;
  final Map<String, dynamic>? customLlmConfig;
  final Map<String, dynamic>? mcpInitParams;
  final DateTime createdAt;
  final bool isMultiTurn;

  const McpPlaygroundSkillMetadata({
    this.chatMode = false,
    this.stopAfterToolCall = false,
    this.useCustomLlm = false,
    this.customLlmConfig,
    this.mcpInitParams,
    required this.createdAt,
    this.isMultiTurn = false,
  });

  Map<String, dynamic> toJson() => {
    'chatMode': chatMode,
    'stopAfterToolCall': stopAfterToolCall,
    'useCustomLlm': useCustomLlm,
    if (customLlmConfig != null) 'customLlmConfig': customLlmConfig,
    if (mcpInitParams != null) 'mcpInitParams': mcpInitParams,
    'createdAt': createdAt.toIso8601String(),
    'isMultiTurn': isMultiTurn,
  };

  factory McpPlaygroundSkillMetadata.fromJson(Map<String, dynamic> json) =>
      McpPlaygroundSkillMetadata(
        chatMode: json['chatMode'] as bool? ?? false,
        stopAfterToolCall: json['stopAfterToolCall'] as bool? ?? false,
        useCustomLlm: json['useCustomLlm'] as bool? ?? false,
        customLlmConfig: json['customLlmConfig'] as Map<String, dynamic>?,
        mcpInitParams: json['mcpInitParams'] as Map<String, dynamic>?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        isMultiTurn: json['isMultiTurn'] as bool? ?? false,
      );
}
