# MCP Playground — Example App

A complete working example demonstrating how to integrate [`mcp_playground_flutter`](https://pub.dev/packages/mcp_playground_flutter) into a Flutter application.

---

## Quick Start

```bash
cd example
flutter run
```

The example launches an interactive AI Playground with **pre-configured demo tools** including weather forecasts, SSH/SFTP operations, and chart generation.

---

## Widget Parameters Explained

The example passes all configurable parameters to the [`McpPlayground`](../lib/mcp_playground.dart:55) widget. Below is a detailed walkthrough.

### 1. `initialLlmConfig` — Default LLM Configuration

```dart
McpPlayground(
  initialLlmConfig: LlmConfig(
    provider: LlmProvider.openai,
    model: 'gpt-4o-mini',
    apiKey: 'sk-...',
  ),
)
```

Sets the **fallback LLM provider** that is used when no custom override is applied in the UI. The user can still change providers and override settings from the settings panel.

| Behavior | Detail |
|----------|--------|
| **Persisted** | When the user saves LLM settings, they are stored via `McpPlaygroundStorageDelegate` (defaults to `SharedPreferences`). |
| **Override** | The setup screen offers a "Custom LLM Override" toggle that lets users temporarily override the default per session. |
| **Per-provider** | Each provider (`openai`, `claude`, `gemini`, `ollama`, `openaiCompatible`, `mistral`) has its own SDK adapter — see [`LLMService`](../lib/llm_service.dart:33). |

**Example — Ollama (no API key needed):**

```dart
initialLlmConfig: LlmConfig(
  provider: LlmProvider.ollama,
  model: 'llama3.2',
  baseUrl: 'http://localhost:11434/api',
  apiKey: '',
)
```

**Example — Claude:**

```dart
initialLlmConfig: LlmConfig(
  provider: LlmProvider.claude,
  model: 'claude-sonnet-4-20250514',
  apiKey: 'sk-ant-...',
  thinking: true,        // Enable extended thinking
  maxTokens: 8192,
)
```

---

### 2. `initialServers` — Pre-registered MCP Servers

```dart
McpPlayground(
  initialServers: [
    McpServerConfig(
      id: 'my-server',
      name: 'My MCP Server',
      url: 'https://mcp.example.com',
      mcpEndpoint: '/mcp',
      apiKey: 'optional-bearer-token',
    ),
  ],
)
```

Pre-populates the MCP server list so they are available right from the first launch. Users can add, edit, remove, or toggle servers via the settings panel.

The [`McpServerConfig`](../lib/models.dart:199) fields:

| Field | Example | Purpose |
|-------|---------|---------|
| `id` | `'my-server'` | Unique identifier. Used for storage and state tracking. |
| `name` | `'My MCP Server'` | Display label in the UI tool lists. |
| `url` | `'https://mcp.example.com'` | Base URL. The client appends the `mcpEndpoint` to form the full JSON-RPC URL. |
| `mcpEndpoint` | `'/mcp'` | Path for MCP JSON-RPC calls. Defaults to `/mcp`. |
| `apiKey` | `'sk-...'` | Bearer token sent as `Authorization: Bearer <token>` header. |
| `apiPassword` | `'secret'` | Password for HTTP Basic auth. When set alongside `apiKey`, the key is used as the username. |
| `enabled` | `true` | Whether the server is active on startup. |

---

### 3. `storageDelegate` — Custom Persistence Layer

```dart
McpPlayground(
  storageDelegate: MyCustomStorageDelegate(),
)
```

By default, the plugin uses [`SharedPreferencesStorageDelegate`](../lib/playground_controller.dart:20) which persists all settings via `SharedPreferences`. Implement [`McpPlaygroundStorageDelegate`](../lib/playground_controller.dart:11) to store data in a database, remote API, or encrypted storage:

```dart
class MyCustomStorageDelegate extends McpPlaygroundStorageDelegate {
  @override
  Future<void> saveLlmConfig(LlmConfig config) async {
    // Save to your backend...
  }

  @override
  Future<LlmConfig?> loadLlmConfig() async {
    // Load from your backend...
  }

  @override
  Future<void> saveServers(List<McpServerConfig> servers) async { ... }

  @override
  Future<List<McpServerConfig>> loadServers() async { ... }

  @override
  Future<void> saveSetups(List<SavedPlaygroundSetup> setups) async { ... }

  @override
  Future<List<SavedPlaygroundSetup>> loadSetups() async { ... }
}
```

---

### 4. `customLocalTools` — Dart-Native Tool Registration

The example registers **10 demo tools** — this is the most powerful customization point.

```dart
McpPlayground(
  customLocalTools: [
    // Weather tools (free Open-Meteo API, no key required)
    GetCurrentWeatherTool(),
    GetHourlyForecastTool(),
    GetDailyForecastTool(),
    GeocodeWeatherCityTool(),

    // SSH/SFTP tools (requires dartssh2)
    SshListDirectoryTool(() => sshDefaults),
    SshReadFileTool(() => sshDefaults),
    SshDownloadFileTool(() => sshDefaults),
    SshUploadFileTool(() => sshDefaults),
    SshExecuteCommandTool(() => sshDefaults),
    SshMakeDirectoryTool(() => sshDefaults),
    SshRemoveDirectoryTool(() => sshDefaults),

    // Canvas-based chart generator (no extra deps)
    CreateChartPngTool(),
  ],
)
```

#### 💬 Prompt Examples per Tool

The tools are designed to be invoked by the LLM through natural language. Here are example user prompts that trigger each tool:

| Tool | Example User Prompt |
|------|-------------------|
| `get_current_weather` | *"What's the current weather in Vienna?"* |
| `get_hourly_forecast` | *"Give me the hourly weather forecast for Tokyo for the next 24 hours."* |
| `get_daily_forecast` | *"Show me the 7-day forecast for New York."* |
| `geocode_weather_city` | *"What are the coordinates of Amsterdam?"* |
| `list_directory` | *"List the contents of /home/user/projects on the remote server."* |
| `read_file` | *"Read /var/log/syslog on the remote machine."* |
| `download_file` | *"Download /home/user/report.pdf from the server."* |
| `upload_file` | *"Upload the file 'hello.txt' with content 'Hello World' to /tmp/ on the remote server."* |
| `execute_command` | *"Run 'df -h' on the remote server to check disk space."* |
| `make_directory` | *"Create a directory /home/user/backups on the remote server."* |
| `remove_directory` | *"Remove the empty directory /home/user/temp on the remote server."* |
| `create_chart_png` | *"Generate a bar chart with Python: 45, JavaScript: 35, Dart: 25, Go: 15."* |

Each tool extends [`McpLocalTool`](../lib/local_tools.dart:4):

```dart
class McpLocalTool {
  String get name;              // Unique tool name (e.g. 'get_current_weather')
  String get description;       // LLM-facing description of what the tool does
  Map<String, dynamic> get inputSchema;  // JSON Schema for tool arguments
  Future<MCPToolResult> execute(Map<String, dynamic> arguments);  // Implementation
}
```

**Example — Minimal custom tool:**

```dart
class EchoTool extends McpLocalTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'Echoes back the input text.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Text to echo back'},
    },
    'required': ['text'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> args) async {
    return MCPToolResult(
      content: [MCPContent(type: 'text', text: args['text'] ?? '')],
    );
  }
}
```

**Example — Weather tool with HTTP call:**

```dart
class GetCurrentWeatherTool extends McpLocalTool {
  @override
  String get name => 'get_current_weather';

  @override
  String get description =>
      'Gets the current weather for a given latitude and longitude.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'latitude': {'type': 'number', 'description': 'Latitude'},
      'longitude': {'type': 'number', 'description': 'Longitude'},
    },
    'required': ['latitude', 'longitude'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> args) async {
    final lat = args['latitude'];
    final lon = args['longitude'];
    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true');
    final response = await http.get(uri);
    return MCPToolResult(
      content: [MCPContent(type: 'text', text: response.body)],
    );
  }
}
```

---

## 💡 UI Configuration Flow

1. **Launch** – The playground shows the **Setup Screen**.
2. **Select Tools** – Choose from built-in toolsets (Weather, Chart), external MCP servers, or installed servers.
3. **Configure LLM** – Use the default or toggle the custom override to set a different model/provider for the session.
4. **System Prompt** – Enter instructions that define the agent's behavior.
5. **Initial Prompt** – Optionally pre-fill a first message that executes immediately on start.
6. **Start Playground** – Begins the agentic chat session with the selected tools and LLM.

---

## 🔧 Running on Different Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ | Full support |
| iOS | ✅ | Full support |
| Web | ✅ | See [CORS caveats](../README.md#-web-mode-restrictions--cors) |
| macOS | ✅ | Full support (SSH tools available) |
| Windows | ✅ | Full support (SSH tools available) |
| Linux | ✅ | Full support (SSH tools available) |

---

## 📄 License

Same as the parent package — MIT.
