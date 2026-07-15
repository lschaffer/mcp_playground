import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'playground_controller.dart';
import 'src/widgets/chat_bubble.dart';
import 'src/widgets/settings_drawer.dart';
import 'src/widgets/registered_tools_dialog.dart';
import 'src/widgets/agent_inspector.dart';
import 'src/widgets/llm_config_form.dart';
import 'src/mcp_localizations.dart';
import 'src/widgets/sub_prompt_list_editor.dart';
import 'src/widgets/skill_save_dialog.dart';
import 'src/utils/mime_utils.dart';
import 'src/widgets/initial_mcp_install_progress_dialog.dart';
import 'src/services/embedded_llm/embedded_model.dart';
import 'src/services/embedded_llm/embedded_model_manager.dart';
import 'src/services/embedded_llm/embedded_llm_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _mimeFromExtension(String name) => mimeFromExtension(name);

/// An interactive AI Agent Playground widget for Flutter.
///
/// Connects to various LLM providers, registers Dart-native tools,
/// remote HTTP/S MCP servers, and local Node.js or Python subprocesses.
class McpPlayground extends StatefulWidget {
  /// Default LLM setup parameters.
  final LlmConfig? initialLlmConfig;

  /// Default list of HTTP/HTTPS MCP servers to connect to.
  final List<McpServerConfig>? initialServers;

  /// Optional list of local MCP servers to auto-initialize/install.
  final List<LocalMcpServerSetup>? initialLocalMcpServers;

  /// Optional delegate to customize settings save/load operations.
  /// Falls back to SharedPreferences if null.
  final McpPlaygroundStorageDelegate? storageDelegate;

  /// Custom list of internal, Dart-native tools to register.
  final List<McpLocalTool>? customLocalTools;

  /// Whether to disable opening the configuration dialog when LLM is not configured.
  final bool disableConfigDialog;

  /// Optional locale override ('en' or 'de').
  final String? locale;

  /// Optional builder to customize rendering of chat bubble message contents dynamically.
  final Widget? Function(BuildContext context, ChatMessage message)?
  messageContentBuilder;

  /// Whether to print clean console logs for key events.
  final bool enableLogging;

  /// Creates a new [McpPlayground] widget instance.
  const McpPlayground({
    super.key,
    this.initialLlmConfig,
    this.initialServers,
    this.initialLocalMcpServers,
    this.storageDelegate,
    this.customLocalTools,
    this.disableConfigDialog = false,
    this.locale,
    this.messageContentBuilder,
    this.enableLogging = false,
  });

  @override
  State<McpPlayground> createState() => _McpPlaygroundState();
}

class _McpPlaygroundState extends State<McpPlayground> {
  late final PlaygroundController _controller;

  McpPlaygroundLocalizations get _l10n {
    if (widget.locale != null) {
      return McpPlaygroundLocalizations(Locale(widget.locale!));
    }
    return McpPlaygroundLocalizations.of(context);
  }

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
  bool _isGeneratingSystemPrompt = false;

  // Custom LLM Override state
  bool _useCustomLlm = false;
  LlmProvider _customProvider = LlmProvider.none;
  final _customModelCtrl = TextEditingController();
  final _customApiKeyCtrl = TextEditingController();
  final _customBaseUrlCtrl = TextEditingController();

  // Per-provider field cache for the custom LLM override
  final Map<LlmProvider, _CustomProviderCache> _customProviderCache = {};
  final _customTempCtrl = TextEditingController(text: '0.2');
  final _customMaxTokensCtrl = TextEditingController(text: '0');
  final _customMaxToolOutputSizeCtrl = TextEditingController(text: '2560000');
  final _customTokenWarningThresholdCtrl = TextEditingController(
    text: '1500000',
  );
  final _customTopKCtrl = TextEditingController();
  final _customTopPCtrl = TextEditingController();
  final _customRepeatPenaltyCtrl = TextEditingController();
  final _customSeedCtrl = TextEditingController();
  bool _customThinking = false;
  bool _customIsSlm = false;
  bool _customIsMultiModal = true;
  bool _customUseNativeTool = true;
  bool _customUseStreaming = false;

