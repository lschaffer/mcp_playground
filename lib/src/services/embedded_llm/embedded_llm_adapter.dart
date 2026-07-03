import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import '../../../models.dart';
import '../../../llm_service.dart';

/// Adapter that wraps the llamadart library and exposes an interface compatible
/// with [LLMService]. This is the ONLY place where llamadart is used.
class EmbeddedLlmAdapter {
  EmbeddedLlmAdapter._();
  static final EmbeddedLlmAdapter instance = EmbeddedLlmAdapter._();

  // LlamaBackend auto-selects the platform-appropriate backend (llama.cpp
  // on native, WebGPU/WASM on web). Keep a single instance for the entire
  // app lifetime.
  static final LlamaBackend _backend = LlamaBackend();

  LlamaEngine? _engine;
  String? _loadedModelPath;
  Future<void>? _loadingFuture;

  bool get isLoaded => _engine?.isReady == true;
  String? get loadedModelPath => _loadedModelPath;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  static const int _mobileMaxContextSize = 4096;

  Future<void> initialize(
    String modelPath, {
    int gpuLayers = 0,
    int contextSize = 4096,
    void Function(double progress)? onProgress,
  }) async {
    final effectiveContextSize = _shouldTruncate
        ? contextSize.clamp(1, _mobileMaxContextSize)
        : contextSize;
    if (_loadedModelPath == modelPath && isLoaded) return;

    // Wait for any in-progress load to settle, then re-check.
    final previousLoad = _loadingFuture;
    if (previousLoad != null) {
      try {
        await previousLoad;
      } catch (_) {
        // Previous load failed — proceed with this attempt.
      }
      if (_loadedModelPath == modelPath && isLoaded) return;
    }

    // Capture this load operation so concurrent callers can await it.
    final future = _performLoad(
      modelPath,
      effectiveContextSize,
      gpuLayers,
      onProgress,
    );
    _loadingFuture = future;
    try {
      await future;
    } finally {
      if (_loadingFuture == future) {
        _loadingFuture = null;
      }
    }
  }

  Future<void> _performLoad(
    String modelPath,
    int contextSize,
    int gpuLayers,
    void Function(double progress)? onProgress,
  ) async {
    await _unloadCurrentModel();
    onProgress?.call(0.0);

    _engine ??= LlamaEngine(_backend);

    // Attempt load with the requested context size. If context creation
    // fails (common with newer GGUF models that have architecture quirks),
    // retry with progressively smaller context sizes before giving up.
    final sizesToTry = <int>[contextSize];
    if (contextSize > 2048) sizesToTry.add(contextSize ~/ 2);
    if (contextSize > 1024) sizesToTry.add(1024);

    Object? lastError;
    for (final size in sizesToTry) {
      try {
        await _engine!.loadModel(
          modelPath,
          modelParams: ModelParams(contextSize: size, gpuLayers: gpuLayers),
        );
        _loadedModelPath = modelPath;
        onProgress?.call(1.0);
        return; // Success
      } on LlamaModelException catch (e) {
        lastError = e;
        // Only retry if this is a context-related failure.
        if (!e.toString().contains('create context')) rethrow;
        // Clean up the failed attempt before retrying.
        if (_engine != null && _engine!.isReady) {
          await _engine!.unloadModel();
        }
        _engine = null;
      }
    }

    // All attempts failed – rethrow the last error.
    throw lastError!;
  }

  Future<void> _unloadCurrentModel() async {
    if (_engine != null && isLoaded) {
      await _engine!.unloadModel();
    }
    _loadedModelPath = null;
  }

  Future<void> dispose() async {
    await _unloadCurrentModel();
    _engine = null;
  }

  // ── GPU capabilities ───────────────────────────────────────────────────────

  Future<bool> isGpuSupported() async {
    try {
      return await _backend.isGpuSupported();
    } catch (_) {
      return false;
    }
  }

  Future<({int total, int free})> getVramInfo() async {
    try {
      return await _backend.getVramInfo();
    } catch (_) {
      return (total: 0, free: 0);
    }
  }

  // ── Inference ────────────────────────────────────────────────────────────────

