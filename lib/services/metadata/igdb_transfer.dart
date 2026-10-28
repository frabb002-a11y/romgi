import 'dart:convert';

/// An IGDB score list that can move between devices.
/// Import merges into the database already on the device.
const igdbTransferKind = 'romgi-igdb';
const igdbTransferVersion = 1;

class IgdbScoreRow {
  final String platform;
  final String titleKey;
  final double score;
  final int gameId;

  const IgdbScoreRow({
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

class IgdbSyncRow {
  final String platform;
  final int pageOffset;
  final bool complete;
  final double cutoff;

  const IgdbSyncRow({
    required this.platform,
    required this.pageOffset,
    required this.complete,
    required this.cutoff,
  });
}

class IgdbTransfer {
  final List<IgdbScoreRow> scores;
  final List<IgdbSyncRow> sync;

  const IgdbTransfer({required this.scores, required this.sync});
}

class IgdbTransferException implements Exception {
  final String message;

  const IgdbTransferException(this.message);

  @override
  String toString() => message;
}

String encodeIgdbTransfer(IgdbTransfer transfer) {
  return const JsonEncoder.withIndent('  ').convert({
    'kind': igdbTransferKind,
    'version': igdbTransferVersion,
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

IgdbTransfer parseIgdbTransfer(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  if (decoded is! Map) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final json = decoded.cast<Object?, Object?>();
  if (json['kind'] != igdbTransferKind) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final version = json['version'];
  if (version is! int || version != igdbTransferVersion) {
    throw const IgdbTransferException(
      'This Romgi build cannot read that score list.',
    );
  }
  return IgdbTransfer(
    scores: _scores(json['scores']),
    sync: _sync(json['sync']),
  );
}

/// Keeps a finished pull. A higher offset wins when both pulls are unfinished.
/// The higher score for a title is applied separately by the database.
List<IgdbSyncRow> mergeIgdbSync({
  required Iterable<IgdbSyncRow> local,
  required Iterable<IgdbSyncRow> imported,
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

IgdbSyncRow _mergeSync(IgdbSyncRow local, IgdbSyncRow imported) {
  final complete = local.complete || imported.complete;
  final pageOffset = imported.pageOffset > local.pageOffset
      ? imported.pageOffset
      : local.pageOffset;
  return IgdbSyncRow(
    platform: local.platform,
    pageOffset: pageOffset,
    complete: complete,
    cutoff: _mergedCutoff(local, imported),
  );
}

double _mergedCutoff(IgdbSyncRow local, IgdbSyncRow imported) {
  if (imported.complete && !local.complete) return imported.cutoff;
  if (local.complete && !imported.complete) return local.cutoff;
  if (local.complete && imported.complete) {
    return imported.cutoff < local.cutoff ? imported.cutoff : local.cutoff;
  }
  return imported.pageOffset >= local.pageOffset
      ? imported.cutoff
      : local.cutoff;
}

List<IgdbScoreRow> _scores(Object? raw) {
  if (raw is! List) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final rows = <IgdbScoreRow>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const IgdbTransferException('That file is not a Romgi score list.');
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
      throw const IgdbTransferException('That file is not a Romgi score list.');
    }
    rows.add(
      IgdbScoreRow(
        platform: platform,
        titleKey: titleKey,
        score: score.toDouble(),
        gameId: gameId,
      ),
    );
  }
  return rows;
}

List<IgdbSyncRow> _sync(Object? raw) {
  if (raw is! List) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final rows = <IgdbSyncRow>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const IgdbTransferException('That file is not a Romgi score list.');
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
      throw const IgdbTransferException('That file is not a Romgi score list.');
    }
    rows.add(
      IgdbSyncRow(
        platform: platform,
        pageOffset: pageOffset,
        complete: complete,
        cutoff: cutoff.toDouble(),
      ),
    );
  }
  return rows;
}
