import 'package:flutter/material.dart';
import '../../models.dart';
import '../../playground_controller.dart';
import '../local_mcp_client.dart';
import '../mcp_localizations.dart';

class InitialMcpInstallProgressDialog extends StatefulWidget {
  final List<LocalMcpServerSetup> serversToInstall;
  final PlaygroundController controller;
  final String? locale;

  const InitialMcpInstallProgressDialog({
    super.key,
    required this.serversToInstall,
    required this.controller,
    this.locale,
  });

  @override
  State<InitialMcpInstallProgressDialog> createState() =>
      _InitialMcpInstallProgressDialogState();
}

class _InitialMcpInstallProgressDialogState
    extends State<InitialMcpInstallProgressDialog> {
  String _currentServerName = '';
  String _statusMessage = '';
  double? _progress;
  int _currentIndex = 0;

  McpPlaygroundLocalizations get l10n {
    if (widget.locale != null) {
      return McpPlaygroundLocalizations(Locale(widget.locale!));
    }
    return McpPlaygroundLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _statusMessage = l10n.get('preparingRuntime');
        });
        _runInstallations();
      }
    });
  }

  Future<void> _runInstallations() async {
    for (int i = 0; i < widget.serversToInstall.length; i++) {
      final setup = widget.serversToInstall[i];
      if (!mounted) return;
      final l10n = this.l10n;
      setState(() {
        _currentIndex = i;
        _currentServerName = setup.name;
        _statusMessage = l10n.get('preparingRuntime');
        _progress = i / widget.serversToInstall.length;
      });

      // Find the server config in the controller
      final config = widget.controller.servers.firstWhere((s) => s.name == setup.name);

      final error = await LocalMcpRuntime.install(
        config,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _statusMessage = p.message;
            });
          }
        },
      );

      if (error != null) {
        if (mounted) {
          final errMsg = l10n.locale.languageCode == 'de'
              ? 'Installation von ${setup.name} fehlgeschlagen: $error'
              : 'Failed to install ${setup.name}: $error';
          setState(() {
            _statusMessage = errMsg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errMsg),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        // Mark server as installed!
        final updatedConfig = config.copyWith(isInstalled: true);
        await widget.controller.updateServer(updatedConfig);
      }
    }

    if (mounted) {
      Navigator.pop(context); // Close the dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = this.l10n;
    return AlertDialog(
      title: Text(l10n.get('initializingServers')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.locale.languageCode == 'de'
                ? 'Installiere $_currentServerName (${_currentIndex + 1}/${widget.serversToInstall.length})'
                : 'Installing $_currentServerName (${_currentIndex + 1}/${widget.serversToInstall.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(_statusMessage),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
        ],
      ),
    );
  }
}
