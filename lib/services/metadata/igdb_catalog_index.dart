import '../../models/igdb_catalog_entry.dart';
import 'igdb_platforms.dart';
import 'igdb_ranking.dart';
import 'moby_titles.dart';

/// Downstream gates (Browse filters) applied on IGDB user scores.
class IgdbDownstreamFilters {
  final double minUserRating;
  final int minVotes;
  final bool mainGameOnly;
  final bool excludeUtilityNames;

  const IgdbDownstreamFilters({
    this.minUserRating = 60,
    this.minVotes = 10,
    this.mainGameOnly = false,
    this.excludeUtilityNames = false,
  });

}

enum IgdbRejectReason { lowVotes, lowRating, gameType, utilityName }

class IgdbGameRecord {
  final String platform;
  final int gameId;
  final String name;
  final double rating;
  final int ratingCount;
  final double weighted;
  final int gameType;

  const IgdbGameRecord({
    required this.platform,
    required this.gameId,
    required this.name,
    required this.rating,
    required this.ratingCount,
    required this.weighted,
    this.gameType = 0,
  });

  IgdbCatalogEntry toCatalogEntry() => IgdbCatalogEntry(
    platform: platform,
    gameId: gameId,
    name: name,
    rating: rating,
    ratingCount: ratingCount,
    weighted: weighted,
  );
}

class IgdbCatalogIndex {
  final Map<String, Map<int, IgdbGameRecord>> gamesByPlatform;
  final Map<String, int> titleKeyToGameId;
  final Set<String> completePlatforms;

  const IgdbCatalogIndex({
    this.gamesByPlatform = const {},
    this.titleKeyToGameId = const {},
    this.completePlatforms = const {},
  });

  static String titleKeyLookupKey(String platform, String titleKey) =>
      '$platform|$titleKey';

  bool isComplete(String romgiPlatform) {
    final canonical = canonicalIgdbPlatform(romgiPlatform);
    if (canonical == null) return false;
    return completePlatforms.contains(canonical);
  }

  IgdbGameRecord? recordForTitle(String romgiPlatform, String title) {
    final canonical = canonicalIgdbPlatform(romgiPlatform);
    if (canonical == null) return null;
    final key = mobyTitleKey(title);
    if (key.isEmpty) return null;
    final gameId = titleKeyToGameId[titleKeyLookupKey(canonical, key)];
    if (gameId == null) return null;
    return gamesByPlatform[canonical]?[gameId];
  }

  /// Display score (0–10) for a ROM title when sync is complete on that platform.
  double? lookupDisplayScore(String romgiPlatform, String title) {
    if (!isComplete(romgiPlatform)) return null;
    final record = recordForTitle(romgiPlatform, title);
    return igdbDisplayScoreFromRating(record?.rating);
  }

  IgdbRejectReason? rejectReason(
    IgdbGameRecord game,
    IgdbDownstreamFilters filters,
  ) {
    if (filters.mainGameOnly && game.gameType != 0) {
      return IgdbRejectReason.gameType;
    }
    if (filters.excludeUtilityNames &&
        _matchesUtilityBlocklist(game.name)) {
      return IgdbRejectReason.utilityName;
    }
    if (game.ratingCount < filters.minVotes) return IgdbRejectReason.lowVotes;
    if (game.rating < filters.minUserRating) {
      return IgdbRejectReason.lowRating;
    }
    return null;
  }

  bool passesMainList(IgdbGameRecord game, IgdbDownstreamFilters filters) =>
      rejectReason(game, filters) == null;

  bool keepRomEntry(
    String romgiPlatform,
    String title, {
    required IgdbDownstreamFilters filters,
    double? minimumDisplayScore,
  }) {
    if (!isComplete(romgiPlatform)) return true;
    final record = recordForTitle(romgiPlatform, title);
    if (record == null) return false;
    if (!passesMainList(record, filters)) return false;
    if (minimumDisplayScore != null && minimumDisplayScore > 0) {
      final display = igdbDisplayScoreFromRating(record.rating);
      if (display == null || display < minimumDisplayScore) return false;
    }
    return true;
  }

  Set<int> matchedGameIdsForPlatform(
    String igdbPlatform,
    Set<String> catalogTitleKeys,
  ) {
    final matched = <int>{};
    for (final key in catalogTitleKeys) {
      final gameId = titleKeyToGameId[titleKeyLookupKey(igdbPlatform, key)];
      if (gameId != null) matched.add(gameId);
    }
    return matched;
  }

  List<IgdbCatalogEntry> unmatchedGaps({
    required Iterable<String> igdbPlatforms,
    required Map<String, Set<String>> catalogKeysByPlatform,
    required IgdbDownstreamFilters filters,
    String? query,
  }) {
    final q = query?.trim().toLowerCase();
    final out = <IgdbGameRecord>[];
    for (final platform in igdbPlatforms) {
      final games = gamesByPlatform[platform];
      if (games == null || games.isEmpty) continue;
      final catalogKeys = catalogKeysByPlatform[platform] ?? {};
      final matched = matchedGameIdsForPlatform(platform, catalogKeys);
      for (final game in games.values) {
        if (matched.contains(game.gameId)) continue;
        if (!passesMainList(game, filters)) continue;
        if (q != null && q.isNotEmpty) {
          if (!game.name.toLowerCase().contains(q)) continue;
        }
        out.add(game);
      }
    }
    out.sort(
      (a, b) => compareIgdbRank(
        a.weighted,
        a.ratingCount,
        a.gameId,
        b.weighted,
        b.ratingCount,
        b.gameId,
      ),
    );
    return [for (final g in out) g.toCatalogEntry()];
  }

  List<IgdbCatalogEntry> discoveryFromCatalog({
    required Iterable<String> igdbPlatforms,
    required Map<String, Set<String>> catalogKeysByPlatform,
    required IgdbDownstreamFilters mainFilters,
    double discoveryMinUserRating = 80,
    int discoveryMinVotes = 5,
    String? query,
  }) {
    final q = query?.trim().toLowerCase();
    final out = <IgdbGameRecord>[];
    for (final platform in igdbPlatforms) {
      final games = gamesByPlatform[platform];
      if (games == null) continue;
      final catalogKeys = catalogKeysByPlatform[platform] ?? {};
      final matched = matchedGameIdsForPlatform(platform, catalogKeys);
      for (final game in games.values) {
        if (!matched.contains(game.gameId)) continue;
        final reason = rejectReason(game, mainFilters);
        if (reason != IgdbRejectReason.lowVotes) continue;
        if (game.ratingCount < discoveryMinVotes) continue;
        if (game.rating < discoveryMinUserRating) continue;
        if (q != null && q.isNotEmpty && !game.name.toLowerCase().contains(q)) {
          continue;
        }
        out.add(game);
      }
    }
    out.sort((a, b) {
      final rd = b.rating.compareTo(a.rating);
      if (rd != 0) return rd;
      return b.ratingCount.compareTo(a.ratingCount);
    });
    return [for (final g in out) g.toCatalogEntry()];
  }
}

bool _matchesUtilityBlocklist(String name) {
  const tokens = [
    'pokemon bank',
    'badge arcade',
    'streetpass mii plaza',
    'mii plaza',
    'ar games',
    'nintendo zone',
    'puzzle swap',
    'face raiders',
    'theme shop',
    'eshop',
    'nintendo video',
    'swapnote',
    'flipnote',
    'dsi shop',
    'system settings',
    'health & safety',
  ];
  final n = name.toLowerCase();
  return tokens.any(n.contains);
}
