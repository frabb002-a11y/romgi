import 'package:dio/dio.dart';

class IgdbException implements Exception {
  final String message;

  const IgdbException(this.message);

  @override
  String toString() => message;
}

class IgdbGenre {
  final int id;
  final String name;

  const IgdbGenre({required this.id, required this.name});
}

class IgdbListedGame {
  final int id;
  final String name;
  final double score;
  final List<String> alternativeNames;

  const IgdbListedGame({
    required this.id,
    required this.name,
    required this.score,
    this.alternativeNames = const [],
  });
}

String igdbGamesQuery({
  required int platformId,
  required List<int> genreIds,
  required double minimumScore,
  required int offset,
}) {
  final score = minimumScore <= 0
      ? 'aggregated_rating != null'
      : 'aggregated_rating >= ${minimumScore.toStringAsFixed(0)}';
  final genres = genreIds.isEmpty
      ? ''
      : ' & genres = (${genreIds.join(',')})';
  return 'fields name,aggregated_rating,alternative_names.name;'
      ' where platforms = ($platformId) & category = 0 & $score$genres;'
      ' sort aggregated_rating desc;'
      ' limit 500;'
      ' offset $offset;';
}

List<IgdbGenre> parseIgdbGenres(Object? body) {
  if (body is! List) return const [];
  final genres = <IgdbGenre>[];
  for (final item in body) {
    if (item is! Map) continue;
    final id = item['id'];
    final name = item['name'];
    if (id is! int || name is! String || name.trim().isEmpty) continue;
    genres.add(IgdbGenre(id: id, name: name.trim()));
  }
  genres.sort((a, b) => a.name.compareTo(b.name));
  return genres;
}

List<IgdbListedGame> parseIgdbGames(Object? body) {
  if (body is! List) return const [];
  final games = <IgdbListedGame>[];
  for (final item in body) {
    if (item is! Map) continue;
    final id = item['id'];
    final name = item['name'];
    final score = item['aggregated_rating'];
    if (id is! int || name is! String || name.trim().isEmpty) continue;
    if (score is! num) continue;
    games.add(
      IgdbListedGame(
        id: id,
        name: name.trim(),
        score: score.toDouble(),
        alternativeNames: _alternativeNames(item['alternative_names']),
      ),
    );
  }
  return games;
}

List<String> _alternativeNames(Object? raw) {
  if (raw is! List) return const [];
  final names = <String>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name'];
    if (name is String && name.trim().isNotEmpty) names.add(name.trim());
  }
  return names;
}

class IgdbClient {
  IgdbClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  String? _token;
  DateTime? _tokenExpires;
  String? _tokenClientId;

  Future<List<IgdbGenre>> genres({
    required String clientId,
    required String clientSecret,
    CancelToken? cancelToken,
  }) async {
    final body = await _post(
      'https://api.igdb.com/v4/genres',
      'fields name; limit 500;',
      clientId: clientId,
      clientSecret: clientSecret,
      cancelToken: cancelToken,
    );
    return parseIgdbGenres(body);
  }

  Future<List<IgdbListedGame>> games({
    required String clientId,
    required String clientSecret,
    required int platformId,
    required List<int> genreIds,
    required double minimumScore,
    required int offset,
    CancelToken? cancelToken,
  }) async {
    final body = await _post(
      'https://api.igdb.com/v4/games',
      igdbGamesQuery(
        platformId: platformId,
        genreIds: genreIds,
        minimumScore: minimumScore,
        offset: offset,
      ),
      clientId: clientId,
      clientSecret: clientSecret,
      cancelToken: cancelToken,
    );
    return parseIgdbGames(body);
  }

  Future<Object?> _post(
    String url,
    String query, {
    required String clientId,
    required String clientSecret,
    CancelToken? cancelToken,
  }) async {
    final token = await _accessToken(
      clientId: clientId,
      clientSecret: clientSecret,
      cancelToken: cancelToken,
    );
    DioException? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      await _pace();
      try {
        final response = await _dio.post<Object?>(
          url,
          data: query,
          cancelToken: cancelToken,
          options: Options(
            contentType: 'text/plain',
            headers: {
              'Client-ID': clientId,
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          ),
        );
        return response.data;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        last = error;
        if (error.response?.statusCode == 429 && attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        break;
      }
    }
    final code = last?.response?.statusCode;
    if (code == 401) {
      throw const IgdbException(
        'IGDB rejected the Twitch login. Check the Client ID and secret.',
      );
    }
    if (code == 429) {
      throw const IgdbException(
        'IGDB is rate limiting requests. Try again in a little while.',
      );
    }
    throw const IgdbException('Could not reach IGDB.');
  }

  DateTime? _nextSlot;

  Future<void> _pace() async {
    final now = DateTime.now();
    final waitUntil = _nextSlot;
    if (waitUntil != null && waitUntil.isAfter(now)) {
      await Future<void>.delayed(waitUntil.difference(now));
    }
    _nextSlot = DateTime.now().add(const Duration(milliseconds: 280));
  }

  Future<String> _accessToken({
    required String clientId,
    required String clientSecret,
    CancelToken? cancelToken,
  }) async {
    final current = _token;
    final expires = _tokenExpires;
    if (current != null &&
        _tokenClientId == clientId &&
        expires != null &&
        DateTime.now().isBefore(expires)) {
      return current;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://id.twitch.tv/oauth2/token',
        queryParameters: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'client_credentials',
        },
        cancelToken: cancelToken,
      );
      final token = response.data?['access_token'];
      final seconds = response.data?['expires_in'];
      if (token is! String || token.isEmpty) {
        throw const IgdbException(
          'IGDB rejected the Twitch login. Check the Client ID and secret.',
        );
      }
      _token = token;
      _tokenClientId = clientId;
      final lifetime = seconds is num ? seconds.toInt() : 3600;
      _tokenExpires = DateTime.now().add(Duration(seconds: lifetime - 60));
      return token;
    } on IgdbException {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const IgdbException(
        'IGDB rejected the Twitch login. Check the Client ID and secret.',
      );
    }
  }
}
