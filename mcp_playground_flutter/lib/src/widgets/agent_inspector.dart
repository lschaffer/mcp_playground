import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_playground_dart/mcp_playground_dart.dart';
import '../../playground_controller.dart';

class ModelTokenPrice {
  final double inputPer1MUsd;
  final double outputPer1MUsd;

  const ModelTokenPrice({
    required this.inputPer1MUsd,
    required this.outputPer1MUsd,
  });
}

const Map<String, Map<String, ModelTokenPrice>> _modelPricingByProvider = {
  'gemini': {
    'gemini-2.5-flash': ModelTokenPrice(
      inputPer1MUsd: 0.15,
      outputPer1MUsd: 0.60,
    ),
    'gemini-1.5-flash': ModelTokenPrice(
      inputPer1MUsd: 0.075,
      outputPer1MUsd: 0.30,
    ),
    'gemini-1.5-pro': ModelTokenPrice(
      inputPer1MUsd: 1.25,
      outputPer1MUsd: 5.00,
    ),
    'gemini-2.0-flash-exp': ModelTokenPrice(
      inputPer1MUsd: 0.15,
      outputPer1MUsd: 0.60,
    ),
    'gemini-2.0-flash-thinking-exp': ModelTokenPrice(
      inputPer1MUsd: 0.15,
      outputPer1MUsd: 0.60,
    ),
  },
  'mistral': {
    'mistral-large-latest': ModelTokenPrice(
      inputPer1MUsd: 0.50,
      outputPer1MUsd: 1.50,
    ),
    'mistral-large': ModelTokenPrice(inputPer1MUsd: 0.50, outputPer1MUsd: 1.50),
    'mistral-medium-latest': ModelTokenPrice(
      inputPer1MUsd: 0.40,
      outputPer1MUsd: 2.00,
    ),
    'mistral-medium': ModelTokenPrice(
      inputPer1MUsd: 0.40,
      outputPer1MUsd: 2.00,
    ),
    'mistral-small-latest': ModelTokenPrice(
      inputPer1MUsd: 0.10,
      outputPer1MUsd: 0.30,
    ),
    'mistral-small': ModelTokenPrice(inputPer1MUsd: 0.10, outputPer1MUsd: 0.30),
  },
  'openai': {
    'gpt-4o': ModelTokenPrice(inputPer1MUsd: 2.50, outputPer1MUsd: 10.00),
    'gpt-4o-mini': ModelTokenPrice(inputPer1MUsd: 0.150, outputPer1MUsd: 0.600),
    'gpt-4-turbo': ModelTokenPrice(inputPer1MUsd: 10.00, outputPer1MUsd: 30.00),
    'gpt-3.5-turbo': ModelTokenPrice(inputPer1MUsd: 0.50, outputPer1MUsd: 1.50),
  },
  'claude': {
    'claude-3-5-sonnet-latest': ModelTokenPrice(
      inputPer1MUsd: 3.00,
      outputPer1MUsd: 15.00,
    ),
    'claude-3-5-sonnet': ModelTokenPrice(
      inputPer1MUsd: 3.00,
      outputPer1MUsd: 15.00,
    ),
    'claude-3-5-haiku-latest': ModelTokenPrice(
      inputPer1MUsd: 0.80,
      outputPer1MUsd: 4.00,
    ),
    'claude-3-5-haiku': ModelTokenPrice(
      inputPer1MUsd: 0.80,
      outputPer1MUsd: 4.00,
    ),
    'claude-3-opus-latest': ModelTokenPrice(
      inputPer1MUsd: 15.00,
      outputPer1MUsd: 75.00,
    ),
  },
};

// ── Live-price cache (session-scoped) ─────────────────────────────────────────

class _CachedModelPrice {
  final ModelTokenPrice price;
  final DateTime fetchedAt;
  final bool isLive; // true = fetched from OpenRouter, false = static fallback
  const _CachedModelPrice({
    required this.price,
    required this.fetchedAt,
    this.isLive = false,
  });
}

const Duration _livePriceTtl = Duration(hours: 12);
const Duration _openRouterModelsTtl = Duration(minutes: 30);
final Map<String, _CachedModelPrice> _liveModelPricingCache = {};
List<dynamic>? _openRouterModelsCache;
DateTime? _openRouterModelsFetchedAt;

