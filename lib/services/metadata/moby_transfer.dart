import 'dart:convert';

/// A MobyGames score list that can move between devices.
/// Import merges into the database already on the device.
const mobyTransferKind = 'romgi-moby';
const mobyTransferVersion = 1;

class MobyScoreRow {
  final String platform;
  final String titleKey;
  final double score;
  final int gameId;

  const MobyScoreRow({
    required this.platform,
    required this.titleKey,
    required this.score,
    required this.gameId,
  });

  Map<String, Object?> toDbRow() => {
    'platform': platform,
    'title_key': titleKey,
    'score': score,
    'game_id': gameId,
  };
}

class MobySyncRow {
  final String platform;
  final int pageOffset;
  final bool complete;
  final double cutoff;

  const MobySyncRow({
    required this.platform,
    required this.pageOffset,
    required this.complete,
    required this.cutoff,
  });
}

class MobyTransfer {
  final List<MobyScoreRow> scores;
  final List<MobySyncRow> sync;

  const MobyTransfer({required this.scores, required this.sync});
}

class MobyTransferException implements Exception {
  final String message;

  const MobyTransferException(this.message);

  @override
  String toString() => message;
}

String encodeMobyTransfer(MobyTransfer transfer) {
  return const JsonEncoder.withIndent('  ').convert({
    'kind': mobyTransferKind,
    'version': mobyTransferVersion,
    'scores': [
      for (final row in transfer.scores)
        {
          'platform': row.platform,
          'title_key': row.titleKey,
          'score': row.score,
          'game_id': row.gameId,
        },
    ],
    'sync': [
      for (final row in transfer.sync)
        {
          'platform': row.platform,
          'page_offset': row.pageOffset,
          'complete': row.complete,
          'cutoff': row.cutoff,
        },
    ],
  });
}

MobyTransfer parseMobyTransfer(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const MobyTransferException('That file is not a Romgi score list.');
  }
  if (decoded is! Map) {
    throw const MobyTransferException('That file is not a Romgi score list.');
  }
  final json = decoded.cast<Object?, Object?>();
  if (json['kind'] != mobyTransferKind) {
    throw const MobyTransferException('That file is not a Romgi score list.');
  }
  final version = json['version'];
  if (version is! int || version != mobyTransferVersion) {
    throw const MobyTransferException(
      'This Romgi build cannot read that score list.',
    );
  }
  return MobyTransfer(
    scores: _scores(json['scores']),
    sync: _sync(json['sync']),
  );
}

/// Keeps a finished walk. A higher page wins when both walks are unfinished.
/// The higher score for a title is applied separately by the database.
List<MobySyncRow> mergeMobySync({
  required Iterable<MobySyncRow> local,
  required Iterable<MobySyncRow> imported,
}) {
  final byPlatform = {for (final row in local) row.platform: row};
  for (final row in imported) {
    final existing = byPlatform[row.platform];
    byPlatform[row.platform] = existing == null
        ? row
        : _mergeSync(existing, row);
  }
  final merged = byPlatform.values.toList()
    ..sort((a, b) => a.platform.compareTo(b.platform));
  return merged;
}

MobySyncRow _mergeSync(MobySyncRow local, MobySyncRow imported) {
  final complete = local.complete || imported.complete;
  final pageOffset = imported.pageOffset > local.pageOffset
      ? imported.pageOffset
      : local.pageOffset;
  return MobySyncRow(
    platform: local.platform,
    pageOffset: pageOffset,
    complete: complete,
    cutoff: _mergedCutoff(local, imported),
  );
}

double _mergedCutoff(MobySyncRow local, MobySyncRow imported) {
  if (imported.complete && !local.complete) return imported.cutoff;
  if (local.complete && !imported.complete) return local.cutoff;
  if (local.complete && imported.complete) {
    return imported.cutoff < local.cutoff ? imported.cutoff : local.cutoff;
  }
  return imported.pageOffset >= local.pageOffset
      ? imported.cutoff
      : local.cutoff;
}

List<MobyScoreRow> _scores(Object? raw) {
  if (raw is! List) {
    throw const MobyTransferException('That file is not a Romgi score list.');
  }
  final rows = <MobyScoreRow>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const MobyTransferException('That file is not a Romgi score list.');
    }
    final json = item.cast<Object?, Object?>();
    final platform = json['platform'];
    final titleKey = json['title_key'];
    final score = json['score'];
    final gameId = json['game_id'];
    if (platform is! String ||
        platform.isEmpty ||
        titleKey is! String ||
        titleKey.isEmpty ||
        score is! num ||
        gameId is! int) {
      throw const MobyTransferException('That file is not a Romgi score list.');
    }
    rows.add(
      MobyScoreRow(
        platform: platform,
        titleKey: titleKey,
        score: score.toDouble(),
        gameId: gameId,
      ),
    );
  }
  return rows;
}

List<MobySyncRow> _sync(Object? raw) {
  if (raw is! List) {
    throw const MobyTransferException('That file is not a Romgi score list.');
  }
  final rows = <MobySyncRow>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const MobyTransferException('That file is not a Romgi score list.');
    }
    final json = item.cast<Object?, Object?>();
    final platform = json['platform'];
    final pageOffset = json['page_offset'];
    final complete = json['complete'];
    final cutoff = json['cutoff'];
    if (platform is! String ||
        platform.isEmpty ||
        pageOffset is! int ||
        complete is! bool ||
        cutoff is! num) {
      throw const MobyTransferException('That file is not a Romgi score list.');
    }
    rows.add(
      MobySyncRow(
        platform: platform,
        pageOffset: pageOffset,
        complete: complete,
        cutoff: cutoff.toDouble(),
      ),
    );
  }
  return rows;
}
