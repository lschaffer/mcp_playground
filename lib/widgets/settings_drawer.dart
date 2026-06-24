import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../playground_controller.dart';
import '../llm_service.dart';
import '../mcp_client.dart';
import 'remote_mcp_dialog.dart';

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

  bool _testingLlm = false;
  bool _fetchingModels = false;
  List<String> _fetchedModels = [];

  final Map<LlmProvider, List<String>> _defaultModels = const {
    LlmProvider.openai: ['gpt-4o', 'gpt-4o-mini', 'o1-mini', 'o3-mini'],
    LlmProvider.claude: [
      'claude-3-5-sonnet-latest',
      'claude-3-5-haiku-latest',
      'claude-3-opus-latest',
    ],
    LlmProvider.gemini: [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash-thinking-exp',
    ],
    LlmProvider.mistral: [
      'mistral-large-latest',
      'pixtral-large-latest',
      'codestral-latest',
      'open-mixtral-8x22b',
    ],
    LlmProvider.ollama: [],
    LlmProvider.openaiCompatible: [],
  };

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
    widget.controller.removeListener(_onControllerChange);
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLlmSettings() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tempVal = double.tryParse(_tempCtrl.text.trim()) ?? 0.2;
    final updated = LlmConfig(
      provider: _selectedProvider,
      model: _modelCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      temperature: tempVal,
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

  Future<void> _testLlmConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _testingLlm = true);

    try {
      final tempVal = double.tryParse(_tempCtrl.text.trim()) ?? 0.2;
      final testConfig = LlmConfig(
        provider: _selectedProvider,
        model: _modelCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        baseUrl: _baseUrlCtrl.text.trim(),
        temperature: tempVal,
        maxTokens: 10,
      );

      final response = await LLMService.generate(
        config: testConfig,
        messages: [
          ChatMessage(
            id: 'test-conn',
            role: ChatRole.user,
            content: 'Respond with the single word "OK" if you can hear me.',
            timestamp: DateTime.now(),
          ),
        ],
        tools: [],
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Connection Successful'),
            ],
          ),
          content: Text(
            'Provider responded! Model reply:\n\n"${response.text.trim()}"',
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Connection Failed'),
            ],
          ),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testingLlm = false);
      }
    }
  }

  Future<void> _fetchAvailableModels() async {
    setState(() => _fetchingModels = true);
    try {
      final provider = _selectedProvider;
      final baseUrl = _baseUrlCtrl.text.trim();
      final apiKey = _apiKeyCtrl.text.trim();
      final List<String> list = [];

      if (provider == LlmProvider.ollama) {
        final base = (baseUrl.isEmpty ? 'http://localhost:11434' : baseUrl)
            .replaceAll(RegExp(r'/+$'), '');
        final tagsBase = base.endsWith('/api') ? base : '$base/api';
        final url = Uri.parse('$tagsBase/tags');
        final headers = apiKey.isNotEmpty
            ? {'Authorization': 'Bearer $apiKey'}
            : <String, String>{};
        final resp = await http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final fetched = (data['models'] as List<dynamic>? ?? [])
              .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          list.addAll(fetched);
        }
      } else {
        var resolvedBaseUrl = baseUrl;
        if (resolvedBaseUrl.isEmpty) {
          if (provider == LlmProvider.openai) {
            resolvedBaseUrl = 'https://api.openai.com/v1';
          } else if (provider == LlmProvider.mistral) {
            resolvedBaseUrl = 'https://api.mistral.ai/v1';
          }
        }
        if (resolvedBaseUrl.isNotEmpty) {
          final base = resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '');
          final url = Uri.parse('$base/models');
          final headers = {
            'Accept': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          };
          final resp = await http
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final fetched = (data['data'] as List<dynamic>? ?? [])
                .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
                .where((n) => n.isNotEmpty)
                .toList();
            list.addAll(fetched);
          }
        }
      }

      if (mounted) {
        setState(() {
          _fetchedModels = list;
          if (list.isNotEmpty && _modelCtrl.text.trim().isEmpty) {
            _modelCtrl.text = list.first;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _fetchingModels = false);
      }
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
    final showBaseUrl =
        _selectedProvider == LlmProvider.ollama ||
        _selectedProvider == LlmProvider.openaiCompatible ||
        _selectedProvider == LlmProvider.mistral;

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
                      DropdownButtonFormField<LlmProvider>(
                        key: ValueKey(_selectedProvider),
                        initialValue: _selectedProvider,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
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
                              _fetchedModels = [];
                              if (val == LlmProvider.gemini &&
                                  _modelCtrl.text.isEmpty) {
                                _modelCtrl.text = 'gemini-2.5-flash';
                              } else if (val == LlmProvider.openai &&
                                  _modelCtrl.text.isEmpty) {
                                _modelCtrl.text = 'gpt-4o-mini';
                              } else if (val == LlmProvider.claude &&
                                  _modelCtrl.text.isEmpty) {
                                _modelCtrl.text = 'claude-3-5-sonnet-latest';
                              } else if (val == LlmProvider.mistral &&
                                  _modelCtrl.text.isEmpty) {
                                _modelCtrl.text = 'mistral-large-latest';
                              }
                            });
                          }
                        },
                      ),
                      if (_selectedProvider != LlmProvider.none) ...[
                        // Autocomplete for Model name
                        Text(
                          'Model Name',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Autocomplete<String>(
                          initialValue: _modelCtrl.value,
                          optionsBuilder: (textEditingValue) {
                            final defaultOpts =
                                _defaultModels[_selectedProvider] ?? [];
                            final models = _fetchedModels.isNotEmpty
                                ? _fetchedModels
                                : defaultOpts;
                            if (textEditingValue.text.isEmpty) {
                              return models;
                            }
                            return models.where(
                              (m) => m.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                            );
                          },
                          fieldViewBuilder:
                              (ctx, controller, focusNode, onSubmitted) {
                                if (controller.text != _modelCtrl.text) {
                                  controller.text = _modelCtrl.text;
                                }
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  onChanged: (value) {
                                    _modelCtrl.text = value;
                                  },
                                  decoration: const InputDecoration(
                                    hintText: 'Enter or select model name',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Model name is required'
                                      : null,
                                );
                              },
                          onSelected: (v) {
                            _modelCtrl.text = v;
                          },
                        ),

                        // API Key (Always Visible)
                        Text(
                          'API Key / Token (Always Visible)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextFormField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),

                        // Base Endpoint Url (Visible for Ollama / Custom API / Mistral)
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

                        // Refresh / Fetch model list button (if provider supports it)
                        if (_selectedProvider == LlmProvider.ollama ||
                            _selectedProvider == LlmProvider.openai ||
                            _selectedProvider == LlmProvider.mistral ||
                            _selectedProvider == LlmProvider.openaiCompatible)
                          OutlinedButton.icon(
                            onPressed: _fetchingModels
                                ? null
                                : _fetchAvailableModels,
                            icon: _fetchingModels
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync, size: 16),
                            label: Text(
                              _fetchedModels.isEmpty
                                  ? 'Fetch Available Models'
                                  : 'Refresh Models (${_fetchedModels.length})',
                            ),
                          ),

                        ExpansionTile(
                          title: const Text(
                            'Advanced Model Settings',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          tilePadding: EdgeInsets.zero,
                          children: [
                            Column(
                              spacing: 8,
                              children: [
                                TextFormField(
                                  controller: _tempCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Temperature',
                                    hintText: '0.0 - 2.0 (e.g. 0.2)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return null;
                                    }
                                    final d = double.tryParse(v.trim());
                                    if (d == null) {
                                      return 'Must be a valid decimal number';
                                    }
                                    if (d < 0.0 || d > 2.0) {
                                      return 'Must be between 0.0 and 2.0';
                                    }
                                    return null;
                                  },
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Small Language Model (SLM)',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  subtitle: const Text(
                                    'Enforce short and simple warmup instructions',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  value: _isSlm,
                                  onChanged: (val) =>
                                      setState(() => _isSlm = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Multi-Modal Capabilities',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _isMultiModal,
                                  onChanged: (val) =>
                                      setState(() => _isMultiModal = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Allow Reasoning / Thinking',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _thinking,
                                  onChanged: (val) =>
                                      setState(() => _thinking = val),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Use Native Tool Calls',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _useNativeToolCall,
                                  onChanged: (val) =>
                                      setState(() => _useNativeToolCall = val),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          spacing: 8,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _testingLlm
                                    ? null
                                    : _testLlmConnection,
                                icon: _testingLlm
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.wifi_tethering,
                                        size: 16,
                                      ),
                                label: const Text('Test Connection'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _saveLlmSettings,
                                icon: const Icon(Icons.save_outlined, size: 16),
                                label: const Text('Save Settings'),
                              ),
                            ),
                          ],
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
