import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/igdb_client.dart';
import 'package:romgi/services/metadata/igdb_platforms.dart';
import 'package:romgi/services/metadata/moby_titles.dart';

void main() {
  test('IGDB setup query keeps main games above the cutoff', () {
    final query = igdbGamesQuery(
      platformId: 20,
      genreIds: const [12, 5],
      minimumScore: 70,
      offset: 500,
    );

    expect(query, contains('platforms = (20)'));
    expect(query, contains('category = 0'));
    expect(query, contains('aggregated_rating >= 70'));
    expect(query, contains('genres = (12,5)'));
    expect(query, contains('offset 500;'));
  });

  test('IGDB games keep the critic score and alternative names', () {
    final games = parseIgdbGames([
      {
        'id': 1,
        'name': 'Metal Gear Solid: Peace Walker',
        'aggregated_rating': 89.4,
        'alternative_names': [
          {'name': 'Peace Walker'},
        ],
      },
    ]);

    expect(games.single.score, 89.4);
    expect(games.single.alternativeNames, ['Peace Walker']);
    expect(mobyTitleKey(games.single.alternativeNames.single), 'peace walker');
  });

  test('New 3DS is its own IGDB platform and Xbox Series is not in the catalog', () {
    expect(igdbPlatformIds['n3ds'], 137);
    expect(igdbPlatformIds['3ds'], 37);
    expect(igdbPlatformIds.containsKey('xboxsx'), isFalse);
    expect(canonicalIgdbPlatform('n3ds'), 'n3ds');
    expect(canonicalIgdbPlatform('genesis'), 'smd');
    expect(canonicalIgdbPlatform('xboxsx'), isNull);
  });
}
