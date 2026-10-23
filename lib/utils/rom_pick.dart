import '../models/rom_entry.dart';
import '../services/metadata/moby_titles.dart';

/// Starting hide list. A term matches a whole word anywhere in the title.
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
final _versionPattern = RegExp(r'v(\d+(?:\.\d+)*)', caseSensitive: false);

/// Hides a title when any term is its own word, inside tags or not.
/// `fifa` matches `FIFA 14`. `beta` matches `(Beta)` and `(Beta 1)`,
/// and leaves Bethesda alone.
bool titleExcluded(String title, Iterable<String> terms) {
  final haystack = ' ${_words(title).join(' ')} ';
  if (haystack.trim().isEmpty) return false;
  for (final term in terms) {
    final needle = _words(term).join(' ');
    if (needle.isEmpty) continue;
    if (haystack.contains(' $needle ')) return true;
  }
  return false;
}

List<String> _words(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList();
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

/// Higher wins. `(v2.00)` beats `(v1.01)`. `(Rev 2)` and `(Rev B)` beat
/// `(Rev 1)` and `(Rev A)`. A release with no version ranks lowest.
List<int> revisionRank(String title) {
  var best = const <int>[];
  for (final tag in _tags(title)) {
    final rank = _tagRevision(tag);
    if (rank == null) continue;
    if (_compareRevision(rank, best) > 0) best = rank;
  }
  return best;
}

List<int>? _tagRevision(String tag) {
  final rev = _revPattern.firstMatch(tag);
  if (rev != null) {
    final token = rev.group(1)!.toLowerCase();
    return [int.tryParse(token) ?? (token.codeUnitAt(0) - 96)];
  }
  final version = _versionPattern.firstMatch(tag);
  if (version == null) return null;
  return [
    for (final part in version.group(1)!.split('.')) int.tryParse(part) ?? 0,
  ];
}

int _compareRevision(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
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
      final revision = _compareRevision(
        revisionRank(b.title),
        revisionRank(a.title),
      );
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
