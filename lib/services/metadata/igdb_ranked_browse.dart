import '../../models/models.dart';
import 'igdb_catalog_index.dart';
import 'igdb_ranking.dart';

class IgdbRankedBrowseResult {
  final List<RomEntry> main;
  final List<RomEntry> pruned;
  final Map<String, int> ranks;

  const IgdbRankedBrowseResult({
    required this.main,
    required this.pruned,
    required this.ranks,
  });
}

/// Sort matched ROMs by IGDB weighted rank; assign fixed ranks before floor split.
IgdbRankedBrowseResult buildIgdbRankedBrowse({
  required List<RomEntry> entries,
  required IgdbCatalogIndex index,
  required IgdbDownstreamFilters filters,
  double? minimumDisplayScore,
}) {
  final matched = <({RomEntry entry, IgdbGameRecord record})>[];
  for (final entry in entries) {
    if (!index.isComplete(entry.platform)) continue;
    final record = index.recordForTitle(entry.platform, entry.title);
    if (record == null) continue;
    matched.add((entry: entry, record: record));
  }

  matched.sort(
    (a, b) => compareIgdbRank(
      a.record.weighted,
      a.record.ratingCount,
      a.record.gameId,
      b.record.weighted,
      b.record.ratingCount,
      b.record.gameId,
    ),
  );

  final ranks = <String, int>{};
  for (var i = 0; i < matched.length; i++) {
    ranks[matched[i].entry.slug] = i + 1;
  }

  final main = <RomEntry>[];
  final pruned = <RomEntry>[];
  for (final row in matched) {
    final passes = index.keepRomEntry(
      row.entry.platform,
      row.entry.title,
      filters: filters,
      minimumDisplayScore: minimumDisplayScore,
    );
    if (passes) {
      main.add(row.entry);
    } else {
      pruned.add(row.entry);
    }
  }

  return IgdbRankedBrowseResult(
    main: main,
    pruned: pruned,
    ranks: ranks,
  );
}

bool igdbRankedBrowseAvailable(
  IgdbCatalogIndex index, {
  List<String>? romgiPlatforms,
}) {
  if (romgiPlatforms == null || romgiPlatforms.isEmpty) {
    return index.completePlatforms.isNotEmpty;
  }
  for (final platform in romgiPlatforms) {
    if (index.isComplete(platform)) return true;
  }
  return false;
}
