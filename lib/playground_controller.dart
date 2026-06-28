import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'mcp_client.dart';
import 'llm_service.dart';
import 'local_tools.dart';
import 'src/local_mcp_client.dart';

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
}

/// A default implementation of [McpPlaygroundStorageDelegate] using SharedPreferences.
class SharedPreferencesStorageDelegate implements McpPlaygroundStorageDelegate {
  static const _kLlm = 'mcp_playground_llm_config';
  static const _kServers = 'mcp_playground_servers';
  static const _kSetups = 'mcp_playground_saved_setups';

  @override
  Future<void> saveLlmConfig(LlmConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLlm, jsonEncode(config.toJson()));
  }

  @override
  Future<LlmConfig?> loadLlmConfig() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final list = servers.map((s) => s.toJson()).toList();
    await prefs.setString(_kServers, jsonEncode(list));
  }

  @override
  Future<List<McpServerConfig>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final list = setups.map((s) => s.toJson()).toList();
    await prefs.setString(_kSetups, jsonEncode(list));
  }

  @override
  Future<List<SavedPlaygroundSetup>> loadSetups() async {
    final prefs = await SharedPreferences.getInstance();
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
  String? _errorMessage;
  bool _stopAfterToolCall = false;
  final Set<String> _enabledToolNames = {};
  
  /// Optional builder to customize rendering of chat bubble message contents dynamically.
  Widget? Function(BuildContext context, ChatMessage message)? messageContentBuilder;

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

  /// Creates a new [PlaygroundController] instance.
  PlaygroundController({
    LlmConfig? initialLlmConfig,
    List<McpServerConfig>? initialServers,
    List<McpLocalTool>? customLocalTools,
    McpPlaygroundStorageDelegate? storageDelegate,
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
    notifyListeners();
  }

  List<MCPTool> get externalTools => _mcpManager.availableTools;

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
      final setups = await _storage.loadSetups();
      _savedSetups.clear();
      _savedSetups.addAll(setups);
      await _syncMcpServers();
    } catch (e) {
      _errorMessage = 'Failed to load configuration: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateLlmConfig(LlmConfig config) async {
    _llmConfig = config;
    await _storage.saveLlmConfig(config);
    notifyListeners();
  }

  Future<void> addServer(McpServerConfig server) async {
    _servers.add(server);
    await _storage.saveServers(_servers);
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
    await _mcpManager.disconnectAll();
    _mcpManager.clear();
    final activeServers = _servers
        .where((s) => s.enabled && (s.isLocal || s.url.trim().isNotEmpty))
        .toList();

    // Re-register external / local servers
    for (final s in activeServers) {
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
      _mcpManager.registerClient(
        MCPClientDef(name: s.id, client: client, displayName: s.name),
      );
    }

    // Connect to external/local servers in parallel
    await _mcpManager.initializeAll();
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
          final isText =
              mime.startsWith('text/') ||
              name.endsWith('.txt') ||
              name.endsWith('.md') ||
              name.endsWith('.csv') ||
              name.endsWith('.json') ||
              name.endsWith('.yaml') ||
              name.endsWith('.yml') ||
              name.endsWith('.xml') ||
              name.endsWith('.html') ||
              name.endsWith('.js') ||
              name.endsWith('.py') ||
              name.endsWith('.dart') ||
              name.endsWith('.sh') ||
              name.endsWith('.bat') ||
              name.endsWith('.ps1');

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
      } else {
        processed.add(m);
      }
    }
    return processed;
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

    // ── Reset tool loop tracking for this new user request ──────────
    _toolIterationCount = 0;
    _forceNoToolCallsNextTurn = false;
    _forcedNoToolHintNextTurn = null;
    _executedToolCallSignatures.clear();
    _executedToolCallIds.clear();

    _errorMessage = null;
    _generating = true;

    // 1. Add User Message
    _messages.add(
      ChatMessage(
        id: _uuid.v4(),
        content: text,
        role: ChatRole.user,
        attachments: attachments,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    try {
      int steps = 0;
      const maxSteps = 5;
      bool continueLoop = true;

      // 3. Execution System Prompt
      final systemPrompt = _systemPrompt.trim().isNotEmpty
          ? _systemPrompt
          : 'You are an agent equipped with tools. Focus on the user\'s task. '
                'Use the tool schemas precisely. If you decide to call a tool, generate the tool call block. '
                'Present final answers directly. Present code and logs inside clean formatting.';

      while (continueLoop && steps < maxSteps) {
        steps++;

        // ── Check iteration limit to prevent infinite loops ─────────
        if (_toolIterationCount > _maxToolIterations) {
          _messages.add(
            ChatMessage(
              id: _uuid.v4(),
              content:
                  'Maximum tool iteration limit ($_maxToolIterations) reached. '
                  'Please refine your request or ask for help.',
              role: ChatRole.assistant,
              timestamp: DateTime.now(),
            ),
          );
          notifyListeners();
          break;
        }

        // 2. Build tools list (may be suppressed on forced-final turn)
        final List<MCPTool> mcpTools = [];
        if (!_chatMode && !_forceNoToolCallsNextTurn) {
          mcpTools.addAll(
            _localTools
                .map((t) => t.toMCPTool())
                .where((t) => _enabledToolNames.contains(t.name)),
          );
          mcpTools.addAll(
            _mcpManager.availableTools.where(
              (t) => _enabledToolNames.contains(t.name),
            ),
          );
        }

        // If forced final turn, inject the hint as a user message
        // so the model switches to text-only synthesis.
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

        final response = await LLMService.generate(
          config: activeLlmConfig,
          messages: requestMsgs,
          tools: mcpTools,
          systemPrompt: systemPrompt,
        );

        if (response.toolCalls.isEmpty) {
          // No more tool calls: append assistant text and end loop
          if (response.text.isNotEmpty) {
            _messages.add(
              ChatMessage(
                id: _uuid.v4(),
                content: response.text,
                role: ChatRole.assistant,
                timestamp: DateTime.now(),
              ),
            );
          }
          continueLoop = false;
        } else {
          // LLM requested tool execution
          final call = response.toolCalls.first;

          // ── Duplicate tool call detection ─────────────────────────
          _toolIterationCount++;
          final toolSignature = '${call.name}|${jsonEncode(call.arguments)}';
          final hasDuplicateId = _executedToolCallIds.contains(call.id);
          final hasDuplicateSignature = _executedToolCallSignatures.contains(
            toolSignature,
          );

          if (hasDuplicateId || hasDuplicateSignature) {
            // Intercept repeated tool call — force the model to finalise.
            final previousResult = _messages
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

            final loopCorrectionText =
                'The tool "${call.name}" was already successfully executed. '
                'Previous result: $previousResult\n\n'
                'Do NOT call this tool again. Generate the final response using this result.';

            _messages.add(
              ChatMessage(
                id: call.id,
                content: loopCorrectionText,
                role: ChatRole.tool,
                type: MessageType.toolResponse,
                toolName: call.name,
                toolResult: MCPToolResult(
                  content: [MCPContent(type: 'text', text: loopCorrectionText)],
                  isError: false,
                ),
                timestamp: DateTime.now(),
              ),
            );
            notifyListeners();

            // Force the next LLM turn to have no tools — the model must
            // produce a text-only final answer.
            _forceNoToolCallsNextTurn = true;
            _forcedNoToolHintNextTurn =
                'The tool "${call.name}" has already been successfully executed with these parameters. '
                'Do NOT call this tool or any other tool again. Use the tool results in the history to write your final response now.';

            continueLoop = false;
            continue; // Exit the while loop; the forced turn will re-enter
          }

          // Record this tool call to prevent future duplicates
          _executedToolCallIds.add(call.id);
          _executedToolCallSignatures.add(toolSignature);

          // Append tool call to log UI
          _messages.add(
            ChatMessage(
              id: call.id,
              content:
                  'Calling tool: ${call.name} with arguments: ${jsonEncode(call.arguments)}',
              role: ChatRole.assistant,
              type: MessageType.toolCall,
              toolName: call.name,
              toolArguments: call.arguments,
              timestamp: DateTime.now(),
            ),
          );
          notifyListeners();

          // Execute tool
          MCPToolResult result;
          final localMatch = _localTools
              .where((t) => t.name == call.name)
              .toList();

          if (localMatch.isNotEmpty) {
            // Run Dart-native tool
            result = await localMatch.first.execute(call.arguments);
          } else {
            // Route to external HTTP MCP server
            result = await _mcpManager.callTool(call.name, call.arguments);
          }

          // Append tool response message
          final String responseContentText = result.content
              .where((c) => c.type == 'text')
              .map((c) => c.text ?? '')
              .join('\n');

          _messages.add(
            ChatMessage(
              id: call.id, // Align with tool call ID for LLM history reference
              content: responseContentText.isNotEmpty
                  ? responseContentText
                  : 'Executed.',
              role: ChatRole.tool,
              type: MessageType.toolResponse,
              toolName: call.name,
              toolResult: result,
              timestamp: DateTime.now(),
            ),
          );
          notifyListeners();

          if (_stopAfterToolCall) {
            continueLoop = false;
          }
        }
      }
    } catch (e) {
      _errorMessage = 'Execution error: $e';
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
