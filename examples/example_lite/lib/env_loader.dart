import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

class EnvLoader {
  static final Map<String, String> _env = {};

  static Future<void> load() async {
    String content = '';
    try {
      final file = File('.env');
      if (await file.exists()) {
        content = await file.readAsString();
      }
    } catch (_) {}

    if (content.trim().isEmpty) {
      try {
        content = await rootBundle.loadString('.env');
      } catch (_) {}
    }

    if (content.isNotEmpty) {
      for (var line in content.split('\n')) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          _env[key] = val;
        }
      }
    }
  }

  static String get(String key, {String defaultValue = ''}) {
    return _env[key] ?? defaultValue;
  }

  static LlmProvider getProvider() {
    final val = get('LLM_PROVIDER').trim().toLowerCase();
    switch (val) {
      case 'openai':
        return LlmProvider.openai;
      case 'claude':
        return LlmProvider.claude;
      case 'gemini':
        return LlmProvider.gemini;
      case 'ollama':
        return LlmProvider.ollama;
      case 'openai-compatible':
      case 'openaicompatible':
        return LlmProvider.openaiCompatible;
      case 'mistral':
        return LlmProvider.mistral;
      default:
        return LlmProvider.none;
    }
  }
}
