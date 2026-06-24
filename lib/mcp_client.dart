import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';

/// Callback signature for logging output.
typedef McpLogCallback = void Function(String message, {bool isError});

/// Core client connection class to communicate with MCP servers over HTTP/HTTPS.
class MCPClient extends ChangeNotifier {
  final String serverUrl;
  final String mcpEndpoint;
  final String? bearerToken;
  final String? apiPassword;
  final McpLogCallback? logCallback;

  String? _effectiveBearerToken;
  final http.Client _httpClient = http.Client();
  final StreamController<MCPMessage> _messageController = StreamController<MCPMessage>.broadcast();
  bool _isConnected = false;
  final Uuid _uuid = const Uuid();

  List<MCPTool> _availableTools = [];
  List<MCPResource> _availableResources = [];

  // Reconnection management
  Timer? _healthCheckTimer;
  bool _isReconnecting = false;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 5;
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const Duration _reconnectionDelay = Duration(seconds: 5);

  /// Session ID for stateful Streamable HTTP transport (MCP 2025).
  String? _sessionId;

  MCPClient(
    this.serverUrl, {
    this.mcpEndpoint = '/mcp',
    this.bearerToken,
    this.apiPassword,
    this.logCallback,
  }) : _effectiveBearerToken = bearerToken;

  void _log(String message, {bool isError = false}) {
    if (logCallback != null) {
      logCallback!(message, isError: isError);
    } else {
      debugPrint('[MCPClient] $message');
    }
  }

  String get _normalizedServerUrl {
    final trimmed = serverUrl.trim();
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  Uri _rpcUri() {
    final uri = Uri.parse(_normalizedServerUrl);
    final normalizedEndpoint = mcpEndpoint.startsWith('/') ? mcpEndpoint : '/$mcpEndpoint';
    final path = uri.path;
    if (path.toLowerCase().endsWith(normalizedEndpoint.toLowerCase())) return uri;
    final separator = path.endsWith('/') ? '' : '/';
    return uri.replace(path: '$path$separator${normalizedEndpoint.startsWith('/') ? normalizedEndpoint.substring(1) : normalizedEndpoint}');
  }

  Uri _healthUri() {
    final uri = Uri.parse(_normalizedServerUrl);
    final normalizedEndpoint = mcpEndpoint.startsWith('/') ? mcpEndpoint : '/$mcpEndpoint';
    final path = uri.path;
    if (path.toLowerCase().endsWith(normalizedEndpoint.toLowerCase())) {
      return uri.replace(path: path.replaceFirst(RegExp('${RegExp.escape(normalizedEndpoint)}\$', caseSensitive: false), '/health'));
    }
    final separator = path.endsWith('/') ? '' : '/';
    return uri.replace(path: '$path${separator}health');
  }

  Map<String, String> _getHeaders({Map<String, String>? additionalHeaders}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };

    if (apiPassword != null && apiPassword!.isNotEmpty) {
      final username = _effectiveBearerToken ?? '';
      final bytes = utf8.encode('$username:$apiPassword');
      final base64Str = base64.encode(bytes);
      headers['Authorization'] = 'Basic $base64Str';
    } else if (_effectiveBearerToken != null && _effectiveBearerToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_effectiveBearerToken';
    }

    if (_sessionId != null) {
      headers['Mcp-Session-Id'] = _sessionId!;
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  static String _extractFirstSseData(String sseBody) {
    for (final line in sseBody.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('data: ') && trimmed.length > 6) {
        final json = trimmed.substring(6).trim();
        if (json.isNotEmpty && json != '[DONE]') return json;
      }
    }
    return sseBody;
  }

  Stream<MCPMessage> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;
  List<MCPTool> get availableTools => List.unmodifiable(_availableTools);
  List<MCPResource> get availableResources => List.unmodifiable(_availableResources);

  Future<void> connect() async {
    try {
      await _testConnection();
      _isConnected = true;
      _reconnectionAttempts = 0;
      notifyListeners();

      await _initialize();
      await _loadCapabilities();
      _startHealthCheck();

      _log('Connected successfully via HTTP');
    } catch (e) {
      _log('Failed to connect: $e', isError: true);
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _testConnection() async {
    final isMcpEndpoint = Uri.parse(_normalizedServerUrl).path.toLowerCase().endsWith('/mcp');

    if (isMcpEndpoint) {
      final probeBody = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'initialize',
        'id': 'probe',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'Flutter MCP Client', 'version': '1.0.0'},
        },
      });
      try {
        var response = await _httpClient.post(_rpcUri(), headers: _getHeaders(), body: probeBody).timeout(const Duration(seconds: 20));
        if (response.statusCode == 401 && _effectiveBearerToken != null) {
          _log('Got 401 on probe, retrying without auth headers');
          _effectiveBearerToken = null;
          response = await _httpClient.post(_rpcUri(), headers: _getHeaders(), body: probeBody).timeout(const Duration(seconds: 20));
        }
        if (response.statusCode != 200) {
          throw Exception('MCP probe failed: HTTP ${response.statusCode}');
        }
      } catch (e) {
        throw Exception('Connection test failed: $e');
      }
      return;
    }

