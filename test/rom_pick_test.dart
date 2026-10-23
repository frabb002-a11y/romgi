import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/rom_entry.dart';
import 'package:romgi/utils/rom_pick.dart';

RomEntry game(
  String title, {
  String platform = 'nds',
  List<String> regions = const [],
}) {
  return RomEntry(
    slug: title,
    title: title,
    platform: platform,
    regions: regions,
    links: const [],
  );
}

void main() {
  test('exclude terms match a whole word inside a tag', () {
    expect(titleExcluded('Game (Beta)', defaultExcludeTerms), isTrue);
    expect(titleExcluded('Game (Beta 1)', defaultExcludeTerms), isTrue);
    expect(titleExcluded('Game (Minis)', defaultExcludeTerms), isTrue);
    expect(titleExcluded('Game [Proto]', defaultExcludeTerms), isTrue);
    expect(
      titleExcluded('Bethesda Pinball (USA)', defaultExcludeTerms),
      isFalse,
    );
    expect(titleExcluded('Alphabet (USA)', ['beta']), isFalse);
  });

  test('1G1R keeps USA over Europe over Japan, then the higher revision', () {
    final picked = pickOnePerGame([
      game('Game (Japan)', regions: ['Japan']),
      game('Game (Europe)', regions: ['Europe']),
      game('Game (USA) (Rev 1)', regions: ['USA']),
      game('Game (USA) (Rev 2)', regions: ['USA']),
    ]);

    expect(picked.map((entry) => entry.title), ['Game (USA) (Rev 2)']);
  });

  test('a US beta loses to a clean European release', () {
    final visible = [
      game('Game (USA) (Beta)', regions: ['USA']),
      game('Game (Europe)', regions: ['Europe']),
    ].where((entry) => !titleExcluded(entry.title, defaultExcludeTerms));

    final picked = pickOnePerGame(visible.toList());
    expect(picked.single.title, 'Game (Europe)');
  });

  test('world ranks with the US, and discs stay separate', () {
    final picked = pickOnePerGame([
      game('Game (Japan)', regions: ['Japan']),
      game('Game (World)', regions: ['World']),
      game('Game (Disc 1) (USA)', regions: ['USA']),
      game('Game (Disc 2) (Europe)', regions: ['Europe']),
    ]);

    expect(picked.map((entry) => entry.title), [
      'Game (Disc 1) (USA)',
      'Game (Disc 2) (Europe)',
      'Game (World)',
    ]);
  });
}
