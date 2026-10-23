import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import '../services/metadata/moby_page.dart';
import '../services/metadata/moby_platforms.dart';
import '../services/metadata/moby_score_index.dart';
import '../services/metadata/moby_titles.dart';
import 'download_provider.dart';

class MobyPlatformProgress {
  final int nextPage;
  final bool complete;
  final double cutoff;
  final int stored;

  const MobyPlatformProgress({
    required this.nextPage,
    required this.complete,
    required this.cutoff,
    required this.stored,
  });
}

class MobySyncState {
  final MobyScoreIndex index;
  final int indexRevision;
  final Map<String, MobyPlatformProgress> platforms;
  final String? activePlatform;
  final int activePage;
  final String? error;
  final bool running;

  const MobySyncState({
    this.index = const MobyScoreIndex(),
    this.indexRevision = 0,
    this.platforms = const {},
    this.activePlatform,
    this.activePage = 0,
    this.error,
    this.running = false,
  });

  MobySyncState copyWith({
    MobyScoreIndex? index,
    int? indexRevision,
    Map<String, MobyPlatformProgress>? platforms,
    String? activePlatform,
    bool clearActive = false,
    int? activePage,
    String? error,
    bool clearError = false,
    bool? running,
  }) {
    return MobySyncState(
      index: index ?? this.index,
      indexRevision: indexRevision ?? this.indexRevision,
      platforms: platforms ?? this.platforms,
      activePlatform: clearActive
          ? null
          : (activePlatform ?? this.activePlatform),
      activePage: activePage ?? this.activePage,
      error: clearError ? null : (error ?? this.error),
      running: running ?? this.running,
    );
  }
}

enum MobyJobKind { build, continueJob, rebuild }

class MobySyncNotifier extends StateNotifier<MobySyncState> {
  MobySyncNotifier({required DatabaseService db, MobyPageClient? client})
    : _db = db,
      _client = client ?? MobyPageClient(),
      super(const MobySyncState()) {
    _load();
  }

  final DatabaseService _db;
  final MobyPageClient _client;
  int _generation = 0;
  CancelToken? _cancelToken;
  var _queueActive = false;

  Future<void> _load({
    bool running = false,
    String? activePlatform,
    int activePage = 0,
    String? error,
    bool clearError = false,
  }) async {
    final scoreRows = await _db.allMobyScores();
    final sync = await _db.mobySyncStates();
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

    final platforms = <String, MobyPlatformProgress>{};
    final complete = <String>{};
    for (final entry in sync.entries) {
      final count = stored[entry.key] ?? 0;
      platforms[entry.key] = MobyPlatformProgress(
        nextPage: entry.value.offset,
        complete: entry.value.complete,
        cutoff: entry.value.cutoff,
        stored: count,
      );
      if (entry.value.complete) complete.add(entry.key);
    }
    for (final entry in stored.entries) {
      platforms.putIfAbsent(
        entry.key,
        () => MobyPlatformProgress(
          nextPage: 0,
          complete: false,
          cutoff: 0,
          stored: entry.value,
        ),
      );
    }

    if (!mounted) return;
    final previous = state;
    state = MobySyncState(
      index: MobyScoreIndex(scores: scores, completePlatforms: complete),
      indexRevision: previous.indexRevision + 1,
      platforms: platforms,
      activePlatform: activePlatform,
      activePage: activePage,
      error: clearError ? null : (error ?? previous.error),
      running: running,
    );
  }

  void cancel() {
    _generation++;
    _cancelToken?.cancel('cancelled');
  }

  /// Walks each platform in order. One browser check is shared, so the
  /// pages stay serial. Stop cancels the platform in progress and the rest.
  Future<void> runPlatforms(
    List<String> platforms, {
    required double cutoff,
    required MobyJobKind kind,
  }) async {
    if (state.running || _queueActive || platforms.isEmpty) return;
    _queueActive = true;
    final queueId = _generation;
    state = state.copyWith(clearError: true);
    try {
      for (final platform in platforms) {
        if (!mounted || _generation != queueId) return;
        await runPlatform(
          platform,
          cutoff: cutoff,
          kind: kind,
          fromQueue: true,
        );
        if (!mounted || _generation != queueId) return;
        if (state.error != null) return;
      }
    } finally {
      _queueActive = false;
    }
  }

