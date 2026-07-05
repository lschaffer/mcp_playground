import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'package:universal_io/io.dart';

final Map<String, String> _env = {};

Future<void> _loadEnv() async {
  try {
    var dir = Directory.current;
    File? envFile;
    // Walk up to find .env file
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

  // 1. Prepare temp directory for the filesystem tool
  final tempDir = Directory('C:\\temp');
  if (!await tempDir.exists()) {
    try {
      await tempDir.create(recursive: true);
      // Create some dummy files to sort
      await File('C:\\temp\\small.txt').writeAsString('Hello');
      await File('C:\\temp\\medium.log').writeAsString('A' * 1024); // 1 KB
      await File('C:\\temp\\large.bin').writeAsString('B' * 10240); // 10 KB
      await File('C:\\temp\\exclude.hex').writeAsString('C' * 50000); // Should be excluded
      await File('C:\\temp\\huge.db').writeAsString('D' * 102400); // 100 KB
    } catch (e) {
      print('Warning: Failed to setup dummy files in C:\\temp: $e');
    }
  }

  // 2. Load LLM credentials
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

  final llmConfig = LlmConfig(
    provider: provider,
    model: model,
    apiKey: apiKey,
    baseUrl: url,
    temperature: 0.2,
  );

  // 3. Define the Local Filesystem MCP server setup
  final filesystemServer = McpServerConfig(
    id: 'filesystem',
    name: 'Filesystem',
    url: 'C:\\temp',
    isLocal: true,
    localType: 'nodejs',
    localInstallMethod: 'npx',
    localPackage: '@modelcontextprotocol/server-filesystem',
    enabled: true,
  );

  // 4. Create the Agent configuration
  final agent = Agent(
    key: 'filesystem_agent',
    name: 'Filesystem Inspector',
    llmConfig: llmConfig,
    systemPrompt: 'You are an agent with access to the local filesystem. Find, list, and sort files as requested.',
    prompts: [
      const SubPromptStep(
        text: 'list files except .hex with sizes in c:\\temp sort by size desc show the first 5',
      ),
    ],
    localServers: [filesystemServer],
  );

  // 5. Initialize the execution engine
  final engine = McpAgentEngine();
  engine.setAgents([agent]);

  try {
    print('Starting Filesystem Agent execution using stream events...');

    final subscription = engine.agentEvents.listen((event) {
      if (event is AgentLogEvent) {
        print('[LOG] ${event.message}');
      } else if (event is AgentToolResultEvent) {
        print('[TOOL RESULT] ${event.toolName} returned ${event.result.length} characters.');
      } else if (event is AgentAssistantResultEvent) {
        print('[ASSISTANT RESPONSE] ${event.response}');
      } else if (event is AgentFinalResultEvent) {
        print('\n=== FINAL RESULT ===');
        print(event.response);
      } else if (event is AgentErrorEvent) {
        print('[ERROR] ${event.error}');
      }
    });

    // Run agent
    final stream = engine.runAsync(agent.key);

    // Wait for the agent to finish
    await stream.firstWhere(
      (event) => event is AgentFinalResultEvent || event is AgentErrorEvent,
    );

    await subscription.cancel();
  } finally {
    await engine.dispose();
  }
}
