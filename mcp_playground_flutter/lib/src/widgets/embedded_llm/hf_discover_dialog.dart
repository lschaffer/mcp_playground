import 'package:flutter/material.dart';
import '../../services/embedded_llm/embedded_model.dart';
import '../../services/embedded_llm/embedded_model_manager.dart';

/// Full-screen dialog that searches HuggingFace for popular GGUF models and
/// lets the user add them to the custom model list.
class HfDiscoverDialog extends StatefulWidget {
  const HfDiscoverDialog({super.key});

  /// Open the dialog. Returns a list of [EmbeddedGgufModel] added by the user.
  static Future<List<EmbeddedGgufModel>?> show(BuildContext context) {
    return Navigator.of(context).push<List<EmbeddedGgufModel>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const HfDiscoverDialog(),
    ));
  }

  @override
  State<HfDiscoverDialog> createState() => _HfDiscoverDialogState();
}

class _HfDiscoverDialogState extends State<HfDiscoverDialog> {
  final _searchCtrl = TextEditingController();
  String _sort = 'downloads';
  bool _loading = false;
  String? _error;
  List<HfDiscoveryResult> _results = [];
  final Set<String> _addedRepoIds = {};
  final List<EmbeddedGgufModel> _added = [];
  bool _hideOversized = false;

  static const int _cpuSizeWarnBytes = 1500000000; // 1.5 GB

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await EmbeddedModelManager.instance.discoverPopularModels(
        query: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        sort: _sort,
        limit: 30,
      );
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFile(HfDiscoveryResult repo, HfGgufFile file) async {
    final model = EmbeddedGgufModel(
      id: 'hf_${repo.repoId.replaceAll('/', '_')}_${file.filename}',
      displayName: '${repo.displayName} — ${file.filename}',
      filename: file.filename,
      url: file.downloadUrl,
      description: repo.description ?? 'From HuggingFace: ${repo.repoId}',
      sizeBytes: file.sizeBytes,
    );
    await EmbeddedModelManager.instance.addCustomModel(model);
    setState(() {
      _addedRepoIds.add('${repo.repoId}/${file.filename}');
      _added.add(model);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${model.displayName}"'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Models (HuggingFace)'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(_added)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search for GGUF models…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _search();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  tooltip: 'Sort by',
                  icon: const Icon(Icons.sort),
                  onSelected: (v) {
                    setState(() => _sort = v);
                    _search();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'downloads', child: Text('Most downloaded')),
                    PopupMenuItem(value: 'trending', child: Text('Trending')),
                    PopupMenuItem(value: 'likes', child: Text('Most liked')),
                    PopupMenuItem(value: 'lastModified', child: Text('Recently updated')),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _search),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Results from HuggingFace. Tap a file to add it to your model list. '
              'You can download it from the model picker afterwards.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Hide too large for CPU'),
                  selected: _hideOversized,
                  onSelected: (v) => setState(() => _hideOversized = v),
                  avatar: Icon(Icons.filter_list, size: 14, color: _hideOversized ? Colors.orange : null),
                  selectedColor: Colors.orange.withValues(alpha: 0.12),
                  checkmarkColor: Colors.orange,
                  side: BorderSide(color: Colors.orange.withValues(alpha: _hideOversized ? 0.5 : 0.2)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
                          const SizedBox(height: 12),
                          Text('Failed to load results', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(_error!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(onPressed: _search, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : _results.isEmpty
                ? Center(child: Text('No GGUF models found. Try a different query.', style: theme.textTheme.bodyMedium))
                : Builder(
                    builder: (context) {
                      final maxBytes = _hideOversized ? _cpuSizeWarnBytes : 0;
                      final visibleRepos = _hideOversized
                          ? _results
                                .where(
                                  (repo) =>
                                      repo.ggufFiles.isEmpty ||
                                      repo.ggufFiles.any((f) => f.effectiveSizeBytes <= 0 || f.effectiveSizeBytes <= maxBytes),
                                )
                                .toList()
                          : _results;
                      final hiddenRepoCount = _results.length - visibleRepos.length;
                      return Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: visibleRepos.length,
                              itemBuilder: (context, index) {
                                final repo = visibleRepos[index];
                                return _RepoCard(
                                  repo: repo,
                                  addedKeys: _addedRepoIds,
                                  onAddFile: _addFile,
                                  maxSafeSizeBytes: maxBytes,
                                  hideOversized: _hideOversized,
                                );
                              },
                            ),
                          ),
                          if (hiddenRepoCount > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "$hiddenRepoCount repo${hiddenRepoCount > 1 ? 's' : ''} hidden (all files too large for CPU)",
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RepoCard extends StatefulWidget {
  final HfDiscoveryResult repo;
  final Set<String> addedKeys;
  final Future<void> Function(HfDiscoveryResult repo, HfGgufFile file) onAddFile;
  final int maxSafeSizeBytes;
  final bool hideOversized;

  const _RepoCard({
    required this.repo,
    required this.addedKeys,
    required this.onAddFile,
    this.maxSafeSizeBytes = 0,
    this.hideOversized = false,
  });

  @override
  State<_RepoCard> createState() => _RepoCardState();
}

class _RepoCardState extends State<_RepoCard> {
  bool _expanded = false;
  final Set<String> _adding = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = widget.repo;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(repo.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: repo.description != null && repo.description!.isNotEmpty
                ? Text(repo.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(_formatCount(repo.downloads), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(Icons.favorite_border, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(_formatCount(repo.likes), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () {
              setState(() => _expanded = !_expanded);
            },
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (repo.ggufFiles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No .gguf files listed for this repo.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              (() {
                final maxBytes = widget.maxSafeSizeBytes;
                final visibleFiles = maxBytes > 0 && widget.hideOversized
                    ? repo.ggufFiles.where((f) => f.effectiveSizeBytes <= 0 || f.effectiveSizeBytes <= maxBytes).toList()
                    : repo.ggufFiles;
                final hiddenCount = repo.ggufFiles.length - visibleFiles.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...visibleFiles.map((file) {
                      final key = '${repo.repoId}/${file.filename}';
                      final alreadyAdded = widget.addedKeys.contains(key);
                      final adding = _adding.contains(key);
                      final effSize = file.effectiveSizeBytes;
                      final tooLarge = maxBytes > 0 && effSize > 0 && effSize > maxBytes;
                      return Opacity(
                        opacity: tooLarge ? 0.55 : 1.0,
                        child: ListTile(
                          dense: true,
                          title: Text(file.filename, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                          subtitle: Row(
                            children: [
                              Text(file.sizeLabel, style: theme.textTheme.bodySmall),
                              if (tooLarge) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                                const SizedBox(width: 2),
                                const Text('Too large for CPU', style: TextStyle(fontSize: 11, color: Colors.orange)),
                              ],
                            ],
                          ),
                          trailing: alreadyAdded
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : adding
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 22),
                                  tooltip: 'Add to model list',
                                  onPressed: () async {
                                    setState(() => _adding.add(key));
                                    await widget.onAddFile(repo, file);
                                    if (mounted) setState(() => _adding.remove(key));
                                  },
                                ),
                        ),
                      );
                    }),
                    if (hiddenCount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          "$hiddenCount file${hiddenCount > 1 ? 's' : ''} hidden (too large for CPU)",
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                  ],
                );
              })(),
            ],
          ],
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}
