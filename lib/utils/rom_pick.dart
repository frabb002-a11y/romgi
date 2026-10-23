import '../models/rom_entry.dart';
import '../services/metadata/moby_titles.dart';

/// Starting hide list. A term matches a whole word inside () [] or {}.
const defaultExcludeTerms = <String>[
  'beta',
  'demo',
  'proto',
  'sample',
  'kiosk',
  'minis',
  'taikenban',
  'promo',
];

final _tagPattern = RegExp(r'\(([^)]*)\)|\[([^\]]*)\]|\{([^}]*)\}');
final _discPattern = RegExp(r'disc\s+(\d+)', caseSensitive: false);
final _revPattern = RegExp(r'rev\s+([0-9]+|[a-z])', caseSensitive: false);

/// Hides a title when any term is its own word inside a tag.
/// `beta` matches `(Beta)` and `(Beta 1)`, and leaves Bethesda alone.
bool titleExcluded(String title, Iterable<String> terms) {
  final tags = _tags(title);
  if (tags.isEmpty) return false;
  for (final term in terms) {
    final needle = term
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (needle.isEmpty) continue;
    for (final tag in tags) {
      final collapsed = tag
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      if (collapsed.isEmpty) continue;
      final words = collapsed.split(' ');
      if (words.contains(needle)) return true;
      if (needle.contains(' ') && ' $collapsed '.contains(' $needle ')) {
        return true;
      }
    }
  }
  return false;
}

/// USA, then Europe, then Japan. Global counts as USA.
/// Null when the release is none of those. The browse region filter
/// already decides whether those other releases are in the list.
int? releaseRegionRank(RomEntry entry) {
  int? best;
  void consider(String raw) {
    final rank = _regionRank(raw);
    if (rank == null) return;
    if (best == null || rank < best!) best = rank;
  }

  for (final region in entry.regions) {
    consider(region);
  }
  for (final tag in _tags(entry.title)) {
    for (final part in tag.split(RegExp(r'\s*[,/+]\s*'))) {
      consider(part);
    }
  }
  return best;
}

/// `(Rev 2)` and `(Rev B)` outrank `(Rev 1)` and `(Rev A)`. No revision is 0.
int revisionNumber(String title) {
  var best = 0;
  for (final tag in _tags(title)) {
    final match = _revPattern.firstMatch(tag);
    if (match == null) continue;
    final token = match.group(1)!.toLowerCase();
    final value = int.tryParse(token) ?? (token.codeUnitAt(0) - 96);
    if (value > best) best = value;
  }
  return best;
}

/// One row per game. Disc 1 and disc 2 stay separate.
/// Call this after [titleExcluded], so a US beta cannot beat a clean EU release.
List<RomEntry> pickOnePerGame(List<RomEntry> entries) {
  final groups = <String, List<RomEntry>>{};
  for (final entry in entries) {
    groups.putIfAbsent(_gameKey(entry), () => []).add(entry);
  }
  final picked = <RomEntry>[];
  for (final group in groups.values) {
    final ranked = [
      for (final entry in group)
        if (releaseRegionRank(entry) != null) entry,
    ];
    if (ranked.isEmpty) continue;
    ranked.sort((a, b) {
      final region = releaseRegionRank(a)!.compareTo(releaseRegionRank(b)!);
      if (region != 0) return region;
      final revision = revisionNumber(
        b.title,
      ).compareTo(revisionNumber(a.title));
      if (revision != 0) return revision;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    picked.add(ranked.first);
  }
  picked.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return picked;
}

List<String> normalizeExcludeTerms(Iterable<String> terms) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in terms) {
    final term = raw.trim().toLowerCase();
    if (term.isEmpty || !seen.add(term)) continue;
    out.add(term);
  }
  return out;
}

String _gameKey(RomEntry entry) {
  final disc =
      _discPattern.firstMatch(_tags(entry.title).join(' '))?.group(1) ?? '';
  return '${entry.platform}|${mobyTitleKey(entry.title)}|$disc';
}

List<String> _tags(String title) {
  return [
    for (final match in _tagPattern.allMatches(title))
      match.group(1) ?? match.group(2) ?? match.group(3) ?? '',
  ];
}

int? _regionRank(String raw) {
  final name = raw.toLowerCase().trim();
  return switch (name) {
    'us' ||
    'usa' ||
    'u' ||
    'america' ||
    'ntsc-u' ||
    'world' ||
    'wld' ||
    'global' => 0,
    'eu' || 'europe' || 'eur' || 'pal' => 1,
    'jp' || 'japan' || 'jpn' || 'ntsc-j' => 2,
    _ => null,
  };
}
