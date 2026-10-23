import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/utils/archive_files.dart';

void main() {
  test('a zip tagged iso is ghosted as an iso', () {
    const filename =
        'Ace Combat X - Skies of Deception (USA).zip';
    expect(
      canGhostRelease(filename: filename, format: 'iso'),
      isTrue,
    );
    expect(
      ghostFilename(filename: filename, format: 'iso'),
      'Ace Combat X - Skies of Deception (USA).iso',
    );
  });

  test('an iso tag is kept and an archive tag is refused', () {
    expect(
      ghostFilename(
        filename: 'Game.iso',
        format: 'ISO',
      ),
      'Game.iso',
    );
    expect(
      canGhostRelease(filename: 'Game.zip', format: 'zip'),
      isFalse,
    );
    expect(
      canGhostRelease(filename: 'Game.nds', format: ''),
      isTrue,
    );
  });
}
