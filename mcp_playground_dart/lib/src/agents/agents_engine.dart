import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../llm/llm_service.dart';
import '../mcp/local_tools.dart';
import '../mcp/mcp_client.dart';
import '../mcp/mcp_client_def.dart';
import '../mcp/local_mcp_client_stub.dart'
    if (dart.library.io) '../mcp/local_mcp_client.dart';

// ═══════════════════════════════════════════════════════════════
// Agent Status
// ═══════════════════════════════════════════════════════════════

enum AgentStatus { running, finished, error }

// ═══════════════════════════════════════════════════════════════
// Agent Events (Stream-based)
// ═══════════════════════════════════════════════════════════════

/// Base class for all agent execution events.
sealed class AgentEvent {}

/// Log/chronology message event.
class AgentLogEvent extends AgentEvent {
  final String message;
  AgentLogEvent(this.message);
}

/// Tool call result event.
class AgentToolResultEvent extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> parameters;
  final String result;
  AgentToolResultEvent({
    required this.toolName,
    required this.parameters,
    required this.result,
  });
}

/// Assistant LLM response event.
class AgentAssistantResultEvent extends AgentEvent {
  /// The user prompt or tool call result that prompted this response.
  final String prompt;

  /// The response from the LLM.
  final String response;
  /// Creates a new [AgentAssistantResultEvent].
  AgentAssistantResultEvent({required this.prompt, required this.response});
}

/// Error event.
class AgentErrorEvent extends AgentEvent {
  final Object error;
  /// Creates a new [AgentErrorEvent] wrapping [error].
  AgentErrorEvent(this.error);
}

/// Final result event — emitted once at the end of agent execution.
class AgentFinalResultEvent extends AgentEvent {
  final String response;
  AgentFinalResultEvent(this.response);
}

// ═══════════════════════════════════════════════════════════════
// Agent Definition
// ═══════════════════════════════════════════════════════════════

/// An agent definition containing its configurations, prompts, and tools.
class Agent {
  /// Short unique key used to reference this agent.
  final String key;

  /// Human-readable name.
  final String name;

  /// LLM configuration.
  final LlmConfig llmConfig;

  /// System prompt (optional).
  final String? systemPrompt;

  /// Sub-prompt steps. Each step can restrict tools and control
  /// whether execution stops after a tool call.
  final List<SubPromptStep> prompts;

  /// Dart-native local tools (all platforms).
  final List<McpLocalTool> dartTools;

  /// Remote MCP server configurations (HTTP/HTTPS/SSE, all platforms).
  final List<McpServerConfig> remoteServers;

  /// Local MCP server configurations (python/nodejs, desktop only).
  final List<McpServerConfig> localServers;

  /// Creates a new [Agent] instance with the specified configurations and tools.
  const Agent({
    required this.key,
    required this.name,
    required this.llmConfig,
    this.systemPrompt,
    this.prompts = const [],
    this.dartTools = const [],
    this.remoteServers = const [],
    this.localServers = const [],
  });

