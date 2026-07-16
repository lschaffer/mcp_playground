---
name: "embedded-weather-assistant"
description: "Get weather forecasts using an embedded on-device LLM with Open-Meteo API tools."
compatibility: "Universal"
metadata:
  original_name: "embedded-weather-assistant"
  author: "mcp_playground"
  required_capabilities:
    - "weather_retrieval"
  llm_settings:
    provider: "embedded"
    model: ""
    temperature: 0.2
    max_tokens: 4096
    is_slm: false
    is_multi_modal: true
    thinking: false
    use_native_tool_call: true
    use_safe_tool_call: false
    enable_tool_parameter_auto_recovery: true
  mcp_servers:
  python_tools:
  workflow:
    prompt: "show next 24 hours forecast from Rome,Italy, list all 24 hours individually without summarizing"
    chat_mode: false
    stop_after_tool_call: false
    agents:
      - id: "embedded-weather-assistant"
        name: "Embedded Weather Assistant"
        system_prompt: "You are an AI assistant specialized in weather forecasts. Use the weather tools to answer user questions."
        prompt: "show next 24 hours forecast from Rome,Italy, list all 24 hours individually without summarizing"
        chat_mode: false
        stop_after_tool_call: false
        mcp_tools:
        internal_mcps:
          - "weather_retrieval"
    edges:
---
# Embedded Weather Assistant

A skill that provides weather forecasts using an on-device (embedded) LLM with Open-Meteo API tools running locally via `llamadart`.

## Required Capabilities
This skill requires the following capabilities to be provided by the host:
- `weather_retrieval`

## Procedure
show next 24 hours forecast from Rome,Italy, list all 24 hours individually without summarizing
