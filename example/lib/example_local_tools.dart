import 'dart:convert';
import 'dart:typed_data';
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
  String get name => 'ssh_list_directory';

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
  String get name => 'ssh_read_file';

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
  String get name => 'ssh_download_file';

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
  String get name => 'ssh_upload_file';

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
  String get name => 'ssh_execute_command';

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
  String get name => 'ssh_make_directory';

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
  String get name => 'ssh_remove_directory';

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
// 3. Chart Generation Tool (JSON-based, rendered via fl_chart in host)
// ═══════════════════════════════════════════════════════════════

class CreateChartPngTool extends McpLocalTool {
  @override
  String get name => 'create_chart_png';

  @override
  String get description =>
      'Generate a chart (line, bar, pie) from x-axis labels and numeric data series. Returns chart configuration JSON.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'chart_type': {
        'type': 'string',
        'description': 'Chart style: "line", "bar", "pie".',
        'enum': ['line', 'bar', 'pie'],
        'default': 'line',
      },
      'title': {'type': 'string', 'description': 'Chart title shown at top.'},
      'labels': {
        'type': 'array',
        'description': 'X-axis labels.',
        'items': {'type': 'string'},
      },
      'data': {
        'type': 'array',
        'description': 'Y-axis numeric values matching labels.',
        'items': {'type': 'number'},
      },
    },
    'required': ['labels', 'data'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final chartType = (arguments['chart_type'] as String? ?? 'line').trim().toLowerCase();
      final title = (arguments['title'] as String?)?.trim() ?? 'Chart';
      final labels = (arguments['labels'] as List?)?.cast<String>() ?? [];
      final data = (arguments['data'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];

      final jsonMap = {
        'chart_type': chartType,
        'title': title,
        'labels': labels,
        'data': data,
      };

      return MCPToolResult(
        content: [
          MCPContent(
            type: 'text',
            text: jsonEncode(jsonMap),
          ),
        ],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Chart generation failed: $e')],
        isError: true,
      );
    }
  }
}
