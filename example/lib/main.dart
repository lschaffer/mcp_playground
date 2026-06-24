import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

void main() {
  runApp(const McpPlaygroundExampleApp());
}

class McpPlaygroundExampleApp extends StatelessWidget {
  const McpPlaygroundExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Playground Example',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED), // Premium violet color
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
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
    // Return the playground widget. The LLM provider configurations, parameters,
    // and HTTP/HTTPS MCP servers are configured by the user dynamically via the widget UI.
    return const McpPlayground();
  }
}
