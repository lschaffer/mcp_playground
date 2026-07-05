// Pure Dart core for AI Agent Playground.
// Agent execution engine, LLM adapters, MCP clients, and tool orchestration
// — no Flutter dependency.

// Models
export 'src/models/models.dart';

// LLM
export 'src/llm/llm_service.dart';
export 'src/llm/llm_response.dart';

// MCP
export 'src/mcp/mcp_client.dart';
export 'src/mcp/mcp_client_def.dart';
export 'src/mcp/local_tools.dart';
export 'src/mcp/local_mcp_client_stub.dart'
    if (dart.library.io) 'src/mcp/local_mcp_client.dart';

// Agents
export 'src/agents/agents_engine.dart';
export 'src/utils/change_notifier.dart';
