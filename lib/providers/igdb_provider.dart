import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import '../services/metadata/igdb_client.dart';
import '../services/metadata/igdb_credentials.dart';
import '../services/metadata/igdb_platforms.dart';
import '../services/metadata/igdb_transfer.dart';
import '../services/metadata/moby_titles.dart';
import '../services/metadata/score_index.dart';
import 'download_provider.dart';

class IgdbPlatformProgress {
  final bool complete;
  final double cutoff;
  final int stored;

  const IgdbPlatformProgress({
    required this.complete,
    required this.cutoff,
    required this.stored,
  });
}

class IgdbSyncState {
  final ScoreIndex index;
  final int indexRevision;
  final Map<String, IgdbPlatformProgress> platforms;
  final List<IgdbGenre> genres;
  final bool configured;
  final String? activePlatform;
  final int activeOffset;
  final String? error;
  final bool running;

  const IgdbSyncState({
    this.index = const ScoreIndex(),
    this.indexRevision = 0,
    this.platforms = const {},
    this.genres = const [],
    this.configured = false,
    this.activePlatform,
    this.activeOffset = 0,
    this.error,
    this.running = false,
  });

  int get storedTitles =>
      platforms.values.fold(0, (sum, item) => sum + item.stored);

  IgdbSyncState copyWith({
    ScoreIndex? index,
    int? indexRevision,
    Map<String, IgdbPlatformProgress>? platforms,
    List<IgdbGenre>? genres,
    bool? configured,
    String? activePlatform,
    bool clearActive = false,
    int? activeOffset,
    String? error,
    bool clearError = false,
    bool? running,
  }) {
    return IgdbSyncState(
      index: index ?? this.index,
      indexRevision: indexRevision ?? this.indexRevision,
      platforms: platforms ?? this.platforms,
      genres: genres ?? this.genres,
      configured: configured ?? this.configured,
      activePlatform: clearActive ? null : (activePlatform ?? this.activePlatform),
      activeOffset: activeOffset ?? this.activeOffset,
      error: clearError ? null : (error ?? this.error),
      running: running ?? this.running,
    );
  }
}

class IgdbSyncNotifier extends StateNotifier<IgdbSyncState> {
  IgdbSyncNotifier({
    required DatabaseService db,
    IgdbClient? client,
    IgdbCredentialStore? credentials,
  }) : _db = db,
       _client = client ?? IgdbClient(),
       _credentials = credentials ?? IgdbCredentialStore(),
       super(const IgdbSyncState()) {
    _load();
  }

  final DatabaseService _db;
  final IgdbClient _client;
  final IgdbCredentialStore _credentials;
  int _generation = 0;
  CancelToken? _cancelToken;

  Future<IgdbCredentials> credentials() => _credentials.read();

