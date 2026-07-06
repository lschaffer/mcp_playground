import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import 'package:llamadart/llamadart.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'weather_tools.dart';

// Resolves the default model storage directory: users/$user/.models
String _getDefaultModelsDir() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return p.join(Directory.current.path, 'models');
  }
  return p.join(home, '.models');
}

// Download helper showing real-time progress percentage in the console
Future<void> _downloadFile(String url, String savePath) async {
  final client = http.Client();
  final request = http.Request('GET', Uri.parse(url));
  final response = await client.send(request);

  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}: Failed to download model');
  }

  final file = File(savePath);
  // Ensure the parent directory exists
  await file.parent.create(recursive: true);
  
  final sink = file.openWrite();
  final contentLength = response.contentLength ?? 0;
  int downloadedBytes = 0;

  print('Downloading Qwen2.5-3B-Instruct model from Hugging Face...');
  await for (final chunk in response.stream) {
    sink.add(chunk);
    downloadedBytes += chunk.length;
    if (contentLength > 0) {
      final pct = (downloadedBytes / contentLength) * 100;
      stdout.write(
        '\rProgress: ${pct.toStringAsFixed(1)}% '
        '(${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / '
        '${(contentLength / (1024 * 1024)).toStringAsFixed(1)} MB)'
      );
    } else {
      stdout.write('\rDownloaded: ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB');
    }
  }

  await sink.close();
  client.close();
  print('\nDownload complete! Saved to: $savePath');
}

// Convert MCP tools schema to llamadart ToolParam format
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

