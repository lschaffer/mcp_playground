import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

/// Creates ZIP archives from [SkillManifest] instances.
class SkillZipExporter {
  /// Creates a ZIP archive containing SKILL.md and optional extra files.
  ///
  /// Returns the raw ZIP bytes ready for storage via a [SkillStorageAdapter].
  Future<Uint8List> exportToZip({
    required SkillManifest manifest,
    Map<String, Uint8List>? extraFiles,
  }) async {
    final archive = Archive();

    // Create the skill directory prefix
    final dirPrefix = '${manifest.name}/';

    // Add SKILL.md
    final exporter = SkillExporter();
    final skillMdContent = utf8.encode(exporter.toSkillMd(manifest));
    archive.addFile(
      ArchiveFile(
        '${dirPrefix}SKILL.md',
        skillMdContent.length,
        skillMdContent,
      ),
    );

    // Add extra files if provided
    if (extraFiles != null) {
      for (final entry in extraFiles.entries) {
        final filename = entry.key;
        final bytes = entry.value;
        archive.addFile(
          ArchiveFile('$dirPrefix$filename', bytes.length, bytes),
        );
      }
    }

    // Encode the archive to ZIP bytes
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }
}
