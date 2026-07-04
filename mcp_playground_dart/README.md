# mcp_playground_dart

Pure Dart core for AI Agent Playground. Contains the agent execution engine, LLM SDK adapters, Model Context Protocol (MCP) clients, and tool orchestration — with zero Flutter dependencies.

Ideal for building pure Dart CLI applications, background workers, backend services, or scripting agents using the Model Context Protocol.

---

## Features

- **Multi-LLM Provider Support** — Unified SDK wrappers for:
  - **OpenAI** (`openai_dart`)
  - **Anthropic Claude** (`anthropic_sdk_dart`)
  - **Google Gemini** (`googleai_dart`)
  - **Ollama** (Local models via `ollama_dart`)
  - **Mistral AI** (OpenAI-compatible client with tool call/assistant formatting patches)
  - **OpenAI-Compatible** (vLLM, LiteLLM, or custom local endpoints)
  - **Embedded GGUF Models** (on-device execution via `llamadart`)
- **Model Context Protocol (MCP) Clients**
  - **Remote HTTP/SSE Transport** — Connection checking, Basic/Bearer authentication, automatic health monitoring, and reconnect loops.
  - **Local Stdio Transport** — Desktop-only (macOS, Windows, Linux) stdio subprocess client that automatically launches and interacts with local Node.js (`npx`/`npm`) or Python (`uvx`/`pip`) MCP servers.
- **Local Tools Framework** — Clean abstract class `McpLocalTool` to register any custom Dart-native functions as LLM-executable tools.
- **McpAgentEngine**
  - Iterative agentic tool execution loop (up to 10 iterations per step).
  - Multi-step sub-prompt chaining with output substitution placeholders (`${tool_result}`, `${task_result}`).
  - Built-in duplicate call loop protection and cancellation tokens.
  - Interactive callbacks for real-time console logging, tool execution, and assistant thoughts.

---

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_playground_dart: ^0.1.0
```

### Basic Example (Pure Dart CLI)

Here is how to set up a multi-step agent with Dart-native tools (using a weather geocoding lookup and forecast flow):

```dart
import 'dart:convert';
import 'dart:io';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

Future<void> main() async {
  // 1. Configure the LLM
  final llmConfig = LlmConfig(
    provider: LlmProvider.openai,
    model: 'gpt-4o-mini',
    apiKey: 'your-openai-api-key',
  );

  // 2. Define your Dart-native tools
  final tools = <McpLocalTool>[
    GeocodeWeatherCityTool(),  // Custom McpLocalTool
    GetHourlyForecastTool(),   // Custom McpLocalTool
  ];

  // 3. Create the Agent configuration
  final agent = Agent(
    key: 'weather_agent',
    name: 'Weather Expert',
    llmConfig: llmConfig,
    systemPrompt: 'You are a weather assistant. Always geocode the city name first.',
    prompts: [
      const SubPromptStep(
        text: 'Find coordinates of Rome, Italy using geocode_weather_city.',
        enabledToolNames: ['geocode_weather_city'],
      ),
      const SubPromptStep(
        text: 'Fetch the 24-hour forecast using get_hourly_forecast for those coordinates.\n\nCoordinates:\n${tool_result}',
      ),
    ],
    dartTools: tools,
  );

  // 4. Create the execution engine and run the Agent
  final engine = McpAgentEngine();
  engine.setAgents([agent]);

  try {
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
```

---

## Creating Custom Tools

To create custom tools, inherit from `McpLocalTool` and implement the fields:

```dart
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
      content: [MCPContent(type: 'text', text: 'Current time is $now')],
    );
  }
}
```
