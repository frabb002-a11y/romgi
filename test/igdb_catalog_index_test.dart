import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/igdb_catalog_index.dart';
import 'package:romgi/services/metadata/igdb_ranking.dart';

void main() {
  final index = IgdbCatalogIndex(
    gamesByPlatform: {
      'nds': {
        1: IgdbGameRecord(
          platform: 'nds',
          gameId: 1,
          name: 'Matched Game',
          rating: 85,
          ratingCount: 50,
          weighted: igdbWeightedRating(85, 50),
        ),
        2: IgdbGameRecord(
          platform: 'nds',
          gameId: 2,
          name: 'Gap Game',
          rating: 90,
          ratingCount: 40,
          weighted: igdbWeightedRating(90, 40),
        ),
        3: IgdbGameRecord(
          platform: 'nds',
          gameId: 3,
          name: 'Low Vote Gem',
          rating: 82,
          ratingCount: 7,
          weighted: igdbWeightedRating(82, 7),
        ),
      },
    },
    titleKeyToGameId: {
      'nds|matched game': 1,
      'nds|low vote gem': 3,
    },
    completePlatforms: {'nds'},
  );

  test('unmatched gaps exclude catalog matches', () {
    final gaps = index.unmatchedGaps(
      igdbPlatforms: ['nds'],
      catalogKeysByPlatform: {
        'nds': {'matched game'},
      },
      filters: const IgdbDownstreamFilters(minUserRating: 60, minVotes: 10),
    );
    expect(gaps.map((g) => g.gameId).toList(), [2]);
  });

  test('discovery keeps low-vote matched titles', () {
    final gems = index.discoveryFromCatalog(
      igdbPlatforms: ['nds'],
      catalogKeysByPlatform: {
        'nds': {'low vote gem'},
      },
      mainFilters: const IgdbDownstreamFilters(minUserRating: 60, minVotes: 10),
      discoveryMinUserRating: 80,
    );
    expect(gems.single.gameId, 3);
  });
}
