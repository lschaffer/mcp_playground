import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dartssh2/dartssh2.dart';
import 'package:mime/mime.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

// ═══════════════════════════════════════════════════════════════
// Example: Dart-native MCP tool implementations
//
// This file demonstrates how to create and register custom
// local (Dart) MCP tools with the McpPlayground widget.
// ═══════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════
// 1. Weather Tool (Open-Meteo REST API)
// ═══════════════════════════════════════════════════════════════

// Helper function to decode WMO codes
String _wmoCodeToDesc(int code) {
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

class GetCurrentWeatherTool extends McpLocalTool {
  static const String _baseUrl = 'https://api.open-meteo.com/v1';
  static const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

  @override
  String get name => 'get_current_weather';

  @override
  String get description =>
      'Get current weather conditions including temperature, wind, humidity, and weather description.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description':
            'City name (e.g. "Vienna") or coordinates "lat,lng" (e.g. "48.2082,16.3738").',
      },
      'latitude': {
        'type': 'number',
        'description': 'Latitude (optional, overrides location)',
      },
      'longitude': {
        'type': 'number',
        'description': 'Longitude (optional, overrides location)',
      },
    },
    'required': [],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      double? lat;
      double? lng;
      String resolvedName = 'Default Location';

      if (arguments['latitude'] != null && arguments['longitude'] != null) {
        lat = (arguments['latitude'] as num).toDouble();
        lng = (arguments['longitude'] as num).toDouble();
        resolvedName = 'Lat $lat, Lng $lng';
      } else {
        final location = arguments['location'] as String? ?? 'Vienna';
        final coordMatch = RegExp(
          r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$',
        ).firstMatch(location);
        if (coordMatch != null) {
          lat = double.parse(coordMatch.group(1)!);
          lng = double.parse(coordMatch.group(2)!);
          resolvedName = 'Lat $lat, Lng $lng';
        } else {
          // Geocode city
          final geoUrl =
              '$_geocodeUrl/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json';
          final geoResp = await http
              .get(Uri.parse(geoUrl))
              .timeout(const Duration(seconds: 15));
          if (geoResp.statusCode == 200) {
            final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
            final results = geoData['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final first = results.first as Map;
              lat = (first['latitude'] as num).toDouble();
              lng = (first['longitude'] as num).toDouble();
              resolvedName = '${first['name']}, ${first['country'] ?? ''}';
            }
          }
        }
      }

      if (lat == null || lng == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve coordinates.',
            ),
          ],
          isError: true,
        );
      }

      final weatherUrl =
          '$_baseUrl/forecast?latitude=$lat&longitude=$lng'
          '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
          '&timezone=auto';

      final resp = await http
          .get(Uri.parse(weatherUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;

      final buffer = StringBuffer();
      buffer.writeln('### Current Weather for $resolvedName');
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
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [
          MCPContent(type: 'text', text: 'Weather execution error: $e'),
        ],
        isError: true,
      );
    }
  }
}

class GetHourlyForecastTool extends McpLocalTool {
  static const String _baseUrl = 'https://api.open-meteo.com/v1';
  static const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

  @override
  String get name => 'get_hourly_forecast';

  @override
  String get description =>
      'Get hourly weather forecast for the next 24-168 hours. Includes temperature, precipitation, wind speed, and weather code.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description':
            'City name (e.g. "Vienna") or coordinates "lat,lng" (e.g. "48.2082,16.3738").',
      },
      'latitude': {'type': 'number'},
      'longitude': {'type': 'number'},
      'hours': {
        'type': 'integer',
        'description': 'Number of forecast hours (default: 24, max: 168)',
        'default': 24,
      },
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      double? lat;
      double? lng;
      String resolvedName = 'Default Location';
      final hoursVal = arguments['hours'];
      final int hours = hoursVal is num ? hoursVal.toInt() : 24;

      if (arguments['latitude'] != null && arguments['longitude'] != null) {
        lat = (arguments['latitude'] as num).toDouble();
        lng = (arguments['longitude'] as num).toDouble();
        resolvedName = 'Lat $lat, Lng $lng';
      } else {
        final location = arguments['location'] as String? ?? 'Vienna';
        final coordMatch = RegExp(
          r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$',
        ).firstMatch(location);
        if (coordMatch != null) {
          lat = double.parse(coordMatch.group(1)!);
          lng = double.parse(coordMatch.group(2)!);
          resolvedName = 'Lat $lat, Lng $lng';
        } else {
          final geoUrl =
              '$_geocodeUrl/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json';
          final geoResp = await http
              .get(Uri.parse(geoUrl))
              .timeout(const Duration(seconds: 15));
          if (geoResp.statusCode == 200) {
            final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
            final results = geoData['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final first = results.first as Map;
              lat = (first['latitude'] as num).toDouble();
              lng = (first['longitude'] as num).toDouble();
              resolvedName = '${first['name']}, ${first['country'] ?? ''}';
            }
          }
        }
      }

      if (lat == null || lng == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve coordinates.',
            ),
          ],
          isError: true,
        );
      }

      final weatherUrl =
          '$_baseUrl/forecast?latitude=$lat&longitude=$lng'
          '&hourly=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
          '&forecast_hours=$hours&timezone=auto';

      final resp = await http
          .get(Uri.parse(weatherUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final hourly = data['hourly'] as Map<String, dynamic>?;

      final buffer = StringBuffer();
      buffer.writeln('### Hourly Forecast ($hours hours) for $resolvedName');
      if (hourly != null) {
        final times = hourly['time'] as List;
        final temps = hourly['temperature_2m'] as List;
        final humidities = hourly['relative_humidity_2m'] as List;
        final codes = hourly['weather_code'] as List;

        for (int i = 0; i < times.length; i++) {
          final codeVal = codes[i] is num ? (codes[i] as num).toInt() : 0;
          buffer.writeln(
            '- **${times[i].toString().replaceFirst('T', ' ')}**: Temp: ${temps[i]}°C, Humidity: ${humidities[i]}%, ${_wmoCodeToDesc(codeVal)}',
          );
        }
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [
          MCPContent(type: 'text', text: 'Weather execution error: $e'),
        ],
        isError: true,
      );
    }
  }
}

