import 'package:mcp_playground_dart/mcp_playground_dart.dart';

Future<void> main() async {
  // 1. Configure the LLM
  final llmConfig = LlmConfig(
    provider: LlmProvider.openai,
    model: 'gpt-4o-mini',
    apiKey: 'your-openai-api-key',
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
    print('Running agent...');
    await engine.run(
      agent.key,
      onLog: (msg) => print('[LOG] $msg'),
      onToolResult: (name, params, result) => print('Tool $name returned: $result'),
      onAssistantResult: (prompt, response) => print('Assistant: $response'),
      onFinalResult: (response) {
        print('\n=== FINAL RESPONSE ===');
        print(response);
      },
    );
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
