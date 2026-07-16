import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'package:universal_io/io.dart';

final Map<String, String> _env = {};

Future<void> _loadEnv() async {
  try {
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

  // ── 1. Set up temp directory with dummy files ──────────────────
  final workingDir = r'C:\temp';
  final tempDir = Directory(workingDir);
  if (!await tempDir.exists()) {
    try {
      await tempDir.create(recursive: true);
      await File('$workingDir\\small.txt').writeAsString('Hello');
      await File('$workingDir\\medium.log').writeAsString('A' * 1024);
      await File('$workingDir\\large.bin').writeAsString('B' * 10240);
      await File('$workingDir\\exclude.hex').writeAsString('C' * 50000);
      await File('$workingDir\\huge.db').writeAsString('D' * 102400);
    } catch (e) {
      print('Warning: Failed to setup dummy files in $workingDir: $e');
    }
  }

  // ── 2. Load and parse skill.md ─────────────────────────────────
  final skillFile = File('skill.md');
  if (!await skillFile.exists()) {
    print('ERROR: skill.md not found in current directory.');
    print('Run this example from: examples/dart/local_filesystem_example/');
    exit(1);
  }

  final skillContent = await skillFile.readAsString();
  final manifest = SkillImporter().parseSkillMd(skillContent);

  print('Loaded skill: ${manifest.name} v${manifest.version}');
  print('  Description: ${manifest.description}');
  print(
    '  Capabilities: ${manifest.tools.map((t) => t.capability ?? t.name).join(', ')}',
  );
  print('  Prompt steps: ${manifest.promptSteps.length}');

  // ── 3. Build LLM config from environment ───────────────────────
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
  final apiKey =
      _env['LLM_API_KEY'] ??
      _env['LLM_KEY'] ??
      Platform.environment['OPENAI_API_KEY'] ??
      'your-openai-api-key';

  final llmConfig = LlmConfig(
    provider: provider,
    model: model,
    apiKey: apiKey,
    baseUrl: url,
    temperature: 0.2,
  );

  // ── 4. Map skill capabilities to runtime server configs ────────
  // The skill declares "filesystem" as a required capability.
  // The host provides the actual MCP server implementation.
  final serverOverrides = <String, McpServerConfig>{
    'filesystem': McpServerConfig(
      id: 'filesystem',
      name: 'Filesystem',
      url: workingDir,
      isLocal: true,
      localType: 'nodejs',
      localInstallMethod: 'npx',
      localPackage: '@modelcontextprotocol/server-filesystem',
      enabled: true,
    ),
  };

  // ── 5. Register agent from manifest (engine handles the rest) ──
  final engine = McpAgentEngine();
  engine.registerAgentFromManifest(
    manifest,
    llmConfig: llmConfig,
    serverOverrides: serverOverrides,
  );

  // ── 6. Execute ─────────────────────────────────────────────────
  try {
    print('\nStarting agent "${manifest.name}" using skill.md workflow...\n');

    final subscription = engine.agentEvents.listen((event) {
      if (event is AgentLogEvent) {
        print('[LOG] ${event.message}');
      } else if (event is AgentToolResultEvent) {
        final preview = event.result.length > 300
            ? '${event.result.substring(0, 300)}...'
            : event.result;
        print('[TOOL RESULT] ${event.toolName}: $preview');
      } else if (event is AgentAssistantResultEvent) {
        print('[ASSISTANT] ${event.response}');
      } else if (event is AgentFinalResultEvent) {
        print('\n=== FINAL RESULT ===');
        print(event.response);
      } else if (event is AgentErrorEvent) {
        print('[ERROR] ${event.error}');
      }
    });

    final stream = engine.runAsync(manifest.name);
    await stream.firstWhere(
      (event) => event is AgentFinalResultEvent || event is AgentErrorEvent,
    );

    await subscription.cancel();
  } finally {
    await engine.dispose();
  }
}
