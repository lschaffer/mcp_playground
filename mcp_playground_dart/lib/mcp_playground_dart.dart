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
export 'src/mcp/local_mcp_client.dart'
    if (dart.library.html) 'src/mcp/local_mcp_client_stub.dart';

// Agents
export 'src/agents/agents_engine.dart';
