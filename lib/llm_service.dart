import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleai_dart/googleai_dart.dart' as gemini;
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:ollama_dart/ollama_dart.dart' as ollama;
import 'package:http/http.dart' as http;
import 'models.dart';

/// Represents a tool call requested by the LLM.
class LLMToolCall {
  /// Unique identifier of the tool call instance.
  final String id;

  /// The name of the tool function to call.
  final String name;

  /// The input parameters mapped as arguments for the tool execution.
  final Map<String, dynamic> arguments;

  /// Creates a new [LLMToolCall] instance.
  const LLMToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Represents the completion response returned by the LLM.
class LLMResponse {
  /// The textual response content from the LLM.
  final String text;

  /// The list of tool calls requested by the LLM in this response.
  final List<LLMToolCall> toolCalls;

  /// Creates a new [LLMResponse] instance.
  const LLMResponse({
    required this.text,
    this.toolCalls = const [],
  });
}

/// Service provider class wrapping client integrations for various LLM SDKs.
class LLMService {
  /// Generate completion using direct SDK adapters.
  static Future<LLMResponse> generate({
    required LlmConfig config,
    required List<ChatMessage> messages,
    required List<MCPTool> tools,
    String? systemPrompt,
  }) async {
    switch (config.provider) {
      case LlmProvider.openai:
      case LlmProvider.openaiCompatible:
        return await _generateOpenAI(config, messages, tools, systemPrompt);
      case LlmProvider.mistral:
        return await _generateMistral(config, messages, tools, systemPrompt);
      case LlmProvider.claude:
        return await _generateAnthropic(config, messages, tools, systemPrompt);
      case LlmProvider.gemini:
        return await _generateGemini(config, messages, tools, systemPrompt);
      case LlmProvider.ollama:
        return await _generateOllama(config, messages, tools, systemPrompt);
      default:
        throw Exception('LLM provider not configured or unsupported');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. OpenAI Adapter
  // ═══════════════════════════════════════════════════════════════
  static Future<LLMResponse> _generateOpenAIWithClient(
    openai.OpenAIClient client,
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    try {
      final List<openai.ChatMessage> openAiMsgs = [];

      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        openAiMsgs.add(
          openai.ChatMessage.system(
            systemPrompt,
          ),
        );
      }

      for (final msg in messages) {
        switch (msg.role) {
          case ChatRole.user:
            openAiMsgs.add(
              openai.ChatMessage.user(
                msg.content,
              ),
            );
          case ChatRole.assistant:
            if (msg.type == MessageType.toolCall) {
              openAiMsgs.add(
                openai.ChatMessage.assistant(
                  toolCalls: [
                    openai.ToolCall.functionCall(
                      id: msg.id,
                      call: openai.FunctionCall.fromMap(
                        name: msg.toolName ?? '',
                        arguments: msg.toolArguments ?? {},
                      ),
                    ),
                  ],
                ),
              );
            } else {
              openAiMsgs.add(
                openai.ChatMessage.assistant(
                  content: msg.content,
                ),
              );
            }
          case ChatRole.tool:
            openAiMsgs.add(
              openai.ChatMessage.tool(
                toolCallId: msg.id,
                content: msg.content,
              ),
            );
          case ChatRole.system:
            openAiMsgs.add(
              openai.ChatMessage.system(
                msg.content,
              ),
            );
        }
      }

      final List<openai.Tool> openAiTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          openAiTools.add(
            openai.Tool.function(
              name: t.name,
              description: t.description ?? '',
              parameters: t.inputSchema ?? {'type': 'object', 'properties': {}},
            ),
          );
        }
      }

      final response = await client.chat.completions.create(
        openai.ChatCompletionCreateRequest(
          model: config.model.trim().isNotEmpty ? config.model : 'gpt-4o-mini',
          messages: openAiMsgs,
          tools: openAiTools.isNotEmpty ? openAiTools : null,
          temperature: config.temperature,
          maxTokens: config.maxTokens > 0 ? config.maxTokens : null,
          topP: config.topP,
          seed: config.seed,
        ),
      );

      final choice = response.choices.first;
      final answer = choice.message.content ?? '';
      final toolCalls = <LLMToolCall>[];

      if (choice.message.toolCalls != null) {
        for (final tc in choice.message.toolCalls!) {
          if (tc.type == 'function') {
            Map<String, dynamic> args = {};
            try {
              args = jsonDecode(tc.function.arguments) as Map<String, dynamic>;
            } catch (_) {}
            toolCalls.add(
              LLMToolCall(
                id: tc.id,
                name: tc.function.name,
                arguments: args,
              ),
            );
          }
        }
      }

      return LLMResponse(text: answer, toolCalls: toolCalls);
    } finally {
      // Client is cleaned up by garbage collection
    }
  }

