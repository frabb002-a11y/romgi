import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/igdb_transfer.dart';

void main() {
  test('a score list round-trips and rejects other files', () {
    final encoded = encodeIgdbTransfer(
      const IgdbTransfer(
        scores: [
          IgdbScoreRow(
            platform: 'snes',
            titleKey: 'chrono trigger',
            score: 91,
            gameId: 12,
          ),
        ],
        sync: [
          IgdbSyncRow(
            platform: 'snes',
            pageOffset: 500,
            complete: true,
            cutoff: 70,
          ),
        ],
      ),
    );

    final parsed = parseIgdbTransfer(encoded);
    expect(parsed.scores.single.titleKey, 'chrono trigger');
    expect(parsed.scores.single.score, 91);
    expect(parsed.sync.single.complete, isTrue);
    expect(parsed.sync.single.pageOffset, 500);

    expect(
      () => parseIgdbTransfer(
        '{"kind":"romgi-moby","version":1,"scores":[],"sync":[]}',
      ),
      throwsA(isA<IgdbTransferException>()),
    );
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
          cutoff: 80,
        ),
      ],
      imported: const [
        IgdbSyncRow(
          platform: 'nes',
          pageOffset: 500,
          complete: true,
          cutoff: 70,
        ),
        IgdbSyncRow(
          platform: 'snes',
          pageOffset: 0,
          complete: true,
          cutoff: 60,
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
    expect(byPlatform['nes']!.cutoff, 70);
    expect(byPlatform['snes']!.complete, isTrue);
    expect(byPlatform['snes']!.cutoff, 60);
    expect(byPlatform['gba']!.pageOffset, 500);
    expect(byPlatform['gba']!.complete, isFalse);
  });
}
