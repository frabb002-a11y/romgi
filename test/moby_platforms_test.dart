import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/services/metadata/moby_platforms.dart';

void main() {
  test('the walk list is the Romgi catalog, with its own 3DS pages', () {
    expect(mobyPlatformSlugs.containsKey('xboxsx'), isFalse);
    expect(mobyPlatformSlugs.containsKey('switch'), isFalse);
    expect(mobyPlatformSlugs['3ds'], '3ds');
    expect(mobyPlatformSlugs['n3ds'], 'new-nintendo-3ds');
    expect(mobyPlatformSlugs['psv'], 'ps-vita');
    expect(mobyPlatformSlugs.length, 50);

    expect(canonicalMobyPlatform('n3ds'), 'n3ds');
    expect(canonicalMobyPlatform('3ds'), '3ds');
    expect(canonicalMobyPlatform('smd'), 'smd');
    expect(canonicalMobyPlatform('genesis'), 'smd');
    expect(canonicalMobyPlatform('xboxsx'), isNull);
  });
}
