import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../../models.dart';

class ToolGroup {
  final String name;
  final List<String> toolNames;
  const ToolGroup({required this.name, required this.toolNames});

  @override
  bool operator ==(Object other) =>
      other is ToolGroup &&
      other.name == name &&
      listEquals(other.toolNames, toolNames);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(toolNames));
}

class SubPromptEntry {
  final TextEditingController controller;
  List<String>? enabledToolNames;
  bool stopAfterToolCall;

  SubPromptEntry({
    String text = '',
    this.enabledToolNames,
    this.stopAfterToolCall = false,
  }) : controller = TextEditingController(text: text);

  factory SubPromptEntry.fromStep(SubPromptStep s) => SubPromptEntry(
        text: s.text,
        enabledToolNames: s.enabledToolNames != null
            ? List<String>.from(s.enabledToolNames!)
            : null,
        stopAfterToolCall: s.stopAfterToolCall,
      );

  SubPromptStep toStep() => SubPromptStep(
        text: controller.text,
        enabledToolNames: enabledToolNames != null
            ? List<String>.unmodifiable(enabledToolNames!)
            : null,
        stopAfterToolCall: stopAfterToolCall,
      );

  void dispose() => controller.dispose();
}

class SubPromptListEditor extends StatefulWidget {
  const SubPromptListEditor({
    super.key,
    required this.controller,
    this.chatMode = false,
    this.availableToolGroups = const [],
    this.minLines = 2,
    this.maxLines = 8,
    this.hintText,
    this.validator,
    this.onToolSelectionChanged,
    this.leading,
    this.trailing,
  });

  final TextEditingController controller;
  final bool chatMode;
  final List<ToolGroup> availableToolGroups;
  final int minLines;
  final int maxLines;
  final String? hintText;
  final String? Function(String?)? validator;
  final VoidCallback? onToolSelectionChanged;
  final Widget? leading;
  final Widget? trailing;

  @override
  State<SubPromptListEditor> createState() => _SubPromptListEditorState();
}

