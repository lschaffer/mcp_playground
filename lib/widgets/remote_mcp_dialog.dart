import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models.dart';
import '../playground_controller.dart';
import '../mcp_client.dart';

class RemoteMcpDialog extends StatefulWidget {
  final PlaygroundController controller;

  const RemoteMcpDialog({super.key, required this.controller});

  static Future<void> show(BuildContext context, PlaygroundController controller) {
    return showDialog(
      context: context,
      builder: (ctx) => RemoteMcpDialog(controller: controller),
    );
  }

  @override
  State<RemoteMcpDialog> createState() => _RemoteMcpDialogState();
}

class _RemoteMcpDialogState extends State<RemoteMcpDialog> {
  String _catalogSource = 'pulsemcp'; // 'pulsemcp' | 'smithery' | 'custom'
  
  // Custom Server Controllers
  final _customNameCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  final _customEndpointCtrl = TextEditingController(text: '/mcp');
  final _customApiKeyCtrl = TextEditingController();
  final _customApiPasswordCtrl = TextEditingController();

  // Search Catalog Controllers
  final _searchCtrl = TextEditingController();
  List<McpServerConfig> _searchResults = [];
  final Set<String> _selectedUrls = {};
  final Map<String, McpServerConfig> _catalogConfigs = {};
  bool _loading = false;
  String? _error;
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    // Pre-populate with currently enabled server URLs to show checked in list
    for (final server in widget.controller.servers) {
      _selectedUrls.add(server.url);
      _catalogConfigs[server.url] = server;
    }
    _runSearch();
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _customUrlCtrl.dispose();
    _customEndpointCtrl.dispose();
    _customApiKeyCtrl.dispose();
    _customApiPasswordCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_catalogSource == 'custom') return;

    setState(() {
      _loading = true;
      _error = null;
      _searchResults = [];
    });

    final query = _searchCtrl.text.trim();
    try {
      final List<McpServerConfig> results;
      if (_catalogSource == 'pulsemcp') {
        results = await _searchPulseMcp(query);
      } else {
        results = await _searchSmithery(query);
      }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        for (final r in results) {
          if (!_catalogConfigs.containsKey(r.url)) {
            _catalogConfigs[r.url] = r;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to fetch catalog: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<List<McpServerConfig>> _searchPulseMcp(String query) async {
    final Map<String, String> params = {'limit': '100'};
    if (query.isNotEmpty) params['q'] = query;

    final uri = Uri.parse('https://registry.modelcontextprotocol.io/v0/servers')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'mcp-playground-flutter/1.0',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Registry returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return _parsePulseMcpResponse(decoded);
  }

  Future<List<McpServerConfig>> _searchSmithery(String query) async {
    final Map<String, String> params = {'pageSize': '50'};
    if (query.isNotEmpty) {
      params['q'] = query;
    } else {
      params['q'] = 'remote';
    }

    final uri = Uri.parse('https://registry.smithery.ai/servers')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'mcp-playground-flutter/1.0',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Smithery returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return _parseSmitheryResponse(decoded);
  }

  List<McpServerConfig> _parsePulseMcpResponse(dynamic decoded) {
    final List<dynamic> serversList;
    if (decoded is Map<String, dynamic>) {
      final raw = decoded['servers'] ?? decoded['items'] ?? decoded['results'] ?? decoded['data'];
      serversList = raw is List ? raw : <dynamic>[];
    } else if (decoded is List) {
      serversList = decoded;
    } else {
      return const [];
    }

    final result = <McpServerConfig>[];
    final seen = <String>{};

    for (final entry in serversList.whereType<Map<String, dynamic>>()) {
      final item = (entry['server'] is Map<String, dynamic>) ? entry['server'] as Map<String, dynamic> : entry;
      String serverUrl = '';

      final remotes = item['remotes'];
      if (remotes is List) {
        for (final r in remotes.whereType<Map<String, dynamic>>()) {
          final u = (r['url'] ?? '').toString().trim();
          if (u.startsWith('https://') || u.startsWith('http://')) {
            serverUrl = u;
            break;
          }
        }
      }

      if (serverUrl.isEmpty) {
        final connections = item['connections'];
        if (connections is List) {
          for (final conn in connections.whereType<Map<String, dynamic>>()) {
            final u = (conn['url'] ?? '').toString().trim();
            if (u.startsWith('https://') || u.startsWith('http://')) {
              serverUrl = u;
              break;
            }
          }
        }
      }

      if (serverUrl.isEmpty) {
        serverUrl = (item['serverUrl'] ?? item['server_url'] ?? item['url'] ?? '').toString().trim();
      }

      if (serverUrl.isEmpty || (!serverUrl.startsWith('https://') && !serverUrl.startsWith('http://'))) continue;

      String baseUrl = serverUrl;
      String endpoint = '/mcp';
      for (final suffix in ['/mcp', '/sse', '/v1/mcp']) {
        if (serverUrl.toLowerCase().endsWith(suffix)) {
          baseUrl = serverUrl.substring(0, serverUrl.length - suffix.length);
          endpoint = suffix;
          break;
        }
      }

      if (!seen.add(baseUrl)) continue;

      final name = (item['title'] ?? item['name'] ?? '').toString().trim();
      final cleanName = name.isNotEmpty ? name : baseUrl;

      result.add(McpServerConfig(
        id: baseUrl,
        name: cleanName,
        url: baseUrl,
        mcpEndpoint: endpoint,
      ));
    }
    return result;
  }

  List<McpServerConfig> _parseSmitheryResponse(dynamic decoded) {
    final List<dynamic> serversList = decoded is Map<String, dynamic> ? (decoded['servers'] as List<dynamic>?) ?? [] : <dynamic>[];
    final result = <McpServerConfig>[];
    final seen = <String>{};

    for (final item in serversList.whereType<Map<String, dynamic>>()) {
      final remote = item['remote'] as bool? ?? false;
      final isDeployed = item['isDeployed'] as bool? ?? false;
      if (!remote || !isDeployed) continue;

      final qualifiedName = (item['qualifiedName'] as String? ?? '').trim();
      if (qualifiedName.isEmpty) continue;

      final name = (item['displayName'] as String? ?? qualifiedName).trim();
      String resolvedUrl = 'https://server.smithery.ai/$qualifiedName/mcp';

      String baseUrl = resolvedUrl;
      String endpoint = '/mcp';
      for (final suffix in ['/mcp', '/sse', '/v1/mcp']) {
        if (resolvedUrl.toLowerCase().endsWith(suffix)) {
          baseUrl = resolvedUrl.substring(0, resolvedUrl.length - suffix.length);
          endpoint = suffix;
          break;
        }
      }

      if (!seen.add(baseUrl)) continue;

      result.add(McpServerConfig(
        id: baseUrl,
        name: name,
        url: baseUrl,
        mcpEndpoint: endpoint,
      ));
    }
    return result;
  }

  Future<void> _testConnection({
    required String url,
    required String endpoint,
    String? apiKey,
    String? apiPassword,
  }) async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    try {
      final tempClient = MCPClient(
        url,
        mcpEndpoint: endpoint,
        bearerToken: apiKey,
        apiPassword: apiPassword,
      );

      // Connect and query tools
      await tempClient.connect().timeout(const Duration(seconds: 12));
      final tools = tempClient.availableTools;
      tempClient.dispose();

      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testMessage = 'Success! Server responded. Discovered ${tools.length} tools:\n'
            '${tools.take(5).map((t) => '- ${t.name}').join('\n')}'
            '${tools.length > 5 ? '\n... and ${tools.length - 5} more' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testMessage = 'Connection failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  void _addCustomServer() {
    final name = _customNameCtrl.text.trim();
    final url = _customUrlCtrl.text.trim();
    final endpoint = _customEndpointCtrl.text.trim();
    final apiKey = _customApiKeyCtrl.text.trim();
    final apiPassword = _customApiPasswordCtrl.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and URL are required.')),
      );
      return;
    }

    final newServer = McpServerConfig(
      id: url,
      name: name,
      url: url,
      mcpEndpoint: endpoint.isEmpty ? '/mcp' : endpoint,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
      apiPassword: apiPassword.isNotEmpty ? apiPassword : null,
    );

    widget.controller.addServer(newServer);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server "$name" registered successfully.')),
    );
  }

  void _saveSelectedCatalogServers() {
    for (final u in _selectedUrls) {
      final existing = widget.controller.servers.any((s) => s.url == u);
      if (!existing) {
        final config = _catalogConfigs[u];
        if (config != null) {
          widget.controller.addServer(config);
        }
      }
    }
    // Also remove unchecked servers
    for (final server in widget.controller.servers) {
      if (!_selectedUrls.contains(server.url)) {
        widget.controller.removeServer(server.id);
      }
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MCP Servers configuration updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          children: [
            AppBar(
              title: const Text('Add / Manage MCP Servers', style: TextStyle(fontWeight: FontWeight.bold)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pulsemcp', label: Text('PulseMCP Registry'), icon: Icon(Icons.hub_outlined)),
                  ButtonSegment(value: 'smithery', label: Text('Smithery Registry'), icon: Icon(Icons.cloud_outlined)),
                  ButtonSegment(value: 'custom', label: Text('Custom Server'), icon: Icon(Icons.link)),
                ],
                selected: {_catalogSource},
                onSelectionChanged: (s) {
                  setState(() {
                    _catalogSource = s.first;
                    _testMessage = null;
                  });
                  _runSearch();
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _catalogSource == 'custom'
                  ? _buildCustomServerForm(theme)
                  : _buildCatalogList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomServerForm(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Configure Custom MCP Server',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Text(
            'Provide settings to establish a stateful JSON-RPC connection over HTTP/SSE.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _customNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Server Name',
              hintText: 'e.g. SQLite Explorer',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          TextFormField(
            controller: _customUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Connection URL (Base)',
              hintText: 'e.g. http://localhost:3000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          TextFormField(
            controller: _customEndpointCtrl,
            decoration: const InputDecoration(
              labelText: 'MCP Endpoint Path',
              hintText: '/mcp',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.route_outlined),
            ),
          ),
          TextFormField(
            controller: _customApiKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'Auth Token / API Key (Optional)',
              hintText: 'Bearer token',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key_outlined),
            ),
            obscureText: true,
          ),
          TextFormField(
            controller: _customApiPasswordCtrl,
            decoration: const InputDecoration(
              labelText: 'API Password (Optional)',
              hintText: 'Basic auth password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.password_outlined),
            ),
            obscureText: true,
          ),
          if (_testMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testSuccess ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _testSuccess ? Colors.green : Colors.red),
              ),
              child: SelectableText(
                _testMessage!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: _testSuccess ? Colors.green[800] : Colors.red[800],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing
                      ? null
                      : () => _testConnection(
                            url: _customUrlCtrl.text.trim(),
                            endpoint: _customEndpointCtrl.text.trim(),
                            apiKey: _customApiKeyCtrl.text.trim(),
                            apiPassword: _customApiPasswordCtrl.text.trim(),
                          ),
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test Connection'),
                ),
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addCustomServer,
                  icon: const Icon(Icons.add),
                  label: const Text('Register Server'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogList(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search catalog servers...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _runSearch,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _searchResults.isEmpty && !_loading
              ? const Center(
                  child: Text(
                    'No servers found matching query.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (ctx, idx) {
                    final s = _searchResults[idx];
                    final isChecked = _selectedUrls.contains(s.url);
                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedUrls.add(s.url);
                          } else {
                            _selectedUrls.remove(s.url);
                          }
                        });
                      },
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(
                        'Base: ${s.url}\nEndpoint: ${s.mcpEndpoint}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      isThreeLine: true,
                      secondary: Tooltip(
                        message: 'Copy URL',
                        child: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: s.url + s.mcpEndpoint));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Endpoint copied to clipboard'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveSelectedCatalogServers,
              icon: const Icon(Icons.save),
              label: const Text('Use Selected Servers'),
            ),
          ),
        ),
      ],
    );
  }
}
