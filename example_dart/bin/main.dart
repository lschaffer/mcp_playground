import 'dart:convert';
import 'dart:io';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'package:mcp_playground_shared_dart_tools/shared_dart_tools.dart';

// ═══════════════════════════════════════════════════════════════
// Pure Dart CLI Example — Weather Agent
//
// Demonstrates:
//  - Loading LLM API key from a .env file
//  - Creating a multi-step Agent with the McpAgentEngine
//  - Registering pure-Dart weather tools from shared_dart_tools
//  - Implementing all callbacks: onLog, onToolResult,
//    onAssistantResult, onError, onFinalResult
//  - Multi-step prompt: geocode Rome → 24h forecast
//
// Usage:  cd example_dart && dart run bin/main.dart
// ═══════════════════════════════════════════════════════════════

Future<void> main() async {
  // ── 1. Load .env ──────────────────────────────────────────────
  final env = _loadEnv();
  final provider = env['LLM_PROVIDER']?.toLowerCase() ?? 'openai';
  final apiKey = env['LLM_API_KEY'] ?? '';
  final model = env['LLM_MODEL'] ?? 'gpt-4o-mini';
  final baseUrl = env['LLM_URL'] ?? '';

  print('╔══════════════════════════════════════════════════╗');
  print('║     Pure Dart MCP Agent — Weather Demo          ║');
  print('╚══════════════════════════════════════════════════╝');
  print('');
  print('Configuration:');
  print('  Provider : $provider');
  print('  Model    : $model');
  if (baseUrl.isNotEmpty) print('  Base URL : $baseUrl');
  print('');

  // ── 2. Build LlmConfig ───────────────────────────────────────
  final llmProvider = _parseProvider(provider);
  final llmConfig = LlmConfig(
    provider: llmProvider,
    model: model,
    apiKey: apiKey,
    baseUrl: baseUrl,
  );

  if (!llmConfig.isConfigured) {
    stderr.writeln(
      'ERROR: LLM not configured. Set LLM_PROVIDER, LLM_API_KEY, '
      'and LLM_MODEL in .env',
    );
    exit(1);
  }

  // ── 3. Create weather tools ──────────────────────────────────
  final tools = <McpLocalTool>[
    GeocodeWeatherCityTool(),
    GetHourlyForecastTool(),
  ];

  print('Registered ${tools.length} tools:');
  for (final t in tools) {
    print('  • ${t.name} — ${t.description.split('.').first}.');
  }
  print('');

  // ── 4. Build the Agent ───────────────────────────────────────
  final agent = Agent(
    key: 'weather_agent',
    name: 'Weather Expert',
    llmConfig: llmConfig,
    systemPrompt:
        'You are a weather tool expert. Use the tools if needed. '
        'Always use geocode_weather_city first to resolve city names to '
        'coordinates (latitude/longitude), then call get_hourly_forecast '
        'with those coordinates. Present the forecast data clearly.',
    prompts: [
      // Step 1: resolve location
      const SubPromptStep(
        text:
            'Find the coordinates (latitude and longitude) of Rome, Italy '
            'using the geocode_weather_city tool.',
        enabledToolNames: ['geocode_weather_city'],
      ),
      // Step 2: get forecast using the coordinates from step 1
      const SubPromptStep(
        text:
            'Now fetch the next 24-hour forecast using get_hourly_forecast. '
            'Use the latitude and longitude from the previous step.\n\n'
            'Previous geocode result:\n\${tool_result}',
      ),
    ],
    dartTools: tools,
  );

  // ── 5. Create engine & set agent ─────────────────────────────
  final engine = McpAgentEngine(enableLogging: true);
  engine.setAgents([agent]);

  print('── Agent execution starting ──');
  print('');

  // ── 6. Run with all callbacks ────────────────────────────────
  try {
    final finalResponse = await engine.run(
      agent.key,
      onLog: (msg) {
        // ── onLog callback ──────────────────────────────────
        print('[LOG] $msg');
      },
      onToolResult: (toolName, parameters, result) {
        // ── onToolResult callback ───────────────────────────
        print('');
        print('┌── TOOL RESULT: $toolName ──');
        print('│ Parameters: ${_truncate(jsonEncode(parameters), 200)}');
        print('│ Result (${result.length} chars):');
        for (final line in result.split('\n').take(15)) {
          print('│   $line');
        }
        if (result.split('\n').length > 15) {
          print(
            '│   ... (truncated, ${result.split('\n').length} lines total)',
          );
        }
        print('└${'─' * 50}');
      },
      onAssistantResult: (prompt, response) {
        // ── onAssistantResult callback ──────────────────────
        print('');
        print('┌── ASSISTANT RESPONSE ──');
        print('│ Prompt: ${_truncate(prompt, 120)}');
        print('│ Response (${response.length} chars):');
        for (final line in response.split('\n').take(10)) {
          print('│   $line');
        }
        if (response.split('\n').length > 10) {
          print('│   ... (truncated)');
        }
        print('└${'─' * 50}');
      },
      onError: (error) {
        // ── onError callback ────────────────────────────────
        print('');
        print('┌── ERROR ──');
        print('│ $error');
        print('└${'─' * 50}');
      },
      onFinalResult: (response) {
        // ── onFinalResult callback ──────────────────────────
        print('');
        print('╔══════════════════════════════════════════════════╗');
        print('║               FINAL RESULT                       ║');
        print('╚══════════════════════════════════════════════════╝');
        print(response);
        print('');
      },
    );

    print('── Agent execution complete ──');
    print('Final response length: ${finalResponse.length} chars');
  } catch (e, stack) {
    stderr.writeln('FATAL: $e');
    stderr.writeln(stack);
    exit(1);
  } finally {
    await engine.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

/// Parse a simple .env file from the current directory.
Map<String, String> _loadEnv() {
  final env = <String, String>{};
  try {
    final file = File('.env');
    if (!file.existsSync()) {
      print('Note: No .env file found — using empty config.');
      return env;
    }
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq == -1) continue;
      final key = trimmed.substring(0, eq).trim();
      final val = trimmed.substring(eq + 1).trim();
      env[key] = val;
    }
  } catch (e) {
    stderr.writeln('Warning: Could not read .env: $e');
  }
  return env;
}

LlmProvider _parseProvider(String name) {
  return switch (name) {
    'openai' => LlmProvider.openai,
    'claude' || 'anthropic' => LlmProvider.claude,
    'gemini' || 'google' => LlmProvider.gemini,
    'ollama' => LlmProvider.ollama,
    'openai_compatible' || 'openaicompatible' => LlmProvider.openaiCompatible,
    'mistral' => LlmProvider.mistral,
    _ => LlmProvider.openai,
  };
}

String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}...';
}
