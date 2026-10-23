import 'package:dio/dio.dart';

class MobyRateLimited implements Exception {}

class MobyUnauthorized implements Exception {}

class MobyGamePage {
  final List<MobyListedGame> games;

  const MobyGamePage(this.games);

  bool get isLast => games.length < 100;
}

class MobyListedGame {
  final int gameId;
  final String title;
  final double? score;
  final List<String> alternateTitles;

  const MobyListedGame({
    required this.gameId,
    required this.title,
    required this.score,
    required this.alternateTitles,
  });
}

class MobyGamesClient {
  MobyGamesClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.mobygames.com/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;

  Future<void> validate(String apiKey) async {
    await _games(apiKey: apiKey, platformId: 22, offset: 0, limit: 1);
  }

  Future<MobyGamePage> games({
    required String apiKey,
    required int platformId,
    required int offset,
  }) async {
    final games = await _games(
      apiKey: apiKey,
      platformId: platformId,
      offset: offset,
      limit: 100,
    );
    return MobyGamePage(games);
  }

  Future<List<MobyListedGame>> _games({
    required String apiKey,
    required int platformId,
    required int offset,
    required int limit,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/games',
      queryParameters: {
        'api_key': apiKey,
        'platform': platformId,
        'limit': limit,
        'offset': offset,
        'format': 'normal',
      },
    );
    final code = response.statusCode ?? 0;
    if (code == 429) throw MobyRateLimited();
    if (code == 401 || code == 403) throw MobyUnauthorized();
    if (code != 200) {
      throw Exception('MobyGames returned $code');
    }
    final body = response.data;
    final raw = body?['games'];
    if (raw is! List) return const [];
    return raw.map((item) {
      final game = item as Map<String, dynamic>;
      final score = game['moby_score'];
      final alternates = <String>[];
      final rawAlternates = game['alternate_titles'];
      if (rawAlternates is List) {
        for (final alternate in rawAlternates) {
          if (alternate is Map && alternate['title'] is String) {
            alternates.add(alternate['title'] as String);
          }
        }
      }
      return MobyListedGame(
        gameId: game['game_id'] as int? ?? 0,
        title: game['title'] as String? ?? '',
        score: score is num ? score.toDouble() : null,
        alternateTitles: alternates,
      );
    }).toList();
  }
}
