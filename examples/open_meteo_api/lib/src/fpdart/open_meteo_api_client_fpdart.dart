import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:open_meteo_api/open_meteo_api.dart';
import 'package:open_meteo_api/src/fpdart/location_failure.dart';
import 'package:open_meteo_api/src/fpdart/weather_failure.dart';

class OpenMeteoApiClientFpdart {
  OpenMeteoApiClientFpdart({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _baseUrlWeather = 'api.open-meteo.com';
  static const _baseUrlGeocoding = 'geocoding-api.open-meteo.com';

  final http.Client _httpClient;

  /// Finds a [Location] `/v1/search/?name=(query)`.
  TaskEither<OpenMeteoApiFpdartLocationFailure, Location> locationSearch(
    String query,
  ) =>
      TaskEither<OpenMeteoApiFpdartLocationFailure, http.Response>.tryCatch(
        () => _httpClient.get(
          Uri.https(
            _baseUrlGeocoding,
            '/v1/search',
            {'name': query, 'count': '1'},
          ),
        ),
        LocationHttpRequestFpdartFailure.new,
      ).chainEither(
        (response) => Either.Do(($) {
          final body = $(
            _validResponseBody(response, LocationRequestFpdartFailure.new),
          );

          final json = $(
            Either.tryCatch(
              () => jsonDecode(body),
              (_, __) => LocationInvalidJsonDecodeFpdartFailure(body),
            ),
          );

          final data = $(
            Either<OpenMeteoApiFpdartLocationFailure,
                Map<dynamic, dynamic>>.safeCast(
              json,
              LocationInvalidMapFpdartFailure.new,
            ),
          );

          final currentWeather = $(
            data
                .lookup('results')
                .toEither(LocationKeyNotFoundFpdartFailure.new),
          );

          final results = $(
            Either<OpenMeteoApiFpdartLocationFailure, List<dynamic>>.safeCast(
              currentWeather,
              LocationInvalidListFpdartFailure.new,
            ),
          );

          final weather = $(
            results.head.toEither(LocationDataNotFoundFpdartFailure.new),
          );

          return $(
            Either.tryCatch(
              () => Location.fromJson(weather as Map<String, dynamic>),
              LocationFormattingFpdartFailure.new,
            ),
          );
        }),
      );

  /// Fetches [Weather] for a given [latitude] and [longitude].
  TaskEither<OpenMeteoApiFpdartWeatherFailure, Weather> getWeather({
    required double latitude,
    required double longitude,
  }) =>
      TaskEither<OpenMeteoApiFpdartWeatherFailure, http.Response>.tryCatch(
        () async => _httpClient.get(
          Uri.https(
            _baseUrlWeather,
            'v1/forecast',
            {
              'latitude': '$latitude',
              'longitude': '$longitude',
              'current_weather': 'true'
            },
          ),
        ),
        WeatherHttpRequestFpdartFailure.new,
      )
          .chainEither(
            (response) =>
                _validResponseBody(response, WeatherRequestFpdartFailure.new),
          )
          .chainEither(
            (body) => Either.safeCastStrict<
                OpenMeteoApiFpdartWeatherFailure,
                Map<dynamic, dynamic>,
                String>(body, WeatherInvalidMapFpdartFailure.new),
          )
          .chainEither(
            (body) => body
                .lookup('current_weather')
                .toEither(WeatherKeyNotFoundFpdartFailure.new),
          )
          .chainEither(
            (currentWeather) => Either<OpenMeteoApiFpdartWeatherFailure,
                List<dynamic>>.safeCast(
              currentWeather,
              WeatherInvalidListFpdartFailure.new,
            ),
          )
          .chainEither(
            (results) =>
                results.head.toEither(WeatherDataNotFoundFpdartFailure.new),
          )
          .chainEither(
            (weather) => Either.tryCatch(
              () => Weather.fromJson(weather as Map<String, dynamic>),
              WeatherFormattingFpdartFailure.new,
            ),
          );

  /// Verify that the response status code is 200,
  /// and extract the response's body.
  Either<E, String> _validResponseBody<E>(
    http.Response response,
    E Function(http.Response) onError,
  ) =>
      Either<E, http.Response>.fromPredicate(
        response,
        (r) => r.statusCode == 200,
        onError,
      ).map((r) => r.body);
}