class GetDailyForecastTool extends McpLocalTool {
  static const String _baseUrl = 'https://api.open-meteo.com/v1';
  static const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

  @override
  String get name => 'get_daily_forecast';

  @override
  String get description =>
      'Get daily weather forecast for the next 1-16 days. Includes high/low temperatures, precipitation sum, sunrise/sunset.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description':
            'City name (e.g. "Vienna") or coordinates "lat,lng" (e.g. "48.2082,16.3738").',
      },
      'latitude': {'type': 'number'},
      'longitude': {'type': 'number'},
      'days': {
        'type': 'integer',
        'description': 'Number of forecast days (1-16, default: 7)',
        'default': 7,
      },
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      double? lat;
      double? lng;
      String resolvedName = 'Default Location';
      final daysVal = arguments['days'];
      final int days = daysVal is num ? daysVal.toInt() : 7;

      if (arguments['latitude'] != null && arguments['longitude'] != null) {
        lat = (arguments['latitude'] as num).toDouble();
        lng = (arguments['longitude'] as num).toDouble();
        resolvedName = 'Lat $lat, Lng $lng';
      } else {
        final location = arguments['location'] as String? ?? 'Vienna';
        final coordMatch = RegExp(
          r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$',
        ).firstMatch(location);
        if (coordMatch != null) {
          lat = double.parse(coordMatch.group(1)!);
          lng = double.parse(coordMatch.group(2)!);
          resolvedName = 'Lat $lat, Lng $lng';
        } else {
          final geoUrl =
              '$_geocodeUrl/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json';
          final geoResp = await http
              .get(Uri.parse(geoUrl))
              .timeout(const Duration(seconds: 15));
          if (geoResp.statusCode == 200) {
            final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
            final results = geoData['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final first = results.first as Map;
              lat = (first['latitude'] as num).toDouble();
              lng = (first['longitude'] as num).toDouble();
              resolvedName = '${first['name']}, ${first['country'] ?? ''}';
            }
          }
        }
      }

      if (lat == null || lng == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve coordinates.',
            ),
          ],
          isError: true,
        );
      }

      final weatherUrl =
          '$_baseUrl/forecast?latitude=$lat&longitude=$lng'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
          '&forecast_days=$days&timezone=auto';

      final resp = await http
          .get(Uri.parse(weatherUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>?;

      final buffer = StringBuffer();
      buffer.writeln('### Daily Weather Forecast for $resolvedName');
      if (daily != null) {
        final times = daily['time'] as List;
        final maxTemps = daily['temperature_2m_max'] as List;
        final minTemps = daily['temperature_2m_min'] as List;
        final probs = daily['precipitation_probability_max'] as List;
        final codes = daily['weather_code'] as List;

        for (int i = 0; i < times.length; i++) {
          final codeVal = codes[i] is num ? (codes[i] as num).toInt() : 0;
          buffer.writeln(
            '- **${times[i]}**: Min: ${minTemps[i]}°C, Max: ${maxTemps[i]}°C, Rain: ${probs[i]}%, ${_wmoCodeToDesc(codeVal)}',
          );
        }
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [
          MCPContent(type: 'text', text: 'Weather execution error: $e'),
        ],
        isError: true,
      );
    }
  }
}

class GeocodeWeatherCityTool extends McpLocalTool {
  static const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

  @override
  String get name => 'geocode_weather_city';

