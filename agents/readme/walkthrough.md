# Agent Readme / Walkthrough: MCP Playground Flutter Package

Hello! This document provides the context, architecture, and current state of the **`mcp_playground_flutter`** package to help you resume work in a new chat window.

---

## 1. Project Goal & Location

- **Package Name**: `mcp_playground_flutter`
- **Location**: `c:\projects\ls\mcp_playground`
- **Purpose**: A standalone open-source Flutter package that provides a premium AI Agent Chat Playground UI. It features advanced LLM hyperparameter configuration, dynamic HTTP/HTTPS Model Context Protocol (MCP) server integration, and built-in native tools (SSH execution, Open-Meteo Weather, and `fl_chart` data charts).

---

## 2. Technical Decisions & Constraints

- **State Management**: Uses pure **vanilla Flutter state management** (e.g. `ChangeNotifier`, `ValueNotifier`, and standard widgets). **Do not introduce heavy packages like Riverpod or Bloc** to keep it lightweight and easy to integrate for consumers.
- **Provider Integrations**: Leverages direct lightweight integrations with the official Dart client SDKs (`openai_dart`, `anthropic_sdk_dart`, `google_generative_ai`, `ollama_dart`). **Genkit is not used** to avoid heavy dependency footprints and beta API instability.
- **Runtime Environment**: All tools run strictly via HTTP/HTTPS MCP servers or native Dart APIs. **No local subprocess runtimes** (Python/Node virtual environments) are allowed in the sandboxed package.

---

## 3. Current State of the Codebase

The package is fully implemented, verified, and compiles cleanly:
- **`flutter analyze`**: **100% clean**. There are no compilation errors, warnings, or lints.
- **`flutter test`**: **All tests passed!** The test suite executes and passes.

### Directory Structure & File Overview:
- [lib/models.dart](file:///c:/projects/ls/mcp_playground/lib/models.dart): Configuration schemas (`LlmConfig`, `McpServerConfig`), JSON-RPC 2.0 schemas (`MCPRequest`, `MCPResponse`, `MCPNotification`), and UI models (`ChatMessage`).
- [lib/mcp_client.dart](file:///c:/projects/ls/mcp_playground/lib/mcp_client.dart): `MCPClient` for HTTP/HTTPS connections and SSE parsing, and `MultiMCPManager` to coordinate multiple active servers in parallel.
- [lib/llm_service.dart](file:///c:/projects/ls/mcp_playground/lib/llm_service.dart): Integrations with LLM SDKs and runtime tool payload generation.
- [lib/local_tools.dart](file:///c:/projects/ls/mcp_playground/lib/local_tools.dart): Dart-native fallback tool registrations:
  - `WeatherLocalTool` (Open-Meteo API)
  - `SshLocalTool` (`dartssh2` client execution)
  - `ChartLocalTool` (generates JSON definitions for charts)
- [lib/playground_controller.dart](file:///c:/projects/ls/mcp_playground/lib/playground_controller.dart): Orchestrates state, triggers agentic loops (executing up to 5 tool-calls sequentially), and persists configurations to `SharedPreferences` via `McpPlaygroundStorageDelegate`.
- [lib/mcp_playground.dart](file:///c:/projects/ls/mcp_playground/lib/mcp_playground.dart): Main widget container.
- [lib/widgets/chat_bubble.dart](file:///c:/projects/ls/mcp_playground/lib/widgets/chat_bubble.dart): Renders markdown text bubbles, collapsible tool calls, and charts (`Bar`, `Line`, `Pie`) via `fl_chart`.
- [lib/widgets/settings_drawer.dart](file:///c:/projects/ls/mcp_playground/lib/widgets/settings_drawer.dart): Drawer for LLM parameters and MCP servers management.

---

## 4. Key Implementation Details & Lessons Learned

- **Anthropic Freezed Union Block Mapping**: The `Block` class in `anthropic_sdk_dart` contains a large number of generated sub-unions. Instead of using `block.map(...)` (which breaks when the package adds new block types), we use standard Dart type checking:
  ```dart
  if (block is anthropic.TextBlock) { ... }
  else if (block is anthropic.ToolUseBlock) { ... }
  ```
- **Anthropic API Constructors**:
  - Use `anthropic.Tool.custom(...)` instead of the unnamed constructor.
  - Use `anthropic.MessageContent.text(...)` instead of `string(...)`.
  - Use `anthropic.CreateMessageRequestSystem.text(...)` instead of `System.string(...)`.
  - Use `anthropic.ToolResultBlockContent.text(...)` inside `Block.toolResult`.
- **Gemini API Constructors**:
  - `GenerativeModel.systemInstruction` takes a `Content` object created via `gemini.Content.system(systemPrompt)`.
  - Parts are represented by `gemini.FunctionCall` and `gemini.FunctionResponse`.
- **Ollama Response Null Safety**:
  - Ollama response tool calls list is nullable (`response.message.toolCalls`), so verify `!= null` and use `response.message.toolCalls!` safely.
- **Form Field Warnings**:
  - Use `initialValue` instead of the deprecated `value` parameter on `DropdownButtonFormField`.

---

## 5. Potential Next Steps

1. **Create an Example App**: Create an `example/` directory within the package containing a simple application running `McpPlayground` to test interactions live.
2. **Cross-Platform Verification**: Verify that SSH tool operations and chart rendering operate cleanly across Android, iOS, Windows, macOS, and Linux targets.
3. **Storage customization**: Implement a custom database delegate (e.g. SQLite or Hive) if a persistence mechanism other than `SharedPreferences` is requested.