  static Future<LLMResponse> _generateOpenAI(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = openai.OpenAIClient(
      config: openai.OpenAIConfig(
        authProvider: openai.ApiKeyProvider(config.apiKey),
        baseUrl: config.baseUrl.trim().isNotEmpty ? config.baseUrl : 'https://api.openai.com/v1',
      ),
    );
    return await _generateOpenAIWithClient(client, config, messages, tools, systemPrompt);
  }

  static Future<LLMResponse> _generateMistral(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = openai.OpenAIClient(
      config: openai.OpenAIConfig(
        authProvider: openai.ApiKeyProvider(config.apiKey),
        baseUrl: config.baseUrl.trim().isNotEmpty ? config.baseUrl : 'https://api.mistral.ai/v1',
      ),
      httpClient: _MistralPatchClient(http.Client()),
    );
    return await _generateOpenAIWithClient(client, config, messages, tools, systemPrompt);
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. Anthropic Claude Adapter
  // ═══════════════════════════════════════════════════════════════
  static Future<LLMResponse> _generateAnthropic(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = anthropic.AnthropicClient(
      config: anthropic.AnthropicConfig(
        authProvider: anthropic.ApiKeyProvider(config.apiKey),
      ),
    );

    try {
      final List<anthropic.InputMessage> anthropicMsgs = [];

      for (final msg in messages) {
        if (msg.role == ChatRole.system) continue;

        switch (msg.role) {
          case ChatRole.user:
            anthropicMsgs.add(
              anthropic.InputMessage.user(msg.content),
            );
          case ChatRole.assistant:
            if (msg.type == MessageType.toolCall) {
              anthropicMsgs.add(
                anthropic.InputMessage.assistantBlocks([
                  anthropic.InputContentBlock.toolUse(
                    id: msg.id,
                    name: msg.toolName ?? '',
                    input: msg.toolArguments ?? {},
                  ),
                ]),
              );
            } else {
              anthropicMsgs.add(
                anthropic.InputMessage.assistant(msg.content),
              );
            }
          case ChatRole.tool:
            anthropicMsgs.add(
              anthropic.InputMessage.userBlocks([
                anthropic.InputContentBlock.toolResultText(
                  toolUseId: msg.id,
                  text: msg.content,
                ),
              ]),
            );
          default:
            break;
        }
      }

      final List<anthropic.ToolDefinition> anthropicTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          anthropicTools.add(
            anthropic.ToolDefinition.custom(
              anthropic.Tool(
                name: t.name,
                description: t.description ?? '',
                inputSchema: anthropic.InputSchema.fromJson(
                  t.inputSchema ?? {'type': 'object', 'properties': {}},
                ),
              ),
            ),
          );
        }
      }

      final response = await client.messages.create(
        anthropic.MessageCreateRequest(
          model: config.model.trim().isNotEmpty ? config.model : 'claude-3-5-sonnet-latest',
          messages: anthropicMsgs,
          system: systemPrompt != null && systemPrompt.trim().isNotEmpty
              ? anthropic.SystemPrompt.text(systemPrompt)
              : null,
          tools: anthropicTools.isNotEmpty ? anthropicTools : null,
          temperature: config.temperature,
          maxTokens: config.maxTokens > 0 ? config.maxTokens : 4096,
        ),
      );

      final textBuffer = StringBuffer();
      final toolCalls = <LLMToolCall>[];

      for (final block in response.content) {
        if (block is anthropic.TextBlock) {
          textBuffer.write(block.text);
        } else if (block is anthropic.ToolUseBlock) {
          toolCalls.add(
            LLMToolCall(
              id: block.id,
              name: block.name,
              arguments: block.input,
            ),
          );
        }
      }

      return LLMResponse(text: textBuffer.toString(), toolCalls: toolCalls);
    } finally {
      // Client is cleaned up by garbage collection
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 3. Gemini Adapter
  // ═══════════════════════════════════════════════════════════════
  static Future<LLMResponse> _generateGemini(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = gemini.GoogleAIClient(
      config: gemini.GoogleAIConfig.googleAI(
        authProvider: gemini.ApiKeyProvider(config.apiKey),
      ),
    );

    try {
      final List<gemini.Tool> geminiTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        final declarations = <gemini.FunctionDeclaration>[];
        for (final t in tools) {
          declarations.add(
            gemini.FunctionDeclaration(
              name: t.name,
              description: t.description ?? '',
              parameters: _sanitizeGeminiSchema(t.inputSchema),
            ),
          );
        }
        geminiTools.add(gemini.Tool(functionDeclarations: declarations));
      }

      final List<gemini.Content> contentList = [];
      for (final msg in messages) {
        if (msg.role == ChatRole.system) continue;

        switch (msg.role) {
          case ChatRole.user:
            contentList.add(
              gemini.Content(
                role: 'user',
                parts: [gemini.Part.text(msg.content)],
              ),
            );
          case ChatRole.assistant:
            if (msg.type == MessageType.toolCall) {
              contentList.add(
                gemini.Content(
                  role: 'model',
                  parts: [
                    gemini.Part.functionCall(
                      msg.toolName ?? '',
                      args: msg.toolArguments,
                    )
                  ],
                ),
              );
            } else {
              contentList.add(
                gemini.Content(
                  role: 'model',
                  parts: [gemini.Part.text(msg.content)],
                ),
              );
            }
          case ChatRole.tool:
            contentList.add(
              gemini.Content(
                role: 'function',
                parts: [
                  gemini.Part.functionResponse(
                    msg.toolName ?? '',
                    {'content': msg.content},
                  )
                ],
              ),
            );
          default:
            break;
        }
      }

      final response = await client.models.generateContent(
        model: config.model.trim().isNotEmpty ? config.model : 'gemini-2.5-flash',
        request: gemini.GenerateContentRequest(
          contents: contentList,
          tools: geminiTools.isNotEmpty ? geminiTools : null,
          systemInstruction: systemPrompt != null && systemPrompt.trim().isNotEmpty
              ? gemini.Content(parts: [gemini.Part.text(systemPrompt)])
              : null,
          generationConfig: gemini.GenerationConfig(
            temperature: config.temperature,
            maxOutputTokens: config.maxTokens > 0 ? config.maxTokens : null,
            topP: config.topP,
            topK: config.topK,
            candidateCount: 1,
          ),
        ),
      );

      final text = response.text ?? '';
      final toolCalls = <LLMToolCall>[];

      final functionCalls = response.functionCalls;
      if (functionCalls.isNotEmpty) {
        for (final fc in functionCalls) {
          final args = Map<String, dynamic>.from(fc.args ?? {});
          final argHash = jsonEncode(args).hashCode.toRadixString(16);
          toolCalls.add(
            LLMToolCall(
              id: 'call_${fc.name}_$argHash',
              name: fc.name,
              arguments: args,
            ),
          );
        }
      }

      return LLMResponse(text: text, toolCalls: toolCalls);
    } finally {
      client.close();
    }
  }

