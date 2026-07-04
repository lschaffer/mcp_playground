## 0.1.1

- Fixed WASM and Web compilation by integrating `universal_io` for subprocess/file wrappers.
- Added pure Dart `McpChangeNotifier` to core clients to remove Flutter dependencies.
- Added comprehensive self-contained package example for pub.dev.

## 0.1.0

- Initial release of the pure-Dart core package.
- Built-in multi-LLM SDK adapters (OpenAI, Claude, Gemini, Ollama, Mistral).
- HTTP/SSE stateful Model Context Protocol (MCP) clients with authentication and health-monitoring reconnection.
- Desktop stdio process execution client for Node.js and Python MCP servers.
- Core `McpAgentEngine` supporting sub-prompt orchestration pipelines, iterative tool loops, and loop-protection.
