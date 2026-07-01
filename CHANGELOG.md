## 0.0.9

* Cached `SharedPreferences` instances inside both storage delegates and model managers to eliminate redundant async initialization overhead.
* Cached LLM clients (OpenAI, Anthropic, Gemini, Ollama) by provider, base URL, and API key in a static cache inside `LLMService` to reuse HTTP connections.
* Extracted MIME mapping and text file detection logic into a unified utility module `src/utils/mime_utils.dart` to resolve code duplication.
* Split `mcp_playground.dart` by relocating `InitialMcpInstallProgressDialog` into its own file under `src/widgets/`.
* Extracted repetitive server connection and caching tool logic to a private helper `_connectClientAndCacheTools` in `PlaygroundController`.
* Added catalog caching support to `McpPlaygroundStorageDelegate` and re-routed registry catalog persistence through the storage delegate.
* Replaced unstable hashCode-based tool call IDs with proper stable UUIDs.
* Unified execution iteration limits and eliminated a redundant inner step limits loop.
* Suppressed system prompt tool description text injection when native tool calling is active.
* Added a safety guard to `ChangeNotifier` updates in `MCPClient` to prevent "used after being disposed" errors from asynchronous disconnection calls.

## 0.0.8

* Added lenient HTML document parsing and a collapsed "HTML Document Preview" magnifier view modal to robot messages.
* Fixed on-demand tool discovery in the tools catalog dialog by triggering local process connections on dialog load and gracefully shutting down inactive servers upon close.
* Implemented comprehensive translations and localizations support for HTML previews, dialog messages, and tab names in English and German.
* Upgraded Kotlin compiler version in the example app to `2.2.20` to support modern Gradle compilation.
* Filtered base64 image strings from monospace text preview bubbles and LLM request payloads to optimize context tokens.
* Added auto-detection of JSON-embedded spreadsheets and binary files, stripping base64 payloads to show interactive file download cards instead.

## 0.0.7

* Replaced the standard chat message `TextField` input bar in the active chat view with `SubPromptListEditor`, providing the identical multi-prompt entry field, step navigation, and active tools selectors in active chat view.
* Filtered step-specific tool checklist selectors and dropdowns in `SubPromptListEditor` to show tools belonging exclusively to active/enabled toolsets.
* Fixed auto-enabling behavior for default/initial local MCP servers installed in background post-frame calls on the very first start, fully guaranteeing zero preselected tools on startup when no configurations are loaded.

## 0.0.6

* Corrected tool state auto-selection on initial app startup: now, if no configuration setup exists, no tools are selected by default.
* Removed the massive 1200+ line hardcoded JSON registry list from `mcp_server_registry_tab.dart` so it always fetches registry definitions dynamically from the GitHub repository registry.
* Resolved local MCP subprocess connection timeouts and hangs on Windows by invoking process creation with shell integration (`runInShell: Platform.isWindows`).
* Increased JSON-RPC call timeout to 60 seconds to allow slow local node packages to initialize successfully.
* Added a trailing expand details icon to log tiles in the `AgentInspector` panel, and refactored log list entries to present properly formatted previews of system prompts, user questions, tool calls, and execution results.

## 0.0.5

* Implemented multi-prompt step chaining supporting sequential sub-prompt execution, output piping using `${tool_result}` / `${task_result}` placeholders, per-step active tools filtering, and per-step "stop after tool call" execution flags.
* Added `SubPromptListEditor` widget to edit multi-prompts on the initial setup screen, featuring desktop side-by-side and mobile stack layouts.
* Refactored active tools selection in playground chat to display only tools belonging to the selected toolset (group) via a dropdown selector, sorting tools alphabetically.
* Provided mobile fullscreen tool selection dialogs using `Dialog.fullscreen`.
* Added persistent tool selection and server initialization tracking to save active configuration across restarts.
* Updated chat input bar tools selector icon dynamically (all, some, none active tools status states).
* Added active tool schemas (names, descriptions, input schemas) into the system prompt to guide LLMs and improve tool calling correctness.
* Introduced a togglable widget event logging parameter (`enableLogging`) printing formatted user messages, system prompts, tool calls, and results.
* Wrapped long tool call names in the chat execution bubble headers by removing truncation behavior.

## 0.0.4

* Improved tool selection dialogs on both the setup screen and chat view by adding per-toolset and global "All / None" toggling controls.
* Prevented toolset groups from disappearing from the chat selection dialog when all their tools are deselected.
* Fixed an issue where external HTTP MCP servers would disappear from the available toolsets list after executing a turn by retaining configured clients regardless of transient connection status.
* Added base64 image and file parsing in chat bubbles to properly render inline image/file attachments (such as PNG charts or spreadsheets) and supported safe, error-free file downloading on Android using scoped storage bytes saving.
* Replaced the hardcoded GitHub MCP server list with an online-fetched list loaded from the remote registry, caching the registry for 24 hours.
* Commited the missing agent walkthrough document back to version control.

## 0.0.3

* Restructured folder layout to relocate all internal widgets and client submodules under the private `lib/src/` directory.
* Added comprehensive dartdoc comments to all exported public API classes, properties, and methods to secure full documentation score points on pub.dev.
* Refined package description metadata in `pubspec.yaml` to note support for local Node.js and Python subprocesses.

## 0.0.2

* Upgraded `openai_dart` to `^7.0.0`, `anthropic_sdk_dart` to `^5.0.0`, and `ollama_dart` to `^2.3.0` and rebuilt all client adapters to match the new SDK specifications.
* Hid the Load, Save, and Clear configuration buttons in the active play/chat view to restrict them only to the initialization screen.
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
