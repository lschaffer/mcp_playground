import 'dart:convert';
import 'dart:io';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'package:yaml/yaml.dart';

// ═══════════════════════════════════════════════════════════════
// MCP CLI — Interactive AI Agent with MCP tool support
//
// Configuration files (YAML with ${ENV_VAR} substitution):
//   llm.yaml              — LLM provider, model, API key, system prompt
//   extern_mcp_tools.yaml — Node.js / Python MCP subprocess servers
//
// Commands:
//   /bye, /exit, Ctrl-X  — quit
//   /tools                — list available tools
//   /clear                — clear conversation context
//   /system               — show system prompt
//
// Usage:
//   cd examples/dart/cli_example
//   dart run bin/main.dart [--llm llm.yaml] [--tools extern_mcp_tools.yaml]
// ═══════════════════════════════════════════════════════════════

const _helpText = '''
Commands:
  /bye, /exit, Ctrl-X  Quit the application
  /tools               List available MCP tools
  /clear               Clear conversation history
  /system              Show the system prompt
  /help, /?            Show this help
''';

Future<void> main(List<String> args) async {
  // ── Parse CLI arguments ──────────────────────────────────────
  String llmPath = 'llm.yaml';
  String toolsPath = 'extern_mcp_tools.yaml';

  for (int i = 0; i < args.length; i++) {
    if ((args[i] == '--llm' || args[i] == '-l') && i + 1 < args.length) {
      llmPath = args[++i];
    } else if ((args[i] == '--tools' || args[i] == '-t') &&
        i + 1 < args.length) {
      toolsPath = args[++i];
    }
  }

  // ── Load configuration ───────────────────────────────────────
  final llmConfig = _loadLlmConfig(llmPath);
  if (llmConfig == null) {
    stderr.writeln('ERROR: Could not load LLM config from "$llmPath".');
    stderr.writeln(
      'Create an llm.yaml file (see sample in the cli_example directory).',
    );
    exit(1);
  }

  if (!llmConfig.isConfigured) {
    stderr.writeln('ERROR: LLM is not fully configured.');
    stderr.writeln('  Provider : ${llmConfig.provider.displayName}');
    stderr.writeln('  Model    : ${llmConfig.model}');
    if (llmConfig.apiKey.isEmpty && llmConfig.provider != LlmProvider.ollama) {
      stderr.writeln('  API Key  : *** MISSING ***');
    }
    exit(1);
  }

  final systemPrompt = _loadSystemPrompt(llmPath);
  final localServers = _loadMcpServers(toolsPath);

  // ── Welcome banner ───────────────────────────────────────────
  print('');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║              MCP CLI — Interactive Agent                ║');
  print('╠══════════════════════════════════════════════════════════╣');
  print('║ Provider : ${llmConfig.provider.displayName.padRight(44)}║');
  print('║ Model    : ${llmConfig.model.padRight(44)}║');
  if (localServers.isNotEmpty) {
    print(
      '║ MCP tools: ${localServers.length} server(s)${''.padRight(34 - localServers.length.toString().length - 10)}║',
    );
  }
  print('║ Type /bye to exit, /help for commands                  ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  // ── Connect MCP servers once ─────────────────────────────────
  final mcpManager = MultiMCPManager();
  final allTools = <MCPTool>[];

  for (final server in localServers) {
    if (!server.enabled) continue;
    try {
      final client = LocalMCPClient(
        server,
        logCallback: (msg, {bool isError = false}) {
          if (isError) stderr.writeln('[MCP:${server.name}] $msg');
        },
      );
      final clientDef = MCPClientDef(
        name: server.id,
        client: client,
        displayName: server.name,
      );
      mcpManager.registerClient(clientDef);
      await client.connect();
      print('Connected to MCP server: ${server.name}');
    } catch (e) {
      print('Warning: Failed to connect to "${server.name}": $e');
    }
  }

  allTools.addAll(mcpManager.availableTools);
  if (allTools.isNotEmpty) {
    print('Available tools: ${allTools.map((t) => t.name).join(', ')}');
  }
  print('');

  // ── Conversation state ───────────────────────────────────────
  final conversation = <ChatMessage>[];

  // ── Interactive loop ─────────────────────────────────────────
  print('Enter your message (empty line to skip):');
  print('');

  while (true) {
    stdout.write('> ');
    final rawInput = stdin.readLineSync();

    // null = EOF or Ctrl-X (on some terminals)
    if (rawInput == null) break;

    final input = rawInput.trim();
    if (input.isEmpty) continue;

    // Handle commands
    if (input == '/bye' || input == '/exit') break;
    if (input == '/help' || input == '/?') {
      print(_helpText);
      continue;
    }
    if (input == '/tools') {
      if (allTools.isEmpty) {
        print('No MCP tools connected.');
      } else {
        print('Available tools (${allTools.length}):');
        for (final t in allTools) {
          final desc = t.description ?? '(no description)';
          print('  • ${t.name} — $desc');
        }
      }
      print('');
      continue;
    }
    if (input == '/clear') {
      conversation.clear();
      print('Conversation cleared.');
      print('');
      continue;
    }
    if (input == '/system') {
      print('System prompt:');
      print('───');
      print(systemPrompt);
      print('───');
      print('');
      continue;
    }

    print('');

    // ── Build agent for this turn ───────────────────────────
    final agent = Agent(
      key: 'cli_agent',
      name: 'CLI Agent',
      llmConfig: llmConfig,
      systemPrompt: systemPrompt,
      prompts: [SubPromptStep(text: input)],
      localServers: [], // already connected via mcpManager
    );

    final engine = McpAgentEngine();
    engine.setAgents([agent]);

    try {
      // Listen to stream events for real-time output
      final subscription = engine.agentEvents.listen((event) {
        switch (event) {
          case AgentLogEvent(:final message):
            // Skip verbose internal logs in interactive mode
            if (message.startsWith('Agent') ||
                message.startsWith('User prompt') ||
                message.startsWith('Registered')) {
              break;
            }
            print('[log] $message');
          case AgentToolResultEvent(
            :final toolName,
            :final parameters,
            :final result,
          ):
            print('┌─ TOOL CALL ──────────────────────────────');
            print('│ Tool    : $toolName');
            print('│ Args    : ${_truncate(jsonEncode(parameters), 200)}');
            print('├─ RESULT ─────────────────────────────────');
            for (final line in result.split('\n').take(20)) {
              print('│ $line');
            }
            if (result.split('\n').length > 20) {
              print('│ ... (${result.split('\n').length} lines total)');
            }
            print('└──────────────────────────────────────────');
          case AgentAssistantResultEvent(:final response):
            print('');
            print(response);
            print('');
          case AgentErrorEvent(:final error):
            print('');
            print('ERROR: $error');
            print('');
          case AgentFinalResultEvent():
            break; // handled separately
        }
      });

      await engine.run(agent.key, mcpManager: mcpManager);
      await subscription.cancel();
    } catch (e) {
      print('ERROR: $e');
    } finally {
      await engine.dispose();
    }

    // Add turn to conversation (for potential future context reuse)
    conversation.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: input,
        role: ChatRole.user,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ── Cleanup ──────────────────────────────────────────────────
  print('');
  print('Disconnecting MCP servers...');
  await mcpManager.disconnectAll();
  mcpManager.dispose();
  print('Goodbye!');
}

// ═══════════════════════════════════════════════════════════════
// Config loaders
// ═══════════════════════════════════════════════════════════════

/// Cached env vars loaded from .env file.
Map<String, String>? _dotEnvCache;

/// Load .env file from the current directory (or walk up to find it).
Map<String, String> _loadDotEnv() {
  if (_dotEnvCache != null) return _dotEnvCache!;

  final env = <String, String>{};
  try {
    // Walk up from current directory to find .env
    var dir = Directory.current;
    for (int i = 0; i < 5; i++) {
      final envFile = File('${dir.path}/.env');
      if (envFile.existsSync()) {
        for (final line in envFile.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eq = trimmed.indexOf('=');
          if (eq == -1) continue;
          final key = trimmed.substring(0, eq).trim();
          final val = trimmed.substring(eq + 1).trim();
          env[key] = val;
        }
        break;
      }
      dir = dir.parent;
    }
  } catch (_) {}
  _dotEnvCache = env;
  return env;
}

/// Load LlmConfig from a YAML file with ${ENV_VAR} substitution.
LlmConfig? _loadLlmConfig(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final raw = file.readAsStringSync();
    final resolved = _substituteEnv(raw);
    final yaml = loadYaml(resolved) as YamlMap?;
    if (yaml == null) return null;

    final providerStr =
        (yaml['provider'] as String?)?.toLowerCase() ?? 'openai';
    final provider = switch (providerStr) {
      'claude' || 'anthropic' => LlmProvider.claude,
      'gemini' || 'google' => LlmProvider.gemini,
      'ollama' => LlmProvider.ollama,
      'openai_compatible' || 'openaicompatible' => LlmProvider.openaiCompatible,
      'mistral' => LlmProvider.mistral,
      _ => LlmProvider.openai,
    };

    return LlmConfig(
      provider: provider,
      model: (yaml['model'] as String?) ?? 'gpt-4o-mini',
      apiKey: (yaml['api_key'] as String?) ?? '',
      baseUrl: (yaml['base_url'] as String?) ?? '',
      temperature: (yaml['temperature'] as num?)?.toDouble() ?? 0.2,
      maxTokens: (yaml['max_tokens'] as int?) ?? 0,
      topP: (yaml['top_p'] as num?)?.toDouble(),
      topK: yaml['top_k'] as int?,
      seed: yaml['seed'] as int?,
    );
  } catch (e) {
    stderr.writeln('Error parsing $path: $e');
    return null;
  }
}

/// Load the system prompt from llm.yaml (or use a default).
String _loadSystemPrompt(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return _defaultSystemPrompt();
    final raw = file.readAsStringSync();
    final resolved = _substituteEnv(raw);
    final yaml = loadYaml(resolved) as YamlMap?;
    final prompt = yaml?['system_prompt'] as String?;
    return (prompt != null && prompt.trim().isNotEmpty)
        ? prompt.trim()
        : _defaultSystemPrompt();
  } catch (_) {
    return _defaultSystemPrompt();
  }
}

