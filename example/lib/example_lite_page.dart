import 'package:flutter/material.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';
import 'env_loader.dart';

class ExampleLitePage extends StatelessWidget {
  const ExampleLitePage({super.key});

  @override
  Widget build(BuildContext context) {
    // A preconfigured LLM setup so that disableConfigDialog: true works.
    final initialLlm = LlmConfig(
      provider: EnvLoader.getProvider(),
      model: EnvLoader.get('LLM_MODEL', defaultValue: 'gpt-4o'),
      apiKey: EnvLoader.get('LLM_API_KEY', defaultValue: 'sk-placeholder-api-key'),
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