// Map user/assistant/tool messages to LlamaChatMessage history properly
void _populateHistory(ChatSession session, List<ChatMessage> messages) {
  int i = 0;
  while (i < messages.length) {
    final msg = messages[i];

    if (msg.role == ChatRole.user) {
      if (session.history.isNotEmpty &&
          session.history.last.role == LlamaChatRole.tool) {
        session.addMessage(
          const LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: ' '),
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
                rawJson: jsonEncode({
                  'name': tr.toolName ?? 'tool',
                  'arguments': tr.toolArguments ?? const {},
                }),
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
          final resultText = tr.toolResult?.content.map((c) => c.text ?? '').join('\n') ?? tr.content;
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
      final resultText = msg.toolResult?.content.map((c) => c.text ?? '').join('\n') ?? msg.content;
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

// Accumulator to compile streamed tool call chunks
class _ToolCallAccumulator {
  String id = '';
  String name = '';
  String arguments = '';
}

// Register dynamic delegate handlers inside LLMService to route LlmProvider.embedded calls to llamadart
void _registerLlamaDelegates(LlamaEngine engine) {
  LLMService.embeddedHandler = ({
    required LlmConfig config,
    required List<ChatMessage> messages,
    required List<MCPTool> tools,
    String? systemPrompt,
  }) async {
    final session = ChatSession(engine);
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      session.systemPrompt = systemPrompt;
    }
    _populateHistory(session, messages);
    final toolDefs = _convertTools(tools);

    final params = GenerationParams(
      maxTokens: config.maxTokens > 0 ? config.maxTokens : 512,
      temp: config.temperature,
    );

    String text = '';
    await for (final chunk in session.create([], tools: toolDefs, params: params)) {
      if (chunk.choices.isNotEmpty) {
        final content = chunk.choices.first.delta.content;
        if (content != null) {
          text += content;
        }
      }
    }

    final lastHistoryMsg = session.history.lastOrNull;
    final toolCalls = lastHistoryMsg?.parts
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

    return LLMResponse(text: text, toolCalls: toolCalls);
  };

  LLMService.embeddedStreamHandler = ({
    required LlmConfig config,
    required List<ChatMessage> messages,
    required List<MCPTool> tools,
    String? systemPrompt,
  }) {
    final controller = StreamController<LLMStreamChunk>();
    final session = ChatSession(engine);
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      session.systemPrompt = systemPrompt;
    }
    _populateHistory(session, messages);
    final toolDefs = _convertTools(tools);

    final params = GenerationParams(
      maxTokens: config.maxTokens > 0 ? config.maxTokens : 512,
      temp: config.temperature,
    );

    runZonedGuarded(() async {
      String fullText = '';
      final toolCallAccumulators = <int, _ToolCallAccumulator>{};
      await for (final chunk in session.create([], tools: toolDefs, params: params)) {
        if (chunk.choices.isNotEmpty) {
          final delta = chunk.choices.first.delta;
          final content = delta.content;
          if (content != null && content.isNotEmpty) {
            fullText += content;
            controller.add(LLMStreamChunk(textDelta: content));
          }
          if (delta.toolCalls != null) {
            for (final tc in delta.toolCalls!) {
              final acc = toolCallAccumulators.putIfAbsent(tc.index, () => _ToolCallAccumulator());
              if (tc.id != null) acc.id = tc.id!;
              if (tc.function?.name != null) acc.name = tc.function!.name!;
              if (tc.function?.arguments != null) {
                acc.arguments += tc.function!.arguments!;
              }
            }
          }
        }
      }

      final toolCalls = <LLMToolCall>[];
      final sortedIndices = toolCallAccumulators.keys.toList()..sort();
      for (final index in sortedIndices) {
        final acc = toolCallAccumulators[index]!;
        Map<String, dynamic> args = {};
        try {
          if (acc.arguments.isNotEmpty) {
            args = Map<String, dynamic>.from(jsonDecode(acc.arguments) as Map);
          }
        } catch (_) {}
        toolCalls.add(
          LLMToolCall(
            id: acc.id.isNotEmpty ? acc.id : 'call_${index}',
            name: acc.name,
            arguments: args,
          ),
        );
      }

      controller.add(LLMStreamChunk(
        textDelta: '',
        isDone: true,
        finalResponse: LLMResponse(text: fullText, toolCalls: toolCalls),
      ));
      await controller.close();
    }, (error, stack) {
      if (!controller.isClosed) {
        controller.addError(error, stack);
        controller.close();
      }
    });

    return controller.stream;
  };
}

Future<void> main() async {
  // 1. Read config.yaml if it exists
  String modelDir = '';
  String modelUrl = 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf';
  String modelName = 'Qwen2.5-3B-Instruct-Q4_K_M.gguf';

  final configFile = File('config.yaml');
  if (await configFile.exists()) {
    try {
      final content = await configFile.readAsString();
      final doc = loadYaml(content);
      if (doc is Map) {
        modelDir = (doc['model_dir'] as String? ?? '').trim();
        modelUrl = (doc['model_url'] as String? ?? modelUrl).trim();
        modelName = (doc['model_name'] as String? ?? modelName).trim();
      }
    } catch (e) {
      print('Warning: Failed to parse config.yaml, using defaults. Error: $e');
    }
  }

  // Fallback to default user models directory
  if (modelDir.isEmpty) {
    modelDir = _getDefaultModelsDir();
  }

  final fullModelPath = p.join(modelDir, modelName);

  // 2. Download model file if not present
  final modelFile = File(fullModelPath);
  if (!await modelFile.exists()) {
    print('Model file not found at: $fullModelPath');
    try {
      await _downloadFile(modelUrl, fullModelPath);
    } catch (e) {
      print('Error downloading model file: $e');
      exit(1);
    }
  } else {
    print('Model file already exists and loaded from: $fullModelPath');
  }

  // 3. Initialize Llama Engine and load model
  print('Loading embedded GGUF model into memory (this can take a few seconds)...');
  LlamaEngine.configureLogging(level: LlamaLogLevel.warn);
  final backend = LlamaBackend();
  final engine = LlamaEngine(backend);

  try {
    await engine.loadModel(
      fullModelPath,
      modelParams: ModelParams(
        contextSize: 2048,
        gpuLayers: 0, // Force CPU execution to prevent Vulkan/GPU Out-Of-Memory errors
      ),
    );
    print('Model successfully loaded!');
  } catch (e) {
    print('Error loading model with llamadart: $e');
    exit(1);
  }

  // 4. Register llamadart delegates with LLMService
  _registerLlamaDelegates(engine);

  // 5. Initialize McpAgentEngine and register Weather Tools
  final defaultLlm = LlmConfig(
    provider: LlmProvider.embedded,
    model: modelName,
    apiKey: '',
    useStreaming: true,
  );

  final List<McpLocalTool> weatherTools = [
    GetCurrentWeatherTool(),
    GetHourlyForecastTool(),
    GetDailyForecastTool(),
    GeocodeWeatherCityTool(),
  ];

  final agent = Agent(
    key: 'embedded_weather_agent',
    name: 'Embedded Weather Assistant',
    llmConfig: defaultLlm,
    systemPrompt: 'You are an AI assistant specialized in weather forecasts. Use the weather tools to answer user questions.',
    prompts: [
      const SubPromptStep(
        text: 'show next 24 hours forecast from Rome,Italy',
      ),
    ],
    dartTools: weatherTools,
  );

  final agentEngine = McpAgentEngine();
  agentEngine.setAgents([agent]);

  // 6. Listen to Agent events to stream final text and tool calls to terminal
  final subscription = agentEngine.agentEvents.listen((event) {
    if (event is AgentLogEvent) {
      print('\n[LOG] ${event.message}');
    } else if (event is AgentToolResultEvent) {
      print('\n[TOOL CALL] ${event.toolName}');
      print('Result: ${event.result.length > 500 ? "${event.result.substring(0, 500)}..." : event.result}');
    } else if (event is AgentTextChunkEvent) {
      stdout.write(event.chunk);
    } else if (event is AgentAssistantResultEvent) {
      // Empty line for spacing
      print('');
    } else if (event is AgentFinalResultEvent) {
      print('\n=== Final Complete Response ===');
      print(event.response);
    } else if (event is AgentErrorEvent) {
      print('\n[ERROR] ${event.error}');
    }
  });

  print('\nRunning Weather Forecast Agent with prompt: "show next 24 hours forecast from Rome,Italy"...\n');

  try {
    final stream = agentEngine.runAsync(agent.key);
    await stream.firstWhere(
      (event) => event is AgentFinalResultEvent || event is AgentErrorEvent,
    );
  } finally {
    await subscription.cancel();
    await engine.unloadModel();
    await agentEngine.dispose();
  }
}
