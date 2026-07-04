import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mcp_playground_dart/mcp_playground_dart.dart';

// ═══════════════════════════════════════════════════════════════
// Pure-Dart MCP tool implementations — no Flutter dependency.
//
// Weather tools:  Open-Meteo free REST API (no key required).
// SSH tools:      dartssh2 (pure Dart, no Flutter).
// Chart tools:    Pure-Dart PNG renderer (dart:io ZLibEncoder).
//
// These tools are shared across the dart (headless) example and
// can also be used by Flutter apps that depend on this package.
// ═══════════════════════════════════════════════════════════════

// ── WMO weather code → human-readable description ──────────────

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

const String _weatherBaseUrl = 'https://api.open-meteo.com/v1';
const String _geocodeUrl = 'https://geocoding-api.open-meteo.com/v1';

/// Helper: resolve a city name or "lat,lng" string into (lat, lng, displayName).
Future<({double lat, double lng, String name})?> _resolveLocation(
  Map<String, dynamic> arguments,
) async {
  double? lat;
  double? lng;
  String resolvedName = 'Unknown';

  if (arguments['latitude'] != null && arguments['longitude'] != null) {
    lat = (arguments['latitude'] as num).toDouble();
    lng = (arguments['longitude'] as num).toDouble();
    resolvedName = 'Lat $lat, Lng $lng';
  } else {
    final location = (arguments['location'] as String? ?? '').trim();
    if (location.isEmpty) return null;

    final coordMatch = RegExp(
      r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$',
    ).firstMatch(location);
    if (coordMatch != null) {
      lat = double.parse(coordMatch.group(1)!);
      lng = double.parse(coordMatch.group(2)!);
      resolvedName = 'Lat $lat, Lng $lng';
    } else {
      final geoResp = await http
          .get(
            Uri.parse(
              '$_geocodeUrl/search?name=${Uri.encodeComponent(location)}&count=1&language=en&format=json',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (geoResp.statusCode == 200) {
        final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
        final results = geoData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          lat = (first['latitude'] as num).toDouble();
          lng = (first['longitude'] as num).toDouble();
          resolvedName =
              '${first['name']}, ${first['country'] ?? ''} (${first['admin1'] ?? ''})';
        }
      }
    }
  }

  if (lat == null || lng == null) return null;
  return (lat: lat, lng: lng, name: resolvedName);
}

// ═══════════════════════════════════════════════════════════════
// 1. Geocode Weather City Tool
// ═══════════════════════════════════════════════════════════════

class GeocodeWeatherCityTool extends McpLocalTool {
  @override
  String get name => 'geocode_weather_city';

  @override
  String get description =>
      'Look up coordinates (latitude, longitude) for a city name. '
      'Returns results with lat, lng, name, country, and timezone.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'city': {
        'type': 'string',
        'description': 'City name, e.g. "Rome, Italy"',
      },
    },
    'required': ['city'],
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final city = (arguments['city'] as String? ?? '').trim();
      if (city.isEmpty) {
        return const MCPToolResult(
          content: [MCPContent(type: 'text', text: 'Error: city is required.')],
          isError: true,
        );
      }
      final geoResp = await http
          .get(
            Uri.parse(
              '$_geocodeUrl/search?name=${Uri.encodeComponent(city)}&count=3&language=en&format=json',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (geoResp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Geocoding failed (HTTP ${geoResp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final results =
          (data['results'] as List?)
              ?.map((r) => r as Map<String, dynamic>)
              .toList() ??
          [];

      if (results.isEmpty) {
        return const MCPToolResult(
          content: [MCPContent(type: 'text', text: 'No results found.')],
          isError: true,
        );
      }

      // Return the first result as JSON for easy ${tool_result} piping
      final first = results.first;
      final output = {
        'latitude': first['latitude'],
        'longitude': first['longitude'],
        'name': '${first['name']}, ${first['country'] ?? ''}',
        'timezone': first['timezone'],
        'country': first['country'],
      };

      final buf = StringBuffer();
      buf.writeln('### Geocoding results for "$city":');
      for (final r in results) {
        buf.writeln(
          '- **${r['name']}**, ${r['country'] ?? ''} (${r['admin1'] ?? ''}) '
          '→ lat=${r['latitude']}, lng=${r['longitude']}',
        );
      }
      buf.writeln();
      buf.writeln('```json');
      buf.writeln(jsonEncode(output));
      buf.writeln('```');

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buf.toString())],
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
// 2. Get Current Weather Tool
// ═══════════════════════════════════════════════════════════════

class GetCurrentWeatherTool extends McpLocalTool {
  @override
  String get name => 'get_current_weather';

  @override
  String get description =>
      'Get current weather: temperature, humidity, wind speed, and conditions.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description': 'City name (e.g. "Vienna") or coordinates "lat,lng".',
      },
      'latitude': {'type': 'number'},
      'longitude': {'type': 'number'},
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final loc = await _resolveLocation(arguments);
      if (loc == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve location.',
            ),
          ],
          isError: true,
        );
      }

      final resp = await http
          .get(
            Uri.parse(
              '$_weatherBaseUrl/forecast?latitude=${loc.lat}&longitude=${loc.lng}'
              '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
              '&timezone=auto',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;

      final buf = StringBuffer();
      buf.writeln('### Current Weather for ${loc.name}');
      if (current != null) {
        buf.writeln('- Temperature: ${current['temperature_2m']}°C');
        buf.writeln('- Humidity: ${current['relative_humidity_2m']}%');
        buf.writeln('- Wind Speed: ${current['wind_speed_10m']} km/h');
        final code = (current['weather_code'] as num?)?.toInt() ?? 0;
        buf.writeln('- Conditions: ${_wmoCodeToDesc(code)}');
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buf.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Weather error: $e')],
        isError: true,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Get Hourly Forecast Tool
// ═══════════════════════════════════════════════════════════════

class GetHourlyForecastTool extends McpLocalTool {
  @override
  String get name => 'get_hourly_forecast';

  @override
  String get description =>
      'Get hourly weather forecast (temperature, humidity, wind, conditions) '
      'for the next N hours. Returns a markdown table.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description': 'City name or "lat,lng" coordinates.',
      },
      'latitude': {'type': 'number'},
      'longitude': {'type': 'number'},
      'hours': {
        'type': 'integer',
        'description': 'Number of forecast hours (default 24, max 168).',
      },
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final loc = await _resolveLocation(arguments);
      if (loc == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve location.',
            ),
          ],
          isError: true,
        );
      }

      final hours = (arguments['hours'] as num?)?.toInt() ?? 24;

      final resp = await http
          .get(
            Uri.parse(
              '$_weatherBaseUrl/forecast?latitude=${loc.lat}&longitude=${loc.lng}'
              '&hourly=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
              '&forecast_hours=$hours&timezone=auto',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final hourly = data['hourly'] as Map<String, dynamic>?;

      final buf = StringBuffer();
      buf.writeln('### ${hours}h Hourly Forecast for ${loc.name}');
      if (hourly != null) {
        final times = hourly['time'] as List;
        final temps = hourly['temperature_2m'] as List;
        final humidities = hourly['relative_humidity_2m'] as List;
        final windSpeeds = hourly['wind_speed_10m'] as List?;
        final codes = hourly['weather_code'] as List;

        buf.writeln(
          '| Time | Temp (°C) | Humidity | Wind (km/h) | Conditions |',
        );
        buf.writeln(
          '|------|-----------|----------|-------------|------------|',
        );
        for (int i = 0; i < times.length; i++) {
          final time = times[i].toString().replaceFirst('T', ' ');
          final temp = temps[i];
          final hum = humidities[i];
          final wind = windSpeeds != null && i < windSpeeds.length
              ? windSpeeds[i].toString()
              : '—';
          final code = codes[i] is num ? (codes[i] as num).toInt() : 0;
          buf.writeln(
            '| $time | $temp°C | $hum% | $wind | ${_wmoCodeToDesc(code)} |',
          );
        }
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buf.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Forecast error: $e')],
        isError: true,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. Get Daily Forecast Tool
// ═══════════════════════════════════════════════════════════════

class GetDailyForecastTool extends McpLocalTool {
  @override
  String get name => 'get_daily_forecast';

  @override
  String get description =>
      'Get daily weather forecast (min/max temperature, precipitation '
      'probability, conditions) for the next 1-16 days.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description': 'City name or "lat,lng" coordinates.',
      },
      'latitude': {'type': 'number'},
      'longitude': {'type': 'number'},
      'days': {
        'type': 'integer',
        'description': 'Number of forecast days (1-16, default: 7).',
      },
    },
  };

  @override
  Future<MCPToolResult> execute(Map<String, dynamic> arguments) async {
    try {
      final loc = await _resolveLocation(arguments);
      if (loc == null) {
        return const MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Error: Could not resolve location.',
            ),
          ],
          isError: true,
        );
      }

      final days = (arguments['days'] as num?)?.toInt() ?? 7;

      final resp = await http
          .get(
            Uri.parse(
              '$_weatherBaseUrl/forecast?latitude=${loc.lat}&longitude=${loc.lng}'
              '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
              '&forecast_days=$days&timezone=auto',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return MCPToolResult(
          content: [
            MCPContent(
              type: 'text',
              text: 'Weather API failed (HTTP ${resp.statusCode}).',
            ),
          ],
          isError: true,
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>?;

      final buf = StringBuffer();
      buf.writeln('### Daily Weather Forecast for ${loc.name}');
      if (daily != null) {
        final times = daily['time'] as List;
        final maxTemps = daily['temperature_2m_max'] as List;
        final minTemps = daily['temperature_2m_min'] as List;
        final probs = daily['precipitation_probability_max'] as List;
        final codes = daily['weather_code'] as List;

        buf.writeln('| Date | Min (°C) | Max (°C) | Rain % | Conditions |');
        buf.writeln('|------|----------|----------|--------|------------|');
        for (int i = 0; i < times.length; i++) {
          final codeVal = codes[i] is num ? (codes[i] as num).toInt() : 0;
          buf.writeln(
            '| ${times[i]} | ${minTemps[i]} | ${maxTemps[i]} | ${probs[i]} | ${_wmoCodeToDesc(codeVal)} |',
          );
        }
      }

      return MCPToolResult(
        content: [MCPContent(type: 'text', text: buf.toString())],
        isError: false,
      );
    } catch (e) {
      return MCPToolResult(
        content: [MCPContent(type: 'text', text: 'Forecast error: $e')],
        isError: true,
      );
    }
  }
}
