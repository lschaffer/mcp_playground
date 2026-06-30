import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models.dart';
import '../../playground_controller.dart';
import '../local_mcp_client.dart';
import 'server_tools_dialog.dart';

class McpServerRegistryTab extends StatefulWidget {
  final PlaygroundController controller;

  const McpServerRegistryTab({super.key, required this.controller});

  @override
  State<McpServerRegistryTab> createState() => _McpServerRegistryTabState();
}

class _McpServerRegistryTabState extends State<McpServerRegistryTab> {
  int _activeTab = 0; // 0 = My Servers, 1 = Registry
  String _searchQuery = '';
  String _selectedCategory = 'all';
  String _selectedMethod = 'all'; // 'all', 'uvx', 'pip', 'npm', 'sse'
  bool _loadingGithub = false;
  bool _loadingMore = false;
  String? _nextCursor;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGithubRegistry();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreServers();
    }
  }

  static const _registryCacheKey = 'official_mcp_registry_cache';
  static const _registryCacheTsKey = 'official_mcp_registry_cache_ts';
  static const _registryRemoteUrl = 'https://registry.modelcontextprotocol.io/v0.1/servers?limit=100';
  static const _cacheMaxAge = Duration(hours: 24);

  Future<void> _loadGithubRegistry({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _nextCursor = null;
    }
    // Populate with fallback initially so it's not empty while loading or if offline
    if (_githubRegistry.isEmpty) {
      _githubRegistry.addAll(_fallbackRegistry);
    }

    // 1. Try to read from cache first (if not forcing refresh)
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_registryCacheTsKey);
        final cachedJson = prefs.getString(_registryCacheKey);
        if (ts != null && cachedJson != null) {
          final age = DateTime.now().millisecondsSinceEpoch - ts;
          if (age < _cacheMaxAge.inMilliseconds) {
            final decoded = jsonDecode(cachedJson);
            final list = _parseFetchedRegistry(decoded);
            String? nextCursor;
            if (decoded is Map && decoded.containsKey('metadata')) {
              nextCursor = decoded['metadata']['nextCursor'] as String?;
            }
            if (list.isNotEmpty) {
              setState(() {
                _githubRegistry.clear();
                _githubRegistry.addAll(_fallbackRegistry);
                _githubRegistry.addAll(list);
                _nextCursor = nextCursor;
              });
              return;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Fetch remote registry
    if (mounted) {
      setState(() {
        _loadingGithub = true;
      });
    }
    try {
      final response = await http.get(
        Uri.parse(_registryRemoteUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = _parseFetchedRegistry(decoded);
        String? nextCursor;
        if (decoded is Map && decoded.containsKey('metadata')) {
          nextCursor = decoded['metadata']['nextCursor'] as String?;
        }
        if (list.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_registryCacheKey, response.body);
          await prefs.setInt(_registryCacheTsKey, DateTime.now().millisecondsSinceEpoch);

          if (mounted) {
            setState(() {
              _githubRegistry.clear();
              _githubRegistry.addAll(_fallbackRegistry);
              _githubRegistry.addAll(list);
              _nextCursor = nextCursor;
            });
          }
        }
      } else {
        throw Exception('HTTP status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[McpServerRegistryTab] Failed to fetch remote registry: $e');
      // If fetching fails and we don't have remote content, keep the fallback/cached list
      if (mounted && _githubRegistry.length <= _fallbackRegistry.length) {
        setState(() {
          _githubRegistry.clear();
          _githubRegistry.addAll(_fallbackRegistry);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingGithub = false;
        });
      }
    }
  }

  Future<void> _loadMoreServers() async {
    if (_nextCursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
    });
    try {
      final url = '$_registryRemoteUrl&cursor=${Uri.encodeComponent(_nextCursor!)}';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = _parseFetchedRegistry(decoded);
        String? nextCursor;
        if (decoded is Map && decoded.containsKey('metadata')) {
          nextCursor = decoded['metadata']['nextCursor'] as String?;
        }
        if (list.isNotEmpty) {
          setState(() {
            _githubRegistry.addAll(list);
            _nextCursor = nextCursor;
          });
        }
      } else {
        throw Exception('HTTP status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[McpServerRegistryTab] Failed to load more servers: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _parseFetchedRegistry(dynamic decoded) {
    if (decoded is Map && decoded.containsKey('servers')) {
      final list = decoded['servers'] as List<dynamic>;
      final parsedList = <Map<String, dynamic>>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final s = entry['server'];
        if (s is! Map) continue;

        final name = s['name'] as String? ?? '';
        final title = s['title'] as String? ?? name;
        final description = s['description'] as String? ?? '';

        String installType = 'npm';
        String language = 'nodejs';
        String entryPoint = name;
        String githubUrl = 'https://github.com/modelcontextprotocol/servers';
        List<dynamic> launchArgs = [];
        List<dynamic> requiredEnvVars = [];

        final remotes = s['remotes'] as List<dynamic>?;
        if (remotes != null && remotes.isNotEmpty) {
          final firstRemote = remotes[0];
          if (firstRemote is Map) {
            final remoteType = firstRemote['type'] as String? ?? '';
            final remoteUrl = firstRemote['url'] as String? ?? '';
            if (remoteType == 'streamable-http' || remoteType == 'sse') {
              installType = 'sse';
              language = 'remote';
              entryPoint = remoteUrl;
              githubUrl = remoteUrl;
            }
          }
        }

        parsedList.add({
          "name": name,
          "displayName": title,
          "description": description,
          "githubUrl": githubUrl,
          "language": language,
          "installType": installType,
          "packageName": name,
          "entryPoint": entryPoint,
          "launchArgs": launchArgs,
          "requiredEnvVars": requiredEnvVars,
          "category": _guessCategory(name, description)
        });
      }
      return parsedList;
    }
    return [];
  }

  static String _guessCategory(String name, String description) {
    final combined = '$name $description'.toLowerCase();
    if (combined.contains('file') || combined.contains('directory') || combined.contains('git')) {
      return 'files';
    }
    if (combined.contains('db') || combined.contains('sql') || combined.contains('postgres') || combined.contains('mongo') || combined.contains('sqlite')) {
      return 'databases';
    }
    if (combined.contains('web') || combined.contains('fetch') || combined.contains('search') || combined.contains('browser')) {
      return 'web';
    }
    if (combined.contains('time') || combined.contains('slack') || combined.contains('todo') || combined.contains('productivity')) {
      return 'productivity';
    }
    return 'other';
  }

  final List<Map<String, dynamic>> _githubRegistry = [];

  static const List<Map<String, dynamic>> _fallbackRegistry = [
    {
      "name": "mcp-server-filesystem",
      "displayName": "Filesystem",
      "description": "Read/write local files, list directories, search files. Configure which directories are accessible.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem",
      "language": "nodejs",
      "installType": "npm",
      "packageName": "@modelcontextprotocol/server-filesystem",
      "entryPoint": "mcp-server-filesystem",
      "launchArgs": ["{{allowed_dirs}}"],
      "requiredEnvVars": ["allowed_dirs"],
      "category": "files"
    },
    {
      "name": "mcp-server-fetch",
      "displayName": "Web Fetch",
      "description": "Fetch content from URLs and return the text. Supports HTML-to-markdown conversion.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-fetch",
      "entryPoint": "mcp-server-fetch",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "web"
    },
    {
      "name": "mcp-server-memory",
      "displayName": "Memory (Knowledge Graph)",
      "description": "Persistent local knowledge graph — create entities, relations, and search observations across sessions.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/memory",
      "language": "nodejs",
      "installType": "npm",
      "packageName": "@modelcontextprotocol/server-memory",
      "entryPoint": "mcp-server-memory",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "productivity"
    },
    {
      "name": "mcp-server-brave-search",
      "displayName": "Brave Search",
      "description": "Web and local search using the Brave Search API. Requires a free Brave Search API key.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/brave-search",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-brave-search",
      "entryPoint": "mcp-server-brave-search",
      "launchArgs": [],
      "requiredEnvVars": ["BRAVE_API_KEY"],
      "category": "web"
    },
    {
      "name": "mcp-server-github",
      "displayName": "GitHub",
      "description": "Interact with GitHub repositories: search code, list issues, PRs, and manage files. Requires a GitHub Personal Access Token at runtime. Note: this is a Node.js package — install Node.js and run 'npm install -g @modelcontextprotocol/server-github' manually before use.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/github",
      "language": "nodejs",
      "installType": "npm",
      "packageName": "@modelcontextprotocol/server-github",
      "entryPoint": "mcp-server-github",
      "launchArgs": [],
      "requiredEnvVars": ["GITHUB_PERSONAL_ACCESS_TOKEN"],
      "category": "productivity"
    },
    {
      "name": "mcp-server-slack",
      "displayName": "Slack",
      "description": "Read channels, post messages, list workspaces via the Slack API.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/slack",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-slack",
      "entryPoint": "mcp-server-slack",
      "launchArgs": [],
      "requiredEnvVars": ["SLACK_BOT_TOKEN"],
      "category": "productivity"
    },
    {
      "name": "mcp-server-postgres",
      "displayName": "PostgreSQL",
      "description": "Connect to a PostgreSQL database: query tables, describe schema, and run read-only SQL.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/postgres",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-postgres",
      "entryPoint": "mcp-server-postgres",
      "launchArgs": ["{{connection_string}}"],
      "requiredEnvVars": [],
      "category": "databases"
    },
    {
      "name": "mcp-server-sqlite",
      "displayName": "SQLite",
      "description": "Query and modify a SQLite database file. Provides schema introspection and safe SQL execution.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/sqlite",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-sqlite",
      "entryPoint": "mcp-server-sqlite",
      "launchArgs": ["--db-path", "{{db_path}}"],
      "requiredEnvVars": [],
      "category": "databases"
    },
    {
      "name": "mcp-server-git",
      "displayName": "Git",
      "description": "Interact with local Git repositories: log, diff, status, commits, branches.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/git",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-git",
      "entryPoint": "mcp-server-git",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "files"
    },
    {
      "name": "mcp-server-puppeteer",
      "displayName": "Puppeteer (Browser)",
      "description": "Control a headless Chromium browser: navigate, screenshot, fill forms, and extract content.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/puppeteer",
      "language": "nodejs",
      "installType": "npm",
      "packageName": "@modelcontextprotocol/server-puppeteer",
      "entryPoint": "mcp_server_puppeteer",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "web"
    },
    {
      "name": "mcp-server-time",
      "displayName": "Time & Timezone",
      "description": "Get current time in any timezone and convert between timezones.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/time",
      "language": "python",
      "installType": "uvx",
      "packageName": "mcp-server-time",
      "entryPoint": "mcp-server-time",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "productivity"
    },
    {
      "name": "mcp-server-sequential-thinking",
      "displayName": "Sequential Thinking",
      "description": "Enables multi-step reasoning chains — decompose complex problems into manageable steps.",
      "githubUrl": "https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking",
      "language": "nodejs",
      "installType": "npm",
      "packageName": "@modelcontextprotocol/server-sequentialthinking",
      "entryPoint": "mcp-server-sequential-thinking",
      "launchArgs": [],
      "requiredEnvVars": [],
      "category": "productivity"
    }
  ];

  List<McpServerConfig> get _myServers => widget.controller.servers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab switcher (My Servers / Registry)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('My Servers'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Registry'),
                      icon: Icon(Icons.public_outlined),
                    ),
                  ],
                  selected: {_activeTab},
                  onSelectionChanged: (set) {
                    setState(() {
                      _activeTab = set.first;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // Tab Content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _activeTab == 0
                ? _buildMyServersTab(theme)
                : _buildRegistryTab(theme),
          ),
        ),
      ],
    );
  }

  // ─── My Servers Tab ────────────────────────────────────────────────────────

  Widget _buildMyServersTab(ThemeData theme) {
    final servers = _myServers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Configured Servers',
                style: theme.textTheme.titleSmall,
              ),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(context, null),
                icon: const Icon(Icons.add),
                label: const Text('Install Manually'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: servers.isEmpty
              ? const Center(
                  child: Text(
                    'No servers configured yet.\nClick "Install Manually" or browse the "Registry" tab to connect to servers.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: servers.length,
                  itemBuilder: (ctx, idx) {
                    final server = servers[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: server.enabled
                              ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
                              : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: const Icon(Icons.extension, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        server.name,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        server.localPackage ?? (server.isLocal ? 'Custom Local Server' : 'Remote SSE Server'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: server.enabled,
                                  onChanged: (val) {
                                    widget.controller.updateServer(
                                      server.copyWith(enabled: val),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.list_alt_outlined),
                                  tooltip: 'Discover Tools',
                                  onPressed: () =>
                                      ServerToolsDialog.show(context, server, widget.controller),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditDialog(context, server),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _confirmDelete(server),
                                ),
                              ],
                            ),
                            if (server.description != null &&
                                server.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                server.description!,
                                style: const TextStyle(fontSize: 13, height: 1.4),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                _buildBadge(server.localInstallMethod?.toUpperCase() ?? (server.isLocal ? 'LOCAL' : 'REMOTE SSE')),
                                if (server.isInstalled) _buildBadge('INSTALLED', color: Colors.green),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Registry Tab ──────────────────────────────────────────────────────────

  Widget _buildRegistryTab(ThemeData theme) {
    // Categories and Methods lists
    final categories = ['all', 'files', 'databases', 'web', 'productivity', 'other'];
    final methods = ['all', 'uvx', 'pip', 'npm', 'sse'];

    // Filter registry list
    final filtered = _githubRegistry.where((s) {
      final name = s['name'].toString().toLowerCase();
      final display = s['displayName'].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      if (!name.contains(query) && !display.contains(query)) return false;

      if (_selectedCategory != 'all' && s['category'] != _selectedCategory) return false;
      if (_selectedMethod != 'all' && s['installType'] != _selectedMethod) return false;

      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          child: Row(
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(_capitalize(cat)),
                  selected: isSelected,
                  onSelected: (sel) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Method filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
          child: Row(
            children: methods.map((m) {
              final isSelected = _selectedMethod == m;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(m.toUpperCase()),
                  selected: isSelected,
                  onSelected: (sel) {
                    setState(() {
                      _selectedMethod = m;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Search box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search servers...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_loadingGithub)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00ACC1),
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF00ACC1)),
                  tooltip: 'Refresh catalog from online registry',
                  onPressed: () => _loadGithubRegistry(forceRefresh: true),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No servers match your filters.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadGithubRegistry(forceRefresh: true),
                  color: const Color(0xFF00ACC1),
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: filtered.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (ctx, idx) {
                      if (idx == filtered.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00ACC1),
                              ),
                            ),
                          ),
                        );
                      }
                      final item = filtered[idx];
                      final packageName = item['packageName'] as String;
                      final installType = item['installType'] as String;
                      final language = item['language'] as String;

                      // Check if installed in controller
                      final installedIndex = _myServers.indexWhere(
                        (s) => s.isLocal
                            ? s.localPackage == packageName
                            : s.url == item['entryPoint'],
                      );
                      final isInstalled = installedIndex != -1;
                      final installedServer = isInstalled ? _myServers[installedIndex] : null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isInstalled
                                ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.secondaryContainer,
                            child: Icon(_iconForCategory(item['category']), size: 18),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item['displayName'] as String,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              if (isInstalled && installedServer!.enabled)
                                _buildBadge('ACTIVE', color: Colors.purple)
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              _buildBadge(language.toUpperCase()),
                              const SizedBox(width: 4),
                              _buildBadge(installType.toUpperCase()),
                              if (isInstalled) ...[
                                const SizedBox(width: 4),
                                _buildBadge('INSTALLED', color: Colors.green),
                              ]
                            ],
                          ),
                          childrenPadding: const EdgeInsets.all(16),
                          expandedAlignment: Alignment.topLeft,
                          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              item['description'] as String,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {}, // Link click handled by context URL if copyable
                              child: SelectableText(
                                item['githubUrl'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (isInstalled) ...[
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _confirmDelete(installedServer!),
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Remove'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red[900],
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        onPressed: () => ServerToolsDialog.show(
                                          context,
                                          installedServer!,
                                          widget.controller,
                                        ),
                                        icon: const Icon(Icons.list_alt_outlined),
                                        label: const Text('Discover Tools'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF7C3AED),
                                          side: const BorderSide(color: Color(0xFF7C3AED)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const Text('Active: '),
                                      Switch(
                                        value: installedServer!.enabled,
                                        onChanged: (val) {
                                          widget.controller.updateServer(
                                            installedServer.copyWith(enabled: val),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  const Spacer(),
                                  ElevatedButton.icon(
                                    onPressed: () => _triggerInstall(item),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Install'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF7C3AED),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Dialogs & Actions ─────────────────────────────────────────────────────

  Widget _buildBadge(String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.15) ?? Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color?.withValues(alpha: 0.4) ?? Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color ?? Colors.grey[400],
        ),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

  IconData _iconForCategory(String? category) {
    switch (category) {
      case 'files':
        return Icons.folder_open;
      case 'databases':
        return Icons.storage;
      case 'web':
        return Icons.language;
      case 'productivity':
        return Icons.work_outline;
      default:
        return Icons.extension_outlined;
    }
  }

  void _triggerInstall(Map<String, dynamic> registryItem) {
    final installType = registryItem['installType'] as String;
    final isLocal = installType != 'sse';

    if (!isLocal) {
      final config = McpServerConfig(
        id: const Uuid().v4(),
        name: registryItem['displayName'] as String,
        url: registryItem['entryPoint'] as String,
        isLocal: false,
        isInstalled: true,
        enabled: true,
        description: registryItem['description'] as String,
      );
      widget.controller.addServer(config);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to remote server: ${config.name}')),
      );
      return;
    }

    // Generate base config
    final config = McpServerConfig(
      id: const Uuid().v4(),
      name: registryItem['displayName'] as String,
      url: (registryItem['launchArgs'] as List).join(' '),
      isLocal: true,
      localType: registryItem['language'] as String,
      localInstallMethod: registryItem['installType'] as String,
      localPackage: registryItem['packageName'] as String,
      isInstalled: false,
      enabled: true,
      description: registryItem['description'] as String,
    );

    // If there are required env vars, we must edit/ask first
    final List<String> requiredVars = List<String>.from(registryItem['requiredEnvVars'] ?? []);
    if (requiredVars.isNotEmpty) {
      _showEditDialog(context, config, requiredVars: requiredVars);
    } else {
      _runInstaller(context, config);
    }
  }

  void _confirmDelete(McpServerConfig server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${server.name}'),
        content: Text('Uninstall "${server.name}" and delete its local environment data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showUninstallLoader(context, server);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showUninstallLoader(BuildContext ctx, McpServerConfig server) async {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Uninstalling server environment...'),
          ],
        ),
      ),
    );

    widget.controller.removeServer(server.id);
    await LocalMcpRuntime.uninstall(server);

    if (!mounted) return;
    Navigator.pop(context); // Close loader
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Uninstalled ${server.name} successfully')),
    );
  }

  void _showEditDialog(
    BuildContext context,
    McpServerConfig? existing, {
    List<String>? requiredVars,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EditLocalMcpDialog(
        controller: widget.controller,
        existing: existing,
        requiredEnvVars: requiredVars,
        onInstalled: () {
          setState(() {});
        },
      ),
    ).then((_) {
      setState(() {});
    });
  }

  void _runInstaller(BuildContext context, McpServerConfig config) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InstallProgressDialog(
        server: config,
        controller: widget.controller,
        onComplete: () {
          setState(() {});
        },
      ),
    );
  }
}

// ─── Edit Dialog ─────────────────────────────────────────────────────────────

class EditLocalMcpDialog extends StatefulWidget {
  final PlaygroundController controller;
  final McpServerConfig? existing;
  final List<String>? requiredEnvVars;
  final VoidCallback onInstalled;

  const EditLocalMcpDialog({
    super.key,
    required this.controller,
    this.existing,
    this.requiredEnvVars,
    required this.onInstalled,
  });

  @override
  State<EditLocalMcpDialog> createState() => _EditLocalMcpDialogState();
}

class _EditLocalMcpDialogState extends State<EditLocalMcpDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl; // Arguments
  late final TextEditingController _packageCtrl;
  late final TextEditingController _commandCtrl;

  late String _type; // 'python' | 'nodejs'
  late String _method; // 'pip' | 'uvx' | 'npm' | 'npx'
  final Map<String, TextEditingController> _envCtrls = {};

  @override
  void initState() {
    super.initState();
    final s = widget.existing;

    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _urlCtrl = TextEditingController(text: s?.url ?? '');
    _packageCtrl = TextEditingController(text: s?.localPackage ?? '');
    _commandCtrl = TextEditingController(text: s?.localCommand ?? '');

    _type = s?.localType ?? 'python';
    _method = s?.localInstallMethod ?? 'uvx';

    final env = s?.localEnvVars ?? {};
    final requiredList = widget.requiredEnvVars ?? [];
    for (final key in requiredList) {
      _envCtrls[key] = TextEditingController(text: env[key] ?? '');
    }
    // Add existing custom env vars if not in required list
    env.forEach((key, val) {
      if (!_envCtrls.containsKey(key)) {
        _envCtrls[key] = TextEditingController(text: val);
      }
    });

    _autoGenerateCommand();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _packageCtrl.dispose();
    _commandCtrl.dispose();
    for (final ctrl in _envCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _autoGenerateCommand() {
    if (_commandCtrl.text.isNotEmpty && widget.existing != null) return;
    final pkg = _packageCtrl.text.trim();
    if (pkg.isEmpty) {
      _commandCtrl.text = '';
      return;
    }

    if (_type == 'python') {
      if (_method == 'uvx') {
        _commandCtrl.text = 'uvx $pkg';
      } else {
        _commandCtrl.text = 'pip install $pkg';
      }
    } else {
      if (_method == 'npx') {
        _commandCtrl.text = 'npx -y $pkg';
      } else {
        _commandCtrl.text = 'npm install -g $pkg';
      }
    }
  }

  McpServerConfig _buildConfigObject() {
    final Map<String, String> env = {};
    _envCtrls.forEach((key, ctrl) {
      if (ctrl.text.trim().isNotEmpty) {
        env[key] = ctrl.text.trim();
      }
    });

    return McpServerConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      mcpEndpoint: widget.existing?.mcpEndpoint ?? '/mcp',
      isLocal: true,
      localType: _type,
      localInstallMethod: _method,
      localPackage: _packageCtrl.text.trim(),
      localCommand: _commandCtrl.text.trim(),
      localEnvVars: env.isNotEmpty ? env : null,
      isInstalled: widget.existing?.isInstalled ?? false,
      enabled: widget.existing?.enabled ?? true,
      description: widget.existing?.description,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_suggest_outlined, color: Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          Text(widget.existing != null ? 'Edit MCP Server' : 'Install MCP Server Manually'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Install an MCP server that is not listed in any registry.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Arguments
                TextFormField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Launch arguments (optional)',
                    hintText: '--db-path /data/db.sqlite',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Type & Method Row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'python', child: Text('Python')),
                          DropdownMenuItem(value: 'nodejs', child: Text('Node.js')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _type = val;
                              _method = val == 'python' ? 'uvx' : 'npx';
                              _autoGenerateCommand();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: const InputDecoration(
                          labelText: 'Method',
                          border: OutlineInputBorder(),
                        ),
                        items: _type == 'python'
                            ? const [
                                DropdownMenuItem(value: 'uvx', child: Text('uvx')),
                                DropdownMenuItem(value: 'pip', child: Text('pip install')),
                              ]
                            : const [
                                DropdownMenuItem(value: 'npx', child: Text('npx')),
                                DropdownMenuItem(value: 'npm', child: Text('npm install -g')),
                              ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _method = val;
                              _autoGenerateCommand();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Package name
                TextFormField(
                  controller: _packageCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Package / server name',
                    hintText: 'e.g. mcp-server-git or github repo URL',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(_autoGenerateCommand),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Command
                TextFormField(
                  controller: _commandCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Install command(s)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        setState(() {
                          _commandCtrl.text = '';
                          _autoGenerateCommand();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Environment Variables
                if (_envCtrls.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Required Environment Variables',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  ..._envCtrls.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextFormField(
                        controller: entry.value,
                        decoration: InputDecoration(
                          labelText: entry.key,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (val) =>
                            val == null || val.trim().isEmpty ? 'Required env variable' : null,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final config = _buildConfigObject();
              if (widget.existing != null) {
                widget.controller.updateServer(config);
              } else {
                widget.controller.addServer(config);
              }
              Navigator.pop(context);
              widget.onInstalled();
            }
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Info'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final config = _buildConfigObject();
              Navigator.pop(context);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => InstallProgressDialog(
                  server: config,
                  controller: widget.controller,
                  onComplete: widget.onInstalled,
                ),
              );
            }
          },
          icon: const Icon(Icons.play_arrow_outlined),
          label: const Text('Execute & Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ─── Install Progress Dialog ─────────────────────────────────────────────────

class InstallProgressDialog extends StatefulWidget {
  final McpServerConfig server;
  final PlaygroundController controller;
  final VoidCallback onComplete;

  const InstallProgressDialog({
    super.key,
    required this.server,
    required this.controller,
    required this.onComplete,
  });

  @override
  State<InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<InstallProgressDialog> {
  final List<String> _logs = [];
  LocalInstallStep _step = LocalInstallStep.detecting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runInstall();
  }

  Future<void> _runInstall() async {
    setState(() {
      _logs.add('Starting installation pipeline for ${widget.server.name}...');
    });

    final error = await LocalMcpRuntime.install(
      widget.server,
      onProgress: (progress) {
        setState(() {
          _step = progress.step;
          _logs.add('[${progress.step.name.toUpperCase()}] ${progress.message}');
        });
      },
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _step = LocalInstallStep.failed;
        _error = error;
        _logs.add('[FAILED] $error');
      });
    } else {
      // Save and register server in controller
      final installedConfig = widget.server.copyWith(isInstalled: true);
      final idx = widget.controller.servers.indexWhere((s) => s.id == widget.server.id);
      if (idx != -1) {
        widget.controller.updateServer(installedConfig);
      } else {
        widget.controller.addServer(installedConfig);
      }

      setState(() {
        _step = LocalInstallStep.done;
        _logs.add('[DONE] Server installed and registered successfully!');
      });
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = _step == LocalInstallStep.done;
    final isFailed = _step == LocalInstallStep.failed;

    return AlertDialog(
      title: Row(
        children: [
          if (!isDone && !isFailed) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Text('Installing MCP Server...'),
          ] else if (isDone) ...[
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 12),
            const Text('Installation Complete'),
          ] else ...[
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            const Text('Installation Failed'),
          ],
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (ctx, idx) {
                    final log = _logs[idx];
                    var logColor = Colors.greenAccent;
                    if (log.startsWith('[FAILED]') || log.contains('error')) {
                      logColor = Colors.redAccent;
                    } else if (log.startsWith('[DETECTING]')) {
                      logColor = Colors.cyanAccent;
                    } else if (log.startsWith('[DONE]')) {
                      logColor = Colors.lightGreenAccent;
                    }
                    return Text(
                      log,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: logColor,
                      ),
                    );
                  },
                ),
              ),
            ),
            if (isFailed && _error != null) ...[
              const SizedBox(height: 12),
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (isDone || isFailed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
      ],
    );
  }
}
