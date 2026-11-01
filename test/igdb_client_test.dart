import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/igdb_client.dart';
import 'package:romgi/services/metadata/igdb_platforms.dart';
import 'package:romgi/services/metadata/igdb_ranking.dart';
import 'package:romgi/services/metadata/moby_titles.dart';

void main() {
  test('IGDB pool query uses user rating pool filters', () {
    final query = igdbPoolQuery(
      platformId: 20,
      genreIds: const [12, 5],
      offset: 500,
    );

    expect(query, contains('platforms = [20]'));
    expect(query, contains('rating_count > 0'));
    expect(query, contains('version_parent = null'));
    expect(query, contains('game_type = 0 | game_type = 3'));
    expect(query, contains('genres = (12,5)'));
    expect(query, contains('offset 500;'));
    expect(query, isNot(contains('aggregated_rating')));
  });

  test('IGDB pool games parse user rating and weighted score', () {
    final games = parseIgdbPoolGames([
      {
        'id': 1,
        'name': 'Metal Gear Solid: Peace Walker',
        'rating': 89.0,
        'rating_count': 120,
        'game_type': 0,
        'alternative_names': [
          {'name': 'Peace Walker'},
        ],
      },
    ]);

    expect(games.single.rating, 89.0);
    expect(games.single.ratingCount, 120);
    expect(
      games.single.weighted,
      closeTo(igdbWeightedRating(89, 120), 0.001),
    );
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
