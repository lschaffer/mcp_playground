import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

/// Extracts SKILL.md from ZIP archives and parses [SkillManifest].
class SkillZipImporter {
  /// Extracts SKILL.md from ZIP bytes and returns the parsed [SkillManifest]
  /// along with any extra files found in the ZIP.
  ({SkillManifest manifest, Map<String, Uint8List> extraFiles}) importFromZip(
    Uint8List zipBytes,
  ) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // Find SKILL.md
    ArchiveFile? skillMdFile;
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      if (name == 'skill.md' || name.endsWith('/skill.md')) {
        skillMdFile = file;
        break;
      }
    }

    if (skillMdFile == null) {
      throw const FormatException('Invalid skill ZIP: no SKILL.md file found');
    }

    final content = utf8.decode(skillMdFile.content as List<int>);
    final importer = SkillImporter();
    final manifest = importer.parseSkillMd(content);

    // Collect extra files (non-SKILL.md)
    final extraFiles = <String, Uint8List>{};
    for (final file in archive.files) {
      final nameLower = file.name.toLowerCase();
      if (nameLower == 'skill.md' || nameLower.endsWith('/skill.md')) {
        continue;
      }

      // Strip the directory prefix if present
      var relativeName = file.name;
      final slashIdx = file.name.indexOf('/');
      if (slashIdx != -1 && slashIdx < file.name.length - 1) {
        relativeName = file.name.substring(slashIdx + 1);
      }

      if (relativeName.isNotEmpty) {
        final raw = file.content as List<int>;
        extraFiles[relativeName] = Uint8List.fromList(raw);
      }
    }

    return (
      manifest: manifest.copyWith(extraFiles: extraFiles),
      extraFiles: extraFiles,
    );
  }
}
