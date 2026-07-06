import 'dart:typed_data';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════════
// 1. LLM Configuration Models
// ═══════════════════════════════════════════════════════════════

enum LlmProvider {
  none,
  openai,
  claude,
  gemini,
  ollama,
  openaiCompatible,
  mistral,
  embedded;

  String get configKey {
    switch (this) {
      case LlmProvider.none:
        return 'none';
      case LlmProvider.openai:
        return 'openai';
      case LlmProvider.claude:
        return 'claude';
      case LlmProvider.gemini:
        return 'gemini';
      case LlmProvider.ollama:
        return 'ollama';
      case LlmProvider.openaiCompatible:
        return 'openai_compatible';
      case LlmProvider.mistral:
        return 'mistral';
      case LlmProvider.embedded:
        return 'embedded';
    }
  }

  static LlmProvider fromConfigKey(String? key) {
    if (key == null) return LlmProvider.none;
    final clean = key.trim().toLowerCase();
    return LlmProvider.values.firstWhere(
      (v) => v.configKey == clean,
      orElse: () => LlmProvider.none,
    );
  }

  String get displayName {
    switch (this) {
      case LlmProvider.none:
        return 'None';
      case LlmProvider.openai:
        return 'OpenAI';
      case LlmProvider.claude:
        return 'Anthropic Claude';
      case LlmProvider.gemini:
        return 'Google Gemini';
      case LlmProvider.ollama:
        return 'Ollama (Local)';
      case LlmProvider.openaiCompatible:
        return 'Custom OpenAI Compatible';
      case LlmProvider.mistral:
        return 'Mistral AI';
      case LlmProvider.embedded:
        return 'Embedded (on-device)';
    }
  }
}

class LlmConfig {
  final LlmProvider provider;
  final String model;
  final String apiKey;
  final String baseUrl;

  // Hyperparameters
  final double temperature;
  final int maxTokens;
  final double? topP;
  final int? topK;
  final double? repeatPenalty;
  final int? seed;
  final int maxToolOutputSize;
  final int tokenWarningThreshold;

  // Flags
  final bool isSlm;
  final bool isMultiModal;
  final bool thinking;
  final bool useNativeToolCall;
  final bool useSafeToolCall;
  final bool useStreaming;

  const LlmConfig({
    required this.provider,
    required this.model,
    required this.apiKey,
    this.baseUrl = '',
    this.temperature = 0.2,
    this.maxTokens = 0,
    this.topP,
    this.topK,
    this.repeatPenalty,
    this.seed,
    this.maxToolOutputSize = 2560000,
    this.tokenWarningThreshold = 1500000,
    this.isSlm = false,
    this.isMultiModal = true,
    this.thinking = false,
    this.useNativeToolCall = true,
    this.useSafeToolCall = false,
    this.useStreaming = false,
  });

  bool get isConfigured {
    if (provider == LlmProvider.none || model.trim().isEmpty) return false;
    if (provider == LlmProvider.embedded) return true;
    if (provider == LlmProvider.ollama ||
        provider == LlmProvider.openaiCompatible) {
      return baseUrl.trim().isNotEmpty;
    }
    return apiKey.trim().isNotEmpty;
  }

