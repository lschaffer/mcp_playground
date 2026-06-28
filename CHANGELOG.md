## 0.0.2

* Upgraded `file_picker` dependency to `^11.0.2` (migrated to static API).
* Upgraded `flutter_lints` dependency to `^6.0.0` and cleaned linter syntax.
* Fixed broken visual preview image links in example documentation to use relative paths for pub.dev CDN compatibility.
* Split chart generation examples into distinct "Interactive (fl_chart)" and "PNG Image (canvas)" select tool checkboxes.

## 0.0.1

* Initial release of `mcp_playground_flutter`.
* Interactive AI Agent Playground widget with setup and conversation views.
* Multi-LLM support: OpenAI, Anthropic Claude, Google Gemini, Ollama, Mistral AI, and OpenAI-compatible endpoints.
* HTTP MCP Server registry with PulseMCP and Smithery catalog browsing.
* Dart-native local tool system with built-in weather, SSH/SFTP, and chart-generation tools.
* Agentic tool-calling loop with duplicate detection, iteration limits, and safety guards.
* Save/load playground configurations (LLM settings, tool selections, server lists, system prompts).
* Agent Inspector for debugging agent state and conversation history.
* Custom persistence via `McpPlaygroundStorageDelegate`.
* Cross-platform: Android, iOS, Web, macOS, Windows, Linux.
