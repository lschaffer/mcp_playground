import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:dartssh2/dartssh2.dart';
import 'models.dart';
import 'local_tools.dart';
import 'playground_controller.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/settings_drawer.dart';
import 'widgets/registered_tools_dialog.dart';
import 'widgets/agent_inspector.dart';
import 'widgets/llm_config_form.dart';

class McpPlayground extends StatefulWidget {
  /// Default LLM setup parameters.
  final LlmConfig? initialLlmConfig;

  /// Default list of HTTP/HTTPS MCP servers to connect to.
  final List<McpServerConfig>? initialServers;

  /// Optional delegate to customize settings save/load operations.
  /// Falls back to SharedPreferences if null.
  final McpPlaygroundStorageDelegate? storageDelegate;

  /// Custom list of internal, Dart-native tools to register.
  final List<McpLocalTool>? customLocalTools;

  const McpPlayground({
    super.key,
    this.initialLlmConfig,
    this.initialServers,
    this.storageDelegate,
    this.customLocalTools,
  });

  @override
  State<McpPlayground> createState() => _McpPlaygroundState();
}

class _McpPlaygroundState extends State<McpPlayground> {
  late final PlaygroundController _controller;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<MessageAttachment> _attachments = [];

  // Two-Site Layout State
  bool _playgroundStarted = false;
  String? _loadedSetupId;
  double _chatFraction = 0.7;

  // Setup form states
  final _systemPromptCtrl = TextEditingController();
  final _initialPromptCtrl = TextEditingController();
  bool _chatMode = false;
  bool _stopAfterToolCall = false;

  // Custom LLM Override state
  bool _useCustomLlm = false;
  LlmProvider _customProvider = LlmProvider.none;
  final _customModelCtrl = TextEditingController();
  final _customApiKeyCtrl = TextEditingController();
  final _customBaseUrlCtrl = TextEditingController();
  final _customTempCtrl = TextEditingController(text: '0.2');
  final _customMaxTokensCtrl = TextEditingController(text: '0');
  final _customMaxToolOutputSizeCtrl = TextEditingController(text: '2560000');
  final _customTokenWarningThresholdCtrl = TextEditingController(text: '1500000');
  final _customTopKCtrl = TextEditingController();
  final _customTopPCtrl = TextEditingController();
  final _customRepeatPenaltyCtrl = TextEditingController();
  final _customSeedCtrl = TextEditingController();
  bool _customThinking = false;
  bool _customIsSlm = false;
  bool _customIsMultiModal = true;
  bool _customUseNativeTool = true;

  // SSH Override text controllers
  final _sshHostCtrl = TextEditingController();
  final _sshPortCtrl = TextEditingController(text: '22');
  final _sshUsernameCtrl = TextEditingController();
  final _sshPasswordCtrl = TextEditingController();
  String _sshPrivateKeyPem = '';
  String _sshPrivateKeyFileName = '';

