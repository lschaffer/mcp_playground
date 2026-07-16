---
name: "local-filesystem-inspector"
description: "List and sort files on the local filesystem using the MCP filesystem server."
compatibility: "Universal"
metadata:
  original_name: "local-filesystem-inspector"
  author: "mcp_playground"
  required_capabilities:
    - "filesystem"
  llm_settings:
    provider: "none"
    model: ""
    temperature: 0.2
    max_tokens: 0
    is_slm: false
    is_multi_modal: true
    thinking: false
    use_native_tool_call: true
    use_safe_tool_call: false
    enable_tool_parameter_auto_recovery: true
  mcp_servers:
  python_tools:
  workflow:
    prompt: "list files except .hex with sizes in C:\\temp sort by size desc show the first 5"
    chat_mode: false
    stop_after_tool_call: false
    agents:
      - id: "local-filesystem-inspector"
        name: "Filesystem Inspector"
        system_prompt: "You are an agent with access to the local filesystem. Find, list, and sort files as requested."
        prompt: "list files except .hex with sizes in C:\\temp sort by size desc show the first 5"
        chat_mode: false
        stop_after_tool_call: false
        mcp_tools:
        internal_mcps:
          - "filesystem"
    edges:
---
# Local Filesystem Inspector

A skill that provides local filesystem inspection capabilities using the MCP filesystem server (`@modelcontextprotocol/server-filesystem`).

## Required Capabilities
This skill requires the following capabilities to be provided by the host:
- `filesystem`

## Procedure
list files except .hex with sizes in C:\temp sort by size desc show the first 5
