import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dartssh2/dartssh2.dart';
import 'models.dart';


/// Base class representing a Dart-native local tool.
abstract class McpLocalTool {
  String get name;
  String get description;
  Map<String, dynamic> get inputSchema;
  Future<MCPToolResult> execute(Map<String, dynamic> arguments);

  /// Convert to standard MCPTool model representation.
  MCPTool toMCPTool() {
    return MCPTool(
      name: name,
      description: description,
      inputSchema: inputSchema,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 1. Weather Tool (Open-Meteo REST API)
// ═══════════════════════════════════════════════════════════════

class WeatherLocalTool extends McpLocalTool {
  static const String _baseUrl = 'https://api.open-meteo.com/v1';
  static const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

  @override
  String get name => 'weather_forecast';

  @override
  String get description =>
      'Fetch current weather conditions and daily forecasts for a city name or latitude/longitude coordinates (free, no API key).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'location': {
            'type': 'string',
            'description': 'City name (e.g. "Vienna") or coordinates "lat,lng" (e.g. "48.2082,16.3738").'
          },
          'days': {
            'type': 'integer',
            'description': 'Number of forecast days (1-16, default: 7)',
            'default': 7
          }
        },
        'required': ['location'],
      };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final location = arguments['location'] as String? ?? '';
    final days = arguments['days'] as int? ?? 7;

