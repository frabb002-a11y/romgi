import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/batch_selection.dart';
import 'package:romgi/services/metadata/moby_page.dart';
import 'package:romgi/services/metadata/moby_titles.dart';
import 'package:romgi/utils/archive_files.dart';

void main() {
  test('page parse keeps scored rows and stops at the cutoff', () {
    const html = '''
      <tr><td><a href="/game/1/alpha/">Alpha</a><span class="mobyscore">8.4</span></td></tr>
      <tr><td><a href="/game/2/beta/">Beta &amp; Co</a><span class="mobyscore">7.0</span></td></tr>
      <tr><td><a href="/game/3/gamma/">Gamma</a><span class="mobyscore">6.5</span></td></tr>
    ''';

    final parsed = parseMobyPlatformPage(html, cutoff: 7);
    expect(parsed.stopped, isTrue);
    expect(parsed.games.map((game) => game.title), ['Alpha', 'Beta & Co']);
    expect(parsed.games.first.gameId, 1);
  });

  test('page parse stops at the first unscored row when cutoff is 0', () {
    const html = '''
      <tr><td><a href="/game/4/delta/">Delta</a><span class="mobyscore">1.2</span></td></tr>
      <tr><td><a href="/game/5/echo/">Echo</a></td></tr>
      <tr><td><a href="/game/6/foxtrot/">Foxtrot</a><span class="mobyscore">9.0</span></td></tr>
    ''';

    final parsed = parseMobyPlatformPage(html, cutoff: 0);
    expect(parsed.stopped, isTrue);
    expect(parsed.games.map((game) => game.title), ['Delta']);
  });

  test('title key drops region tags and a leading the', () {
    expect(mobyTitleKey('The Legend of Zelda (USA) [!]'), 'legend of zelda');
  });

  test('the listing pager is the one after the scores', () {
    const html = '''
      <tr><td><a href="/game/1/alpha/">Alpha</a>
        <span class="mobyscore">8.4</span></td></tr>
      [ Page 2 of 49 ]
      Related [ Page 1 of 3 ]
    ''';

    final pager = mobyListingPager(html);
    expect(pager?.current, 2);
    expect(pager?.count, 49);
    expect(pager?.isLast, isFalse);
    expect(
      mobyPageRepeats({1, 2}, [1]),
      isTrue,
    );
    expect(mobyPageRepeats({1}, [1, 2]), isFalse);
  });

  test('a Cloudflare check page counts as blocked', () {
    expect(
      mobyPageLooksBlocked('<html><title>Just a moment...</title></html>'),
      isTrue,
    );
    expect(
      mobyPageLooksBlocked('<a href="/game/1/alpha/">Alpha</a>'),
      isFalse,
    );
  });

  test('archives cannot be ghosted and a normal rom filename can', () {
    expect(canGhostFilename('Game.nds'), isTrue);
    expect(canGhostFilename('Game.iso'), isTrue);
    expect(canGhostFilename('Game.zip'), isFalse);
    expect(canGhostFilename('Game.7z'), isFalse);
    expect(canGhostFilename('readme'), isFalse);
  });

  test('select all counts the full result minus exclusions', () {
    final selection = BatchSelection.empty.start('a').selectAll().toggle('b');
    expect(selection.count(10), 9);
    expect(selection.contains('a'), isTrue);
    expect(selection.contains('b'), isFalse);
  });
}
