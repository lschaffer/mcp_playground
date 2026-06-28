# MCP Playground — UI/Full Example

A complete working example demonstrating how to integrate the full [`mcp_playground_flutter`](https://github.com/laszlovaspali/mcp_playground_flutter) widget into a Flutter application.

This example is **platform-independent** and runs on Android, iOS, Web, macOS, Windows, and Linux.

---

## Features Demonstrated

- **Platform-Independent UI**: Fully responsive playground that works across mobile, web, and desktop.
- **Dart-native local tools**: Features build-in weather, SSH/SFTP (via `dartssh2`), and canvas-based chart-generation tools.
- **Dynamic Configuration**: Connect to any HTTP MCP server or LLM provider using the settings drawer and registry catalogs.

## Quick Start

```bash
cd examples/example_ui/
flutter pub get
flutter run
```

---

## How to Use

1. Launch the application.
2. Select your desired LLM Provider (OpenAI, Anthropic Claude, Google Gemini, Ollama, etc.) and supply your model name and API key.
3. Interact with the chat interface and inspect tool calls, execution phases, and state changes side-by-side using the **Agent Inspector** panel.