  @override
  void initState() {
    super.initState();
    _controller = PlaygroundController(
      initialLlmConfig: widget.initialLlmConfig,
      initialServers: widget.initialServers,
      customLocalTools: widget.customLocalTools,
      storageDelegate: widget.storageDelegate,
      enableLogging: widget.enableLogging,
    );
    _controller.messageContentBuilder = widget.messageContentBuilder;
    _controller.addListener(_onStateChange);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndInstallInitialLocalMcpServers();
      await _checkAndDownloadInitialEmbeddedModel();
    });
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {});
      if (_controller.messages.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    }
  }

  Future<void> _checkAndInstallInitialLocalMcpServers() async {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    if (!isDesktop) return;

    // Wait until controller is done loading from storage
    while (_controller.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final localServersSetup = widget.initialLocalMcpServers;
    if (localServersSetup == null || localServersSetup.isEmpty) return;

    final List<LocalMcpServerSetup> serversToInstall = [];
    final List<McpServerConfig> configsToRegister = [];

    for (final setup in localServersSetup) {
      final existingIdx = _controller.servers.indexWhere(
        (s) => s.name == setup.name,
      );

      McpServerConfig? config;
      bool needsInstall = false;

      if (existingIdx != -1) {
        config = _controller.servers[existingIdx];
        if (setup.reinstall || !config.isInstalled) {
          needsInstall = true;
        }
      } else {
        needsInstall = true;
        config = McpServerConfig(
          id: const Uuid().v4(),
          name: setup.name,
          url: setup.launchArguments ?? '',
          isLocal: true,
          localType: setup.type,
          localInstallMethod: setup.method,
          localPackage: setup.packageOrServerName,
          localCommand: setup.installCommand,
          customLaunchCommand: setup.launchCommand,
          localEnvVars: setup.envVars,
          isInstalled: false,
          enabled: true,
        );
        configsToRegister.add(config);
      }

      if (needsInstall) {
        serversToInstall.add(setup);
      }
    }

    // Register all configs that are not in database yet
    for (final config in configsToRegister) {
      await _controller.addServer(config, autoSelectTools: false);
    }

    if (serversToInstall.isEmpty) return;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return InitialMcpInstallProgressDialog(
          serversToInstall: serversToInstall,
          controller: _controller,
          locale: widget.locale,
        );
      },
    );
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
    super.dispose();
  }

  void _handleSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    final loaded = await _ensureEmbeddedModelLoaded();
    if (!loaded) return;

    final listToSend = List<MessageAttachment>.from(_attachments);
    _inputCtrl.clear();
    setState(() {
      _attachments.clear();
    });

    _controller.sendMessage(text, attachments: listToSend);
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.pickFiles(
        withData: true,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.bytes != null) {
              final name = file.name;
              final mime = _mimeFromExtension(name);
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
    final groups = <_ToolsetGroup>[];

    final weatherTools = _controller.localTools
        .where(
          (t) =>
              t.name == 'get_current_weather' ||
              t.name == 'get_hourly_forecast' ||
              t.name == 'get_daily_forecast' ||
              t.name == 'geocode_weather_city',
        )
        .map((t) => t.toMCPTool())
        .toList();
    if (weatherTools.isNotEmpty) {
      groups.add(
        _ToolsetGroup(
          name: 'Weather',
          description:
              'Fetch weather forecasts using Open-Meteo (free, no API key). Provides current conditions, hourly and daily forecasts.',
          tools: weatherTools,
        ),
      );
    }

    final interactiveChartTools = _controller.localTools
        .where((t) => t.name == 'create_chart_png')
        .map((t) => t.toMCPTool())
        .toList();
    if (interactiveChartTools.isNotEmpty) {
      groups.add(
        _ToolsetGroup(
          name: 'Chart generator (Interactive)',
          description:
              'Generate interactive JSON charts rendered via fl_chart.',
          tools: interactiveChartTools,
        ),
      );
    }

    final imageChartTools = _controller.localTools
        .where((t) => t.name == 'chart2png')
        .map((t) => t.toMCPTool())
        .toList();
    if (imageChartTools.isNotEmpty) {
      groups.add(
        _ToolsetGroup(
          name: 'Chart generator (PNG Image)',
          description: 'Generate flat PNG image charts from canvas rendering.',
          tools: imageChartTools,
        ),
      );
    }

    final sshTools = _controller.localTools
        .where(
          (t) =>
              t.name.startsWith('ssh_') ||
              t.name.startsWith('sftp_') ||
              t.name == 'ssh_execute_command',
        )
        .map((t) => t.toMCPTool())
        .toList();
    if (sshTools.isNotEmpty) {
      groups.add(
        _ToolsetGroup(
          name: 'SSH/SFTP',
          description:
              'Execute remote commands, list directories, read, and transfer files via SSH/SFTP.',
          tools: sshTools,
        ),
      );
    }

    final otherTools = _controller.localTools
        .where(
          (t) =>
              t.name != 'get_current_weather' &&
              t.name != 'get_hourly_forecast' &&
              t.name != 'get_daily_forecast' &&
              t.name != 'geocode_weather_city' &&
              t.name != 'create_chart_png' &&
              t.name != 'chart2png' &&
              !t.name.startsWith('ssh_') &&
              !t.name.startsWith('sftp_'),
        )
        .map((t) => t.toMCPTool())
        .toList();
    if (otherTools.isNotEmpty) {
      groups.add(
        _ToolsetGroup(
          name: 'Custom Local Tools',
          description:
              'Custom Dart-native tools registered with the playground.',
          tools: otherTools,
        ),
      );
    }

    for (final client in _controller.mcpClients) {
      final isExt = client.url.startsWith('http');
      groups.add(
        _ToolsetGroup(
          name: client.label,
          description: client.url,
          tools: client.availableTools,
          isExternal: isExt,
          isInstalled: !isExt,
        ),
      );
    }
    return groups;
  }

  bool _isToolsetEnabled(_ToolsetGroup group) {
    final enabled = _controller.enabledToolNames;
    return group.tools.any((t) => enabled.contains(t.name));
  }

  void _showToolChecklistDialog() {
    final isMobileView = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF00ACC1)),
                const SizedBox(width: 16),
                Text(_l10n.get('discoveringAvailableTools')),
              ],
            ),
          ),
        ),
      ),
    );

    _controller.initializeAllUndiscoveredServers().then((_) {
      if (mounted) {
        Navigator.pop(context);
      }
      if (!mounted) return;

      Widget buildSetupDialogContent(
        BuildContext ctx,
        StateSetter setDialogState,
      ) {
        final theme = Theme.of(context);
        final groups = _getToolsetGroups();

        final builtin = groups
            .where((g) => !g.isExternal && !g.isInstalled)
            .toList();
        final external = groups.where((g) => g.isExternal).toList();
        final installed = groups.where((g) => g.isInstalled).toList();

        Widget buildHeader(String title, IconData icon, Color color) {
          return Padding(
            padding: const EdgeInsets.only(
              top: 16.0,
              bottom: 8.0,
              left: 20.0,
              right: 20.0,
            ),
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
          final enabled = _controller.enabledToolNames;
          final groupTools = group.tools;
          final activeCount = groupTools
              .where((t) => enabled.contains(t.name))
              .length;
          final totalCount = groupTools.length;

          final allEnabled =
              groupTools.isNotEmpty &&
              groupTools.every((t) => enabled.contains(t.name));
          final noneEnabled = groupTools.every(
            (t) => !enabled.contains(t.name),
          );
          bool? triStateVal;
          if (allEnabled) {
            triStateVal = true;
          } else if (noneEnabled) {
            triStateVal = false;
          } else {
            triStateVal = null; // Indeterminate
          }

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 12.0,
            ),
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$activeCount/$totalCount tools active',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (totalCount > 1) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                _showIndividualToolsDialog(group);
                              },
                              child: const Text(
                                'Customize',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF00ACC1),
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Checkbox(
                  value: triStateVal,
                  tristate: true,
                  activeColor: const Color(0xFF00ACC1),
                  onChanged: (val) {
                    final target = val ?? false;
                    setState(() {
                      _controller.toggleToolsEnabled(
                        groupTools.map((t) => t.name),
                        target,
                      );
                    });
                  },
                ),
              ],
            ),
          );
        }

        return ListView(
          shrinkWrap: true,
          children: [
            if (builtin.isNotEmpty) ...[
              buildHeader(
                'Built-in Tools',
                Icons.extension,
                theme.colorScheme.primary,
              ),
              ...builtin.map(buildGroupTile),
            ],
            if (external.isNotEmpty) ...[
              buildHeader(
                'External MCP Servers (SSE/HTTP)',
                Icons.dns,
                Colors.orange,
              ),
              ...external.map(buildGroupTile),
            ],
            if (installed.isNotEmpty) ...[
              buildHeader('Installed MCP Servers', Icons.hub, Colors.teal),
              ...installed.map(buildGroupTile),
            ],
          ],
        );
      }

      if (isMobileView) {
        showDialog(
          context: context,
          builder: (ctx) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Select Tools'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'OK',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                body: ListenableBuilder(
                  listenable: _controller,
                  builder: (ctx2, _) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) =>
                          buildSetupDialogContent(ctx, setDialogState),
                    );
                  },
                ),
              ),
            );
          },
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) {
            return ListenableBuilder(
              listenable: _controller,
              builder: (ctx2, _) {
                return StatefulBuilder(
                  builder: (context, setDialogState) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      title: const Text(
                        'Select Tools',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      content: SizedBox(
                        width: 480,
                        child: buildSetupDialogContent(ctx, setDialogState),
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
          },
        );
      }
    });
  }

  void _showIndividualToolsDialog(_ToolsetGroup group) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final enabled = _controller.enabledToolNames;
            final sortedTools = List<MCPTool>.from(group.tools)
              ..sort((a, b) => a.name.compareTo(b.name));
            return AlertDialog(
              title: Text(
                'Select tools from ${group.name}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: SizedBox(
                width: 400,
                child: ListView(
                  shrinkWrap: true,
                  children: sortedTools.map((t) {
                    final isEnabled = enabled.contains(t.name);
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
                        t.description ?? 'No description available.',
                        style: const TextStyle(fontSize: 11),
                      ),
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

  // Reset function
  void _resetPlayground() {
    setState(() {
      _playgroundStarted = false;
      _controller.clearChat();
      _attachments.clear();
    });
  }

  void _showSaveSkillDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SkillSaveDialog(
        controller: _controller,
        unsentInput: _inputCtrl.text.trim().isNotEmpty
            ? _inputCtrl.text.trim()
            : null,
      ),
    );
  }

  Future<void> _showLoadSkillDialog() async {
    final result = await showDialog<SavedPlaygroundSetup>(
      context: context,
      builder: (ctx) => SkillLoadDialog(controller: _controller),
    );

    if (result == null || !mounted) return;

    setState(() {
      _loadedSetupId = result.id;
      _systemPromptCtrl.text = result.systemPrompt;
      _initialPromptCtrl.text = result.initialPrompt;
      _chatMode = result.chatMode;
      _stopAfterToolCall = result.stopAfterToolCall;
      _useCustomLlm = result.useCustomLlm;

      if (result.customLlmConfig != null) {
        final custom = result.customLlmConfig!;
        _customProvider = custom.provider;
        _customModelCtrl.text = custom.model;
        _customApiKeyCtrl.text = custom.apiKey;
        _customBaseUrlCtrl.text = custom.baseUrl;
        _customTempCtrl.text = custom.temperature.toString();
        _customMaxTokensCtrl.text = custom.maxTokens.toString();
        _customMaxToolOutputSizeCtrl.text = custom.maxToolOutputSize.toString();
        _customTokenWarningThresholdCtrl.text = custom.tokenWarningThreshold
            .toString();
        _customTopKCtrl.text = custom.topK?.toString() ?? '';
        _customTopPCtrl.text = custom.topP?.toString() ?? '';
        _customRepeatPenaltyCtrl.text = custom.repeatPenalty?.toString() ?? '';
        _customSeedCtrl.text = custom.seed?.toString() ?? '';
        _customThinking = custom.thinking;
        _customIsSlm = custom.isSlm;
        _customIsMultiModal = custom.isMultiModal;
        _customUseNativeTool = custom.useNativeToolCall;
        _customUseStreaming = custom.useStreaming;
      }

      _controller.updateEnabledTools(result.enabledToolNames.toSet());
    });

    debugPrint('[LoadSkill] systemPrompt: ${result.systemPrompt.length} chars');
    debugPrint(
      '[LoadSkill] initialPrompt: ${result.initialPrompt.length} chars',
    );
    debugPrint('[LoadSkill] tools: ${result.enabledToolNames.length}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded skill "${result.name}".'),
          backgroundColor: Colors.green,
        ),
      );
    }
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
      _customTokenWarningThresholdCtrl.text = defaults.tokenWarningThreshold
          .toString();
      _customTopKCtrl.text = defaults.topK?.toString() ?? '';
      _customTopPCtrl.text = defaults.topP?.toString() ?? '';
      _customRepeatPenaltyCtrl.text = defaults.repeatPenalty?.toString() ?? '';
      _customSeedCtrl.text = defaults.seed?.toString() ?? '';
      _customThinking = defaults.thinking;
      _customIsSlm = defaults.isSlm;
      _customIsMultiModal = defaults.isMultiModal;
      _customUseNativeTool = defaults.useNativeToolCall;
      _customUseStreaming = defaults.useStreaming;
    });
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final isMobile = screenWidth < 600;
        if (isMobile) {
          return Dialog.fullscreen(
            child: SettingsPanel(controller: _controller),
          );
        }
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.8,
              minWidth: 400,
            ),
            child: SettingsPanel(controller: _controller),
          ),
        );
      },
    );
  }

  Future<void> _checkAndDownloadInitialEmbeddedModel() async {
    // Wait until controller is done loading from storage
    while (_controller.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final initialLlm = widget.initialLlmConfig;
    if (initialLlm == null || initialLlm.provider != LlmProvider.embedded) {
      return;
    }

    String filename = initialLlm.model.trim();
    if (filename == 'ministral3-3b-instruct q4' ||
        filename == 'ministral-3b-instruct q4') {
      filename = 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf';
    }

    if (filename.isEmpty) return;

    // Check if the custom GGUF model is registered in our local custom models db
    final customs = await EmbeddedModelManager.instance.loadCustomModels();
    EmbeddedGgufModel? model = customs
        .where((m) => m.filename == filename)
        .firstOrNull;

    if (model == null && _defaultModelMetadata.containsKey(filename)) {
      final meta = _defaultModelMetadata[filename]!;
      model = EmbeddedGgufModel(
        id: meta['repoId']!,
        displayName: meta['displayName']!,
        filename: filename,
        url: meta['url']!,
        description: 'Auto-registered model',
        sizeBytes: int.tryParse(meta['size']!) ?? 0,
        minRamGb: int.tryParse(meta['minRam']!) ?? 4,
        contextSize: int.tryParse(meta['contextSize']!) ?? 32768,
      );
      await EmbeddedModelManager.instance.addCustomModel(model);
    }

    model ??= EmbeddedGgufModel(
      id: filename,
      displayName: filename,
      filename: filename,
      url: '',
      description: '',
    );

    final bool fileExists;
    if (kIsWeb) {
      fileExists = true;
    } else {
      final fullPath = await EmbeddedModelManager.instance.fullPathForFilename(
        filename,
      );
      fileExists =
          await File(fullPath).exists() ||
          (model.url.isNotEmpty && await File(model.url).exists());
    }

    if (fileExists) {
      final updated = initialLlm.copyWith(model: filename);
      await _controller.updateLlmConfig(updated);
    } else {
      if (model.url.isEmpty) {
        return; // No URL to download
      }

      if (!mounted) return;
      final downloaded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ModelDownloadProgressDialog(model: model!),
      );

      if (downloaded == true) {
        final updated = initialLlm.copyWith(model: filename);
        await _controller.updateLlmConfig(updated);
      }
    }
  }

  Future<bool> _ensureEmbeddedModelLoaded() async {
    final config = _controller.activeLlmConfig;
    if (config.provider != LlmProvider.embedded) return true;

    String filename = config.model.trim();
    if (filename == 'ministral3-3b-instruct q4' ||
        filename == 'ministral-3b-instruct q4') {
      filename = 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf';
    }

    if (filename.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an embedded model in LLM Settings.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    final adapter = EmbeddedLlmAdapter.instance;
    if (adapter.isLoaded &&
        (adapter.loadedModelPath?.endsWith(filename) ?? false)) {
      return true;
    }

    final customs = await EmbeddedModelManager.instance.loadCustomModels();
    EmbeddedGgufModel? model = customs
        .where((m) => m.filename == filename)
        .firstOrNull;

    if (model == null && _defaultModelMetadata.containsKey(filename)) {
      final meta = _defaultModelMetadata[filename]!;
      model = EmbeddedGgufModel(
        id: meta['repoId']!,
        displayName: meta['displayName']!,
        filename: filename,
        url: meta['url']!,
        description: 'Auto-registered model',
        sizeBytes: int.tryParse(meta['size']!) ?? 0,
        minRamGb: int.tryParse(meta['minRam']!) ?? 4,
        contextSize: int.tryParse(meta['contextSize']!) ?? 32768,
      );
      await EmbeddedModelManager.instance.addCustomModel(model);
    }

    model ??= EmbeddedGgufModel(
      id: filename,
      displayName: filename,
      filename: filename,
      url: '',
      description: '',
    );

    final modelToLoad = model;

    final bool fileExists;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('web_downloaded_models') ?? [];
      fileExists = list.contains(filename);
    } else {
      final fullPath = await EmbeddedModelManager.instance.fullPathForFilename(
        filename,
      );
      fileExists =
          await File(fullPath).exists() ||
          (modelToLoad.url.isNotEmpty && await File(modelToLoad.url).exists());
    }

    if (!fileExists) {
      if (modelToLoad.url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Model file "$filename" not found and no download URL is available.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      if (!mounted) return false;
      final downloaded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ModelDownloadProgressDialog(model: modelToLoad),
      );

      if (downloaded != true) {
        return false;
      }
    }

    if (!mounted) return false;
    final loaded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModelLoadProgressDialog(model: modelToLoad),
    );

    return loaded ?? false;
  }

  LlmConfig _getActiveLlmConfig() {
    if (_useCustomLlm) {
      return LlmConfig(
        provider: _customProvider,
        model: _customModelCtrl.text.trim(),
        apiKey: _customApiKeyCtrl.text.trim(),
        baseUrl: _customBaseUrlCtrl.text.trim(),
        temperature: double.tryParse(_customTempCtrl.text.trim()) ?? 0.2,
        maxTokens: int.tryParse(_customMaxTokensCtrl.text.trim()) ?? 0,
        maxToolOutputSize:
            int.tryParse(_customMaxToolOutputSizeCtrl.text.trim()) ?? 2560000,
        tokenWarningThreshold:
            int.tryParse(_customTokenWarningThresholdCtrl.text.trim()) ??
            1500000,
        topK: int.tryParse(_customTopKCtrl.text.trim()),
        topP: double.tryParse(_customTopPCtrl.text.trim()),
        repeatPenalty: double.tryParse(_customRepeatPenaltyCtrl.text.trim()),
        seed: int.tryParse(_customSeedCtrl.text.trim()),
        thinking: _customThinking,
        isSlm: _customIsSlm,
        isMultiModal: _customIsMultiModal,
        useNativeToolCall: _customUseNativeTool,
        useStreaming: _customUseStreaming,
      );
    }
    return _controller.llmConfig;
  }

  Future<void> _generateSystemPrompt() async {
    final activeConfig = _getActiveLlmConfig();
    if (!activeConfig.isConfigured) return;

    setState(() {
      _isGeneratingSystemPrompt = true;
    });

    try {
      final groups = _getToolsetGroups();
      final enabledGroups = groups.where((g) => _isToolsetEnabled(g)).toList();

      String promptText =
          'Write a concise, professional system prompt (maximum 2-3 sentences) for an AI assistant. ';
      if (enabledGroups.isNotEmpty) {
        final toolDetails = enabledGroups
            .map((g) => '${g.name}: ${g.description}')
            .join('\n');
        promptText +=
            'The assistant is equipped with the following toolsets:\n$toolDetails\n\n';
        promptText +=
            'Focus on how the assistant should behave, be direct, and optimize usage of these tools. ';
      } else {
        promptText += 'Focus on being helpful, direct, and clear. ';
      }
      promptText +=
          'Respond ONLY with the generated system prompt text, with no introduction, quotes, or explanations.';

      final messages = [
        ChatMessage(
          id: const Uuid().v4(),
          content: promptText,
          role: ChatRole.user,
          timestamp: DateTime.now(),
        ),
      ];

      final response = await LLMService.generate(
        config: activeConfig,
        messages: messages,
        tools: const [],
        systemPrompt:
            'You are a prompt engineering expert. You output only the final requested prompt text with no markdown formatting or surrounding quotes.',
      );

      if (response.text.isNotEmpty && mounted) {
        setState(() {
          String text = response.text.trim();
          if (text.startsWith('"') && text.endsWith('"')) {
            text = text.substring(1, text.length - 1);
          }
          if (text.startsWith("'") && text.endsWith("'")) {
            text = text.substring(1, text.length - 1);
          }
          _systemPromptCtrl.text = text.trim();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate system prompt: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingSystemPrompt = false;
        });
      }
    }
  }

  void _startPlayground() async {
    // 1. Check if LLM is configured
    LlmConfig? nextCustom;
    if (_useCustomLlm) {
      nextCustom = LlmConfig(
        provider: _customProvider,
        model: _customModelCtrl.text.trim(),
        apiKey: _customApiKeyCtrl.text.trim(),
        baseUrl: _customBaseUrlCtrl.text.trim(),
        temperature: double.tryParse(_customTempCtrl.text.trim()) ?? 0.2,
        maxTokens: int.tryParse(_customMaxTokensCtrl.text.trim()) ?? 0,
        maxToolOutputSize:
            int.tryParse(_customMaxToolOutputSizeCtrl.text.trim()) ?? 2560000,
        tokenWarningThreshold:
            int.tryParse(_customTokenWarningThresholdCtrl.text.trim()) ??
            1500000,
        topK: int.tryParse(_customTopKCtrl.text.trim()),
        topP: double.tryParse(_customTopPCtrl.text.trim()),
        repeatPenalty: double.tryParse(_customRepeatPenaltyCtrl.text.trim()),
        seed: int.tryParse(_customSeedCtrl.text.trim()),
        thinking: _customThinking,
        isSlm: _customIsSlm,
        isMultiModal: _customIsMultiModal,
        useNativeToolCall: _customUseNativeTool,
        useStreaming: _customUseStreaming,
      );
    }

    final tempActiveConfig = nextCustom ?? _controller.llmConfig;
    if (!tempActiveConfig.isConfigured) {
      final l10n = _l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.get('pleaseConfigureLlm')),
          backgroundColor: Colors.orange,
        ),
      );
      if (!widget.disableConfigDialog) {
        _showSettingsDialog();
      }
      return;
    }

    _controller.systemPrompt = _systemPromptCtrl.text;
    _controller.chatMode = _chatMode;
    _controller.stopAfterToolCall = _stopAfterToolCall;
    _controller.customLlmConfig = nextCustom;

    final loaded = await _ensureEmbeddedModelLoaded();
    if (!loaded) return;

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        spacing: 16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tool Selector section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                spacing: 10,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Tools',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (enabledGroups.isEmpty) ...[
                    ElevatedButton.icon(
                      onPressed: _showToolChecklistDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Choose active tools/toolsets'),
                    ),
                    const Text(
                      'No tools selected. Chat mode will be active.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
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
                            label: Text(
                              group.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() {
                                _controller.toggleToolsEnabled(
                                  group.tools.map((t) => t.name),
                                  false,
                                );
                              });
                            },
                            onPressed: () {
                              _showIndividualToolsDialog(group);
                            },
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 14),
                          label: const Text(
                            'Select Tools',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: _showToolChecklistDialog,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Setup parameters checklists
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _chatMode,
                    title: const Text(
                      'Chat mode',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Direct LLM chat — no system prompt, no tools. Fastest for simple tasks.',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _chatMode = v ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // System Prompt Field
          if (!_chatMode) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Prompt',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                if (_getActiveLlmConfig().isConfigured)
                  IconButton(
                    icon: _isGeneratingSystemPrompt
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined, size: 20),
                    tooltip: 'Generate System Prompt',
                    onPressed: _isGeneratingSystemPrompt
                        ? null
                        : _generateSystemPrompt,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _systemPromptCtrl,
              maxLines: 5,
              minLines: 2,
              decoration: const InputDecoration(
                hintText:
                    'Enter instructions, persona details, or system guidelines...',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          // LLM Selector Selection
          const Text(
            'LLM Configuration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  'LLM 1 (${_controller.llmConfig.model.isNotEmpty ? _controller.llmConfig.model : 'default'})',
                ),
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
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'Custom LLM Config',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
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
                        // Save current provider's fields before switching
                        _customProviderCache[_customProvider] =
                            _CustomProviderCache(
                              model: _customModelCtrl.text,
                              apiKey: _customApiKeyCtrl.text,
                              baseUrl: _customBaseUrlCtrl.text,
                            );
                        // Restore or clear fields for the new provider
                        final cached = _customProviderCache[val];
                        if (cached != null) {
                          _customModelCtrl.text = cached.model;
                          _customApiKeyCtrl.text = cached.apiKey;
                          _customBaseUrlCtrl.text = cached.baseUrl;
                        } else {
                          _customModelCtrl.clear();
                          _customApiKeyCtrl.clear();
                          _customBaseUrlCtrl.clear();
                        }
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
                            tokenWarningThresholdCtrl:
                                _customTokenWarningThresholdCtrl,
                            topKCtrl: _customTopKCtrl,
                            topPCtrl: _customTopPCtrl,
                            repeatPenaltyCtrl: _customRepeatPenaltyCtrl,
                            seedCtrl: _customSeedCtrl,
                            thinking: _customThinking,
                            onThinkingChanged: (val) =>
                                setState(() => _customThinking = val),
                            isSlm: _customIsSlm,
                            onIsSlmChanged: (val) =>
                                setState(() => _customIsSlm = val),
                            isMultiModal: _customIsMultiModal,
                            onIsMultiModalChanged: (val) =>
                                setState(() => _customIsMultiModal = val),
                            useNativeToolCall: _customUseNativeTool,
                            onUseNativeToolCallChanged: (val) =>
                                setState(() => _customUseNativeTool = val),
                            useStreaming: _customUseStreaming,
                            onUseStreamingChanged: (val) =>
                                setState(() => _customUseStreaming = val),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Initial User message Prompt
          const Text(
            'Initial Prompt (Optional first message)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          SubPromptListEditor(
            controller: _initialPromptCtrl,
            chatMode: _chatMode,
            availableToolGroups: _getToolsetGroups()
                .where((g) => _isToolsetEnabled(g))
                .map(
                  (g) => ToolGroup(
                    name: g.name,
                    toolNames: g.tools.map((t) => t.name).toList(),
                  ),
                )
                .toList(),
            minLines: 2,
            maxLines: 8,
            hintText:
                'Enter an optional first message to execute immediately on launch...',
          ),

          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _startPlayground,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'Start Playground',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Conversation/Chat Area build
  Widget _buildConversationView(ThemeData theme) {
    final groups = _getToolsetGroups();
    final enabledToolsCount = groups
        .expand((g) => g.tools)
        .where((t) => _controller.enabledToolNames.contains(t.name))
        .length;

    return Column(
      children: [
        // Top Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 16),
                label: const Text('System Prompt (tap to edit)'),
                onPressed: () {
                  final promptCtrl = TextEditingController(
                    text: _controller.systemPrompt,
                  );
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
                    return ChatBubble(
                      message: _controller.messages[idx],
                      controller: _controller,
                    );
                  },
                ),
        ),

        // --- Action Indicators (Generating / Errors) ---
        if (_controller.isGenerating)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
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
              label: Text(att.name, style: const TextStyle(fontSize: 11)),
              avatar: Icon(
                isImage
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
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
    final showButton =
        _inputCtrl.text.isNotEmpty ||
        _attachments.isNotEmpty ||
        !_controller.isGenerating;
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
              SubPromptListEditor(
                controller: _inputCtrl,
                chatMode: _chatMode,
                availableToolGroups: _getToolsetGroups()
                    .where((g) => _isToolsetEnabled(g))
                    .map(
                      (g) => ToolGroup(
                        name: g.name,
                        toolNames: g.tools.map((t) => t.name).toList(),
                      ),
                    )
                    .toList(),
                minLines: 1,
                maxLines: 6,
                hintText: 'Type a message or ask a tool to run...',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file_outlined),
                    tooltip: 'Attach Files / Images',
                    onPressed: _controller.isGenerating
                        ? null
                        : _pickAttachments,
                  ),
                  const Spacer(),
                  if (_controller.isGenerating)
                    IconButton(
                      icon: const Icon(Icons.stop_circle),
                      iconSize: 24,
                      tooltip: 'Stop execution',
                      onPressed: () => _controller.cancelGeneration(),
                      color: Colors.red,
                    )
                  else
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color:
                            showButton &&
                                _controller.activeLlmConfig.isConfigured
                            ? theme.colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed:
                          showButton && _controller.activeLlmConfig.isConfigured
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
              Icon(
                Icons.smart_toy_outlined,
                size: 72,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Playground Active',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
      _loadedSetupId = null;

      final allTools = _getToolsetGroups()
          .expand((g) => g.tools)
          .map((t) => t.name)
          .toList();
      for (final tool in allTools) {
        _controller.toggleToolEnabled(tool, false);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cleared all inputs and disabled all tools.'),
      ),
    );
  }

  void _showAgentInspectorDialog() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Agent Inspector'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            body: AgentInspector(controller: _controller),
          ),
        ),
      );
      return;
    }

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
    final enabled = _controller.enabledToolNames;
    final enabledTools = groups
        .expand((g) => g.tools)
        .where((t) => enabled.contains(t.name))
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
                      subtitle:
                          tool.description != null &&
                              tool.description!.isNotEmpty
                          ? Text(
                              tool.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
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
    final l10n = _l10n;

    if (isWide) {
      final showInspectorButton =
          _playgroundStarted && MediaQuery.sizeOf(context).width < 900;
      return [
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: l10n.get('resetTooltip'),
          onPressed: _resetPlayground,
        ),
        if (!_playgroundStarted) ...[
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.get('clearTooltip'),
            onPressed: _clearSetupInputs,
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Load Skill',
            onPressed: _showLoadSkillDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Skill',
            onPressed: _showSaveSkillDialog,
          ),
        ],
        IconButton(
          icon: const Icon(Icons.save_outlined),
          tooltip: 'Save Skill',
          onPressed: _showSaveSkillDialog,
        ),
        const VerticalDivider(width: 16, indent: 12, endIndent: 12),
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: l10n.get('catalogTooltip'),
          onPressed: () => RegisteredToolsDialog.show(context, _controller),
        ),
        if (showInspectorButton)
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: l10n.get('agentInspector'),
            onPressed: _showAgentInspectorDialog,
          ),
      ];
    }

    // Mobile / Narrow: Pinned buttons + Overflow
    return [
      IconButton(
        icon: const Icon(Icons.restart_alt),
        tooltip: l10n.get('resetTooltip'),
        onPressed: _resetPlayground,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.get('moreActions'),
        onSelected: (val) {
          if (val == 'clear') {
            _clearSetupInputs();
          } else if (val == 'saveSkill') {
            _showSaveSkillDialog();
          } else if (val == 'loadSkill') {
            _showLoadSkillDialog();
          } else if (val == 'catalog') {
            RegisteredToolsDialog.show(context, _controller);
          } else if (val == 'inspector') {
            _showAgentInspectorDialog();
          }
        },
        itemBuilder: (ctx) => [
          if (!_playgroundStarted) ...[
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  const Icon(Icons.delete_sweep_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(l10n.get('clearTooltip')),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'loadSkill',
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 20),
                  const SizedBox(width: 12),
                  const Text('Load Skill'),
                ],
              ),
            ),
          ],
          PopupMenuItem(
            value: 'saveSkill',
            child: Row(
              children: [
                const Icon(Icons.save_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('Save Skill'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'catalog',
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 20),
                const SizedBox(width: 12),
                Text(l10n.get('catalogTooltip')),
              ],
            ),
          ),
          if (_playgroundStarted)
            PopupMenuItem(
              value: 'inspector',
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(l10n.get('agentInspector')),
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

    final loadedSetupName = _loadedSetupId != null
        ? _controller.savedSetups
              .cast<SavedPlaygroundSetup?>()
              .firstWhere((s) => s?.id == _loadedSetupId, orElse: () => null)
              ?.name
        : null;

    final l10n = _l10n;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.get('menu'),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          loadedSetupName != null
              ? '${l10n.get('playground')} - $loadedSetupName'
              : l10n.get('playground'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: _buildAppBarActions(context),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
              child: Text(
                l10n.get('agentPlayground'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(l10n.get('playground')),
              onTap: () {
                Navigator.pop(context);
                _resetPlayground();
              },
            ),
            if (!widget.disableConfigDialog)
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(l10n.get('playgroundSettings')),
                onTap: () {
                  Navigator.pop(context);
                  _showSettingsDialog();
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
                    SizedBox(width: chatWidth, child: bodyContent),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _chatFraction =
                              (chatWidth + details.delta.dx) / totalWidth;
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
                    Expanded(child: AgentInspector(controller: _controller)),
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

/// Holds per-provider model/apiKey/baseUrl for the custom LLM override,
/// so switching providers preserves previously entered data.
class _CustomProviderCache {
  final String model;
  final String apiKey;
  final String baseUrl;

  const _CustomProviderCache({
    required this.model,
    required this.apiKey,
    required this.baseUrl,
  });
}

const Map<String, Map<String, String>> _defaultModelMetadata = {
  'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf': {
    'repoId': 'lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF',
    'displayName': 'Ministral-3-3B-Instruct-2512-Q4_K_M',
    'url':
        'https://huggingface.co/lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
    'size': '2140000000',
    'minRam': '4',
    'contextSize': '32768',
  },
};

class _ModelDownloadProgressDialog extends StatefulWidget {
  final EmbeddedGgufModel model;
  const _ModelDownloadProgressDialog({required this.model});

  @override
  State<_ModelDownloadProgressDialog> createState() =>
      _ModelDownloadProgressDialogState();
}

class _ModelDownloadProgressDialogState
    extends State<_ModelDownloadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Starting download...';
  late final DownloadCancelToken _cancelToken;

  @override
  void initState() {
    super.initState();
    _cancelToken = DownloadCancelToken();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      if (kIsWeb) {
        final gpuLayers = await EmbeddedModelManager.instance.getGpuLayers(
          widget.model.filename,
        );
        await EmbeddedLlmAdapter.instance.initialize(
          widget.model.url,
          gpuLayers: gpuLayers,
          contextSize: widget.model.contextSize,
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _progress = p;
                _status = 'Downloading... ${(p * 100).toStringAsFixed(1)}%';
              });
            }
          },
        );
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('web_downloaded_models') ?? [];
        if (!list.contains(widget.model.filename)) {
          list.add(widget.model.filename);
          await prefs.setStringList('web_downloaded_models', list);
        }
      } else {
        await EmbeddedModelManager.instance.downloadModel(
          url: widget.model.url,
          filename: widget.model.filename,
          cancelToken: _cancelToken,
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _progress = p;
                _status = 'Downloading... ${(p * 100).toStringAsFixed(1)}%';
              });
            }
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Downloading ${widget.model.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelToken.cancel();
            Navigator.pop(context, false);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ModelLoadProgressDialog extends StatefulWidget {
  final EmbeddedGgufModel model;
  const _ModelLoadProgressDialog({required this.model});

  @override
  State<_ModelLoadProgressDialog> createState() =>
      _ModelLoadProgressDialogState();
}

class _ModelLoadProgressDialogState extends State<_ModelLoadProgressDialog> {
  double _progress = 0.0;
  String _status = 'Loading model into memory...';

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  Future<void> _startLoad() async {
    try {
      final gpuLayers = await EmbeddedModelManager.instance.getGpuLayers(
        widget.model.filename,
      );
      final String fullPath;
      if (kIsWeb) {
        fullPath = widget.model.url;
      } else {
        fullPath = File(widget.model.url).existsSync()
            ? widget.model.url
            : await EmbeddedModelManager.instance.fullPathForFilename(
                widget.model.filename,
              );
      }

      await EmbeddedLlmAdapter.instance.initialize(
        fullPath,
        gpuLayers: gpuLayers,
        contextSize: widget.model.contextSize,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status =
                  'Loading model into memory... ${(p * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Loading ${widget.model.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress),
        ],
      ),
    );
  }
}
