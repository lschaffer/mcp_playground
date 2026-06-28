import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
import 'example_local_tools.dart';
import 'env_loader.dart';

class ExampleUiPage extends StatelessWidget {
  const ExampleUiPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ── Register custom local (Dart-native) MCP tools ──────────────
    // These tools are passed via customLocalTools and demonstrate how
    // consumers can add their own Dart-native tool implementations.
    final sshDefaults = <String, dynamic>{
      'host': EnvLoader.get('LOCAL_MCP_SSH_HOST', defaultValue: ''),
      'port': int.tryParse(EnvLoader.get('LOCAL_MCP_SSH_PORT')) ?? 22,
      'username': EnvLoader.get('LOCAL_MCP_SSH_USER', defaultValue: ''),
      'password': EnvLoader.get('LOCAL_MCP_SSH_PASSW', defaultValue: ''),
    };

    final List<McpLocalTool> demoLocalTools = [
      // --- Weather tools (free Open-Meteo API, no key required) ---
      GetCurrentWeatherTool(),
      GetHourlyForecastTool(),
      GetDailyForecastTool(),
      GeocodeWeatherCityTool(),

      // --- SSH/SFTP tools (requires the dartssh2 package) ---
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

    // Load initial LLM configuration if configured in .env
    final initialLlm = LlmConfig(
      provider: EnvLoader.getProvider(),
      model: EnvLoader.get('LLM_MODEL', defaultValue: 'gpt-4o-mini'),
      apiKey: EnvLoader.get('LLM_API_KEY'),
      baseUrl: EnvLoader.get('LLM_URL'),
    );

    // Return the playground widget with custom tools registered.
    return McpPlayground(
      initialLlmConfig: initialLlm.provider != LlmProvider.none ? initialLlm : null,
      customLocalTools: demoLocalTools,
    );
  }
}
