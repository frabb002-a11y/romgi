import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/moby_transfer.dart';

void main() {
  test('a score list round-trips and rejects other files', () {
    final encoded = encodeMobyTransfer(
      const MobyTransfer(
        scores: [
          MobyScoreRow(
            platform: 'snes',
            titleKey: 'chrono trigger',
            score: 9.1,
            gameId: 12,
          ),
        ],
        sync: [
          MobySyncRow(
            platform: 'snes',
            pageOffset: 3,
            complete: true,
            cutoff: 7,
          ),
        ],
      ),
    );

    final parsed = parseMobyTransfer(encoded);
    expect(parsed.scores.single.titleKey, 'chrono trigger');
    expect(parsed.scores.single.score, 9.1);
    expect(parsed.sync.single.complete, isTrue);
    expect(parsed.sync.single.pageOffset, 3);

    expect(
      () => parseMobyTransfer('{"kind":"other","version":1,"scores":[],"sync":[]}'),
      throwsA(isA<MobyTransferException>()),
    );
  });

  test('import keeps a finished walk and the further unfinished page', () {
    final merged = mergeMobySync(
      local: const [
        MobySyncRow(
          platform: 'nes',
          pageOffset: 1,
          complete: false,
          cutoff: 0,
        ),
        MobySyncRow(
          platform: 'snes',
          pageOffset: 4,
          complete: true,
          cutoff: 8,
        ),
      ],
      imported: const [
        MobySyncRow(
          platform: 'nes',
          pageOffset: 6,
          complete: true,
          cutoff: 7,
        ),
        MobySyncRow(
          platform: 'snes',
          pageOffset: 2,
          complete: true,
          cutoff: 6,
        ),
        MobySyncRow(
          platform: 'gba',
          pageOffset: 2,
          complete: false,
          cutoff: 0,
        ),
      ],
    );

    final byPlatform = {for (final row in merged) row.platform: row};
    expect(byPlatform['nes']!.complete, isTrue);
    expect(byPlatform['nes']!.pageOffset, 6);
    expect(byPlatform['nes']!.cutoff, 7);
    expect(byPlatform['snes']!.complete, isTrue);
    expect(byPlatform['snes']!.cutoff, 6);
    expect(byPlatform['gba']!.pageOffset, 2);
    expect(byPlatform['gba']!.complete, isFalse);
  });
}
