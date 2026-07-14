import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

/// Searches the web using DuckDuckGo Instant Answer API.
///
/// Free to use, no API key required. Returns abstract, related topics,
/// and external links from DuckDuckGo.
class WebSearchTool extends McpLocalTool {
  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web for information. Returns abstracts and related topics from DuckDuckGo. '
      'Use this to find population data, facts, and current information.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'The search query (e.g. "France population 2026")',
      },
    },
    'required': ['query'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final query = arguments['query'] as String? ?? '';
      if (query.isEmpty) {
        return const MCPToolResult(
          content: [
            MCPContent(type: 'text', text: 'Error: query is required.'),
          ],
          isError: true,
        );
      }

      final url =
          'https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json&no_html=1&skip_disambig=1';

      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Search failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final buffer = StringBuffer();

      buffer.writeln('### Web Search Results for: "$query"');
      buffer.writeln();

      // Abstract
      final abstract = data['AbstractText'] as String?;
      final abstractUrl = data['AbstractURL'] as String?;
      final abstractSource = data['AbstractSource'] as String?;

      if (abstract != null && abstract.isNotEmpty) {
        buffer.writeln('**Summary:** $abstract');
        if (abstractSource != null) buffer.writeln('Source: $abstractSource');
        if (abstractUrl != null) buffer.writeln('URL: $abstractUrl');
        buffer.writeln();
      }

      // Answer
      final answer = data['Answer'] as String?;
      if (answer != null && answer.isNotEmpty) {
        buffer.writeln('**Instant Answer:** $answer');
        buffer.writeln();
      }

      // Related Topics
      final relatedTopics = data['RelatedTopics'] as List?;
      if (relatedTopics != null && relatedTopics.isNotEmpty) {
        buffer.writeln('**Related Results:**');
        for (final topic in relatedTopics) {
          if (topic is Map) {
            final text = topic['Text'] as String?;
            final url = topic['FirstURL'] as String?;
            if (text != null && text.isNotEmpty) {
              buffer.writeln('- $text');
              if (url != null) buffer.writeln('  $url');
            }
          }
        }
      }

      // If nothing useful was found
      if (buffer.length < 50) {
        buffer.writeln(
          '(No detailed results found. The query may be too specific. '
          'Try a broader search like "population of France".)',
        );
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Web search error: $e')],
        isError: true,
      );
    }
  }
}

/// Generates an HTML file with a Chart.js bar chart from provided data.
///
/// The HTML file is saved to the current directory and can be opened in a browser.
class HtmlChartTool extends McpLocalTool {
  @override
  String get name => 'create_html_chart';

  @override
  String get description =>
      'Creates an HTML file containing a bar chart using Chart.js. '
      'Provide a title, labels (categories), and values (numbers). '
      'The generated file can be opened in any web browser. '
      'Returns the path to the generated HTML file.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'The chart title'},
      'labels': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Labels for each bar (e.g. ["France", "Italy"])',
      },
      'values': {
        'type': 'array',
        'items': {'type': 'number'},
        'description':
            'Numeric values for each bar (e.g. [68000000, 59000000])',
      },
      'x_label': {
        'type': 'string',
        'description': 'X-axis label (e.g. "Country")',
      },
      'y_label': {
        'type': 'string',
        'description': 'Y-axis label (e.g. "Population")',
      },
    },
    'required': ['title', 'labels', 'values'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final title = arguments['title'] as String? ?? 'Chart';
      final xLabel = arguments['x_label'] as String? ?? 'Category';
      final yLabel = arguments['y_label'] as String? ?? 'Value';

      final labelsRaw = arguments['labels'] as List? ?? [];
      final valuesRaw = arguments['values'] as List? ?? [];

      final labels = labelsRaw.map((e) => e.toString()).toList();
      final values = valuesRaw
          .map((e) => (e is num) ? e.toDouble() : 0.0)
          .toList();

      if (labels.isEmpty || values.isEmpty) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: labels and values arrays must not be empty.',
            ),
          ],
          isError: true,
        );
      }

      // Generate a unique filename
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      final filename = 'chart_$timestamp.html';

      // Build the HTML with Chart.js
      final html = _buildHtml(
        title: title,
        xLabel: xLabel,
        yLabel: yLabel,
        labels: labels,
        values: values,
      );

      // Save to current directory
      final file = File(filename);
      await file.writeAsString(html);
      final fullPath = file.absolute.path;

      return MCPToolResult(
        content: [
          MCPContent(
            type: 'text',
            text:
                'Bar chart generated successfully!\n\n'
                '**File:** $fullPath\n'
                '**Title:** $title\n'
                '**Data:**\n${_formatDataTable(labels, values)}\n\n'
                'Open the HTML file in your browser to view the chart.',
          ),
        ],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Chart generation error: $e')],
        isError: true,
      );
    }
  }

  String _formatDataTable(List<String> labels, List<double> values) {
    final buf = StringBuffer();
    for (var i = 0; i < labels.length; i++) {
      buf.writeln('  ${labels[i]}: ${_formatNumber(values[i])}');
    }
    return buf.toString();
  }

  String _formatNumber(double value) {
    if (value >= 1e9) {
      return '${(value / 1e9).toStringAsFixed(1)} billion';
    } else if (value >= 1e6) {
      return '${(value / 1e6).toStringAsFixed(1)} million';
    }
    return value.toStringAsFixed(0);
  }

  String _buildHtml({
    required String title,
    required String xLabel,
    required String yLabel,
    required List<String> labels,
    required List<double> values,
  }) {
    final labelsJson = jsonEncode(labels);
    final valuesJson = jsonEncode(values);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      background: #f5f5f5;
    }
    .chart-container {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.1);
      width: 90%;
      max-width: 700px;
    }
    h2 {
      text-align: center;
      color: #333;
      margin-top: 0;
    }
  </style>
</head>
<body>
  <div class="chart-container">
    <h2>$title</h2>
    <canvas id="chart"></canvas>
  </div>
  <script>
    const ctx = document.getElementById('chart').getContext('2d');
    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: $labelsJson,
        datasets: [{
          label: '$yLabel',
          data: $valuesJson,
          backgroundColor: [
            'rgba(54, 162, 235, 0.8)',
            'rgba(255, 99, 132, 0.8)',
            'rgba(75, 192, 192, 0.8)',
            'rgba(255, 206, 86, 0.8)',
            'rgba(153, 102, 255, 0.8)',
          ],
          borderColor: [
            'rgba(54, 162, 235, 1)',
            'rgba(255, 99, 132, 1)',
            'rgba(75, 192, 192, 1)',
            'rgba(255, 206, 86, 1)',
            'rgba(153, 102, 255, 1)',
          ],
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false }
        },
        scales: {
          y: {
            beginAtZero: false,
            title: {
              display: true,
              text: '$yLabel'
            }
          },
          x: {
            title: {
              display: true,
              text: '$xLabel'
            }
          }
        }
      }
    });
  </script>
</body>
</html>''';
  }
}