  Future<void> runPlatform(
    String platform, {
    required double cutoff,
    required MobyJobKind kind,
    bool fromQueue = false,
  }) async {
    if ((state.running || _queueActive) && !fromQueue) return;
    final slug = mobyPlatformSlugs[platform];
    if (slug == null) {
      state = state.copyWith(error: 'No MobyGames page for this platform.');
      return;
    }

    if (kind == MobyJobKind.rebuild) {
      await _db.deleteMobyPlatform(platform);
      await _load(clearError: true);
    }

    final existing = state.platforms[platform];
    if (kind != MobyJobKind.rebuild &&
        existing != null &&
        existing.complete &&
        existing.cutoff <= cutoff + 0.001) {
      return;
    }

    final runId = _generation;
    final token = CancelToken();
    _cancelToken = token;
    var page = kind == MobyJobKind.rebuild || existing == null
        ? 0
        : existing.nextPage;
    state = state.copyWith(
      running: true,
      activePlatform: platform,
      activePage: page,
      clearError: true,
    );

    var failed = false;
    final seenIds = <int>{};
    try {
      while (mounted && _generation == runId) {
        state = state.copyWith(activePlatform: platform, activePage: page);
        final html = await _client.fetchPlatformPage(
          slug,
          page,
          cancelToken: token,
        );
        if (!mounted || _generation != runId) break;
        final parsed = parseMobyPlatformPage(html, cutoff: cutoff);
        final pager = mobyListingPager(html);
        // A page past the end of a long list (Nintendo DS is 49) still
        // returns scored rows, so an empty-page check never trips.
        if (pager != null && pager.current != page + 1) {
          throw MobyPageException(
            'MobyGames returned page ${pager.current} of ${pager.count} '
            'instead of page ${page + 1}. Rebuild this platform.',
          );
        }
        final ids = [for (final game in parsed.games) game.gameId];
        if (page > 0 && mobyPageRepeats(seenIds, ids)) {
          final kept = ids.where((id) => id > 0).length;
          if (seenIds.length > kept) {
            await _db.setMobySync(
              platform: platform,
              offset: page,
              complete: true,
              cutoff: cutoff,
            );
            break;
          }
          throw const MobyPageException(
            'MobyGames returned the same page again. Rebuild this platform.',
          );
        }
        if (parsed.games.isNotEmpty) {
          await _db.upsertMobyScores([
            for (final game in parsed.games)
              {
                'platform': platform,
                'title_key': mobyTitleKey(game.title),
                'score': game.score,
                'game_id': game.gameId,
              },
          ]);
          await _load(
            running: true,
            activePlatform: platform,
            activePage: page,
            clearError: true,
          );
        }
        for (final id in ids) {
          if (id > 0) seenIds.add(id);
        }
        final reachedEnd = parsed.games.isEmpty && !parsed.stopped;
        final onLastPage = pager?.isLast ?? false;
        if (reachedEnd && page == 0) {
          throw const MobyPageException('No games found on the first page.');
        }
        if (parsed.stopped || reachedEnd || onLastPage) {
          await _db.setMobySync(
            platform: platform,
            offset: page,
            complete: true,
            cutoff: cutoff,
          );
          break;
        }
        page += 1;
        await _db.setMobySync(
          platform: platform,
          offset: page,
          complete: false,
          cutoff: cutoff,
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error)) {
        failed = true;
        await _db.setMobySync(
          platform: platform,
          offset: page,
          complete: false,
          cutoff: cutoff,
        );
        if (mounted) {
          state = state.copyWith(error: 'Could not read the MobyGames page.');
        }
      }
    } on MobyPageException catch (error) {
      failed = true;
      await _db.setMobySync(
        platform: platform,
        offset: page,
        complete: false,
        cutoff: cutoff,
      );
      if (mounted) state = state.copyWith(error: error.message);
    } catch (_) {
      failed = true;
      await _db.setMobySync(
        platform: platform,
        offset: page,
        complete: false,
        cutoff: cutoff,
      );
      if (mounted) {
        state = state.copyWith(error: 'Could not read the MobyGames page.');
      }
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }

    if (!mounted) return;
    if (!failed && _generation != runId) {
      await _db.setMobySync(
        platform: platform,
        offset: page,
        complete: false,
        cutoff: cutoff,
      );
    }
    await _load(clearError: !failed && state.error == null);
  }
}

final mobySyncProvider = StateNotifierProvider<MobySyncNotifier, MobySyncState>(
  (ref) {
    return MobySyncNotifier(db: ref.watch(databaseServiceProvider));
  },
);
