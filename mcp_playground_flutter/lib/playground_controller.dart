import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import 'src/utils/mime_utils.dart';
import 'src/services/embedded_llm/embedded_llm_adapter.dart';
import 'src/skills/file_system_skill_storage_adapter.dart';
import 'src/skills/web_skill_storage_adapter.dart';

/// Abstract delegate for storing and loading LLM configuration, server registry, and saved setups.
abstract class McpPlaygroundStorageDelegate {
  /// Saves the active LLM configuration.
  Future<void> saveLlmConfig(LlmConfig config);

  /// Loads the saved LLM configuration.
  Future<LlmConfig?> loadLlmConfig();

  /// Saves the list of registered MCP servers.
  Future<void> saveServers(List<McpServerConfig> servers);

  /// Loads the list of registered MCP servers.
  Future<List<McpServerConfig>> loadServers();

  /// Saves the list of user-created configuration setups.
  Future<void> saveSetups(List<SavedPlaygroundSetup> setups);

  /// Loads the list of user-created configuration setups.
  Future<List<SavedPlaygroundSetup>> loadSetups();

  /// Saves the active enabled tool names.
  Future<void> saveEnabledTools(Set<String> tools) async {}

  /// Loads the saved enabled tool names.
  Future<Set<String>> loadEnabledTools() async => {};

  /// Saves the set of initialized client IDs.
  Future<void> saveInitializedClients(Set<String> clients) async {}

  /// Loads the set of initialized client IDs.
  Future<Set<String>> loadInitializedClients() async => {};

  /// Saves cached tools list for a server ID.
  Future<void> saveCachedServerTools(
    String serverId,
    List<MCPTool> tools,
  ) async {}

  /// Loads cached tools list for a server ID.
  Future<List<MCPTool>> loadCachedServerTools(String serverId) async => [];

  /// Saves the remote MCP server catalog response.
  Future<void> saveServerCatalog(String catalogJson) async {}

  /// Loads the saved server catalog response.
  Future<String?> loadServerCatalog() async => null;

  /// Saves the remote MCP server catalog timestamp.
  Future<void> saveServerCatalogTimestamp(int timestamp) async {}

  /// Loads the saved server catalog timestamp.
  Future<int?> loadServerCatalogTimestamp() async => null;

  /// Saves the root directory path for skill ZIP storage (desktop/mobile).
  Future<void> saveSkillsRootPath(String path) async {}

  /// Loads the root directory path for skill ZIP storage.
  Future<String?> loadSkillsRootPath() async => null;
}

/// A default implementation of [McpPlaygroundStorageDelegate] using SharedPreferences.
class SharedPreferencesStorageDelegate implements McpPlaygroundStorageDelegate {
  static const _kLlm = 'mcp_playground_llm_config';
  static const _kServers = 'mcp_playground_servers';
  static const _kSetups = 'mcp_playground_saved_setups';
  static const _kEnabledTools = 'mcp_playground_enabled_tools';
  static const _kInitializedClients = 'mcp_playground_initialized_clients';
  static const _kCachedServerTools = 'mcp_playground_cached_server_tools';

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> get _instance async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  @override
  Future<void> saveLlmConfig(LlmConfig config) async {
    final prefs = await _instance;
    await prefs.setString(_kLlm, jsonEncode(config.toJson()));
  }

