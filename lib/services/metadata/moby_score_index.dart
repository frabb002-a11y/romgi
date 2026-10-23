import 'moby_platforms.dart';
import 'moby_titles.dart';

class MobyScoreIndex {
  final Map<String, double> scores;
  final Set<String> completePlatforms;

  const MobyScoreIndex({
    this.scores = const {},
    this.completePlatforms = const {},
  });

  static String keyFor(String canonicalPlatform, String title) =>
      '$canonicalPlatform|${mobyTitleKey(title)}';

  bool isComplete(String romgiPlatform) {
    final canonical = canonicalMobyPlatform(romgiPlatform);
    if (canonical == null) return false;
    return completePlatforms.contains(canonical);
  }

  /// Null when the platform walk has not finished, or the title has no score.
  double? lookup(String romgiPlatform, String title) {
    final canonical = canonicalMobyPlatform(romgiPlatform);
    if (canonical == null || !completePlatforms.contains(canonical)) {
      return null;
    }
    return scores[keyFor(canonical, title)];
  }

  bool keep(String romgiPlatform, String title, {double? minimum}) {
    if (!isComplete(romgiPlatform)) return true;
    final score = lookup(romgiPlatform, title);
    if (score == null) return false;
    if (minimum != null && score < minimum) return false;
    return true;
  }
}
