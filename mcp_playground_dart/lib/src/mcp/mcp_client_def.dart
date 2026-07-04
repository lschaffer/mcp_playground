import 'mcp_client.dart';
import '../models/models.dart';
import '../utils/change_notifier.dart';

/// Dynamic wrapper representing an MCP server definition in the multi-server manager.
class MCPClientDef {
  /// Unique identifier name of the server config.
  final String name;

  /// The associated [MCPClient] instance.
  final MCPClient client;

  /// Optional display/friendly name for rendering in UI tabs.
  final String? displayName;

  List<MCPTool> _cachedTools = [];

  /// Creates a new [MCPClientDef] instance.
  MCPClientDef({required this.name, required this.client, this.displayName});

  /// The user-facing label name of the server.
  String get label => displayName ?? name;

  /// The target connection endpoint URL.
  String get url => client.serverUrl;

  /// Connection status of the wrapped client.
  bool get isConnected => client.isConnected;

  /// List of capabilities/tools exposed by the server.
  List<MCPTool> get availableTools =>
      _cachedTools.isNotEmpty ? _cachedTools : client.availableTools;

  /// Update cached tools list in memory.
  set cachedTools(List<MCPTool> tools) {
    _cachedTools = tools;
  }

  /// Passes the tool call request to the wrapped client instance.
  Future<MCPToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    return client.callTool(toolName, arguments);
  }
}

/// Manager coordinating multiple MCP server connections.
class MultiMCPManager extends McpChangeNotifier {
  final List<MCPClientDef> _clients = [];

  /// Called when the state of a managed client changes.
  void Function()? onStateChanged;

  void registerClient(MCPClientDef clientDef) {
    _clients.add(clientDef);
    onStateChanged?.call();
    notifyListeners();
  }

  void unregisterClient(String name) {
    final idx = _clients.indexWhere((c) => c.name == name);
    if (idx != -1) {
      final clientDef = _clients.removeAt(idx);
      clientDef.client.dispose();
      onStateChanged?.call();
      notifyListeners();
    }
  }

  void clear() {
    for (final c in _clients) {
      c.client.dispose();
    }
    _clients.clear();
    onStateChanged?.call();
    notifyListeners();
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

  Future<MCPToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
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
    final prefixMatches = names
        .where((n) => n.startsWith(name) || name.startsWith(n))
        .toList();
    if (prefixMatches.length == 1) return prefixMatches.first;

    final substringMatches = names
        .where((n) => n.contains(name) || name.contains(n))
        .toList();
    if (substringMatches.length == 1) return substringMatches.first;

    return name;
  }

  /// Disposes all managed clients.
  @override
  void dispose() {
    for (final c in _clients) {
      c.client.dispose();
    }
    super.dispose();
  }
}