  static gemini.Schema _sanitizeGeminiSchema(Map<String, dynamic>? schema) {
    if (schema == null) return const gemini.Schema(type: gemini.SchemaType.string);
    final typeStr = (schema['type'] ?? 'string').toString().toLowerCase();

    final desc = schema['description'] as String?;
    final properties = schema['properties'] as Map?;
    final requiredProps = (schema['required'] as List?)?.cast<String>() ?? [];

    switch (typeStr) {
      case 'object':
        final propsMap = <String, gemini.Schema>{};
        if (properties != null) {
          for (final entry in properties.entries) {
            if (entry.value is Map) {
              propsMap[entry.key.toString()] = _sanitizeGeminiSchema(
                Map<String, dynamic>.from(entry.value as Map),
              );
            }
          }
        }
        return gemini.Schema(
          type: gemini.SchemaType.object,
          description: desc,
          properties: propsMap,
          required: requiredProps,
        );
      case 'array':
        final items = schema['items'];
        final itemsSchema = items is Map
            ? _sanitizeGeminiSchema(Map<String, dynamic>.from(items))
            : const gemini.Schema(type: gemini.SchemaType.string);
        return gemini.Schema(
          type: gemini.SchemaType.array,
          description: desc,
          items: itemsSchema,
        );
      case 'integer':
        return gemini.Schema(type: gemini.SchemaType.integer, description: desc);
      case 'number':
        return gemini.Schema(type: gemini.SchemaType.number, description: desc);
      case 'boolean':
        return gemini.Schema(type: gemini.SchemaType.boolean, description: desc);
      default:
        return gemini.Schema(type: gemini.SchemaType.string, description: desc);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. Ollama Adapter
  // ═══════════════════════════════════════════════════════════════
  static Future<LLMResponse> _generateOllama(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final headers = <String, String>{};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    final client = ollama.OllamaClient(
      config: ollama.OllamaConfig(
        baseUrl: config.baseUrl.trim().isNotEmpty
            ? config.baseUrl
            : 'http://localhost:11434/api',
        defaultHeaders: headers,
      ),
    );

    try {
      final List<ollama.ChatMessage> ollamaMsgs = [];

      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        ollamaMsgs.add(
          ollama.ChatMessage(
            role: ollama.MessageRole.system,
            content: systemPrompt,
          ),
        );
      }

      for (final msg in messages) {
        ollama.MessageRole role = ollama.MessageRole.user;
        if (msg.role == ChatRole.assistant) {
          role = ollama.MessageRole.assistant;
        } else if (msg.role == ChatRole.system) {
          role = ollama.MessageRole.system;
        } else if (msg.role == ChatRole.tool) {
          role = ollama.MessageRole.tool;
        }

        List<ollama.ToolCall>? toolCalls;
        if (msg.type == MessageType.toolCall) {
          toolCalls = [
            ollama.ToolCall(
              function: ollama.ToolCallFunction(
                name: msg.toolName ?? '',
                arguments: msg.toolArguments ?? {},
              ),
            )
          ];
        }

        ollamaMsgs.add(
          ollama.ChatMessage(
            role: role,
            content: msg.content,
            toolCalls: toolCalls,
          ),
        );
      }

      final List<ollama.ToolDefinition> ollamaTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          ollamaTools.add(
            ollama.ToolDefinition(
              function: ollama.ToolFunction(
                name: t.name,
                description: t.description ?? '',
                parameters: t.inputSchema ?? {'type': 'object', 'properties': {}},
              ),
            ),
          );
        }
      }

      final response = await client.chat.create(
        request: ollama.ChatRequest(
          model: config.model,
          messages: ollamaMsgs,
          tools: ollamaTools.isNotEmpty ? ollamaTools : null,
          options: ollama.ModelOptions(
            temperature: config.temperature,
            numPredict: config.maxTokens > 0 ? config.maxTokens : null,
            seed: config.seed,
          ),
        ),
      );

      final answer = response.message?.content ?? '';
      final toolCalls = <LLMToolCall>[];

      if (response.message?.toolCalls != null && response.message!.toolCalls!.isNotEmpty) {
        for (final tc in response.message!.toolCalls!) {
          final name = tc.function?.name ?? '';
          final args = tc.function?.arguments ?? {};
          final argHash = jsonEncode(args).hashCode.toRadixString(16);
          toolCalls.add(
            LLMToolCall(
              id: 'call_${name}_$argHash',
              name: name,
              arguments: args,
            ),
          );
        }
      }

      return LLMResponse(text: answer, toolCalls: toolCalls);
    } finally {
      // ollama client uses standard http which closes connection on garbage collect
    }
  }
}