  /// Serialize to JSON for external storage.
  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'llmConfig': llmConfig.toJson(),
    'systemPrompt': systemPrompt,
    'prompts': prompts.map((p) => p.toJson()).toList(),
    'remoteServers': remoteServers.map((s) => s.toJson()).toList(),
    'localServers': localServers.map((s) => s.toJson()).toList(),
  };

  /// Deserialize from JSON.
  factory Agent.fromJson(
    Map<String, dynamic> json, {
    List<McpLocalTool> dartTools = const [],
  }) {
    return Agent(
      key: json['key'] as String,
      name: json['name'] as String? ?? '',
      llmConfig: LlmConfig.fromJson(
        json['llmConfig'] as Map<String, dynamic>? ?? {},
      ),
      systemPrompt: json['systemPrompt'] as String?,
      prompts:
          (json['prompts'] as List?)
              ?.map((e) => SubPromptStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dartTools: dartTools,
      remoteServers:
          (json['remoteServers'] as List?)
              ?.map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      localServers:
          (json['localServers'] as List?)
              ?.map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Callback Typedefs
// ═══════════════════════════════════════════════════════════════

typedef LogCallback = void Function(String message);
typedef ToolResultCallback =
    void Function(
      String toolName,
      Map<String, dynamic> parameters,
      String result,
    );
typedef AssistantResultCallback = void Function(String prompt, String response);
typedef ErrorCallback = void Function(Object error);
typedef FinalResultCallback = void Function(String response);

// ═══════════════════════════════════════════════════════════════
// Main Agent Engine
// ═══════════════════════════════════════════════════════════════

class McpAgentEngine {
  final Map<String, Agent> _agents = {};
  final Map<String, AgentStatus> _statuses = {};
  final Map<String, MultiMCPManager> _mcpManagers = {};
  final Uuid _uuid = const Uuid();

  // Per-agent cancel tokens
  final Map<String, bool> _cancelTokens = {};

  /// Maximum tool loop iterations per sub-prompt step.
  static const int _maxToolIterations = 10;

  /// Event stream controller for reactive consumers.
  final StreamController<AgentEvent> _eventController =
      StreamController<AgentEvent>.broadcast();

  /// Broadcast stream of all agent events.
  Stream<AgentEvent> get agentEvents => _eventController.stream;

  final bool _enableLogging;
  McpAgentEngine({this._enableLogging = false});
  void _log(String message) {
    if (_enableLogging) {
      print('[McpAgentEngine] $message');
    }
  }

  // ── Agent Management ──────────────────────────────────────────

  /// Register agents. Existing agents with the same key are replaced.
  void setAgents(List<Agent> agents) {
    for (final agent in agents) {
      _agents[agent.key] = agent;
    }
    _log(
      'Registered ${agents.length} agent(s): ${agents.map((a) => a.key).join(', ')}',
    );
  }

  /// Retrieve all currently registered agents.
  List<Agent> getAgents() => List.unmodifiable(_agents.values);

  /// Get status of a specific agent.
  AgentStatus? statusOf(String agentKey) => _statuses[agentKey];

  /// Cancel a running agent execution.
  void cancel(String agentKey) {
    _cancelTokens[agentKey] = true;
    _log('Cancellation requested for agent: $agentKey');
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    for (final manager in _mcpManagers.values) {
      await manager.disconnectAll();
      manager.dispose();
    }
    _mcpManagers.clear();
    _agents.clear();
    _statuses.clear();
    _cancelTokens.clear();
    await _eventController.close();
  }

  // ── Execution ─────────────────────────────────────────────────

  /// Execute an agent synchronously. Blocks until completion.
  ///
  /// Callbacks are optional except [onError] and [onFinalResult].
  /// Returns the final response text.
  Future<String> run(
    String agentKey, {
    LogCallback? onLog,
    ToolResultCallback? onToolResult,
    AssistantResultCallback? onAssistantResult,
    ErrorCallback? onError,
    FinalResultCallback? onFinalResult,
  }) async {
    return await _executeAgent(
      agentKey,
      onLog: onLog,
      onToolResult: onToolResult,
      onAssistantResult: onAssistantResult,
      onError: onError,
      onFinalResult: onFinalResult,
    );
  }

  /// Execute an agent asynchronously. Returns a [Stream] of [AgentEvent]s immediately.
  /// Callbacks are also supported.
  Stream<AgentEvent> runAsync(
    String agentKey, {
    LogCallback? onLog,
    ToolResultCallback? onToolResult,
    AssistantResultCallback? onAssistantResult,
    ErrorCallback? onError,
    FinalResultCallback? onFinalResult,
  }) {
    unawaited(
      _executeAgent(
        agentKey,
        onLog: onLog,
        onToolResult: onToolResult,
        onAssistantResult: onAssistantResult,
        onError: onError,
        onFinalResult: onFinalResult,
      ),
    );
    return agentEvents;
  }

  // ── Internal Execution ────────────────────────────────────────

  Future<String> _executeAgent(
    String agentKey, {
    LogCallback? onLog,
    ToolResultCallback? onToolResult,
    AssistantResultCallback? onAssistantResult,
    ErrorCallback? onError,
    FinalResultCallback? onFinalResult,
  }) async {
    final agent = _agents[agentKey];
    if (agent == null) {
      final err = 'Agent with key "$agentKey" not found.';
      _eventController.add(AgentErrorEvent(err));
      onError?.call(err);
      _statuses[agentKey] = AgentStatus.error;
      throw ArgumentError(err);
    }

    _statuses[agentKey] = AgentStatus.running;
    _cancelTokens[agentKey] = false;
    String lastResponse = '';

    try {
      // ── Set up MCP manager ──────────────────────────────
      final mcpManager = MultiMCPManager();
      _mcpManagers[agentKey] = mcpManager;

      // Connect remote servers
      for (final server in agent.remoteServers) {
        if (!server.enabled) continue;
        final client = MCPClient(
          server.url,
          mcpEndpoint: server.mcpEndpoint,
          bearerToken: server.apiKey,
          apiPassword: server.apiPassword,
          logCallback: (msg, {bool isError = false}) {
            final logMsg = isError
                ? '[MCP:${server.name}] ERROR: $msg'
                : '[MCP:${server.name}] $msg';
            _log(logMsg);
          },
        );
        final clientDef = MCPClientDef(
          name: server.id,
          client: client,
          displayName: server.name,
        );
        mcpManager.registerClient(clientDef);
        try {
          await client.connect();
          _log('Connected to remote MCP server: ${server.name}');
        } catch (e) {
          _log('Failed to connect to remote MCP server ${server.name}: $e');
          _eventController.add(
            AgentLogEvent(
              'Warning: Could not connect to MCP server "${server.name}": $e',
            ),
          );
          onLog?.call(
            'Warning: Could not connect to MCP server "${server.name}": $e',
          );
        }
      }

      // Connect local servers (desktop only via conditional import)
      for (final server in agent.localServers) {
        if (!server.enabled) continue;
        try {
          final client = LocalMCPClient(
            server,
            logCallback: (msg, {bool isError = false}) {
              final logMsg = isError
                  ? '[LocalMCP:${server.name}] ERROR: $msg'
                  : '[LocalMCP:${server.name}] $msg';
              _log(logMsg);
            },
          );
          final clientDef = MCPClientDef(
            name: server.id,
            client: client,
            displayName: server.name,
          );
          mcpManager.registerClient(clientDef);
          await client.connect();
          _log('Connected to local MCP server: ${server.name}');
        } catch (e) {
          _log('Failed to connect to local MCP server ${server.name}: $e');
          _eventController.add(
            AgentLogEvent(
              'Warning: Could not connect to local MCP server "${server.name}": $e',
            ),
          );
          onLog?.call(
            'Warning: Could not connect to local MCP server "${server.name}": $e',
          );
        }
      }

      // ── Build full tool list ────────────────────────────
      final allTools = <MCPTool>[];
      allTools.addAll(agent.dartTools.map((t) => t.toMCPTool()));
      allTools.addAll(mcpManager.availableTools);

      // ── Build messages list ────────────────────────────
      final messages = <ChatMessage>[];

      // Add system prompt if present
      String effectiveSystem =
          agent.systemPrompt ??
          'You are an agent equipped with tools. '
              'Focus on the user\'s task. '
              'Use the tool schemas precisely. If you decide to call a tool, '
              'generate the tool call block. '
              'Present final answers directly.';

      effectiveSystem +=
          '\n\nTool execution rules:\n'
          '- Each tool execution result is returned in a JSON structure: '
          '{"tool": "name", "id": "unique_id", "tool_executed": true, "tool_result": ...}.\n'
          '- Once a tool has been successfully executed (tool_executed is true), '
          'you must NEVER call that tool with the same "id" or parameters again.\n'
          '- Instead, formulate your final response to the user using the result provided in tool_result.';

      // Inject tool descriptions into system prompt for non-native tool calling
      if (allTools.isNotEmpty && !agent.llmConfig.useNativeToolCall) {
        effectiveSystem += '\n\nAvailable Tools:\n';
        for (final tool in allTools) {
          effectiveSystem += '- Tool Name: ${tool.name}\n';
          if (tool.description != null && tool.description!.isNotEmpty) {
            effectiveSystem += '  Description: ${tool.description}\n';
          }
          if (tool.inputSchema != null) {
            effectiveSystem +=
                '  Input Schema: ${jsonEncode(tool.inputSchema)}\n';
          }
        }
      }

      _eventController.add(AgentLogEvent('Agent "${agent.name}" started.'));
      onLog?.call('Agent "${agent.name}" started.');

      // ── Execute sub-prompts ────────────────────────────
      String? lastToolOutput;
      String? lastTaskResult;

      final steps = agent.prompts.isEmpty
          ? [const SubPromptStep(text: '')]
          : agent.prompts;

      for (int stepIdx = 0; stepIdx < steps.length; stepIdx++) {
        if (_cancelTokens[agentKey] == true) {
          final cancelMsg = 'Execution cancelled by user.';
          _eventController.add(AgentLogEvent(cancelMsg));
          onLog?.call(cancelMsg);
          messages.add(
            ChatMessage(
              id: _uuid.v4(),
              content: cancelMsg,
              role: ChatRole.system,
              type: MessageType.log,
              timestamp: DateTime.now(),
            ),
          );
          break;
        }

        final step = steps[stepIdx];
        String prompt = step.text;

        // Substitute placeholders from previous steps
        if (lastToolOutput != null) {
          prompt = prompt
              .replaceAll(r'${tool_result}', lastToolOutput)
              .replaceAll('[tool_result]', lastToolOutput);
          lastToolOutput = null;
        }
        if (lastTaskResult != null) {
          prompt = prompt
              .replaceAll(r'${task_result}', lastTaskResult)
              .replaceAll('[task_result]', lastTaskResult);
          lastTaskResult = null;
        }

        // Determine if next step needs tool result
        final nextNeedsToolResult =
            (stepIdx + 1 < steps.length) &&
            (steps[stepIdx + 1].text.contains(r'${tool_result}') ||
                steps[stepIdx + 1].text.contains('[tool_result]'));

        // Reset loop tracking
        int toolIterationCount = 0;
        bool forceNoToolCalls = false;
        String? forcedNoToolHint;
        final executedSignatures = <String>{};
        final executedIds = <String>{};

        // Filter step tools
        final List<MCPTool> activeStepTools = step.isAllTools
            ? allTools
            : allTools.where((t) {
                return step.enabledToolNames?.contains(t.name) ?? false;
              }).toList();

        // Add user message for this step
        if (prompt.isNotEmpty) {
          final userMsg = ChatMessage(
            id: _uuid.v4(),
            content: prompt,
            role: ChatRole.user,
            timestamp: DateTime.now(),
          );
          messages.add(userMsg);
          _eventController.add(
            AgentLogEvent('User prompt [step ${stepIdx + 1}]: $prompt'),
          );
          onLog?.call('User prompt [step ${stepIdx + 1}]: $prompt');
        }

        final stepNewMsgs = <ChatMessage>[];
        bool continueLoop = step.isNoTools ? false : true;

        while (continueLoop) {
          if (_cancelTokens[agentKey] == true) {
            final cancelMsg = 'Execution cancelled by user.';
            messages.add(
              ChatMessage(
                id: _uuid.v4(),
                content: cancelMsg,
                role: ChatRole.system,
                type: MessageType.log,
                timestamp: DateTime.now(),
              ),
            );
            _eventController.add(AgentLogEvent(cancelMsg));
            onLog?.call(cancelMsg);
            break;
          }

          if (toolIterationCount >= _maxToolIterations) {
            final limitMsg =
                'Maximum tool iteration limit ($_maxToolIterations) reached.';
            messages.add(
              ChatMessage(
                id: _uuid.v4(),
                content: limitMsg,
                role: ChatRole.assistant,
                timestamp: DateTime.now(),
              ),
            );
            _eventController.add(AgentLogEvent(limitMsg));
            onLog?.call(limitMsg);
            break;
          }

          final mcpTools = (!forceNoToolCalls && !step.isNoTools)
              ? activeStepTools
              : <MCPTool>[];

          final requestMsgs = List<ChatMessage>.from(messages);
          if (forceNoToolCalls && forcedNoToolHint != null) {
            requestMsgs.add(
              ChatMessage(
                id: _uuid.v4(),
                content: forcedNoToolHint,
                role: ChatRole.user,
                timestamp: DateTime.now(),
              ),
            );
            forceNoToolCalls = false;
            forcedNoToolHint = null;
          }

          _log('Generating LLM response (step ${stepIdx + 1})...');
          final response = await LLMService.generate(
            config: agent.llmConfig,
            messages: requestMsgs,
            tools: mcpTools,
            systemPrompt: effectiveSystem,
          );

          if (_cancelTokens[agentKey] == true) break;

          if (response.toolCalls.isEmpty) {
            if (response.text.isNotEmpty) {
              final textMsg = ChatMessage(
                id: _uuid.v4(),
                content: response.text,
                role: ChatRole.assistant,
                timestamp: DateTime.now(),
              );
              messages.add(textMsg);
              stepNewMsgs.add(textMsg);

              final promptForEvent = prompt.isNotEmpty
                  ? prompt
                  : '[tool result]';
              _eventController.add(
                AgentAssistantResultEvent(
                  prompt: promptForEvent,
                  response: response.text,
                ),
              );
              onAssistantResult?.call(promptForEvent, response.text);

              _log('Assistant Response: ${response.text}');
              lastResponse = response.text;
            }
            continueLoop = false;
          } else {
            final call = response.toolCalls.first;
            _log(
              'Tool Call: ${call.name} with args: ${jsonEncode(call.arguments)}',
            );

            toolIterationCount++;
            final signature = '${call.name}|${jsonEncode(call.arguments)}';
            final hasDuplicateId = executedIds.contains(call.id);
            final hasDuplicateSignature = executedSignatures.contains(
              signature,
            );

            if (hasDuplicateId || hasDuplicateSignature) {
              String previousResult = messages
                  .lastWhere(
                    (m) => m.role == ChatRole.tool && m.toolName == call.name,
                    orElse: () => ChatMessage(
                      id: '',
                      content: '',
                      role: ChatRole.tool,
                      timestamp: DateTime.now(),
                    ),
                  )
                  .content;

              if (previousResult.trim().startsWith('{')) {
                try {
                  final decoded = jsonDecode(previousResult);
                  if (decoded is Map && decoded.containsKey('tool_result')) {
                    previousResult = decoded['tool_result'].toString();
                  }
                } catch (_) {}
              }

              final loopCorrectionText =
                  'The tool "${call.name}" was already executed. '
                  'Previous result: $previousResult\n\n'
                  'Do NOT call this tool again. Generate the final response.';

              final dupMsg = ChatMessage(
                id: call.id,
                content: agent.llmConfig.provider == LlmProvider.ollama
                    ? jsonEncode({
                        'tool': call.name,
                        'id': call.id,
                        'tool_executed': true,
                        'tool_result': loopCorrectionText,
                      })
                    : loopCorrectionText,
                role: ChatRole.tool,
                type: MessageType.toolResponse,
                toolName: call.name,
                toolResult: MCPToolResult(
                  content: [MCPContent(type: 'text', text: loopCorrectionText)],
                  isError: false,
                ),
                timestamp: DateTime.now(),
              );
              messages.add(dupMsg);
              stepNewMsgs.add(dupMsg);

              forceNoToolCalls = true;
              forcedNoToolHint =
                  'The tool "${call.name}" has already been executed. '
                  'Do NOT call any tool again. Write your final response now.';
              continueLoop = true;
              continue;
            }

            executedIds.add(call.id);
            executedSignatures.add(signature);

            // Add tool call message
            final callMsg = ChatMessage(
              id: call.id,
              content:
                  'Calling tool: ${call.name} with args: ${jsonEncode(call.arguments)}',
              role: ChatRole.assistant,
              type: MessageType.toolCall,
              toolName: call.name,
              toolArguments: call.arguments,
              timestamp: DateTime.now(),
            );
            messages.add(callMsg);
            stepNewMsgs.add(callMsg);
            _eventController.add(AgentLogEvent('Calling tool: ${call.name}'));
            onLog?.call('Calling tool: ${call.name}');

            // Execute tool
            MCPToolResult result;
            final localMatch = agent.dartTools
                .where((t) => t.name == call.name)
                .toList();

            if (localMatch.isNotEmpty) {
              result = await localMatch.first.execute(call.arguments);
            } else {
              result = await mcpManager.callTool(call.name, call.arguments);
            }

            final responseContentText = result.content
                .where((c) => c.type == 'text')
                .map((c) => c.text ?? '')
                .join('\n');

            final String finalContent;
            if (agent.llmConfig.provider == LlmProvider.ollama) {
              finalContent = jsonEncode({
                'tool': call.name,
                'id': call.id,
                'tool_executed': true,
                'tool_result': responseContentText.isNotEmpty
                    ? responseContentText
                    : 'Executed.',
              });
            } else {
              finalContent = responseContentText.isNotEmpty
                  ? responseContentText
                  : 'Executed.';
            }

            final resMsg = ChatMessage(
              id: call.id,
              content: finalContent,
              role: ChatRole.tool,
              type: MessageType.toolResponse,
              toolName: call.name,
              toolResult: result,
              timestamp: DateTime.now(),
            );
            messages.add(resMsg);
            stepNewMsgs.add(resMsg);

            _eventController.add(
              AgentToolResultEvent(
                toolName: call.name,
                parameters: call.arguments,
                result: responseContentText,
              ),
            );
            onToolResult?.call(call.name, call.arguments, responseContentText);
            _log('Tool Result: $responseContentText');

            final bool shouldStop =
                step.stopAfterToolCall || nextNeedsToolResult;
            if (shouldStop) {
              continueLoop = false;
            }
          }
        }

        // ── Capture step output ──────────────────────────
        final toolTexts = stepNewMsgs
            .where((m) => m.role == ChatRole.tool && m.content.isNotEmpty)
            .map((m) {
              if (m.content.trim().startsWith('{')) {
                try {
                  final decoded = jsonDecode(m.content);
                  if (decoded is Map && decoded.containsKey('tool_result')) {
                    return decoded['tool_result'].toString();
                  }
                } catch (_) {}
              }
              return m.content;
            })
            .join('\n\n');

        final assistantTexts = stepNewMsgs
            .where(
              (m) =>
                  m.role == ChatRole.assistant &&
                  m.content.isNotEmpty &&
                  m.type != MessageType.toolCall,
            )
            .map((m) => m.content)
            .join('\n\n');

        final stepOutput = toolTexts.isNotEmpty
            ? toolTexts
            : (assistantTexts.isNotEmpty ? assistantTexts : null);

        if (stepOutput != null) {
          lastTaskResult = stepOutput;
          if (nextNeedsToolResult) {
            lastToolOutput = stepOutput;
          }
        }
      }

      // ── Final result ────────────────────────────────────
      _statuses[agentKey] = AgentStatus.finished;
      _eventController.add(AgentFinalResultEvent(lastResponse));
      onFinalResult?.call(lastResponse);

      _log(
        'Agent "${agent.name}" completed. Final response: ${lastResponse.length} chars',
      );

      return lastResponse;
    } catch (e, stack) {
      _statuses[agentKey] = AgentStatus.error;
      _eventController.add(AgentErrorEvent(e));
      onError?.call(e);
      _log('Agent "${agent.name}" failed: $e\n$stack');
      rethrow;
    } finally {
      // Clean up MCP connections
      final manager = _mcpManagers.remove(agentKey);
      if (manager != null) {
        await manager.disconnectAll();
        manager.dispose();
      }
    }
  }
}
