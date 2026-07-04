import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models.dart';
import '../../playground_controller.dart';
import '../mcp_localizations.dart';

class ServerToolsDialog extends StatefulWidget {
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
  State<ServerToolsDialog> createState() => _ServerToolsDialogState();
}

class _ServerToolsDialogState extends State<ServerToolsDialog> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.server.enabled) {
      _connect();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    // Cleanup connection if no tools are selected
    widget.controller.syncMcpServers();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
    });
    try {
      await widget.controller.connectServer(widget.server.id);
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = McpPlaygroundLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Background dialog colors matching premium dark theme
    final dialogBgColor = isDark ? const Color(0xFF1E2530) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    // Find the client definition in active clients
    final clients = widget.controller.mcpClients.where((c) => c.name == widget.server.id);
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
                  '${widget.server.name} Tools',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
                ),
                Text(
                  !widget.server.enabled
                      ? l10n.get('serverDisabled')
                      : (isConnected ? '${tools.length} tools available' : (_connecting ? l10n.get('connecting') : l10n.get('offline'))),
                  style: TextStyle(
                    fontSize: 12,
                    color: !widget.server.enabled
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
          body: !widget.server.enabled
              ? _buildDisabledState(context)
              : (_connecting
                  ? _buildLoadingState(context)
                  : (isConnected ? _buildToolsList(context, tools) : _buildOfflineState(context))),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final l10n = McpPlaygroundLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00ACC1)),
            const SizedBox(height: 16),
            Text(
              l10n.get('connectingToServer'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('startingProcessQueryingTools'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabledState(BuildContext context) {
    final l10n = McpPlaygroundLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.power_settings_new_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.get('serverDisabled'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('pleaseEnableServerToDiscover'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineState(BuildContext context) {
    final l10n = McpPlaygroundLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.offline_bolt_outlined, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text(
              l10n.get('serverOfflineOrStarting'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('makeSureServerIsRunningToDiscover'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsList(BuildContext context, List<MCPTool> tools) {
    final l10n = McpPlaygroundLocalizations.of(context);
    if (tools.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            l10n.get('noToolsRegistered'),
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
                Text(l10n.get('description'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(tool.description!, style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.get('inputSchema'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: l10n.get('copyJsonSchema'),
                    onPressed: () {
                      final rawJson = const JsonEncoder.withIndent('  ').convert(tool.inputSchema ?? {});
                      Clipboard.setData(ClipboardData(text: rawJson));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.get('schemaCopied')), duration: const Duration(seconds: 1)),
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
