import 'package:flutter/material.dart';
import 'models.dart';
import 'local_tools.dart';
import 'playground_controller.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/settings_drawer.dart';


class McpPlayground extends StatefulWidget {
  /// Default LLM setup parameters.
  final LlmConfig? initialLlmConfig;

  /// Default list of HTTP/HTTPS MCP servers to connect to.
  final List<McpServerConfig>? initialServers;

  /// Optional delegate to customize settings save/load operations.
  /// Falls back to SharedPreferences if null.
  final McpPlaygroundStorageDelegate? storageDelegate;

  /// Custom list of internal, Dart-native tools to register.
  final List<McpLocalTool>? customLocalTools;

  const McpPlayground({
    super.key,
    this.initialLlmConfig,
    this.initialServers,
    this.storageDelegate,
    this.customLocalTools,
  });

  @override
  State<McpPlayground> createState() => _McpPlaygroundState();
}

class _McpPlaygroundState extends State<McpPlayground> {
  late final PlaygroundController _controller;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _controller = PlaygroundController(
      initialLlmConfig: widget.initialLlmConfig,
      initialServers: widget.initialServers,
      customLocalTools: widget.customLocalTools,
      storageDelegate: widget.storageDelegate,
    );
    _controller.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {});
      // Autoscroll to bottom when messages are added
      if (_controller.messages.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _controller.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('AI Agent Playground', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Conversation',
            onPressed: _controller.messages.isEmpty ? null : _controller.clearChat,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configure Settings',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: SettingsDrawer(controller: _controller),
      body: Column(
        children: [
          // --- Main Conversation Area ---
          Expanded(
            child: _controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _controller.messages.isEmpty
                    ? _buildWelcomeWidget(theme)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _controller.messages.length,
                        itemBuilder: (ctx, idx) {
                          return ChatBubble(message: _controller.messages[idx]);
                        },
                      ),
          ),
          
          // --- Action Indicators (Generating / Errors) ---
          if (_controller.isGenerating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Agent is thinking and processing tool calls...',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
            
          if (_controller.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.errorContainer,
              child: Text(
                _controller.errorMessage!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),

          // --- User Text Input Row ---
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildWelcomeWidget(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 72, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Welcome to the Playground',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Configure an LLM provider and add HTTP MCP servers via settings, '
                'or call built-in native tools directly (Weather, SSH, and Charts).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              if (!_controller.llmConfig.isConfigured) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Setup Provider First'),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final showButton = _inputCtrl.text.isNotEmpty || !_controller.isGenerating;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message or ask a tool to run...',
                  border: InputBorder.none,
                ),
                onChanged: (text) {
                  // Re-evaluate display of send button
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: showButton && _controller.llmConfig.isConfigured
                    ? theme.colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: showButton && _controller.llmConfig.isConfigured
                  ? _handleSend
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
