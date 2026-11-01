import 'dart:convert';

import 'igdb_ranking.dart';

/// IGDB catalog export/import between devices.
const igdbTransferKind = 'romgi-igdb';
const igdbTransferVersion = 2;

class IgdbGameRow {
  final String platform;
  final int gameId;
  final String name;
  final double rating;
  final int ratingCount;
  final double weighted;
  final int gameType;

  const IgdbGameRow({
    required this.platform,
    required this.gameId,
    required this.name,
    required this.rating,
    required this.ratingCount,
    required this.weighted,
    this.gameType = 0,
  });

  Map<String, Object?> toGameDbRow() => {
    'platform': platform,
    'game_id': gameId,
    'name': name,
    'rating': rating,
    'rating_count': ratingCount,
    'weighted': weighted,
    'game_type': gameType,
  };
}

class IgdbTitleKeyRow {
  final String platform;
  final String titleKey;
  final int gameId;

  const IgdbTitleKeyRow({
    required this.platform,
    required this.titleKey,
    required this.gameId,
  });

  Map<String, Object?> toDbRow() => {
    'platform': platform,
    'title_key': titleKey,
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
  final List<IgdbGameRow> games;
  final List<IgdbTitleKeyRow> titleKeys;
  final List<IgdbSyncRow> sync;

  const IgdbTransfer({
    required this.games,
    required this.titleKeys,
    required this.sync,
  });

  Iterable<IgdbTitleKeyRow> titleKeysForGame(String platform, int gameId) sync* {
    for (final row in titleKeys) {
      if (row.platform == platform && row.gameId == gameId) yield row;
    }
  }
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
    'games': [
      for (final row in transfer.games)
        {
          'platform': row.platform,
          'game_id': row.gameId,
          'name': row.name,
          'rating': row.rating,
          'rating_count': row.ratingCount,
          'weighted': row.weighted,
          'game_type': row.gameType,
        },
    ],
    'title_keys': [
      for (final row in transfer.titleKeys)
        {
          'platform': row.platform,
          'title_key': row.titleKey,
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
  if (version is! int) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  if (version == 1) return _parseV1(json);
  if (version == 2) {
    return IgdbTransfer(
      games: _gamesV2(json['games']),
      titleKeys: _titleKeysV2(json['title_keys']),
      sync: _sync(json['sync']),
    );
  }
  throw const IgdbTransferException(
    'This Romgi build cannot read that score list.',
  );
}

IgdbTransfer _parseV1(Map<Object?, Object?> json) {
  final rawScores = json['scores'];
  if (rawScores is! List) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final keys = <IgdbTitleKeyRow>[];
  final gamesById = <String, IgdbGameRow>{};
  for (final item in rawScores) {
    if (item is! Map) continue;
    final m = item.cast<Object?, Object?>();
    final platform = m['platform'];
    final titleKey = m['title_key'];
    final score = m['score'];
    final gameId = m['game_id'];
    if (platform is! String ||
        titleKey is! String ||
        score is! num ||
        gameId is! int) {
      continue;
    }
    keys.add(
      IgdbTitleKeyRow(platform: platform, titleKey: titleKey, gameId: gameId),
    );
    final idKey = '$platform|$gameId';
    gamesById.putIfAbsent(
      idKey,
      () => IgdbGameRow(
        platform: platform,
        gameId: gameId,
        name: titleKey,
        rating: score.toDouble(),
        ratingCount: 1,
        weighted: igdbWeightedRating(score.toDouble(), 1),
      ),
    );
  }
  return IgdbTransfer(
    games: gamesById.values.toList(),
    titleKeys: keys,
    sync: _sync(json['sync']),
  );
}

List<IgdbGameRow> _gamesV2(Object? raw) {
  if (raw is! List) {
    throw const IgdbTransferException('That file is not a Romgi score list.');
  }
  final rows = <IgdbGameRow>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const IgdbTransferException('That file is not a Romgi score list.');
    }
    final json = item.cast<Object?, Object?>();
    final platform = json['platform'];
    final gameId = json['game_id'];
    final name = json['name'];
    final rating = json['rating'];
    final ratingCount = json['rating_count'];
    final weighted = json['weighted'];
    if (platform is! String ||
        platform.isEmpty ||
        gameId is! int ||
        name is! String ||
        rating is! num ||
        ratingCount is! int ||
        weighted is! num) {
      throw const IgdbTransferException('That file is not a Romgi score list.');
    }
    rows.add(
      IgdbGameRow(
        platform: platform,
        gameId: gameId,
        name: name,
        rating: rating.toDouble(),
        ratingCount: ratingCount,
        weighted: weighted.toDouble(),
        gameType: json['game_type'] is int ? json['game_type'] as int : 0,
      ),
    );
  }
  return rows;
}

List<IgdbTitleKeyRow> _titleKeysV2(Object? raw) {
  if (raw is! List) return const [];
  final rows = <IgdbTitleKeyRow>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final json = item.cast<Object?, Object?>();
    final platform = json['platform'];
    final titleKey = json['title_key'];
    final gameId = json['game_id'];
    if (platform is! String ||
        titleKey is! String ||
        gameId is! int) {
      continue;
    }
    rows.add(
      IgdbTitleKeyRow(
        platform: platform,
        titleKey: titleKey,
        gameId: gameId,
      ),
    );
  }
  return rows;
}

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
  return byPlatform.values.toList()
    ..sort((a, b) => a.platform.compareTo(b.platform));
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
    cutoff: 0,
  );
}

List<IgdbSyncRow> _sync(Object? raw) {
  if (raw is! List) return const [];
  final rows = <IgdbSyncRow>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final json = item.cast<Object?, Object?>();
    final platform = json['platform'];
    final pageOffset = json['page_offset'];
    final complete = json['complete'];
    if (platform is! String ||
        platform.isEmpty ||
        pageOffset is! int ||
        complete is! bool) {
      continue;
    }
    rows.add(
      IgdbSyncRow(
        platform: platform,
        pageOffset: pageOffset,
        complete: complete,
        cutoff: 0,
      ),
    );
  }
  return rows;
}
