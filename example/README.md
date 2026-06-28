# MCP Playground Examples Showcase

This directory contains a consolidated showcase application demonstrating how to integrate the [`mcp_playground_flutter`](https://pub.dev/packages/mcp_playground_flutter) widget into a Flutter project.

It provides a selection interface to launch either the **Full UI Example** or the **Lite Desktop Example**.

---

## 🎨 Visual Preview

Here is how the playground and its configuration interfaces look:

### LLM Provider Setup
![LLM Config](https://raw.githubusercontent.com/lschaffer/mcp_playground/main/screenshots/example_ui/playground_config_llm.png)

### Local MCP Subprocesses Setup (Desktop Mode)
![Local MCP Config](https://raw.githubusercontent.com/lschaffer/mcp_playground/main/screenshots/example_ui/playground_config_local_mcp.png)

### Filesystem MCP Server Integration
![Filesystem MCP Test](https://raw.githubusercontent.com/lschaffer/mcp_playground/main/screenshots/example_ui/filesystem_mcp_test.png)

---

## 🚀 How to Run

1. Navigate to the `example/` directory:
   ```bash
   cd example/
   ```
2. Copy the template `.env` and fill in your provider keys and parameters:
   ```env
   LLM_PROVIDER=openai
   LLM_MODEL=gpt-4o-mini
   LLM_API_KEY=your_key_here
   ```
3. Run the application:
   ```bash
   flutter pub get
   flutter run
   ```

---

## 📦 Demonstrations Included

### 1. Full UI Example (Multiplatform)
- **Target**: Web, Android, iOS, Windows, macOS, Linux.
- **Features**: Registers built-in Dart-native tools (Weather forecast, SSH/SFTP terminal actions, and canvas-based PNG chart generators) and connects dynamically to remote HTTP MCP servers.
- **Visuals**:
  ![Local Dart MCP Test](https://raw.githubusercontent.com/lschaffer/mcp_playground/main/screenshots/example_ui/local_dart_mcp_test.png)

### 2. Lite Desktop Example (Desktop Only)
- **Target**: macOS, Windows, Linux.
- **Features**: Bypasses the configuration setup dialog on startup (`disableConfigDialog: true`) using credentials loaded from `.env`. Automatically registers and spawns local subprocess stdio MCP servers:
  - **Git** (runs `mcp-server-git` via `uvx`)
  - **Filesystem** (runs `@modelcontextprotocol/server-filesystem` via `npx` or `npm`)
- **Host Requirements**:
  - **Node.js** (for npx filesystem actions)
  - **Python 3** & **`uv`** tool (for uvx git actions)