  Future<LLMResponse> generateResponse({
    required List<ChatMessage> messages,
    List<MCPTool>? availableTools,
    double temperature = 0.3,
    int maxTokens = 1024,
    int topK = 40,
    double topP = 0.9,
    double penalty = 1.15,
    void Function(String chunk)? onStreamChunk,
  }) async {
    final engine = _engine;
    if (engine == null || !engine.isReady) {
      throw StateError('Embedded model not loaded. Call initialize() first.');
    }

    final session = ChatSession(engine);

    final systemMsg = messages.lastWhereOrNull(
      (m) => m.role == ChatRole.system,
    );
    if (systemMsg != null) {
      session.systemPrompt = systemMsg.content;
    }

    final nonSystem = messages.where((m) => m.role != ChatRole.system).toList();
    if (nonSystem.isEmpty) {
      throw ArgumentError('No user messages in conversation.');
    }

    final lastIsToolResult = nonSystem.last.role == ChatRole.tool;
    final historySlice = lastIsToolResult
        ? nonSystem
        : nonSystem.take(nonSystem.length - 1).toList();
    _populateHistory(session, historySlice);

    if (!lastIsToolResult) {
      if (session.history.isNotEmpty &&
          session.history.last.role == LlamaChatRole.tool) {
        session.addMessage(
          LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: ' '),
        );
      }
    }

    final inputParts = <LlamaContentPart>[];
    if (!lastIsToolResult) {
      final lastMsg = nonSystem.last;
      inputParts.add(LlamaTextContent(lastMsg.content));
      if (lastMsg.attachments != null) {
        for (final att in lastMsg.attachments!) {
          final mime = att.mimeType.toLowerCase();
          if (mime.startsWith('image/') && att.bytes != null) {
            inputParts.add(LlamaImageContent(bytes: att.bytes!));
          }
        }
      }
    }

    final toolDefs = availableTools != null && availableTools.isNotEmpty
        ? _convertTools(availableTools)
        : null;
    final params = GenerationParams(
      maxTokens: maxTokens,
      temp: temperature,
      topK: topK,
      topP: topP,
      penalty: penalty,
    );

    String fullText = '';
    await for (final chunk in session.create(
      inputParts,
      tools: toolDefs,
      params: params,
    )) {
      if (chunk.choices.isNotEmpty) {
        final content = chunk.choices.first.delta.content;
        if (content != null && content.isNotEmpty) {
          fullText += content;
          onStreamChunk?.call(content);
        }
      }
    }

    final lastHistoryMsg = session.history.lastOrNull;
    var toolCalls =
        lastHistoryMsg?.parts
            .whereType<LlamaToolCallContent>()
            .map(
              (tc) => LLMToolCall(
                id: tc.id ?? tc.name,
                name: tc.name,
                arguments: tc.arguments,
              ),
            )
            .toList() ??
        [];

    if (toolCalls.isEmpty && fullText.isNotEmpty) {
      final parsed = _extractTextToolCall(fullText);
      if (parsed != null) {
        toolCalls = [parsed];
        fullText = '';
      }
    }

