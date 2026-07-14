---
name: population-chart-generator
description: Multi-step skill that searches for population data of countries and generates an HTML bar chart
version: 1.0.0
author: mcp_playground
system_prompt: |
  You are a data research assistant. Use the web_search tool to find current population data,
  then use the create_html_chart tool to generate a bar chart from the results.
  Always present the data clearly before creating the chart.

prompts:
  - text: Search for the population of France and Italy in 2026. Return the exact numbers.
    tools: [web_search]
    stop_after_tool_call: true
  - text: Using the population data from the previous step, create an HTML bar chart comparing France and Italy. The chart title should be "Population Comparison 2026"
    tools: [create_html_chart]

tools:
  - name: web_search
    description: Search the web for information using DuckDuckGo Instant Answer API
    runtime: dart
    capability: web_search
    input_schema:
      type: object
      properties:
        query: {type: string, description: The search query}
      required: [query]

  - name: create_html_chart
    description: Generate an HTML file containing a bar chart from provided data
    runtime: dart
    capability: chart_generation
    input_schema:
      type: object
      properties:
        title: {type: string, description: Chart title}
        labels: {type: array, items: {type: string}, description: X-axis labels}
        values: {type: array, items: {type: number}, description: Y-axis values}
        x_label: {type: string, description: X-axis label}
        y_label: {type: string, description: Y-axis label}
      required: [title, labels, values]

mcp_playground:
  chat_mode: false
  is_multi_turn: true
  created_at: "2026-07-14T20:00:00Z"
---

# Population Chart Generator

This skill demonstrates multi-turn agent workflow:
1. Search the web for population data
2. Generate an HTML bar chart from the results

## Tools Used
- **web_search**: DuckDuckGo Instant Answer API (free, no API key)
- **create_html_chart**: Generates an HTML file with Chart.js bar chart
