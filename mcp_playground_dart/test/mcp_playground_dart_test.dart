import 'package:test/test.dart';
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Models Tests
  // ═══════════════════════════════════════════════════════════════

  group('LlmConfig', () {
    test('should create with defaults', () {
      const config = LlmConfig(
        provider: LlmProvider.openai,
        model: 'gpt-4',
        apiKey: 'test-key',
      );
      expect(config.provider, LlmProvider.openai);
      expect(config.model, 'gpt-4');
      expect(config.apiKey, 'test-key');
      expect(config.temperature, 0.2);
      expect(config.maxTokens, 0);
      expect(config.isConfigured, true);
    });

    test('should detect not configured', () {
      const config = LlmConfig(
        provider: LlmProvider.none,
        model: '',
        apiKey: '',
      );
      expect(config.isConfigured, false);
    });

    test('should detect embedded as configured without apiKey', () {
      const config = LlmConfig(
        provider: LlmProvider.embedded,
        model: 'model.gguf',
        apiKey: '',
      );
      expect(config.isConfigured, true);
    });

    test('should serialize and deserialize to JSON', () {
      const config = LlmConfig(
        provider: LlmProvider.claude,
        model: 'claude-3-opus',
        apiKey: 'sk-ant-test',
        temperature: 0.7,
        maxTokens: 4096,
        topP: 0.9,
        topK: 50,
      );
      final json = config.toJson();
      expect(json['provider'], 'claude');
      expect(json['model'], 'claude-3-opus');
      expect(json['temperature'], 0.7);

      final restored = LlmConfig.fromJson(json);
      expect(restored.provider, LlmProvider.claude);
      expect(restored.model, 'claude-3-opus');
      expect(restored.temperature, 0.7);
      expect(restored.maxTokens, 4096);
      expect(restored.topP, 0.9);
      expect(restored.topK, 50);
    });

    test('copyWith should preserve unchanged fields', () {
      const config = LlmConfig(
        provider: LlmProvider.openai,
        model: 'gpt-4',
        apiKey: 'test-key',
        temperature: 0.5,
      );
      final updated = config.copyWith(temperature: 0.8);
      expect(updated.provider, LlmProvider.openai);
      expect(updated.model, 'gpt-4');
      expect(updated.temperature, 0.8);
    });
  });

  group('LlmProvider', () {
    test('configKey returns correct values', () {
      expect(LlmProvider.openai.configKey, 'openai');
      expect(LlmProvider.claude.configKey, 'claude');
      expect(LlmProvider.gemini.configKey, 'gemini');
      expect(LlmProvider.ollama.configKey, 'ollama');
      expect(LlmProvider.embedded.configKey, 'embedded');
    });

    test('fromConfigKey returns correct enum', () {
      expect(LlmProvider.fromConfigKey('openai'), LlmProvider.openai);
      expect(LlmProvider.fromConfigKey('claude'), LlmProvider.claude);
      expect(LlmProvider.fromConfigKey(null), LlmProvider.none);
      expect(LlmProvider.fromConfigKey('unknown'), LlmProvider.none);
    });
  });

  group('McpServerConfig', () {
    test('should serialize and deserialize', () {
      final config = McpServerConfig(
        id: 'test-id',
        name: 'Test Server',
        url: 'https://mcp.example.com',
        apiKey: 'bearer-token',
        enabled: true,
      );
      final json = config.toJson();
      expect(json['id'], 'test-id');
      expect(json['name'], 'Test Server');

      final restored = McpServerConfig.fromJson(json);
      expect(restored.id, 'test-id');
      expect(restored.name, 'Test Server');
      expect(restored.url, 'https://mcp.example.com');
    });

    test('should handle local server config', () {
      final config = McpServerConfig(
        id: 'local-id',
        name: 'Local Python',
        url: '',
        isLocal: true,
        localType: 'python',
        localInstallMethod: 'pip',
        localPackage: 'my-mcp-server',
      );
      expect(config.isLocal, true);
      expect(config.localType, 'python');
      expect(config.localInstallMethod, 'pip');

      final json = config.toJson();
      final restored = McpServerConfig.fromJson(json);
      expect(restored.isLocal, true);
      expect(restored.localPackage, 'my-mcp-server');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // MCP Protocol Models Tests
  // ═══════════════════════════════════════════════════════════════

  group('MCPMessage', () {
    test('MCPRequest serialization', () {
      final req = MCPRequest(
        id: '1',
        method: 'tools/list',
        params: {'cursor': 'abc'},
      );
      final json = req.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], '1');
      expect(json['method'], 'tools/list');
      expect(json['params'], {'cursor': 'abc'});
    });

    test('MCPResponse serialization', () {
      final resp = MCPResponse(id: '1', result: {'tools': []});
      final json = resp.toJson();
      expect(json['id'], '1');
      expect(json['result'], {'tools': []});
    });

    test('MCPResponse with error', () {
      final resp = MCPResponse(
        id: '1',
        error: MCPError(code: -32600, message: 'Invalid Request'),
      );
      final json = resp.toJson();
      expect(json['error']['code'], -32600);
      expect(json['error']['message'], 'Invalid Request');
    });

    test('MCPMessage.fromJson dispatches correctly', () {
      final reqJson = {
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'tools/call',
        'params': {'name': 'test'},
      };
      final msg = MCPMessage.fromJson(reqJson);
      expect(msg, isA<MCPRequest>());
      expect((msg as MCPRequest).method, 'tools/call');
    });

    test('MCPNotification serialization', () {
      final notif = MCPNotification(method: 'notifications/initialized');
      final json = notif.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['method'], 'notifications/initialized');
      expect(json.containsKey('id'), false);
    });
  });

  group('MCPTool', () {
    test('serialization', () {
      final tool = MCPTool(
        name: 'get_weather',
        description: 'Get current weather',
        inputSchema: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
        },
      );
      final json = tool.toJson();
      expect(json['name'], 'get_weather');
      expect(json['description'], 'Get current weather');

      final restored = MCPTool.fromJson(json);
      expect(restored.name, 'get_weather');
      expect(restored.inputSchema?['properties'], isNotNull);
    });
  });

  group('MCPToolResult', () {
    test('serialization', () {
      final result = MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Result text')],
        isError: false,
      );
      final json = result.toJson();
      expect(json['content'], isA<List>());
      expect(json['isError'], false);

      final restored = MCPToolResult.fromJson(json);
      expect(restored.content.length, 1);
      expect(restored.content.first.text, 'Result text');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // ChatMessage Tests
  // ═══════════════════════════════════════════════════════════════

  group('ChatMessage', () {
    test('serialization with tool call', () {
      final msg = ChatMessage(
        id: 'msg-1',
        content: 'Calling tool: test',
        role: ChatRole.assistant,
        timestamp: DateTime(2025, 1, 1),
        type: MessageType.toolCall,
        toolName: 'test_tool',
        toolArguments: {'arg1': 'val1'},
      );
      final json = msg.toJson();
      expect(json['toolName'], 'test_tool');

      final restored = ChatMessage.fromJson(json);
      expect(restored.toolName, 'test_tool');
      expect(restored.toolArguments, {'arg1': 'val1'});
      expect(restored.type, MessageType.toolCall);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // SubPromptStep Tests
  // ═══════════════════════════════════════════════════════════════

  group('SubPromptStep', () {
    test('parse single prompt', () {
      final steps = parseSubPromptSteps('Hello, do something.');
      expect(steps.length, 1);
      expect(steps[0].text, 'Hello, do something.');
      expect(steps[0].isAllTools, true);
    });

    test('parse multi-step prompt', () {
      final text = 'First task.\n++#++[NT:tool1|tool2][SATC]\nSecond task.';
      final steps = parseSubPromptSteps(text);
      expect(steps.length, 2);
      expect(steps[0].text, 'First task.');
      expect(steps[0].isAllTools, true);
      expect(steps[1].text, 'Second task.');
      expect(steps[1].enabledToolNames, ['tool1', 'tool2']);
      expect(steps[1].stopAfterToolCall, true);
    });

    test('parse chat mode (no tools)', () {
      final text = 'Tell me a joke.\n++#++[NT:]\nWhat about another?';
      final steps = parseSubPromptSteps(text);
      expect(steps.length, 2);
      expect(steps[0].isAllTools, true);
      expect(steps[1].isNoTools, true);
    });

    test('serialize round-trip', () {
      final steps = [
        const SubPromptStep(text: 'Step 1'),
        SubPromptStep(
          text: 'Step 2',
          enabledToolNames: ['tool_a'],
          stopAfterToolCall: true,
        ),
      ];
      final serialized = serializeSubPromptSteps(steps);
      final parsed = parseSubPromptSteps(serialized);
      expect(parsed.length, 2);
      expect(parsed[0].text, 'Step 1');
      expect(parsed[1].text, 'Step 2');
      expect(parsed[1].enabledToolNames, ['tool_a']);
      expect(parsed[1].stopAfterToolCall, true);
    });

    test('toJson and fromJson round-trip', () {
      const step = SubPromptStep(
        text: 'Execute task',
        enabledToolNames: ['tool1', 'tool2'],
        stopAfterToolCall: true,
      );
      final json = step.toJson();
      final restored = SubPromptStep.fromJson(json);
      expect(restored.text, 'Execute task');
      expect(restored.enabledToolNames, ['tool1', 'tool2']);
      expect(restored.stopAfterToolCall, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // McpLocalTool Tests
  // ═══════════════════════════════════════════════════════════════

  group('McpLocalTool', () {
    test('toMCPTool conversion', () {
      final tool = _TestLocalTool();
      final mcpTool = tool.toMCPTool();
      expect(mcpTool.name, 'test_tool');
      expect(mcpTool.description, 'A test tool');
      expect(mcpTool.inputSchema, isA<Map>());
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Agent Tests
  // ═══════════════════════════════════════════════════════════════

  group('Agent', () {
    test('serialization to JSON', () {
      final agent = Agent(
        key: 'agent-1',
        name: 'Test Agent',
        llmConfig: const LlmConfig(
          provider: LlmProvider.openai,
          model: 'gpt-4',
          apiKey: 'test-key',
        ),
        systemPrompt: 'You are a test agent.',
        prompts: [
          const SubPromptStep(text: 'Do task 1'),
          SubPromptStep(text: 'Do task 2', stopAfterToolCall: true),
        ],
        remoteServers: [
          McpServerConfig(
            id: 'srv-1',
            name: 'Remote Server',
            url: 'https://mcp.example.com',
          ),
        ],
      );

      final json = agent.toJson();
      expect(json['key'], 'agent-1');
      expect(json['name'], 'Test Agent');
      expect(json['systemPrompt'], 'You are a test agent.');
      expect((json['prompts'] as List).length, 2);
      expect((json['remoteServers'] as List).length, 1);
    });

    test('deserialization from JSON', () {
      final json = {
        'key': 'agent-2',
        'name': 'Restored Agent',
        'llmConfig': {
          'provider': 'claude',
          'model': 'claude-3',
          'apiKey': 'key',
          'temperature': 0.5,
          'maxTokens': 2000,
          'baseUrl': '',
          'maxToolOutputSize': 2560000,
          'tokenWarningThreshold': 1500000,
          'isSlm': false,
          'isMultiModal': true,
          'thinking': false,
          'useNativeToolCall': true,
          'useSafeToolCall': false,
        },
        'systemPrompt': null,
        'prompts': [
          {
            'text': 'Task 1',
            'enabledToolNames': null,
            'stopAfterToolCall': false,
          },
        ],
        'remoteServers': [],
        'localServers': [],
      };

      final agent = Agent.fromJson(json);
      expect(agent.key, 'agent-2');
      expect(agent.name, 'Restored Agent');
      expect(agent.llmConfig.provider, LlmProvider.claude);
      expect(agent.llmConfig.model, 'claude-3');
      expect(agent.prompts.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // AgentEvent Tests
  // ═══════════════════════════════════════════════════════════════

  group('AgentEvent', () {
    test('AgentLogEvent', () {
      final event = AgentLogEvent('Test log message');
      expect(event.message, 'Test log message');
      expect(event, isA<AgentEvent>());
    });

    test('AgentToolResultEvent', () {
      final event = AgentToolResultEvent(
        toolName: 'test_tool',
        parameters: {'arg': 'val'},
        result: 'success',
      );
      expect(event.toolName, 'test_tool');
      expect(event.parameters, {'arg': 'val'});
      expect(event.result, 'success');
    });

    test('AgentFinalResultEvent', () {
      final event = AgentFinalResultEvent('final answer');
      expect(event.response, 'final answer');
    });

    test('AgentErrorEvent', () {
      final event = AgentErrorEvent('Something went wrong');
      expect(event.error, 'Something went wrong');
    });

    test('AgentAssistantResultEvent', () {
      final event = AgentAssistantResultEvent(
        prompt: 'User prompt',
        response: 'LLM response',
      );
      expect(event.prompt, 'User prompt');
      expect(event.response, 'LLM response');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // McpAgentEngine Tests
  // ═══════════════════════════════════════════════════════════════

  group('McpAgentEngine', () {
    late McpAgentEngine engine;

    setUp(() {
      engine = McpAgentEngine(enableLogging: false);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('setAgents registers agents', () {
      final agent = Agent(
        key: 'test',
        name: 'Test',
        llmConfig: const LlmConfig(
          provider: LlmProvider.none,
          model: '',
          apiKey: '',
        ),
      );
      engine.setAgents([agent]);
      final agents = engine.getAgents();
      expect(agents.length, 1);
      expect(agents.first.key, 'test');
    });

    test('getAgents returns empty when no agents registered', () {
      expect(engine.getAgents(), isEmpty);
    });

    test('statusOf returns null for unknown agent', () {
      expect(engine.statusOf('unknown'), isNull);
    });

    test('run with unknown agent throws and sets error status', () async {
      try {
        await engine.run('unknown');
        fail('Should have thrown');
      } catch (e) {
        expect(e, isA<ArgumentError>());
      }
      expect(engine.statusOf('unknown'), AgentStatus.error);
    });

    test('agentEvents stream receives events', () async {
      final events = <AgentEvent>[];
      final sub = engine.agentEvents.listen(events.add);

      // Trigger an error event by running unknown agent
      try {
        await engine.run('nonexistent');
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 100));
      expect(events, isNotEmpty);
      expect(events.any((e) => e is AgentErrorEvent), true);

      await sub.cancel();
    });

    test('cancel tokens work', () {
      engine.cancel('test-agent');
      // cancel should not throw even if agent doesn't exist
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // LLMResponse / LLMToolCall Tests
  // ═══════════════════════════════════════════════════════════════

  group('LLMResponse', () {
    test('create with text only', () {
      const response = LLMResponse(text: 'Hello world');
      expect(response.text, 'Hello world');
      expect(response.toolCalls, isEmpty);
    });

    test('create with tool calls', () {
      final toolCalls = [
        const LLMToolCall(
          id: 'call_1',
          name: 'get_weather',
          arguments: {'city': 'Vienna'},
        ),
      ];
      final response = LLMResponse(text: '', toolCalls: toolCalls);
      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.name, 'get_weather');
      expect(response.toolCalls.first.arguments, {'city': 'Vienna'});
    });
  });
}

/// Simple test implementation of [McpLocalTool].
class _TestLocalTool extends McpLocalTool {
  @override
  String get name => 'test_tool';

  @override
  String get description => 'A test tool';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'input': {'type': 'string'},
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    return MCPToolResult(
      content: [
        MCPContent(type: 'text', text: 'Executed: ${arguments['input']}'),
      ],
    );
  }
}