    return LLMResponse(text: fullText, toolCalls: toolCalls);
  }

  // ── History builder ──────────────────────────────────────────────────────────

  void _populateHistory(ChatSession session, List<ChatMessage> messages) {
    int i = 0;
    while (i < messages.length) {
      final msg = messages[i];

      if (msg.role == ChatRole.user) {
        if (session.history.isNotEmpty &&
            session.history.last.role == LlamaChatRole.tool) {
          session.addMessage(
            LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: ' '),
          );
        }
        session.addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: msg.content,
          ),
        );
        i++;
      } else if (msg.role == ChatRole.assistant) {
        int j = i + 1;
        final toolResults = <ChatMessage>[];
        while (j < messages.length && messages[j].role == ChatRole.tool) {
          toolResults.add(messages[j]);
          j++;
        }

        if (toolResults.isNotEmpty) {
          final parts = toolResults
              .map<LlamaContentPart>(
                (tr) => LlamaToolCallContent(
                  id: tr.id,
                  name: tr.toolName ?? 'tool',
                  arguments: tr.toolArguments ?? const {},
                  rawJson: '{"name":"${tr.toolName ?? "tool"}","arguments":{}}',
                ),
              )
              .toList();
          session.addMessage(
            LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: parts,
            ),
          );

          for (final tr in toolResults) {
            final resultText = _truncateToolResult(
              _extractToolResultText(tr.toolResult?.content, tr.content),
            );
            session.addMessage(
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [
                  LlamaToolResultContent(
                    id: tr.id,
                    name: tr.toolName ?? 'tool',
                    result: resultText,
                  ),
                ],
              ),
            );
          }

          i = j;
        } else {
          session.addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: msg.content,
            ),
          );
          i++;
        }
      } else if (msg.role == ChatRole.tool) {
        final resultText = _truncateToolResult(
          _extractToolResultText(msg.toolResult?.content, msg.content),
        );
        session.addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: msg.id,
                name: msg.toolName ?? 'tool',
                result: resultText,
              ),
            ],
          ),
        );
        i++;
      } else {
        i++;
      }
    }
  }

  // ── Tool result truncation ───────────────────────────────────────────────────

  static bool get _shouldTruncate =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String _extractToolResultText(List<MCPContent>? contents, String fallback) {
    if (contents == null || contents.isEmpty) return fallback;

    final parts = <String>[];
    int skippedImages = 0;

    for (final c in contents) {
      final mime = c.mimeType?.toLowerCase() ?? '';
      final isImage =
          c.type == 'image' ||
          mime.startsWith('image/') ||
          mime == 'application/octet-stream';

      if (isImage || (c.data != null && c.data!.isNotEmpty)) {
        skippedImages++;
        continue;
      }

      final text = c.text;
      if (text == null || text.trim().isEmpty) continue;

      if (_looksLikeBase64Blob(text)) {
        skippedImages++;
        continue;
      }

      String trimmed = text.trim();
      if (trimmed.startsWith('{')) {
        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>?;
          if (json != null) {
            final data = json['data'];
            if (data is Map) {
              final inner = data['content'];
              if (inner is String && _looksLikeBase64Blob(inner)) {
                final summary = <String, dynamic>{
                  if (json['success'] != null) 'success': json['success'],
                  'message': 'File generated and available in the UI.',
                  if (data['fileName'] != null) 'fileName': data['fileName'],
                  if (data['mimeType'] != null) 'mimeType': data['mimeType'],
                  if (data['size'] != null) 'size': data['size'],
                };
                trimmed = jsonEncode(summary);
              }
            }
          }
        } catch (_) {}
      }

      parts.add(trimmed);
    }

    if (parts.isEmpty) {
      if (skippedImages > 0) {
        return '[Tool produced $skippedImages image/binary output(s). '
            'The file has been saved and is visible in the UI. '
            'Do not describe or reproduce the binary data.]';
      }
      return fallback;
    }

    final joined = parts.join('\n');
    if (skippedImages > 0) {
      return '$joined\n[$skippedImages image/binary output(s) omitted — visible in UI]';
    }
    return joined;
  }

  static bool _looksLikeBase64Blob(String text) {
    if (text.length < 256) return false;
    final hasWhitespace =
        text.contains(' ') || text.contains('\n') || text.contains('\t');
    if (hasWhitespace) return false;
    return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text);
  }

  static const int _maxToolResultChars = 2500;

  String _truncateToolResult(String text) {
    final payload = _extractTextualPayload(text);
    if (!_shouldTruncate || payload.length <= _maxToolResultChars) {
      return payload;
    }
    return '[TOOL OUTPUT BLOCKED — the output was ${payload.length} characters, '
        'which exceeds the on-device limit of $_maxToolResultChars characters. '
        'The result has NOT been sent to the model to prevent memory issues and hallucinations. '
        'Please retry with a more specific or filtered command that produces less output, '
        'or use a cloud/desktop agent for commands with large outputs.]';
  }

  String _extractTextualPayload(String text) {
    if (!text.startsWith('{')) return text;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>?;
      if (json == null) return text;
      final stdout = json['stdout'] as String?;
      if (stdout != null && stdout.trim().isNotEmpty) return stdout.trim();
      for (final key in const ['output', 'text', 'result', 'content']) {
        final v = json[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return text;
  }

  // ── Plain-text tool-call parser ────────────────────────────────────────────

  static LLMToolCall? _extractTextToolCall(String content) {
    try {
      Map<String, dynamic>? payload;

      final marker = content.indexOf('tool_call:');
      if (marker >= 0) {
        final firstBrace = content.indexOf('{', marker);
        if (firstBrace >= 0) {
          final jsonStr = _extractBalancedJson(content, firstBrace);
          if (jsonStr.isNotEmpty) {
            final decoded = jsonDecode(jsonStr);
            if (decoded is Map<String, dynamic>) payload = decoded;
          }
        }
      }

      if (payload == null) {
        final firstBrace = content.indexOf('{');
        if (firstBrace >= 0) {
          final jsonStr = _extractBalancedJson(content, firstBrace);
          if (jsonStr.isNotEmpty) {
            final decoded = jsonDecode(jsonStr);
            if (decoded is Map<String, dynamic>) payload = decoded;
          }
        }
      }

      if (payload == null) return null;

      final inner = payload.containsKey('tool_call')
          ? payload['tool_call']
          : payload;
      if (inner is! Map) return null;
      final toolCall = Map<String, dynamic>.from(inner);

      final name = (toolCall['name'] ?? '').toString().trim();
      if (name.isEmpty) return null;

      final args = toolCall['arguments'];
      final params = toolCall['parameters'];
      Map<String, dynamic> arguments = const {};
      if (args is Map) {
        arguments = Map<String, dynamic>.from(args);
      } else if (params is Map) {
        arguments = Map<String, dynamic>.from(params);
      }

      return LLMToolCall(id: name, name: name, arguments: arguments);
    } catch (_) {
      return null;
    }
  }

  static String _extractBalancedJson(String input, int startIndex) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = startIndex; i < input.length; i++) {
      final ch = input[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return input.substring(startIndex, i + 1);
      }
    }
    return '';
  }

  // ── Tool conversion ──────────────────────────────────────────────────────────

  List<ToolDefinition> _convertTools(List<MCPTool> tools) {
    return tools.map((tool) {
      final params = _schemaToParams(tool.inputSchema);
      return ToolDefinition(
        name: tool.name,
        description: tool.description ?? '',
        parameters: params,
        handler: (_) async => null,
      );
    }).toList();
  }

  List<ToolParam> _schemaToParams(Map<String, dynamic>? schema) {
    final rawProps = schema?['properties'];
    final props = rawProps == null
        ? <String, dynamic>{}
        : (rawProps as Map).cast<String, dynamic>();
    final rawRequired = schema?['required'];
    final required = rawRequired == null
        ? <String>[]
        : (rawRequired as List).cast<String>();

    return props.entries.map((entry) {
      final def = (entry.value as Map).cast<String, dynamic>();
      final isRequired = required.contains(entry.key);
      final desc = def['description'] as String?;
      final type = def['type'] as String? ?? 'string';

      switch (type) {
        case 'integer':
          return ToolParam.integer(
            entry.key,
            description: desc,
            required: isRequired,
          );
        case 'number':
          return ToolParam.number(
            entry.key,
            description: desc,
            required: isRequired,
          );
        case 'boolean':
          return ToolParam.boolean(
            entry.key,
            description: desc,
            required: isRequired,
          );
        case 'array':
          return ToolParam.array(
            entry.key,
            itemType: ToolParam.string('item'),
            description: desc,
            required: isRequired,
          );
        default:
          final enumVals = (def['enum'] as List?)?.cast<String>();
          if (enumVals != null && enumVals.isNotEmpty) {
            return ToolParam.enumType(
              entry.key,
              values: enumVals,
              description: desc,
              required: isRequired,
            );
          }
          return ToolParam.string(
            entry.key,
            description: desc,
            required: isRequired,
          );
      }
    }).toList();
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (int i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
