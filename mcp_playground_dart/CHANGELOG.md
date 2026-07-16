## 0.2.1

- Added `McpAgentEngine.registerAgentFromManifest()` — builds and registers an `Agent` directly from a parsed `SkillManifest`, handling tool-declaration → `McpServerConfig` mapping and prompt-step conversion. Accepts optional `dartTools`, `workingDir`, and `serverOverrides`.
- Updated `SkillExporter.toSkillMd()` compatibility tag from `mcp_playground` to `"Universal"` to match agentskills.io TealKit standard.
- Added `dartTools` parameter to `registerAgentFromManifest()` for Dart-native local tool injection (weather, charts, SSH).

## 0.2.0

- **BREAKING**: SKILL.md export/import format changed to agentskills.io TealKit-compatible standard (`compatibility:`, `metadata:`, `workflow:`, `agents:`). Legacy custom format (`system_prompt:`, `prompts:`, `tools:`) is deprecated.
- Added `SkillManifest`, `SkillPromptStep`, `SkillToolDeclaration` models with 3-tier portability (`capability`, `local`, `external`).
- Added `SkillExporter` — converts `SavedPlaygroundSetup`/conversation → SKILL.md YAML frontmatter.
- Added `SkillImporter` — parses SKILL.md (both TealKit and legacy formats) → `SavedPlaygroundSetup` with multi-prompt step conversion.
- Added `SkillStorageAdapter` abstract interface with `StoredSkillInfo` for pluggable skill ZIP persistence.
- Added `yaml` dependency for robust YAML parsing.

## 0.1.4

- Upgraded dependencies: `anthropic_sdk_dart` to `^6.0.0`, `googleai_dart` to `^9.0.0`, `ollama_dart` to `^2.4.0`, `http` to `^1.6.0`.

## 0.1.3

- Refactored streaming support for Small Language Models (SLMs) and embedded models.
- Added dynamic static delegates `embeddedHandler` and `embeddedStreamHandler` to plug on-device inference engines without hard code dependencies.
- Added a new headless CLI example `embedded_example` demonstrating on-device Hugging Face GGUF model downloading, offline inference, local weather tool execution, and token-by-token terminal stream outputs.

## 0.1.2

- Expose `agentEvents` stream in `McpAgentEngine` and return a reactive event stream from `runAsync` for asynchronous streaming execution.
- Add support for loading `LlmConfig` hyperparameters (`temperature`, `maxTokens`, `topP`, `topK`, `repeatPenalty`) inside provider clients.
- Isolate local stdio client dependencies from web/wasm builds via default stub conditional imports.
- Protocol and logging compliance updates.

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
