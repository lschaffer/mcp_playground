import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

void main() {
  runApp(const McpPlaygroundExampleLiteApp());
}

class McpPlaygroundExampleLiteApp extends StatelessWidget {
  const McpPlaygroundExampleLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP Playground Example Lite',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 18, 130, 234),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 2, 19, 65),
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
    // A preconfigured LLM setup so that disableConfiguDialog: true works.
    const initialLlm = LlmConfig(
      provider: LlmProvider.openai,
      model: 'gpt-4o',
      apiKey: 'sk-placeholder-api-key',
    );

    // Initial local MCP servers setup with git and filesystem configs
    const initialLocalServers = [
      LocalMcpServerSetup(
        name: 'Filesystem',
        type: 'nodejs',
        method: 'npx',
        packageOrServerName: '@modelcontextprotocol/server-filesystem',
        launchArguments: 'c:\\',
        reinstall: false,
      ),
      LocalMcpServerSetup(
        name: 'Git',
        type: 'python',
        method: 'uvx',
        packageOrServerName: 'mcp-server-git',
        launchArguments: '',
        reinstall: false,
      ),
    ];

    return const McpPlayground(
      initialLlmConfig: initialLlm,
      initialLocalMcpServers: initialLocalServers,
      disableConfiguDialog: true,
    );
  }
}
