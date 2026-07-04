import '../models/models.dart';

/// Base class representing a Dart-native local tool.
abstract class McpLocalTool {
  /// The unique identifier name of the tool.
  String get name;

  /// A description of what the tool does, used by the LLM.
  String get description;

  /// The input parameters JSON schema mapping for the tool.
  Map<String, dynamic> get inputSchema;

  /// Executes the tool actions using the supplied LLM arguments.
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