  @override
  String get description =>
      'Look up the coordinates (latitude, longitude) for a city name. Useful for finding coordinates to pass to other weather tools.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'city': {
        'type': 'string',
        'description': 'City name to look up (e.g. "Vienna", "New York")',
      },
    },
    'required': ['city'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final city = arguments['city'] as String? ?? '';
      if (city.isEmpty) {
        return const MCPToolResult(
          content: [
            MCPContent(type: 'text', text: 'Error: City name is required.'),
          ],
          isError: true,
        );
      }

      final geoUrl =
          '$_geocodeUrl/search?name=${Uri.encodeComponent(city)}&count=5&language=en&format=json';
      final geoResp = await http
          .get(Uri.parse(geoUrl))
          .timeout(const Duration(seconds: 15));
      if (geoResp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Geocoding failed (HTTP ${geoResp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final results = geoData['results'] as List?;

      final buffer = StringBuffer();
      buffer.writeln('### Geocoding results for "$city":');
      if (results != null && results.isNotEmpty) {
        for (final item in results) {
          final m = item as Map;
          buffer.writeln(
            '- **${m['name']}**, ${m['country'] ?? ''} (${m['admin1'] ?? ''})',
          );
          buffer.writeln('  - Latitude: ${m['latitude']}');
          buffer.writeln('  - Longitude: ${m['longitude']}');
          buffer.writeln('  - Timezone: ${m['timezone']}');
          buffer.writeln();
        }
      } else {
        buffer.writeln('No results found.');
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Geocoding error: $e')],
        isError: true,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. SSH Execution Tool (requires dartssh2)
// ═══════════════════════════════════════════════════════════════

class SshCredentials {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;

  SshCredentials({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
  });

  static SshCredentials? fromArgsAndConfig(
    Map<String, dynamic> arguments,
    Map<String, dynamic>? globalSsh,
  ) {
    final host = (arguments['host'] as String?)?.isNotEmpty == true
        ? arguments['host'] as String
        : (globalSsh?['host'] as String? ?? '');

    final portVal = arguments['port'] ?? globalSsh?['port'];
    final port = portVal is num ? portVal.toInt() : 22;

    final username = (arguments['username'] as String?)?.isNotEmpty == true
        ? arguments['username'] as String
        : (globalSsh?['username'] as String? ?? '');

    final password = (arguments['password'] as String?)?.isNotEmpty == true
        ? arguments['password'] as String
        : (globalSsh?['password'] as String? ??
              globalSsh?['password'] as String?);

    final privateKey = (arguments['private_key'] as String?)?.isNotEmpty == true
        ? arguments['private_key'] as String
        : ((arguments['privateKey'] as String?)?.isNotEmpty == true
              ? arguments['privateKey'] as String
              : (globalSsh?['privateKey'] as String? ??
                    globalSsh?['private_key'] as String?));

    if (host.isEmpty || username.isEmpty) {
      return null;
    }
    return SshCredentials(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey,
    );
  }

  Future<SSHClient> connect() async {
    List<SSHKeyPair>? keyPairs;
    if (privateKey != null && privateKey!.trim().isNotEmpty) {
      keyPairs = SSHKeyPair.fromPem(privateKey!);
    }
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 15),
    );
    return SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password ?? '',
      identities: keyPairs ?? const [],
    );
  }
}

abstract class SshBaseLocalTool extends McpLocalTool {
  final Map<String, dynamic>? Function() getGlobalSsh;
  SshBaseLocalTool(this.getGlobalSsh);

  SshCredentials? _getCreds(Map<String, dynamic> arguments) {
    return SshCredentials.fromArgsAndConfig(arguments, getGlobalSsh());
  }

  MCPToolResult _noCredsResult() {
    return const MCPToolResult(
      content: [
        MCPContent(
          type: 'text',
          text:
              'Error: SSH host or username is not configured. Configure Connection Override settings.',
        ),
      ],
      isError: true,
    );
  }
}

class SshListDirectoryTool extends SshBaseLocalTool {
  SshListDirectoryTool(super.getGlobalSsh);

  @override
  String get name => 'list_directory';

  @override
  String get description => 'List files and subdirectories at a remote path.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Remote directory path (e.g. /home/user or ~).',
      },
    },
    'required': ['path'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '.';
    SSHClient? client;
    try {
      client = await creds.connect();
      final session = await client.execute('ls -la "$path"');
      final stdout = await utf8.decodeStream(session.stdout);
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final resultText = code == 0
          ? stdout
          : 'Error listing directory: $stderr';
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: resultText)],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshReadFileTool extends SshBaseLocalTool {
  SshReadFileTool(super.getGlobalSsh);

  @override
  String get name => 'read_file';

  @override
  String get description => 'Read the text content of a remote file.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Full remote path of the file to read.',
      },
      'maxBytes': {
        'type': 'integer',
        'description':
            'Maximum bytes to read (default 65536). Use 0 for unlimited.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '';
    final maxBytesVal = arguments['maxBytes'];
    final int maxBytes = maxBytesVal is num ? maxBytesVal.toInt() : 65536;

    SSHClient? client;
    try {
      client = await creds.connect();
      final cmd = maxBytes > 0 ? 'head -c $maxBytes "$path"' : 'cat "$path"';
      final session = await client.execute(cmd);
      final stdout = await utf8.decodeStream(session.stdout);
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final resultText = code == 0 ? stdout : 'Error reading file: $stderr';
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: resultText)],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshDownloadFileTool extends SshBaseLocalTool {
  SshDownloadFileTool(super.getGlobalSsh);

  @override
  String get name => 'download_file';

  @override
  String get description =>
      'Download a remote file. Returns base-64 encoded content and MIME type.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Full remote path of the file to download.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '';
    SSHClient? client;
    try {
      client = await creds.connect();
      final session = await client.execute('cat "$path"');

      final List<int> bytes = [];
      await for (final chunk in session.stdout) {
        bytes.addAll(chunk);
      }

      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      if (code != 0) {
        return MCPToolResult(
          content: [
            MCPContent(type: 'text', text: 'Error downloading file: $stderr'),
          ],
          isError: true,
        );
      }

      final base64String = base64Encode(bytes);
      final fileName = path.split('/').last;
      return MCPToolResult(
        content: [
          MCPContent(
            type: 'image',
            data: base64String,
            mimeType: lookupMimeType(fileName) ?? 'application/octet-stream',
            text:
                'File $fileName downloaded successfully (${bytes.length} bytes).',
          ),
        ],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshUploadFileTool extends SshBaseLocalTool {
  SshUploadFileTool(super.getGlobalSsh);

  @override
  String get name => 'upload_file';

  @override
  String get description =>
      'Upload a file to the remote server. Provide path and content.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Full remote path where the file should be written.',
      },
      'content': {
        'type': 'string',
        'description':
            'Inline file content – UTF-8 text or base64-encoded bytes.',
      },
      'encoding': {
        'type': 'string',
        'description':
            'Set to "base64" when content is base64-encoded (default: utf8).',
      },
    },
    'required': ['path', 'content'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '';
    final content = arguments['content'] as String? ?? '';
    final encoding = arguments['encoding'] as String? ?? 'utf8';

    SSHClient? client;
    try {
      client = await creds.connect();

      List<int> bytesToUpload;
      if (encoding.trim().toLowerCase() == 'base64') {
        bytesToUpload = base64Decode(content.trim());
      } else {
        bytesToUpload = utf8.encode(content);
      }

      final sftp = await client.sftp();
      final file = await sftp.open(
        path,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await file.writeBytes(Uint8List.fromList(bytesToUpload));
      await file.close();

      return MCPToolResult(
        content: [
          MCPContent(
            type: 'text',
            text:
                'File uploaded successfully to $path (${bytesToUpload.length} bytes).',
          ),
        ],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [
          MCPContent(
            type: 'text',
            text: 'SSH connection or SFTP upload failed: $e',
          ),
        ],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshExecuteCommandTool extends SshBaseLocalTool {
  SshExecuteCommandTool(super.getGlobalSsh);

  @override
  String get name => 'execute_command';

  @override
  String get description =>
      'Run an ad-hoc shell command on the remote server and return stdout/stderr.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description': 'Shell command string to execute',
      },
    },
    'required': ['command'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final command = arguments['command'] as String? ?? '';
    SSHClient? client;
    try {
      client = await creds.connect();
      final session = await client.execute(command);
      final stdout = await utf8.decodeStream(session.stdout);
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final buffer = StringBuffer();
      buffer.writeln('### Command exited with code: $code');
      if (stdout.trim().isNotEmpty) {
        buffer.writeln('**Stdout:**\n```\n${stdout.trim()}\n```');
      }
      if (stderr.trim().isNotEmpty) {
        buffer.writeln('**Stderr:**\n```\n${stderr.trim()}\n```');
      }
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buffer.toString())],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [
          MCPContent(type: 'text', text: 'SSH command execution failed: $e'),
        ],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshMakeDirectoryTool extends SshBaseLocalTool {
  SshMakeDirectoryTool(super.getGlobalSsh);

  @override
  String get name => 'make_directory';

  @override
  String get description =>
      'Create a directory (and all missing parent directories) on the remote server.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Full remote path of the directory to create.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '';
    SSHClient? client;
    try {
      client = await creds.connect();
      final session = await client.execute('mkdir -p "$path"');
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final resultText = code == 0
          ? 'Directory created successfully.'
          : 'Error creating directory: $stderr';
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: resultText)],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

class SshRemoveDirectoryTool extends SshBaseLocalTool {
  SshRemoveDirectoryTool(super.getGlobalSsh);

  @override
  String get name => 'remove_directory';

  @override
  String get description =>
      'Remove an EMPTY directory on the remote server. Fails if the directory is not empty.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Full remote path of the empty directory to remove.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    final creds = _getCreds(arguments);
    if (creds == null) return _noCredsResult();

    final path = arguments['path'] as String? ?? '';
    SSHClient? client;
    try {
      client = await creds.connect();
      final session = await client.execute('rmdir "$path"');
      final stderr = await utf8.decodeStream(session.stderr);
      final code = session.exitCode;

      final resultText = code == 0
          ? 'Directory removed successfully.'
          : 'Error removing directory: $stderr';
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: resultText)],
        isError: code != 0,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'SSH connection failed: $e')],
        isError: true,
      );
    } finally {
      client?.close();
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Chart Generation Tool (Canvas-based, no extra deps)
// ═══════════════════════════════════════════════════════════════

class CreateChartPngTool extends McpLocalTool {
  @override
  String get name => 'create_chart_png';

  @override
  String get description =>
      'Generate a PNG chart (line, bar, pie, area, scatter) from x-axis labels and numeric data series. Returns a base64 encoded PNG image.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'chart_type': {
        'type': 'string',
        'description': 'Chart style: "line", "bar", "pie", "area", "scatter".',
        'enum': ['line', 'bar', 'pie', 'area', 'scatter'],
        'default': 'line',
      },
      'chartType': {
        'type': 'string',
        'description': 'Alias for chart_type.',
        'enum': ['line', 'bar', 'pie', 'area', 'scatter'],
      },
      'title': {'type': 'string', 'description': 'Chart title shown at top.'},
      'chartTitle': {'type': 'string', 'description': 'Alias for title.'},
      'labels': {
        'type': 'array',
        'description': 'X-axis labels (not required for pie).',
        'items': {'type': 'string'},
      },
      'xAxis': {
        'type': 'array',
        'description': 'Alias for labels.',
        'items': {'type': 'string'},
      },
      'data': {
        'type': 'array',
        'description':
            'Y-axis numeric values matching labels (for single series).',
        'items': {'type': 'number'},
      },
      'series': {
        'type': 'array',
        'description':
            'Series definitions with name, numeric data array, and optional colorHex.',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'data': {
              'type': 'array',
              'items': {'type': 'number'},
            },
            'colorHex': {
              'type': 'string',
              'description': 'Optional color hex, e.g. #1E88E5.',
            },
          },
          'required': ['name', 'data'],
        },
      },
      'width': {
        'type': 'integer',
        'default': 800,
        'description': 'Image width in px.',
      },
      'height': {
        'type': 'integer',
        'default': 500,
        'description': 'Image height in px.',
      },
      'xAxisTitle': {'type': 'string', 'description': 'X-axis label.'},
      'yAxisTitle': {'type': 'string', 'description': 'Y-axis label.'},
      'xAxisRotate': {
        'type': 'number',
        'default': 0,
        'description': 'Rotation angle in degrees for x-axis tick labels.',
      },
      'yAxisRotate': {
        'type': 'number',
        'default': -90,
        'description': 'Rotation angle in degrees for the y-axis title.',
      },
      'lineColors': {
        'type': 'array',
        'description': 'Array of hex color strings to use for series in order.',
        'items': {'type': 'string'},
      },
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final chartType =
          ((arguments['chart_type'] ?? arguments['chartType']) as String? ??
                  'line')
              .trim()
              .toLowerCase();
      final title =
          ((arguments['title'] ??
                      arguments['chartTitle'] ??
                      arguments['chart_title'])
                  as String?)
              ?.trim();
      final xAxisTitle = (arguments['xAxisTitle'] as String?)?.trim() ?? '';
      final yAxisTitle = (arguments['yAxisTitle'] as String?)?.trim() ?? '';
      final xAxisRotate = (arguments['xAxisRotate'] as num?)?.toDouble() ?? 0.0;
      final yAxisRotate =
          (arguments['yAxisRotate'] as num?)?.toDouble() ?? -90.0;

      final width = ((arguments['width'] as num?)?.toInt() ?? 800).clamp(
        400,
        2400,
      );
      final height = ((arguments['height'] as num?)?.toInt() ?? 500).clamp(
        300,
        1600,
      );

      final xAxisRaw =
          (arguments['labels'] ?? arguments['xAxis']) as List<dynamic>?;
      final xAxis = xAxisRaw?.map((e) => e.toString()).toList() ?? <String>[];

      final lineColorsRaw = arguments['lineColors'] as List<dynamic>?;
      final lineColors =
          lineColorsRaw
              ?.map((c) => _parseColor(c.toString()))
              .whereType<Color>()
              .toList() ??
          <Color>[];

      final seriesRaw = arguments['series'] as List<dynamic>?;
      final parsedSeries = _extractSeries(
        arguments,
        rawSeries: seriesRaw,
        lineColors: lineColors,
      );

      if (parsedSeries.isEmpty) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: No valid data/series provided for the chart.',
            ),
          ],
          isError: true,
        );
      }

      final needsXAxis =
          chartType == 'line' ||
          chartType == 'bar' ||
          chartType == 'area' ||
          chartType == 'scatter';
      if (needsXAxis && xAxis.isEmpty) {
        final maxLen = parsedSeries
            .map((s) => s.data.length)
            .fold<int>(0, math.max);
        xAxis.addAll(List.generate(maxLen, (i) => '${i + 1}'));
      }

      Uint8List bytes;
      if (chartType == 'pie') {
        bytes = await _drawPieChart(
          series: parsedSeries,
          xLabels: xAxis,
          chartTitle: title,
          width: width,
          height: height,
        );
      } else {
        final minLength = _minDataLength(xAxis.length, parsedSeries);
        final clippedXAxis = xAxis.take(minLength).toList();
        final clippedSeries = parsedSeries
            .map(
              (s) => _ChartSeriesData(
                name: s.name,
                data: s.data.take(minLength).toList(),
                color: s.color,
              ),
            )
            .toList();

        bytes = await _drawChart(
          chartType: chartType,
          xAxis: clippedXAxis,
          series: clippedSeries,
          chartTitle: title,
          xAxisTitle: xAxisTitle,
          yAxisTitle: yAxisTitle,
          xAxisRotate: xAxisRotate,
          yAxisRotate: yAxisRotate,
          width: width,
          height: height,
        );
      }

      return MCPToolResult(
        content: [
          MCPContent(
            type: 'image',
            data: base64Encode(bytes),
            mimeType: 'image/png',
          ),
        ],
        isError: false,
      );
    } catch (e, stack) {
      return MCPToolResult(
        content: [
          MCPContent(type: 'text', text: 'Error rendering chart: $e\n$stack'),
        ],
        isError: true,
      );
    }
  }

  List<_ChartSeriesData> _extractSeries(
    Map<String, dynamic> args, {
    required List<dynamic>? rawSeries,
    List<Color> lineColors = const [],
  }) {
    final series = <_ChartSeriesData>[];

    if (rawSeries != null && rawSeries.isNotEmpty) {
      series.addAll(_parseSeries(rawSeries, lineColors: lineColors));
    }

    final yAxisData = (args['yAxisData'] ?? args['yAxisSeries']);
    if (yAxisData is Map) {
      final normalized = <Map<String, dynamic>>[];
      for (final entry in yAxisData.entries) {
        normalized.add({'name': entry.key.toString(), 'data': entry.value});
      }
      series.addAll(
        _parseSeries(
          normalized,
          lineColors: lineColors,
          startIndex: series.length,
        ),
      );
    }

    final dataRaw = args['data'] as List<dynamic>?;
    if (dataRaw != null && dataRaw.isNotEmpty) {
      final sName = ((args['title'] ?? args['chartTitle']) as String? ?? 'Data')
          .trim();
      series.add(
        _parseSingleSeries(
          sName,
          dataRaw,
          lineColors: lineColors,
          startIndex: series.length,
        ),
      );
    }

    final deduped = <String, _ChartSeriesData>{};
    for (final item in series) {
      deduped[item.name] = item;
    }
    return deduped.values.toList();
  }

  _ChartSeriesData _parseSingleSeries(
    String name,
    List<dynamic> dataRaw, {
    List<Color> lineColors = const [],
    int startIndex = 0,
  }) {
    final defaults = <Color>[
      const Color(0xFF1E88E5),
      const Color(0xFFE53935),
      const Color(0xFF43A047),
      const Color(0xFF8E24AA),
      const Color(0xFFFB8C00),
      const Color(0xFF00897B),
    ];
    final color = lineColors.isNotEmpty
        ? lineColors[startIndex % lineColors.length]
        : defaults[startIndex % defaults.length];

    final data = <double>[];
    for (final value in dataRaw) {
      final numeric = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (numeric != null) data.add(numeric);
    }
    return _ChartSeriesData(name: name, data: data, color: color);
  }

  List<_ChartSeriesData> _parseSeries(
    List<dynamic> rawSeries, {
    List<Color> lineColors = const [],
    int startIndex = 0,
  }) {
    final defaults = <Color>[
      const Color(0xFF1E88E5),
      const Color(0xFFE53935),
      const Color(0xFF43A047),
      const Color(0xFF8E24AA),
      const Color(0xFFFB8C00),
      const Color(0xFF00897B),
    ];

    Color paletteColor(int index) {
      final i = startIndex + index;
      if (lineColors.isNotEmpty) return lineColors[i % lineColors.length];
      return defaults[i % defaults.length];
    }

    final parsed = <_ChartSeriesData>[];
    for (var index = 0; index < rawSeries.length; index++) {
      final item = rawSeries[index];
      if (item is! Map) continue;

      final name = (item['name'] as String?)?.trim();
      final dataRaw = item['data'];
      if (name == null || name.isEmpty || dataRaw is! List || dataRaw.isEmpty) {
        continue;
      }

      final data = <double>[];
      for (final value in dataRaw) {
        final numeric = value is num
            ? value.toDouble()
            : double.tryParse(value.toString());
        if (numeric != null) data.add(numeric);
      }
      if (data.isEmpty) continue;

      final colorHex = (item['colorHex'] as String?)?.trim();
      final color = (colorHex == null || colorHex.isEmpty)
          ? paletteColor(index)
          : _parseColor(colorHex) ?? paletteColor(index);

      parsed.add(_ChartSeriesData(name: name, data: data, color: color));
    }

    return parsed;
  }

  int _minDataLength(int xAxisLength, List<_ChartSeriesData> series) {
    var minLen = xAxisLength;
    for (final s in series) {
      if (s.data.length < minLen) minLen = s.data.length;
    }
    return minLen;
  }

  Future<Uint8List> _drawChart({
    required String chartType,
    required List<String> xAxis,
    required List<_ChartSeriesData> series,
    required String? chartTitle,
    required String xAxisTitle,
    required String yAxisTitle,
    required double xAxisRotate,
    required double yAxisRotate,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    final background = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      background,
    );

    final xLabelPad = xAxisRotate.abs() > 20 ? 100.0 : 70.0;
    const leftPad = 80.0;
    const rightPad = 26.0;
    const topPad = 64.0;
    final bottomPad = xLabelPad;

    final plotLeft = leftPad;
    final plotTop = topPad;
    final plotRight = width - rightPad;
    final plotBottom = height - bottomPad;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    final allValues = series.expand((s) => s.data).toList();
    var minY = allValues.isNotEmpty ? allValues.reduce(math.min) : 0.0;
    var maxY = allValues.isNotEmpty ? allValues.reduce(math.max) : 10.0;

    if (chartType == 'bar') minY = math.min(0.0, minY);
    if ((maxY - minY).abs() < 0.0001) {
      maxY += 1;
      minY -= 1;
    }

    double mapX(int i) {
      if (xAxis.length <= 1) return plotLeft;
      return plotLeft + (i / (xAxis.length - 1)) * plotWidth;
    }

    double mapY(double value) {
      final ratio = (value - minY) / (maxY - minY);
      return plotBottom - (ratio * plotHeight);
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF6B7280)
      ..strokeWidth = 1.5;

    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(plotLeft, plotBottom),
      Offset(plotRight, plotBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotLeft, plotTop),
      Offset(plotLeft, plotBottom),
      axisPaint,
    );

    for (var i = 0; i <= 5; i++) {
      final yValue = minY + ((maxY - minY) * i / 5);
      final y = mapY(yValue);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      _drawText(
        canvas,
        yValue.toStringAsFixed(1),
        Offset(10, y - 8),
        const TextStyle(fontSize: 12, color: Color(0xFF374151)),
      );
    }

    final step = xAxis.length <= 6 ? 1 : (xAxis.length / 6).ceil();
    final indicesDrawn = <int>{};
    for (var i = 0; i < xAxis.length; i += step) {
      indicesDrawn.add(i);
      final x = mapX(i);
      canvas.drawLine(
        Offset(x, plotBottom),
        Offset(x, plotBottom + 6),
        axisPaint,
      );
      _drawXLabel(canvas, xAxis[i], x, plotBottom + 8, xAxisRotate);
    }
    if (!indicesDrawn.contains(xAxis.length - 1) && xAxis.isNotEmpty) {
      final i = xAxis.length - 1;
      final x = mapX(i);
      canvas.drawLine(
        Offset(x, plotBottom),
        Offset(x, plotBottom + 6),
        axisPaint,
      );
      _drawXLabel(canvas, xAxis[i], x, plotBottom + 8, xAxisRotate);
    }

    switch (chartType) {
      case 'line':
        _renderLine(canvas, series, mapX, mapY, dots: true);
        break;
      case 'area':
        _renderArea(canvas, series, mapX, mapY, plotBottom);
        break;
      case 'scatter':
        _renderScatter(canvas, series, mapX, mapY);
        break;
      case 'bar':
        _renderBar(canvas, series, xAxis, mapX, mapY, plotWidth);
        break;
      default:
        _renderLine(canvas, series, mapX, mapY, dots: true);
        break;
    }

    if (chartTitle != null && chartTitle.isNotEmpty) {
      _drawText(
        canvas,
        chartTitle,
        const Offset(16, 14),
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF111827),
        ),
        maxWidth: width - 32,
      );
    }

    if (xAxisTitle.isNotEmpty) {
      _drawText(
        canvas,
        xAxisTitle,
        Offset((plotLeft + plotRight) / 2 - 80, height - 24),
        const TextStyle(fontSize: 12, color: Color(0xFF374151)),
        maxWidth: 160,
        align: TextAlign.center,
      );
    }

    if (yAxisTitle.isNotEmpty) {
      final angleRad = yAxisRotate * math.pi / 180.0;
      canvas.save();
      canvas.translate(16, (plotTop + plotBottom) / 2 + 50);
      canvas.rotate(angleRad);
      _drawText(
        canvas,
        yAxisTitle,
        const Offset(0, 0),
        const TextStyle(fontSize: 12, color: Color(0xFF374151)),
        maxWidth: 120,
        align: TextAlign.center,
      );
      canvas.restore();
    }

    _drawLegend(canvas, series, width: width);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _drawPieChart({
    required List<_ChartSeriesData> series,
    required List<String> xLabels,
    required String? chartTitle,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    final data = series.first.data;
    final labels = xLabels.isNotEmpty
        ? xLabels
        : List.generate(data.length, (i) => '${i + 1}');
    final total = data.fold<double>(0, (a, b) => a + b.abs());

    if (total == 0) {
      _drawText(
        canvas,
        'All values are zero',
        Offset(width / 2 - 80, height / 2),
        const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
      );
    } else {
      const palette = [
        Color(0xFF1E88E5),
        Color(0xFFE53935),
        Color(0xFF43A047),
        Color(0xFF8E24AA),
        Color(0xFFFB8C00),
        Color(0xFF00897B),
        Color(0xFFD81B60),
        Color(0xFF546E7A),
        Color(0xFF6D4C41),
        Color(0xFF039BE5),
      ];

      final cx = width * 0.40;
      final cy = height * 0.52;
      final radius = math.min(width * 0.30, height * 0.38);

      var startAngle = -math.pi / 2;
      for (var i = 0; i < data.length; i++) {
        final sweep = (data[i].abs() / total) * 2 * math.pi;
        final color = series.length == 1
            ? palette[i % palette.length]
            : series[i % series.length].color;

        final paint = Paint()..color = color;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          startAngle,
          sweep,
          true,
          paint,
        );

        final sep = Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          startAngle,
          sweep,
          true,
          sep,
        );

        final midAngle = startAngle + sweep / 2;
        final pct = (data[i].abs() / total * 100);
        if (pct > 4) {
          final lx = cx + math.cos(midAngle) * radius * 0.65;
          final ly = cy + math.sin(midAngle) * radius * 0.65;
          _drawText(
            canvas,
            '${pct.toStringAsFixed(1)}%',
            Offset(lx - 18, ly - 8),
            const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxWidth: 52,
            align: TextAlign.center,
          );
        }
        startAngle += sweep;
      }

      var ly = height * 0.18;
      final legendX = cx + radius + 24;
      for (var i = 0; i < data.length && i < labels.length; i++) {
        final color = series.length == 1
            ? palette[i % palette.length]
            : series[i % series.length].color;
        canvas.drawRect(
          Rect.fromLTWH(legendX, ly, 12, 12),
          Paint()..color = color,
        );
        _drawText(
          canvas,
          '${labels[i]} (${data[i].toStringAsFixed(1)})',
          Offset(legendX + 16, ly - 2),
          const TextStyle(fontSize: 11, color: Color(0xFF1F2937)),
          maxWidth: width - legendX - 24,
        );
        ly += 20;
      }
    }

    if (chartTitle != null && chartTitle.isNotEmpty) {
      _drawText(
        canvas,
        chartTitle,
        const Offset(16, 14),
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF111827),
        ),
        maxWidth: width - 32,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _renderLine(
    ui.Canvas canvas,
    List<_ChartSeriesData> series,
    double Function(int) mapX,
    double Function(double) mapY, {
    bool dots = true,
  }) {
    for (final line in series) {
      final path = Path();
      for (var i = 0; i < line.data.length; i++) {
        final pt = Offset(mapX(i), mapY(line.data[i]));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      if (dots) {
        final dotPaint = Paint()..color = line.color;
        for (var i = 0; i < line.data.length; i++) {
          canvas.drawCircle(Offset(mapX(i), mapY(line.data[i])), 3.0, dotPaint);
        }
      }
    }
  }

  void _renderArea(
    ui.Canvas canvas,
    List<_ChartSeriesData> series,
    double Function(int) mapX,
    double Function(double) mapY,
    double plotBottom,
  ) {
    for (final line in series) {
      final path = Path();
      for (var i = 0; i < line.data.length; i++) {
        final pt = Offset(mapX(i), mapY(line.data[i]));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.lineTo(mapX(line.data.length - 1), plotBottom);
      path.lineTo(mapX(0), plotBottom);
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = line.color.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );

      final stroke = Path();
      for (var i = 0; i < line.data.length; i++) {
        final pt = Offset(mapX(i), mapY(line.data[i]));
        if (i == 0) {
          stroke.moveTo(pt.dx, pt.dy);
        } else {
          stroke.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        stroke,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  void _renderScatter(
    ui.Canvas canvas,
    List<_ChartSeriesData> series,
    double Function(int) mapX,
    double Function(double) mapY,
  ) {
    for (final s in series) {
      final paint = Paint()..color = s.color.withValues(alpha: 0.8);
      for (var i = 0; i < s.data.length; i++) {
        canvas.drawCircle(Offset(mapX(i), mapY(s.data[i])), 4.0, paint);
      }
    }
  }

  void _renderBar(
    ui.Canvas canvas,
    List<_ChartSeriesData> series,
    List<String> xAxis,
    double Function(int) mapX,
    double Function(double) mapY,
    double plotWidth,
  ) {
    final groupCount = xAxis.length;
    final seriesCount = series.length;
    final groupWidth = plotWidth / math.max(groupCount, 1);
    final barGroupWidth = math.min(40.0, groupWidth * 0.75);
    final barWidth = math.max(3.0, barGroupWidth / math.max(seriesCount, 1));

    for (var i = 0; i < groupCount; i++) {
      final groupStart = mapX(i) - (barGroupWidth / 2);
      for (var j = 0; j < seriesCount; j++) {
        if (i >= series[j].data.length) continue;
        final value = series[j].data[i];
        final y = mapY(value);
        final zeroY = mapY(0);
        final top = math.min(y, zeroY);
        final bottom = math.max(y, zeroY);
        final left = groupStart + (j * barWidth);
        canvas.drawRect(
          Rect.fromLTWH(left, top, barWidth - 1, bottom - top),
          Paint()..color = series[j].color,
        );
      }
    }
  }

  void _drawXLabel(
    ui.Canvas canvas,
    String label,
    double x,
    double y,
    double rotateAngle,
  ) {
    if (rotateAngle.abs() < 1) {
      _drawText(
        canvas,
        label,
        Offset(x - 20, y),
        const TextStyle(fontSize: 10, color: Color(0xFF374151)),
        maxWidth: 60,
      );
    } else {
      final rad = rotateAngle * math.pi / 180.0;
      canvas.save();
      canvas.translate(x, y + 6);
      canvas.rotate(rad);
      _drawText(
        canvas,
        label,
        const Offset(-25, -6),
        const TextStyle(fontSize: 10, color: Color(0xFF374151)),
        maxWidth: 60,
      );
      canvas.restore();
    }
  }

  void _drawLegend(
    ui.Canvas canvas,
    List<_ChartSeriesData> series, {
    required int width,
  }) {
    var x = 16.0;
    const y = 42.0;

    for (final item in series) {
      final swatchPaint = Paint()..color = item.color;
      canvas.drawRect(Rect.fromLTWH(x, y, 12, 12), swatchPaint);
      _drawText(
        canvas,
        item.name,
        Offset(x + 16, y - 2),
        const TextStyle(fontSize: 11, color: Color(0xFF1F2937)),
        maxWidth: 140,
      );
      x += 160;
      if (x > width - 160) x = 16;
    }
  }

  void _drawText(
    ui.Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double? maxWidth,
    TextAlign align = TextAlign.left,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: '…',
    );
    textPainter.layout(maxWidth: maxWidth ?? double.infinity);
    textPainter.paint(canvas, offset);
  }

  Color? _parseColor(String hex) {
    final normalized = hex.replaceAll('#', '').trim();
    if (normalized.length == 6) {
      final parsed = int.tryParse('FF$normalized', radix: 16);
      if (parsed == null) return null;
      return Color(parsed);
    }
    if (normalized.length == 8) {
      final parsed = int.tryParse(normalized, radix: 16);
      if (parsed == null) return null;
      return Color(parsed);
    }
    return null;
  }
}

class _ChartSeriesData {
  final String name;
  final List<double> data;
  final Color color;

  const _ChartSeriesData({
    required this.name,
    required this.data,
    required this.color,
  });
}
