# AGENTS.md

Welcome! This document provides operational context and constraints for AI agents working on the `mcp_playground` monorepo.

## Project Overview

- **Technologies**: Dart, Flutter.
- **Packages**:
  - **`mcp_playground_dart`**: A headless, pure-Dart package providing the core client transport, model service adapters, and `McpAgentEngine` loops (no Flutter dependencies).
  - **`mcp_playground_flutter`**: An interactive UI widget library providing the playground, chat layouts, and inspector views.
- **Core Integrations**:
  - Direct HTTP/HTTPS client adapters for LLM providers: OpenAI (`openai_dart`), Anthropic (`anthropic_sdk_dart`), Gemini (`google_generative_ai`), and Ollama (`ollama_dart`).
  - Dynamic completion delegates (`embeddedHandler` / `embeddedStreamHandler`) to route local `LlmProvider.embedded` inference calls via desktop-native FFI runtimes (`llamadart`).
  - Model Context Protocol (MCP) clients using HTTP/HTTPS, Server-Sent Events (SSE), and stdio transport subprocesses.

## Build & Verification Commands

Ensure these commands run cleanly inside their respective packages before submitting any changes:

### `mcp_playground_dart`
```powershell
# Analyze package for lints and warnings
dart analyze

# Run unit test suite
dart test
```

### `mcp_playground_flutter`
```powershell
# Analyze package for lints and warnings
flutter analyze

# Run package tests
flutter test
```

## Key Constraints & Guidelines

### 1. State Management
- **Rule**: Use strictly **vanilla Flutter state management** (e.g. `ChangeNotifier`, `ValueNotifier`, `StatefulWidget`) inside `mcp_playground_flutter`.
- **Reasoning**: To keep the package lightweight and easy to integrate, **do not introduce state management frameworks** such as Riverpod, Bloc, MobX, etc.

### 2. Dependency Policy
- **Rule**: Keep dependency additions to an absolute minimum.
- **Reasoning**: Consumers of the packages should not be burdened with a heavy transitive dependency footprint. Prefer native Dart or standard package implementations.

### 3. Cross-Platform Compatibility & Sandbox
- **Rule**: Standard file and subprocess APIs (`dart:io`) are restricted to desktop platforms (Windows, macOS, Linux).
- **Reasoning**: The widget runs on Web and Mobile (Android, iOS) where running child subprocesses or direct file system access is unsupported. Ensure web/mobile execution paths use appropriate platform guards or fall back gracefully.
- **Web CORS**: Remember that Flutter Web requests to external MCP servers must respect browser CORS policies.

### 4. API & SDK Integration Patterns
- **Anthropic Union Mapping**: When mapping Anthropic response blocks, do not use `block.map(...)` as it breaks when new union variants are added by the SDK. Use type checking:
  ```dart
  if (block is anthropic.TextBlock) { ... }
  ```
- **Gemini API**: System instruction needs to be structured via `gemini.Content.system(...)`.
- **Ollama Null Safety**: Tool call fields returned from Ollama messages can be null. Check them safely.
- **Embedded Model Delegates**: Do not import `llamadart` or other native binary dependencies directly inside the headless `mcp_playground_dart` library. Access them purely through the pluggable `LLMService.embeddedHandler` and `LLMService.embeddedStreamHandler` static delegate hooks.
