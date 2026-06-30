import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../models.dart';
import '../../playground_controller.dart';
import '../mcp_localizations.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final PlaygroundController? controller;

  const ChatBubble({super.key, required this.message, this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isSystem = message.role == ChatRole.system;

    if (controller?.messageContentBuilder != null) {
      final customWidget = controller!.messageContentBuilder!(context, message);
      if (customWidget != null) {
        return customWidget;
      }
    }

    if (message.type == MessageType.toolCall) {
      return _buildToolCallBubble(context, theme);
    }

    if (message.type == MessageType.toolResponse && message.toolResult != null) {
      return _buildToolResponseBubble(context, theme);
    }

    if (isSystem || message.type == MessageType.log) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.primaryContainer,
              radius: 16,
              child: Icon(Icons.smart_toy_outlined, size: 18, color: isDark ? Colors.white : theme.colorScheme.onPrimaryContainer),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isUser
                    ? (isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.15) : const Color(0xFF7C3AED).withValues(alpha: 0.08))
                    : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUser
                      ? (isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.35) : const Color(0xFF7C3AED).withValues(alpha: 0.2))
                      : (isDark ? Colors.white10 : Colors.black12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isHtmlContent(message.content))
                    _buildTextContent(context, message.content, theme)
                  else
                    _buildMarkdownWithEmbeddedDataUris(context, message.content, theme),
                  if (message.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: message.content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.content_copy_outlined,
                                  size: 13,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              backgroundColor: isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.3) : theme.colorScheme.primary,
              radius: 16,
              child: Icon(Icons.person_outline, size: 18, color: isDark ? Colors.white : theme.colorScheme.onPrimary),
            ),
        ],
      ),
    );
  }

  Widget _buildToolCallBubble(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: ExpansionTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.amber.withValues(alpha: 0.15),
          radius: 14,
          child: const Icon(Icons.build_outlined, size: 14, color: Colors.amber),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Tool Execution Call: ${message.toolName}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              tooltip: 'Copy arguments',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final argsStr = const JsonEncoder.withIndent('  ').convert(message.toolArguments ?? {});
                Clipboard.setData(ClipboardData(text: argsStr));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Arguments copied to clipboard.')),
                );
              },
            ),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: theme.colorScheme.surfaceContainerLowest,
            child: Text(
              const JsonEncoder.withIndent('  ').convert(message.toolArguments ?? {}),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          )
        ],
      ),
    );
  }

  void _showFullScreenOutput(BuildContext context, String text) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.code, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Tool Output',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                      },
                      tooltip: 'Copy',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolResponseBubble(BuildContext context, ThemeData theme) {
    final contents = message.toolResult?.content ?? [];
    final isError = message.toolResult?.isError ?? false;
    final textLength = contents.fold(0, (sum, c) => sum + (c.text?.length ?? 0));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: isError ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isError ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          dense: true,
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
          iconColor: isError ? Colors.red[700] : Colors.green[700],
          collapsedIconColor: isError ? Colors.red[700] : Colors.green[700],
          leading: CircleAvatar(
            backgroundColor: isError ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
            radius: 14,
            child: Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 14,
              color: isError ? Colors.red : Colors.green,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isError ? 'Tool Error: ${message.toolName}' : 'Tool Result: ${message.toolName}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isError ? Colors.red[700] : Colors.green[700],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$textLength chars',
                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contents.map((c) {
                if (c.type == 'image' || c.mimeType?.startsWith('image/') == true) {
                  return _buildImageContent(context, c.data ?? c.text ?? '', c.mimeType, theme);
                } else {
                  return _buildTextContent(context, c.text ?? '', theme);
                }
              }).toList(),
            ),
          )
        ],
      ),
    ),
  );
}

  Future<void> _downloadImage(BuildContext context, Uint8List bytes, String? mimeType) async {
    try {
      final isMobile = !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS);
      final extension = mimeType != null && mimeType.contains('/')
          ? mimeType.split('/').last
          : 'png';
      final fileName = 'generated_image.$extension';

      final resultPath = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: isMobile ? bytes : null,
      );

      if (resultPath != null) {
        if (!kIsWeb && !isMobile) {
          final file = io.File(resultPath);
          await file.writeAsBytes(bytes);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image saved successfully.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(BuildContext context, Uint8List bytes, String fileName) async {
    try {
      final isMobile = !kIsWeb && (io.Platform.isAndroid || io.Platform.isIOS);
      final extension = fileName.contains('.') ? fileName.split('.').last : 'bin';

      final resultPath = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: isMobile ? bytes : null,
      );

      if (resultPath != null) {
        if (!kIsWeb && !isMobile) {
          final file = io.File(resultPath);
          await file.writeAsBytes(bytes);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved successfully: $fileName')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save file: $e')),
        );
      }
    }
  }

  Widget _buildImageContent(BuildContext context, String base64Data, String? mimeType, ThemeData theme) {
    try {
      String cleanBase64 = base64Data.trim();
      if (cleanBase64.startsWith('data:')) {
        final commaIndex = cleanBase64.indexOf(',');
        if (commaIndex != -1) {
          cleanBase64 = cleanBase64.substring(commaIndex + 1);
        }
      }
      final bytes = base64Decode(cleanBase64);
      return Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image, size: 32, color: Colors.red),
                          const SizedBox(height: 8),
                          const Text('Failed to display image', style: TextStyle(color: Colors.red)),
                          if (mimeType != null) Text('MIME type: $mimeType', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              child: IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download Image',
                onPressed: () => _downloadImage(context, bytes, mimeType),
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Error decoding image: $e',
          style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
        ),
      );
    }
  }

  Widget _buildTextContent(BuildContext context, String text, ThemeData theme) {
    if (text.isEmpty) return const SizedBox.shrink();
    final l10n = McpPlaygroundLocalizations.of(context);

    final embeddedImages = _extractBase64Images(text);
    
    // Check if the text is JSON containing an embedded file
    Map<String, String>? embeddedFile;
    String strippedText = text;
    
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is Map) {
        final content = decoded['content'] ?? decoded['data'];
        final fileName = decoded['fileName'] ?? decoded['filename'];
        final mimeType = decoded['mimeType'] ?? decoded['mimetype'] ?? 'application/octet-stream';
        
        if (content is String && fileName is String && _looksLikeBase64String(content.trim().replaceAll(RegExp(r'\s+'), ''))) {
          embeddedFile = {
            'content': content.trim().replaceAll(RegExp(r'\s+'), ''),
            'fileName': fileName,
            'mimeType': mimeType.toString(),
          };
          
          // Create a copy and remove content/data keys to hide the base64 string in the UI
          final cleanMap = Map<String, dynamic>.from(decoded);
          cleanMap.remove('content');
          cleanMap.remove('data');
          
          if (cleanMap.isEmpty || (cleanMap.length == 2 && cleanMap.containsKey('fileName') && cleanMap.containsKey('mimeType'))) {
            strippedText = '';
          } else {
            strippedText = const JsonEncoder.withIndent('  ').convert(cleanMap);
          }
        } else {
          strippedText = _stripBase64Images(text);
        }
      } else {
        strippedText = _stripBase64Images(text);
      }
    } catch (_) {
      strippedText = _stripBase64Images(text);
    }

    if (strippedText.isEmpty) {
      final widgets = <Widget>[];
      if (embeddedImages.isNotEmpty) {
        widgets.addAll(embeddedImages.map((imgData) => _buildImageContent(context, imgData, 'image/png', theme)));
      }
      if (embeddedFile != null) {
        widgets.add(_buildEmbeddedFile(
          context,
          embeddedFile['content']!,
          embeddedFile['mimeType']!,
          embeddedFile['fileName']!,
          theme,
        ));
      }
      if (widgets.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      }
      return const SizedBox.shrink();
    }

    final isHtml = _isHtmlContent(strippedText);
    String processedText = strippedText;
    bool isFormatted = false;

    // Direct JSON check (only if not HTML)
    if (!isHtml) {
      try {
        final cleaned = strippedText.trim();
        final dynamic jsonData = jsonDecode(cleaned);
        processedText = const JsonEncoder.withIndent('  ').convert(jsonData);
        isFormatted = true;
      } catch (_) {
        // Not direct JSON
      }
    }

    final outputLines = processedText.split('\n');
    const maxPreviewLines = 15;
    const maxPreviewChars = 2000;
    final shouldTruncate = isHtml || outputLines.length > maxPreviewLines || processedText.length > maxPreviewChars;

    var previewText = processedText;
    if (shouldTruncate) {
      final limitedLines = outputLines.take(maxPreviewLines).join('\n');
      if (limitedLines.length > maxPreviewChars) {
        previewText = '${limitedLines.substring(0, maxPreviewChars)}\n...';
      } else {
        previewText = '$limitedLines\n...';
      }
    }

    final textWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHtml)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.html_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    l10n.get('htmlDocumentPreview'),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.zoom_in, size: 18, color: theme.colorScheme.primary),
                    onPressed: () => _showHtmlFullScreen(context, processedText),
                    tooltip: l10n.get('tapMagnifierTooltip'),
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            )
          else if (isFormatted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.code, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  const Text(
                    'JSON Format',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00ACC1)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.search, size: 18, color: Color(0xFF00ACC1)),
                    onPressed: () => _showFullScreenOutput(context, processedText),
                    tooltip: 'View full screen',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            )
          else if (shouldTruncate)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Preview (${outputLines.length} lines)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.search, size: 18, color: theme.colorScheme.primary),
                    onPressed: () => _showFullScreenOutput(context, processedText),
                    tooltip: 'View full screen',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          SelectableText(
            previewText,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );

    if (embeddedImages.isEmpty && embeddedFile == null) {
      return textWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        textWidget,
        const SizedBox(height: 8),
        ...embeddedImages.map((imgData) {
          return _buildImageContent(context, imgData, 'image/png', theme);
        }),
        if (embeddedFile != null)
          _buildEmbeddedFile(
            context,
            embeddedFile['content']!,
            embeddedFile['mimeType']!,
            embeddedFile['fileName']!,
            theme,
          ),
      ],
    );
  }

  String _stripBase64Images(String text) {
    var result = text;

    // 1. If the text itself is just a raw base64 string
    final cleanRaw = text.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanRaw.length > 100 && _looksLikeBase64String(cleanRaw)) {
      return '';
    }

    // 2. Try JSON replacement (if the text is JSON containing base64)
    try {
      final decoded = jsonDecode(text.trim());
      final strippedJson = _stripJsonImages(decoded);
      if (strippedJson == null) {
        return '';
      }
      return const JsonEncoder.withIndent('  ').convert(strippedJson);
    } catch (_) {
      // Not JSON
    }

    // 3. Fallback: regex search and replace base64 PNG block
    final regex = RegExp(r'(iVBORw0KGgo[a-zA-Z0-9+/=\s\r\n]{50,})');
    result = result.replaceAll(regex, '');

    // Also strip data:image/... URI pattern if it's there
    final dataUriRegex = RegExp(r'data:image/[^;]+;base64,[a-zA-Z0-9+/=\s\r\n]+');
    result = result.replaceAll(dataUriRegex, '');

    // Clean up empty JSON markdown code blocks
    result = result.replaceAll(RegExp(r'```json\s*```'), '');
    result = result.replaceAll(RegExp(r'```\s*```'), '');

    return result.trim();
  }

  bool _looksLikeBase64String(String str) {
    if (str.startsWith('iVBORw0KGgo') || str.startsWith('data:')) return true;
    final clean = str.replaceAll(RegExp(r'\s+'), '');
    if (clean.length < 50) return false;
    final hasBase64Chars = RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(clean);
    return hasBase64Chars;
  }

  dynamic _stripJsonImages(dynamic val) {
    if (val is String) {
      final clean = val.trim().replaceAll(RegExp(r'\s+'), '');
      if (clean.length > 100 && _looksLikeBase64String(clean)) {
        return null; // Strip this value
      }
      return val;
    } else if (val is Map) {
      final nextMap = <String, dynamic>{};
      for (final entry in val.entries) {
        final stripped = _stripJsonImages(entry.value);
        if (stripped != null) {
          nextMap[entry.key.toString()] = stripped;
        }
      }
      return nextMap.isEmpty ? null : nextMap;
    } else if (val is List) {
      final nextList = [];
      for (final item in val) {
        final stripped = _stripJsonImages(item);
        if (stripped != null) {
          nextList.add(stripped);
        }
      }
      return nextList.isEmpty ? null : nextList;
    }
    return val;
  }

  bool _isHtmlContent(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('```html') || lower.contains('```xml')) {
      return true;
    }
    if (lower.contains('<!doctype') || lower.contains('<! doctype')) {
      return true;
    }
    final hasHtmlOpen = lower.contains('<html');
    final hasHtmlClose = lower.contains('</html>');
    if (hasHtmlOpen && hasHtmlClose) {
      return true;
    }
    if (hasHtmlOpen && (lower.contains('<head') || lower.contains('<body') || lower.contains('<style'))) {
      return true;
    }
    return false;
  }

  String _extractHtmlCode(String text) {
    // 1. Check inside ```html ... ``` block
    final codeBlockRegex = RegExp(r'```(?:html|xml)?([\s\S]*?)```', caseSensitive: false);
    final match = codeBlockRegex.firstMatch(text);
    if (match != null) {
      final code = match.group(1)?.trim();
      if (code != null && code.isNotEmpty) {
        return code;
      }
    }

    // 2. Otherwise, extract starting from <!DOCTYPE html> or <html...
    final docTypeIndex = text.toLowerCase().indexOf('<!doctype');
    if (docTypeIndex != -1) {
      return text.substring(docTypeIndex).trim();
    }
    final htmlOpenIndex = text.toLowerCase().indexOf('<html');
    if (htmlOpenIndex != -1) {
      return text.substring(htmlOpenIndex).trim();
    }

    return text;
  }

  void _showHtmlFullScreen(BuildContext context, String rawHtml) {
    final html = _extractHtmlCode(rawHtml);
    final l10n = McpPlaygroundLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(l10n.get('htmlPreview')),
              bottom: TabBar(
                tabs: [
                  Tab(icon: const Icon(Icons.preview), text: l10n.get('renderedView')),
                  Tab(icon: const Icon(Icons.code), text: l10n.get('htmlSource')),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: l10n.get('copyHtmlSource'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: html));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.get('htmlSourceCopied'))),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body: TabBarView(
              children: [
                // Rendered View
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: HtmlWidget(
                    html,
                    textStyle: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                // HTML Source
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      html,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _extractBase64Images(String text) {
    final images = <String>[];
    final trimmed = text.trim();

    // 1. Check if the raw text is a base64 image directly
    final cleanRaw = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (cleanRaw.startsWith('iVBORw0KGgo') || cleanRaw.startsWith('data:image/')) {
      images.add(cleanRaw);
      return images;
    }

    // 2. Check if it's JSON and search for image fields
    try {
      final parsed = jsonDecode(trimmed);
      _searchJsonForImages(parsed, images);
    } catch (_) {
      // Not valid JSON, or error parsing
    }

    // 3. Fallback regex search for base64 PNG block in the text
    if (images.isEmpty) {
      // A base64 PNG block typically starts with iVBORw0KGgo and is long
      final regex = RegExp(r'(iVBORw0KGgo[a-zA-Z0-9+/=\s\r\n]{50,})');
      for (final match in regex.allMatches(trimmed)) {
        final matchedStr = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
        // Validate length is multiple of 4 or looks like valid base64
        if (matchedStr.length >= 100) {
          images.add(matchedStr);
        }
      }
    }

    return images;
  }

  void _searchJsonForImages(dynamic val, List<String> images) {
    if (val is String) {
      final clean = val.trim().replaceAll(RegExp(r'\s+'), '');
      if (clean.startsWith('iVBORw0KGgo') || clean.startsWith('data:image/')) {
        images.add(clean);
      }
    } else if (val is Map) {
      for (final v in val.values) {
        _searchJsonForImages(v, images);
      }
    } else if (val is List) {
      for (final v in val) {
        _searchJsonForImages(v, images);
      }
    }
  }

  static final RegExp _markdownDataUriPattern = RegExp(
    r'\[([^\]]+)\]\(\s*data:([^;\s\)]+);base64,([A-Za-z0-9+/=\s\r\n]+)\s*\)',
    dotAll: true,
    caseSensitive: false,
  );

  Widget _buildMarkdownWithEmbeddedDataUris(BuildContext context, String content, ThemeData theme) {
    final match = _markdownDataUriPattern.firstMatch(content);
    if (match == null) {
      return MarkdownBody(
        data: content,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: TextStyle(color: theme.colorScheme.onSurface),
          code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    }

    final fileName = (match.group(1) ?? 'file').trim();
    final mimeType = (match.group(2) ?? 'application/octet-stream').trim();
    final payload = (match.group(3) ?? '').replaceAll(RegExp(r'\s+'), '');
    var beforeText = content.substring(0, match.start);
    if (beforeText.endsWith('!')) {
      beforeText = beforeText.substring(0, beforeText.length - 1);
    }
    final afterText = content.substring(match.end);

    Widget embeddedWidget;
    if (mimeType.toLowerCase().startsWith('image/')) {
      embeddedWidget = _buildEmbeddedImage(context, payload, mimeType, theme);
    } else {
      embeddedWidget = _buildEmbeddedFile(context, payload, mimeType, fileName, theme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (beforeText.trim().isNotEmpty)
          MarkdownBody(
            data: beforeText,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: TextStyle(color: theme.colorScheme.onSurface),
              code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        embeddedWidget,
        if (afterText.trim().isNotEmpty)
          _buildMarkdownWithEmbeddedDataUris(context, afterText, theme),
      ],
    );
  }

  Widget _buildEmbeddedImage(BuildContext context, String base64Data, String mimeType, ThemeData theme) {
    return _buildImageContent(context, base64Data, mimeType, theme);
  }

  Widget _buildEmbeddedFile(BuildContext context, String base64Data, String mimeType, String fileName, ThemeData theme) {
    Uint8List bytes;
    try {
      bytes = base64Decode(base64Data);
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text('Error decoding file: $e', style: const TextStyle(color: Colors.red)),
      );
    }
    final sizeInKb = (bytes.length / 1024).toStringAsFixed(1);

    IconData fileIcon = Icons.insert_drive_file_outlined;
    Color fileColor = theme.colorScheme.primary;
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel') || fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
      fileIcon = Icons.table_chart_outlined;
      fileColor = Colors.green;
    } else if (mimeType.contains('pdf') || fileName.endsWith('.pdf')) {
      fileIcon = Icons.picture_as_pdf_outlined;
      fileColor = Colors.red;
    } else if (mimeType.contains('word') || mimeType.contains('document') || fileName.endsWith('.docx')) {
      fileIcon = Icons.description_outlined;
      fileColor = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: fileColor.withValues(alpha: 0.15),
          child: Icon(fileIcon, color: fileColor),
        ),
        title: Text(
          fileName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '$sizeInKb KB · $mimeType',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download_outlined),
          onPressed: () => _downloadFile(context, bytes, fileName),
          tooltip: 'Download File',
        ),
      ),
    );
  }
}
