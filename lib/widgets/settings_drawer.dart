import 'package:flutter/material.dart';
import '../models.dart';
import '../playground_controller.dart';

class SettingsDrawer extends StatefulWidget {
  final PlaygroundController controller;

  const SettingsDrawer({super.key, required this.controller});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  late LlmProvider _selectedProvider;
  final _modelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  
  double _temperature = 0.2;
  int _maxTokens = 0;
  double? _topP;
  int? _topK;
  double? _repeatPenalty;
  int? _seed;
  bool _isSlm = false;
  bool _isMultiModal = true;
  bool _thinking = false;
  bool _useNativeToolCall = true;
  bool _useSafeToolCall = false;

  final _mcpNameCtrl = TextEditingController();
  final _mcpUrlCtrl = TextEditingController();
  final _mcpKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLlmValues();
  }

  void _loadLlmValues() {
    final config = widget.controller.llmConfig;
    _selectedProvider = config.provider;
    _modelCtrl.text = config.model;
    _apiKeyCtrl.text = config.apiKey;
    _baseUrlCtrl.text = config.baseUrl;
    _temperature = config.temperature;
    _maxTokens = config.maxTokens;
    _topP = config.topP;
    _topK = config.topK;
    _repeatPenalty = config.repeatPenalty;
    _seed = config.seed;
    _isSlm = config.isSlm;
    _isMultiModal = config.isMultiModal;
    _thinking = config.thinking;
    _useNativeToolCall = config.useNativeToolCall;
    _useSafeToolCall = config.useSafeToolCall;
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _mcpNameCtrl.dispose();
    _mcpUrlCtrl.dispose();
    _mcpKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLlmSettings() async {
    final updated = LlmConfig(
      provider: _selectedProvider,
      model: _modelCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      temperature: _temperature,
      maxTokens: _maxTokens,
      topP: _topP,
      topK: _topK,
      repeatPenalty: _repeatPenalty,
      seed: _seed,
      isSlm: _isSlm,
      isMultiModal: _isMultiModal,
      thinking: _thinking,
      useNativeToolCall: _useNativeToolCall,
      useSafeToolCall: _useSafeToolCall,
    );

    await widget.controller.updateLlmConfig(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LLM configuration saved successfully.')),
      );
    }
  }

  void _addMcpServer() {
    final name = _mcpNameCtrl.text.trim();
    final url = _mcpUrlCtrl.text.trim();
    final apiKey = _mcpKeyCtrl.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and URL are required.')),
      );
      return;
    }

    final newServer = McpServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );

    widget.controller.addServer(newServer);
    _mcpNameCtrl.clear();
    _mcpUrlCtrl.clear();
    _mcpKeyCtrl.clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final showApiKey = _selectedProvider != LlmProvider.none &&
        _selectedProvider != LlmProvider.ollama;
    final showBaseUrl = _selectedProvider == LlmProvider.ollama ||
        _selectedProvider == LlmProvider.openaiCompatible;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined),
                  const SizedBox(width: 8),
                  Text('Playground Settings', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // --- Section 1: LLM Settings ---
                  Text('LLM / SLM PROVIDER', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LlmProvider>(
                    initialValue: _selectedProvider,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: LlmProvider.values.map((provider) {
                      return DropdownMenuItem(
                        value: provider,
                        child: Text(provider.displayName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedProvider = val;
                          if (val == LlmProvider.gemini && _modelCtrl.text.isEmpty) {
                            _modelCtrl.text = 'gemini-2.5-flash';
                          } else if (val == LlmProvider.openai && _modelCtrl.text.isEmpty) {
                            _modelCtrl.text = 'gpt-4o-mini';
                          } else if (val == LlmProvider.claude && _modelCtrl.text.isEmpty) {
                            _modelCtrl.text = 'claude-3-5-sonnet-latest';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_selectedProvider != LlmProvider.none) ...[
                    TextFormField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Model Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (showApiKey)
                      TextFormField(
                        controller: _apiKeyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'API Key',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    if (showBaseUrl)
                      TextFormField(
                        controller: _baseUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base Endpoint URL',
                          hintText: 'e.g. http://localhost:11434/api',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: const Text('Advanced Model Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      tilePadding: EdgeInsets.zero,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Temperature: ${_temperature.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                          subtitle: Slider(
                            value: _temperature,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            onChanged: (val) => setState(() => _temperature = val),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Small Language Model (SLM)', style: TextStyle(fontSize: 12)),
                          subtitle: const Text('Enforce short and simple warmup instructions', style: TextStyle(fontSize: 10)),
                          value: _isSlm,
                          onChanged: (val) => setState(() => _isSlm = val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Multi-Modal Capabilities', style: TextStyle(fontSize: 12)),
                          value: _isMultiModal,
                          onChanged: (val) => setState(() => _isMultiModal = val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Allow Reasoning / Thinking', style: TextStyle(fontSize: 12)),
                          value: _thinking,
                          onChanged: (val) => setState(() => _thinking = val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Ollama Native Tool-Calls', style: TextStyle(fontSize: 12)),
                          value: _useNativeToolCall,
                          onChanged: (val) => setState(() => _useNativeToolCall = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _saveLlmSettings,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Save LLM Settings'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  
                  // --- Section 2: MCP Tool Servers ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MCP SERVERS', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                      IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: _showAddMcpDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.controller.servers.isEmpty)
                    Text(
                      'No HTTP MCP servers configured.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    )
                  else
                    ...widget.controller.servers.map((server) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(server.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        leading: Switch(
                          value: server.enabled,
                          onChanged: (val) => widget.controller.toggleServer(server.id, val),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => widget.controller.removeServer(server.id),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMcpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add HTTP MCP Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _mcpNameCtrl,
              decoration: const InputDecoration(labelText: 'Server Name', hintText: 'e.g. File Explorer'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mcpUrlCtrl,
              decoration: const InputDecoration(labelText: 'Connection URL', hintText: 'http://localhost:3000/mcp'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mcpKeyCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Auth Token (Optional)', hintText: 'Bearer token'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: _addMcpServer, child: const Text('Register')),
        ],
      ),
    );
  }
}
