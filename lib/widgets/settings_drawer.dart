import 'dart:convert';
import 'package:flutter/material.dart';
import '../models.dart';
import '../playground_controller.dart';
import '../mcp_client.dart';
import 'remote_mcp_dialog.dart';
import 'edit_mcp_dialog.dart';
import 'llm_config_form.dart';

class SettingsDrawer extends StatelessWidget {
  final PlaygroundController controller;

  const SettingsDrawer({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Drawer(child: SettingsPanel(controller: controller));
  }
}

class SettingsPanel extends StatefulWidget {
  final PlaygroundController controller;

  const SettingsPanel({super.key, required this.controller});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final _formKey = GlobalKey<FormState>();
  late LlmProvider _selectedProvider;
  final _modelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _tempCtrl = TextEditingController(text: '0.2');
  final _maxTokensCtrl = TextEditingController(text: '0');
  final _maxToolOutputSizeCtrl = TextEditingController(text: '2560000');
  final _tokenWarningThresholdCtrl = TextEditingController(text: '1500000');
  final _topKCtrl = TextEditingController();
  final _topPCtrl = TextEditingController();
  final _repeatPenaltyCtrl = TextEditingController();
  final _seedCtrl = TextEditingController();

  bool _isSlm = false;
  bool _isMultiModal = true;
  bool _thinking = false;
  bool _useNativeToolCall = true;
  bool _useSafeToolCall = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    _loadLlmValues();
  }

