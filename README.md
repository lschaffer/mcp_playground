# mcp_playground

A monorepo for building interactive AI Agent Playgrounds with Model Context Protocol (MCP) support in Dart and Flutter.

---

## 🎥 Demo

Teaser of the Flutter AI Agent Playground executing shell commands via SSH and rendering dynamic charts in real time:

<video src="screenshots/video/mcp_playground_ssh_chart_test.mp4" width="100%" controls></video>

*(If the video doesn't play, you can watch or download it directly [here](screenshots/video/mcp_playground_ssh_chart_test.mp4))*

---

## 📁 Repository Structure

This repository contains two main packages and multiple showcase applications:

### Packages

1. **[`mcp_playground_dart`](mcp_playground_dart)** (Pure Dart Core)
   * Standalone Dart package with **zero Flutter dependency**.
   * Integrates LLM providers: OpenAI, Claude, Gemini, Ollama, and Mistral.
   * Fully implements the JSON-RPC 2.0 Model Context Protocol (MCP) client specification (for remote HTTP/SSE and desktop stdio subprocess execution).
   * Orchestrates the agent execution loop and multi-step prompt chaining via the `McpAgentEngine`.
2. **[`mcp_playground_flutter`](mcp_playground_flutter)** (Flutter Widget Library)
   * Provides the full `McpPlayground` widget UI.
   * Extends the core engine with a chat interface, code markdown rendering, file attachments, and an Agent Inspector tab.
   * Auto-installs local Node.js/Python MCP servers and provides progress modals.
   * Integrates embedded (on-device) GGUF models (`llamadart`) with HuggingFace model search and download progress bars.

### Example Applications

* **[`example`](example)**: A comprehensive, feature-rich Flutter showcase application. Implements custom local tools (SSH/SFTP, Open-Meteo Weather, Canvas-based chart generation) and intercepts tool calls to draw interactive `fl_chart` elements inline in the chat bubble.
* **[`example_embedded`](example_embedded)**: A Flutter application demonstrating fully offline, local on-device GGUF execution, showing automatic HuggingFace download/load progress dialogs.
* **[`example_dart`](example_dart)**: A lightweight command-line tool demonstration showcasing how to run headlessly, register weather tools, run multi-prompt scripts, and save generated PNG charts directly to disk from pure Dart.

---

## 🚀 Getting Started

Depending on your integration style:

### Flutter Widget Integration
Add `mcp_playground_flutter` to your app:
```yaml
dependencies:
  mcp_playground_flutter: ^0.0.13
```
Then see the [mcp_playground_flutter README](mcp_playground_flutter/README.md) for usage and parameters.

### Pure Dart CLI/Backend Integration
Add `mcp_playground_dart` to your CLI or server app:
```yaml
dependencies:
  mcp_playground_dart: ^0.1.0
```
Then see the [mcp_playground_dart README](mcp_playground_dart/README.md) for headless execution guidelines.