class _SubPromptListEditorState extends State<SubPromptListEditor> {
  late List<SubPromptEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _parse(widget.controller.text);
    widget.controller.addListener(_onExternalWrite);
    for (final e in _entries) {
      e.controller.addListener(_onEntryChanged);
    }
  }

  @override
  void didUpdateWidget(SubPromptListEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onExternalWrite);
      widget.controller.addListener(_onExternalWrite);
      _rebuildFromController();
    }
    if (!listEquals(old.availableToolGroups, widget.availableToolGroups)) {
      if (widget.controller.text != _serialize()) {
        _rebuildFromController();
      } else {
        _syncToolGroupsToNewList(widget.availableToolGroups);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalWrite);
    for (final e in _entries) {
      e.controller.removeListener(_onEntryChanged);
      e.dispose();
    }
    super.dispose();
  }

  List<SubPromptEntry> _parse(String text) =>
      parseSubPromptSteps(text).map(SubPromptEntry.fromStep).toList();

  String _serialize() =>
      serializeSubPromptSteps(_entries.map((e) => e.toStep()).toList());

  void _syncToolGroupsToNewList(List<ToolGroup> newGroups) {
    final newAllNames = {for (final g in newGroups) ...g.toolNames};
    bool changed = false;
    for (final entry in _entries) {
      if (entry.enabledToolNames == null) continue;
      final before = entry.enabledToolNames!.length;
      entry.enabledToolNames!.removeWhere((t) => !newAllNames.contains(t));
      if (entry.enabledToolNames!.length != before) changed = true;
    }
    if (changed) {
      setState(() {});
      _onEntryChanged();
    }
  }

  bool _suppressExternalWrite = false;

  void _onEntryChanged() {
    _suppressExternalWrite = true;
    widget.controller.text = _serialize();
    _suppressExternalWrite = false;
  }

  void _onExternalWrite() {
    if (_suppressExternalWrite) return;
    _rebuildFromController();
  }

  void _rebuildFromController() {
    final newText = widget.controller.text;
    if (newText == _serialize()) return;
    setState(() {
      for (final e in _entries) {
        e.controller.removeListener(_onEntryChanged);
        e.dispose();
      }
      _entries = _parse(newText);
      for (final e in _entries) {
        e.controller.addListener(_onEntryChanged);
      }
    });
  }

  void _addEntryAfter(int index) {
    setState(() {
      final e = SubPromptEntry(
        enabledToolNames: null,
        stopAfterToolCall: false,
      );
      e.controller.addListener(_onEntryChanged);
      _entries.insert(index + 1, e);
      _onEntryChanged();
    });
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() {
      _entries[index].controller.removeListener(_onEntryChanged);
      _entries[index].dispose();
      _entries.removeAt(index);
      _onEntryChanged();
    });
  }

  void _setEnabledTools(int index, List<String>? names) {
    setState(() {
      _entries[index].enabledToolNames = names;
      _onEntryChanged();
    });
    widget.onToolSelectionChanged?.call();
  }

  void _setStopAfterToolCall(int index, bool value) {
    setState(() {
      _entries[index].stopAfterToolCall = value;
      _onEntryChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _entries.length; i++) _buildRow(context, i)
      ],
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final entry = _entries[index];
    final theme = Theme.of(context);
    final hasTools = widget.availableToolGroups.isNotEmpty;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${index + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (index == 0 && widget.leading != null) widget.leading!,
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: entry.controller,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  decoration: InputDecoration(
                    hintText: index == 0
                        ? (widget.hintText ?? 'Message AI Playground...')
                        : 'Continue...  use \${tool_result} to inject prior step output',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!widget.chatMode && hasTools) ...[
                      _ToolsChecklistButton(
                        entry: entry,
                        stepIndex: index,
                        availableToolGroups: widget.availableToolGroups,
                        isMobile: isMobile,
                        onChanged: (names) => _setEnabledTools(index, names),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!widget.chatMode) ...[
                      _StopAfterToolCallBtn(
                        active: entry.stopAfterToolCall,
                        onToggle: () => _setStopAfterToolCall(index, !entry.stopAfterToolCall),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _IconBtn(
                      icon: Icons.add_circle_outline,
                      color: const Color(0xFF00ACC1),
                      tooltip: 'Add step after this one',
                      onPressed: () => _addEntryAfter(index),
                    ),
                    if (_entries.length > 1) ...[
                      const SizedBox(width: 8),
                      _IconBtn(
                        icon: Icons.remove_circle_outline,
                        color: theme.colorScheme.error,
                        tooltip: 'Remove this step',
                        onPressed: () => _removeEntry(index),
                      ),
                    ],
                    if (index == 0 && widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      widget.trailing!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (index > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Row(
                children: [
                  Expanded(child: Divider(color: theme.dividerColor, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Step ${index + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: theme.dividerColor, height: 1)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index == 0 && widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: entry.controller,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  decoration: InputDecoration(
                    hintText: index == 0
                        ? (widget.hintText ?? 'Message AI Playground...')
                        : 'Continue...  use \${tool_result} to inject prior step output',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.chatMode && hasTools)
                    _ToolsChecklistButton(
                      entry: entry,
                      stepIndex: index,
                      availableToolGroups: widget.availableToolGroups,
                      isMobile: isMobile,
                      onChanged: (names) => _setEnabledTools(index, names),
                    ),
                  if (!widget.chatMode)
                    _StopAfterToolCallBtn(
                      active: entry.stopAfterToolCall,
                      onToggle: () => _setStopAfterToolCall(index, !entry.stopAfterToolCall),
                    ),
                  _IconBtn(
                    icon: Icons.add_circle_outline,
                    color: const Color(0xFF00ACC1),
                    tooltip: 'Add step after this one',
                    onPressed: () => _addEntryAfter(index),
                  ),
                  if (_entries.length > 1)
                    _IconBtn(
                      icon: Icons.remove_circle_outline,
                      color: theme.colorScheme.error,
                      tooltip: 'Remove this step',
                      onPressed: () => _removeEntry(index),
                    ),
                ],
              ),
              if (index == 0 && widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      );
}

class _StopAfterToolCallBtn extends StatelessWidget {
  const _StopAfterToolCallBtn({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active
          ? 'Stop after tool call: ON\nResult not sent to LLM — next step starts immediately'
          : 'Stop after tool call: OFF for this step\nTap to stop LLM loop after first tool call',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            active ? Icons.flag : Icons.flag_outlined,
            size: 18,
            color: active ? Colors.orange : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _ToolsChecklistButton extends StatelessWidget {
  const _ToolsChecklistButton({
    required this.entry,
    required this.stepIndex,
    required this.availableToolGroups,
    required this.isMobile,
    required this.onChanged,
  });

  final SubPromptEntry entry;
  final int stepIndex;
  final List<ToolGroup> availableToolGroups;
  final bool isMobile;
  final ValueChanged<List<String>?> onChanged;

  Set<String> _enabledToolNamesSet() {
    if (entry.enabledToolNames == null) {
      return {for (final g in availableToolGroups) ...g.toolNames};
    }
    return entry.enabledToolNames!.toSet();
  }

  int get _totalToolCount =>
      availableToolGroups.fold(0, (s, g) => s + g.toolNames.length);

  (IconData, Color) _iconState(ThemeData theme) {
    if (entry.enabledToolNames == null) {
      return (Icons.build_rounded, theme.colorScheme.primary);
    }
    if (entry.enabledToolNames!.isEmpty) return (Icons.block_outlined, Colors.grey);
    if (entry.enabledToolNames!.length == _totalToolCount) {
      return (Icons.build_rounded, theme.colorScheme.primary);
    }
    return (Icons.rule, Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _iconState(theme);
    final enabledCount = entry.enabledToolNames?.length ?? _totalToolCount;
    final tooltip = 'Tools: $enabledCount/$_totalToolCount';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showSelectionDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Future<void> _showSelectionDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final isMobileView = MediaQuery.of(context).size.width < 600;
    var current = _enabledToolNamesSet();
    final allToolNames = {for (final g in availableToolGroups) ...g.toolNames};

    Widget buildContent(BuildContext ctx, StateSetter setDialogState) {
      final allSelectedGlobally = current.length == allToolNames.length;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: availableToolGroups.length,
              itemBuilder: (context, groupIdx) {
                final group = availableToolGroups[groupIdx];
                final groupSet = group.toolNames.toSet();
                final allSelectedInGroup = groupSet.every(current.contains);
                final sortedTools = List<String>.from(group.toolNames)
                  ..sort((a, b) => a.compareTo(b));

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.outline,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setDialogState(() {
                              if (allSelectedInGroup) {
                                current = current.difference(groupSet);
                              } else {
                                current = current.union(groupSet);
                              }
                            }),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 28),
                            ),
                            child: Text(allSelectedInGroup ? 'None' : 'All'),
                          ),
                        ],
                      ),
                    ),
                    if (group.toolNames.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        child: Text(
                          '(no tools found)',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ...sortedTools.map((toolName) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          title: Text(toolName, style: const TextStyle(fontSize: 13)),
                          value: current.contains(toolName),
                          activeColor: theme.colorScheme.primary,
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              current = {...current, toolName};
                            } else {
                              current = current.difference({toolName});
                            }
                          }),
                        );
                      }),
                    const Divider(),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setDialogState(() => current = Set.from(allToolNames)),
                  child: Text(allSelectedGlobally ? 'All selected' : 'Select all'),
                ),
                TextButton(
                  onPressed: () => setDialogState(() => current = {}),
                  child: const Text('None'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _commit(current);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isMobileView) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text('Tools - Step ${stepIndex + 1}'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: StatefulBuilder(
              builder: (ctx2, setState) => buildContent(ctx, setState),
            ),
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Tools - Step ${stepIndex + 1}'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SizedBox(
            width: 380,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500),
              child: StatefulBuilder(
                builder: (ctx2, setState) => buildContent(ctx, setState),
              ),
            ),
          ),
        ),
      );
    }
  }

  void _commit(Set<String> selectedToolNames) {
    final allCount = _totalToolCount;
    if (selectedToolNames.length == allCount) {
      onChanged(null);
    } else if (selectedToolNames.isEmpty) {
      onChanged([]);
    } else {
      onChanged(selectedToolNames.toList());
    }
  }
}
