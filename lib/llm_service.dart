import 'dart:async';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:ollama_dart/ollama_dart.dart' as ollama;
import 'package:uuid/uuid.dart';
import 'models.dart';

class LLMToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const LLMToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

class LLMResponse {
  final String text;
  final List<LLMToolCall> toolCalls;

  const LLMResponse({
    required this.text,
    this.toolCalls = const [],
  });
}

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
  static Future<LLMResponse> _generateOpenAI(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = openai.OpenAIClient(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl.trim().isNotEmpty ? config.baseUrl : null,
    );

    try {
      final List<openai.ChatCompletionMessage> openAiMsgs = [];

      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        openAiMsgs.add(
          openai.ChatCompletionMessage.system(
            content: systemPrompt,
          ),
        );
      }

      for (final msg in messages) {
        switch (msg.role) {
          case ChatRole.user:
            openAiMsgs.add(
              openai.ChatCompletionMessage.user(
                content: openai.ChatCompletionUserMessageContent.string(
                  msg.content,
                ),
              ),
            );
          case ChatRole.assistant:
            if (msg.type == MessageType.toolCall) {
              openAiMsgs.add(
                openai.ChatCompletionMessage.assistant(
                  toolCalls: [
                    openai.ChatCompletionMessageToolCall(
                      id: msg.id,
                      type: openai.ChatCompletionMessageToolCallType.function,
                      function: openai.ChatCompletionMessageFunctionCall(
                        name: msg.toolName ?? '',
                        arguments: jsonEncode(msg.toolArguments ?? {}),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              openAiMsgs.add(
                openai.ChatCompletionMessage.assistant(
                  content: msg.content,
                ),
              );
            }
          case ChatRole.tool:
            openAiMsgs.add(
              openai.ChatCompletionMessage.tool(
                toolCallId: msg.id,
                content: jsonEncode(msg.toolResult?.toJson() ?? {}),
              ),
            );
          case ChatRole.system:
            openAiMsgs.add(
              openai.ChatCompletionMessage.system(
                content: msg.content,
              ),
            );
        }
      }

      final List<openai.ChatCompletionTool> openAiTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          openAiTools.add(
            openai.ChatCompletionTool(
              type: openai.ChatCompletionToolType.function,
              function: openai.FunctionObject(
                name: t.name,
                description: t.description ?? '',
                parameters: t.inputSchema ?? {'type': 'object', 'properties': {}},
              ),
            ),
          );
        }
      }

      final response = await client.createChatCompletion(
        request: openai.CreateChatCompletionRequest(
          model: openai.ChatCompletionModel.model(
            openai.ChatCompletionModels.values.firstWhere(
              (m) => m.name == config.model,
              orElse: () => openai.ChatCompletionModels.gpt4oMini,
            ),
          ),
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
          if (tc.type == openai.ChatCompletionMessageToolCallType.function) {
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

  // ═══════════════════════════════════════════════════════════════
  // 2. Anthropic Claude Adapter
  // ═══════════════════════════════════════════════════════════════
  static Future<LLMResponse> _generateAnthropic(
    LlmConfig config,
    List<ChatMessage> messages,
    List<MCPTool> tools,
    String? systemPrompt,
  ) async {
    final client = anthropic.AnthropicClient(apiKey: config.apiKey);

    try {
      final List<anthropic.Message> anthropicMsgs = [];

      for (final msg in messages) {
        if (msg.role == ChatRole.system) continue;

        switch (msg.role) {
          case ChatRole.user:
            anthropicMsgs.add(
              anthropic.Message(
                role: anthropic.MessageRole.user,
                content: anthropic.MessageContent.text(msg.content),
              ),
            );
          case ChatRole.assistant:
            if (msg.type == MessageType.toolCall) {
              anthropicMsgs.add(
                anthropic.Message(
                  role: anthropic.MessageRole.assistant,
                  content: anthropic.MessageContent.blocks([
                    anthropic.Block.toolUse(
                      id: msg.id,
                      name: msg.toolName ?? '',
                      input: msg.toolArguments ?? {},
                    ),
                  ]),
                ),
              );
            } else {
              anthropicMsgs.add(
                anthropic.Message(
                  role: anthropic.MessageRole.assistant,
                  content: anthropic.MessageContent.text(msg.content),
                ),
              );
            }
          case ChatRole.tool:
            anthropicMsgs.add(
              anthropic.Message(
                role: anthropic.MessageRole.user,
                content: anthropic.MessageContent.blocks([
                  anthropic.Block.toolResult(
                    toolUseId: msg.id,
                    content: anthropic.ToolResultBlockContent.text(
                      jsonEncode(msg.toolResult?.toJson() ?? {}),
                    ),
                  ),
                ]),
              ),
            );
          default:
            break;
        }
      }

      final List<anthropic.Tool> anthropicTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          anthropicTools.add(
            anthropic.Tool.custom(
              name: t.name,
              description: t.description ?? '',
              inputSchema: t.inputSchema ?? {'type': 'object', 'properties': {}},
            ),
          );
        }
      }

      final response = await client.createMessage(
        request: anthropic.CreateMessageRequest(
          model: anthropic.Model.model(
            anthropic.Models.values.firstWhere(
              (m) => m.name == config.model,
              orElse: () => anthropic.Models.claude35SonnetLatest,
            ),
          ),
          messages: anthropicMsgs,
          system: systemPrompt != null && systemPrompt.trim().isNotEmpty
              ? anthropic.CreateMessageRequestSystem.text(systemPrompt)
              : null,
          tools: anthropicTools.isNotEmpty ? anthropicTools : null,
          temperature: config.temperature,
          maxTokens: config.maxTokens > 0 ? config.maxTokens : 4096,
        ),
      );

      final textBuffer = StringBuffer();
      final toolCalls = <LLMToolCall>[];

      for (final block in response.content.blocks) {
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
    final List<gemini.Tool> geminiTools = [];
    if (tools.isNotEmpty && config.useNativeToolCall) {
      final declarations = <gemini.FunctionDeclaration>[];
      for (final t in tools) {
        declarations.add(
          gemini.FunctionDeclaration(
            t.name,
            t.description ?? '',
            _sanitizeGeminiSchema(t.inputSchema),
          ),
        );
      }
      geminiTools.add(gemini.Tool(functionDeclarations: declarations));
    }

    final model = gemini.GenerativeModel(
      model: config.model.trim().isNotEmpty ? config.model : 'gemini-2.5-flash',
      apiKey: config.apiKey,
      systemInstruction: systemPrompt != null && systemPrompt.trim().isNotEmpty
          ? gemini.Content.system(systemPrompt)
          : null,
      generationConfig: gemini.GenerationConfig(
        temperature: config.temperature,
        maxOutputTokens: config.maxTokens > 0 ? config.maxTokens : null,
        topP: config.topP,
        topK: config.topK,
        candidateCount: 1,
      ),
      tools: geminiTools.isNotEmpty ? geminiTools : null,
    );

    final List<gemini.Content> contentList = [];
    for (final msg in messages) {
      if (msg.role == ChatRole.system) continue;

      switch (msg.role) {
        case ChatRole.user:
          contentList.add(
            gemini.Content.text(msg.content),
          );
        case ChatRole.assistant:
          if (msg.type == MessageType.toolCall) {
            contentList.add(
              gemini.Content('model', [
                gemini.FunctionCall(
                  msg.toolName ?? '',
                  msg.toolArguments ?? {},
                )
              ]),
            );
          } else {
            contentList.add(
              gemini.Content.model([gemini.TextPart(msg.content)]),
            );
          }
        case ChatRole.tool:
          contentList.add(
            gemini.Content('function', [
              gemini.FunctionResponse(
                msg.toolName ?? '',
                msg.toolResult?.toJson() ?? {},
              )
            ]),
          );
        default:
          break;
      }
    }

    final response = await model.generateContent(contentList);
    final text = response.text ?? '';
    final toolCalls = <LLMToolCall>[];

    final functionCalls = response.functionCalls;
    if (functionCalls.isNotEmpty) {
      for (final fc in functionCalls) {
        toolCalls.add(
          LLMToolCall(
            id: const Uuid().v4(),
            name: fc.name,
            arguments: Map<String, dynamic>.from(fc.args),
          ),
        );
      }
    }

    return LLMResponse(text: text, toolCalls: toolCalls);
  }

  static gemini.Schema _sanitizeGeminiSchema(Map<String, dynamic>? schema) {
    if (schema == null) return gemini.Schema.string();
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
        return gemini.Schema.object(
          description: desc,
          properties: propsMap,
          requiredProperties: requiredProps,
        );
      case 'array':
        final items = schema['items'];
        final itemsSchema = items is Map
            ? _sanitizeGeminiSchema(Map<String, dynamic>.from(items))
            : gemini.Schema.string();
        return gemini.Schema.array(description: desc, items: itemsSchema);
      case 'integer':
        return gemini.Schema.integer(description: desc);
      case 'number':
        return gemini.Schema.number(description: desc);
      case 'boolean':
        return gemini.Schema.boolean(description: desc);
      default:
        return gemini.Schema.string(description: desc);
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
    final client = ollama.OllamaClient(
      baseUrl: config.baseUrl.trim().isNotEmpty
          ? config.baseUrl
          : 'http://localhost:11434/api',
    );

    try {
      final List<ollama.Message> ollamaMsgs = [];

      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        ollamaMsgs.add(
          ollama.Message(
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
          ollama.Message(
            role: role,
            content: msg.content,
            toolCalls: toolCalls,
          ),
        );
      }

      final List<ollama.Tool> ollamaTools = [];
      if (tools.isNotEmpty && config.useNativeToolCall) {
        for (final t in tools) {
          ollamaTools.add(
            ollama.Tool(
              type: ollama.ToolType.function,
              function: ollama.ToolFunction(
                name: t.name,
                description: t.description ?? '',
                parameters: t.inputSchema ?? {'type': 'object', 'properties': {}},
              ),
            ),
          );
        }
      }

      final response = await client.generateChatCompletion(
        request: ollama.GenerateChatCompletionRequest(
          model: config.model,
          messages: ollamaMsgs,
          tools: ollamaTools.isNotEmpty ? ollamaTools : null,
          options: ollama.RequestOptions(
            temperature: config.temperature,
            numPredict: config.maxTokens > 0 ? config.maxTokens : null,
            seed: config.seed,
          ),
        ),
      );

      final answer = response.message.content;
      final toolCalls = <LLMToolCall>[];

      if (response.message.toolCalls != null && response.message.toolCalls!.isNotEmpty) {
        for (final tc in response.message.toolCalls!) {
          toolCalls.add(
            LLMToolCall(
              id: const Uuid().v4(),
              name: tc.function?.name ?? '',
              arguments: tc.function?.arguments ?? {},
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
