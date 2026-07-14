import 'dart:io';
import 'dart:async';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'skill_tools.dart';

/// Loads environment variables from a .env file.
///
/// Tries the current directory first, then the project root (../../.env).
Future<Map<String, String>> _loadEnv() async {
  final env = <String, String>{};

  // First, check process environment (highest priority)
  for (final key in ['LLM_PROVIDER', 'LLM_MODEL', 'LLM_URL', 'LLM_API_KEY']) {
    final val = Platform.environment[key];
    if (val != null && val.isNotEmpty) {
      env[key] = val;
    }
  }

  // Walk up directories from cwd to find .env
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final envFile = File('${dir.path}/.env');
    if (await envFile.exists()) {
      final content = await envFile.readAsString();
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final eqIdx = line.indexOf('=');
        if (eqIdx == -1) continue;
        final key = line.substring(0, eqIdx).trim();
        final val = line.substring(eqIdx + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty && !env.containsKey(key)) {
          env[key] = val;
        }
      }
      break;
    }
    dir = dir.parent;
  }

  return env;
}

Future<void> main() async {
  print('═══ MCP Playground — Skill Example ═══');
  print('');

  // 1. Load environment
  final env = await _loadEnv();

  // 2. Read skill.md from the current directory
  final skillFile = File('skill.md');
  if (!await skillFile.exists()) {
    print('ERROR: skill.md not found in current directory.');
    print('Run this example from: examples/dart/skill_example/');
    exit(1);
  }

  final skillContent = await skillFile.readAsString();
  print('✓ Loaded skill.md (${skillContent.length} chars)');

  // 3. Parse the SKILL.md using SkillImporter
  final importer = SkillImporter();
  final SkillManifest manifest;
  try {
    manifest = importer.parseSkillMd(skillContent);
    print('✓ Parsed skill: "${manifest.name}"');
    print('  Description: ${manifest.description}');
    print('  Steps: ${manifest.promptSteps.length}');
    print('  Tools: ${manifest.tools.map((t) => t.name).join(', ')}');
    print('');
  } catch (e) {
    print('ERROR parsing SKILL.md: $e');
    exit(1);
  }

  // 4. Build LLM config from .env
  final providerStr = env['LLM_PROVIDER']?.trim().toLowerCase() ?? '';
  LlmProvider provider;
  switch (providerStr) {
    case 'openai':
      provider = LlmProvider.openai;
    case 'claude':
      provider = LlmProvider.claude;
    case 'gemini':
      provider = LlmProvider.gemini;
    case 'ollama':
      provider = LlmProvider.ollama;
    case 'openai-compatible':
    case 'openaicompatible':
      provider = LlmProvider.openaiCompatible;
    case 'mistral':
      provider = LlmProvider.mistral;
    default:
      print('ERROR: LLM_PROVIDER not set or unrecognized.');
      print('Set it in the project root .env file:');
      print('  LLM_PROVIDER=openai');
      print('  LLM_API_KEY=sk-...');
      print('  LLM_MODEL=gpt-4o-mini');
      exit(1);
  }

  final apiKey = env['LLM_API_KEY'] ?? '';
  final model = env['LLM_MODEL'] ?? '';
  final baseUrl = env['LLM_URL'] ?? '';

  if (apiKey.isEmpty && provider != LlmProvider.ollama) {
    print('ERROR: LLM_API_KEY not set.');
    print('Set it in the project root .env file.');
    exit(1);
  }
  if (model.isEmpty) {
    print('ERROR: LLM_MODEL not set.');
    print('Set it in the project root .env file.');
    exit(1);
  }

  final llmConfig = LlmConfig(
    provider: provider,
    model: model,
    apiKey: apiKey,
    baseUrl: baseUrl,
    temperature: 0.2,
    maxTokens: 4096,
    useNativeToolCall: true,
  );

  print('✓ LLM: ${provider.displayName} / $model');
  print('');

  // 5. Register Dart-native tools
  final List<McpLocalTool> localTools = [WebSearchTool(), HtmlChartTool()];

  print('✓ Registered tools: ${localTools.map((t) => t.name).join(', ')}');
  print('');

  // 6. Convert SKILL.md prompt steps to SubPromptStep list
  final promptSteps = manifest.promptSteps.map((step) {
    return SubPromptStep(
      text: step.text,
      enabledToolNames: step.enabledToolNames,
      stopAfterToolCall: step.stopAfterToolCall,
    );
  }).toList();

  print('Prompt steps:');
  for (var i = 0; i < promptSteps.length; i++) {
    final step = promptSteps[i];
    print(
      '  Step ${i + 1}: "${step.text.length > 80 ? '${step.text.substring(0, 80)}...' : step.text}"',
    );
    if (step.enabledToolNames != null) {
      print('    Tools: ${step.enabledToolNames!.join(', ')}');
    }
    if (step.stopAfterToolCall) {
      print('    [Stop after tool call]');
    }
  }
  print('');

  // 7. Create the Agent
  final agentKey = 'skill_agent';
  final agent = Agent(
    key: agentKey,
    name: manifest.name,
    llmConfig: llmConfig,
    systemPrompt: manifest.systemPrompt,
    prompts: promptSteps,
    dartTools: localTools,
  );

  final agentEngine = McpAgentEngine();
  agentEngine.setAgents([agent]);

  print('═══ Starting Agent Execution ═══');
  print('');

  // 8. Listen to agent events
  final subscription = agentEngine.agentEvents.listen((event) {
    if (event is AgentLogEvent) {
      print('[LOG] ${event.message}');
    } else if (event is AgentToolResultEvent) {
      print('');
      print('┌─ TOOL: ${event.toolName}');
      final result = event.result;
      if (result.length > 1000) {
        print('│ ${result.substring(0, 1000)}...');
      } else {
        for (final line in result.split('\n')) {
          print('│ $line');
        }
      }
      print('└─');
      print('');
    } else if (event is AgentTextChunkEvent) {
      stdout.write(event.chunk);
    } else if (event is AgentAssistantResultEvent) {
      print('');
      print('---');
    } else if (event is AgentFinalResultEvent) {
      print('');
      print('═══ Final Response ═══');
      print(event.response);
      print('═════════════════════');
      print('');
    } else if (event is AgentErrorEvent) {
      print('');
      print('ERROR: ${event.error}');
    }
  });

  // 9. Run the agent
  try {
    final stream = agentEngine.runAsync(agentKey);
    await stream.firstWhere(
      (event) => event is AgentFinalResultEvent || event is AgentErrorEvent,
    );
  } finally {
    await subscription.cancel();
    await agentEngine.dispose();
  }

  print('');
  print('═══ Done ═══');
}
