import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minimal_weather/place.dart';
import 'package:minimal_weather/weather_service.dart';

Map<String, dynamic> _geo(String name, double lat, double lon,
        {String? region, String country = 'India', String cc = 'IN'}) =>
    {
      'name': name,
      'latitude': lat,
      'longitude': lon,
      'admin1': region,
      'country': country,
      'country_code': cc,
    };

void main() {
  group('searchPlaces', () {
    test('returns suggestions with region and country', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'geocoding-api.open-meteo.com');
        return http.Response(
          jsonEncode({
            'results': [
              _geo('Bengaluru', 12.97, 77.59, region: 'Karnataka'),
              _geo('Bengaluru Rural', 13.2, 77.4, region: 'Karnataka'),
            ]
          }),
          200,
        );
      });

      final places = await WeatherService(client: client).searchPlaces('beng');

      expect(places.map((p) => p.name), ['Bengaluru', 'Bengaluru Rural']);
      expect(places.first.subtitle, 'Karnataka, India');
      expect(places.first.countryCode, 'IN');
    });

    test('drops duplicates at the same spot', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'results': [
                _geo('Paris', 48.85, 2.35, country: 'France', cc: 'FR'),
                _geo('Paris', 48.851, 2.351, country: 'France', cc: 'FR'),
              ]
            }),
            200,
          ));

      final places = await WeatherService(client: client).searchPlaces('paris');

      expect(places, hasLength(1));
    });

    test('is empty when nothing matches', () async {
      final client = MockClient((_) async => http.Response('{}', 200));

      final places = await WeatherService(client: client).searchPlaces('zzzzz');

      expect(places, isEmpty);
    });

    test('rejects an empty search', () {
      final client = MockClient((_) async => http.Response('', 200));

      expect(
        () => WeatherService(client: client).searchPlaces('   '),
        throwsA(isA<WeatherException>()),
      );
    });

    test('turns network failures into a friendly error', () {
      final client =
          MockClient((_) async => throw http.ClientException('offline'));

      expect(
        () => WeatherService(client: client).searchPlaces('Paris'),
        throwsA(isA<WeatherException>()),
      );
    });
  });

  group('weatherFor', () {
    test('returns weather and the place UTC offset', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.queryParameters['timezone'], 'auto');
        return http.Response(
          jsonEncode({
            'utc_offset_seconds': 19800,
            'current': {'temperature_2m': 26.4, 'weather_code': 3, 'is_day': 1}
          }),
          200,
        );
      });
      const place = Place(
        name: 'Bengaluru',
        latitude: 12.97,
        longitude: 77.59,
        country: 'India',
      );

      final weather = await WeatherService(client: client).weatherFor(place);

      expect(weather.place.name, 'Bengaluru');
      expect(weather.temperatureC, 26.4);
      expect(weather.code, 3);
      expect(weather.isDay, isTrue);
      expect(weather.utcOffsetSeconds, 19800);
    });

    test('reports a server error', () {
      final client = MockClient((_) async => http.Response('nope', 500));
      const place = Place(name: 'X', latitude: 0, longitude: 0);

      expect(
        () => WeatherService(client: client).weatherFor(place),
        throwsA(isA<WeatherException>()),
      );
    });
  });
}
