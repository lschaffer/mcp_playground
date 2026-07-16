import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import '../../playground_controller.dart';
import '../skills/skill_zip_exporter.dart';
import '../skills/skill_zip_importer.dart';

/// Dialog for saving the current playground state as a skill ZIP.
///
/// Gathers all user prompts from the chat conversation history,
/// flattens subprompts, includes the unsent input if present,
/// and serializes as a multi-step skill.
class SkillSaveDialog extends StatefulWidget {
  final PlaygroundController controller;
  final String? unsentInput;

  const SkillSaveDialog({
    super.key,
    required this.controller,
    this.unsentInput,
  });

  @override
  State<SkillSaveDialog> createState() => _SkillSaveDialogState();
}

class _SkillSaveDialogState extends State<SkillSaveDialog> {
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(() {});
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  /// Gathers all user prompts from the conversation, flattens subprompts,
  /// includes unsent input, and builds prompt steps with per-turn tool info.
  List<SubPromptStep> _gatherPromptSteps() {
    final steps = <SubPromptStep>[];

    // Collect user messages from chat history (skip tool-result "user" messages)
    for (final msg in widget.controller.messages) {
      if (msg.role != ChatRole.user) continue;
      final text = msg.content.trim();
      if (text.isEmpty) continue;

      // Parse subprompts from this message (may contain ++#++ separators)
      final subSteps = parseSubPromptSteps(text);
      for (final sub in subSteps) {
        if (sub.text.trim().isNotEmpty) {
          steps.add(sub);
        }
      }
    }

    // Include the currently typed (unsent) prompt if present
    if (widget.unsentInput != null && widget.unsentInput!.trim().isNotEmpty) {
      final unsentSteps = parseSubPromptSteps(widget.unsentInput!.trim());
      for (final sub in unsentSteps) {
        if (sub.text.trim().isNotEmpty) {
          // Use current enabled tools for unsent prompt
          final currentTools = widget.controller.enabledToolNames.isEmpty
              ? null
              : widget.controller.enabledToolNames.toList();
          steps.add(
            SubPromptStep(
              text: sub.text,
              enabledToolNames: sub.enabledToolNames ?? currentTools,
              stopAfterToolCall: sub.stopAfterToolCall,
            ),
          );
        }
      }
    }

    // If no steps found, create a single step from the setup
    if (steps.isEmpty) {
      steps.add(
        SubPromptStep(
          text: '',
          enabledToolNames: widget.controller.enabledToolNames.isEmpty
              ? null
              : widget.controller.enabledToolNames.toList(),
        ),
      );
    }

    return steps;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final zipExporter = SkillZipExporter();

      // Gather prompt steps from conversation + unsent input
      final promptSteps = _gatherPromptSteps();

      // Build manifest
      final manifest = SkillManifest(
        name: _sanitizeName(name),
        description: _descriptionCtrl.text.trim(),
        version: '1.0.0',
        author: 'mcp_playground',
        systemPrompt: widget.controller.systemPrompt,
        promptSteps: promptSteps
            .map(
              (s) => SkillPromptStep(
                text: s.text,
                enabledToolNames: s.enabledToolNames,
                stopAfterToolCall: s.stopAfterToolCall,
              ),
            )
            .toList(),
        tools: [],
        mcpPlaygroundMeta: McpPlaygroundSkillMetadata(
          chatMode: widget.controller.chatMode,
          stopAfterToolCall: widget.controller.stopAfterToolCall,
          useCustomLlm: widget.controller.customLlmConfig != null,
          createdAt: DateTime.now(),
          isMultiTurn: promptSteps.length > 1,
        ),
        isMultiTurn: promptSteps.length > 1,
      );

      final exporter = SkillExporter();
      final md = exporter.toSkillMd(manifest);
      debugPrint(
        '[SaveSkill] SKILL.md preview (first 500 chars):\n${md.substring(0, md.length < 500 ? md.length : 500)}',
      );

      final zipBytes = await zipExporter.exportToZip(manifest: manifest);

      await widget.controller.skillStorage.saveSkill(
        name: name,
        description: _descriptionCtrl.text.trim(),
        zipBytes: zipBytes,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Skill "$name" saved (${promptSteps.length} step${promptSteps.length == 1 ? '' : 's'}).',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save skill: $e';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepCount = _gatherPromptSteps().length;

    return AlertDialog(
      title: const Text('Save Skill'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Skill Name',
                hintText: 'e.g. weather-assistant',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What does this skill do?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stepCount > 1
                          ? '$stepCount prompt steps will be captured from conversation history'
                          : 'Single prompt will be saved',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _nameCtrl.text.trim().isEmpty ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Skill'),
        ),
      ],
    );
  }

