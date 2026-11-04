import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'place.dart';

/// Current conditions for one place.
class Weather {
  const Weather({
    required this.place,
    required this.temperatureC,
    required this.code,
    required this.isDay,
    required this.utcOffsetSeconds,
  });

  final Place place;
  final double temperatureC;
  final int code;
  final bool isDay;

  /// The place's offset from UTC, in seconds (19800 for India).
  final int utcOffsetSeconds;
}

/// An error with a message that is safe to show to the person.
class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Looks places up and fetches their current weather from Open-Meteo
/// (free, no API key).
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  /// Places matching [query], best match first. Empty when nothing matches.
  Future<List<Place>> searchPlaces(String query, {int count = 5}) async {
    final name = query.trim();
    if (name.isEmpty) {
      throw const WeatherException('Type a place to search.');
    }
    final json = await _getJson(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': name,
        'count': '$count',
        'language': 'en',
        'format': 'json',
      }),
      failure: 'Location search failed. Try again.',
    );
    final results = json['results'] as List<dynamic>?;
    if (results == null) return const [];

    // Drop near-duplicates so the suggestion list stays tidy.
    final seen = <String>{};
    final places = <Place>[];
    for (final item in results) {
      final place = Place.fromGeocoding(item as Map<String, dynamic>);
      if (seen.add(place.id)) places.add(place);
    }
    return places;
  }

  /// Current weather at [place].
  Future<Weather> weatherFor(Place place) async {
    final json = await _getJson(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${place.latitude}',
        'longitude': '${place.longitude}',
        'current': 'temperature_2m,weather_code,is_day',
        'timezone': 'auto',
      }),
      failure: 'Weather is unavailable. Try again.',
    );
    final current = json['current'] as Map<String, dynamic>;
    return Weather(
      place: place,
      temperatureC: (current['temperature_2m'] as num).toDouble(),
      code: (current['weather_code'] as num).toInt(),
      isDay: (current['is_day'] as num) == 1,
      utcOffsetSeconds: (json['utc_offset_seconds'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri,
      {required String failure}) async {
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) throw WeatherException(failure);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on WeatherException {
      rethrow;
    } on TimeoutException {
      throw const WeatherException('That took too long. Try again.');
    } on http.ClientException {
      throw const WeatherException('No connection. Check your internet.');
    } catch (_) {
      throw const WeatherException('Something went wrong. Try again.');
    }
  }
}