class _MistralPatchClient extends http.BaseClient {
  _MistralPatchClient(this._inner);
  final http.Client _inner;

  Map<String, dynamic> _sanitizeMistralChatRequest(
    Map<String, dynamic> payload,
  ) {
    final rawMessages = payload['messages'];
    if (rawMessages is! List) return payload;

    final sanitized = <dynamic>[];
    bool changed = false;

    for (final item in rawMessages) {
      if (item is! Map) {
        sanitized.add(item);
        continue;
      }

      final msg = Map<String, dynamic>.from(item);
      final role = (msg['role'] ?? '').toString();

      if (role == 'user') {
        final content = msg['content'];
        if (content is List) {
          final patchedContent = content.map((part) {
            if (part is! Map) return part;
            final partMap = Map<String, dynamic>.from(part);
            if (partMap['type'] == 'image_url') {
              final imageUrl = partMap['image_url'];
              if (imageUrl is Map) {
                final url = imageUrl['url'];
                if (url is String) {
                  partMap['image_url'] = url;
                  changed = true;
                }
              }
            }
            return partMap;
          }).toList();
          msg['content'] = patchedContent;
        }
      }

      if (role == 'tool') {
        final toolCallId = (msg['tool_call_id'] ?? '').toString().trim();
        final prev = sanitized.isNotEmpty && sanitized.last is Map
            ? Map<String, dynamic>.from(sanitized.last as Map)
            : null;

        bool hasMatchingAssistantToolCall = false;
        if (prev != null && (prev['role']?.toString() == 'assistant')) {
          final toolCalls = prev['tool_calls'];
          if (toolCalls is List) {
            hasMatchingAssistantToolCall = toolCalls.any((tc) {
              if (tc is! Map) return false;
              final tcMap = Map<String, dynamic>.from(tc);
              return (tcMap['id'] ?? '').toString().trim() == toolCallId;
            });
          }
        }

        if (!hasMatchingAssistantToolCall && toolCallId.isNotEmpty) {
          sanitized.add({
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': toolCallId,
                'type': 'function',
                'function': {'name': 'unknown_tool', 'arguments': '{}'},
              },
            ],
          });
          changed = true;
        }
      }

