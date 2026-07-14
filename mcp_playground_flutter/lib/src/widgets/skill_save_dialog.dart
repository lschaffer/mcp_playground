import 'package:flutter/material.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import '../../playground_controller.dart';
import '../skills/skill_zip_exporter.dart';
import '../skills/skill_zip_importer.dart';

/// Dialog for saving the current playground state as a skill ZIP.
class SkillSaveDialog extends StatefulWidget {
  final PlaygroundController controller;

  const SkillSaveDialog({super.key, required this.controller});

  @override
  State<SkillSaveDialog> createState() => _SkillSaveDialogState();
}

class _SkillSaveDialogState extends State<SkillSaveDialog> {
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _wholeWorkflow = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final exporter = SkillExporter();
      final zipExporter = SkillZipExporter();

      SkillManifest manifest;
      if (_wholeWorkflow && widget.controller.messages.isNotEmpty) {
        // Export conversation as skill
        manifest = exporter.fromConversation(
          name: name,
          description: _descriptionCtrl.text.trim(),
          systemPrompt: widget.controller.systemPrompt,
          conversation: widget.controller.messages,
          servers: widget.controller.servers,
          localTools: widget.controller.localTools,
          enabledToolNames: widget.controller.enabledToolNames,
        );
      } else {
        // Export the current active setup
        final setup = SavedPlaygroundSetup(
          id: 'export_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          description: _descriptionCtrl.text.trim(),
          createdAt: DateTime.now(),
          systemPrompt: widget.controller.systemPrompt,
          initialPrompt: '',
          enabledToolNames: widget.controller.enabledToolNames.toList(),
          chatMode: widget.controller.chatMode,
          stopAfterToolCall: widget.controller.stopAfterToolCall,
          useCustomLlm: widget.controller.customLlmConfig != null,
          customLlmConfig: widget.controller.customLlmConfig,
        );
        manifest = exporter.fromSetup(
          setup,
          servers: widget.controller.servers,
          localTools: widget.controller.localTools,
        );
      }

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
            content: Text('Skill "$name" saved successfully.'),
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
    final hasConversation = widget.controller.messages.isNotEmpty;

    return AlertDialog(
      title: const Text('Save as Skill'),
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
            if (hasConversation) ...[
              const SizedBox(height: 16),
              const Text(
                'Export Scope',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Whole workflow'),
                    icon: Icon(Icons.history, size: 18),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Setup only'),
                    icon: Icon(Icons.tune, size: 18),
                  ),
                ],
                selected: {_wholeWorkflow},
                onSelectionChanged: (v) =>
                    setState(() => _wholeWorkflow = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                _wholeWorkflow
                    ? 'All conversation turns will be captured as prompt steps'
                    : 'Only the current system prompt + tools configuration',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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

      final skillImporter = SkillImporter();
      final allToolNames = {
        for (final t in widget.controller.localTools) t.name,
        for (final t in widget.controller.externalTools) t.name,
      };
      final setup = skillImporter.toSetup(
        manifest,
        availableToolNames: allToolNames,
      );
      final missingTools = skillImporter.getUnresolvableTools(
        manifest,
        allToolNames,
      );

      if (!mounted) return;

      // Save to controller's saved setups
      await widget.controller.saveSetup(setup);

      if (!mounted) return;

      Navigator.of(context).pop(true);

      if (missingTools.isNotEmpty) {
        _showMissingToolsWarning(missingTools, setup.name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded skill "${info.name}".'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load skill: $e';
          _loading = false;
        });
      }
    }
  }

  void _showMissingToolsWarning(List<String> missingTools, String skillName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Tools Not Available')),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Skill "$skillName" loaded, but ${missingTools.length} tool(s) are not available:',
              ),
              const SizedBox(height: 12),
              ...missingTools.map(
                (t) => ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.block,
                    size: 16,
                    color: Colors.red.shade400,
                  ),
                  title: Text(
                    t,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load Skill'),
      content: SizedBox(
        width: 420,
        height: 400,
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
                  'No saved skills found.\n\nUse "Save as Skill" to create one.',
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
                    subtitle: Text(
                      skill.description ?? 'No description',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
