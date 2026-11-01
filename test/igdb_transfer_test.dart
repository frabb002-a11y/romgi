import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/igdb_transfer.dart';

void main() {
  test('v2 catalog round-trips and rejects other files', () {
    final encoded = encodeIgdbTransfer(
      const IgdbTransfer(
        games: [
          IgdbGameRow(
            platform: 'snes',
            gameId: 12,
            name: 'Chrono Trigger',
            rating: 91,
            ratingCount: 200,
            weighted: 90.5,
          ),
        ],
        titleKeys: [
          IgdbTitleKeyRow(
            platform: 'snes',
            titleKey: 'chrono trigger',
            gameId: 12,
          ),
        ],
        sync: [
          IgdbSyncRow(
            platform: 'snes',
            pageOffset: 500,
            complete: true,
            cutoff: 0,
          ),
        ],
      ),
    );

    final parsed = parseIgdbTransfer(encoded);
    expect(parsed.games.single.name, 'Chrono Trigger');
    expect(parsed.titleKeys.single.titleKey, 'chrono trigger');
    expect(parsed.sync.single.complete, isTrue);
    expect(parsed.sync.single.pageOffset, 500);

    expect(
      () => parseIgdbTransfer(
        '{"kind":"romgi-moby","version":1,"scores":[],"sync":[]}',
      ),
      throwsA(isA<IgdbTransferException>()),
    );
  });

  test('v1 score lists still import', () {
    final parsed = parseIgdbTransfer('''
{
  "kind": "romgi-igdb",
  "version": 1,
  "scores": [
    {"platform": "nes", "title_key": "metroid", "score": 88, "game_id": 3}
  ],
  "sync": []
}
''');
    expect(parsed.games.single.gameId, 3);
    expect(parsed.titleKeys.single.titleKey, 'metroid');
  });

  test('import keeps a finished pull and the further unfinished page', () {
    final merged = mergeIgdbSync(
      local: const [
        IgdbSyncRow(
          platform: 'nes',
          pageOffset: 0,
          complete: false,
          cutoff: 0,
        ),
        IgdbSyncRow(
          platform: 'snes',
          pageOffset: 500,
          complete: true,
          cutoff: 0,
        ),
      ],
      imported: const [
        IgdbSyncRow(
          platform: 'nes',
          pageOffset: 500,
          complete: true,
          cutoff: 0,
        ),
        IgdbSyncRow(
          platform: 'snes',
          pageOffset: 0,
          complete: true,
          cutoff: 0,
        ),
        IgdbSyncRow(
          platform: 'gba',
          pageOffset: 500,
          complete: false,
          cutoff: 0,
        ),
      ],
    );

    final byPlatform = {for (final row in merged) row.platform: row};
    expect(byPlatform['nes']!.complete, isTrue);
    expect(byPlatform['nes']!.pageOffset, 500);
    expect(byPlatform['snes']!.complete, isTrue);
    expect(byPlatform['gba']!.pageOffset, 500);
    expect(byPlatform['gba']!.complete, isFalse);
  });
}