  @override
  void didUpdateWidget(SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      _loadLlmValues();
    }
  }

  void _onControllerChange() {
    if (mounted) {
      setState(() {
        _loadLlmValues();
      });
    }
  }

  void _loadLlmValues() {
    final config = widget.controller.llmConfig;
    _selectedProvider = config.provider;

    // Avoid resetting text cursor while user is typing in settings panel
    if (_modelCtrl.text != config.model) {
      _modelCtrl.text = config.model;
    }
    if (_apiKeyCtrl.text != config.apiKey) {
      _apiKeyCtrl.text = config.apiKey;
    }
    if (_baseUrlCtrl.text != config.baseUrl) {
      _baseUrlCtrl.text = config.baseUrl;
    }
    if (_tempCtrl.text != config.temperature.toString()) {
      _tempCtrl.text = config.temperature.toString();
    }
    if (_maxTokensCtrl.text != config.maxTokens.toString()) {
      _maxTokensCtrl.text = config.maxTokens.toString();
    }
    if (_maxToolOutputSizeCtrl.text != config.maxToolOutputSize.toString()) {
      _maxToolOutputSizeCtrl.text = config.maxToolOutputSize.toString();
    }
    if (_tokenWarningThresholdCtrl.text != config.tokenWarningThreshold.toString()) {
      _tokenWarningThresholdCtrl.text = config.tokenWarningThreshold.toString();
    }
    if (_topKCtrl.text != (config.topK?.toString() ?? '')) {
      _topKCtrl.text = config.topK?.toString() ?? '';
    }
    if (_topPCtrl.text != (config.topP?.toString() ?? '')) {
      _topPCtrl.text = config.topP?.toString() ?? '';
    }
    if (_repeatPenaltyCtrl.text != (config.repeatPenalty?.toString() ?? '')) {
      _repeatPenaltyCtrl.text = config.repeatPenalty?.toString() ?? '';
    }
    if (_seedCtrl.text != (config.seed?.toString() ?? '')) {
      _seedCtrl.text = config.seed?.toString() ?? '';
    }

    _isSlm = config.isSlm;
    _isMultiModal = config.isMultiModal;
    _thinking = config.thinking;
    _useNativeToolCall = config.useNativeToolCall;
    _useSafeToolCall = config.useSafeToolCall;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _tempCtrl.dispose();
    _maxTokensCtrl.dispose();
    _maxToolOutputSizeCtrl.dispose();
    _tokenWarningThresholdCtrl.dispose();
    _topKCtrl.dispose();
    _topPCtrl.dispose();
    _repeatPenaltyCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLlmSettings() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tempVal = double.tryParse(_tempCtrl.text.trim()) ?? 0.2;
    final maxTokensVal = int.tryParse(_maxTokensCtrl.text.trim()) ?? 0;
    final maxToolSizeVal = int.tryParse(_maxToolOutputSizeCtrl.text.trim()) ?? 2560000;
    final tokenWarningVal = int.tryParse(_tokenWarningThresholdCtrl.text.trim()) ?? 1500000;

    final updated = LlmConfig(
      provider: _selectedProvider,
      model: _modelCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      temperature: tempVal,
      maxTokens: maxTokensVal,
      maxToolOutputSize: maxToolSizeVal,
      tokenWarningThreshold: tokenWarningVal,
      topP: double.tryParse(_topPCtrl.text.trim()),
      topK: int.tryParse(_topKCtrl.text.trim()),
      repeatPenalty: double.tryParse(_repeatPenaltyCtrl.text.trim()),
      seed: int.tryParse(_seedCtrl.text.trim()),
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

  Future<void> _testMcpServerConnection(McpServerConfig server) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final tempClient = MCPClient(
        server.url,
        mcpEndpoint: server.mcpEndpoint,
        bearerToken: server.apiKey,
        apiPassword: server.apiPassword,
      );
      await tempClient.connect().timeout(const Duration(seconds: 10));
      final toolsCount = tempClient.availableTools.length;
      tempClient.dispose();

      if (!mounted) return;
      Navigator.pop(context); // close loading spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully connected to ${server.name}! ($toolsCount tools found)',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _discoverServerTools(McpServerConfig server) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final tempClient = MCPClient(
        server.url,
        mcpEndpoint: server.mcpEndpoint,
        bearerToken: server.apiKey,
        apiPassword: server.apiPassword,
      );
      await tempClient.connect().timeout(const Duration(seconds: 10));
      final tools = tempClient.availableTools;
      tempClient.dispose();

      if (!mounted) return;
      Navigator.pop(context); // close loader

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Tools from ${server.name}'),
          content: SizedBox(
            width: 480,
            height: 450,
            child: tools.isEmpty
                ? const Center(child: Text('No tools reported by this server.'))
                : ListView.builder(
                    itemCount: tools.length,
                    itemBuilder: (c, idx) {
                      final t = tools[idx];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ExpansionTile(
                          title: Text(
                            t.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            t.description ?? 'No description',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            if (t.description != null) ...[
                              Text(
                                t.description!,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                            ],
                            const Text(
                              'Schema:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(t.inputSchema ?? {}),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loader
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Failed to Fetch Tools'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Column(
                    spacing: 12,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Section 1: LLM Settings ---
                      Text(
                        'LLM / SLM PROVIDER',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      LlmConfigForm(
                        provider: _selectedProvider,
                        onProviderChanged: (val) {
                          setState(() {
                            _selectedProvider = val;
                          });
                        },
                        modelCtrl: _modelCtrl,
                        apiKeyCtrl: _apiKeyCtrl,
                        baseUrlCtrl: _baseUrlCtrl,
                      ),
                      if (_selectedProvider != LlmProvider.none) ...[
                        const SizedBox(height: 12),
                        ExpansionTile(
                          title: const Text(
                            'Advanced Hyperparameters & Flags',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          tilePadding: EdgeInsets.zero,
                          children: [
                            LlmAdvancedSettingsForm(
                              tempCtrl: _tempCtrl,
                              maxTokensCtrl: _maxTokensCtrl,
                              maxToolOutputSizeCtrl: _maxToolOutputSizeCtrl,
                              tokenWarningThresholdCtrl: _tokenWarningThresholdCtrl,
                              topKCtrl: _topKCtrl,
                              topPCtrl: _topPCtrl,
                              repeatPenaltyCtrl: _repeatPenaltyCtrl,
                              seedCtrl: _seedCtrl,
                              thinking: _thinking,
                              onThinkingChanged: (val) => setState(() => _thinking = val),
                              isSlm: _isSlm,
                              onIsSlmChanged: (val) => setState(() => _isSlm = val),
                              isMultiModal: _isMultiModal,
                              onIsMultiModalChanged: (val) => setState(() => _isMultiModal = val),
                              useNativeToolCall: _useNativeToolCall,
                              onUseNativeToolCallChanged: (val) => setState(() => _useNativeToolCall = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saveLlmSettings,
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: const Text('Save Settings'),
                          ),
                        ),
                      ],
                      const Divider(height: 24),

                      // --- Section 2: MCP Tool Servers ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'MCP SERVERS',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_link, size: 24),
                            tooltip: 'Add / Catalog MCP',
                            onPressed: () => RemoteMcpDialog.show(
                              context,
                              widget.controller,
                            ),
                          ),
                        ],
                      ),
                      if (widget.controller.servers.isEmpty)
                        Text(
                          'No HTTP MCP servers configured.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        )
                      else
                        ...widget.controller.servers.map((server) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                spacing: 4,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Switch(
                                        value: server.enabled,
                                        onChanged: (val) => widget.controller
                                            .toggleServer(server.id, val),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          server.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () => EditMcpServerDialog.show(
                                          context,
                                          server,
                                          widget.controller,
                                        ),
                                        tooltip: 'Edit Details',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 18,
                                        ),
                                        onPressed: () => widget.controller
                                            .removeServer(server.id),
                                        tooltip: 'Remove',
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${server.url}${server.mcpEndpoint}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    spacing: 8,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _testMcpServerConnection(server),
                                        icon: const Icon(
                                          Icons.wifi_tethering,
                                          size: 12,
                                        ),
                                        label: const Text(
                                          'Test',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _discoverServerTools(server),
                                        icon: const Icon(
                                          Icons.list_alt,
                                          size: 12,
                                        ),
                                        label: const Text(
                                          'Tools',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