  LlmConfig copyWith({
    LlmProvider? provider,
    String? model,
    String? apiKey,
    String? baseUrl,
    double? temperature,
    int? maxTokens,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? seed,
    int? maxToolOutputSize,
    int? tokenWarningThreshold,
    bool? isSlm,
    bool? isMultiModal,
    bool? thinking,
    bool? useNativeToolCall,
    bool? useSafeToolCall,
    bool? useStreaming,
  }) {
    return LlmConfig(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      seed: seed ?? this.seed,
      maxToolOutputSize: maxToolOutputSize ?? this.maxToolOutputSize,
      tokenWarningThreshold:
          tokenWarningThreshold ?? this.tokenWarningThreshold,
      isSlm: isSlm ?? this.isSlm,
      isMultiModal: isMultiModal ?? this.isMultiModal,
      thinking: thinking ?? this.thinking,
      useNativeToolCall: useNativeToolCall ?? this.useNativeToolCall,
      useSafeToolCall: useSafeToolCall ?? this.useSafeToolCall,
      useStreaming: useStreaming ?? this.useStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.configKey,
    'model': model,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'temperature': temperature,
    'maxTokens': maxTokens,
    if (topP != null) 'topP': topP,
    if (topK != null) 'topK': topK,
    if (repeatPenalty != null) 'repeatPenalty': repeatPenalty,
    if (seed != null) 'seed': seed,
    'maxToolOutputSize': maxToolOutputSize,
    'tokenWarningThreshold': tokenWarningThreshold,
    'isSlm': isSlm,
    'isMultiModal': isMultiModal,
    'thinking': thinking,
    'useNativeToolCall': useNativeToolCall,
    'useSafeToolCall': useSafeToolCall,
    'useStreaming': useStreaming,
  };

  factory LlmConfig.fromJson(Map<String, dynamic> json) {
    return LlmConfig(
      provider: LlmProvider.fromConfigKey(json['provider'] as String?),
      model: json['model'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      maxTokens: json['maxTokens'] as int? ?? 0,
      topP: (json['topP'] as num?)?.toDouble(),
      topK: json['topK'] as int?,
      repeatPenalty: (json['repeatPenalty'] as num?)?.toDouble(),
      seed: json['seed'] as int?,
      maxToolOutputSize: json['maxToolOutputSize'] as int? ?? 2560000,
      tokenWarningThreshold: json['tokenWarningThreshold'] as int? ?? 1500000,
      isSlm: json['isSlm'] as bool? ?? false,
      isMultiModal: json['isMultiModal'] as bool? ?? true,
      thinking: json['thinking'] as bool? ?? false,
      useNativeToolCall: json['useNativeToolCall'] as bool? ?? true,
      useSafeToolCall: json['useSafeToolCall'] as bool? ?? false,
      useStreaming: json['useStreaming'] as bool? ?? false,
    );
  }
}

class McpServerConfig {
  final String id;
  final String name;
  final String url;
  final String mcpEndpoint;
  final String? apiKey;
  final String? apiPassword;
  final bool enabled;
  final bool? isOnline;
  final String? description;
  final bool isLocal;
  final String? localType;
  final String? localInstallMethod;
  final String? localPackage;
  final String? localCommand;
  final String? customLaunchCommand;
  final Map<String, String>? localEnvVars;
  final bool isInstalled;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.mcpEndpoint = '/mcp',
    this.apiKey,
    this.apiPassword,
    this.enabled = true,
    this.isOnline,
    this.description,
    this.isLocal = false,
    this.localType,
    this.localInstallMethod,
    this.localPackage,
    this.localCommand,
    this.customLaunchCommand,
    this.localEnvVars,
    this.isInstalled = false,
  });

  McpServerConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? mcpEndpoint,
    String? apiKey,
    String? apiPassword,
    bool? enabled,
    bool? isOnline,
    String? description,
    bool? isLocal,
    String? localType,
    String? localInstallMethod,
    String? localPackage,
    String? localCommand,
    String? customLaunchCommand,
    Map<String, String>? localEnvVars,
    bool? isInstalled,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      mcpEndpoint: mcpEndpoint ?? this.mcpEndpoint,
      apiKey: apiKey ?? this.apiKey,
      apiPassword: apiPassword ?? this.apiPassword,
      enabled: enabled ?? this.enabled,
      isOnline: isOnline ?? this.isOnline,
      description: description ?? this.description,
      isLocal: isLocal ?? this.isLocal,
      localType: localType ?? this.localType,
      localInstallMethod: localInstallMethod ?? this.localInstallMethod,
      localPackage: localPackage ?? this.localPackage,
      localCommand: localCommand ?? this.localCommand,
      customLaunchCommand: customLaunchCommand ?? this.customLaunchCommand,
      localEnvVars: localEnvVars ?? this.localEnvVars,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'mcpEndpoint': mcpEndpoint,
    if (apiKey != null) 'apiKey': apiKey,
    if (apiPassword != null) 'apiPassword': apiPassword,
    'enabled': enabled,
    if (isOnline != null) 'isOnline': isOnline,
    if (description != null) 'description': description,
    'isLocal': isLocal,
    if (localType != null) 'localType': localType,
    if (localInstallMethod != null) 'localInstallMethod': localInstallMethod,
    if (localPackage != null) 'localPackage': localPackage,
    if (localCommand != null) 'localCommand': localCommand,
    if (customLaunchCommand != null) 'customLaunchCommand': customLaunchCommand,
    if (localEnvVars != null) 'localEnvVars': localEnvVars,
    'isInstalled': isInstalled,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'unnamed_mcp',
      url: json['url'] as String? ?? '',
      mcpEndpoint: json['mcpEndpoint'] as String? ?? '/mcp',
      apiKey: json['apiKey'] as String?,
      apiPassword: json['apiPassword'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      isOnline: json['isOnline'] as bool?,
      description: json['description'] as String?,
      isLocal: json['isLocal'] as bool? ?? false,
      localType: json['localType'] as String?,
      localInstallMethod: json['localInstallMethod'] as String?,
      localPackage: json['localPackage'] as String?,
      localCommand: json['localCommand'] as String?,
      customLaunchCommand: json['customLaunchCommand'] as String?,
      localEnvVars: json['localEnvVars'] != null
          ? Map<String, String>.from(json['localEnvVars'] as Map)
          : null,
      isInstalled: json['isInstalled'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. Core MCP Message Formats (JSON-RPC 2.0)
// ═══════════════════════════════════════════════════════════════

abstract class MCPMessage {
  final String jsonrpc;

  const MCPMessage({this.jsonrpc = '2.0'});

  factory MCPMessage.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('id')) {
      if (json.containsKey('method')) {
        return MCPRequest.fromJson(json);
      } else {
        return MCPResponse.fromJson(json);
      }
    } else if (json.containsKey('method')) {
      return MCPNotification.fromJson(json);
    } else {
      throw ArgumentError('Invalid MCP message format');
    }
  }

  Map<String, dynamic> toJson();
}

class MCPRequest extends MCPMessage {
  final String id;
  final String method;
  final Map<String, dynamic>? params;

