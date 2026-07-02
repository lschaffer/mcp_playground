import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/embedded_llm/embedded_model.dart';
import '../../services/embedded_llm/embedded_model_manager.dart';
import '../../services/embedded_llm/embedded_llm_adapter.dart';
import '../../mcp_localizations.dart';
import 'add_gguf_dialog.dart';
import 'hf_discover_dialog.dart';

/// Widget shown in the LLM settings dialog when the user picks "Embedded (on-device)".
class EmbeddedModelPickerWidget extends StatefulWidget {
  final String selectedFilename;
  final ValueChanged<String> onFilenameSelected;

  const EmbeddedModelPickerWidget({
    super.key,
    required this.selectedFilename,
    required this.onFilenameSelected,
  });

  @override
  State<EmbeddedModelPickerWidget> createState() =>
      _EmbeddedModelPickerWidgetState();
}

class _EmbeddedModelPickerWidgetState extends State<EmbeddedModelPickerWidget> {
  List<EmbeddedGgufModel> _customModels = [];
  Set<String> _downloadedFilenames = {};
  bool _loading = true;

  // Local selection state — drives radio icon without depending on parent rebuild
  late String _selectedFilename;

  // Track active download per filename
  final Map<String, double> _downloadProgress = {}; // filename → 0.0–1.0
  final Map<String, DownloadCancelToken> _cancelTokens = {};

  // Track loading model into the LlamaEngine (app memory)
  String? _appLoadingFilename; // filename being loaded into app
  double _appLoadProgress = 0.0; // 0.0–1.0

  // Per-model GPU layers setting (filename → gpuLayers)
  final Map<String, int> _gpuLayersMap = {};

  // GPU support state
  bool? _gpuSupported; // null = not yet checked
  int _vramFreeBytes = 0;

  static const int _cpuSizeWarnBytes = 1500000000; // 1.5 GB

  @override
  void initState() {
    super.initState();
    _selectedFilename = widget.selectedFilename;
    _refresh();
  }