    try {
      final response = await _httpClient.get(_healthUri(), headers: _getHeaders()).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (e) {
      try {
        final response = await _httpClient
            .post(
              _rpcUri(),
              headers: _getHeaders(),
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'initialize',
                'id': 'probe',
                'params': {
                  'protocolVersion': '2024-11-05',
                  'capabilities': {},
                  'clientInfo': {'name': 'Flutter MCP Client', 'version': '1.0.0'},
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          throw Exception('MCP endpoint test failed: ${response.statusCode}');
        }
      } catch (testError) {
        throw Exception('Connection test failed: $testError');
      }
    }
  }

  Future<void> _initialize() async {
    final initBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': _uuid.v4(),
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'roots': {'listChanged': true},
          'sampling': {},
          'tools': {'listChanged': true},
          'resources': {'listChanged': true},
        },
        'clientInfo': {'name': 'Flutter MCP Client', 'version': '1.0.0'},
      },
    });

    final response = await _httpClient.post(_rpcUri(), headers: _getHeaders(), body: initBody).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Initialize failed: HTTP ${response.statusCode}');
    }

    final sessionId = response.headers['mcp-session-id'];
    if (sessionId != null && sessionId.isNotEmpty) {
      _sessionId = sessionId;
      _log('Session established: $sessionId');
    }

    await _sendNotification('notifications/initialized');
  }

  Future<void> _loadCapabilities() async {
    final toolsResponse = await _sendRequest(MCPRequest(id: _uuid.v4(), method: 'tools/list'));
    if (toolsResponse['tools'] != null) {
      _availableTools = (toolsResponse['tools'] as List).map((tool) => MCPTool.fromJson(tool)).toList();
    }

    try {
      final resourcesResponse = await _sendRequest(MCPRequest(id: _uuid.v4(), method: 'resources/list'));
      if (resourcesResponse['resources'] != null) {
        _availableResources = (resourcesResponse['resources'] as List).map((resource) => MCPResource.fromJson(resource)).toList();
      }
    } catch (e) {
      _log('Resources not supported by server: $e');
    }

    _log('Loaded ${_availableTools.length} tools and ${_availableResources.length} resources');
    notifyListeners();
  }

  Future<dynamic> _sendRequest(MCPRequest request) async {
    if (!_isConnected) {
      throw Exception('Not connected to MCP server');
    }

    try {
      final response = await _httpClient
          .post(_rpcUri(), headers: _getHeaders(), body: jsonEncode(request.toJson()))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final contentType = response.headers['content-type'] ?? '';
      final rawBody = contentType.contains('text/event-stream') ? _extractFirstSseData(response.body) : response.body;
      final responseData = jsonDecode(rawBody) as Map<String, dynamic>;

      if (responseData.containsKey('error')) {
        final error = responseData['error'];
        throw Exception('Server error: ${error['message'] ?? error.toString()}');
      }

      return responseData['result'];
    } catch (e) {
      if (e.toString().contains('Connection') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('Failed host lookup')) {
        if (_isConnected) {
          _isConnected = false;
          notifyListeners();
          _attemptReconnection();
        }
      }
      throw Exception('MCP request failed: $e');
    }
  }

  Future<void> _sendNotification(String method, [Map<String, dynamic>? params]) async {
    if (!_isConnected) return;
    try {
      final notification = <String, dynamic>{'jsonrpc': '2.0', 'method': method, 'params': params}
        ..removeWhere((key, value) => value == null);

      await _httpClient.post(_rpcUri(), headers: _getHeaders(), body: jsonEncode(notification)).timeout(const Duration(seconds: 10));
    } catch (e) {
      _log('Failed to send notification: $e', isError: true);
    }
  }

  Future<MCPToolResult> callTool(String name, Map<String, dynamic> arguments) async {
    final request = MCPRequest(id: _uuid.v4(), method: 'tools/call', params: {'name': name, 'arguments': arguments});

    final response = await _sendRequest(request);

    if (response is Map<String, dynamic> && response['content'] is List) {
      return MCPToolResult.fromJson(response);
    }

    if (response != null) {
      final content = <Map<String, dynamic>>[];
      if (response is String) {
        content.add({'type': 'text', 'text': response});
      } else {
        content.add({'type': 'text', 'text': jsonEncode(response)});
      }
      return MCPToolResult(content: content.map((item) => MCPContent.fromJson(item)).toList(), isError: false);
    }

    return const MCPToolResult(
      content: [MCPContent(type: 'text', text: '{"success": false, "error": "No response from server"}')],
      isError: true,
    );
  }

  Future<String> readResource(String uri) async {
    final request = MCPRequest(id: _uuid.v4(), method: 'resources/read', params: {'uri': uri});
    final response = await _sendRequest(request);
    final contents = response['contents'] as List?;
    if (contents != null && contents.isNotEmpty) {
      return contents.first['text'] ?? '';
    }
    return '';
  }

  void _startHealthCheck() {
    _stopHealthCheck();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _performHealthCheck() async {
    if (!_isConnected) return;
    try {
      await _testConnection();
    } catch (e) {
      _log('Health check failed, attempting reconnection: $e');
      _isConnected = false;
      notifyListeners();
      _attemptReconnection();
    }
  }

  Future<void> _attemptReconnection() async {
    if (_isReconnecting || _reconnectionAttempts >= _maxReconnectionAttempts) return;

    _isReconnecting = true;
    _reconnectionAttempts++;

    final backoffDelay = Duration(seconds: (_reconnectionDelay.inSeconds * _reconnectionAttempts).clamp(5, 60));
    _log('Attempting reconnection $_reconnectionAttempts/$_maxReconnectionAttempts in ${backoffDelay.inSeconds}s...');
    await Future.delayed(backoffDelay);

    try {
      await connect();
      _log('Reconnection successful after $_reconnectionAttempts attempts');
    } catch (e) {
      _log('Reconnection attempt $_reconnectionAttempts failed: $e', isError: true);
    } finally {
      _isReconnecting = false;
    }
  }

  Future<void> reconnect() async {
    _reconnectionAttempts = 0;
    _isReconnecting = false;
    await connect();
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _stopHealthCheck();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _httpClient.close();
    super.dispose();
  }
}

