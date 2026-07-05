import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import 'mcp_client.dart';

/// Stdio JSON-RPC 2.0 Client for local MCP servers running as child processes.
class LocalMCPClient extends MCPClient {
  final McpServerConfig serverConfig;
  Process? _process;
  bool _isConnectedLocal = false;
  List<MCPTool> _availableToolsLocal = [];
  int _nextId = 1;
  final StreamController<Map<String, dynamic>> _responseController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _stdoutSub;

  LocalMCPClient(this.serverConfig, {McpLogCallback? logCallback})
    : super(serverConfig.url, logCallback: logCallback);

  void _log(String message, {bool isError = false}) {
    if (logCallback != null) {
      logCallback!(message, isError: isError);
    }
  }

  @override
  bool get isConnected => _isConnectedLocal;

  @override
  List<MCPTool> get availableTools => List.unmodifiable(_availableToolsLocal);

  @override
  Future<void> connect() async {
    try {
      _log('Connecting to local MCP server: ${serverConfig.name}');
      final dir = await LocalMcpRuntime.serverDir(serverConfig.id);
      final args = LocalMcpRuntime.buildLaunchArgs(serverConfig);
      final env = LocalMcpRuntime.augmentedEnv(
        baseEnv: serverConfig.localEnvVars,
      );

      late String exe;
      late List<String> cmdArgs;

      if (serverConfig.customLaunchCommand != null &&
          serverConfig.customLaunchCommand!.trim().isNotEmpty) {
        final cmdParts = _parseCommand(serverConfig.customLaunchCommand!);
        exe = cmdParts.first;
        cmdArgs = [...cmdParts.sublist(1), ...args];
      } else if (serverConfig.localInstallMethod == 'uvx') {
        final uvx = await LocalMcpRuntime.detectUv();
        if (uvx == null) {
          throw const LocalMcpException(
            'uvx not found on PATH. Please install uv and restart the app.',
          );
        }
        exe = uvx;
        cmdArgs = [serverConfig.localPackage ?? serverConfig.name, ...args];
      } else if (serverConfig.localInstallMethod == 'npm') {
        final node = await LocalMcpRuntime.detectNode();
        if (node == null) {
          throw const LocalMcpException(
            'Node.js (18+) not found. Please install Node.js and restart the app.',
          );
        }
        exe = LocalMcpRuntime.siblingTool(node, 'npx');
        cmdArgs = [
          '-y',
          serverConfig.localPackage ?? serverConfig.name,
          ...args,
        ];
      } else if (serverConfig.localInstallMethod == 'npx') {
        final node = await LocalMcpRuntime.detectNode();
        if (node == null) {
          throw const LocalMcpException(
            'Node.js (18+) not found. Please install Node.js and restart the app.',
          );
        }
        exe = LocalMcpRuntime.siblingTool(node, 'npx');
        cmdArgs = [
          '-y',
          serverConfig.localPackage ?? serverConfig.name,
          ...args,
        ];
      } else if (serverConfig.localCommand != null &&
          serverConfig.localCommand!.trim().isNotEmpty &&
          serverConfig.localInstallMethod != 'pip' &&
          serverConfig.localInstallMethod != 'uvx' &&
          serverConfig.localInstallMethod != 'npm' &&
          serverConfig.localInstallMethod != 'npx') {
        final cmdParts = _parseCommand(serverConfig.localCommand!);
        exe = cmdParts.first;
        cmdArgs = [...cmdParts.sublist(1), ...args];
      } else {
        final pythonExe = LocalMcpRuntime.pythonVenvExe(dir);
        if (!await File(pythonExe).exists()) {
          _log(
            'Virtual environment executable is missing. Initializing .venv...',
          );
          final error = await LocalMcpRuntime.install(serverConfig);
          if (error != null) {
            throw LocalMcpException(
              'Virtual environment initialization failed: $error',
            );
          }
          if (!await File(pythonExe).exists()) {
            throw const LocalMcpException(
              'Virtual environment executable is still missing after installation.',
            );
          }
        }
        exe = pythonExe;
        final entry = (serverConfig.localPackage ?? '').trim();
        if (entry.toLowerCase().endsWith('.py') || entry.contains('.py')) {
          cmdArgs = [entry, ...args];
        } else {
          cmdArgs = [
            '-m',
            entry.isNotEmpty ? entry : serverConfig.name,
            ...args,
          ];
        }
      }

      final bool runInShell =
          Platform.isWindows &&
          (exe.endsWith('.bat') ||
              exe.endsWith('.cmd') ||
              exe.contains('npx') ||
              exe.contains('npm') ||
              !p.basename(exe).contains('.'));

      _process = await Process.start(
        exe,
        cmdArgs,
        environment: env,
        workingDirectory: dir,
        runInShell: runInShell,
      );

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onStdoutLine,
            onError: (e) {
              _log('stdout error: $e', isError: true);
            },
          );

      _process!.stderr.transform(utf8.decoder).listen((chunk) {
        _log('stderr: ${chunk.trim()}', isError: true);
      });

      final initResp = await _sendRpcRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'Dart Local MCP Client', 'version': '1.0.0'},
      });
      if (initResp.containsKey('error')) {
        _log('initialize error: ${initResp['error']}', isError: true);
      }

      final initializedEnvelope = {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': {},
      };
      _process!.stdin.writeln(jsonEncode(initializedEnvelope));
      await _process!.stdin.flush();

      final toolsResp = await _sendRpcRequest('tools/list', null);
      final result = toolsResp['result'];
      if (result != null && result['tools'] is List) {
        _availableToolsLocal = (result['tools'] as List)
            .map((tool) => MCPTool.fromJson(tool))
            .toList();
      }

      _isConnectedLocal = true;
      _log(
        'Connected successfully via Stdio. Tools registered: ${_availableToolsLocal.length}',
      );
    } catch (e) {
      _log('Failed to connect: $e', isError: true);
      _isConnectedLocal = false;
      _process?.kill();
      _process = null;
      rethrow;
    }
  }

  void _onStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final msg = jsonDecode(trimmed) as Map<String, dynamic>;
      _responseController.add(msg);
    } catch (e) {
      _log('Unparseable stdio line: $trimmed', isError: true);
    }
  }

  Future<Map<String, dynamic>> _sendRpcRequest(
    String method,
    Map<String, dynamic>? params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_process == null) {
      throw Exception('Process not running');
    }
    final id = _nextId++;
    final envelope = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };

    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription sub;
    sub = _responseController.stream.listen((msg) {
      if (msg['id'] == id) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete(msg);
      }
    });

    _process!.stdin.writeln(jsonEncode(envelope));
    await _process!.stdin.flush();

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub.cancel();
        throw TimeoutException(
          'Local MCP request "$method" timed out after ${timeout.inSeconds}s',
        );
      },
    );
  }

  @override
  Future<MCPToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      _log('Calling local tool: $name');
      final resp = await _sendRpcRequest('tools/call', {
        'name': name,
        'arguments': arguments,
      });

      if (resp.containsKey('error')) {
        final err = resp['error'];
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error (${err['code']}): ${err['message']}',
            ),
          ],
          isError: true,
        );
      }

      final result = resp['result'] as Map<String, dynamic>? ?? {};
      if (result['content'] is List) {
        return MCPToolResult.fromJson(result);
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: jsonEncode(result))],
        isError: false,
      );
    } catch (e) {
      _log('Local tool call failed: $e', isError: true);
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Error: $e')],
        isError: true,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnectedLocal = false;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    if (_process != null) {
      _process!.kill();
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _process = null;
    _availableToolsLocal = [];
    _log('Disconnected local server: ${serverConfig.name}');
  }

  @override
  void dispose() {
    disconnect();
    _responseController.close();
  }

  List<String> _parseCommand(String command) {
    final parts = <String>[];
    var current = StringBuffer();
    var inQuotes = false;
    var quoteChar = '';

    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if ((char == '"' || char == "'") && (i == 0 || command[i - 1] != '\\')) {
        if (inQuotes && char == quoteChar) {
          inQuotes = false;
        } else if (!inQuotes) {
          inQuotes = true;
          quoteChar = char;
        }
      } else if (char == ' ' && !inQuotes) {
        if (current.isNotEmpty) {
          parts.add(current.toString());
          current = StringBuffer();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) {
      parts.add(current.toString());
    }
    return parts.isNotEmpty ? parts : [command];
  }
}

// ═══════════════════════════════════════════════════════════════
// Install / Execution Steps & Runtime Helpers
// ═══════════════════════════════════════════════════════════════

enum LocalInstallStep { detecting, installing, done, failed }

class LocalInstallProgress {
  final LocalInstallStep step;
  final String message;
  const LocalInstallProgress(this.step, this.message);
}

class LocalMcpException implements Exception {
  final String message;
  const LocalMcpException(this.message);
  @override
  String toString() => 'LocalMcpException: $message';
}

class LocalMcpRuntime {
  static Future<String> get _rootDir async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory(p.join(home, '.mcp_playground', 'mcp-local-servers'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> serverDir(String serverId) async {
    final root = await _rootDir;
    final dir = Directory(p.join(root, serverId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static String _pipExe(String dir) {
    return Platform.isWindows
        ? p.join(dir, '.venv', 'Scripts', 'pip.exe')
        : p.join(dir, '.venv', 'bin', 'pip');
  }

  static String pythonVenvExe(String dir) {
    return Platform.isWindows
        ? p.join(dir, '.venv', 'Scripts', 'python.exe')
        : p.join(dir, '.venv', 'bin', 'python');
  }

  static List<String> _unixCandidates(String name) {
    final home = Platform.environment['HOME'] ?? '';
    final pathEnv = Platform.environment['PATH'] ?? '';
    final fromPath = pathEnv
        .split(':')
        .where((s) => s.isNotEmpty)
        .map((dir) => p.join(dir, name));

    return {
      name,
      ...fromPath,
      '/usr/local/bin/$name',
      '/opt/homebrew/bin/$name',
      '/usr/bin/$name',
      '/bin/$name',
      if (home.isNotEmpty) p.join(home, '.local', 'bin', name),
    }.toList();
  }

  static Future<String?> _resolveViaShell(String toolName) async {
    if (Platform.isWindows) return null;
    try {
      final result = await Process.run('/bin/zsh', [
        '-lc',
        'command -v $toolName',
      ]);
      final resolved = (result.stdout as String?)?.trim() ?? '';
      if (result.exitCode == 0 && resolved.isNotEmpty) {
        return resolved;
      }
    } catch (_) {}
    try {
      final result = await Process.run('/bin/bash', [
        '-lc',
        'command -v $toolName',
      ]);
      final resolved = (result.stdout as String?)?.trim() ?? '';
      if (result.exitCode == 0 && resolved.isNotEmpty) {
        return resolved;
      }
    } catch (_) {}
    return null;
  }

  static String siblingTool(String exePath, String tool) {
    if (!p.isAbsolute(exePath)) {
      return Platform.isWindows ? '$tool.cmd' : tool;
    }
    return Platform.isWindows
        ? p.join(p.dirname(exePath), '$tool.cmd')
        : p.join(p.dirname(exePath), tool);
  }

  static Map<String, String> augmentedEnv({
    Map<String, String>? baseEnv,
    String? extraPath,
  }) {
    final env = Map<String, String>.from(Platform.environment);
    if (baseEnv != null) {
      env.addAll(baseEnv);
    }
    if (Platform.isWindows) return env;

    final currentPath = env['PATH'] ?? '';
    final List<String> paths = currentPath
        .split(':')
        .where((p) => p.isNotEmpty)
        .toList();

    const standardPaths = [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
    ];
    for (final p in standardPaths) {
      if (!paths.contains(p)) {
        paths.add(p);
      }
    }
    if (extraPath != null &&
        extraPath.isNotEmpty &&
        !paths.contains(extraPath)) {
      paths.insert(0, extraPath);
    }

    env['PATH'] = paths.join(':');
    return env;
  }

  static Future<String?> detectUv() async {
    final shellResolved = await _resolveViaShell('uvx');
    final candidates = Platform.isWindows
        ? ['uvx.exe', 'uvx']
        : [?shellResolved, ..._unixCandidates('uvx')];
    for (final exe in candidates) {
      try {
        final result = await Process.run(exe, [
          '--version',
        ], runInShell: Platform.isWindows);
        if (result.exitCode == 0) return exe;
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> detectNode() async {
    final shellResolved = await _resolveViaShell('node');
    final candidates = Platform.isWindows
        ? ['node.exe', 'node']
        : [?shellResolved, ..._unixCandidates('node')];
    for (final exe in candidates) {
      try {
        final result = await Process.run(exe, [
          '--version',
        ], runInShell: Platform.isWindows);
        if (result.exitCode == 0) {
          final version = (result.stdout as String).trim();
          final major =
              int.tryParse(
                version.replaceFirst(RegExp(r'^v'), '').split('.').first,
              ) ??
              0;
          if (major >= 18) return exe;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> detectPython() async {
    final shellResolvedPy3 = await _resolveViaShell('python3');
    final shellResolvedPy = await _resolveViaShell('python');
    final candidates = Platform.isWindows
        ? ['python', 'python3']
        : [
            ?shellResolvedPy3,
            ?shellResolvedPy,
            'python3',
            'python',
            '/usr/local/bin/python3',
            '/opt/homebrew/bin/python3',
            '/usr/bin/python3',
          ];
    for (final exe in candidates) {
      try {
        final result = await Process.run(exe, [
          '--version',
        ], runInShell: Platform.isWindows);
        final out = (result.stdout as String?) ?? '';
        final err = (result.stderr as String?) ?? '';
        final version = (out.isNotEmpty ? out : err).trim();
        if (result.exitCode == 0 &&
            version.toLowerCase().contains('python 3')) {
          return exe;
        }
      } catch (_) {}
    }
    return null;
  }

  static List<String> buildLaunchArgs(McpServerConfig server) {
    if (server.customLaunchCommand != null &&
        server.customLaunchCommand!.trim().isNotEmpty) {
      return [];
    }
    final isStandardMethod =
        server.localInstallMethod == 'uvx' ||
        server.localInstallMethod == 'pip' ||
        server.localInstallMethod == 'npm' ||
        server.localInstallMethod == 'npx';
    if (!isStandardMethod &&
        server.localCommand != null &&
        server.localCommand!.contains(' ')) {
      return [];
    }
    final rawArgs = server.url.trim();
    if (rawArgs.isEmpty) return [];

    final args = rawArgs.split(' ').where((s) => s.trim().isNotEmpty).toList();
    final Map<String, String> vars = server.localEnvVars ?? {};

    return args.map((arg) {
      var output = arg;
      for (final entry in vars.entries) {
        output = output.replaceAll('{{${entry.key}}}', entry.value);
      }
      return output;
    }).toList();
  }

  static Future<String?> install(
    McpServerConfig server, {
    void Function(LocalInstallProgress)? onProgress,
  }) async {
    final method = server.localInstallMethod;

    if (method == 'uvx') {
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.detecting,
          'Checking for uvx...',
        ),
      );
      final uvx = await detectUv();
      if (uvx == null) {
        return 'uvx executable not found. Please install uv and try again.';
      }
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.done,
          'uvx server marked ready.',
        ),
      );
      return null;
    } else if (method == 'npx') {
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.detecting,
          'Checking for Node.js...',
        ),
      );
      final node = await detectNode();
      if (node == null) {
        return 'Node.js (version 18+) not found. Please install Node.js and try again.';
      }
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.done,
          'npx server marked ready.',
        ),
      );
      return null;
    } else if (method == 'npm') {
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.detecting,
          'Checking for Node.js...',
        ),
      );
      final node = await detectNode();
      if (node == null) {
        return 'Node.js (version 18+) not found. Please install Node.js and try again.';
      }
      final npm = siblingTool(node, 'npm');
      final pkgName = server.localPackage ?? server.name;
      onProgress?.call(
        LocalInstallProgress(
          LocalInstallStep.installing,
          'npm install -g $pkgName...',
        ),
      );
      try {
        final result = await Process.run(
          npm,
          ['install', '-g', pkgName],
          environment: augmentedEnv(
            extraPath: p.isAbsolute(npm) ? p.dirname(npm) : null,
          ),
          runInShell: Platform.isWindows,
        );
        if (result.exitCode != 0) {
          return 'npm install failed with exit code ${result.exitCode}: ${result.stderr}';
        }
      } catch (e) {
        return 'npm install execution failed: $e';
      }
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.done,
          'Package installed successfully.',
        ),
      );
      return null;
    } else {
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.detecting,
          'Checking for Python 3...',
        ),
      );
      final python = await detectPython();
      if (python == null) {
        return 'Python 3 not found on PATH. Please install Python and try again.';
      }
      final dir = await serverDir(server.id);
      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.installing,
          'Creating virtual environment...',
        ),
      );
      try {
        final venvResult = await Process.run(
          python,
          ['-m', 'venv', '.venv'],
          workingDirectory: dir,
          runInShell: Platform.isWindows,
        );
        if (venvResult.exitCode != 0) {
          return 'Python venv creation failed: ${venvResult.stderr}';
        }
      } catch (e) {
        return 'Python venv creation execution failed: $e';
      }

      final pip = _pipExe(dir);
      final pkgSpec = server.localPackage ?? '';
      onProgress?.call(
        LocalInstallProgress(
          LocalInstallStep.installing,
          'pip install $pkgSpec...',
        ),
      );
      try {
        final isRequirements =
            pkgSpec.trim().toLowerCase().endsWith('.txt') ||
            pkgSpec.contains('/requirements');
        final pipArgs = isRequirements
            ? ['install', '-r', pkgSpec]
            : ['install', pkgSpec];
        final pipResult = await Process.run(
          pip,
          pipArgs,
          workingDirectory: dir,
          runInShell: Platform.isWindows,
        );
        if (pipResult.exitCode != 0) {
          return 'pip install failed: ${pipResult.stderr}';
        }
      } catch (e) {
        return 'pip install execution failed: $e';
      }

      onProgress?.call(
        const LocalInstallProgress(
          LocalInstallStep.done,
          'Virtual environment ready.',
        ),
      );
      return null;
    }
  }

  static Future<void> uninstall(McpServerConfig server) async {
    try {
      final dir = await serverDir(server.id);
      final dirObj = Directory(dir);
      if (await dirObj.exists()) {
        await dirObj.delete(recursive: true);
      }
    } catch (_) {}
  }
}