String _normModel(String m) => m.trim().toLowerCase();
String _priceCacheKey(String providerKey, String model) =>
    '${providerKey.trim().toLowerCase()}:${_normModel(model)}';

_CachedModelPrice? _getCachedLivePrice(String providerKey, String model) {
  final key = _priceCacheKey(providerKey, model);
  final cached = _liveModelPricingCache[key];
  if (cached == null) return null;
  if (DateTime.now().difference(cached.fetchedAt) > _livePriceTtl) return null;
  return cached;
}

void _cacheLivePrice(
  String providerKey,
  String model,
  ModelTokenPrice price, {
  bool isLive = false,
}) {
  final now = DateTime.now();
  final key = _priceCacheKey(providerKey, model);
  final entry = _CachedModelPrice(price: price, fetchedAt: now, isLive: isLive);
  _liveModelPricingCache[key] = entry;
  // Also cache with/without -latest alias
  final nm = _normModel(model);
  if (nm.endsWith('-latest')) {
    _liveModelPricingCache[_priceCacheKey(
          providerKey,
          nm.substring(0, nm.length - 7),
        )] =
        entry;
  } else {
    _liveModelPricingCache[_priceCacheKey(providerKey, '$nm-latest')] = entry;
  }
}

Future<List<dynamic>?> _loadOpenRouterModels() async {
  if (_openRouterModelsCache != null &&
      _openRouterModelsFetchedAt != null &&
      DateTime.now().difference(_openRouterModelsFetchedAt!) <=
          _openRouterModelsTtl) {
    return _openRouterModelsCache;
  }
  try {
    final response = await http
        .get(Uri.parse('https://openrouter.ai/api/v1/models'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    if (data is! List<dynamic>) return null;
    _openRouterModelsCache = data;
    _openRouterModelsFetchedAt = DateTime.now();
    return data;
  } catch (_) {
    return null;
  }
}

bool _matchesProviderForModel({
  required String providerKey,
  required String idLower,
  required String nameLower,
}) {
  switch (providerKey) {
    case 'openai':
      return idLower.startsWith('openai/') ||
          idLower.contains('gpt') ||
          nameLower.contains('openai');
    case 'claude':
      return idLower.startsWith('anthropic/') ||
          idLower.contains('claude') ||
          nameLower.contains('claude');
    case 'mistral':
      return idLower.startsWith('mistral-ai/') ||
          idLower.startsWith('mistralai/') ||
          idLower.contains('mistral');
    case 'gemini':
      return idLower.startsWith('google/') ||
          idLower.contains('gemini') ||
          nameLower.contains('gemini');
    default:
      return true;
  }
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

double _toPer1M(double value) => value <= 0.01 ? value * 1000000.0 : value;

Future<ModelTokenPrice?> _fetchOpenRouterLivePrice({
  required String providerKey,
  required String normalizedModel,
}) async {
  final models = await _loadOpenRouterModels();
  if (models == null || models.isEmpty) return null;

  final baseModel = normalizedModel.endsWith('-latest')
      ? normalizedModel.substring(0, normalizedModel.length - 7)
      : normalizedModel;

  ModelTokenPrice? bestPrice;
  var bestScore = -1;

  for (final raw in models) {
    if (raw is! Map<String, dynamic>) continue;
    final idLower = (raw['id'] ?? '').toString().trim().toLowerCase();
    final nameLower = (raw['name'] ?? '').toString().trim().toLowerCase();
    if (idLower.isEmpty) {
      continue;
    }
    if (!_matchesProviderForModel(
      providerKey: providerKey,
      idLower: idLower,
      nameLower: nameLower,
    )) {
      continue;
    }

    final shortModel = idLower.contains('/')
        ? idLower.split('/').last
        : idLower;
    var score = 0;
    if (shortModel == normalizedModel) {
      score += 120;
    } else if (shortModel == baseModel) {
      score += 110;
    } else if (shortModel.startsWith('$baseModel-') ||
        shortModel.contains(baseModel)) {
      score += 80;
    } else if (nameLower.contains(baseModel)) {
      score += 60;
    } else {
      continue;
    }
    if (idLower.startsWith('$providerKey/')) {
      score += 30;
    }

    final pricing = raw['pricing'];
    if (pricing is! Map<String, dynamic>) {
      continue;
    }
    final promptRaw = _parseDouble(pricing['prompt'] ?? pricing['input']);
    final completionRaw = _parseDouble(
      pricing['completion'] ?? pricing['output'],
    );
    if (promptRaw == null || completionRaw == null) {
      continue;
    }

    final candidate = ModelTokenPrice(
      inputPer1MUsd: _toPer1M(promptRaw),
      outputPer1MUsd: _toPer1M(completionRaw),
    );
    if (score > bestScore) {
      bestScore = score;
      bestPrice = candidate;
    }
  }
  return bestPrice;
}

Future<ModelTokenPrice?> refreshModelTokenPrice({
  required String providerKey,
  required String model,
}) async {
  final np = providerKey.trim().toLowerCase();
  final nm = _normModel(model);
  if (np.isEmpty || nm.isEmpty) return null;
  if (np == 'ollama' ||
      np == 'openai_compatible' ||
      np == 'embedded' ||
      np == 'none') {
    return null;
  }
  try {
    final fetched = await _fetchOpenRouterLivePrice(
      providerKey: np,
      normalizedModel: nm,
    );
    if (fetched != null) {
      _cacheLivePrice(np, nm, fetched, isLive: true);
      return fetched;
    }
  } catch (_) {}
  return _getModelTokenPrice2(np, nm);
}

ModelTokenPrice? _getModelTokenPrice2(
  String providerKey,
  String normalizedModel,
) {
  final cached = _getCachedLivePrice(providerKey, normalizedModel);
  if (cached != null) return cached.price;
  final providerModels = _modelPricingByProvider[providerKey];
  if (providerModels == null) return null;
  if (providerModels.containsKey(normalizedModel)) {
    return providerModels[normalizedModel];
  }
  for (final entry in providerModels.entries) {
    if (normalizedModel.startsWith(entry.key) ||
        entry.key.startsWith(normalizedModel)) {
      return entry.value;
    }
  }
  return null;
}

ModelTokenPrice? _getModelTokenPrice(LlmProvider provider, String model) {
  final normalizedModel = model.trim().toLowerCase();
  String providerKey = '';
  switch (provider) {
    case LlmProvider.gemini:
      providerKey = 'gemini';
      break;
    case LlmProvider.mistral:
      providerKey = 'mistral';
      break;
    case LlmProvider.openai:
      providerKey = 'openai';
      break;
    case LlmProvider.claude:
      providerKey = 'claude';
      break;
    case LlmProvider.openaiCompatible:
      if (normalizedModel.contains('mistral')) {
        providerKey = 'mistral';
      } else {
        providerKey = 'openai';
      }
      break;
    case LlmProvider.embedded:
    case LlmProvider.ollama:
    case LlmProvider.none:
      return null;
  }

  // Check live cache first, then fall back to static map
  final cached = _getCachedLivePrice(providerKey, normalizedModel);
  if (cached != null) return cached.price;
  return _getModelTokenPrice2(providerKey, normalizedModel);
}

class AgentInspector extends StatefulWidget {
  final PlaygroundController controller;

  const AgentInspector({super.key, required this.controller});

  @override
  State<AgentInspector> createState() => _AgentInspectorState();
}

class _AgentInspectorState extends State<AgentInspector> {
  bool _logsAscending = true;
  DateTime? _logsClearedAt;
  bool _priceIsLive = false;

  @override
  void initState() {
    super.initState();
    _refreshPriceAsync();
  }

  @override
  void didUpdateWidget(AgentInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConfig = oldWidget.controller.activeLlmConfig;
    final newConfig = widget.controller.activeLlmConfig;
    if (oldConfig.provider != newConfig.provider ||
        oldConfig.model != newConfig.model) {
      _refreshPriceAsync();
    }
  }

  void _refreshPriceAsync() {
    final config = widget.controller.activeLlmConfig;
    final providerKey = switch (config.provider) {
      LlmProvider.gemini => 'gemini',
      LlmProvider.mistral => 'mistral',
      LlmProvider.openai => 'openai',
      LlmProvider.claude => 'claude',
      LlmProvider.openaiCompatible =>
        config.model.toLowerCase().contains('mistral') ? 'mistral' : 'openai',
      _ => '',
    };
    if (providerKey.isEmpty || config.model.isEmpty) return;
    refreshModelTokenPrice(providerKey: providerKey, model: config.model).then((
      price,
    ) {
      if (!mounted) return;
      final cached = _getCachedLivePrice(providerKey, _normModel(config.model));
      setState(() => _priceIsLive = cached?.isLive ?? false);
    });
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$hour:$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final config = widget.controller.activeLlmConfig;
    final messages = widget.controller.messages;

    // Calculate stats
    int toolCallsCount = 0;
    int sentCharsCount = 0;
    int receivedCharsCount = 0;

    if (widget.controller.systemPrompt.isNotEmpty) {
      sentCharsCount += widget.controller.systemPrompt.length;
    }

    for (final m in messages) {
      if (m.type == MessageType.toolCall) {
        toolCallsCount++;
      }
      if (m.role == ChatRole.user) {
        sentCharsCount += m.content.length;
      } else if (m.role == ChatRole.tool) {
        sentCharsCount += m.content.length;
      } else if (m.role == ChatRole.assistant) {
        if (m.type != MessageType.toolCall) {
          receivedCharsCount += m.content.length;
        }
      }
    }

    final estInputTokens = (sentCharsCount / 3.8).round();
    final estOutputTokens = (receivedCharsCount / 3.8).round();
    final estTotalTokens = estInputTokens + estOutputTokens;
    final tokenProgress = (estTotalTokens / 100000.0).clamp(0.0, 1.0);

    // Build log entries
    final entries = <_LogEntry>[];
    for (final msg in messages) {
      if (_logsClearedAt != null && !msg.timestamp.isAfter(_logsClearedAt!)) {
        continue;
      }
      switch (msg.role) {
        case ChatRole.system:
          final content = msg.content.trim();
          if (content.isNotEmpty) {
            final oneLine = content.replaceAll('\n', ' ');
            final preview = oneLine.length > 80
                ? '${oneLine.substring(0, 80)}...'
                : oneLine;
            entries.add(
              _LogEntry(
                type: 'system',
                text: 'System prompt: $preview',
                details: content,
                timestamp: msg.timestamp,
              ),
            );
          }
          break;
        case ChatRole.user:
          final content = msg.content.trim();
          if (content.isNotEmpty) {
            entries.add(
              _LogEntry(
                type: 'user',
                text: 'User prompt: $content',
                details: content.length > 80 ? content : null,
                timestamp: msg.timestamp,
              ),
            );
          }
          break;
        case ChatRole.assistant:
          final content = msg.content.trim();
          if (content.isNotEmpty) {
            if (msg.type == MessageType.toolCall) {
              final argsRaw = msg.toolArguments != null
                  ? jsonEncode(msg.toolArguments)
                  : '';
              final argsPreview = argsRaw.length > 100
                  ? '${argsRaw.substring(0, 100)}...'
                  : argsRaw;
              final toolText = argsPreview.isNotEmpty
                  ? 'Called tool: ${msg.toolName}($argsPreview)'
                  : 'Called tool: ${msg.toolName ?? 'Tool'}';
              entries.add(
                _LogEntry(
                  type: 'tool_call',
                  text: toolText,
                  details: argsRaw.isNotEmpty ? argsRaw : null,
                  timestamp: msg.timestamp,
                ),
              );
            } else {
              final oneLine = content.replaceAll('\n', ' ');
              final preview = oneLine.length > 80
                  ? '${oneLine.substring(0, 80)}...'
                  : oneLine;
              entries.add(
                _LogEntry(
                  type: 'assistant',
                  text: preview,
                  details: content.length > 80 ? content : null,
                  timestamp: msg.timestamp,
                ),
              );
            }
          }
          break;
        case ChatRole.tool:
          final resultText = msg.content.trim();
          final oneLine = resultText.replaceAll('\n', ' ');
          final resultPreview = oneLine.length > 150
              ? '${oneLine.substring(0, 150)}...'
              : oneLine;
          final displayText = resultPreview.isNotEmpty
              ? '→ $resultPreview'
              : 'Executed.';
          entries.add(
            _LogEntry(
              type: 'tool_response',
              text: displayText,
              details: resultText.isNotEmpty ? resultText : null,
              timestamp: msg.timestamp,
            ),
          );
          break;
      }
    }

    final displayEntries = _logsAscending ? entries : entries.reversed.toList();

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text(
                  'Agent Inspector',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.controller.isGenerating
                        ? Colors.green
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.controller.isGenerating ? 'Processing' : 'Idle',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active Model Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Model',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            config.model.isNotEmpty
                                ? config.model
                                : 'No Model selected',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Provider: ${config.provider.displayName}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Token Usage Card
                  () {
                    final price = _getModelTokenPrice(
                      config.provider,
                      config.model,
                    );
                    final showCost =
                        price != null &&
                        config.provider != LlmProvider.ollama &&
                        config.provider != LlmProvider.none;
                    double estCost = 0.0;
                    if (showCost) {
                      estCost =
                          (estInputTokens / 1000000.0) * price.inputPer1MUsd +
                          (estOutputTokens / 1000000.0) * price.outputPer1MUsd;
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Est. Token Usage',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  '$estTotalTokens / 100000',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: tokenProgress,
                              color: const Color(0xFF7C3AED),
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            if (showCost) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Price/1M: \$${price.inputPer1MUsd.toStringAsFixed(2)} in / \$${price.outputPer1MUsd.toStringAsFixed(2)} out',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 11,
                                                ),
                                          ),
                                        ),
                                        if (_priceIsLive) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(
                                                alpha: 0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.green.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                            child: const Text(
                                              'live',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.green,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Est. Cost: \$${estCost.toStringAsFixed(5)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF7C3AED),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }(),
                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tool Calls',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$toolCallsCount',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sent Chars',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$sentCharsCount',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Live Execution Logs
                  Row(
                    children: [
                      Text(
                        'Live Execution Logs',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _logsAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                        ),
                        tooltip: _logsAscending ? 'Ascending' : 'Descending',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _logsAscending = !_logsAscending;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear_all),
                        tooltip: 'Clear logs',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _logsClearedAt = DateTime.now();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: displayEntries.isEmpty
                            ? const Center(
                                child: Text(
                                  'No execution logs.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8.0),
                                itemCount: displayEntries.length,
                                itemBuilder: (ctx, idx) {
                                  final entry = displayEntries[idx];
                                  IconData icon = Icons.info_outline;
                                  Color iconColor = Colors.grey;

                                  if (entry.type == 'system') {
                                    icon = Icons.security;
                                    iconColor = Colors.orange;
                                  } else if (entry.type == 'user') {
                                    icon = Icons.person;
                                    iconColor = const Color(0xFF7C3AED);
                                  } else if (entry.type == 'tool_call') {
                                    icon = Icons.build;
                                    iconColor = Colors.amber;
                                  } else if (entry.type == 'tool_response') {
                                    icon = Icons.check_circle;
                                    iconColor = Colors.green;
                                  } else if (entry.type == 'assistant') {
                                    icon = Icons.smart_toy;
                                    iconColor = Colors.blue;
                                  }
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      icon,
                                      size: 16,
                                      color: iconColor,
                                    ),
                                    title: Text(
                                      entry.text,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    subtitle: Text(
                                      _formatTimestamp(entry.timestamp),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    trailing: entry.details != null
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.open_in_full,
                                              size: 14,
                                            ),
                                            tooltip: 'Expand log details',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: Text(
                                                    entry.type == 'system'
                                                        ? 'System Prompt'
                                                        : 'Log Details',
                                                  ),
                                                  content:
                                                      SingleChildScrollView(
                                                        child: SelectableText(
                                                          entry.details!,
                                                          style:
                                                              const TextStyle(
                                                                fontFamily:
                                                                    'monospace',
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(c),
                                                      child: const Text(
                                                        'Close',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          )
                                        : null,
                                    onTap: entry.details != null
                                        ? () {
                                            showDialog(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                title: Text(
                                                  entry.type == 'system'
                                                      ? 'System Prompt'
                                                      : 'Log Details',
                                                ),
                                                content: SingleChildScrollView(
                                                  child: SelectableText(
                                                    entry.details!,
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c),
                                                    child: const Text('Close'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        : null,
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  final String type;
  final String text;
  final String? details;
  final DateTime timestamp;

  _LogEntry({
    required this.type,
    required this.text,
    this.details,
    required this.timestamp,
  });
}
