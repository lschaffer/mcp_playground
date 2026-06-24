import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'mcp_client.dart';
import 'llm_service.dart';
import 'local_tools.dart';

abstract class McpPlaygroundStorageDelegate {
  Future<void> saveLlmConfig(LlmConfig config);
  Future<LlmConfig?> loadLlmConfig();
  Future<void> saveServers(List<McpServerConfig> servers);
  Future<List<McpServerConfig>> loadServers();
}

class SharedPreferencesStorageDelegate implements McpPlaygroundStorageDelegate {
  static const _kLlm = 'mcp_playground_llm_config';
  static const _kServers = 'mcp_playground_servers';

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
      return list.map((item) => McpServerConfig.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

class PlaygroundController extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  LlmConfig _llmConfig;
  final List<McpServerConfig> _servers = [];
  final List<McpLocalTool> _localTools = [];
  final McpPlaygroundStorageDelegate _storage;

  bool _loading = false;
  bool _generating = false;
  String? _errorMessage;

  final MultiMCPManager _mcpManager = MultiMCPManager();
  final Uuid _uuid = const Uuid();

  PlaygroundController({
    LlmConfig? initialLlmConfig,
    List<McpServerConfig>? initialServers,
    List<McpLocalTool>? customLocalTools,
    McpPlaygroundStorageDelegate? storageDelegate,
  })  : _llmConfig = initialLlmConfig ??
            const LlmConfig(
              provider: LlmProvider.none,
              model: '',
              apiKey: '',
            ),
        _storage = storageDelegate ?? SharedPreferencesStorageDelegate() {
    if (initialServers != null) {
      _servers.addAll(initialServers);
    }
    // Register built-in local tools
    _localTools.addAll([
      WeatherLocalTool(),
      SshLocalTool(),
      ChartLocalTool(),
    ]);
    if (customLocalTools != null) {
      _localTools.addAll(customLocalTools);
    }
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
      final old = _servers[idx];
      _servers[idx] = McpServerConfig(
        id: old.id,
        name: old.name,
        url: old.url,
        apiKey: old.apiKey,
        apiPassword: old.apiPassword,
        enabled: enabled,
      );
      await _storage.saveServers(_servers);
      await _syncMcpServers();
      notifyListeners();
    }
  }

  Future<void> _syncMcpServers() async {
    await _mcpManager.disconnectAll();
    final activeServers = _servers.where((s) => s.enabled && s.url.trim().isNotEmpty).toList();

    // Re-register external servers
    for (final s in activeServers) {
      final client = MCPClient(
        s.url,
        bearerToken: s.apiKey,
        logCallback: (msg, {bool isError = false}) => debugPrint('[Playground MCP Log: ${s.name}] $msg'),
      );
      _mcpManager.registerClient(
        MCPClientDef(name: s.id, client: client, displayName: s.name),
      );
    }

    // Connect to external servers in parallel
    await _mcpManager.initializeAll();
  }

  void clearChat() {
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  /// Sends a message and triggers the agentic tool call loop.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _generating) return;

    _errorMessage = null;
    _generating = true;
    
    // 1. Add User Message
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      content: text,
      role: ChatRole.user,
      timestamp: DateTime.now(),
    ));
    notifyListeners();

    try {
      // 2. Build full available tools list (local + active external)
      final List<MCPTool> mcpTools = [];
      // Add local tools
      mcpTools.addAll(_localTools.map((t) => t.toMCPTool()));
      // Add connected external tools
      mcpTools.addAll(_mcpManager.availableTools);

      int steps = 0;
      const maxSteps = 5;
      bool continueLoop = true;

      // 3. Execution System Prompt
      final systemPrompt =
          'You are an agent equipped with tools. Focus on the user\'s task. '
          'Use the tool schemas precisely. If you decide to call a tool, generate the tool call block. '
          'Present final answers directly. Present code and logs inside clean formatting.';

      while (continueLoop && steps < maxSteps) {
        steps++;
        
        final response = await LLMService.generate(
          config: _llmConfig,
          messages: _messages,
          tools: mcpTools,
          systemPrompt: systemPrompt,
        );

        if (response.toolCalls.isEmpty) {
          // No more tool calls: append assistant text and end loop
          if (response.text.isNotEmpty) {
            _messages.add(ChatMessage(
              id: _uuid.v4(),
              content: response.text,
              role: ChatRole.assistant,
              timestamp: DateTime.now(),
            ));
          }
          continueLoop = false;
        } else {
          // LLM requested tool execution
          final call = response.toolCalls.first;

          // Append tool call to log UI
          final callMsgId = _uuid.v4();
          _messages.add(ChatMessage(
            id: callMsgId,
            content: 'Calling tool: ${call.name} with arguments: ${jsonEncode(call.arguments)}',
            role: ChatRole.assistant,
            type: MessageType.toolCall,
            toolName: call.name,
            toolArguments: call.arguments,
            timestamp: DateTime.now(),
          ));
          notifyListeners();

          // Execute tool
          MCPToolResult result;
          final localMatch = _localTools.where((t) => t.name == call.name).toList();

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

          _messages.add(ChatMessage(
            id: call.id, // Align with tool call ID for LLM history reference
            content: responseContentText.isNotEmpty ? responseContentText : 'Executed.',
            role: ChatRole.tool,
            type: result.content.any((c) => c.type == 'chart') ? MessageType.text : MessageType.toolResponse,
            toolName: call.name,
            toolResult: result,
            timestamp: DateTime.now(),
          ));
          notifyListeners();
        }
      }
    } catch (e) {
      _errorMessage = 'Execution error: $e';
      _messages.add(ChatMessage(
        id: _uuid.v4(),
        content: 'Error: $e',
        role: ChatRole.system,
        type: MessageType.log,
        timestamp: DateTime.now(),
      ));
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _mcpManager.disconnectAll();
    _mcpManager.dispose();
    super.dispose();
  }
}
