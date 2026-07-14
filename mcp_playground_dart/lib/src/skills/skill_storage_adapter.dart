import 'dart:typed_data';

/// Info about a stored skill returned by the adapter.
class StoredSkillInfo {
  /// Display name of the skill.
  final String name;

  /// ZIP file name (e.g. "weather-assistant.zip").
  final String zipFileName;

  /// When the skill was saved/imported.
  final DateTime savedAt;

  /// Optional description of the skill.
  final String? description;

  const StoredSkillInfo({
    required this.name,
    required this.zipFileName,
    required this.savedAt,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'zipFileName': zipFileName,
    'savedAt': savedAt.toIso8601String(),
    if (description != null) 'description': description,
  };

  factory StoredSkillInfo.fromJson(Map<String, dynamic> json) =>
      StoredSkillInfo(
        name: json['name'] as String,
        zipFileName: json['zipFileName'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        description: json['description'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is StoredSkillInfo &&
      other.name == name &&
      other.zipFileName == zipFileName;

  @override
  int get hashCode => Object.hash(name, zipFileName);
}

/// Abstract adapter for persisting skill ZIP files.
///
/// Implementations decide where and how ZIPs are stored
/// (filesystem, database, cloud, etc.).
abstract class SkillStorageAdapter {
  /// Saves a skill ZIP. Returns the [StoredSkillInfo] with the
  /// [zipFileName] used.
  Future<StoredSkillInfo> saveSkill({
    required String name,
    String? description,
    required Uint8List zipBytes,
  });

  /// Loads a skill ZIP by its [name]. Returns the raw ZIP bytes,
  /// or `null` if the skill is not found or the data is corrupt.
  Future<Uint8List?> loadSkillZip(String name);

  /// Lists all stored skills.
  Future<List<StoredSkillInfo>> listSkills();

  /// Deletes a stored skill by [name].
  Future<void> deleteSkill(String name);

  /// Checks if a skill with the given [name] exists.
  Future<bool> skillExists(String name);
}
