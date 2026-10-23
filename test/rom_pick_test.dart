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
    expect(titleExcluded('FIFA 14', ['fifa']), isTrue);
    expect(titleExcluded('FIFA Soccer 96 (USA)', ['fifa']), isTrue);
    expect(titleExcluded('Fifantic Adventure', ['fifa']), isFalse);
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

  test('1G1R keeps Peace Walker v2.00 over v1.01', () {
    final picked = pickOnePerGame([
      game('Peace Walker (v1.01) (USA)', regions: ['USA']),
      game('Peace Walker (v2.00) (USA)', regions: ['USA']),
    ]);

    expect(picked.single.title, 'Peace Walker (v2.00) (USA)');
  });

  test('a USA release still beats a higher version from Japan', () {
    final picked = pickOnePerGame([
      game('Peace Walker (v1.01) (USA)', regions: ['USA']),
      game('Peace Walker (v2.00) (Japan)', regions: ['Japan']),
    ]);

    expect(picked.single.title, 'Peace Walker (v1.01) (USA)');
  });

  test('a US beta loses to a clean European release', () {
    final visible = [
      game('Game (USA) (Beta)', regions: ['USA']),
      game('Game (Europe)', regions: ['Europe']),
    ].where((entry) => !titleExcluded(entry.title, defaultExcludeTerms));

    final picked = pickOnePerGame(visible.toList());
    expect(picked.single.title, 'Game (Europe)');
  });

  test('global counts as USA, and discs stay separate', () {
    final picked = pickOnePerGame([
      game('Game (Japan)', regions: ['Japan']),
      game('Game (Global)', regions: ['Global']),
      game('Game (Disc 1) (USA)', regions: ['USA']),
      game('Game (Disc 2) (Europe)', regions: ['Europe']),
    ]);

    expect(picked.map((entry) => entry.title), [
      'Game (Disc 1) (USA)',
      'Game (Disc 2) (Europe)',
      'Game (Global)',
    ]);
  });

  test('a release outside USA, Europe, and Japan is not the 1G1R pick', () {
    final picked = pickOnePerGame([
      game('Only Korea (Korea)', regions: ['Korea']),
      game('Mixed (Korea)', regions: ['Korea']),
      game('Mixed (Japan)', regions: ['Japan']),
    ]);

    expect(picked.map((entry) => entry.title), ['Mixed (Japan)']);
  });
}
