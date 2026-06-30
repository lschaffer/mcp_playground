# mcp_playground_flutter

An interactive AI Agent Playground widget for Flutter — connect to any LLM provider, register **local Dart-native tools** and **remote HTTP MCP servers**, and prototype agentic workflows in a chat-based UI.

> [!TIP]
> A full working multiplatform app **Tealkit** based on the features of this widget is available in Play Store, App Store, and Windows Store. See [github.com/lschaffer/tealkit](https://github.com/lschaffer/tealkit).

---

## ✨ Features

- **Multi-LLM support** – OpenAI, Anthropic Claude, Google Gemini, Ollama (local), Mistral AI, and any OpenAI-compatible endpoint.
- **HTTP MCP Server registry** – Browse [PulseMCP](https://pulsemcp.com) and [Smithery](https://smithery.ai) catalogs or add custom remote MCP servers.
- **Local MCP subprocesses** – Install, configure, and launch local stdio MCP servers (Node.js, Python) directly within the application (supported in desktop mode).
- **Dart-native local tools** – Extend with custom Dart-native tools (e.g., Weather, SSH, and Chart-generation tools; see the [example](example) implementation).
- **Agentic tool loop** – Automatic iterative tool calling with duplicate-call detection, iteration limits, and safety guards.
- **Save/Load configurations** – Persist LLM settings, tool selections, system prompts, and server lists via `SharedPreferences` or a custom `McpPlaygroundStorageDelegate`.
- **Agent Inspector** – Side-by-side conversation + internal state inspector for debugging agent behavior.
- **Cross-platform** – Works on Android, iOS, Web, macOS, Windows, and Linux.

---

## 🎥 Demo

Watch the AI Agent Playground in action executing SSH commands and generating charts:

<video src="screenshots/video/mcp_playground_ssh_chart_test.mp4" width="100%" controls></video>

*(If the video doesn't play, you can watch/download it directly [here](screenshots/video/mcp_playground_ssh_chart_test.mp4))*

---

## 🚀 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_playground_flutter: ^0.0.1
```

Then import:

```dart
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
```

---

## 📦 Widget API

### [`McpPlayground`](lib/mcp_playground.dart:56)

The main widget. Drop it into your app to get a full AI playground UI.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `initialLlmConfig` | [`LlmConfig?`](lib/models.dart:65) | `null` | Default LLM provider, model, API key, and hyperparameters. Falls back to persisted settings. |
| `initialServers` | `List<McpServerConfig>?` | `null` | Pre-configured list of HTTP MCP servers to connect to on startup. |
| `initialLocalMcpServers` | `List<LocalMcpServerSetup>?` | `null` | Pre-configured list of local Node.js or Python MCP servers to auto-initialize/install. |
| `storageDelegate` | `McpPlaygroundStorageDelegate?` | `null` | Custom persistence layer for settings. Uses `SharedPreferences` if omitted. |
| `customLocalTools` | `List<McpLocalTool>?` | `null` | Custom Dart-native tool implementations. See [`McpLocalTool`](lib/local_tools.dart:4). |
| `disableConfigDialog` | `bool` | `false` | Disable opening the settings dialog when LLM is not configured. |
| `messageContentBuilder` | `Widget? Function(BuildContext, ChatMessage)?` | `null` | Optional builder callback to intercept message layouts and render custom widgets (e.g., interactive charts). |
| `locale` | `String?` | `null` | Optional explicit locale override ('en' or 'de'). Defaults to system language. |

#### Basic usage

```dart
McpPlayground()
```

#### With default LLM config & custom tools

```dart
McpPlayground(
  initialLlmConfig: LlmConfig(
    provider: LlmProvider.openai,
    model: 'gpt-4o-mini',
    apiKey: 'sk-...',
  ),
  customLocalTools: [
    GetCurrentWeatherTool(),
    SshListDirectoryTool(() => sshDefaults),
  ],
)
```

#### With pre-registered MCP servers & custom storage

```dart
McpPlayground(
  initialServers: [
    McpServerConfig(
      id: 'my-server',
      name: 'My MCP Server',
      url: 'https://mcp.example.com',
      mcpEndpoint: '/mcp',
    ),
  ],
  storageDelegate: MyCustomStorageDelegate(),
)
```

---

### [`LlmConfig`](lib/models.dart:65)

Configures an LLM provider and its parameters.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `provider` | `LlmProvider` | *(required)* | One of: `none`, `openai`, `claude`, `gemini`, `ollama`, `openaiCompatible`, `mistral`. |
| `model` | `String` | *(required)* | Model identifier (e.g. `gpt-4o-mini`, `claude-sonnet-4-20250514`). |
| `apiKey` | `String` | *(required)* | API key for the provider. Not required for Ollama or OpenAI-compatible if using a local endpoint. |
| `baseUrl` | `String` | `''` | Custom base URL (required for Ollama and OpenAI-compatible providers). |
| `temperature` | `double` | `0.2` | Sampling temperature. |
| `maxTokens` | `int` | `0` | Maximum output tokens (`0` = no limit). |
| `topP` | `double?` | `null` | Nucleus sampling parameter. |
| `topK` | `int?` | `null` | Top-K sampling (Gemini). |
| `repeatPenalty` | `double?` | `null` | Repetition penalty (Ollama). |
| `seed` | `int?` | `null` | Random seed for deterministic output. |
| `maxToolOutputSize` | `int` | `2560000` | Max bytes for tool output before truncation warning. |
| `tokenWarningThreshold` | `int` | `1500000` | Token count warning threshold. |
| `isSlm` | `bool` | `false` | Treat as small language model (affects prompts). |
| `isMultiModal` | `bool` | `true` | Send image attachments as vision input. |
| `thinking` | `bool` | `false` | Enable extended thinking (Claude). |
| `useNativeToolCall` | `bool` | `true` | Use provider-native tool-calling API. |
| `useSafeToolCall` | `bool` | `false` | Enable safety wrapper around tool calls. |

**Example — Ollama local:**

```dart
LlmConfig(
  provider: LlmProvider.ollama,
  model: 'llama3.2',
  baseUrl: 'http://localhost:11434/api',
  apiKey: '',
  temperature: 0.7,
)
```

**Example — OpenAI-compatible (e.g. vLLM, LiteLLM):**

```dart
LlmConfig(
  provider: LlmProvider.openaiCompatible,
  model: 'mistral-7b',
  baseUrl: 'https://my-custom-endpoint.com/v1',
  apiKey: 'optional-key',
)
```

---

### [`McpServerConfig`](lib/models.dart:199)

Defines a remote HTTP MCP server connection.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | `String` | *(required)* | Unique identifier. |
| `name` | `String` | *(required)* | Human-readable label shown in the UI. |
| `url` | `String` | *(required)* | Base URL of the MCP server (e.g. `https://server.smithery.ai/...`). |
| `mcpEndpoint` | `String` | `'/mcp'` | JSON-RPC endpoint path. |
| `apiKey` | `String?` | `null` | Bearer token for authentication. |
| `apiPassword` | `String?` | `null` | Password for HTTP Basic auth. |
| `enabled` | `bool` | `true` | Whether the server is active. |

---

### [`McpLocalTool`](lib/local_tools.dart:4)

Abstract base class for implementing Dart-native tools.

```dart
class MyCustomTool extends McpLocalTool {
  @override
  String get name => 'my_custom_tool';

  @override
  String get description => 'Does something useful.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'input': {'type': 'string', 'description': 'The input string'},
    },
    'required': ['input'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final result = doSomething(arguments['input']);
    return MCPToolResult(
      content: [MCPContent(type: 'text', text: result)],
    );
  }
}
```

---

### [`McpPlaygroundStorageDelegate`](lib/playground_controller.dart:11)

Abstract class for custom persistence. Implement this to store settings in your own backend.

| Method | Description |
|--------|-------------|
| `saveLlmConfig(LlmConfig)` | Persist LLM configuration. |
| `loadLlmConfig()` | Retrieve previously saved LLM config. |
| `saveServers(List<McpServerConfig>)` | Persist MCP server list. |
| `loadServers()` | Retrieve saved MCP servers. |
| `saveSetups(List<SavedPlaygroundSetup>)` | Persist saved playground setups. |
| `loadSetups()` | Retrieve saved setups. |

---

### Custom Message Content Rendering

By default, the playground renders markdown text responses, collapsible tool details, and default attachments (like image preview widgets).
If a custom tool returns structured JSON or another custom raw format, you can intercept the rendering using the `messageContentBuilder` callback parameter on the widget (or the controller) and return custom interactive Flutter widgets (e.g., using third-party libraries like `fl_chart`):

```dart
McpPlayground(
  messageContentBuilder: (context, message) {
    // Only intercept tool response messages
    if (message.type != MessageType.toolResponse) return null;
    
    // Check if the response was generated by a specific tool
    if (message.toolName == 'create_chart_png') {
      try {
        final decoded = jsonDecode(message.content.trim());
        // Return a custom widget representing the decoded chart data
        return MyInteractiveChartWidget(decoded);
      } catch (_) {
        return null;
      }
    }
    
    // Return null to let the playground fall back to its default rendering
    return null;
  },
)
```

---

## 🖥️ Local MCP Servers (Desktop Stdio Transport)

On desktop platforms (macOS, Windows, Linux), you can register, install, and run **Node.js** and **Python** MCP servers directly as child subprocesses using stdio transport.

### Host Restrictions & Requirements:
- **Desktop Only**: Running subprocesses (local node/python MCP servers) via `dart:io` is **not supported on Web or Mobile (Android/iOS)**.
- **Node.js & Python Tools**: The host system must have the target runtime installed and present in the system PATH:
  - For Node.js servers (e.g. `npx`, `npm`), **Node.js 18+** is required.
  - For Python servers (e.g. `pip`, `uvx`), **Python 3** and the **`uv`** tool (for `uvx` servers) are required.
- **Auto-Installation**: When using `initialLocalMcpServers`, if any server environment is missing (e.g. python virtualenv is not initialized), the app will display a modal progress dialog showing the setup progress (creating `.venv`, installing packages) on startup.

---

## 📁 Examples

This repository contains a comprehensive showcase example showing both local Dart-native tools and local stdio MCP servers:

- **[example](example)**: A complete example demonstrating all features (Weather, SSH, Chart generator local tools) and auto-installing/configuring local `Git` and `Filesystem` MCP servers.

---

## ⚠️ Web Mode Restrictions & CORS

When running on **Flutter Web**, the browser's [same-origin policy](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy) and **CORS** (Cross-Origin Resource Sharing) restrictions apply to HTTP MCP server connections.

**Key limitations in web mode:**

1. **External HTTP MCP servers** – The plugin communicates with remote MCP servers via `POST` requests from the browser. These servers **must** include the appropriate CORS headers:
   - `Access-Control-Allow-Origin: *` (or your app's origin)
   - `Access-Control-Allow-Methods: POST, GET, OPTIONS`
   - `Access-Control-Allow-Headers: Content-Type, Authorization, Mcp-Session-Id`
   - The server **must** respond to `OPTIONS` preflight requests.

2. **Localhost / private network servers** – Browsers may block requests to `localhost` or private IPs from HTTPS origins unless the site is also served over `localhost`. Consider using a CORS proxy or running the app as a PWA (Progressive Web App) with appropriate headers.

3. **`dart:io`-dependent tools & Local Servers** – Local tools that depend on `dart:io` (e.g., SSH/SFTP tools, file system access) and local Node/Python MCP subprocess servers **will not work on web**. WebFlutter runs on `dart:html` and lacks socket-level APIs. Only pure-Dart and HTTP-based tools function in the browser.

4. **Workarounds:**
   - Configure your MCP server with proper CORS middleware (e.g., `cors` npm package for Node.js).
   - For development, launch Chrome with `--disable-web-security` (**not recommended for production**).
   - Deploy the MCP server on the same origin as your Flutter web app to avoid cross-origin issues entirely.

---

## 🗺️ Roadmap

- **Embedded Model Support** — Support running lightweight models locally on the device (e.g. via ONNX or TensorFlow Lite) for private offline usage.
- **Improved Agent Inspector** — Enhanced debugging with execution traces, token usage breakdowns, and step-by-step replay.
- **Plugin ecosystem** — Allow third-party tool packages to be discovered and registered at build time.
- **Streaming responses** — Real-time streaming LLM output in the chat UI.

---

## 📄 License

MIT — see the [`LICENSE`](LICENSE) file.
