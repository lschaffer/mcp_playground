import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../playground_controller.dart';

class RegisteredToolsDialog extends StatelessWidget {
  final PlaygroundController controller;

  const RegisteredToolsDialog({super.key, required this.controller});

  static Future<void> show(BuildContext context, PlaygroundController controller) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: RegisteredToolsDialog(controller: controller),
        ),
      );
    }
    return showDialog(
      context: context,
      builder: (ctx) => RegisteredToolsDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localTools = controller.localTools.map((t) => t.toMCPTool()).toList();
    final externalTools = controller.externalTools;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final childWidget = DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registered Tools', style: TextStyle(fontWeight: FontWeight.bold)),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Inbuilt Tools'),
              Tab(text: 'Server Tools'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildToolsList(context, localTools, 'No inbuilt tools registered.'),
            _buildToolsList(context, externalTools, 'No active HTTP/SSE MCP server tools found.'),
          ],
        ),
      ),
    );

    if (isMobile) {
      return childWidget;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
        child: childWidget,
      ),
    );
  }

  Widget _buildToolsList(BuildContext context, List<MCPTool> tools, String emptyMessage) {
    if (tools.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tools.length,
      itemBuilder: (ctx, idx) {
        final tool = tools[idx];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ExpansionTile(
            title: Text(tool.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              tool.description ?? 'No description provided.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tool.description != null && tool.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(tool.description!, style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Input Schema', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy JSON Schema',
                    onPressed: () {
                      final rawJson = const JsonEncoder.withIndent('  ').convert(tool.inputSchema ?? {});
                      Clipboard.setData(ClipboardData(text: rawJson));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Schema copied to clipboard'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(tool.inputSchema ?? {}),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
