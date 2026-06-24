import 'package:flutter/material.dart';
import '../models.dart';
import '../playground_controller.dart';

class EditMcpServerDialog extends StatefulWidget {
  final McpServerConfig server;
  final PlaygroundController controller;

  const EditMcpServerDialog({
    super.key,
    required this.server,
    required this.controller,
  });

  static Future<void> show(BuildContext context, McpServerConfig server, PlaygroundController controller) {
    return showDialog(
      context: context,
      builder: (ctx) => EditMcpServerDialog(server: server, controller: controller),
    );
  }

  @override
  State<EditMcpServerDialog> createState() => _EditMcpServerDialogState();
}

class _EditMcpServerDialogState extends State<EditMcpServerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _apiPasswordCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.server.name);
    _urlCtrl = TextEditingController(text: widget.server.url);
    _endpointCtrl = TextEditingController(text: widget.server.mcpEndpoint);
    _apiKeyCtrl = TextEditingController(text: widget.server.apiKey ?? '');
    _apiPasswordCtrl = TextEditingController(text: widget.server.apiPassword ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _apiPasswordCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = widget.server.copyWith(
      name: _nameCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      mcpEndpoint: _endpointCtrl.text.trim().isEmpty ? '/mcp' : _endpointCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim().isEmpty ? null : _apiKeyCtrl.text.trim(),
      apiPassword: _apiPasswordCtrl.text.trim().isEmpty ? null : _apiPasswordCtrl.text.trim(),
    );

    widget.controller.updateServer(updated);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server "${updated.name}" updated successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Teal accent color used in mockup (Image 2)
    const tealAccent = Color(0xFF009688);
    
    // Background dialog colors
    final dialogBgColor = isDark ? const Color(0xFF1E2530) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: dialogBgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit MCP Server',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 20),
                _buildField(
                  controller: _nameCtrl,
                  labelText: 'Name',
                  validator: (value) => value == null || value.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _urlCtrl,
                  labelText: 'Server URL *',
                  keyboardType: TextInputType.url,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Server URL is required' : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _endpointCtrl,
                  labelText: 'MCP Endpoint',
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _apiKeyCtrl,
                  labelText: 'API Key (optional)',
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _apiPasswordCtrl,
                  labelText: 'API Password (optional)',
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: tealAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String labelText,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Styled inputs matching the dark premium mockup
    final fillColor = isDark ? const Color(0xFF131922) : Colors.grey[100];
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[700];

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: labelColor),
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2C3545) : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF009688),
            width: 2.0,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.redAccent,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.redAccent,
            width: 2.0,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
