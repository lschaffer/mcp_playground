# AGENTS.md

Welcome! This document provides operational context and constraints for AI agents working on the `mcp_playground_flutter` repository.

## Project Overview

- **Technologies**: Dart, Flutter.
- **Framework Target**: Stands as a standalone, lightweight Flutter package providing an AI Agent Playground widget (`McpPlayground`).
- **Core Integrations**:
  - Direct HTTP/HTTPS client adapters for LLM providers: OpenAI (`openai_dart`), Anthropic (`anthropic_sdk_dart`), Gemini (`google_generative_ai`), and Ollama (`ollama_dart`).
  - Model Context Protocol (MCP) clients using HTTP/HTTPS and Server-Sent Events (SSE).
  - Desktop-only stdio transport for local Node.js/Python MCP subprocesses.

## Build & Verification Commands

Ensure these commands run cleanly before submitting any changes:

```powershell
# Analyze codebase for lints, errors, and warnings
flutter analyze

# Run the test suite
flutter test
```

## Key Constraints & Guidelines

### 1. State Management
- **Rule**: Use strictly **vanilla Flutter state management** (e.g. `ChangeNotifier`, `ValueNotifier`, `StatefulWidget`).
- **Reasoning**: To keep the package lightweight and easy to integrate, **do not introduce state management frameworks** such as Riverpod, Bloc, MobX, etc.

### 2. Dependency Policy
- **Rule**: Keep dependency additions to a absolute minimum.
- **Reasoning**: Consumers of the package should not be burdened with a heavy transitive dependency footprint. Prefer native Dart or standard package implementations.

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
