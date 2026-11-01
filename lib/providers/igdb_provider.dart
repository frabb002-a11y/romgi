import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import '../services/metadata/igdb_catalog_index.dart';
import '../services/metadata/igdb_client.dart';
import '../services/metadata/igdb_credentials.dart';
import '../services/metadata/igdb_platforms.dart';
import '../services/metadata/igdb_transfer.dart';
import '../services/metadata/moby_titles.dart';
import 'download_provider.dart';

class IgdbPlatformProgress {
  final bool complete;
  final int stored;

  const IgdbPlatformProgress({
    required this.complete,
    required this.stored,
  });
}

class IgdbSyncState {
  final IgdbCatalogIndex index;
  final int indexRevision;
  final Map<String, IgdbPlatformProgress> platforms;
  final List<IgdbGenre> genres;
  final bool configured;
  final String? activePlatform;
  final int activeOffset;
  final String? error;
  final bool running;

  const IgdbSyncState({
    this.index = const IgdbCatalogIndex(),
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
    IgdbCatalogIndex? index,
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
    final catalog = await _db.allIgdbCatalogRows();
    final sync = await _db.mobySyncStates();
    final auth = await _credentials.read();

    final gamesByPlatform = <String, Map<int, IgdbGameRecord>>{};
    for (final row in catalog.games) {
      final platform = row['platform'] as String? ?? '';
      final gameId = row['game_id'] as int?;
      if (platform.isEmpty || gameId == null) continue;
      gamesByPlatform.putIfAbsent(platform, () => {})[gameId] = IgdbGameRecord(
        platform: platform,
        gameId: gameId,
        name: row['name'] as String? ?? '',
        rating: (row['rating'] as num?)?.toDouble() ?? 0,
        ratingCount: row['rating_count'] as int? ?? 0,
        weighted: (row['weighted'] as num?)?.toDouble() ?? 0,
        gameType: row['game_type'] as int? ?? 0,
      );
    }

    final titleKeyToGameId = <String, int>{};
    for (final row in catalog.titleKeys) {
      final platform = row['platform'] as String? ?? '';
      final titleKey = row['title_key'] as String? ?? '';
      final gameId = row['game_id'] as int?;
      if (platform.isEmpty || titleKey.isEmpty || gameId == null) continue;
      titleKeyToGameId[IgdbCatalogIndex.titleKeyLookupKey(platform, titleKey)] =
          gameId;
    }

    final stored = <String, int>{};
    for (final entry in gamesByPlatform.entries) {
      stored[entry.key] = entry.value.length;
    }

    final platforms = <String, IgdbPlatformProgress>{};
    final complete = <String>{};
    for (final entry in sync.entries) {
      platforms[entry.key] = IgdbPlatformProgress(
        complete: entry.value.complete,
        stored: stored[entry.key] ?? 0,
      );
      if (entry.value.complete) complete.add(entry.key);
    }
    for (final entry in stored.entries) {
      platforms.putIfAbsent(
        entry.key,
        () => IgdbPlatformProgress(complete: false, stored: entry.value),
      );
    }

    if (!mounted) return;
    final previous = state;
    state = IgdbSyncState(
      index: IgdbCatalogIndex(
        gamesByPlatform: gamesByPlatform,
        titleKeyToGameId: titleKeyToGameId,
        completePlatforms: complete,
      ),
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

  /// Upstream sync: full IGDB pool per platform (no score cutoff — filter in Browse).
  Future<void> runSetup({
    required List<String> platforms,
    required List<int> genreIds,
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
    required IgdbCredentials auth,
    required int runId,
    required CancelToken token,
  }) async {
    final platformId = igdbPlatformIds[platform.toLowerCase()];
    if (platformId == null) return;

    await _db.deleteIgdbPlatform(platform);
    await _load(
      running: true,
      activePlatform: platform,
      clearError: true,
    );

    var offset = 0;
    try {
      while (mounted && _generation == runId) {
        state = state.copyWith(activePlatform: platform, activeOffset: offset);
        final page = await _client.poolPage(
          clientId: auth.clientId,
          clientSecret: auth.clientSecret,
          platformId: platformId,
          genreIds: genreIds,
          offset: offset,
          cancelToken: token,
        );
        if (!mounted || _generation != runId) return;

        if (page.isNotEmpty) {
          final releaseFlags = await _client.releaseOnPlatform(
            clientId: auth.clientId,
            clientSecret: auth.clientSecret,
            platformId: platformId,
            gameIds: [for (final g in page) g.id],
            cancelToken: token,
          );
          final onPlatform = page
              .where((g) => releaseFlags[g.id] ?? false)
              .toList();
          if (onPlatform.isNotEmpty) {
            await _db.appendIgdbCatalogBatch(
              platform: platform,
              games: [
                for (final game in onPlatform)
                  {
                    'platform': platform,
                    'game_id': game.id,
                    'name': game.name,
                    'rating': game.rating,
                    'rating_count': game.ratingCount,
                    'weighted': game.weighted,
                    'game_type': game.gameType,
                  },
              ],
              titleKeys: [
                for (final game in onPlatform)
                  ..._titleKeyRows(platform, game),
              ],
            );
          }
          await _load(
            running: true,
            activePlatform: platform,
            activeOffset: offset,
            clearError: true,
          );
        }

        if (page.length < 500) {
          await _db.setMobySync(
            platform: platform,
            offset: offset,
            complete: true,
            cutoff: 0,
          );
          return;
        }
        offset += 500;
        await _db.setMobySync(
          platform: platform,
          offset: offset,
          complete: false,
          cutoff: 0,
        );
      }
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return;
      await _fail(platform, offset);
    } on IgdbException catch (error) {
      await _fail(platform, offset, error.message);
    } catch (_) {
      await _fail(platform, offset);
    }
  }

  Future<void> _fail(String platform, int offset, [String? message]) async {
    await _db.setMobySync(
      platform: platform,
      offset: offset,
      complete: false,
      cutoff: 0,
    );
    if (mounted) {
      state = state.copyWith(
        error: message ?? 'Could not reach IGDB.',
      );
    }
  }

  Iterable<Map<String, Object?>> _titleKeyRows(
    String platform,
    IgdbPoolGame game,
  ) sync* {
    final seen = <String>{};
    for (final name in [game.name, ...game.alternativeNames]) {
      final titleKey = mobyTitleKey(name);
      if (titleKey.isEmpty || !seen.add(titleKey)) continue;
      yield {
        'platform': platform,
        'title_key': titleKey,
        'game_id': game.id,
      };
    }
  }

  Future<IgdbTransfer> exportTransfer() async {
    final catalog = await _db.allIgdbCatalogRows();
    final sync = await _db.mobySyncStates();
    return IgdbTransfer(
      games: [
        for (final row in catalog.games)
          if (row['platform'] is String &&
              row['game_id'] is int &&
              row['name'] is String &&
              row['rating'] is num &&
              row['rating_count'] is int &&
              row['weighted'] is num)
            IgdbGameRow(
              platform: row['platform'] as String,
              gameId: row['game_id'] as int,
              name: row['name'] as String,
              rating: (row['rating'] as num).toDouble(),
              ratingCount: row['rating_count'] as int,
              weighted: (row['weighted'] as num).toDouble(),
              gameType: row['game_type'] as int? ?? 0,
            ),
      ],
      titleKeys: [
        for (final row in catalog.titleKeys)
          if (row['platform'] is String &&
              row['title_key'] is String &&
              row['game_id'] is int)
            IgdbTitleKeyRow(
              platform: row['platform'] as String,
              titleKey: row['title_key'] as String,
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

  Future<int> importTransfer(String source) async {
    final transfer = parseIgdbTransfer(source);
    await _db.importIgdbCatalog(
      games: [for (final row in transfer.games) row.toGameDbRow()],
      titleKeys: [for (final row in transfer.titleKeys) row.toDbRow()],
    );
    for (final row in transfer.sync) {
      await _db.setMobySync(
        platform: row.platform,
        offset: row.pageOffset,
        complete: row.complete,
        cutoff: 0,
      );
    }
    await _load(clearError: true);
    return transfer.games.length;
  }
}

final igdbSyncProvider = StateNotifierProvider<IgdbSyncNotifier, IgdbSyncState>(
  (ref) {
    return IgdbSyncNotifier(db: ref.watch(databaseServiceProvider));
  },
);