/// Dynamic wrapper representing an MCP server definition in the multi-server manager.
class MCPClientDef {
  final String name;
  final MCPClient client;
  final String? displayName;

  MCPClientDef({
    required this.name,
    required this.client,
    this.displayName,
  });

  String get label => displayName ?? name;
  String get url => client.serverUrl;
  bool get isConnected => client.isConnected;
  List<MCPTool> get availableTools => client.availableTools;

  Future<MCPToolResult> callTool(String toolName, Map<String, dynamic> arguments) {
    return client.callTool(toolName, arguments);
  }
}

/// Manager coordinating multiple MCP server connections.
class MultiMCPManager extends ChangeNotifier {
  final List<MCPClientDef> _clients = [];


  void registerClient(MCPClientDef clientDef) {
    _clients.add(clientDef);
    clientDef.client.addListener(notifyListeners);
    notifyListeners();
  }

  void unregisterClient(String name) {
    final idx = _clients.indexWhere((c) => c.name == name);
    if (idx != -1) {
      final clientDef = _clients.removeAt(idx);
      clientDef.client.removeListener(notifyListeners);
      clientDef.client.dispose();
      notifyListeners();
    }
  }

  List<MCPClientDef> get clients => List.unmodifiable(_clients);
  bool get isConnected => _clients.any((c) => c.isConnected);

  List<MCPTool> get availableTools {
    final tools = <MCPTool>[];
    final seen = <String>{};

    for (final clientDef in _clients) {
      if (!clientDef.isConnected) continue;
      for (final tool in clientDef.availableTools) {
        if (seen.add(tool.name)) {
          tools.add(tool);
        }
      }
    }
    return tools;
  }

  Future<void> initializeAll() async {
    await Future.wait(
      _clients.map((c) => c.client.connect().catchError((e) => null)),
    );
  }

  Future<void> disconnectAll() async {
    await Future.wait(_clients.map((c) => c.client.disconnect()));
  }

  Future<MCPToolResult> callTool(String toolName, Map<String, dynamic> arguments) async {
    final resolvedName = _resolveToolName(toolName);
    for (final clientDef in _clients) {
      if (!clientDef.isConnected) continue;
      if (clientDef.availableTools.any((t) => t.name == resolvedName)) {
        return await clientDef.callTool(resolvedName, arguments);
      }
    }
    throw Exception('Tool "$toolName" not found on any connected MCP server');
  }

  String _resolveToolName(String name) {
    final all = availableTools;
    if (all.any((t) => t.name == name)) return name;

    final names = all.map((t) => t.name).toList();
    final prefixMatches = names.where((n) => n.startsWith(name) || name.startsWith(n)).toList();
    if (prefixMatches.length == 1) return prefixMatches.first;

    final substringMatches = names.where((n) => n.contains(name) || name.contains(n)).toList();
    if (substringMatches.length == 1) return substringMatches.first;

    return name;
  }

  @override
  void dispose() {
    for (final c in _clients) {
      c.client.removeListener(notifyListeners);
      c.client.dispose();
    }
    super.dispose();
  }
}