  @override
  void didUpdateWidget(EmbeddedModelPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync if parent explicitly changes the value (e.g. on clear).
    if (oldWidget.selectedFilename != widget.selectedFilename) {
      _selectedFilename = widget.selectedFilename;
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final customs = await EmbeddedModelManager.instance.loadCustomModels();
      final downloaded = await EmbeddedModelManager.instance
          .listDownloadedFilenames();

      final gpuMap = <String, int>{};
      for (final filename in downloaded) {
        gpuMap[filename] = await EmbeddedModelManager.instance.getGpuLayers(
          filename,
        );
      }

      bool gpuSupported = false;
      int vramFree = 0;
      final adapter = EmbeddedLlmAdapter.instance;
      try {
        gpuSupported = await adapter.isGpuSupported();
        if (gpuSupported) {
          final vram = await adapter.getVramInfo();
          vramFree = vram.free;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _customModels = customs;
          _downloadedFilenames = downloaded;
          _gpuLayersMap
            ..clear()
            ..addAll(gpuMap);
          _gpuSupported = gpuSupported;
          _vramFreeBytes = vramFree;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // All models = custom + any .gguf files already on disk (no hardcoded catalog)
  List<EmbeddedGgufModel> get _allModels {
    final seen = <String>{};
    final combined = <EmbeddedGgufModel>[];
    for (final m in _customModels) {
      if (seen.add(m.filename)) combined.add(m);
    }
    for (final filename in _downloadedFilenames) {
      if (seen.add(filename)) {
        final name = filename
            .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
            .replaceAll(RegExp(r'[-_]'), ' ');
        // If it maps to a custom model, keep the url/display info
        final custom = _customModels.firstWhere(
          (c) => c.filename == filename,
          orElse: () => const EmbeddedGgufModel(
            id: '',
            displayName: '',
            filename: '',
            url: '',
            description: '',
          ),
        );
        combined.add(
          EmbeddedGgufModel(
            id: filename,
            displayName: custom.id.isNotEmpty ? custom.displayName : name,
            filename: filename,
            url: custom.id.isNotEmpty ? custom.url : '',
            description: custom.id.isNotEmpty
                ? custom.description
                : 'Downloaded model.',
          ),
        );
      }
    }
    return combined;
  }

  Future<void> _startDownload(EmbeddedGgufModel model) async {
    if (_downloadProgress.containsKey(model.filename)) return;

    final token = DownloadCancelToken();
    setState(() {
      _cancelTokens[model.filename] = token;
      _downloadProgress[model.filename] = 0.0;
    });
    try {
      await EmbeddedModelManager.instance.downloadModel(
        url: model.url,
        filename: model.filename,
        cancelToken: token,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress[model.filename] = p);
        },
      );
      if (!token.isCancelled) {
        await _refresh();
        if (mounted) widget.onFilenameSelected(model.filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(model.filename);
          _cancelTokens.remove(model.filename);
        });
      }
    }
  }

  void _cancelDownload(String filename) {
    _cancelTokens[filename]?.cancel();
    setState(() {
      _downloadProgress.remove(filename);
      _cancelTokens.remove(filename);
    });
  }

  Future<void> _deleteModel(EmbeddedGgufModel model) async {
    final l10n = McpPlaygroundLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('Remove "${model.displayName}" from device storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.get('clear'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await EmbeddedModelManager.instance.deleteModel(model.filename);
    if (widget.selectedFilename == model.filename) {
      widget.onFilenameSelected('');
    }
    await _refresh();
  }

  Future<void> _deleteAllModels() async {
    final l10n = McpPlaygroundLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all models?'),
        content: const Text(
          'This will delete all downloaded GGUF files from device storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.get('removeAll'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await EmbeddedModelManager.instance.deleteAllModels();
    widget.onFilenameSelected('');
    await _refresh();
  }

  Future<void> _openDiscover() async {
    final added = await HfDiscoverDialog.show(context);
    if (added != null && added.isNotEmpty) {
      await _refresh();
    }
  }

  Future<void> _openAddGguf() async {
    final model = await AddGgufDialog.show(context);
    if (model != null) {
      await _refresh();
    }
  }

  Future<void> _openAddFromDisk() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      setState(() => _loading = true);

      final filename = file.name;
      String finalUrl = '';

      final isDesktop =
          !kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

      if (isDesktop) {
        finalUrl = path;
      } else {
        final modelsDir = await EmbeddedModelManager.instance
            .getModelsDirectory();
        final destFile = File('${modelsDir.path}/$filename');
        if (!destFile.existsSync()) {
          final sourceFile = File(path);
          await sourceFile.copy(destFile.path);
        }
        finalUrl = destFile.path;
      }

      final model = EmbeddedGgufModel(
        id: 'disk_${DateTime.now().millisecondsSinceEpoch}',
        displayName: filename
            .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '')
            .replaceAll(RegExp(r'[-_]'), ' '),
        filename: filename,
        url: finalUrl,
        description: 'Local model added from disk.',
        sizeBytes: file.size,
      );

      await EmbeddedModelManager.instance.addCustomModel(model);
      await _refresh();

      widget.onFilenameSelected(model.filename);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added local model "${model.displayName}" from disk.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add model from disk: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _removeFromList(EmbeddedGgufModel model) async {
    await EmbeddedModelManager.instance.removeCustomModel(model.id);
    if (widget.selectedFilename == model.filename) {
      widget.onFilenameSelected('');
    }
    await _refresh();
  }

  Future<void> _setGpuLayers(String filename, int gpuLayers) async {
    await EmbeddedModelManager.instance.saveGpuLayers(filename, gpuLayers);
    if (mounted) setState(() => _gpuLayersMap[filename] = gpuLayers);
  }

  Future<void> _loadModelIntoApp(EmbeddedGgufModel model) async {
    if (_appLoadingFilename != null) return;

    final bool cpuOnly = (_gpuLayersMap[model.filename] ?? 0) == 0;
    if (Platform.isAndroid && cpuOnly && model.sizeBytes > _cpuSizeWarnBytes) {
      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Model may be too large'),
          content: Text(
            '${model.displayName}${model.sizeLabel.isNotEmpty ? ' (${model.sizeLabel})' : ''} '
            'is larger than 1.5 GB. On CPU-only mode this often fails on Android due '
            'to process memory limits.\n\n'
            'Try a smaller quantization (Q2_K or Q3_K_S), or enable GPU layers '
            'if your device supports it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Load anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _appLoadingFilename = model.filename;
      _appLoadProgress = 0.0;
    });
    try {
      final gpuLayers = _gpuLayersMap[model.filename] ?? 0;
      // If GGUF is linked directly from disk (e.g. on desktop), the model.url represents the original path
      final fullPath = File(model.url).existsSync()
          ? model.url
          : await EmbeddedModelManager.instance.fullPathForFilename(
              model.filename,
            );

      await EmbeddedLlmAdapter.instance.initialize(
        fullPath,
        gpuLayers: gpuLayers,
        contextSize: model.contextSize,
        onProgress: (p) {
          if (mounted) setState(() => _appLoadProgress = p);
        },
      );
    } catch (e) {
      if (mounted) {
        final l10n = McpPlaygroundLocalizations.of(context);
        final errorStr = e.toString();
        final isContextFailure =
            errorStr.contains('create context') ||
            errorStr.contains('Failed to create context');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isContextFailure
                  ? '${l10n.get('loadModelFailed')}: The model architecture may not be compatible with '
                        'the current llama.cpp version. Try a different quantization '
                        '(e.g. Q8_0 or Q6_K) or a different model. Error: $errorStr'
                  : '${l10n.get('loadModelFailed')}: $errorStr',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _appLoadingFilename = null);
    }
  }

  Future<void> _unloadModelFromApp() async {
    await EmbeddedLlmAdapter.instance.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = McpPlaygroundLocalizations.of(context);
    final appLoadedPath = EmbeddedLlmAdapter.instance.loadedModelPath;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final models = _allModels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.get('onDeviceModels'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.get('refresh')),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (models.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.explore_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Find a model to get started',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use "Discover popular" to browse HuggingFace GGUF repos, "Add GGUF URL" to paste a link, or "Add GGUF from Disk" to select a local file.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...models.map((model) {
            // Check if the GGUF file is in models/ folder, or if it points to a valid file on disk (direct path)
            final isDownloaded =
                _downloadedFilenames.contains(model.filename) ||
                File(model.url).existsSync();
            final isAppLoaded =
                EmbeddedLlmAdapter.instance.isLoaded &&
                (appLoadedPath?.endsWith(model.filename) ?? false);
            final isAppLoading = _appLoadingFilename == model.filename;
            final isCustom = _customModels.any((m) => m.id == model.id);
            return _ModelTile(
              key: ValueKey(model.filename),
              model: model,
              isSelected: _selectedFilename == model.filename,
              isDownloaded: isDownloaded,
              downloadProgress: _downloadProgress[model.filename],
              onSelect: isDownloaded
                  ? () {
                      setState(() => _selectedFilename = model.filename);
                      widget.onFilenameSelected(model.filename);
                    }
                  : null,
              onDownload: () => _startDownload(model),
              onCancelDownload: () => _cancelDownload(model.filename),
              onDelete: isDownloaded ? () => _deleteModel(model) : null,
              onRemoveFromList: (isCustom && !isDownloaded)
                  ? () => _removeFromList(model)
                  : null,
              isAppLoaded: isAppLoaded,
              isAppLoading: isAppLoading,
              appLoadProgress: isAppLoading ? _appLoadProgress : null,
              gpuLayers: _gpuLayersMap[model.filename] ?? 0,
              onGpuLayersChanged: isDownloaded
                  ? (v) => _setGpuLayers(model.filename, v)
                  : null,
              gpuSupported: _gpuSupported ?? true,
              vramFreeBytes: _vramFreeBytes,
              onLoadToApp:
                  (isDownloaded &&
                      !isAppLoaded &&
                      !isAppLoading &&
                      _appLoadingFilename == null)
                  ? () => _loadModelIntoApp(model)
                  : null,
              onUnloadFromApp: isAppLoaded ? _unloadModelFromApp : null,
            );
          }),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _openDiscover,
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text(l10n.get('discoverPopular')),
            ),
            OutlinedButton.icon(
              onPressed: _openAddGguf,
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(l10n.get('addGgufUrl')),
            ),
            OutlinedButton.icon(
              onPressed: _openAddFromDisk,
              icon: const Icon(Icons.drive_folder_upload, size: 18),
              label: Text(l10n.get('addGgufDisk')),
            ),
            if (_downloadedFilenames.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _deleteAllModels,
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  l10n.get('removeAll'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.selectedFilename.isEmpty && _downloadedFilenames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.get('selectDownloadedModelHint'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_downloadedFilenames.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.get('downloadModelHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  final EmbeddedGgufModel model;
  final bool isSelected;
  final bool isDownloaded;
  final double? downloadProgress;
  final VoidCallback? onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback? onDelete;
  final bool isAppLoaded;
  final bool isAppLoading;
  final double? appLoadProgress;
  final int gpuLayers;
  final ValueChanged<int>? onGpuLayersChanged;
  final bool gpuSupported;
  final int vramFreeBytes;
  final VoidCallback? onLoadToApp;
  final VoidCallback? onUnloadFromApp;
  final VoidCallback? onRemoveFromList;

  const _ModelTile({
    super.key,
    required this.model,
    required this.isSelected,
    required this.isDownloaded,
    required this.downloadProgress,
    required this.onSelect,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onDelete,
    this.isAppLoaded = false,
    this.isAppLoading = false,
    this.appLoadProgress,
    this.gpuLayers = 0,
    this.onGpuLayersChanged,
    this.gpuSupported = true,
    this.vramFreeBytes = 0,
    this.onLoadToApp,
    this.onUnloadFromApp,
    this.onRemoveFromList,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = McpPlaygroundLocalizations.of(context);
    final isDownloading = downloadProgress != null;
    final selectedButMissing = isSelected && !isDownloaded;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: (isSelected && isDownloaded)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : selectedButMissing
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.error, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isDownloaded && !isDownloading ? onSelect : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDownloaded)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    )
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          model.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (model.sizeLabel.isNotEmpty)
                              _Chip(
                                label: model.sizeLabel,
                                icon: Icons.sd_card_outlined,
                              ),
                            _Chip(
                              label: '≥ ${model.minRamGb} GB RAM',
                              icon: Icons.memory_outlined,
                            ),
                            _Chip(
                              label:
                                  '${(model.contextSize / 1024).round()}K ctx',
                              icon: Icons.chat_bubble_outline,
                            ),
                            if (model.supportsToolCalling)
                              _Chip(
                                label: 'Tool calling',
                                icon: Icons.build_outlined,
                                color: Colors.green,
                              ),
                            if (!gpuSupported &&
                                model.sizeBytes >
                                    _EmbeddedModelPickerWidgetState
                                        ._cpuSizeWarnBytes)
                              _Chip(
                                label: 'May not load on CPU',
                                icon: Icons.warning_amber_rounded,
                                color: theme.colorScheme.error,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isDownloaded && !isDownloading) ...[
                        if (model.url.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.download_outlined),
                            tooltip: 'Download model',
                            onPressed: onDownload,
                          ),
                        if (onRemoveFromList != null)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Remove from list',
                            onPressed: onRemoveFromList,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                      ] else if (isDownloading)
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          tooltip: 'Cancel download',
                          onPressed: onCancelDownload,
                        )
                      else if (onDelete != null)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Delete model',
                          onPressed: onDelete,
                        ),
                    ],
                  ),
                ],
              ),
              if (isDownloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: downloadProgress,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  downloadProgress != null
                      ? 'Downloading… ${(downloadProgress! * 100).toStringAsFixed(0)}%'
                      : 'Starting…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (selectedButMissing) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Selected in settings, but not downloaded yet. Download is required before use.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isDownloaded && !isDownloading) ...[
                const SizedBox(height: 8),
                if (onGpuLayersChanged != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.memory_outlined,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'GPU layers:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('CPU'),
                          icon: Icon(Icons.computer, size: 13),
                        ),
                        ButtonSegment(
                          value: 32,
                          label: Text('Partial'),
                          icon: Icon(Icons.auto_fix_high, size: 13),
                        ),
                        ButtonSegment(
                          value: 99,
                          label: Text('Full GPU'),
                          icon: Icon(Icons.bolt, size: 13),
                        ),
                      ],
                      selected: {
                        gpuLayers == 0
                            ? 0
                            : gpuLayers <= 32
                            ? 32
                            : 99,
                      },
                      onSelectionChanged: isAppLoaded || isAppLoading
                          ? null
                          : (s) {
                              final v = s.first;
                              if (v != 0 && !gpuSupported) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'GPU acceleration is not supported on this device — using CPU only.',
                                    ),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                                onGpuLayersChanged!(0);
                              } else {
                                onGpuLayersChanged!(v);
                              }
                            },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 11),
                        ),
                        iconSize: WidgetStateProperty.all(13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (gpuLayers > 0 && !gpuSupported)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'GPU not supported on this device — model will run on CPU.',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (gpuLayers > 0 &&
                      vramFreeBytes > 0 &&
                      model.sizeBytes > vramFreeBytes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Model (~${(model.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB) may exceed available GPU memory (~${(vramFreeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB free). Consider CPU or Partial GPU.',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                Row(
                  children: [
                    if (isAppLoaded) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.memory,
                              size: 12,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.get('modelLoadedInApp'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (onUnloadFromApp != null)
                        OutlinedButton.icon(
                          onPressed: onUnloadFromApp,
                          icon: const Icon(Icons.memory_outlined, size: 14),
                          label: Text(l10n.get('unloadModel')),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ] else if (isAppLoading) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value:
                                  (appLoadProgress == null ||
                                      appLoadProgress == 0.0)
                                  ? null
                                  : appLoadProgress,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (appLoadProgress != null &&
                                      appLoadProgress! > 0.0)
                                  ? '${l10n.get('loadingModelIntoApp')} (${(appLoadProgress! * 100).round()}%)'
                                  : l10n.get('loadingModelIntoApp'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (onLoadToApp != null) ...[
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onLoadToApp,
                        icon: const Icon(Icons.memory, size: 14),
                        label: Text(
                          l10n
                              .get('loadingModelIntoApp')
                              .replaceAll(RegExp(r'\.\.\.$'), ''),
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          backgroundColor: theme.colorScheme.primary,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _Chip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
