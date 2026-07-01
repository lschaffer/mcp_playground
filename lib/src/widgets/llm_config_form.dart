import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models.dart';
import '../../llm_service.dart';
import 'embedded_llm/embedded_model_picker_widget.dart';

/// Reusable widget for base LLM configuration: Provider, Model (with autocomplete),
/// API Key, Base URL, Fetch/Refresh Models button, and Test Connection button.
class LlmConfigForm extends StatefulWidget {
  final LlmProvider provider;
  final ValueChanged<LlmProvider> onProviderChanged;
  final TextEditingController modelCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController baseUrlCtrl;

  const LlmConfigForm({
    super.key,
    required this.provider,
    required this.onProviderChanged,
    required this.modelCtrl,
    required this.apiKeyCtrl,
    required this.baseUrlCtrl,
  });

  @override
  State<LlmConfigForm> createState() => _LlmConfigFormState();
}

class _LlmConfigFormState extends State<LlmConfigForm> {
  bool _fetchingModels = false;
  bool _testingLlm = false;
  List<String> _fetchedModels = [];

  final Map<LlmProvider, List<String>> _defaultModels = const {
    LlmProvider.openai: ['gpt-4o', 'gpt-4o-mini', 'o1-mini', 'o3-mini'],
    LlmProvider.claude: [
      'claude-3-5-sonnet-latest',
      'claude-3-5-haiku-latest',
      'claude-3-opus-latest',
    ],
    LlmProvider.gemini: [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash-thinking-exp',
    ],
    LlmProvider.mistral: [
      'mistral-large-latest',
      'pixtral-large-latest',
      'codestral-latest',
      'open-mixtral-8x22b',
    ],
    LlmProvider.ollama: [],
    LlmProvider.openaiCompatible: [],
  };

  bool get showBaseUrl {
    return widget.provider == LlmProvider.ollama ||
        widget.provider == LlmProvider.openaiCompatible ||
        widget.provider == LlmProvider.mistral;
  }

