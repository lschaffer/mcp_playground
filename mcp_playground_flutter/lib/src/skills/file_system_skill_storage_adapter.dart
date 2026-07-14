import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

/// Default [SkillStorageAdapter] for desktop and mobile platforms.
///
/// Stores skill ZIP files in a directory on the local filesystem,
/// tracking them via a `skills-defs.json` manifest file.
class FileSystemSkillStorageAdapter implements SkillStorageAdapter {
  final String rootPath;

  const FileSystemSkillStorageAdapter({required this.rootPath});

  String get _defsPath => '$rootPath${Platform.pathSeparator}skills-defs.json';

  @override
  Future<StoredSkillInfo> saveSkill({
    required String name,
    String? description,
    required Uint8List zipBytes,
  }) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final zipFileName = '${_sanitizeForFilename(name)}.zip';
    final zipPath = '$rootPath${Platform.pathSeparator}$zipFileName';

    // Write the ZIP file
    await File(zipPath).writeAsBytes(zipBytes);

    // Update the manifest
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
    final defs = await _loadDefs();
    final info = defs.where((d) => d.name == name).firstOrNull;
    if (info == null) return null;

    final zipPath = '$rootPath${Platform.pathSeparator}${info.zipFileName}';
    final file = File(zipPath);
    if (!await file.exists()) return null;

    try {
      return await file.readAsBytes();
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
    final defs = await _loadDefs();
    final info = defs.where((d) => d.name == name).firstOrNull;
    if (info == null) return;

    // Delete the ZIP file
    final zipPath = '$rootPath${Platform.pathSeparator}${info.zipFileName}';
    final file = File(zipPath);
    if (await file.exists()) {
      await file.delete();
    }

    // Update manifest
    defs.removeWhere((d) => d.name == name);
    await _saveDefs(defs);
  }

  @override
  Future<bool> skillExists(String name) async {
    final defs = await _loadDefs();
    return defs.any((d) => d.name == name);
  }

  // ── Manifest helpers ────────────────────────────────────────────

  Future<List<StoredSkillInfo>> _loadDefs() async {
    final file = File(_defsPath);
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => StoredSkillInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveDefs(List<StoredSkillInfo> defs) async {
    final list = defs.map((d) => d.toJson()).toList();
    await File(
      _defsPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(list));
  }

  String _sanitizeForFilename(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