      sanitized.add(msg);
    }

    if (changed) {
      payload['messages'] = sanitized;
    }
    return payload;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.BaseRequest requestToSend = request;

    if (request.method.toUpperCase() == 'POST' &&
        request.url.path.contains('chat/completions') &&
        request is http.Request) {
      try {
        final decoded = jsonDecode(request.body);
        if (decoded is Map<String, dynamic>) {
          final patchedPayload = _sanitizeMistralChatRequest(decoded);
          final cleanHeaders = Map<String, String>.from(request.headers);
          cleanHeaders.removeWhere((key, _) =>
              key.toLowerCase() == 'content-length' ||
              (kIsWeb && key.toLowerCase() == 'user-agent'));
          requestToSend = http.Request(request.method, request.url)
            ..headers.addAll(cleanHeaders)
            ..body = jsonEncode(patchedPayload);
        }
      } catch (_) {}
    } else {
      if (kIsWeb) {
        try {
          requestToSend.headers.removeWhere((key, _) => key.toLowerCase() == 'user-agent');
        } catch (_) {}
      }
    }

    final streamed = await _inner.send(requestToSend);

    if (!request.url.path.contains('chat/completions')) return streamed;

    final bodyBytes = await streamed.stream.toBytes();
    final bodyStr = utf8.decode(bodyBytes);

    String patched = bodyStr;
    try {
      final dynamic decoded = jsonDecode(bodyStr);
      if (decoded is Map<String, dynamic>) {
        bool changed = false;
        final choices = decoded['choices'];
        if (choices is List) {
          for (final choice in choices) {
            if (choice is! Map<String, dynamic>) continue;
            final msg = choice['message'];
            if (msg is! Map<String, dynamic>) continue;
            final toolCalls = msg['tool_calls'];
            if (toolCalls is! List) continue;
            for (final tc in toolCalls) {
              if (tc is Map<String, dynamic> && !tc.containsKey('type')) {
                tc['type'] = 'function';
                changed = true;
              }
            }
          }
        }
        if (changed) {
          patched = jsonEncode(decoded);
        }
      }
    } catch (_) {}

    final patchedBytes = utf8.encode(patched);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(patchedBytes),
      streamed.statusCode,
      contentLength: patchedBytes.length,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