  Future<void> _testLlmConnection() async {
    setState(() => _testingLlm = true);

    try {
      final testConfig = LlmConfig(
        provider: widget.provider,
        model: widget.modelCtrl.text.trim(),
        apiKey: widget.apiKeyCtrl.text.trim(),
        baseUrl: widget.baseUrlCtrl.text.trim(),
        temperature: 0.2,
        maxTokens: 10,
      );

      final response = await LLMService.generate(
        config: testConfig,
        messages: [
          ChatMessage(
            id: 'test-conn',
            role: ChatRole.user,
            content: 'Respond with the single word "OK" if you can hear me.',
            timestamp: DateTime.now(),
          ),
        ],
        tools: [],
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text('Connection Successful'),
              ),
            ],
          ),
          content: Text(
            'Provider responded! Model reply:\n\n"${response.text.trim()}"',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Connection Failed'),
              ),
            ],
          ),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testingLlm = false);
      }
    }
  }

  Future<void> _fetchAvailableModels() async {
    setState(() => _fetchingModels = true);
    try {
      final provider = widget.provider;
      final baseUrl = widget.baseUrlCtrl.text.trim();
      final apiKey = widget.apiKeyCtrl.text.trim();
      final List<String> list = [];

      if (provider == LlmProvider.ollama) {
        final base = (baseUrl.isEmpty ? 'http://localhost:11434' : baseUrl)
            .replaceAll(RegExp(r'/+$'), '');
        final tagsBase = base.endsWith('/api') ? base : '$base/api';
        final url = Uri.parse('$tagsBase/tags');
        final headers = apiKey.isNotEmpty
            ? {'Authorization': 'Bearer $apiKey'}
            : <String, String>{};
        final resp = await http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final fetched = (data['models'] as List<dynamic>? ?? [])
              .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          list.addAll(fetched);
        }
      } else {
        var resolvedBaseUrl = baseUrl;
        if (resolvedBaseUrl.isEmpty) {
          if (provider == LlmProvider.openai) {
            resolvedBaseUrl = 'https://api.openai.com/v1';
          } else if (provider == LlmProvider.mistral) {
            resolvedBaseUrl = 'https://api.mistral.ai/v1';
          }
        }
        if (resolvedBaseUrl.isNotEmpty) {
          final base = resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '');
          final url = Uri.parse('$base/models');
          final headers = {
            'Accept': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          };
          final resp = await http
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final fetched = (data['data'] as List<dynamic>? ?? [])
                .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
                .where((n) => n.isNotEmpty)
                .toList();
            list.addAll(fetched);
          }
        }
      }

      if (mounted) {
        setState(() {
          _fetchedModels = list;
          if (list.isNotEmpty && widget.modelCtrl.text.trim().isEmpty) {
            widget.modelCtrl.text = list.first;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _fetchingModels = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<LlmProvider>(
          key: ValueKey(widget.provider),
          initialValue: widget.provider,
          decoration: const InputDecoration(
            labelText: 'Provider',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: LlmProvider.values.where((p) {
            if (kIsWeb && p == LlmProvider.embedded) return false;
            return true;
          }).map((provider) {
            return DropdownMenuItem(
              value: provider,
              child: Text(provider.displayName),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              widget.onProviderChanged(val);
              setState(() {
                _fetchedModels = [];
                if (val == LlmProvider.gemini && widget.modelCtrl.text.isEmpty) {
                  widget.modelCtrl.text = 'gemini-2.5-flash';
                } else if (val == LlmProvider.openai && widget.modelCtrl.text.isEmpty) {
                  widget.modelCtrl.text = 'gpt-4o-mini';
                } else if (val == LlmProvider.claude && widget.modelCtrl.text.isEmpty) {
                  widget.modelCtrl.text = 'claude-3-5-sonnet-latest';
                } else if (val == LlmProvider.mistral && widget.modelCtrl.text.isEmpty) {
                  widget.modelCtrl.text = 'mistral-large-latest';
                }
              });
            }
          },
        ),
        if (widget.provider != LlmProvider.none && widget.provider != LlmProvider.embedded) ...[
          // Autocomplete for Model name
          Autocomplete<String>(
            initialValue: widget.modelCtrl.value,
            optionsBuilder: (textEditingValue) {
              final defaultOpts = _defaultModels[widget.provider] ?? [];
              final models = _fetchedModels.isNotEmpty ? _fetchedModels : defaultOpts;
              if (textEditingValue.text.isEmpty) {
                return models;
              }
              return models.where((m) => m.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
              if (controller.text != widget.modelCtrl.text) {
                controller.text = widget.modelCtrl.text;
              }
              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (value) {
                  widget.modelCtrl.text = value;
                },
                decoration: const InputDecoration(
                  labelText: 'Model Name',
                  hintText: 'Enter or select model name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Model name is required' : null,
              );
            },
            onSelected: (v) {
              widget.modelCtrl.text = v;
            },
          ),

          // API Key
          TextFormField(
            controller: widget.apiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          // Base Endpoint Url (Visible for Ollama / Custom API / Mistral)
          if (showBaseUrl)
            TextFormField(
              controller: widget.baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base Endpoint URL (optional)',
                hintText: 'e.g. http://localhost:11434/api',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

          // Action Buttons: Fetch and Test
          Row(
            spacing: 12,
            children: [
              if (widget.provider == LlmProvider.ollama ||
                  widget.provider == LlmProvider.openai ||
                  widget.provider == LlmProvider.mistral ||
                  widget.provider == LlmProvider.openaiCompatible)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _fetchingModels ? null : _fetchAvailableModels,
                    icon: _fetchingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: Text(
                      _fetchedModels.isEmpty
                          ? 'Fetch Available Models'
                          : 'Refresh Models (${_fetchedModels.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingLlm ? null : _testLlmConnection,
                  icon: _testingLlm
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: const Text(
                    'Test Connection',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (widget.provider == LlmProvider.embedded) ...[
          EmbeddedModelPickerWidget(
            selectedFilename: widget.modelCtrl.text,
            onFilenameSelected: (val) {
              widget.modelCtrl.text = val;
            },
          ),
        ],
      ],
    );
  }
}

/// Reusable advanced settings widget matching layout of Image 2 & 3.
/// Renders Temperature, Max Tokens, Max Tool Output Size, Token Warning Threshold,
/// and hyperparameters (Top K, Top P, Repeat Penalty, Seed) with tooltips,
/// plus switches for Thinking capabilities and flags.
class LlmAdvancedSettingsForm extends StatelessWidget {
  final TextEditingController tempCtrl;
  final TextEditingController maxTokensCtrl;
  final TextEditingController maxToolOutputSizeCtrl;
  final TextEditingController tokenWarningThresholdCtrl;
  final TextEditingController topKCtrl;
  final TextEditingController topPCtrl;
  final TextEditingController repeatPenaltyCtrl;
  final TextEditingController seedCtrl;

  final bool thinking;
  final ValueChanged<bool> onThinkingChanged;
  final bool isSlm;
  final ValueChanged<bool> onIsSlmChanged;
  final bool isMultiModal;
  final ValueChanged<bool> onIsMultiModalChanged;
  final bool useNativeToolCall;
  final ValueChanged<bool> onUseNativeToolCallChanged;

  const LlmAdvancedSettingsForm({
    super.key,
    required this.tempCtrl,
    required this.maxTokensCtrl,
    required this.maxToolOutputSizeCtrl,
    required this.tokenWarningThresholdCtrl,
    required this.topKCtrl,
    required this.topPCtrl,
    required this.repeatPenaltyCtrl,
    required this.seedCtrl,
    required this.thinking,
    required this.onThinkingChanged,
    required this.isSlm,
    required this.onIsSlmChanged,
    required this.isMultiModal,
    required this.onIsMultiModalChanged,
    required this.useNativeToolCall,
    required this.onUseNativeToolCallChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: tempCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Temperature',
                  hintText: '0.0 - 2.0 (e.g. 0.2)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.thermostat_outlined),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final d = double.tryParse(v.trim());
                  if (d == null) return 'Invalid decimal';
                  if (d < 0.0 || d > 2.0) return 'Must be 0.0 - 2.0';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: maxTokensCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Tokens',
                  hintText: '0 = default',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.data_usage),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 0) return 'Must be >= 0';
                  return null;
                },
              ),
            ),
          ],
        ),
        TextFormField(
          controller: maxToolOutputSizeCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Max Tool Output Size (chars)',
            hintText: '0 = unlimited',
            helperText: 'Limit tool output size (0 = unlimited)',
            helperStyle: TextStyle(fontSize: 10, color: Colors.grey),
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.build_circle_outlined),
            isDense: true,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final n = int.tryParse(v.trim());
            if (n == null || n < 0) return 'Must be >= 0';
            return null;
          },
        ),
        TextFormField(
          controller: tokenWarningThresholdCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Token Warning Threshold',
            hintText: 'e.g. 1500000',
            helperText: 'Cleanup suggestion after this many tokens',
            helperStyle: TextStyle(fontSize: 10, color: Colors.grey),
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.warning_amber_outlined),
            isDense: true,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final n = int.tryParse(v.trim());
            if (n == null || n < 0) return 'Must be >= 0';
            return null;
          },
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                label: 'Top K',
                tooltip: 'Limits vocabulary to the top-K tokens at each step. Lower = more deterministic. Range: 1–100.',
                hint: '40',
                controller: topKCtrl,
                isInt: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                label: 'Top P',
                tooltip: 'Nucleus sampling cutoff. Lower = more focused output. Range: 0.0–1.0.',
                hint: '0.9',
                controller: topPCtrl,
                isDecimal: true,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                label: 'Repeat Penalty',
                tooltip: 'Penalizes repeating tokens. Values > 1.0 reduce repetition. Range: 0.5–2.0.',
                hint: '1.1',
                controller: repeatPenaltyCtrl,
                isDecimal: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                label: 'Seed',
                tooltip: 'Random seed for reproducible outputs. Leave empty for random.',
                hint: '42',
                controller: seedCtrl,
                isInt: true,
              ),
            ),
          ],
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Thinking / Reasoning capabilities', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          subtitle: const Text(
            'Allow the model to emit internal thinking/reasoning tokens (e.g. <think> blocks, QwQ, DeepSeek-R1). Disable to suppress thinking output and reduce token usage.',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          value: thinking,
          onChanged: (v) => onThinkingChanged(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Small Language Model (SLM)', style: TextStyle(fontSize: 12)),
          subtitle: const Text('Enforce short and simple warmup instructions', style: TextStyle(fontSize: 10, color: Colors.grey)),
          value: isSlm,
          onChanged: (v) => onIsSlmChanged(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Multi-modal features enabled', style: TextStyle(fontSize: 12)),
          value: isMultiModal,
          onChanged: (v) => onIsMultiModalChanged(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Native tool calls supported', style: TextStyle(fontSize: 12)),
          value: useNativeToolCall,
          onChanged: (v) => onUseNativeToolCallChanged(v),
        ),
      ],
    );
  }

  static Widget _field({
    required String label,
    required String tooltip,
    required TextEditingController controller,
    String? hint,
    bool isInt = false,
    bool isDecimal = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.tap,
          child: const Icon(Icons.info_outline, size: 16),
        ),
      ),
      keyboardType: isInt
          ? TextInputType.number
          : (isDecimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (isInt) {
          final n = int.tryParse(v.trim());
          if (n == null) return 'Invalid integer';
        }
        if (isDecimal) {
          final d = double.tryParse(v.trim());
          if (d == null) return 'Invalid decimal';
        }
        return null;
      },
    );
  }
}
