import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../models.dart';
import '../../playground_controller.dart';

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
                  MarkdownBody(
                    data: message.content,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(color: theme.colorScheme.onSurface),
                      code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
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
        title: Text(
          'Tool Execution Call: ${message.toolName}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
      final extension = mimeType != null && mimeType.contains('/')
          ? mimeType.split('/').last
          : 'png';
      final fileName = 'generated_image.$extension';

      final resultPath = await FilePicker.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );

      if (resultPath != null) {
        if (!kIsWeb) {
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

    String processedText = text;
    bool isFormatted = false;

    // Direct JSON check
    try {
      final cleaned = text.trim();
      final dynamic jsonData = jsonDecode(cleaned);
      processedText = const JsonEncoder.withIndent('  ').convert(jsonData);
      isFormatted = true;
    } catch (_) {
      // Not direct JSON
    }

    final outputLines = processedText.split('\n');
    const maxPreviewLines = 20;
    const maxPreviewChars = 5000;
    final shouldTruncate = outputLines.length > maxPreviewLines || processedText.length > maxPreviewChars;

    var previewText = processedText;
    if (shouldTruncate) {
      final limitedLines = outputLines.take(maxPreviewLines).join('\n');
      if (limitedLines.length > maxPreviewChars) {
        previewText = '${limitedLines.substring(0, maxPreviewChars)}\n...';
      } else {
        previewText = '$limitedLines\n...';
      }
    }

    return Container(
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
          if (isFormatted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.code, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'JSON Format',
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
          if (!isFormatted && shouldTruncate)
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
  }
}