  @override
  void initState() {
    super.initState();
    _controller = PlaygroundController(
      initialLlmConfig: widget.initialLlmConfig,
      initialServers: widget.initialServers,
      customLocalTools: widget.customLocalTools,
      storageDelegate: widget.storageDelegate,
    );
    _controller.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {});
      if (_controller.messages.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _updateSshParamsInController() {
    _controller.updateMcpInitParams({
      'ssh': {
        'host': _sshHostCtrl.text,
        'port': int.tryParse(_sshPortCtrl.text) ?? 22,
        'username': _sshUsernameCtrl.text,
        'password': _sshPasswordCtrl.text,
        'privateKey': _sshPrivateKeyPem,
        '_privateKeyFileName': _sshPrivateKeyFileName,
      }
    });
  }

  Future<void> _testSshOverrideConnection() async {
    final host = _sshHostCtrl.text.trim();
    final port = int.tryParse(_sshPortCtrl.text.trim()) ?? 22;
    final username = _sshUsernameCtrl.text.trim();
    final password = _sshPasswordCtrl.text;
    final privateKey = _sshPrivateKeyPem.trim();

    if (host.isEmpty || username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SSH test failed: host and username are required.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Testing SSH connection...')));

    SSHClient? client;
    try {
      client = SSHClient(
        await SSHSocket.connect(
          host,
          port,
        ).timeout(const Duration(seconds: 12)),
        username: username,
        identities: privateKey.isNotEmpty
            ? SSHKeyPair.fromPem(privateKey)
            : null,
        onPasswordRequest: () => password,
      );
      await client.authenticated.timeout(const Duration(seconds: 12));
      final session = await client
          .execute('echo mcp_ssh_test_ok')
          .timeout(const Duration(seconds: 12));
      await session.stdout.drain<void>();
      await session.stderr.drain<void>();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SSH connection successful.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SSH connection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      client?.close();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _systemPromptCtrl.dispose();
    _initialPromptCtrl.dispose();
    _customModelCtrl.dispose();
    _customApiKeyCtrl.dispose();
    _customBaseUrlCtrl.dispose();
    _customTempCtrl.dispose();
    _customMaxTokensCtrl.dispose();
    _customMaxToolOutputSizeCtrl.dispose();
    _customTokenWarningThresholdCtrl.dispose();
    _customTopKCtrl.dispose();
    _customTopPCtrl.dispose();
    _customRepeatPenaltyCtrl.dispose();
    _customSeedCtrl.dispose();
    _sshHostCtrl.dispose();
    _sshPortCtrl.dispose();
    _sshUsernameCtrl.dispose();
    _sshPasswordCtrl.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    final listToSend = List<MessageAttachment>.from(_attachments);
    _inputCtrl.clear();
    setState(() {
      _attachments.clear();
    });

    _controller.sendMessage(text, attachments: listToSend);
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.bytes != null) {
              final name = file.name;
              final mime = lookupMimeType(name) ?? 'application/octet-stream';
              _attachments.add(
                MessageAttachment(
                  id: const Uuid().v4(),
                  name: name,
                  path: file.path ?? '',
                  bytes: file.bytes,
                  mimeType: mime,
                  size: file.size,
                ),
              );
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  // Grouped Toolsets Helper
  List<_ToolsetGroup> _getToolsetGroups() {
    final groups = <_ToolsetGroup>[
      _ToolsetGroup(
        name: 'Weather',
        description: 'Fetch weather forecasts using Open-Meteo (free, no API key). Provides current conditions, hourly and daily forecasts.',
        tools: _controller.localTools.where((t) => t.name == 'get_current_weather' || t.name == 'get_hourly_forecast' || t.name == 'get_daily_forecast' || t.name == 'geocode_weather_city').map((t) => t.toMCPTool()).toList(),
      ),
      _ToolsetGroup(
        name: 'SSH / SFTP',
        description: 'Connect to a remote Linux/Unix server via SSH. Browse directories, read/upload/download files, execute commands.',
        tools: _controller.localTools.where((t) => t.name == 'list_directory' || t.name == 'read_file' || t.name == 'download_file' || t.name == 'upload_file' || t.name == 'execute_command' || t.name == 'make_directory' || t.name == 'remove_directory').map((t) => t.toMCPTool()).toList(),
      ),
      _ToolsetGroup(
        name: 'Chart generator',
        description: 'Generate PNG charts: line, bar, area, pie, scatter.',
        tools: _controller.localTools.where((t) => t.name == 'create_chart_png').map((t) => t.toMCPTool()).toList(),
      ),
    ];
    for (final client in _controller.mcpClients) {
      if (client.isConnected) {
        final isExt = client.url.startsWith('http');
        groups.add(_ToolsetGroup(
          name: client.label,
          description: client.url,
          tools: client.availableTools,
          isExternal: isExt,
          isInstalled: !isExt,
        ));
      }
    }
    return groups;
  }

  bool _isToolsetEnabled(_ToolsetGroup group) {
    final disabled = _controller.disabledToolNames;
    return group.tools.any((t) => !disabled.contains(t.name));
  }

  void _showToolChecklistDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final groups = _getToolsetGroups();

            final builtin = groups.where((g) => !g.isExternal && !g.isInstalled).toList();
            final external = groups.where((g) => g.isExternal).toList();
            final installed = groups.where((g) => g.isInstalled).toList();

            Widget buildHeader(String title, IconData icon, Color color) {
              return Padding(
                padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 20.0, right: 20.0),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildGroupTile(_ToolsetGroup group) {
              final isEnabled = _isToolsetEnabled(group);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group.description,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Checkbox(
                      value: isEnabled,
                      activeColor: const Color(0xFF00ACC1),
                      onChanged: (val) {
                        final targetVal = val ?? false;
                        for (final t in group.tools) {
                          _controller.toggleToolEnabled(t.name, targetVal);
                        }
                        setDialogState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: const Text(
                'Select Tools',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: SizedBox(
                width: 480,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...builtin.map(buildGroupTile),
                    if (external.isNotEmpty) ...[
                      buildHeader('External MCP Servers', Icons.dns, Colors.orange),
                      ...external.map(buildGroupTile),
                    ],
                    if (installed.isNotEmpty) ...[
                      buildHeader('Installed MCP Servers', Icons.hub, Colors.teal),
                      ...installed.map(buildGroupTile),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00ACC1),
                  ),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChatToolsChecklistDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final groups = _getToolsetGroups().where((g) => _isToolsetEnabled(g)).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: const Text(
                'Select Active Tools',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: SizedBox(
                width: 480,
                child: groups.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No toolsets selected or active. Change toolsets on the setup screen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: groups.length,
                        itemBuilder: (context, gIdx) {
                          final group = groups[gIdx];
                          final disabled = _controller.disabledToolNames;
                          final groupTools = group.tools;
                          
                          // Check if all tools in group are enabled
                          final allEnabled = groupTools.every((t) => !disabled.contains(t.name));
                          final noneEnabled = groupTools.every((t) => disabled.contains(t.name));
                          
                          bool? triStateVal;
                          if (allEnabled) {
                            triStateVal = true;
                          } else if (noneEnabled) {
                            triStateVal = false;
                          } else {
                            triStateVal = null; // Indeterminate
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Group header with select all/none checkbox
                              Container(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: triStateVal,
                                      tristate: true,
                                      activeColor: const Color(0xFF00ACC1),
                                      onChanged: (val) {
                                        final targetVal = val ?? false;
                                        setDialogState(() {
                                          for (final t in groupTools) {
                                            _controller.toggleToolEnabled(t.name, targetVal);
                                          }
                                        });
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      group.name,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              // Tools in this group
                              ...groupTools.map((t) {
                                final isEnabled = !disabled.contains(t.name);
                                return CheckboxListTile(
                                  value: isEnabled,
                                  activeColor: const Color(0xFF00ACC1),
                                  title: Text(
                                    t.name,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    t.description ?? 'No description.',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onChanged: (val) {
                                    setDialogState(() {
                                      _controller.toggleToolEnabled(t.name, val == true);
                                    });
                                    setState(() {});
                                  },
                                );
                              }),
                            ],
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showIndividualToolsDialog(_ToolsetGroup group) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final disabled = _controller.disabledToolNames;
            return AlertDialog(
              title: Text('Select tools from ${group.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: SizedBox(
                width: 400,
                child: ListView(
                  shrinkWrap: true,
                  children: group.tools.map((t) {
                    final isEnabled = !disabled.contains(t.name);
                    return CheckboxListTile(
                      value: isEnabled,
                      title: Text(t.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
                      subtitle: Text(t.description ?? 'No description available.', style: const TextStyle(fontSize: 11)),
                      onChanged: (val) {
                        _controller.toggleToolEnabled(t.name, val == true);
                        setDialogState(() {});
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleExampleAction(String action) {
    // Reset/clear current conversation and switch view back to the initial setup screen
    _resetPlayground();

    // Clear all other text inputs
    _inputCtrl.clear();
    _systemPromptCtrl.clear();
    _sshHostCtrl.clear();
    _sshUsernameCtrl.clear();
    _sshPasswordCtrl.clear();
    _sshPrivateKeyPem = '';
    _sshPrivateKeyFileName = '';

    // Disable all tools first
    final allTools = _getToolsetGroups().expand((g) => g.tools).map((t) => t.name).toList();
    for (final tool in allTools) {
      _controller.toggleToolEnabled(tool, false);
    }

    String textToInsert = '';
    List<String> toolsToEnable = [];

    if (action == 'weather') {
      textToInsert = 'Check the weather in Paris, London, and Tokyo, and compile a report.';
      toolsToEnable = ['get_current_weather', 'get_hourly_forecast', 'get_daily_forecast', 'geocode_weather_city'];
    } else if (action == 'ssh') {
      textToInsert = 'list top 20 biggest files in /var/lib';
      toolsToEnable = ['list_directory', 'read_file', 'download_file', 'upload_file', 'execute_command', 'make_directory', 'remove_directory'];
    } else if (action == 'chart') {
      textToInsert = 'Generate a bar chart with the following data: Python: 45, JavaScript: 35, Dart: 25, Go: 15.';
      toolsToEnable = ['create_chart_png'];
    }

    // Enable target tools
    for (final tool in toolsToEnable) {
      _controller.toggleToolEnabled(tool, true);
    }

    // Populate initial prompt
    _initialPromptCtrl.text = textToInsert;

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded "$action" template. Tools selected & setup cleared.')),
    );
  }

  // Reset function
  void _resetPlayground() {
    setState(() {
      _playgroundStarted = false;
      _loadedSetupId = null;
      _controller.clearChat();
      _attachments.clear();
    });
  }

  // Save current setup dialog
  void _showSaveSetupDialog() {
    SavedPlaygroundSetup? loadedSetup;
    if (_loadedSetupId != null) {
      for (final s in _controller.savedSetups) {
        if (s.id == _loadedSetupId) {
          loadedSetup = s;
          break;
        }
      }
    }
    final nameCtrl = TextEditingController(text: loadedSetup?.name ?? 'My Playground Setup');
    bool saveAsNew = _loadedSetupId == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          return AlertDialog(
            title: const Text('Save Setup Configuration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Configuration Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_loadedSetupId != null) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Save as a new configuration'),
                    value: saveAsNew,
                    onChanged: (val) {
                      setDialogState(() {
                        saveAsNew = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  final id = saveAsNew ? const Uuid().v4() : _loadedSetupId!;
                  final disabled = _controller.disabledToolNames;
                  final allTools = _getToolsetGroups().expand((g) => g.tools).map((t) => t.name).toList();
                  final enabledTools = allTools.where((t) => !disabled.contains(t)).toList();

                  final setup = SavedPlaygroundSetup(
                    id: id,
                    name: name,
                    createdAt: DateTime.now(),
                    systemPrompt: _systemPromptCtrl.text,
                    initialPrompt: _initialPromptCtrl.text,
                    enabledToolNames: enabledTools,
                    chatMode: _chatMode,
                    stopAfterToolCall: _stopAfterToolCall,
                    useCustomLlm: _useCustomLlm,
                    customLlmConfig: _useCustomLlm
                        ? LlmConfig(
                            provider: _customProvider,
                            model: _customModelCtrl.text,
                            apiKey: _customApiKeyCtrl.text,
                            baseUrl: _customBaseUrlCtrl.text,
                            temperature: double.tryParse(_customTempCtrl.text) ?? 0.2,
                            maxTokens: int.tryParse(_customMaxTokensCtrl.text) ?? 0,
                            maxToolOutputSize: int.tryParse(_customMaxToolOutputSizeCtrl.text) ?? 2560000,
                            tokenWarningThreshold: int.tryParse(_customTokenWarningThresholdCtrl.text) ?? 1500000,
                            topP: double.tryParse(_customTopPCtrl.text),
                            topK: int.tryParse(_customTopKCtrl.text),
                            repeatPenalty: double.tryParse(_customRepeatPenaltyCtrl.text),
                            seed: int.tryParse(_customSeedCtrl.text),
                            thinking: _customThinking,
                            isSlm: _customIsSlm,
                            isMultiModal: _customIsMultiModal,
                            useNativeToolCall: _customUseNativeTool,
                          )
                        : null,
                    mcpInitParams: {
                      'ssh': {
                        'host': _sshHostCtrl.text,
                        'port': int.tryParse(_sshPortCtrl.text) ?? 22,
                        'username': _sshUsernameCtrl.text,
                        'password': _sshPasswordCtrl.text,
                        'privateKey': _sshPrivateKeyPem,
                        '_privateKeyFileName': _sshPrivateKeyFileName,
                      }
                    },
                  );

                  _controller.saveSetup(setup);
                  setState(() {
                    _loadedSetupId = id;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Setup "$name" saved successfully.')),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Load setups dialog
  void _showLoadSetupsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load Setup Configuration'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: _controller.savedSetups.isEmpty
              ? const Center(child: Text('No saved configurations found.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _controller.savedSetups.length,
                  itemBuilder: (c, idx) {
                    final setup = _controller.savedSetups[idx];
                    return ListTile(
                      title: Text(setup.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Created: ${setup.createdAt.toString().split('.').first}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () {
                          _controller.deleteSetup(setup.id);
                          Navigator.pop(ctx);
                          _showLoadSetupsDialog();
                        },
                      ),
                      onTap: () {
                        // Load setup configuration
                        setState(() {
                          _loadedSetupId = setup.id;
                          _systemPromptCtrl.text = setup.systemPrompt;
                          _initialPromptCtrl.text = setup.initialPrompt;
                          _chatMode = setup.chatMode;
                          _stopAfterToolCall = setup.stopAfterToolCall;
                          _useCustomLlm = setup.useCustomLlm;

                          if (setup.customLlmConfig != null) {
                            final custom = setup.customLlmConfig!;
                            _customProvider = custom.provider;
                            _customModelCtrl.text = custom.model;
                            _customApiKeyCtrl.text = custom.apiKey;
                            _customBaseUrlCtrl.text = custom.baseUrl;
                            _customTempCtrl.text = custom.temperature.toString();
                            _customMaxTokensCtrl.text = custom.maxTokens.toString();
                            _customMaxToolOutputSizeCtrl.text = custom.maxToolOutputSize.toString();
                            _customTokenWarningThresholdCtrl.text = custom.tokenWarningThreshold.toString();
                            _customTopKCtrl.text = custom.topK?.toString() ?? '';
                            _customTopPCtrl.text = custom.topP?.toString() ?? '';
                            _customRepeatPenaltyCtrl.text = custom.repeatPenalty?.toString() ?? '';
                            _customSeedCtrl.text = custom.seed?.toString() ?? '';
                            _customThinking = custom.thinking;
                            _customIsSlm = custom.isSlm;
                            _customIsMultiModal = custom.isMultiModal;
                            _customUseNativeTool = custom.useNativeToolCall;
                          }

                          if (setup.mcpInitParams != null && setup.mcpInitParams!['ssh'] != null) {
                            final ssh = setup.mcpInitParams!['ssh'] as Map<String, dynamic>;
                            _sshHostCtrl.text = ssh['host'] as String? ?? '';
                            _sshPortCtrl.text = (ssh['port'] ?? 22).toString();
                            _sshUsernameCtrl.text = ssh['username'] as String? ?? '';
                            _sshPasswordCtrl.text = ssh['password'] as String? ?? '';
                            _sshPrivateKeyPem = ssh['privateKey'] as String? ?? '';
                            _sshPrivateKeyFileName = ssh['_privateKeyFileName'] as String? ?? '';
                            _updateSshParamsInController();
                          } else {
                            _sshHostCtrl.clear();
                            _sshPortCtrl.text = '22';
                            _sshUsernameCtrl.clear();
                            _sshPasswordCtrl.clear();
                            _sshPrivateKeyPem = '';
                            _sshPrivateKeyFileName = '';
                            _controller.updateMcpInitParams({});
                          }

                          // Load tool selections
                          final allTools = _getToolsetGroups().expand((g) => g.tools).map((t) => t.name).toList();
                          for (final t in allTools) {
                            final enable = setup.enabledToolNames.contains(t);
                            _controller.toggleToolEnabled(t, enable);
                          }
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Loaded setup "${setup.name}".')),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _applyLlmDefaults() {
    final defaults = _controller.llmConfig;
    setState(() {
      _customProvider = defaults.provider;
      _customModelCtrl.text = defaults.model;
      _customApiKeyCtrl.text = defaults.apiKey;
      _customBaseUrlCtrl.text = defaults.baseUrl;
      _customTempCtrl.text = defaults.temperature.toString();
      _customMaxTokensCtrl.text = defaults.maxTokens.toString();
      _customMaxToolOutputSizeCtrl.text = defaults.maxToolOutputSize.toString();
      _customTokenWarningThresholdCtrl.text = defaults.tokenWarningThreshold.toString();
      _customTopKCtrl.text = defaults.topK?.toString() ?? '';
      _customTopPCtrl.text = defaults.topP?.toString() ?? '';
      _customRepeatPenaltyCtrl.text = defaults.repeatPenalty?.toString() ?? '';
      _customSeedCtrl.text = defaults.seed?.toString() ?? '';
      _customThinking = defaults.thinking;
      _customIsSlm = defaults.isSlm;
      _customIsMultiModal = defaults.isMultiModal;
      _customUseNativeTool = defaults.useNativeToolCall;
    });
  }

  void _startPlayground() {
    // 1. Configure controller properties
    _controller.systemPrompt = _systemPromptCtrl.text;
    _controller.chatMode = _chatMode;
    _controller.stopAfterToolCall = _stopAfterToolCall;

    if (_useCustomLlm) {
      _controller.customLlmConfig = LlmConfig(
        provider: _customProvider,
        model: _customModelCtrl.text.trim(),
        apiKey: _customApiKeyCtrl.text.trim(),
        baseUrl: _customBaseUrlCtrl.text.trim(),
        temperature: double.tryParse(_customTempCtrl.text.trim()) ?? 0.2,
        maxTokens: int.tryParse(_customMaxTokensCtrl.text.trim()) ?? 0,
        maxToolOutputSize: int.tryParse(_customMaxToolOutputSizeCtrl.text.trim()) ?? 2560000,
        tokenWarningThreshold: int.tryParse(_customTokenWarningThresholdCtrl.text.trim()) ?? 1500000,
        topK: int.tryParse(_customTopKCtrl.text.trim()),
        topP: double.tryParse(_customTopPCtrl.text.trim()),
        repeatPenalty: double.tryParse(_customRepeatPenaltyCtrl.text.trim()),
        seed: int.tryParse(_customSeedCtrl.text.trim()),
        thinking: _customThinking,
        isSlm: _customIsSlm,
        isMultiModal: _customIsMultiModal,
        useNativeToolCall: _customUseNativeTool,
      );
    } else {
      _controller.customLlmConfig = null;
    }

    setState(() {
      _playgroundStarted = true;
    });

    // 2. Populate initial prompt in text input if provided
    final initPrompt = _initialPromptCtrl.text.trim();
    if (initPrompt.isNotEmpty) {
      _inputCtrl.text = initPrompt;
    }
  }

  // Initial Screen Widget Build
  Widget _buildSetupView(ThemeData theme) {
    final groups = _getToolsetGroups();
    final enabledGroups = groups.where((g) => _isToolsetEnabled(g)).toList();
    final hasSshEnabled = groups.any((g) => g.name == 'SSH / SFTP' && _isToolsetEnabled(g));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
              // Welcome / Try info banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const Expanded(
                      child: Text(
                        'Try out prompts, tools, and system instructions here before scheduling an agent.',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              // Tool Selector section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    spacing: 10,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (enabledGroups.isEmpty) ...[
                        ElevatedButton.icon(
                          onPressed: _showToolChecklistDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Choose active tools/toolsets'),
                        ),
                        const Text('No tools selected. Chat mode will be active.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ] else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...enabledGroups.map((group) {
                              IconData icon = Icons.extension_outlined;
                              Color iconColor = theme.colorScheme.primary;
                              if (group.isExternal) {
                                icon = Icons.dns_outlined;
                                iconColor = Colors.orange;
                              } else if (group.isInstalled) {
                                icon = Icons.hub_outlined;
                                iconColor = Colors.teal;
                              }
                              return InputChip(
                                avatar: Icon(icon, size: 14, color: iconColor),
                                label: Text(group.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setState(() {
                                    for (final t in group.tools) {
                                      _controller.toggleToolEnabled(t.name, false);
                                    }
                                  });
                                },
                                onPressed: () {
                                  _showIndividualToolsDialog(group);
                                },
                              );
                            }),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 14),
                              label: const Text('Select Tools', style: TextStyle(fontSize: 12)),
                              onPressed: _showToolChecklistDialog,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // SSH Override Card
              if (hasSshEnabled)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'SSH — Connection Override',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Leave empty to use global SSH settings.',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _sshHostCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Host / IP',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) => _updateSshParamsInController(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _sshPortCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _updateSshParamsInController(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _sshUsernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _updateSshParamsInController(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _sshPasswordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _updateSshParamsInController(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await FilePicker.platform.pickFiles(
                                    type: FileType.any,
                                    allowMultiple: false,
                                    withData: true,
                                  );
                                  if (result == null ||
                                      result.files.single.bytes == null) {
                                    return;
                                  }
                                  final keyText = utf8.decode(
                                    result.files.single.bytes!,
                                    allowMalformed: false,
                                  );
                                  setState(() {
                                    _sshPrivateKeyPem = keyText;
                                    _sshPrivateKeyFileName = result.files.single.name;
                                    _updateSshParamsInController();
                                  });
                                },
                                icon: const Icon(Icons.key, size: 16),
                                label: Text(
                                  _sshPrivateKeyFileName.isNotEmpty
                                      ? _sshPrivateKeyFileName
                                      : 'Load Private Key (PEM)…',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (_sshPrivateKeyPem.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Clear private key',
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setState(() {
                                  _sshPrivateKeyPem = '';
                                  _sshPrivateKeyFileName = '';
                                  _updateSshParamsInController();
                                }),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _testSshOverrideConnection,
                            icon: const Icon(Icons.network_check),
                            label: const Text('Test connection'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Setup parameters checklists
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: _chatMode,
                        title: const Text('Chat mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Direct LLM chat — no system prompt, no tools. Fastest for simple tasks.', style: TextStyle(fontSize: 11)),
                        onChanged: (v) {
                          setState(() {
                            _chatMode = v ?? false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        value: _stopAfterToolCall,
                        title: const Text('Stop after tool call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Execute the tool call but don\'t send the result back to the LLM.', style: TextStyle(fontSize: 11)),
                        onChanged: (v) {
                          setState(() {
                            _stopAfterToolCall = v ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // System Prompt Field
              if (!_chatMode) ...[
                const Text('System Prompt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                TextFormField(
                  controller: _systemPromptCtrl,
                  maxLines: 5,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Enter instructions, persona details, or system guidelines...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              // LLM Selector Selection
              const Text('LLM Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('LLM 1 (${_controller.llmConfig.model.isNotEmpty ? _controller.llmConfig.model : 'default'})'),
                    icon: const Icon(Icons.psychology_outlined),
                  ),
                  const ButtonSegment(
                    value: true,
                    label: Text('Custom LLM Override'),
                    icon: Icon(Icons.tune_outlined),
                  ),
                ],
                selected: {_useCustomLlm},
                onSelectionChanged: (val) {
                  setState(() {
                    _useCustomLlm = val.first;
                    if (_useCustomLlm && _customModelCtrl.text.isEmpty) {
                      _applyLlmDefaults();
                    }
                  });
                },
              ),

              // Custom LLM Configurations Panel (Pic 3 style)
              if (_useCustomLlm)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      spacing: 12,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Custom LLM Config', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            OutlinedButton.icon(
                              onPressed: _applyLlmDefaults,
                              icon: const Icon(Icons.settings_backup_restore),
                              label: const Text('Apply defaults from settings'),
                            ),
                          ],
                        ),
                        LlmConfigForm(
                          provider: _customProvider,
                          onProviderChanged: (val) {
                            setState(() {
                              _customProvider = val;
                            });
                          },
                          modelCtrl: _customModelCtrl,
                          apiKeyCtrl: _customApiKeyCtrl,
                          baseUrlCtrl: _customBaseUrlCtrl,
                        ),
                        if (_customProvider != LlmProvider.none) ...[
                          const SizedBox(height: 12),
                          ExpansionTile(
                            title: const Text(
                              'Advanced Custom Settings',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            tilePadding: EdgeInsets.zero,
                            children: [
                              LlmAdvancedSettingsForm(
                                tempCtrl: _customTempCtrl,
                                maxTokensCtrl: _customMaxTokensCtrl,
                                maxToolOutputSizeCtrl: _customMaxToolOutputSizeCtrl,
                                tokenWarningThresholdCtrl: _customTokenWarningThresholdCtrl,
                                topKCtrl: _customTopKCtrl,
                                topPCtrl: _customTopPCtrl,
                                repeatPenaltyCtrl: _customRepeatPenaltyCtrl,
                                seedCtrl: _customSeedCtrl,
                                thinking: _customThinking,
                                onThinkingChanged: (val) => setState(() => _customThinking = val),
                                isSlm: _customIsSlm,
                                onIsSlmChanged: (val) => setState(() => _customIsSlm = val),
                                isMultiModal: _customIsMultiModal,
                                onIsMultiModalChanged: (val) => setState(() => _customIsMultiModal = val),
                                useNativeToolCall: _customUseNativeTool,
                                onUseNativeToolCallChanged: (val) => setState(() => _customUseNativeTool = val),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Initial User message Prompt
              const Text('Initial Prompt (Optional first message)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              TextFormField(
                controller: _initialPromptCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter an optional first message to execute immediately on launch...',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _startPlayground,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Playground', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
    );
  }

  // Conversation/Chat Area build
  Widget _buildConversationView(ThemeData theme) {
    final groups = _getToolsetGroups();
    final enabledToolsCount = groups.expand((g) => g.tools).where((t) => !_controller.disabledToolNames.contains(t.name)).length;

    return Column(
      children: [
        // Top Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 16),
                label: const Text('System Prompt (tap to edit)'),
                onPressed: () {
                  final promptCtrl = TextEditingController(text: _controller.systemPrompt);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Edit System Prompt'),
                      content: TextFormField(
                        controller: promptCtrl,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _controller.systemPrompt = promptCtrl.text;
                              _systemPromptCtrl.text = promptCtrl.text;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.build_circle_outlined, size: 16),
                label: Text('$enabledToolsCount tools selected'),
                onPressed: _showSelectedToolsDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- Main Conversation Area ---
        Expanded(
          child: _controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _controller.messages.isEmpty
                  ? _buildWelcomeWidget(theme)
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _controller.messages.length,
                      itemBuilder: (ctx, idx) {
                        return ChatBubble(message: _controller.messages[idx]);
                      },
                    ),
        ),
        
        // --- Action Indicators (Generating / Errors) ---
        if (_controller.isGenerating)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Agent is thinking and processing tool calls...',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          
        if (_controller.errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.errorContainer,
            child: Text(
              _controller.errorMessage!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),

        // --- User Text Input Row ---
        _buildInputBar(theme),
      ],
    );
  }

  Widget _buildAttachmentPreviews() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        itemBuilder: (ctx, idx) {
          final att = _attachments[idx];
          final isImage = att.mimeType.startsWith('image/');
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(
                att.name,
                style: const TextStyle(fontSize: 11),
              ),
              avatar: Icon(
                isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                size: 14,
              ),
              onDeleted: () {
                setState(() {
                  _attachments.removeAt(idx);
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final showButton = _inputCtrl.text.isNotEmpty || _attachments.isNotEmpty || !_controller.isGenerating;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAttachmentPreviews(),
              TextField(
                controller: _inputCtrl,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message or ask a tool to run...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (text) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file_outlined),
                    tooltip: 'Attach Files / Images',
                    onPressed: _pickAttachments,
                  ),
                  IconButton(
                    icon: const Icon(Icons.build_outlined),
                    tooltip: 'Active Tools Checklist',
                    onPressed: _showChatToolsChecklistDialog,
                  ),
                  IconButton(
                    icon: Icon(
                      _controller.stopAfterToolCall ? Icons.flag : Icons.flag_outlined,
                      color: _controller.stopAfterToolCall ? theme.colorScheme.error : null,
                    ),
                    tooltip: _controller.stopAfterToolCall
                        ? 'Stop after tool execution: ON'
                        : 'Stop after tool execution: OFF',
                    onPressed: () {
                      setState(() {
                        _controller.stopAfterToolCall = !_controller.stopAfterToolCall;
                      });
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.send_rounded,
                      color: showButton && _controller.llmConfig.isConfigured
                          ? theme.colorScheme.primary
                          : Colors.grey,
                    ),
                    onPressed: showButton && _controller.llmConfig.isConfigured
                        ? _handleSend
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeWidget(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 72, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Playground Active',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your system prompt, enabled tools, and configurations have been successfully initialized. Start the chat below.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearSetupInputs() {
    setState(() {
      _systemPromptCtrl.clear();
      _initialPromptCtrl.clear();
      _sshHostCtrl.clear();
      _sshPortCtrl.text = '22';
      _sshUsernameCtrl.clear();
      _sshPasswordCtrl.clear();
      _sshPrivateKeyPem = '';
      _sshPrivateKeyFileName = '';
      
      final allTools = _getToolsetGroups().expand((g) => g.tools).map((t) => t.name).toList();
      for (final tool in allTools) {
        _controller.toggleToolEnabled(tool, false);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared all inputs and disabled all tools.')),
    );
  }

  void _showAgentInspectorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Color(0xFF7C3AED)),
            const SizedBox(width: 8),
            const Text('Agent Inspector'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.85,
          child: AgentInspector(controller: _controller),
        ),
      ),
    );
  }

  void _showSelectedToolsDialog() {
    final groups = _getToolsetGroups();
    final disabled = _controller.disabledToolNames;
    final enabledTools = groups
        .expand((g) => g.tools)
        .where((t) => !disabled.contains(t.name))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selected Tools'),
        content: SizedBox(
          width: 320,
          child: enabledTools.isEmpty
              ? const Text('No tools selected.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: enabledTools.length,
                  itemBuilder: (context, index) {
                    final tool = enabledTools[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.build, size: 16),
                      title: Text(
                        tool.name,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: tool.description != null && tool.description!.isNotEmpty
                          ? Text(tool.description!, maxLines: 2, overflow: TextOverflow.ellipsis)
                          : null,
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
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    final examplesButton = PopupMenuButton<String>(
      icon: const Icon(Icons.lightbulb_outline),
      tooltip: 'Load Prompt Templates / Examples',
      onSelected: _handleExampleAction,
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: 'weather',
          child: Row(
            children: [
              Icon(Icons.cloud_outlined, size: 18),
              SizedBox(width: 8),
              Text('Template: Weather Report'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'ssh',
          child: Row(
            children: [
              Icon(Icons.terminal_outlined, size: 18),
              SizedBox(width: 8),
              Text('Template: SSH Command'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'chart',
          child: Row(
            children: [
              Icon(Icons.bar_chart_outlined, size: 18),
              SizedBox(width: 8),
              Text('Template: Generate Chart'),
            ],
          ),
        ),
      ],
    );

    if (isWide) {
      final showInspectorButton = _playgroundStarted && MediaQuery.sizeOf(context).width < 900;
      return [
        examplesButton,
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: 'Reset Conversation & Setup',
          onPressed: _resetPlayground,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: 'Clear Inputs & Tools',
          onPressed: _clearSetupInputs,
        ),
        IconButton(
          icon: const Icon(Icons.bookmarks_outlined),
          tooltip: 'Load Saved Setup Configurations',
          onPressed: _showLoadSetupsDialog,
        ),
        IconButton(
          icon: const Icon(Icons.bookmark_add_outlined),
          tooltip: 'Save Current Setup Configuration',
          onPressed: _showSaveSetupDialog,
        ),
        const VerticalDivider(width: 16, indent: 12, endIndent: 12),
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: 'Registered Tools Catalog',
          onPressed: () => RegisteredToolsDialog.show(context, _controller),
        ),
        if (showInspectorButton)
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Agent Inspector',
            onPressed: _showAgentInspectorDialog,
          ),
      ];
    }

    // Mobile / Narrow: Pinned buttons + Overflow
    return [
      examplesButton,
      IconButton(
        icon: const Icon(Icons.restart_alt),
        tooltip: 'Reset Conversation & Setup',
        onPressed: _resetPlayground,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'More Actions',
        onSelected: (val) {
          if (val == 'clear') {
            _clearSetupInputs();
          } else if (val == 'load') {
            _showLoadSetupsDialog();
          } else if (val == 'save') {
            _showSaveSetupDialog();
          } else if (val == 'catalog') {
            RegisteredToolsDialog.show(context, _controller);
          } else if (val == 'inspector') {
            _showAgentInspectorDialog();
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.delete_sweep_outlined, size: 20),
                SizedBox(width: 12),
                Text('Clear Inputs & Tools'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'load',
            child: Row(
              children: [
                Icon(Icons.bookmarks_outlined, size: 20),
                SizedBox(width: 12),
                Text('Load Configuration'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'save',
            child: Row(
              children: [
                Icon(Icons.bookmark_add_outlined, size: 20),
                SizedBox(width: 12),
                Text('Save Configuration'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'catalog',
            child: Row(
              children: [
                Icon(Icons.list_alt, size: 20),
                SizedBox(width: 12),
                Text('Tools Catalog'),
              ],
            ),
          ),
          if (_playgroundStarted)
            const PopupMenuItem(
              value: 'inspector',
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Agent Inspector'),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final Widget bodyContent = _playgroundStarted
        ? _buildConversationView(theme)
        : _buildSetupView(theme);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'Playground',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: _buildAppBarActions(context),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
              ),
              child: const Text(
                'AI Agent Playground',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Playground'),
              onTap: () {
                Navigator.pop(context);
                _resetPlayground();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Playground Settings'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SettingsPanel(controller: _controller),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: isWide
          ? LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                if (!_playgroundStarted) {
                  return bodyContent;
                }
                const minChatWidth = 300.0;
                const minInspectorWidth = 250.0;

                double chatWidth = totalWidth * _chatFraction;
                if (chatWidth < minChatWidth) {
                  chatWidth = minChatWidth;
                }
                if (totalWidth - chatWidth - 8 < minInspectorWidth) {
                  chatWidth = totalWidth - minInspectorWidth - 8;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: chatWidth,
                      child: bodyContent,
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _chatFraction = (chatWidth + details.delta.dx) / totalWidth;
                          if (_chatFraction < 0.2) _chatFraction = 0.2;
                          if (_chatFraction > 0.85) _chatFraction = 0.85;
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: Container(
                          width: 8,
                          color: theme.dividerColor.withValues(alpha: 0.1),
                          child: Center(
                            child: Container(
                              width: 1,
                              color: theme.dividerColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: AgentInspector(controller: _controller),
                    ),
                  ],
                );
              },
            )
          : bodyContent,
    );
  }
}

class _ToolsetGroup {
  final String name;
  final String description;
  final List<MCPTool> tools;
  final bool isExternal;
  final bool isInstalled;

  _ToolsetGroup({
    required this.name,
    required this.description,
    required this.tools,
    this.isExternal = false,
    this.isInstalled = false,
  });
}