  const MCPRequest({
    required this.id,
    required this.method,
    this.params,
    super.jsonrpc,
  });

  factory MCPRequest.fromJson(Map<String, dynamic> json) {
    return MCPRequest(
      id: json['id'].toString(),
      method: json['method'] as String,
      params: json['params'] as Map<String, dynamic>?,
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
  }
}

class MCPResponse extends MCPMessage {
  final String id;
  final dynamic result;
  final MCPError? error;

  const MCPResponse({required this.id, this.result, this.error, super.jsonrpc});

  factory MCPResponse.fromJson(Map<String, dynamic> json) {
    return MCPResponse(
      id: json['id'].toString(),
      result: json['result'],
      error: json['error'] != null ? MCPError.fromJson(json['error']) : null,
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      if (result != null) 'result': result,
      if (error != null) 'error': error!.toJson(),
    };
  }
}

class MCPNotification extends MCPMessage {
  final String method;
  final Map<String, dynamic>? params;

  const MCPNotification({required this.method, this.params, super.jsonrpc});

  factory MCPNotification.fromJson(Map<String, dynamic> json) {
    return MCPNotification(
      method: json['method'] as String,
      params: json['params'] as Map<String, dynamic>?,
      jsonrpc: json['jsonrpc'] as String? ?? '2.0',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'method': method,
      if (params != null) 'params': params,
    };
  }
}

class MCPError {
  final int code;
  final String message;
  final dynamic data;

  const MCPError({required this.code, required this.message, this.data});

  factory MCPError.fromJson(Map<String, dynamic> json) {
    return MCPError(
      code: json['code'] as int,
      message: json['message'] as String,
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'code': code, 'message': message, if (data != null) 'data': data};
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. MCP Capabilities & Tool Execution Schema
// ═══════════════════════════════════════════════════════════════

class MCPTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const MCPTool({required this.name, this.description, this.inputSchema});

  factory MCPTool.fromJson(Map<String, dynamic> json) {
    return MCPTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (inputSchema != null) 'inputSchema': inputSchema,
    };
  }
}

class MCPContent {
  final String type;
  final String? text;
  final String? data;
  final String? mimeType;

  const MCPContent({required this.type, this.text, this.data, this.mimeType});

