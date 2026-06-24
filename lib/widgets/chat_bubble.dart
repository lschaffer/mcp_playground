import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isSystem = message.role == ChatRole.system;


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

  Widget _buildToolResponseBubble(BuildContext context, ThemeData theme) {
    final contents = message.toolResult?.content ?? [];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: ExpansionTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          radius: 14,
          child: const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
        ),
        title: Text(
          'Tool Response received: ${message.toolName}',
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
    );
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
      return Container(
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
    // Check if it's formatted JSON or code
    final isJson = (text.startsWith('{') && text.endsWith('}')) || (text.startsWith('[') && text.endsWith(']'));
    if (isJson) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MarkdownBody(
        data: text,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: TextStyle(color: theme.colorScheme.onSurface),
          code: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
