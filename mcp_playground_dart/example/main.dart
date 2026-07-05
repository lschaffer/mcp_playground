import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'dart:io';

final Map<String, String> _env = {};

Future<void> _loadEnv() async {
  try {
    // Check local directory and parent directories for .env
    var dir = Directory.current;
    File? envFile;
    for (int i = 0; i < 5; i++) {
      final file = File('${dir.path}/.env');
      if (await file.exists()) {
        envFile = file;
        break;
      }
      dir = dir.parent;
    }
    if (envFile != null) {
      final content = await envFile.readAsString();
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          _env[key] = val;
        }
      }
    }
  } catch (_) {}
}

Future<void> main() async {
  await _loadEnv();

  final providerStr = _env['LLM_PROVIDER']?.toLowerCase() ?? 'openai';
  var provider = LlmProvider.openai;
  if (providerStr == 'claude') provider = LlmProvider.claude;
  if (providerStr == 'gemini') provider = LlmProvider.gemini;
  if (providerStr == 'ollama') provider = LlmProvider.ollama;
  if (providerStr == 'openai-compatible' || providerStr == 'openaicompatible') {
    provider = LlmProvider.openaiCompatible;
  }
  if (providerStr == 'mistral') provider = LlmProvider.mistral;

  final model = _env['LLM_MODEL'] ?? 'gpt-4o-mini';
  final url = _env['LLM_URL'] ?? '';
  final apiKey = _env['LLM_API_KEY'] ?? _env['LLM_KEY'] ?? Platform.environment['OPENAI_API_KEY'] ?? 'your-openai-api-key';

  // 1. Configure the LLM with extended hyperparameters
  final llmConfig = LlmConfig(
    provider: provider,
    model: model,
    apiKey: apiKey,
    baseUrl: url,
    temperature: 0.7,
    maxTokens: 100,
    topP: 0.9,
    topK: 40,
  );

  // 2. Define a simple inline Dart-native tool
  final timeTool = GetCurrentTimeTool();

  // 3. Create the Agent configuration
  final agent = Agent(
    key: 'time_agent',
    name: 'Time Expert',
    llmConfig: llmConfig,
    systemPrompt: 'You are a helpful assistant with access to local tools.',
    prompts: [
      const SubPromptStep(
        text: 'What is the current time?',
        enabledToolNames: ['get_current_time'],
      ),
    ],
    dartTools: [timeTool],
  );

  // 4. Create the execution engine and run the Agent
  final engine = McpAgentEngine();
  engine.setAgents([agent]);

  try {
    print('--- Running Agent asynchronously using Stream ---');

    // Subscribe to the Agent Event Stream reactively
    final subscription = engine.agentEvents.listen((event) {
      if (event is AgentLogEvent) {
        print('[STREAM LOG] ${event.message}');
      } else if (event is AgentToolResultEvent) {
        print('[STREAM TOOL] ${event.toolName} returned: ${event.result}');
      } else if (event is AgentAssistantResultEvent) {
        print('[STREAM ASSISTANT] ${event.response}');
      } else if (event is AgentFinalResultEvent) {
        print('\n=== STREAM FINAL RESPONSE ===');
        print(event.response);
      } else if (event is AgentErrorEvent) {
        print('[STREAM ERROR] ${event.error}');
      }
    });

    // Start execution asynchronously (returns the stream)
    final stream = engine.runAsync(agent.key);

    // Wait for completion (final response or error event)
    await stream.firstWhere(
      (event) => event is AgentFinalResultEvent || event is AgentErrorEvent,
    );

    await subscription.cancel();
  } finally {
    await engine.dispose();
  }
}

class GetCurrentTimeTool extends McpLocalTool {
  @override
  String get name => 'get_current_time';

  @override
  String get description => 'Returns the current local time.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final now = DateTime.now().toLocal().toString();
    return MCPToolResult(
      content: [MCPContent(type: 'text', text: 'Current local time is $now')],
    );
  }
}
