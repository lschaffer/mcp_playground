/// Represents a tool call requested by the LLM.
class LLMToolCall {
  /// Unique identifier of the tool call instance.
  final String id;

  /// The name of the tool function to call.
  final String name;

  /// The input parameters mapped as arguments for the tool execution.
  final Map<String, dynamic> arguments;

  /// Creates a new [LLMToolCall] instance.
  const LLMToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Represents the completion response returned by the LLM.
class LLMResponse {
  /// The textual response content from the LLM.
  final String text;

  /// The list of tool calls requested by the LLM in this response.
  final List<LLMToolCall> toolCalls;

  /// Creates a new [LLMResponse] instance.
  const LLMResponse({required this.text, this.toolCalls = const []});
}
