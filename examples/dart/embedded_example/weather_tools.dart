import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

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

const String _baseUrl = 'https://api.open-meteo.com/v1';
const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

class GetCurrentWeatherTool extends McpLocalTool {
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
