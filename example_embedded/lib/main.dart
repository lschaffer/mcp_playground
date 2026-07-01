import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
import 'package:mcp_playground_shared_tools/shared_tools.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const McpPlaygroundExampleEmbeddedApp());
}

class McpPlaygroundExampleEmbeddedApp extends StatelessWidget {
  const McpPlaygroundExampleEmbeddedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Playground Example Embedded',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 83, 18, 234),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 92, 2, 83),
          brightness: Brightness.dark,
        ),
      ),
      home: const McpPlaygroundScreen(),
    );
  }
}

class McpPlaygroundScreen extends StatelessWidget {
  const McpPlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<McpLocalTool> demoLocalTools = [
      // --- Weather tools (free Open-Meteo API, no key required) ---
      GetCurrentWeatherTool(),
      GetHourlyForecastTool(),
      GetDailyForecastTool(),
      GeocodeWeatherCityTool(),

      // --- Chart tools ---
      CreateChartPngTool(),
      Chart2PngTool(),
    ];

    // Configure the playground widget with an initial embedded model
    const initialLlm = LlmConfig(
      provider: LlmProvider.embedded,
      model: 'ministral3-3b-instruct q4',
      apiKey: '',
    );

    return Scaffold(
      body: McpPlayground(
        initialLlmConfig: initialLlm,
        customLocalTools: demoLocalTools,
        messageContentBuilder: (context, message) {
          if (message.type != MessageType.toolResponse) return null;
          if (message.toolName != 'create_chart_png') return null;
          final contentText = message.content.trim();
          if (!((contentText.startsWith('{') && contentText.endsWith('}')) ||
              (contentText.startsWith('[') && contentText.endsWith(']')))) {
            return null;
          }

          try {
            final decoded = jsonDecode(contentText);
            if (decoded is! Map<String, dynamic>) return null;

            final chartType = ((decoded['chart_type'] ?? decoded['chartType']) as String? ?? 'line').trim().toLowerCase();
            final labels = ((decoded['labels'] ?? decoded['xAxis']) as List?)?.cast<String>() ?? [];
            final dataList = ((decoded['data'] ?? decoded['yAxis']) as List?)?.map((d) => (d as num).toDouble()).toList() ?? [];

            if (labels.isEmpty || dataList.isEmpty) return null;

            final theme = Theme.of(context);
            final title = (decoded['title'] ?? decoded['chartTitle'] ?? 'Chart').toString();

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 220,
                    child: _renderFlChart(chartType, labels, dataList, theme),
                  ),
                ],
              ),
            );
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }

  Widget _renderFlChart(String type, List<String> labels, List<double> data, ThemeData theme) {
    if (type == 'pie') {
      final List<PieChartSectionData> sections = [];
      for (int i = 0; i < data.length; i++) {
        sections.add(PieChartSectionData(
          color: Colors.primaries[i % Colors.primaries.length],
          value: data[i],
          title: '${labels.length > i ? labels[i] : ""}\n${data[i]}',
          radius: 60,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
      return PieChart(PieChartData(sections: sections, centerSpaceRadius: 40));
    }

    if (type == 'bar') {
      final List<BarChartGroupData> groups = [];
      for (int i = 0; i < data.length; i++) {
        groups.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: data[i],
              color: theme.colorScheme.primary,
              width: 16,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        ));
      }

      return BarChart(
        BarChartData(
          barGroups: groups,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < labels.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(labels[idx], style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      );
    }

    // Default: Line chart
    final List<FlSpot> spots = [];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i]));
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
          )
        ],
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(labels[idx], style: const TextStyle(fontSize: 10)),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
      ),
    );
  }
}
