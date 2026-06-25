import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
import 'example_local_tools.dart';

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
          seedColor: const Color(0xFF7C3AED),
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
    // ── Register custom local (Dart-native) MCP tools ──────────────
    // These tools are passed via customLocalTools and demonstrate how
    // consumers can add their own Dart-native tool implementations.
    //
    // The SSH tools receive a callback providing default SSH connection
    // parameters. These defaults can be overridden at call time by
    // providing 'host', 'port', 'username', 'password' arguments.
    final sshDefaults = <String, dynamic>{
      'host': '192.168.1.100',
      'port': 22,
      'username': 'admin',
      'password': 'changeme',
      // Optionally set a private key (PEM) instead of password:
      // 'privateKey': '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
    };

    final List<McpLocalTool> demoLocalTools = [
      // --- Weather tools (free Open-Meteo API, no key required) ---
      GetCurrentWeatherTool(),
      GetHourlyForecastTool(),
      GetDailyForecastTool(),
      GeocodeWeatherCityTool(),

      // --- SSH/SFTP tools (requires the dartssh2 package) ---
      // The callback returns default credentials; the LLM can also
      // supply 'host', 'port', etc. per-call in the tool arguments.
      SshListDirectoryTool(() => sshDefaults),
      SshReadFileTool(() => sshDefaults),
      SshDownloadFileTool(() => sshDefaults),
      SshUploadFileTool(() => sshDefaults),
      SshExecuteCommandTool(() => sshDefaults),
      SshMakeDirectoryTool(() => sshDefaults),
      SshRemoveDirectoryTool(() => sshDefaults),

      // --- Canvas-based chart generator (no extra deps) ---
      CreateChartPngTool(),
    ];

    // Return the playground widget with custom tools registered.
    // LLM provider configurations and HTTP MCP servers are configured
    // by the user dynamically via the widget UI.
    return McpPlayground(customLocalTools: demoLocalTools);
  }
}