  factory MCPContent.fromJson(Map<String, dynamic> json) {
    return MCPContent(
      type: json['type'] as String,
      text: json['text'] as String?,
      data: json['data'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (text != null) 'text': text,
      if (data != null) 'data': data,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }
}

class MCPToolResult {
  final List<MCPContent> content;
  final bool isError;

  const MCPToolResult({required this.content, this.isError = false});

  factory MCPToolResult.fromJson(Map<String, dynamic> json) {
    final contentList = json['content'] as List? ?? [];
    return MCPToolResult(
      content: contentList.map((item) => MCPContent.fromJson(item)).toList(),
      isError: json['isError'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content.map((item) => item.toJson()).toList(),
      'isError': isError,
    };
  }
}

class MCPResource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  const MCPResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  factory MCPResource.fromJson(Map<String, dynamic> json) {
    return MCPResource(
      uri: json['uri'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'name': name,
      if (description != null) 'description': description,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. Chat Message Models
// ═══════════════════════════════════════════════════════════════

enum ChatRole { user, assistant, system, tool }

enum MessageType { text, image, file, toolCall, toolResponse, log }

class MessageAttachment {
  final String id;
  final String name;
  final String path;
  final Uint8List? bytes;
  final String mimeType;
  final int? size;

  const MessageAttachment({
    required this.id,
    required this.name,
    required this.path,
    this.bytes,
    required this.mimeType,
    this.size,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'mimeType': mimeType,
    if (size != null) 'size': size,
  };

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    return MessageAttachment(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      size: json['size'] as int?,
    );
  }
}

class ChatMessage {
  final String id;
  final String content;
  final ChatRole role;
  final DateTime timestamp;
  final MessageType type;

  // Tool info
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final MCPToolResult? toolResult;

  // Attachments
  final List<MessageAttachment>? attachments;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.timestamp,
    this.type = MessageType.text,
    this.toolName,
    this.toolArguments,
    this.toolResult,
    this.attachments,
  });

  ChatMessage copyWith({
    String? id,
    String? content,
    ChatRole? role,
    DateTime? timestamp,
    MessageType? type,
    String? toolName,
    Map<String, dynamic>? toolArguments,
    MCPToolResult? toolResult,
    List<MessageAttachment>? attachments,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      toolName: toolName ?? this.toolName,
      toolArguments: toolArguments ?? this.toolArguments,
      toolResult: toolResult ?? this.toolResult,
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'role': role.name,
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
    if (toolName != null) 'toolName': toolName,
    if (toolArguments != null) 'toolArguments': toolArguments,
    if (toolResult != null) 'toolResult': toolResult!.toJson(),
    if (attachments != null)
      'attachments': attachments!.map((a) => a.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      role: ChatRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => ChatRole.user,
      ),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      type: MessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => MessageType.text,
      ),
      toolName: json['toolName'] as String?,
      toolArguments: json['toolArguments'] as Map<String, dynamic>?,
      toolResult: json['toolResult'] != null
          ? MCPToolResult.fromJson(json['toolResult'])
          : null,
      attachments: json['attachments'] != null
          ? (json['attachments'] as List)
                .map((a) => MessageAttachment.fromJson(a))
                .toList()
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. Sub-Prompt Step
// ═══════════════════════════════════════════════════════════════

final RegExp subPromptSepRegex = RegExp(
  r'^\+\+#\+\+(?:\[N(\d)\]|\[NT:([^\]]*)\])?(\[SATC\])?$',
  multiLine: true,
);

class SubPromptStep {
  final String text;
  final List<String>? enabledToolNames;
  final bool stopAfterToolCall;

  const SubPromptStep({
    required this.text,
    this.enabledToolNames,
    this.stopAfterToolCall = false,
  });

  bool get isAllTools => enabledToolNames == null;
  bool get isNoTools => enabledToolNames != null && enabledToolNames!.isEmpty;

  static List<String>? _fromLegacyDigit(String? d) {
    if (d == '0') return const [];
    return null;
  }

  factory SubPromptStep.fromLegacyDigit(
    String text,
    String? digit, {
    bool stopAfterToolCall = false,
  }) {
    return SubPromptStep(
      text: text,
      enabledToolNames: _fromLegacyDigit(digit),
      stopAfterToolCall: stopAfterToolCall,
    );
  }

  factory SubPromptStep.fromNamedTools(
    String text,
    String ntContent, {
    bool stopAfterToolCall = false,
  }) {
    if (ntContent.isEmpty) {
      return SubPromptStep(
        text: text,
        enabledToolNames: const [],
        stopAfterToolCall: stopAfterToolCall,
      );
    }
    return SubPromptStep(
      text: text,
      enabledToolNames: ntContent
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      stopAfterToolCall: stopAfterToolCall,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'enabledToolNames': enabledToolNames,
    'stopAfterToolCall': stopAfterToolCall,
  };

  factory SubPromptStep.fromJson(Map<String, dynamic> json) {
    return SubPromptStep(
      text: json['text'] as String? ?? '',
      enabledToolNames: (json['enabledToolNames'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      stopAfterToolCall: json['stopAfterToolCall'] as bool? ?? false,
    );
  }
}

List<SubPromptStep> parseSubPromptSteps(String text) {
  final matches = subPromptSepRegex.allMatches(text).toList();

  if (matches.isEmpty) {
    return [SubPromptStep(text: text.trim())];
  }

  final steps = <SubPromptStep>[];

  final beforeFirst = text.substring(0, matches[0].start).trim();
  if (beforeFirst.isNotEmpty) {
    steps.add(SubPromptStep(text: beforeFirst));
  }

  for (int i = 0; i < matches.length; i++) {
    final m = matches[i];
    final segEnd = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final segText = text.substring(m.end, segEnd).trim();

    final legacyDigit = m.group(1);
    final ntContent = m.group(2);
    final satcFlag = m.group(3);
    final satc = satcFlag != null;

    SubPromptStep step;
    if (ntContent != null) {
      step = SubPromptStep.fromNamedTools(
        segText,
        ntContent,
        stopAfterToolCall: satc,
      );
    } else {
      step = SubPromptStep.fromLegacyDigit(
        segText,
        legacyDigit,
        stopAfterToolCall: satc,
      );
    }
    steps.add(step);
  }

  if (steps.isEmpty) steps.add(const SubPromptStep(text: ''));
  return steps;
}

String serializeSubPromptSteps(List<SubPromptStep> steps) {
  if (steps.isEmpty) return '';

  if (steps.length == 1 && steps[0].isAllTools && !steps[0].stopAfterToolCall) {
    return steps[0].text;
  }

  String tag(SubPromptStep s) {
    final nt = s.enabledToolNames == null
        ? ''
        : (s.enabledToolNames!.isEmpty
              ? '[NT:]'
              : '[NT:${s.enabledToolNames!.join('|')}]');
    final satc = s.stopAfterToolCall ? '[SATC]' : '';
    return '$nt$satc';
  }

  final sb = StringBuffer();
  for (int i = 0; i < steps.length; i++) {
    final s = steps[i];
    final t = tag(s);
    if (i == 0 && t.isEmpty) {
      sb.write(s.text);
    } else {
      if (sb.isNotEmpty) sb.write('\n');
      sb.write('++#++');
      sb.write(t);
      if (s.text.isNotEmpty) {
        sb.write('\n');
        sb.write(s.text);
      }
    }
  }
  return sb.toString();
}

// ═══════════════════════════════════════════════════════════════
// 6. Local MCP Server Setup
// ═══════════════════════════════════════════════════════════════

class LocalMcpServerSetup {
  final String name;
  final String? launchArguments;
  final String type; // 'python' | 'nodejs'
  final String method; // 'pip' | 'uvx' | 'npm' | 'npx'
  final String packageOrServerName;
  final String? installCommand;
  final bool reinstall;
  final Map<String, String>? envVars;
  final String? launchCommand;

  const LocalMcpServerSetup({
    required this.name,
    this.launchArguments,
    required this.type,
    required this.method,
    required this.packageOrServerName,
    this.installCommand,
    this.reinstall = false,
    this.envVars,
    this.launchCommand,
  });
}

// ═══════════════════════════════════════════════════════════════
// 7. Saved Playground Setup
// ═══════════════════════════════════════════════════════════════

class SavedPlaygroundSetup {
  final String id;
  final String name;
  final DateTime createdAt;
  final String systemPrompt;
  final String initialPrompt;
  final List<String> enabledToolNames;
  final bool chatMode;
  final bool stopAfterToolCall;
  final bool useCustomLlm;
  final LlmConfig? customLlmConfig;

  // SSH Override parameters & generic parameters
  final Map<String, dynamic>? mcpInitParams;

  SavedPlaygroundSetup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.systemPrompt,
    required this.initialPrompt,
    required this.enabledToolNames,
    required this.chatMode,
    required this.stopAfterToolCall,
    required this.useCustomLlm,
    this.customLlmConfig,
    this.mcpInitParams,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'systemPrompt': systemPrompt,
        'initialPrompt': initialPrompt,
        'enabledToolNames': enabledToolNames,
        'chatMode': chatMode,
        'stopAfterToolCall': stopAfterToolCall,
        'useCustomLlm': useCustomLlm,
        'customLlmConfig': customLlmConfig?.toJson(),
        'mcpInitParams': mcpInitParams,
      };

  factory SavedPlaygroundSetup.fromJson(Map<String, dynamic> json) {
    return SavedPlaygroundSetup(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      systemPrompt: json['systemPrompt'] as String? ?? '',
      initialPrompt: json['initialPrompt'] as String? ?? '',
      enabledToolNames: (json['enabledToolNames'] as List?)?.cast<String>() ?? [],
      chatMode: json['chatMode'] as bool? ?? false,
      stopAfterToolCall: json['stopAfterToolCall'] as bool? ?? false,
      useCustomLlm: json['useCustomLlm'] as bool? ?? false,
      customLlmConfig: json['customLlmConfig'] != null
          ? LlmConfig.fromJson(json['customLlmConfig'] as Map<String, dynamic>)
          : null,
      mcpInitParams: json['mcpInitParams'] as Map<String, dynamic>?,
    );
  }
}
