# Implementation Overview

This document provides a comprehensive overview of everything implemented in the **mcp_playground** monorepo — a Flutter widget package (`mcp_playground_flutter`) and its pure-Dart core (`mcp_playground_dart`) for building AI Agent Playgrounds with Model Context Protocol (MCP) support.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Package: `mcp_playground_dart` (Pure Dart Core)](#package-mcp_playground_dart-pure-dart-core)
   - [Models & Data Structures](#models--data-structures)
   - [LLM Service](#llm-service)
   - [MCP Client (HTTP/SSE)](#mcp-client-httpsse)
   - [Local MCP Client (Desktop Stdio)](#local-mcp-client-desktop-stdio)
   - [Multi-MCP Manager](#multi-mcp-manager)
   - [Local Tools Framework](#local-tools-framework)
   - [Agent Engine](#agent-engine)
3. [Package: `mcp_playground_flutter` (Flutter Widget)](#package-mcp_playground_flutter-flutter-widget)
   - [Main Widget: `McpPlayground`](#main-widget-mcpplayground)
   - [Configuration & Persistence](#configuration--persistence)
   - [Widgets](#widgets)
   - [Embedded (On-Device) LLM Support](#embedded-on-device-llm-support)
   - [Localizations (i18n)](#localizations-i18n)
   - [Services & Utilities](#services--utilities)
4. [Example Applications](#example-applications)
5. [Cross-Platform Considerations](#cross-platform-considerations)
6. [Changelog Summary](#changelog-summary)

---

## Architecture

The project follows a **two-package architecture**:

```
mcp_playground/
├── mcp_playground_dart/       # Pure Dart — zero Flutter dependency
│   ├── lib/src/models/        # Data models (LLM config, MCP messages, chat, tools)
│   ├── lib/src/llm/           # LLM provider adapters
│   ├── lib/src/mcp/           # MCP client (HTTP/SSE), local stdio client, tool defs
│   └── lib/src/agents/        # Agent execution engine
└── mcp_playground_flutter/    # Flutter package (depends on mcp_playground_dart)
    ├── lib/
    │   ├── mcp_playground.dart    # Main McpPlayground widget (~2900 lines)
    │   ├── playground_controller.dart  # State orchestration via ChangeNotifier
    │   ├── src/widgets/           # All UI widgets
    │   └── src/services/          # Embedded LLM, registry, MCP server install
    └── test/                      # Tests for the Flutter package
```

- **`mcp_playground_dart`** is a standalone Dart package with zero Flutter dependency. It can be used in pure Dart CLI/backend apps.
- **`mcp_playground_flutter`** depends on `mcp_playground_dart` and provides the full Flutter widget UI.

---

## Package: `mcp_playground_dart` (Pure Dart Core)

### Models & Data Structures

**File:** [`mcp_playground_dart/lib/src/models/models.dart`](mcp_playground_dart/lib/src/models/models.dart)

| Model | Description |
|-------|-------------|
| `LlmProvider` | Enum: `none`, `openai`, `claude`, `gemini`, `ollama`, `openaiCompatible`, `mistral`, `embedded`. Includes `configKey`, `displayName`, and `fromConfigKey()` serialization. |
| `LlmConfig` | Full LLM configuration — provider, model, API key, base URL, temperature, max tokens, topP, topK, repeat penalty, seed, max tool output size, token warning threshold, SLM flag, multi-modal flag, extended thinking, native tool call toggle, safe tool call toggle. Includes `copyWith()`, JSON serialization, and `isConfigured` validation. |
| `McpServerConfig` | MCP server connection definition — id, name, URL, MCP endpoint, API key, password, enabled flag, online state, local process config (type, install method, package, command, env vars, installed state). Full JSON serialization. |
| `MCPMessage` / `MCPRequest` / `MCPResponse` / `MCPNotification` | Full **JSON-RPC 2.0** protocol message models with serialization and `MCPError`. |
| `MCPTool` / `MCPContent` / `MCPToolResult` | MCP tool capability schemas and execution result models. |
| `MCPResource` | MCP resource representation (URI, name, description, MIME type). |
| `ChatMessage` | Chat conversation message — id, content, role (`user`/`assistant`/`system`/`tool`), timestamp, message type (`text`/`image`/`file`/`toolCall`/`toolResponse`/`log`), tool metadata (name, arguments, result), and file attachments. |
| `MessageAttachment` | File attachment metadata (id, name, path, bytes, MIME type, size). |
| `SubPromptStep` | Multi-prompt step — text content, per-step enabled tool names filter, stop-after-tool-call flag. Supports `isAllTools` and `isNoTools` convenience getters. |
| `parseSubPromptSteps()` / `serializeSubPromptSteps()` | Serialization format using `++#++[NT:tool1|tool2][SATC]` separators for encoding multi-step prompts with per-step tool filters and stop flags. |
| `LocalMcpServerSetup` | Definition for auto-installing local Node.js/Python MCP subprocesses — name, launch args, type (`python`/`nodejs`), method (`pip`/`uvx`/`npm`/`npx`), package name, install command, env vars. |

### LLM Service

**File:** [`mcp_playground_dart/lib/src/llm/llm_service.dart`](mcp_playground_dart/lib/src/llm/llm_service.dart)

A static service class `LLMService` with a single `generate()` entry point that routes to provider-specific adapters:

| Adapter | SDK | Key Features |
|---------|-----|-------------|
| **OpenAI** | `openai_dart ^7.0.0` | Native tool calling via `Tool.function()`, system message injection, full hyperparameter passthrough (temperature, maxTokens, topP, seed). Client caching by API key + base URL. |
| **OpenAI-Compatible** | `openai_dart ^7.0.0` | Same adapter as OpenAI but with custom `baseUrl`. Supports any OpenAI-compatible endpoint (vLLM, LiteLLM, local models). |
| **Mistral AI** | `openai_dart ^7.0.0` + patch client | Uses OpenAI client but with a custom `_MistralPatchClient` HTTP interceptor that: patches tool call `type` field to `"function"`, inserts synthetic assistant tool-call messages before orphaned tool messages, and flattens `image_url` objects to plain URLs. |
| **Anthropic Claude** | `anthropic_sdk_dart ^5.0.0` | Uses **type-checking** (`block is anthropic.TextBlock`) instead of `.map()` for forward-compatibility. Groups consecutive same-role messages. Supports `SystemPrompt.text()`, `ToolDefinition.custom()`, `InputSchema.fromJson()`. |
| **Google Gemini** | `googleai_dart ^8.0.0` | Maps tools to `gemini.FunctionDeclaration` with a recursive `_sanitizeGeminiSchema()` that converts JSON Schema types to Gemini's `SchemaType` enum (object, array, integer, number, boolean, string). System instruction via `gemini.Content(parts: [...])`. Groups consecutive same-role messages. |
| **Ollama** | `ollama_dart ^2.3.0` | Null-safe tool call field access. Tool call IDs generated with UUID. Supports `ModelOptions` (temperature, numPredict, seed), custom headers for auth, and `ToolDefinition` mapping. |

**LLM Response Model** — [`mcp_playground_dart/lib/src/llm/llm_response.dart`](mcp_playground_dart/lib/src/llm/llm_response.dart):

- `LLMToolCall` — id, name, arguments map.
- `LLMResponse` — text content + list of tool calls.

### MCP Client (HTTP/SSE)

**File:** [`mcp_playground_dart/lib/src/mcp/mcp_client.dart`](mcp_playground_dart/lib/src/mcp/mcp_client.dart)

`MCPClient` — a full HTTP/HTTPS MCP client with:

- **JSON-RPC 2.0 protocol** implementation (`tools/list`, `tools/call`, `resources/list`, `resources/read`)
- **MCP 2025 Streamable HTTP** — `Mcp-Session-Id` header tracking for stateful sessions
- **SSE parsing** — `_extractFirstSseData()` extracts JSON from `text/event-stream` responses
- **Authentication** — Bearer token OR HTTP Basic auth (username + password), with automatic 401 retry without auth headers
- **Health monitoring** — 30-second periodic health checks with automatic reconnection
- **Exponential backoff reconnection** — up to 5 attempts with 5-60 second delays
- **Connection probing** — tests `/health` endpoint first, falls back to MCP `initialize` probe
- **Tool execution** — `callTool()` with robust response parsing (handles both structured MCP content and raw string/JSON responses)
- **Resource reading** — `readResource()` for MCP resource URIs

### Local MCP Client (Desktop Stdio)

**Files:**
- [`mcp_playground_dart/lib/src/mcp/local_mcp_client.dart`](mcp_playground_dart/lib/src/mcp/local_mcp_client.dart) — Desktop implementation
- [`mcp_playground_dart/lib/src/mcp/local_mcp_client_stub.dart`](mcp_playground_dart/lib/src/mcp/local_mcp_client_stub.dart) — Web/mobile stub

Uses **conditional imports** (`if (dart.library.html)`) to provide:
- **Desktop**: Full `LocalMCPClient` that spawns stdio subprocesses for Node.js (`npx`, `npm`) and Python (`uvx`, `pip`) MCP servers, with JSON-RPC communication over stdin/stdout.
- **Web/Mobile**: Stub that throws `UnsupportedError`.

### Multi-MCP Manager

**File:** [`mcp_playground_dart/lib/src/mcp/mcp_client_def.dart`](mcp_playground_dart/lib/src/mcp/mcp_client_def.dart)

- `MCPClientDef` — Dynamic wrapper for a single MCP server with tool caching, display name, and connection status.
- `MultiMCPManager` — Coordinates multiple MCP server connections:
  - Register/unregister clients
  - Aggregate available tools across all servers (deduplicated by name)
  - `callTool()` with fuzzy name resolution (prefix/substring matching)
  - `initializeAll()` and `disconnectAll()` for batch operations
  - `onStateChanged` callback for UI reactivity

### Local Tools Framework

**File:** [`mcp_playground_dart/lib/src/mcp/local_tools.dart`](mcp_playground_dart/lib/src/mcp/local_tools.dart)

`McpLocalTool` — abstract base class for Dart-native tools:
- `name` — unique tool identifier
- `description` — LLM-visible description
- `inputSchema` — JSON Schema for parameters
- `execute(Map<String, dynamic> arguments)` — async execution method
- `toMCPTool()` — conversion to standard `MCPTool` model

### Agent Engine

**File:** [`mcp_playground_dart/lib/src/agents/agents_engine.dart`](mcp_playground_dart/lib/src/agents/agents_engine.dart)

`McpAgentEngine` — the core agentic execution engine:

**Agent Definition** (`Agent`):
- `key`, `name`, `llmConfig`, `systemPrompt`
- `prompts` — list of `SubPromptStep` for multi-step execution
- `dartTools` — local Dart-native tools (all platforms)
- `remoteServers` — HTTP/HTTPS MCP server configs (all platforms)
- `localServers` — Desktop stdio MCP server configs
- Full JSON serialization/deserialization

**Event System** (reactive stream-based):
- `AgentEvent` sealed class hierarchy:
  - `AgentLogEvent` — log/chronology messages
  - `AgentToolResultEvent` — tool execution results
  - `AgentAssistantResultEvent` — LLM text responses
  - `AgentErrorEvent` — error notifications
  - `AgentFinalResultEvent` — completion with final response
- Broadcast `StreamController<AgentEvent>` for UI consumers

**Execution Engine Features**:
- **Multi-step sub-prompt chaining** — Sequentially executes sub-prompts with:
  - `${tool_result}` / `[tool_result]` and `${task_result}` / `[task_result]` placeholder substitution between steps
  - Per-step tool filtering (`enabledToolNames` or all tools)
  - Per-step `stopAfterToolCall` flag
- **Agentic tool loop** — Automatic iterative tool calling within each step (up to 10 iterations)
- **Duplicate-call detection** — Tracks executed tool signatures (name + arguments) and tool IDs; injects correction messages to prevent infinite loops
- **Cancellation support** — Per-agent cancel tokens via `cancel()` method
- **Sync and async execution** — `run()` (blocks, returns final response) and `runAsync()` (fire-and-forget with callbacks/streams)
- **Automatic MCP connection management** — Connects remote + local servers at execution start, disconnects in `finally` block
- **Tool description injection** — When `useNativeToolCall` is false, injects tool names, descriptions, and input schemas into the system prompt
- **Ollama-specific format** — JSON-encoded tool results `{"tool": "...", "id": "...", "tool_executed": true, "tool_result": "..."}` for Ollama compatibility
- **Agent lifecycle** — `AgentStatus` enum (`running`, `finished`, `error`) tracked per agent

---

## Package: `mcp_playground_flutter` (Flutter Widget)

### Main Widget: `McpPlayground`

**File:** [`mcp_playground_flutter/lib/mcp_playground.dart`](mcp_playground_flutter/lib/mcp_playground.dart) (~2900 lines)

A `StatefulWidget` that provides the complete AI playground UI:

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `initialLlmConfig` | `LlmConfig?` | Default LLM provider config. Falls back to persisted settings. |
| `initialServers` | `List<McpServerConfig>?` | Pre-configured HTTP MCP servers. |
| `initialLocalMcpServers` | `List<LocalMcpServerSetup>?` | Pre-configured local Node.js/Python MCP servers for auto-install. |
| `storageDelegate` | `McpPlaygroundStorageDelegate?` | Custom persistence (defaults to `SharedPreferences`). |
| `customLocalTools` | `List<McpLocalTool>?` | Custom Dart-native tool implementations. |
| `disableConfigDialog` | `bool` | Suppress auto-opening config dialog when unconfigured. |
| `messageContentBuilder` | `Widget? Function(BuildContext, ChatMessage)?` | Custom message content renderer (e.g., interactive charts). |
| `locale` | `String?` | Locale override (`'en'` or `'de'`). |
| `enableLogging` | `bool` | Console log toggle. |

**Two-mode UI:**
1. **Setup Screen** — LLM configuration form, MCP server management, tool selection, multi-prompt editor, save/load/export/import configurations
2. **Chat View** — Conversation UI with markdown rendering, tool call/results bubbles, file attachments, stop button, agent inspector sidebar

### Configuration & Persistence

**File:** [`mcp_playground_flutter/lib/playground_controller.dart`](mcp_playground_flutter/lib/playground_controller.dart)

`McpPlaygroundController` — `ChangeNotifier`-based state orchestrator:

- **LLM Config** — Save/load with `SharedPreferences` or custom `McpPlaygroundStorageDelegate`
- **Server Management** — Register/remove/connect HTTP MCP servers and local subprocess servers
- **Tool Selection** — Track enabled tools per toolset group, persist selection
- **Setup Management** — Save/load/delete named playground setups (LLM config + servers + tools + system prompt + multi-prompt steps)
- **Export/Import** — JSON file export/import of all saved setups via `FilePicker`, with duplicate detection and unavailable tool filtering
- **Agentic Execution** — Orchestrates the `McpAgentEngine` with full tool loop, cancellation, attachment handling, and message history
- **Stop Button** — User-cancellable prompt execution

`McpPlaygroundStorageDelegate` — Abstract class for custom persistence:
- `saveLlmConfig()` / `loadLlmConfig()`
- `saveServers()` / `loadServers()`
- `saveSetups()` / `loadSetups()`

### Widgets

All widgets under [`mcp_playground_flutter/lib/src/widgets/`](mcp_playground_flutter/lib/src/widgets/):

| Widget | File | Description |
|--------|------|-------------|
| `ChatBubble` | `chat_bubble.dart` | Renders chat messages with markdown (via `flutter_markdown_plus`), collapsible tool call/result cards, image/file attachment previews, HTML document preview magnifier, base64 image detection & rendering, auto-detection of JSON-embedded spreadsheets/binary files with download cards. |
| `SettingsDrawer` | `settings_drawer.dart` | Navigation drawer for LLM parameters and MCP server management. |
| `LlmConfigForm` | `llm_config_form.dart` | LLM provider picker with dynamic fields (API key, base URL, model, temperature, max tokens, topP, topK, seed, thinking toggle, SLM toggle, multi-modal toggle, native/safe tool call toggles). |
| `McpServerRegistryTab` | `mcp_server_registry_tab.dart` | Browse PulseMCP and Smithery catalogs; dynamically fetches registry definitions from GitHub (24-hour cache); add custom remote MCP servers. |
| `RemoteMcpDialog` | `remote_mcp_dialog.dart` | Form dialog for adding/editing remote HTTP MCP server connections. |
| `EditMcpDialog` | `edit_mcp_dialog.dart` | Form dialog for configuring local MCP subprocess servers. |
| `ServerToolsDialog` | `server_tools_dialog.dart` | Dialog showing tools exposed by a specific connected MCP server. |
| `RegisteredToolsDialog` | `registered_tools_dialog.dart` | Full tool selection dialog — grouped by toolset, with per-group and global "All/None" toggles, mobile fullscreen mode, alphabetical sorting. |
| `SubPromptListEditor` | `sub_prompt_list_editor.dart` | Multi-prompt step editor with desktop side-by-side layout and mobile stack layout. Supports step reordering, per-step tool filtering, stop-after-tool-call flags, and `${tool_result}`/`${task_result}` placeholder documentation. Used on both setup screen and active chat view. |
| `AgentInspector` | `agent_inspector.dart` | Side-by-side conversation + internal state inspector panel. Shows formatted system prompts, user questions, tool calls, and execution results with expandable log entries. |
| `InitialMcpInstallProgressDialog` | `initial_mcp_install_progress_dialog.dart` | Modal progress dialog for auto-installing local MCP servers on first startup (creates venv, installs packages via pip/uvx/npm/npx). |
| `AddGgufDialog` | `embedded_llm/add_gguf_dialog.dart` | Dialog for adding local GGUF model files. |
| `EmbeddedModelPickerWidget` | `embedded_llm/embedded_model_picker_widget.dart` | Widget for selecting downloaded embedded models with context-size fallback retry logic. |
| `HfDiscoverDialog` | `embedded_llm/hf_discover_dialog.dart` | Browse and download models from HuggingFace. |

### Embedded (On-Device) LLM Support

**Files under [`mcp_playground_flutter/lib/src/services/embedded_llm/`](mcp_playground_flutter/lib/src/services/embedded_llm/):**

- `EmbeddedModel` — Model metadata (name, path, quantization, context size)
- `EmbeddedModelManager` — Discover, download (from HuggingFace), and manage local GGUF models
- `EmbeddedLlmAdapter` — Adapter for `llamadart` that:
  - Auto-selects platform-appropriate backend (CPU/WASM)
  - Context-size fallback retry (full → half → 1024) when `llama_init_from_model` fails
  - Suggests alternative quantizations when context creation fails
  - Web/WASM support via `SharedArrayBuffer` (requires COOP/COEP headers)

### Localizations (i18n)

**File:** [`mcp_playground_flutter/lib/src/mcp_localizations.dart`](mcp_playground_flutter/lib/src/mcp_localizations.dart)

Full English (`en`) and German (`de`) translations covering:
- UI labels (tabs, buttons, dialogs, form fields)
- Status messages (connecting, connected, error, loading)
- Tool-related strings (tool sets, tool selection, tool execution)
- MCP server management (add/edit/remove local/remote servers)
- Embedded model UI (download, load, model picker)
- Export/Import dialogs
- HTML preview and file attachment strings

### Services & Utilities

| `mcp_playground_flutter/lib/src/services/mcp_registry_service.dart` | Fetches MCP server registry from GitHub with 24-hour cache. |
| `mcp_playground_flutter/lib/src/services/mcp_server_installer.dart` | Installs local Node.js/Python MCP servers (creates venv, runs pip/uvx/npm/npx). |
| `mcp_playground_flutter/lib/src/utils/mime_utils.dart` | MIME type detection from file extensions. |

---

## Example Applications

### `example/` — Full Featured Example

**File:** [`example/lib/main.dart`](example/lib/main.dart)

A complete app demonstrating:
- **Custom local tools**: Weather (Open-Meteo API, 4 tools), SSH/SFTP (`dartssh2`, 7 tools), Chart generation (2 tools)
- **Local MCP servers**: Filesystem (Node.js `@modelcontextprotocol/server-filesystem`) and Git (Python `mcp-server-git`) auto-install
- **Custom message rendering**: `messageContentBuilder` that intercepts `create_chart_png` tool results and renders interactive `fl_chart` widgets (Line, Bar, Pie charts)
- **Environment-based config**: LLM provider/model/API key from `.env` file
- **Desktop-only guards**: Local MCP servers only enabled on desktop platforms

### `example_embedded/` — Offline On-Device Example

**File:** [`example_embedded/lib/main.dart`](example_embedded/lib/main.dart)

Demonstrates fully offline, on-device GGUF model execution:
- `LlmProvider.embedded` with a pre-configured model name
- Same chart rendering via `fl_chart`
- Weather tools (no API key needed for Open-Meteo)

### `example/shared_tools/` — Shared Tool Package

**File:** [`example/shared_tools/lib/shared_tools.dart`](example/shared_tools/lib/shared_tools.dart)

A separate Dart package (`mcp_playground_shared_tools`) with reusable tool implementations shared between examples.

---

## Cross-Platform Considerations

| Platform | LLM Providers | HTTP MCP Servers | Local Stdio MCP | Dart-Native Tools | Embedded Models |
|----------|--------------|------------------|-----------------|-------------------|-----------------|
| **macOS** | All | Yes | Yes (Node/Python subprocess) | Yes (incl. `dart:io`) | Yes |
| **Windows** | All | Yes | Yes (Node/Python subprocess) | Yes (incl. `dart:io`) | Yes |
| **Linux** | All | Yes | Yes (Node/Python subprocess) | Yes (incl. `dart:io`) | Yes |
| **Android** | All | Yes (CORS-dependent) | No | Yes (pure Dart only) | Limited |
| **iOS** | All | Yes (CORS-dependent) | No | Yes (pure Dart only) | Limited |
| **Web** | All | Yes (CORS-dependent) | No | Yes (pure Dart only) | Yes (WASM, <2GB models) |

**Web-specific notes:**
- External MCP servers must include CORS headers (`Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers`, handle `OPTIONS` preflight)
- `dart:io`-dependent tools and local subprocess servers do not work on web
- Embedded WASM models limited to ~2 GB (use Qwen2.5-0.5B, Llama-3.2-1B, SmolLM2-1.7B etc.); larger models require experimental Wasm64 in Chrome

---

## Changelog Summary

### v0.0.13 (Current)
- Export/import playground configurations as JSON files via `FilePicker`
- Web/WASM support for `llamadart` (removed `kIsWeb` guards)
- `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` meta tags for `SharedArrayBuffer`
- Removed top-level "Stop after tool call" checkbox (now per sub-prompt step)

### v0.0.12
- Explicit platform declaration in `pubspec.yaml`

### v0.0.11
- Fixed `anthropic.InputContentBlock.text` positional argument issues

### v0.0.10
- User-cancellable prompt execution (stop button)
- Embedded model context-size fallback retry logic
- Fixed embedded model adapter ConcurrentModificationError
- Fixed `CreateChartPngTool` string-to-num coercion
- Fixed Agent Inspector `ListTile` Material ancestor assertion

### v0.0.9
- Embedded model support (HuggingFace discovery, local GGUF loading, on-device execution)
- Codebase audit and refactoring

### v0.0.8
- HTML document parsing and magnifier preview
- On-demand tool discovery in tools catalog dialog
- English/German localizations for HTML previews and dialogs
- Base64 image filtering from monospace previews
- Auto-detection of JSON-embedded spreadsheets and binary files

### v0.0.7
- Replaced chat input with `SubPromptListEditor` in active chat view
- Filtered step-specific tool selectors to active toolsets only
- Fixed auto-enabling behavior for default local MCP servers

### v0.0.6
- Corrected tool state auto-selection on initial startup
- Removed hardcoded 1200+ line JSON registry list (now fetched dynamically from GitHub)
- Resolved local MCP subprocess timeouts on Windows (`runInShell: Platform.isWindows`)
- Increased JSON-RPC timeout to 60 seconds
- Agent Inspector expandable log tiles with formatted previews

### v0.0.5
- Multi-prompt step chaining with output piping (`${tool_result}`, `${task_result}`)
- `SubPromptListEditor` widget on setup screen
- Per-step tool filtering and stop-after-tool-call flags
- Active tool schemas injected into system prompt
- Togglable widget event logging

### v0.0.4
- "All/None" toggling in tool selection dialogs
- Base64 image/file parsing in chat bubbles
- Online-fetched MCP registry list with 24-hour cache
- Fixed HTTP MCP servers disappearing after tool execution

### v0.0.3
- Restructured to `lib/src/` private directory layout
- Comprehensive dartdoc on all public API

### v0.0.2
- Upgraded `openai_dart` to v7, `anthropic_sdk_dart` to v5, `ollama_dart` to v2.3
- Hid Load/Save/Clear in active chat view
- Upgraded `file_picker` to v11 (static API)
- Upgraded `flutter_lints` to v6

### v0.0.1
- Initial release with full multi-LLM support, HTTP MCP server registry, Dart-native local tools, agentic tool loop, save/load configurations, Agent Inspector, custom persistence, and cross-platform support.
