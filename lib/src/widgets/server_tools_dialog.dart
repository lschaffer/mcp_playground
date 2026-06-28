import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models.dart';
import '../../playground_controller.dart';

class ServerToolsDialog extends StatelessWidget {
  final McpServerConfig server;
  final PlaygroundController controller;

  const ServerToolsDialog({
    super.key,
    required this.server,
    required this.controller,
  });

  static Future<void> show(BuildContext context, McpServerConfig server, PlaygroundController controller) {
    return showDialog(
      context: context,
      builder: (ctx) => ServerToolsDialog(server: server, controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Background dialog colors matching premium dark theme
    final dialogBgColor = isDark ? const Color(0xFF1E2530) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    // Find the client definition in active clients
    final clients = controller.mcpClients.where((c) => c.name == server.id);
    final clientDef = clients.isNotEmpty ? clients.first : null;
    final isConnected = clientDef?.isConnected ?? false;
    final tools = clientDef?.availableTools ?? [];

    return Dialog(
      backgroundColor: dialogBgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${server.name} Tools',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                ),
                Text(
                  !server.enabled
                      ? 'Disabled'
                      : (isConnected ? '${tools.length} tools available' : 'Offline / Connecting'),
                  style: TextStyle(
                    fontSize: 12,
                    color: !server.enabled
                        ? Colors.grey
                        : (isConnected ? Colors.green : Colors.orangeAccent),
                  ),
                ),
              ],
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: Icon(Icons.close, color: textColor),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: !server.enabled
              ? _buildDisabledState(context)
              : (isConnected ? _buildToolsList(context, tools) : _buildOfflineState(context)),
        ),
      ),
    );
  }

  Widget _buildDisabledState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.power_settings_new_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Server is disabled',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Please enable "${server.name}" using the switch in the server item to start the server and discover its tools.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.offline_bolt_outlined, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            const Text(
              'Server is offline or starting',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure "${server.name}" is installed and running properly to discover its tools.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsList(BuildContext context, List<MCPTool> tools) {
    if (tools.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'No tools registered by this server.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
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
