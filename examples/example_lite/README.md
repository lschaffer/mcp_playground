# MCP Playground — Lite/Desktop Example

A lightweight, developer-focused example of the MCP Playground showing how to run the widget in **headless/pre-configured mode** on desktop systems (macOS, Windows, Linux).

This example is **desktop-only** because it spawns local Python and Node.js processes on the host system to run the MCP servers.

---

## Features Demonstrated

- **Skip Initial Configuration**: Shows how to use the `disableConfigDialog: true` parameter, running the app without prompting the LLM setup drawer on startup.
- **Pre-configured Local MCP Servers**: Uses `initialLocalMcpServers` to register local servers:
  - **Filesystem** (Node.js, package `@modelcontextprotocol/server-filesystem` via `npx` or `npm`)
  - **Git** (Python, package `mcp-server-git` via `uvx`)
- **Auto-Installation & Progress Tracking**: Shows the automatic progress modal dialog at startup when installing the Python and Node.js environments and packages on the host machine.

---

## Host Requirements

To run this example successfully, the following must be installed and available on your host system:
1. **Node.js** (version 18+)
2. **Python 3** (and `uv` tool for `uvx` execution)

---

## Quick Start

```bash
cd examples/example_lite/
flutter pub get
flutter run
```

---

## How to Use

1. Ensure Python 3, `uv`, and Node.js are in your system PATH.
2. Launch the application.
3. On startup, a modal dialog will track the progress of downloading and initializing the virtual environment (`.venv` via Python) and Node.js packages.
4. Interact with the chat interface to query your local filesystem or Git repositories directly using the connected local MCP servers!