String _defaultSystemPrompt() =>
    'You are a helpful AI assistant. Use available tools when needed '
    'to answer user questions accurately. Be concise.';

/// Load MCP server configurations from YAML.
List<McpServerConfig> _loadMcpServers(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return [];
    final raw = file.readAsStringSync();
    final resolved = _substituteEnv(raw);
    final yaml = loadYaml(resolved) as YamlMap?;
    final serversList = yaml?['servers'] as YamlList?;
    if (serversList == null) return [];

    return serversList.whereType<YamlMap>().map((s) {
      final localEnv = s['env'] as YamlMap?;
      return McpServerConfig(
        id: (s['id'] as String?) ?? 'mcp_${serversList.indexOf(s)}',
        name: (s['name'] as String?) ?? 'Unnamed',
        url: (s['url'] as String?) ?? '',
        isLocal: s['is_local'] as bool? ?? false,
        localType: s['local_type'] as String?,
        localInstallMethod: s['local_install_method'] as String?,
        localPackage: s['local_package'] as String?,
        localCommand: s['local_command'] as String?,
        customLaunchCommand: s['custom_launch_command'] as String?,
        enabled: s['enabled'] as bool? ?? true,
        localEnvVars: localEnv?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
    }).toList();
  } catch (e) {
    stderr.writeln('Warning: Could not parse $path: $e');
    return [];
  }
}

/// Replace ${VAR_NAME} with values from .env file first, then system env vars.
String _substituteEnv(String input) {
  final dotEnv = _loadDotEnv();
  final envPattern = RegExp(r'\$\{([^}]+)\}');
  return input.replaceAllMapped(envPattern, (m) {
    final varName = m.group(1)!;
    // .env file takes priority over system environment
    return dotEnv[varName] ?? Platform.environment[varName] ?? '';
  });
}

String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}...';
}
