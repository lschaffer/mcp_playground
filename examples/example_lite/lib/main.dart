import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
import 'env_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvLoader.load();
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
          seedColor: const Color.fromARGB(255, 3, 97, 36),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 4, 83, 17),
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
    final initialLlm = LlmConfig(
      provider: EnvLoader.getProvider(),
      model: EnvLoader.get('LLM_MODEL', defaultValue: 'gpt-4o'),
      apiKey: EnvLoader.get(
        'LLM_API_KEY',
        defaultValue: 'sk-placeholder-api-key',
      ),
      baseUrl: EnvLoader.get('LLM_URL'),
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

    return McpPlayground(
      initialLlmConfig: initialLlm,
      initialLocalMcpServers: initialLocalServers,
      disableConfigDialog: true,
    );
  }
}
