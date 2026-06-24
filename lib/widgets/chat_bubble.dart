import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isSystem = message.role == ChatRole.system;


    if (message.type == MessageType.toolCall) {
      return _buildToolCallBubble(context, theme);
    }

    if (message.type == MessageType.toolResponse && message.toolResult != null) {
      final hasChart = message.toolResult!.content.any((c) => c.type == 'chart');
      if (hasChart) {
        return _buildChartBubble(context, theme);
      }
      return _buildToolResponseBubble(context, theme);
    }

    if (isSystem || message.type == MessageType.log) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              radius: 16,
              child: Icon(Icons.smart_toy_outlined, size: 18, color: theme.colorScheme.onPrimaryContainer),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.content,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface),
                      code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              radius: 16,
              child: Icon(Icons.person_outline, size: 18, color: theme.colorScheme.onPrimary),
            ),
        ],
      ),
    );
  }

  Widget _buildToolCallBubble(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: ExpansionTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.amber.withValues(alpha: 0.15),
          radius: 14,
          child: const Icon(Icons.build_outlined, size: 14, color: Colors.amber),
        ),
        title: Text(
          'Tool Execution Call: ${message.toolName}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: theme.colorScheme.surfaceContainerLowest,
            child: Text(
              const JsonEncoder.withIndent('  ').convert(message.toolArguments ?? {}),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildToolResponseBubble(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: ExpansionTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          radius: 14,
          child: const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
        ),
        title: Text(
          'Tool Response received: ${message.toolName}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: theme.colorScheme.surfaceContainerLowest,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                message.content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChartBubble(BuildContext context, ThemeData theme) {
    final chartContent = message.toolResult!.content.firstWhere((c) => c.type == 'chart');
    Map<String, dynamic> chartData = {};
    try {
      chartData = jsonDecode(chartContent.text ?? '{}') as Map<String, dynamic>;
    } catch (_) {}

    final title = chartData['title'] as String? ?? 'Data Chart';
    final chartType = chartData['chart_type'] as String? ?? 'line';
    final labels = (chartData['labels'] as List?)?.cast<String>() ?? [];
    final data = (chartData['data'] as List?)?.map((d) => (d as num).toDouble()).toList() ?? [];

    if (labels.isEmpty || data.isEmpty) {
      return const SizedBox.shrink();
    }

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
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: _renderChart(chartType, labels, data, theme),
          ),
        ],
      ),
    );
  }

  Widget _renderChart(String type, List<String> labels, List<double> data, ThemeData theme) {
    if (type == 'pie') {
      final List<PieChartSectionData> sections = [];
      for (int i = 0; i < data.length; i++) {
        sections.add(PieChartSectionData(
          color: Colors.primaries[i % Colors.primaries.length],
          value: data[i],
          title: '${labels[i]}\n${data[i]}',
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