  String _sanitizeName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

/// Dialog for loading/importing a saved skill.
class SkillLoadDialog extends StatefulWidget {
  final PlaygroundController controller;

  const SkillLoadDialog({super.key, required this.controller});

  @override
  State<SkillLoadDialog> createState() => _SkillLoadDialogState();
}

class _SkillLoadDialogState extends State<SkillLoadDialog> {
  List<StoredSkillInfo> _skills = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    try {
      final skills = await widget.controller.skillStorage.listSkills();
      if (mounted) {
        setState(() {
          _skills = skills;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load skills: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSkill(StoredSkillInfo info) async {
    setState(() => _loading = true);

    try {
      final zipBytes = await widget.controller.skillStorage.loadSkillZip(
        info.name,
      );
      if (zipBytes == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Skill "${info.name}" not found or corrupt.';
            _loading = false;
          });
        }
        return;
      }

      final importer = SkillZipImporter();
      final result = importer.importFromZip(zipBytes);
      final manifest = result.manifest;

      final setup = _manifestToSetup(manifest);

      if (!mounted) return;

      // Save to controller's saved setups
      await widget.controller.saveSetup(setup);

      if (!mounted) return;

      Navigator.of(context).pop(setup);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load skill: $e';
          _loading = false;
        });
      }
    }
  }

  /// Converts a [SkillManifest] to [SavedPlaygroundSetup] using the shared
  /// [SkillImporter.toSetup] helper. For direct agent execution (skipping
  /// config storage), use [McpAgentEngine.registerAgentFromManifest] instead.
  SavedPlaygroundSetup _manifestToSetup(SkillManifest manifest) {
    final skillImporter = SkillImporter();
    final allToolNames = {
      for (final t in widget.controller.localTools) t.name,
      for (final t in widget.controller.externalTools) t.name,
    };
    final setup = skillImporter.toSetup(
      manifest,
      availableToolNames: allToolNames,
    );
    skillImporter.getUnresolvableTools(manifest, allToolNames);
    return setup;
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'md'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      SkillManifest manifest;
      if (file.extension?.toLowerCase() == 'md') {
        // Direct SKILL.md file
        final content = utf8.decode(bytes);
        manifest = SkillImporter().parseSkillMd(content);
      } else {
        // ZIP file
        final importer = SkillZipImporter();
        final zipResult = importer.importFromZip(bytes);
        manifest = zipResult.manifest;
      }

      // Convert manifest to setup using shared helper.
      // For direct execution use McpAgentEngine.registerAgentFromManifest.
      final setup = _manifestToSetup(manifest);

      if (!mounted) return;
      await widget.controller.saveSetup(setup);
      if (!mounted) return;

      Navigator.of(context).pop(setup);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load Skill'),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('Import Skill from File'),
                onPressed: _importFromFile,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null && _skills.isEmpty
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    )
                  : _skills.isEmpty
                  ? const Center(
                      child: Text(
                        'No saved skills found.\n\nUse "Save Skill" to create one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _skills.length,
                      itemBuilder: (ctx, idx) {
                        final skill = _skills[idx];
                        return ListTile(
                          title: Text(
                            skill.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (skill.description != null &&
                                  skill.description!.isNotEmpty)
                                Text(
                                  skill.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                skill.zipFileName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: () async {
                              await widget.controller.skillStorage.deleteSkill(
                                skill.name,
                              );
                              _loadSkills();
                            },
                          ),
                          onTap: () => _loadSkill(skill),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
