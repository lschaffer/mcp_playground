import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../playground_controller.dart';
import '../mcp_client.dart';

class RemoteMcpDialog extends StatefulWidget {
  final PlaygroundController controller;

  const RemoteMcpDialog({super.key, required this.controller});

  static Future<void> show(
    BuildContext context,
    PlaygroundController controller,
  ) {
    return showDialog(
      context: context,
      builder: (ctx) => RemoteMcpDialog(controller: controller),
    );
  }

  @override
  State<RemoteMcpDialog> createState() => _RemoteMcpDialogState();
}

class _RemoteMcpDialogState extends State<RemoteMcpDialog> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String _catalogSource = 'pulsemcp'; // 'pulsemcp' | 'custom'

  // Custom Server Controllers
  final _customNameCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  final _customEndpointCtrl = TextEditingController(text: '/mcp');
  final _customApiKeyCtrl = TextEditingController();
  final _customApiPasswordCtrl = TextEditingController();

  // Search Catalog Controllers
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  List<McpServerConfig> _searchResults = [];
  final Set<String> _selectedUrls = {};
  final Map<String, McpServerConfig> _catalogConfigs = {};
  bool _loading = false;
  String? _error;
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;

  // Pagination fields
  String? _nextCursor;
  bool _loadingMore = false;

  // Per-server metadata from catalog
  final Map<String, String> _serverDescriptions = {};
  final Map<String, String> _serverHomepages = {};
  final Map<String, bool> _serverIsOnline = {};

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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_catalogSource == 'custom') return;

    setState(() {
      _loading = true;
      _error = null;
      _searchResults = [];
      _nextCursor = null;
    });

    final query = _searchCtrl.text.trim();
    try {
      final responseMap = await _fetchPulseMcpPage(query: query, cursor: null);
      final results = responseMap['servers'] as List<McpServerConfig>;
      final nextCursor = responseMap['nextCursor'] as String?;

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _nextCursor = nextCursor;
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

  Future<Map<String, dynamic>> _fetchPulseMcpPage({
    required String query,
    String? cursor,
  }) async {
    final Map<String, String> params = {'limit': '40'};
    if (query.isNotEmpty) params['search'] = query;
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;

    final uri = Uri.parse(
      'https://registry.modelcontextprotocol.io/v0/servers',
    ).replace(queryParameters: params);
    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            if (!kIsWeb) 'User-Agent': 'mcp-playground-flutter/1.0',
          },
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Registry returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final List<McpServerConfig> servers = _parsePulseMcpResponse(decoded);

    String? nextCursor;
    if (decoded is Map<String, dynamic>) {
      final meta = decoded['metadata'];
      if (meta is Map<String, dynamic>) {
        nextCursor = meta['nextCursor']?.toString();
      }
    }

    return {
      'servers': servers,
      'nextCursor': nextCursor,
    };
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _nextCursor == null || _nextCursor!.isEmpty) return;

    setState(() {
      _loadingMore = true;
    });

    final query = _searchCtrl.text.trim();
    try {
      final responseMap = await _fetchPulseMcpPage(query: query, cursor: _nextCursor);
      final results = responseMap['servers'] as List<McpServerConfig>;
      final nextCursor = responseMap['nextCursor'] as String?;

      if (!mounted) return;
      setState(() {
        _searchResults.addAll(results);
        _nextCursor = nextCursor;
        for (final r in results) {
          if (!_catalogConfigs.containsKey(r.url)) {
            _catalogConfigs[r.url] = r;
          }
        }
      });
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to load more: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  List<McpServerConfig> _parsePulseMcpResponse(dynamic decoded) {
    final List<dynamic> serversList;
    if (decoded is Map<String, dynamic>) {
      final raw =
          decoded['servers'] ??
          decoded['items'] ??
          decoded['results'] ??
          decoded['data'];
      serversList = raw is List ? raw : <dynamic>[];
    } else if (decoded is List) {
      serversList = decoded;
    } else {
      return const [];
    }

    final result = <McpServerConfig>[];
    final seen = <String>{};

    for (final entry in serversList.whereType<Map<String, dynamic>>()) {
      final item = (entry['server'] is Map<String, dynamic>)
          ? entry['server'] as Map<String, dynamic>
          : entry;
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
        final flatUrl = (item['serverUrl'] ?? item['server_url'] ?? item['url'] ?? '')
            .toString()
            .trim();
        final lower = flatUrl.toLowerCase();
        final isWebpage = lower.contains('github.com') ||
            lower.contains('npmjs.com') ||
            lower.contains('gitlab.com') ||
            (lower.contains('smithery.ai') && !lower.contains('server.smithery.ai')) ||
            lower.endsWith('.md') ||
            lower.contains('/tree/') ||
            lower.contains('/blob/');
        if (!isWebpage) {
          serverUrl = flatUrl;
        }
      }

      if (serverUrl.isEmpty ||
          (!serverUrl.startsWith('https://') &&
              !serverUrl.startsWith('http://'))) {
        continue;
      }

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

      final description = (item['description'] ?? '').toString().trim();
      if (description.isNotEmpty) {
        _serverDescriptions[baseUrl] = description;
      }

      // Homepage: websiteUrl, repository.url, etc.
      String homepage = '';
      final repo = item['repository'];
      if (repo is Map<String, dynamic>) {
        homepage = (repo['url'] ?? '').toString().trim();
      }
      if (homepage.isEmpty) {
        homepage = (item['websiteUrl'] ??
                item['source_code_url'] ??
                item['homepage'] ??
                item['repoUrl'] ??
                item['repo_url'] ??
                '')
            .toString()
            .trim();
      }
      if (homepage.isNotEmpty) {
        _serverHomepages[baseUrl] = homepage;
      }

      // Online status: defaults to true for registry listing
      final rawOnline =
          item['is_online'] ??
          item['isOnline'] ??
          item['online'] ??
          item['reachable'];
      bool isOnline = true;
      if (rawOnline != null) {
        if (rawOnline is bool) {
          isOnline = rawOnline;
        } else if (rawOnline is String) {
          final v = rawOnline.toLowerCase().trim();
          isOnline = (v == 'true' ||
              v == '1' ||
              v == 'online' ||
              v == 'up' ||
              v == 'healthy' ||
              v == 'ok');
        }
      }
      _serverIsOnline[baseUrl] = isOnline;

      result.add(
        McpServerConfig(
          id: baseUrl,
          name: cleanName,
          url: baseUrl,
          mcpEndpoint: endpoint,
          isOnline: isOnline,
          description: description.isNotEmpty ? description : null,
        ),
      );
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
        _testMessage =
            'Success! Server responded. Discovered ${tools.length} tools:\n'
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

    final parentMessenger = ScaffoldMessenger.of(context);
    widget.controller.addServer(newServer);
    Navigator.of(context).pop();
    parentMessenger.showSnackBar(
      SnackBar(content: Text('Server "$name" registered successfully.')),
    );
  }

  void _saveSelectedCatalogServers() {
    for (final u in _selectedUrls) {
      final existingIndex = widget.controller.servers.indexWhere((s) => s.url == u);
      if (existingIndex == -1) {
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
    final parentMessenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    parentMessenger.showSnackBar(
      const SnackBar(content: Text('MCP Servers configuration updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Add / Manage MCP Servers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'pulsemcp',
                        label: Text('PulseMCP'),
                        icon: Icon(Icons.hub_outlined),
                      ),
                      ButtonSegment(
                        value: 'custom',
                        label: Text('Custom'),
                        icon: Icon(Icons.link),
                      ),
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth * 0.8,
          minWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Add / Manage MCP Servers',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'pulsemcp',
                        label: Text('PulseMCP Registry'),
                        icon: Icon(Icons.hub_outlined),
                      ),
                      ButtonSegment(
                        value: 'custom',
                        label: Text('Custom Server'),
                        icon: Icon(Icons.link),
                      ),
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
                color: _testSuccess
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testSuccess ? Colors.green : Colors.red,
                ),
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.amber[700], size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Showing live remote-hosted servers from the Official MCP Registry (registry.modelcontextprotocol.io). Some require an API key — tap the 🔗 icon to visit the server page.',
                  style: TextStyle(fontSize: 11, color: Colors.amber),
                ),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _runSearch,
                  icon: const Icon(Icons.refresh, color: Colors.redAccent),
                  label: const Text(
                    'Retry Connection',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
            ),
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
                  controller: _scrollController,
                  itemCount: _searchResults.length + (_nextCursor != null ? 1 : 0),
                  itemBuilder: (ctx, idx) {
                    if (idx == _searchResults.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadMore();
                      });
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final s = _searchResults[idx];
                    final isChecked = _selectedUrls.contains(s.url);
                    final description = _serverDescriptions[s.url];
                    final homepage = _serverHomepages[s.url];
                    final isOnline = _serverIsOnline[s.url] ?? true;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Checkbox(
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
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.cloud_queue, size: 16, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (description != null && description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      description,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    s.url,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Catalog status: ${isOnline ? 'Online' : 'Offline'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (homepage != null && homepage.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.link, size: 18, color: Colors.grey),
                                  tooltip: 'Open Server Homepage',
                                  onPressed: () async {
                                    final uri = Uri.tryParse(homepage);
                                    if (uri != null) {
                                      try {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } catch (_) {}
                                    }
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: isOnline ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
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
