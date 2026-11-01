import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/models.dart';
import 'package:romgi/services/metadata/igdb_catalog_index.dart';
import 'package:romgi/services/metadata/igdb_ranked_browse.dart';
import 'package:romgi/services/metadata/igdb_ranking.dart';

RomEntry _entry(String slug, String title, String platform) => RomEntry(
  slug: slug,
  title: title,
  platform: platform,
  regions: const [],
  links: const [],
);

void main() {
  final index = IgdbCatalogIndex(
    gamesByPlatform: {
      'nds': {
        1: IgdbGameRecord(
          platform: 'nds',
          gameId: 1,
          name: 'High',
          rating: 90,
          ratingCount: 100,
          weighted: igdbWeightedRating(90, 100),
        ),
        2: IgdbGameRecord(
          platform: 'nds',
          gameId: 2,
          name: 'Low votes',
          rating: 85,
          ratingCount: 7,
          weighted: igdbWeightedRating(85, 7),
        ),
      },
    },
    titleKeyToGameId: {
      'nds|high game': 1,
      'nds|low votes': 2,
    },
    completePlatforms: {'nds'},
  );

  test('ranks before floor split and keeps rank on pruned rows', () {
    const filters = IgdbDownstreamFilters(minUserRating: 60, minVotes: 10);
    final result = buildIgdbRankedBrowse(
      entries: [
        _entry('a', 'Low votes', 'nds'),
        _entry('b', 'High game', 'nds'),
      ],
      index: index,
      filters: filters,
    );

    expect(result.main.map((e) => e.slug).toList(), ['b']);
    expect(result.pruned.map((e) => e.slug).toList(), ['a']);
    expect(result.ranks['b'], 1);
    expect(result.ranks['a'], 2);
  });
}