  @override
  Future<LlmConfig?> loadLlmConfig() async {
    final prefs = await _instance;
    final raw = prefs.getString(_kLlm);
    if (raw == null || raw.isEmpty) return null;
    try {
      return LlmConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveServers(List<McpServerConfig> servers) async {
    final prefs = await _instance;
    final list = servers.map((s) => s.toJson()).toList();
    await prefs.setString(_kServers, jsonEncode(list));
  }

  @override
  Future<List<McpServerConfig>> loadServers() async {
    final prefs = await _instance;
    final raw = prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => McpServerConfig.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveSetups(List<SavedPlaygroundSetup> setups) async {
    final prefs = await _instance;
    final list = setups.map((s) => s.toJson()).toList();
    await prefs.setString(_kSetups, jsonEncode(list));
  }

  @override
  Future<List<SavedPlaygroundSetup>> loadSetups() async {
    final prefs = await _instance;
    final raw = prefs.getString(_kSetups);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (item) =>
                SavedPlaygroundSetup.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveEnabledTools(Set<String> tools) async {
    final prefs = await _instance;
    await prefs.setStringList(_kEnabledTools, tools.toList());
  }

  @override
  Future<Set<String>> loadEnabledTools() async {
    final prefs = await _instance;
    final list = prefs.getStringList(_kEnabledTools);
    return list?.toSet() ?? {};
  }

  @override
  Future<void> saveInitializedClients(Set<String> clients) async {
    final prefs = await _instance;
    await prefs.setStringList(_kInitializedClients, clients.toList());
  }

  @override
  Future<Set<String>> loadInitializedClients() async {
    final prefs = await _instance;
    final list = prefs.getStringList(_kInitializedClients);
    return list?.toSet() ?? {};
  }

  @override
  Future<void> saveCachedServerTools(
    String serverId,
    List<MCPTool> tools,
  ) async {
    final prefs = await _instance;
    final list = tools.map((t) => t.toJson()).toList();
    await prefs.setString('${_kCachedServerTools}_$serverId', jsonEncode(list));
  }

  @override
  Future<List<MCPTool>> loadCachedServerTools(String serverId) async {
    final prefs = await _instance;
    final raw = prefs.getString('${_kCachedServerTools}_$serverId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => MCPTool.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveServerCatalog(String catalogJson) async {
    final prefs = await _instance;
    await prefs.setString('mcp_playground_server_catalog', catalogJson);
  }

  @override
  Future<String?> loadServerCatalog() async {
    final prefs = await _instance;
    return prefs.getString('mcp_playground_server_catalog');
  }

  @override
  Future<void> saveServerCatalogTimestamp(int timestamp) async {
    final prefs = await _instance;
    await prefs.setInt('mcp_playground_server_catalog_ts', timestamp);
  }

  @override
  Future<int?> loadServerCatalogTimestamp() async {
    final prefs = await _instance;
    return prefs.getInt('mcp_playground_server_catalog_ts');
  }

  @override
  Future<void> saveSkillsRootPath(String path) async {
    final prefs = await _instance;
    await prefs.setString('mcp_playground_skills_root_path', path);
  }

  @override
  Future<String?> loadSkillsRootPath() async {
    final prefs = await _instance;
    return prefs.getString('mcp_playground_skills_root_path');
  }
}

/// Controller managing the state of the AI Agent Playground, chat messages, active tool loop execution, and server manager.
class PlaygroundController extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  LlmConfig _llmConfig;
  final List<McpServerConfig> _servers = [];
  final List<McpLocalTool> _localTools = [];
  final McpPlaygroundStorageDelegate _storage;

  bool _loading = false;
  bool _generating = false;
  bool _cancelRequested = false;
  String? _errorMessage;
  bool _stopAfterToolCall = false;
  final Set<String> _enabledToolNames = {};
  final Set<String> _initializedClientIds = {};
  final bool enableLogging;
  bool _isInitializing = false;

  /// Optional builder to customize rendering of chat bubble message contents dynamically.
  Widget? Function(BuildContext context, ChatMessage message)?
  messageContentBuilder;

  // ── Tool loop interception ──────────────────────────────────────
  /// Maximum number of tool call iterations per user request.
  static const int _maxToolIterations = 10;

  /// Counts tool call iterations in the current request.
  int _toolIterationCount = 0;

  /// When true, the next LLM call must NOT receive any tool definitions
  /// so the model is forced to produce a final text answer.
  bool _forceNoToolCallsNextTurn = false;

  /// Hint message injected alongside the forced no-tools turn.
  String? _forcedNoToolHintNextTurn;

  /// Tracks already-executed tool call signatures (`name|jsonArgs`) to
  /// detect repeated calls (especially from small models).
  final Set<String> _executedToolCallSignatures = {};

  /// Tracks already-executed tool call IDs.
  final Set<String> _executedToolCallIds = {};
  // ────────────────────────────────────────────────────────────────

  String _systemPrompt = '';
  bool _chatMode = false;
  LlmConfig? _customLlmConfig;

  final List<SavedPlaygroundSetup> _savedSetups = [];
  final MultiMCPManager _mcpManager = MultiMCPManager();
  final Uuid _uuid = const Uuid();

  SkillStorageAdapter? _skillStorage;

  /// The [SkillStorageAdapter] used for saving/loading skill ZIPs.
  ///
  /// Auto-selects a platform-appropriate default:
  /// - Desktop/mobile: [FileSystemSkillStorageAdapter] using [skillsRootPath]
  /// - Web: [WebSkillStorageAdapter]
  ///
  /// Users may inject a custom adapter via [setSkillStorageAdapter].
  SkillStorageAdapter get skillStorage {
    if (_skillStorage != null) return _skillStorage!;

    if (kIsWeb) {
      _skillStorage = WebSkillStorageAdapter();
    } else {
      _skillStorage = FileSystemSkillStorageAdapter(
        rootPath:
            _skillsRootPath ??
            '${Directory.systemTemp.path}${Platform.pathSeparator}mcp_playground_skills',
      );
    }
    return _skillStorage!;
  }

  /// Allows injecting a custom [SkillStorageAdapter] (e.g., DB-backed).
  void setSkillStorageAdapter(SkillStorageAdapter adapter) {
    _skillStorage = adapter;
  }

  String? _skillsRootPath;

  /// The root directory where skill ZIPs are stored (desktop/mobile only).
  String? get skillsRootPath => _skillsRootPath;

  /// Creates a new [PlaygroundController] instance.
  PlaygroundController({
    LlmConfig? initialLlmConfig,
    List<McpServerConfig>? initialServers,
    List<McpLocalTool>? customLocalTools,
    McpPlaygroundStorageDelegate? storageDelegate,
    this.enableLogging = false,
  }) : _llmConfig =
           initialLlmConfig ??
           const LlmConfig(provider: LlmProvider.none, model: '', apiKey: ''),
       _storage = storageDelegate ?? SharedPreferencesStorageDelegate() {
    if (initialServers != null) {
      _servers.addAll(initialServers);
    }
    // Register custom local tools (if any) passed via constructor
    if (customLocalTools != null) {
      _localTools.addAll(customLocalTools);
    }
    _registerEmbeddedLlmHandlers();
    _mcpManager.addListener(notifyListeners);
    _initAndLoad();
  }

  // --- Getters ---
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  LlmConfig get llmConfig => _llmConfig;
  List<McpServerConfig> get servers => List.unmodifiable(_servers);
  List<McpLocalTool> get localTools => List.unmodifiable(_localTools);
  bool get isLoading => _loading;
  bool get isGenerating => _generating;
  String? get errorMessage => _errorMessage;

  /// Requests cancellation of the currently executing prompt/sub-prompt chain.
  /// Safe to call from any thread.
  void cancelGeneration() {
    if (_generating) {
      _cancelRequested = true;
      notifyListeners();
    }
  }

  McpPlaygroundStorageDelegate get storage => _storage;

  bool get stopAfterToolCall => _stopAfterToolCall;
  set stopAfterToolCall(bool val) {
    _stopAfterToolCall = val;
    notifyListeners();
  }

  List<SavedPlaygroundSetup> get savedSetups => List.unmodifiable(_savedSetups);

  String get systemPrompt => _systemPrompt;
  set systemPrompt(String val) {
    _systemPrompt = val;
    notifyListeners();
  }

  bool get chatMode => _chatMode;
  set chatMode(bool val) {
    _chatMode = val;
    notifyListeners();
  }

  LlmConfig? get customLlmConfig => _customLlmConfig;
  set customLlmConfig(LlmConfig? val) {
    _customLlmConfig = val;
    notifyListeners();
  }

  LlmConfig get activeLlmConfig => _customLlmConfig ?? _llmConfig;

  Future<void> saveSetup(SavedPlaygroundSetup setup) async {
    final idx = _savedSetups.indexWhere((s) => s.id == setup.id);
    if (idx >= 0) {
      _savedSetups[idx] = setup;
    } else {
      _savedSetups.add(setup);
    }
    await _storage.saveSetups(_savedSetups);
    notifyListeners();
  }

  Future<void> deleteSetup(String id) async {
    _savedSetups.removeWhere((s) => s.id == id);
    await _storage.saveSetups(_savedSetups);
    notifyListeners();
  }

  List<MCPClientDef> get mcpClients => _mcpManager.clients;

  Set<String> get enabledToolNames => _enabledToolNames;
  void toggleToolEnabled(String toolName, bool enabled) {
    if (enabled) {
      _enabledToolNames.add(toolName);
    } else {
      _enabledToolNames.remove(toolName);
    }
    _storage.saveEnabledTools(_enabledToolNames);
    _syncMcpServers();
    notifyListeners();
  }

  void toggleToolsEnabled(Iterable<String> toolNames, bool enabled) {
    if (enabled) {
      _enabledToolNames.addAll(toolNames);
    } else {
      _enabledToolNames.removeAll(toolNames);
    }
    _storage.saveEnabledTools(_enabledToolNames);
    _syncMcpServers();
    notifyListeners();
  }

  void updateEnabledTools(Set<String> toolNames) {
    _enabledToolNames.clear();
    _enabledToolNames.addAll(toolNames);
    _storage.saveEnabledTools(_enabledToolNames);
    _syncMcpServers();
    notifyListeners();
  }

  List<MCPTool> get externalTools => _mcpManager.availableTools;

  static void _registerEmbeddedLlmHandlers() {
    LLMService.embeddedHandler =
        ({
          required LlmConfig config,
          required List<ChatMessage> messages,
          required List<MCPTool> tools,
          String? systemPrompt,
        }) async {
          final combinedMessages = <ChatMessage>[];
          if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
            combinedMessages.add(
              ChatMessage(
                id: 'system_prompt',
                content: systemPrompt,
                role: ChatRole.system,
                timestamp: DateTime.now(),
              ),
            );
          }
          combinedMessages.addAll(messages);

          return await EmbeddedLlmAdapter.instance.generateResponse(
            messages: combinedMessages,
            availableTools: tools,
            temperature: config.temperature,
            maxTokens: config.maxTokens > 0 ? config.maxTokens : 1024,
            topK: config.topK ?? 40,
            topP: config.topP ?? 0.9,
            penalty: config.repeatPenalty ?? 1.15,
          );
        };

    LLMService.embeddedStreamHandler =
        ({
          required LlmConfig config,
          required List<ChatMessage> messages,
          required List<MCPTool> tools,
          String? systemPrompt,
        }) {
          final controller = StreamController<LLMStreamChunk>();

          final combinedMessages = <ChatMessage>[];
          if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
            combinedMessages.add(
              ChatMessage(
                id: 'system_prompt',
                content: systemPrompt,
                role: ChatRole.system,
                timestamp: DateTime.now(),
              ),
            );
          }
          combinedMessages.addAll(messages);

          // Run in the background
          runZonedGuarded(
            () async {
              try {
                final response = await EmbeddedLlmAdapter.instance
                    .generateResponse(
                      messages: combinedMessages,
                      availableTools: tools,
                      temperature: config.temperature,
                      maxTokens: config.maxTokens > 0 ? config.maxTokens : 1024,
                      topK: config.topK ?? 40,
                      topP: config.topP ?? 0.9,
                      penalty: config.repeatPenalty ?? 1.15,
                      onStreamChunk: (textChunk) {
                        controller.add(LLMStreamChunk(textDelta: textChunk));
                      },
                    );
                controller.add(
                  LLMStreamChunk(
                    textDelta: '',
                    isDone: true,
                    finalResponse: response,
                  ),
                );
                await controller.close();
              } catch (e, st) {
                controller.addError(e, st);
                await controller.close();
              }
            },
            (error, stack) {
              if (!controller.isClosed) {
                controller.addError(error, stack);
                controller.close();
              }
            },
          );

          return controller.stream;
        };
  }

  Future<void> _initAndLoad() async {
    _loading = true;
    notifyListeners();
    try {
      final savedLlm = await _storage.loadLlmConfig();
      if (savedLlm != null) {
        _llmConfig = savedLlm;
      }
      final savedServers = await _storage.loadServers();
      if (savedServers.isNotEmpty) {
        _servers.clear();
        _servers.addAll(savedServers);
      }
      _isInitializing = true;
      final setups = await _storage.loadSetups();
      _savedSetups.clear();
      _savedSetups.addAll(setups);

      // Startup starts with no tools preselected
      _enabledToolNames.clear();

      final savedClients = await _storage.loadInitializedClients();
      _initializedClientIds.addAll(savedClients);

      await _syncMcpServers();
    } catch (e) {
      _errorMessage = 'Failed to load configuration: $e';
    } finally {
      _isInitializing = false;
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateLlmConfig(LlmConfig config) async {
    _llmConfig = config;
    await _storage.saveLlmConfig(config);
    notifyListeners();
  }

  Future<void> addServer(
    McpServerConfig server, {
    bool autoSelectTools = true,
  }) async {
    _servers.add(server);
    await _storage.saveServers(_servers);
    if (!autoSelectTools) {
      _initializedClientIds.add(server.name);
      await _storage.saveInitializedClients(_initializedClientIds);
    }
    await _syncMcpServers();
    notifyListeners();
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await _storage.saveServers(_servers);
    await _syncMcpServers();
    notifyListeners();
  }

  Future<void> toggleServer(String id, bool enabled) async {
    final idx = _servers.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _servers[idx] = _servers[idx].copyWith(enabled: enabled);
      await _storage.saveServers(_servers);
      await _syncMcpServers();
      notifyListeners();
    }
  }

  Future<void> updateServer(McpServerConfig server) async {
    final idx = _servers.indexWhere((s) => s.id == server.id);
    if (idx != -1) {
      _servers[idx] = server;
      await _storage.saveServers(_servers);
      await _syncMcpServers();
      notifyListeners();
    }
  }

  Future<void> _syncMcpServers() async {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final activeServers = _servers.where((s) {
      if (!s.enabled) return false;
      if (s.isLocal) {
        return isDesktop;
      }
      return s.url.trim().isNotEmpty;
    }).toList();

    final List<MCPClientDef> nextClients = [];
    final List<MCPClientDef> clientsToConnect = [];

    for (final s in activeServers) {
      final cachedTools = await _storage.loadCachedServerTools(s.id);

      final MCPClient client;
      if (s.isLocal) {
        client = LocalMCPClient(
          s,
          logCallback: (msg, {bool isError = false}) =>
              debugPrint('[Playground Local MCP Log: ${s.name}] $msg'),
        );
      } else {
        client = MCPClient(
          s.url,
          mcpEndpoint: s.mcpEndpoint,
          bearerToken: s.apiKey,
          apiPassword: s.apiPassword,
          logCallback: (msg, {bool isError = false}) =>
              debugPrint('[Playground MCP Log: ${s.name}] $msg'),
        );
      }

      final clientDef = MCPClientDef(
        name: s.id,
        client: client,
        displayName: s.name,
      );
      if (cachedTools.isNotEmpty) {
        clientDef.cachedTools = cachedTools;
      }
      nextClients.add(clientDef);

      final hasSelectedTool = cachedTools.any(
        (t) => _enabledToolNames.contains(t.name),
      );
      final shouldConnect = hasSelectedTool;

      if (shouldConnect) {
        clientsToConnect.add(clientDef);
      }
    }

    // Disconnect everything currently running
    await _mcpManager.disconnectAll();
    _mcpManager.clear();

    // Register all active client definitions
    for (final c in nextClients) {
      _mcpManager.registerClient(c);
    }

    // Only trigger actual connections for selected/undiscovered servers
    if (clientsToConnect.isNotEmpty) {
      await Future.wait(
        clientsToConnect.map((c) => _connectClientAndCacheTools(c)),
      );
    }

    bool changed = false;
    for (final clientDef in _mcpManager.clients) {
      if (clientDef.isConnected &&
          !_initializedClientIds.contains(clientDef.name)) {
        _initializedClientIds.add(clientDef.name);
        if (!_isInitializing) {
          for (final tool in clientDef.availableTools) {
            _enabledToolNames.add(tool.name);
          }
        }
        changed = true;
      }
    }

    if (changed) {
      await _storage.saveInitializedClients(_initializedClientIds);
      await _storage.saveEnabledTools(_enabledToolNames);
    }
  }

  Future<void> _connectClientAndCacheTools(MCPClientDef c) async {
    try {
      await c.client.connect();
      if (c.client.availableTools.isNotEmpty) {
        await _storage.saveCachedServerTools(c.name, c.client.availableTools);
        c.cachedTools = c.client.availableTools;
      }
    } catch (_) {}
  }

  Future<void> initializeAllUndiscoveredServers() async {
    final undiscovered = _mcpManager.clients.where((c) {
      final s = _servers.where((srv) => srv.id == c.name).firstOrNull;
      if (s == null || !s.enabled) return false;
      return !c.isConnected && c.availableTools.isEmpty;
    }).toList();

    if (undiscovered.isEmpty) return;

    await Future.wait(undiscovered.map((c) => _connectClientAndCacheTools(c)));

    bool changed = false;
    for (final clientDef in undiscovered) {
      if (clientDef.isConnected) {
        _initializedClientIds.add(clientDef.name);
        changed = true;
      }
    }

    if (changed) {
      await _storage.saveInitializedClients(_initializedClientIds);
    }

    await _syncMcpServers();
  }

  Future<void> connectServer(String id) async {
    final clients = _mcpManager.clients.where((c) => c.name == id);
    if (clients.isEmpty) return;
    final clientDef = clients.first;
    if (clientDef.isConnected) return;

    await _connectClientAndCacheTools(clientDef);

    notifyListeners();
  }

  Future<void> syncMcpServers() async {
    await _syncMcpServers();
  }

  void clearChat() {
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  Future<List<ChatMessage>> _preprocessMessagesForLlm(
    List<ChatMessage> messages,
    bool isMultiModal,
  ) async {
    final List<ChatMessage> processed = [];
    for (final m in messages) {
      if (m.role == ChatRole.user &&
          m.attachments != null &&
          m.attachments!.isNotEmpty) {
        final buffer = StringBuffer(m.content);
        final imagesOnly = <MessageAttachment>[];
        for (final att in m.attachments!) {
          final mime = att.mimeType.toLowerCase();
          final name = att.name.toLowerCase();
          final isText = isTextFile(mime, name);

          if (isText && att.bytes != null) {
            try {
              final content = utf8.decode(att.bytes!);
              buffer.writeln('\n\n[Attached File: ${att.name}]');
              buffer.writeln('--- CONTENT START ---');
              buffer.writeln(content);
              buffer.writeln('--- CONTENT END ---');
            } catch (_) {}
          } else if (att.bytes != null && mime.startsWith('image/')) {
            imagesOnly.add(att);
          }
        }
        processed.add(
          ChatMessage(
            id: m.id,
            role: m.role,
            content: buffer.toString(),
            timestamp: m.timestamp,
            attachments: isMultiModal ? imagesOnly : null,
          ),
        );
      } else if (m.role == ChatRole.tool) {
        final cleanedContent = _stripBase64AndBinary(m.content);
        processed.add(
          ChatMessage(
            id: m.id,
            role: m.role,
            content: cleanedContent,
            timestamp: m.timestamp,
            toolName: m.toolName,
            attachments: m.attachments,
          ),
        );
      } else {
        processed.add(m);
      }
    }
    return processed;
  }

  String _stripBase64AndBinary(String text) {
    var result = text;

    // 1. Check if the entire text is just a raw base64 string
    final cleanRaw = text.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanRaw.length > 100 && _looksLikeBase64(cleanRaw)) {
      return '[Binary/Image Data]';
    }

    // 2. Try JSON replacement (if the text is JSON containing base64)
    try {
      final decoded = jsonDecode(text.trim());
      final cleaned = _cleanJsonBase64(decoded);
      if (cleaned == null) {
        return '[Binary/Image Data]';
      }
      return const JsonEncoder.withIndent('  ').convert(cleaned);
    } catch (_) {
      // Not JSON
    }

    // 3. Fallback: regex search and replace base64 PNG blocks or general base64 blocks
    final base64Regex = RegExp(
      r'(iVBORw0KGgo[a-zA-Z0-9+/=\s\r\n]{50,})|([A-Za-z0-9+/]{100,}[=]{0,2})',
    );
    result = result.replaceAll(base64Regex, '[Binary/Image Data]');

    // Also strip data:image/... or data:application/... URI patterns
    final dataUriRegex = RegExp(
      r'data:[^/]+/[^;]+;base64,[a-zA-Z0-9+/=\s\r\n]+',
    );
    result = result.replaceAll(dataUriRegex, '[Binary/Image Data]');

    return result.trim();
  }

  bool _looksLikeBase64(String str) {
    if (str.startsWith('iVBORw0KGgo') || str.startsWith('data:')) return true;
    final clean = str.replaceAll(RegExp(r'\s+'), '');
    if (clean.length < 50) return false;
    final hasBase64Chars = RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(clean);
    return hasBase64Chars;
  }

  dynamic _cleanJsonBase64(dynamic val) {
    if (val is String) {
      final clean = val.trim().replaceAll(RegExp(r'\s+'), '');
      if (clean.length > 100 && _looksLikeBase64(clean)) {
        return '[Binary/Image Data]';
      }
      return val;
    } else if (val is Map) {
      final nextMap = <String, dynamic>{};
      for (final entry in val.entries) {
        nextMap[entry.key.toString()] = _cleanJsonBase64(entry.value);
      }
      return nextMap;
    } else if (val is List) {
      return val.map((item) => _cleanJsonBase64(item)).toList();
    }
    return val;
  }

  void _log(String message) {
    if (enableLogging) {
      debugPrint('[McpPlayground] $message');
    }
  }

  /// Sends a message and triggers the agentic tool call loop.
  Future<void> sendMessage(
    String text, {
    List<MessageAttachment>? attachments,
  }) async {
    if ((text.trim().isEmpty && (attachments == null || attachments.isEmpty)) ||
        _generating) {
      return;
    }

    _errorMessage = null;
    _cancelRequested = false;
    _generating = true;
    notifyListeners();

    _log('User Message: $text');

    try {
      final subPrompts = parseSubPromptSteps(text);
      _log('Parsed ${subPrompts.length} sub-prompt steps.');

      String? lastToolOutput;
      String? lastTaskResult;

      for (int i = 0; i < subPrompts.length; i++) {
        // ── Cancellation check between sub-prompts ──────────────────────────
        if (_cancelRequested) {
          _messages.add(
            ChatMessage(
              id: _uuid.v4(),
              content:
                  'Execution cancelled by user. Remaining sub-prompts skipped.',
              role: ChatRole.system,
              type: MessageType.log,
              timestamp: DateTime.now(),
            ),
          );
          notifyListeners();
          break;
        }
        final step = subPrompts[i];
        String prompt = step.text;

        // Substitute placeholders from previous steps
        if (lastToolOutput != null) {
          prompt = prompt
              .replaceAll(r'${tool_result}', lastToolOutput)
              .replaceAll('[tool_result]', lastToolOutput);
          lastToolOutput = null;
        }
        if (lastTaskResult != null) {
          prompt = prompt
              .replaceAll(r'${task_result}', lastTaskResult)
              .replaceAll('[task_result]', lastTaskResult);
          lastTaskResult = null;
        }

        // Determine if next step needs tool result
        final nextNeedsToolResult =
            (i + 1 < subPrompts.length) &&
            (subPrompts[i + 1].text.contains(r'${tool_result}') ||
                subPrompts[i + 1].text.contains('[tool_result]'));

        // Reset tool loop tracking for this step
        _toolIterationCount = 0;
        _forceNoToolCallsNextTurn = false;
        _forcedNoToolHintNextTurn = null;
        _executedToolCallSignatures.clear();
        _executedToolCallIds.clear();

        // 1. Add User Message (first step uses attachments if any, subsequent steps don't)
        final userMsg = ChatMessage(
          id: _uuid.v4(),
          content: prompt,
          role: ChatRole.user,
          attachments: (i == 0) ? attachments : null,
          timestamp: DateTime.now(),
        );
        _messages.add(userMsg);
        notifyListeners();

        final stepNewMsgs = <ChatMessage>[];

        // 3. Execution System Prompt
        String systemPrompt = _systemPrompt.trim().isNotEmpty
            ? _systemPrompt
            : 'You are an agent equipped with tools. Focus on the user\'s task. '
                  'Use the tool schemas precisely. If you decide to call a tool, generate the tool call block. '
                  'Present final answers directly. Present code and logs inside clean formatting.';

        // Inject short instructions into the system prompt to guide tool execution and loop prevention
        systemPrompt +=
            '\n\n'
            'Tool execution rules:\n'
            '- Each tool execution result is returned in a JSON structure: {"tool": "name", "id": "unique_id", "tool_executed": true, "tool_result": ...}.\n'
            '- Once a tool has been successfully executed (tool_executed is true), you must NEVER call that tool with the same "id" or parameters again.\n'
            '- Instead, formulate your final response to the user using the result provided in tool_result.';

        // Filter step tools
        final stepEnabled = step.enabledToolNames;
        final bool stepHasTools = stepEnabled != null
            ? stepEnabled.isNotEmpty
            : (_localTools.isNotEmpty || _mcpManager.availableTools.isNotEmpty);

        // Inject active tool descriptions into system prompt
        final List<MCPTool> allAvailableTools = [];
        allAvailableTools.addAll(_localTools.map((t) => t.toMCPTool()));
        allAvailableTools.addAll(_mcpManager.availableTools);

        final List<MCPTool> activeStepTools = allAvailableTools.where((t) {
          if (stepEnabled != null) {
            return stepEnabled.contains(t.name);
          }
          return _enabledToolNames.contains(t.name);
        }).toList();

        if (stepHasTools &&
            activeStepTools.isNotEmpty &&
            !activeLlmConfig.useNativeToolCall) {
          systemPrompt += '\n\nAvailable Tools:\n';
          for (final tool in activeStepTools) {
            systemPrompt += '- Tool Name: ${tool.name}\n';
            if (tool.description != null && tool.description!.isNotEmpty) {
              systemPrompt += '  Description: ${tool.description}\n';
            }
            if (tool.inputSchema != null) {
              systemPrompt +=
                  '  Input Schema: ${jsonEncode(tool.inputSchema)}\n';
            }
          }
        }

        _log('System Prompt for step ${i + 1}:\n$systemPrompt');

        bool continueLoop = true;

        while (continueLoop) {
          // ── Cancellation check between tool iterations ───────────────────
          if (_cancelRequested) {
            _messages.add(
              ChatMessage(
                id: _uuid.v4(),
                content: 'Execution cancelled by user.',
                role: ChatRole.system,
                type: MessageType.log,
                timestamp: DateTime.now(),
              ),
            );
            notifyListeners();
            break;
          }

          if (_toolIterationCount >= _maxToolIterations) {
            final limitMsg = ChatMessage(
              id: _uuid.v4(),
              content:
                  'Maximum tool iteration limit ($_maxToolIterations) reached. '
                  'Please refine your request or ask for help.',
              role: ChatRole.assistant,
              timestamp: DateTime.now(),
            );
            _messages.add(limitMsg);
            stepNewMsgs.add(limitMsg);
            notifyListeners();
            break;
          }

          // Build tools list (may be suppressed on forced-final turn)
          final List<MCPTool> mcpTools = [];
          if (!_chatMode && !_forceNoToolCallsNextTurn) {
            mcpTools.addAll(activeStepTools);
          }

          final List<ChatMessage> requestMsgs = await _preprocessMessagesForLlm(
            _messages,
            activeLlmConfig.isMultiModal,
          );
          if (_forceNoToolCallsNextTurn && _forcedNoToolHintNextTurn != null) {
            requestMsgs.add(
              ChatMessage(
                id: _uuid.v4(),
                content: _forcedNoToolHintNextTurn!,
                role: ChatRole.user,
                timestamp: DateTime.now(),
              ),
            );
            _forceNoToolCallsNextTurn = false;
            _forcedNoToolHintNextTurn = null;
          }

          _log('Generating LLM response...');
          final LLMResponse response;
          if (activeLlmConfig.useStreaming ||
              activeLlmConfig.isSlm ||
              activeLlmConfig.provider == LlmProvider.ollama) {
            final assistantId = _uuid.v4();
            final streamMsg = ChatMessage(
              id: assistantId,
              content: '',
              role: ChatRole.assistant,
              timestamp: DateTime.now(),
            );
            _messages.add(streamMsg);
            notifyListeners();

            final textBuffer = StringBuffer();
            LLMResponse? finalResponse;

            try {
              await for (final chunk in LLMService.generateStream(
                config: activeLlmConfig,
                messages: requestMsgs,
                tools: mcpTools,
                systemPrompt: systemPrompt,
              )) {
                if (_cancelRequested) break;
                if (chunk.textDelta.isNotEmpty) {
                  textBuffer.write(chunk.textDelta);
                  final idx = _messages.indexWhere((m) => m.id == assistantId);
                  if (idx != -1) {
                    _messages[idx] = streamMsg.copyWith(
                      content: textBuffer.toString(),
                    );
                    notifyListeners();
                  }
                }
                if (chunk.isDone) {
                  finalResponse = chunk.finalResponse;
                }
              }
            } finally {
              _messages.removeWhere((m) => m.id == assistantId);
            }

            if (_cancelRequested) break;
            response =
                finalResponse ?? LLMResponse(text: textBuffer.toString());
          } else {
            response = await LLMService.generate(
              config: activeLlmConfig,
              messages: requestMsgs,
              tools: mcpTools,
              systemPrompt: systemPrompt,
            );
          }

          // ── Cancellation check after LLM returns ──────────────────────
          if (_cancelRequested) {
            _messages.add(
              ChatMessage(
                id: _uuid.v4(),
                content: 'Execution cancelled by user.',
                role: ChatRole.system,
                type: MessageType.log,
                timestamp: DateTime.now(),
              ),
            );
            notifyListeners();
            break;
          }

          if (response.toolCalls.isEmpty) {
            if (response.text.isNotEmpty) {
              final textMsg = ChatMessage(
                id: _uuid.v4(),
                content: response.text,
                role: ChatRole.assistant,
                timestamp: DateTime.now(),
              );
              _messages.add(textMsg);
              stepNewMsgs.add(textMsg);
              _log('Assistant Response: ${response.text}');
            }
            continueLoop = false;
          } else {
            final call = response.toolCalls.first;
            _log(
              'Assistant Tool Call: ${call.name} with arguments: ${jsonEncode(call.arguments)}',
            );

            _toolIterationCount++;
            final toolSignature = '${call.name}|${jsonEncode(call.arguments)}';
            final hasDuplicateId = _executedToolCallIds.contains(call.id);
            final hasDuplicateSignature = _executedToolCallSignatures.contains(
              toolSignature,
            );

            if (hasDuplicateId || hasDuplicateSignature) {
              String previousResult = _messages
                  .lastWhere(
                    (m) => m.role == ChatRole.tool && m.toolName == call.name,
                    orElse: () => ChatMessage(
                      id: '',
                      content: '',
                      role: ChatRole.tool,
                      timestamp: DateTime.now(),
                    ),
                  )
                  .content;

              if (previousResult.trim().startsWith('{')) {
                try {
                  final decoded = jsonDecode(previousResult);
                  if (decoded is Map && decoded.containsKey('tool_result')) {
                    previousResult = decoded['tool_result'].toString();
                  }
                } catch (_) {}
              }

              final loopCorrectionText =
                  'The tool "${call.name}" was already successfully executed. '
                  'Previous result: $previousResult\n\n'
                  'Do NOT call this tool again. Generate the final response using this result.';

              final dupMsg = ChatMessage(
                id: call.id,
                content: activeLlmConfig.provider == LlmProvider.ollama
                    ? jsonEncode({
                        'tool': call.name,
                        'id': call.id,
                        'tool_executed': true,
                        'tool_result': loopCorrectionText,
                      })
                    : loopCorrectionText,
                role: ChatRole.tool,
                type: MessageType.toolResponse,
                toolName: call.name,
                toolResult: MCPToolResult(
                  content: [MCPContent(type: 'text', text: loopCorrectionText)],
                  isError: false,
                ),
                timestamp: DateTime.now(),
              );
              _messages.add(dupMsg);
              stepNewMsgs.add(dupMsg);
              notifyListeners();

              _forceNoToolCallsNextTurn = true;
              _forcedNoToolHintNextTurn =
                  'The tool "${call.name}" has already been successfully executed with these parameters. '
                  'Do NOT call this tool or any other tool again. Use the tool results in the history to write your final response now.';

              continueLoop = true;
              continue;
            }

            _executedToolCallIds.add(call.id);
            _executedToolCallSignatures.add(toolSignature);

            final callMsg = ChatMessage(
              id: call.id,
              content:
                  'Calling tool: ${call.name} with arguments: ${jsonEncode(call.arguments)}',
              role: ChatRole.assistant,
              type: MessageType.toolCall,
              toolName: call.name,
              toolArguments: call.arguments,
              timestamp: DateTime.now(),
            );
            _messages.add(callMsg);
            stepNewMsgs.add(callMsg);
            notifyListeners();

            _log('Executing Tool: ${call.name}');
            MCPToolResult result;
            final localMatch = _localTools
                .where((t) => t.name == call.name)
                .toList();

            if (localMatch.isNotEmpty) {
              result = await localMatch.first.execute(call.arguments);
            } else {
              result = await _mcpManager.callTool(call.name, call.arguments);
            }

            final String responseContentText = result.content
                .where((c) => c.type == 'text')
                .map((c) => c.text ?? '')
                .join('\n');

            _log('Tool Result: $responseContentText');

            final String finalContent;
            if (activeLlmConfig.provider == LlmProvider.ollama) {
              finalContent = jsonEncode({
                'tool': call.name,
                'id': call.id,
                'tool_executed': true,
                'tool_result': responseContentText.isNotEmpty
                    ? responseContentText
                    : 'Executed.',
              });
            } else {
              finalContent = responseContentText.isNotEmpty
                  ? responseContentText
                  : 'Executed.';
            }

            final resMsg = ChatMessage(
              id: call.id,
              content: finalContent,
              role: ChatRole.tool,
              type: MessageType.toolResponse,
              toolName: call.name,
              toolResult: result,
              timestamp: DateTime.now(),
            );
            _messages.add(resMsg);
            stepNewMsgs.add(resMsg);
            notifyListeners();

            final bool shouldStop =
                step.stopAfterToolCall ||
                _stopAfterToolCall ||
                nextNeedsToolResult;
            if (shouldStop) {
              continueLoop = false;
            }
          }
        }

        // Post-step processing: capture step output
        final toolTexts = stepNewMsgs
            .where((m) => m.role == ChatRole.tool && m.content.isNotEmpty)
            .map((m) {
              if (m.content.trim().startsWith('{')) {
                try {
                  final decoded = jsonDecode(m.content);
                  if (decoded is Map && decoded.containsKey('tool_result')) {
                    return decoded['tool_result'].toString();
                  }
                } catch (_) {}
              }
              return m.content;
            })
            .join('\n\n');

        final assistantTexts = stepNewMsgs
            .where(
              (m) =>
                  m.role == ChatRole.assistant &&
                  m.content.isNotEmpty &&
                  m.type != MessageType.toolCall,
            )
            .map((m) => m.content)
            .join('\n\n');

        final stepOutput = toolTexts.isNotEmpty
            ? toolTexts
            : (assistantTexts.isNotEmpty ? assistantTexts : null);

        if (stepOutput != null) {
          lastTaskResult = stepOutput;
          if (nextNeedsToolResult) {
            lastToolOutput = stepOutput;
            _log(
              'Captured step output for \${tool_result}/\${task_result} (${stepOutput.length} chars)',
            );
          } else {
            _log(
              'Captured step output for \${task_result} (${stepOutput.length} chars)',
            );
          }
        }

        final bool globalStopActive =
            _stopAfterToolCall && !nextNeedsToolResult;
        if (globalStopActive) {
          final nextWantsResult =
              (i + 1 < subPrompts.length) &&
              (subPrompts[i + 1].text.contains(r'${task_result}') ||
                  subPrompts[i + 1].text.contains('[task_result]'));
          if (!nextWantsResult &&
              stepNewMsgs.any((m) => m.role == ChatRole.tool)) {
            _log(
              '[stopAfterToolCall] Breaking sub-prompt chain after step ${i + 1} — no result consumer in next step',
            );
            break;
          }
        }
      }
    } catch (e) {
      _errorMessage = 'Execution error: $e';
      _log('Execution error: $e');
      _messages.add(
        ChatMessage(
          id: _uuid.v4(),
          content: 'Error: $e',
          role: ChatRole.system,
          type: MessageType.log,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _mcpManager.removeListener(notifyListeners);
    _mcpManager.disconnectAll();
    _mcpManager.dispose();
    super.dispose();
  }
}
