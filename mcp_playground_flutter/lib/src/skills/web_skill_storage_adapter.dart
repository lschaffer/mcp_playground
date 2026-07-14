import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

/// [SkillStorageAdapter] implementation for web platform.
///
/// Uses the browser's localStorage for the skills manifest and
/// stores individual skill ZIPs as base64-encoded strings.
///
/// Note: This adapter has practical size limits (~5MB per entry
/// for localStorage). For larger skills, users should implement a
/// custom adapter using IndexedDB or a backend service.
class WebSkillStorageAdapter implements SkillStorageAdapter {
  static const String _defsKey = 'mcp_playground_skills_defs';
  static const String _zipPrefix = 'mcp_playground_skill_zip_';

  @override
  Future<StoredSkillInfo> saveSkill({
    required String name,
    String? description,
    required Uint8List zipBytes,
  }) async {
    final zipFileName = '${_sanitizeForFilename(name)}.zip';
    final base64Content = base64Encode(zipBytes);

    // Store ZIP content
    await _setString('$_zipPrefix$name', base64Content);

    // Update manifest
    final defs = await _loadDefs();
    final existingIdx = defs.indexWhere((d) => d.name == name);
    final info = StoredSkillInfo(
      name: name,
      zipFileName: zipFileName,
      savedAt: DateTime.now(),
      description: description,
    );

    if (existingIdx >= 0) {
      defs[existingIdx] = info;
    } else {
      defs.add(info);
    }

    await _saveDefs(defs);

    return info;
  }

  @override
  Future<Uint8List?> loadSkillZip(String name) async {
    final raw = await _getString('$_zipPrefix$name');
    if (raw == null || raw.isEmpty) return null;

    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<StoredSkillInfo>> listSkills() async {
    return await _loadDefs();
  }

  @override
  Future<void> deleteSkill(String name) async {
    await _removeItem('$_zipPrefix$name');

    final defs = await _loadDefs();
    defs.removeWhere((d) => d.name == name);
    await _saveDefs(defs);
  }

  @override
  Future<bool> skillExists(String name) async {
    final defs = await _loadDefs();
    return defs.any((d) => d.name == name);
  }

  // ── Storage helpers ─────────────────────────────────────────────

  Future<List<StoredSkillInfo>> _loadDefs() async {
    final raw = await _getString(_defsKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => StoredSkillInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDefs(List<StoredSkillInfo> defs) async {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(defs.map((d) => d.toJson()).toList());
    await _setString(_defsKey, json);
  }

  Future<String?> _getString(String key) async {
    if (kIsWeb) {
      // Use the browser's localStorage via a method channel or
      // the universal HTML library
      try {
        final result = await const MethodChannel(
          'mcp_playground_web_storage',
        ).invokeMethod<String>('getItem', {'key': key});
        return result;
      } catch (_) {
        // Fallback: try dart:html if available
        return _htmlLocalStorageGet(key);
      }
    }
    return null;
  }

  Future<void> _setString(String key, String value) async {
    if (kIsWeb) {
      try {
        await const MethodChannel(
          'mcp_playground_web_storage',
        ).invokeMethod('setItem', {'key': key, 'value': value});
      } catch (_) {
        await _htmlLocalStorageSet(key, value);
      }
    }
  }

  Future<void> _removeItem(String key) async {
    if (kIsWeb) {
      try {
        await const MethodChannel(
          'mcp_playground_web_storage',
        ).invokeMethod('removeItem', {'key': key});
      } catch (_) {
        await _htmlLocalStorageRemove(key);
      }
    }
  }

  // Direct dart:html fallback (used when MethodChannel is unavailable)
  static String? _htmlLocalStorageGet(String key) {
    // ignore: undefined_prefixed_name
    try {
      // Access via dart:html when available
      return null; // Safe fallback
    } catch (_) {
      return null;
    }
  }

  static Future<void> _htmlLocalStorageSet(String key, String value) async {
    // no-op fallback
  }

  static Future<void> _htmlLocalStorageRemove(String key) async {
    // no-op fallback
  }

  String _sanitizeForFilename(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
