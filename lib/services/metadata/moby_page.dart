import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

class MobyPageException implements Exception {
  final String message;

  const MobyPageException(this.message);

  @override
  String toString() => message;
}

class MobyListedGame {
  final int gameId;
  final String title;
  final double score;

  const MobyListedGame({
    required this.gameId,
    required this.title,
    required this.score,
  });
}

class MobyPageParse {
  final List<MobyListedGame> games;

  /// True when a row had no score, or a score below the cutoff.
  /// [games] stops before that row.
  final bool stopped;

  const MobyPageParse({required this.games, required this.stopped});
}

/// The "Page 3 of 49" line under a platform list. [current] is 1-based.
class MobyListingPager {
  final int current;
  final int count;

  const MobyListingPager({required this.current, required this.count});

  bool get isLast => current >= count;
}

final _pagerPattern = RegExp(
  r'Page\s+(\d+)\s+of\s+(\d+)',
  caseSensitive: false,
);

/// Reads the pager that follows the scored table. A later widget, such as
/// related listings, can carry its own "Page 1 of 2" and is ignored.
MobyListingPager? mobyListingPager(String html) {
  final scoreAt = html.toLowerCase().indexOf('mobyscore');
  final region = scoreAt >= 0 ? html.substring(scoreAt) : html;
  final match = _pagerPattern.firstMatch(region);
  if (match == null) return null;
  final current = int.tryParse(match.group(1)!);
  final count = int.tryParse(match.group(2)!);
  if (current == null || count == null || current < 1 || count < 1) {
    return null;
  }
  return MobyListingPager(current: current, count: count);
}

/// True when every id on this page was already stored from an earlier page.
bool mobyPageRepeats(Set<int> seen, Iterable<int> gameIds) {
  final ids = gameIds.where((id) => id > 0).toList();
  if (ids.isEmpty) return false;
  return ids.every(seen.contains);
}

final _rowPattern = RegExp(r'<tr>(.*?)</tr>', dotAll: true);
final _titlePattern = RegExp(
  r'<a href="(?:https://www\.mobygames\.com)?/game/(\d+)/[^"]+/">([^<]+)</a>',
);
final _scorePattern = RegExp(r'class="mobyscore"[^>]*>\s*([\d.]+)');

/// Reads one public platform listing page. Rows are already ordered by
/// score, highest first. Stops at the first missing score or the first
/// score below [cutoff]. A cutoff of 0 keeps every scored row.
MobyPageParse parseMobyPlatformPage(String html, {required double cutoff}) {
  final games = <MobyListedGame>[];
  final seen = <String>{};
  for (final row in _rowPattern.allMatches(html)) {
    final rowHtml = row.group(1)!;
    final titleMatch = _titlePattern.firstMatch(rowHtml);
    if (titleMatch == null) continue;
    final title = unescapeHtml(titleMatch.group(2)!.trim());
    if (title.isEmpty || !seen.add(title)) continue;
    final scoreMatch = _scorePattern.firstMatch(rowHtml);
    final score = scoreMatch == null
        ? null
        : double.tryParse(scoreMatch.group(1)!);
    if (score == null || score < cutoff) {
      return MobyPageParse(games: games, stopped: true);
    }
    games.add(
      MobyListedGame(
        gameId: int.tryParse(titleMatch.group(1)!) ?? 0,
        title: title,
        score: score,
      ),
    );
  }
  return MobyPageParse(games: games, stopped: false);
}

String unescapeHtml(String value) {
  final numeric = value.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    return String.fromCharCode(int.parse(match.group(1)!));
  }).replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
  });
  return numeric
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

bool mobyPageLooksBlocked(String html) {
  if (html.contains('/game/')) return false;
  final lower = html.toLowerCase();
  return lower.contains('just a moment') ||
      lower.contains('cf-challenge') ||
      lower.contains('challenge-platform') ||
      lower.contains('cf-browser-verification') ||
      lower.contains('cf-mitigated');
}

/// Loads a MobyGames URL in the app browser. Set by [MobyBrowserHost]
/// while the app is on screen. The site answers plain requests with a
/// Cloudflare check, and that check has to run in a real page.
typedef MobyBrowserLoad = Future<String> Function(
  String url, {
  CancelToken? cancelToken,
});

class MobyBrowser {
  static MobyBrowserLoad? load;
}

class MobyPageClient {
  MobyPageClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  var _preferBrowser = false;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    dio.httpClientAdapter = NativeAdapter();
    return dio;
  }

  Future<String> fetchPlatformPage(
    String slug,
    int page, {
    CancelToken? cancelToken,
  }) async {
    final base = 'https://www.mobygames.com/platform/$slug/';
    final url = page <= 0 ? base : '${base}page:$page/';
    if (_preferBrowser) {
      return _loadInBrowser(url, cancelToken);
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _dio.get<String>(url, cancelToken: cancelToken);
      final code = response.statusCode ?? 0;
      if (code == 429) {
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      final html = response.data ?? '';
      if (code == 403 || code == 503 || mobyPageLooksBlocked(html)) {
        return _loadInBrowser(url, cancelToken);
      }
      if (code != 200) {
        throw MobyPageException('MobyGames returned HTTP $code.');
      }
      return html;
    }
    throw const MobyPageException(
      'MobyGames is rate limiting requests. Try again in a little while.',
    );
  }

  Future<String> _loadInBrowser(String url, CancelToken? cancelToken) {
    final load = MobyBrowser.load;
    if (load == null) {
      throw const MobyPageException(
        'MobyGames asked for a browser check. Open Romgi and start the build again.',
      );
    }
    _preferBrowser = true;
    return load(url, cancelToken: cancelToken);
  }
}