    if (location.trim().isEmpty) {
      return const MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Error: Location cannot be empty.')],
        isError: true,
      );
    }

    try {
      double lat = 0.0;
      double lng = 0.0;
      String resolvedName = location;

      final coordMatch = RegExp(r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$').firstMatch(location);
      if (coordMatch != null) {
        lat = double.parse(coordMatch.group(1)!);
        lng = double.parse(coordMatch.group(2)!);
        resolvedName = 'Lat $lat, Lng $lng';
      } else {
        // Geocode city
        final geoUrl = '$_geocodeUrl/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json';
        final geoResp = await http.get(Uri.parse(geoUrl)).timeout(const Duration(seconds: 15));
        if (geoResp.statusCode != 200) {
          return MCPToolResult(
            content: [MCPContent(type: 'text', text: 'Error: Geocoding failed (HTTP ${geoResp.statusCode}).')],
            isError: true,
          );
        }

        final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
        final results = geoData['results'] as List?;
        if (results == null || results.isEmpty) {
          return MCPToolResult(
            content: [MCPContent(type: 'text', text: 'Error: Location "$location" not found.')],
            isError: true,
          );
        }

        final first = results.first as Map;
        lat = (first['latitude'] as num).toDouble();
        lng = (first['longitude'] as num).toDouble();
        resolvedName = '${first['name']}, ${first['country'] ?? ''}';
      }

      // Fetch Weather Data
      final weatherUrl = '$_baseUrl/forecast?latitude=$lat&longitude=$lng'
          '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
          '&forecast_days=$days&timezone=auto';

      final resp = await http.get(Uri.parse(weatherUrl)).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [MCPContent(type: 'text', text: 'Error: Weather API failed (HTTP ${resp.statusCode}).')],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      final daily = data['daily'] as Map<String, dynamic>?;

      final buffer = StringBuffer();
      buffer.writeln('### Weather for $resolvedName');
      if (current != null) {
        final temp = current['temperature_2m'];
        final humidity = current['relative_humidity_2m'];
        final wind = current['wind_speed_10m'];
        final code = current['weather_code'] as int? ?? 0;
        buffer.writeln('**Current Conditions:**');
        buffer.writeln('- Temperature: $temp°C');
        buffer.writeln('- Humidity: $humidity%');
        buffer.writeln('- Wind Speed: $wind km/h');
        buffer.writeln('- Condition: ${_wmoCodeToDesc(code)}');
        buffer.writeln();
      }

      if (daily != null) {
        buffer.writeln('**Daily Forecast ($days days):**');
        final times = daily['time'] as List;
        final maxTemps = daily['temperature_2m_max'] as List;
        final minTemps = daily['temperature_2m_min'] as List;
        final probs = daily['precipitation_probability_max'] as List;
        final codes = daily['weather_code'] as List;

        for (int i = 0; i < times.length; i++) {
          buffer.writeln('- **${times[i]}**: Min: ${minTemps[i]}°C, Max: ${maxTemps[i]}°C, Rain: ${probs[i]}%, ${_wmoCodeToDesc(codes[i] as int)}');
        }
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Weather execution error: $e')],
        isError: true,
      );
    }
  }

  static String _wmoCodeToDesc(int code) {
    return switch (code) {
      0 => 'Clear sky',
      1 => 'Mainly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      51 || 53 || 55 => 'Drizzle',
      61 || 63 || 65 => 'Rain',
      71 || 73 || 75 => 'Snowfall',
      80 || 81 || 82 => 'Rain showers',
      95 || 96 || 99 => 'Thunderstorm',
      _ => 'Unknown ($code)',
    };
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. SSH Execution Tool
// ═══════════════════════════════════════════════════════════════

class SshLocalTool extends McpLocalTool {
  @override
  String get name => 'ssh_execute';

  @override
  String get description => 'Connect to a remote server via SSH and execute a terminal shell command.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'host': {'type': 'string', 'description': 'Hostname or IP address of the target server'},
          'port': {'type': 'integer', 'description': 'SSH Port (default: 22)', 'default': 22},
          'username': {'type': 'string', 'description': 'Authentication username'},
          'password': {'type': 'string', 'description': 'Authentication password (optional)'},
          'private_key': {'type': 'string', 'description': 'PEM formatted private key string (optional)'},
          'command': {'type': 'string', 'description': 'Shell command string to execute'}
        },
        'required': ['host', 'username', 'command'],
      };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final host = arguments['host'] as String? ?? '';
    final port = arguments['port'] as int? ?? 22;
    final username = arguments['username'] as String? ?? '';
    final password = arguments['password'] as String?;
    final privateKey = arguments['private_key'] as String?;
    final command = arguments['command'] as String? ?? '';

    if (host.isEmpty || username.isEmpty || command.isEmpty) {
      return const MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Error: host, username, and command must not be empty.')],
        isError: true,
      );
    }

    SSHClient? client;
    try {
      List<SSHKeyPair>? keyPairs;
      if (privateKey != null && privateKey.trim().isNotEmpty) {
        try {
          keyPairs = SSHKeyPair.fromPem(privateKey);
        } catch (e) {
          return MCPToolResult(
            content: [MCPContent(type: 'text', text: 'Error decoding SSH private key PEM: $e')],
            isError: true,
          );
        }
      }

      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));
      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password ?? '',
        onUserauthBanner: (message) => debugPrint('[SSH Auth] $message'),
        identities: keyPairs ?? const [],
      );

      final session = await client.execute(command);
      final stdout = await utf8.decodeStream(session.stdout);
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final buffer = StringBuffer();
      if (code == 0) {
        buffer.writeln('### Command execution succeeded (exit code: 0)');
      } else {
        buffer.writeln('### Command execution failed (exit code: $code)');
      }
      
      if (stdout.trim().isNotEmpty) {
        buffer.writeln('**Stdout:**');
        buffer.writeln('```');
        buffer.writeln(stdout.trim());
        buffer.writeln('```');
      }
      if (stderr.trim().isNotEmpty) {
        buffer.writeln('**Stderr:**');
        buffer.writeln('```');
        buffer.writeln(stderr.trim());
        buffer.writeln('```');
      }
      if (stdout.trim().isEmpty && stderr.trim().isEmpty) {
        buffer.writeln('*(No output)*');
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection or execution failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
      await client?.done;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Chart Generation Tool
// ═══════════════════════════════════════════════════════════════

class ChartLocalTool extends McpLocalTool {
  @override
  String get name => 'generate_chart_data';

  @override
  String get description => 'Generate structured numeric data configurations for drawing visual Line, Bar, or Pie charts in the chat widget.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Title description of the chart'},
          'chart_type': {
            'type': 'string',
            'description': 'Type of chart to render',
            'enum': ['line', 'bar', 'pie']
          },
          'labels': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'X-axis text labels (e.g. ["Q1", "Q2", "Q3", "Q4"])'
          },
          'data': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Y-axis numeric values matching labels'
          }
        },
        'required': ['chart_type', 'labels', 'data'],
      };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final chartType = arguments['chart_type'] as String? ?? 'line';
    final labels = arguments['labels'] as List?;
    final data = arguments['data'] as List?;

    if (labels == null || data == null || labels.length != data.length) {
      return const MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Error: labels and data list lengths must match.')],
        isError: true,
      );
    }

    final payload = {
      'title': arguments['title'] ?? 'Chart Output',
      'chart_type': chartType,
      'labels': labels,
      'data': data.map((d) => (d as num).toDouble()).toList(),
    };

    return MCPToolResult(
      content: [
        MCPContent(
          type: 'chart',
          text: jsonEncode(payload),
        )
      ],
      isError: false,
    );
  }
}
