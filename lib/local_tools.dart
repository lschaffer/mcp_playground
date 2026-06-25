import 'models.dart';

/// Base class representing a Dart-native local tool.
abstract class McpLocalTool {
  String get name;
  String get description;
  Map<String, dynamic> get inputSchema;
  Future<MCPToolResult> execute(Map<String, dynamic> arguments);

  /// Convert to standard MCPTool model representation.
  MCPTool toMCPTool() {
    return MCPTool(
      name: name,
      description: description,
      inputSchema: inputSchema,
    );
  }
}