  Future<void> saveCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    await _credentials.write(
      IgdbCredentials(clientId: clientId, clientSecret: clientSecret),
    );
    if (!mounted) return;
    state = state.copyWith(
      configured: clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty,
      clearError: true,
    );
  }

  Future<void> _load({
    bool running = false,
    String? activePlatform,
    int activeOffset = 0,
    String? error,
    bool clearError = false,
  }) async {
    final scoreRows = await _db.allMobyScores();
    final sync = await _db.mobySyncStates();
    final auth = await _credentials.read();
    final scores = <String, double>{};
    final stored = <String, int>{};
    for (final row in scoreRows) {
      final platform = row['platform'] as String? ?? '';
      final titleKey = row['title_key'] as String? ?? '';
      final score = (row['score'] as num?)?.toDouble();
      if (platform.isEmpty || titleKey.isEmpty || score == null) continue;
      scores['$platform|$titleKey'] = score;
      stored[platform] = (stored[platform] ?? 0) + 1;
    }

    final platforms = <String, IgdbPlatformProgress>{};
    final complete = <String>{};
    for (final entry in sync.entries) {
      platforms[entry.key] = IgdbPlatformProgress(
        complete: entry.value.complete,
        cutoff: entry.value.cutoff,
        stored: stored[entry.key] ?? 0,
      );
      if (entry.value.complete) complete.add(entry.key);
    }
    for (final entry in stored.entries) {
      platforms.putIfAbsent(
        entry.key,
        () => IgdbPlatformProgress(
          complete: false,
          cutoff: 0,
          stored: entry.value,
        ),
      );
    }

    if (!mounted) return;
    final previous = state;
    state = IgdbSyncState(
      index: ScoreIndex(scores: scores, completePlatforms: complete),
      indexRevision: previous.indexRevision + 1,
      platforms: platforms,
      genres: previous.genres,
      configured: auth.ready,
      activePlatform: activePlatform,
      activeOffset: activeOffset,
      error: clearError ? null : (error ?? previous.error),
      running: running,
    );
  }

  void cancel() {
    _generation++;
    _cancelToken?.cancel('cancelled');
  }

  Future<List<IgdbGenre>> loadGenres() async {
    final auth = await _credentials.read();
    if (!auth.ready) {
      throw const IgdbException(
        'Add a Twitch Client ID and secret, then try Setup again.',
      );
    }
    final genres = await _client.genres(
      clientId: auth.clientId,
      clientSecret: auth.clientSecret,
    );
    if (mounted) state = state.copyWith(genres: genres, configured: true);
    return genres;
  }

  Future<void> runSetup({
    required List<String> platforms,
    required List<int> genreIds,
    required double cutoff,
  }) async {
    if (state.running || platforms.isEmpty) return;
    final auth = await _credentials.read();
    if (!auth.ready) {
      state = state.copyWith(
        error: 'Add a Twitch Client ID and secret, then try Setup again.',
      );
      return;
    }

    final runId = ++_generation;
    final token = CancelToken();
    _cancelToken = token;
    state = state.copyWith(running: true, clearError: true);

    try {
      for (final platform in platforms) {
        if (!mounted || _generation != runId) return;
        await _runPlatform(
          platform: platform,
          genreIds: genreIds,
          cutoff: cutoff,
          auth: auth,
          runId: runId,
          token: token,
        );
        if (!mounted || _generation != runId) return;
        if (state.error != null) return;
      }
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
      if (mounted) await _load(clearError: state.error == null);
    }
  }

  Future<void> _runPlatform({
    required String platform,
    required List<int> genreIds,
    required double cutoff,
    required IgdbCredentials auth,
    required int runId,
    required CancelToken token,
  }) async {
    final platformId = igdbPlatformIds[platform.toLowerCase()];
    if (platformId == null) return;

    await _db.deleteMobyPlatform(platform);
    await _load(
      running: true,
      activePlatform: platform,
      clearError: true,
    );

    var offset = 0;
    try {
      while (mounted && _generation == runId) {
        state = state.copyWith(activePlatform: platform, activeOffset: offset);
        final games = await _client.games(
          clientId: auth.clientId,
          clientSecret: auth.clientSecret,
          platformId: platformId,
          genreIds: genreIds,
          minimumScore: cutoff,
          offset: offset,
          cancelToken: token,
        );
        if (!mounted || _generation != runId) return;
        if (games.isNotEmpty) {
          await _db.upsertMobyScores([
            for (final game in games)
              ..._rowsFor(platform, game),
          ]);
          await _load(
            running: true,
            activePlatform: platform,
            activeOffset: offset,
            clearError: true,
          );
        }
        if (games.length < 500) {
          await _db.setMobySync(
            platform: platform,
            offset: offset,
            complete: true,
            cutoff: cutoff,
          );
          return;
        }
        offset += 500;
        await _db.setMobySync(
          platform: platform,
          offset: offset,
          complete: false,
          cutoff: cutoff,
        );
      }
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return;
      await _fail(platform, offset, cutoff, 'Could not reach IGDB.');
    } on IgdbException catch (error) {
      await _fail(platform, offset, cutoff, error.message);
    } catch (_) {
      await _fail(platform, offset, cutoff, 'Could not reach IGDB.');
    }
  }

  Future<void> _fail(
    String platform,
    int offset,
    double cutoff,
    String message,
  ) async {
    await _db.setMobySync(
      platform: platform,
      offset: offset,
      complete: false,
      cutoff: cutoff,
    );
    if (mounted) state = state.copyWith(error: message);
  }

  List<Map<String, Object?>> _rowsFor(String platform, IgdbListedGame game) {
    final seen = <String>{};
    final rows = <Map<String, Object?>>[];
    for (final name in [game.name, ...game.alternativeNames]) {
      final titleKey = mobyTitleKey(name);
      if (titleKey.isEmpty || !seen.add(titleKey)) continue;
      rows.add({
        'platform': platform,
        'title_key': titleKey,
        'score': game.score,
        'game_id': game.id,
      });
    }
    return rows;
  }

  Future<IgdbTransfer> exportTransfer() async {
    final scoreRows = await _db.allMobyScores();
    final sync = await _db.mobySyncStates();
    return IgdbTransfer(
      scores: [
        for (final row in scoreRows)
          if (row['platform'] is String &&
              row['title_key'] is String &&
              row['score'] is num &&
              row['game_id'] is int)
            IgdbScoreRow(
              platform: row['platform'] as String,
              titleKey: row['title_key'] as String,
              score: (row['score'] as num).toDouble(),
              gameId: row['game_id'] as int,
            ),
      ],
      sync: [
        for (final entry in sync.entries)
          IgdbSyncRow(
            platform: entry.key,
            pageOffset: entry.value.offset,
            complete: entry.value.complete,
            cutoff: entry.value.cutoff,
          ),
      ],
    );
  }

  /// Merges a score list into this device. Download history is left alone.
  Future<int> importTransfer(String source) async {
    final transfer = parseIgdbTransfer(source);
    await _db.upsertMobyScores([
      for (final row in transfer.scores) row.toDbRow(),
    ]);
    final local = await _db.mobySyncStates();
    final merged = mergeIgdbSync(
      local: [
        for (final entry in local.entries)
          IgdbSyncRow(
            platform: entry.key,
            pageOffset: entry.value.offset,
            complete: entry.value.complete,
            cutoff: entry.value.cutoff,
          ),
      ],
      imported: transfer.sync,
    );
    for (final row in merged) {
      await _db.setMobySync(
        platform: row.platform,
        offset: row.pageOffset,
        complete: row.complete,
        cutoff: row.cutoff,
      );
    }
    await _load(clearError: true);
    return transfer.scores.length;
  }
}

final igdbSyncProvider = StateNotifierProvider<IgdbSyncNotifier, IgdbSyncState>(
  (ref) {
    return IgdbSyncNotifier(db: ref.watch(databaseServiceProvider));
  },
);
