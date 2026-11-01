import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/metadata/igdb_catalog_index.dart';
import '../services/metadata/igdb_platforms.dart';
import '../services/rom_database_service.dart';
import '../utils/rom_pick.dart';
import 'api_provider.dart';
import 'igdb_provider.dart';
import 'settings_provider.dart';

class SearchState {
  final String query;
  final List<String> selectedPlatforms;
  final List<String> selectedRegions;
  final bool retroAchievementsOnly;
  final bool scoreOnly;
  final double minimumScore;
  final int minIgdbVotes;
  final bool igdbGapsOnly;
  final bool igdbDiscoveryOnly;
  final double discoveryMinScore;
  final bool oneGameOneRom;
  final SearchResult? result;
  final bool isLoading;
  final dynamic error;
  final BatchSelection selection;

  const SearchState({
    this.query = '',
    this.selectedPlatforms = const [],
    this.selectedRegions = const [],
    this.retroAchievementsOnly = false,
    this.scoreOnly = false,
    this.minimumScore = 60,
    this.minIgdbVotes = 10,
    this.igdbGapsOnly = false,
    this.igdbDiscoveryOnly = false,
    this.discoveryMinScore = 80,
    this.oneGameOneRom = false,
    this.result,
    this.isLoading = false,
    this.error,
    this.selection = BatchSelection.empty,
  });

  int get selectedCount => selection.count(result?.totalResults ?? 0);

  IgdbDownstreamFilters get igdbFilters => IgdbDownstreamFilters(
    minUserRating: minimumScore <= 0 ? 0 : minimumScore,
    minVotes: minIgdbVotes,
  );

  SearchState copyWith({
    String? query,
    List<String>? selectedPlatforms,
    List<String>? selectedRegions,
    bool? retroAchievementsOnly,
    bool? scoreOnly,
    double? minimumScore,
    int? minIgdbVotes,
    bool? igdbGapsOnly,
    bool? igdbDiscoveryOnly,
    double? discoveryMinScore,
    bool? oneGameOneRom,
    SearchResult? result,
    bool clearResult = false,
    bool? isLoading,
    dynamic error,
    bool clearError = false,
    BatchSelection? selection,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedPlatforms: selectedPlatforms ?? this.selectedPlatforms,
      selectedRegions: selectedRegions ?? this.selectedRegions,
      retroAchievementsOnly:
          retroAchievementsOnly ?? this.retroAchievementsOnly,
      scoreOnly: scoreOnly ?? this.scoreOnly,
      minimumScore: minimumScore ?? this.minimumScore,
      minIgdbVotes: minIgdbVotes ?? this.minIgdbVotes,
      igdbGapsOnly: igdbGapsOnly ?? this.igdbGapsOnly,
      igdbDiscoveryOnly: igdbDiscoveryOnly ?? this.igdbDiscoveryOnly,
      discoveryMinScore: discoveryMinScore ?? this.discoveryMinScore,
      oneGameOneRom: oneGameOneRom ?? this.oneGameOneRom,
      result: clearResult ? null : (result ?? this.result),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selection: selection ?? this.selection,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final RomDatabaseService _db;
  final IgdbCatalogIndex Function() _index;
  final List<String> Function() _excludeTerms;
  List<RomEntry>? _filteredAll;
  List<IgdbCatalogEntry>? _filteredIgdb;
  Map<String, Set<String>>? _catalogKeys;
  int _request = 0;

  SearchNotifier(this._db, this._index, this._excludeTerms)
    : super(const SearchState());

  bool get _usesLocalList =>
      state.scoreOnly ||
      state.oneGameOneRom ||
      state.igdbGapsOnly ||
      state.igdbDiscoveryOnly ||
      _excludeTerms().isNotEmpty;

  Future<void> search({String? query}) async {
    final request = ++_request;
    _filteredAll = null;
    _filteredIgdb = null;
    _catalogKeys = null;
    state = state.copyWith(
      query: query ?? state.query,
      isLoading: true,
      clearResult: true,
      clearError: true,
      selection: BatchSelection.empty,
    );

    try {
      final result = await _load(page: 1, request: request);
      if (request != _request) return;
      state = state.copyWith(result: result, isLoading: false);
    } catch (error) {
      if (request != _request) return;
      state = state.copyWith(error: error, isLoading: false);
    }
  }

  Future<void> loadNextPage() async {
    final currentResult = state.result;
    if (currentResult == null || !currentResult.hasMore || state.isLoading) {
      return;
    }

    final request = _request;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final nextPage = currentResult.currentPage + 1;
      final result = await _load(page: nextPage, request: request);
      if (request != _request) return;
      state = state.copyWith(
        result: SearchResult(
          entries: [...currentResult.entries, ...result.entries],
          igdbGaps: [
            ...?currentResult.igdbGaps,
            ...?result.igdbGaps,
          ],
          totalResults: result.totalResults,
          currentPage: result.currentPage,
          totalPages: result.totalPages,
          currentResults: currentResult.entries.length +
              result.entries.length +
              (currentResult.igdbGaps?.length ?? 0) +
              (result.igdbGaps?.length ?? 0),
        ),
        isLoading: false,
      );
    } catch (error) {
      if (request != _request) return;
      state = state.copyWith(error: error, isLoading: false);
    }
  }

  Future<SearchResult> _load({required int page, required int request}) async {
    const pageSize = 100;

    if (state.igdbGapsOnly) {
      if (_filteredIgdb == null) {
        _filteredIgdb = await _buildIgdbList();
        if (request != _request) {
          return SearchResult.empty(page: page);
        }
      }
      final all = _filteredIgdb!;
      final start = (page - 1) * pageSize;
      final end = start + pageSize;
      final slice = start >= all.length
          ? const <IgdbCatalogEntry>[]
          : all.sublist(start, end > all.length ? all.length : end);
      final totalPages = all.isEmpty ? 1 : (all.length / pageSize).ceil();
      return SearchResult(
        entries: const [],
        igdbGaps: slice,
        totalResults: all.length,
        currentPage: page,
        totalPages: totalPages,
        currentResults: slice.length,
      );
    }

    if (!_usesLocalList) {
      if (request == _request) _filteredAll = null;
      return _db.search(
        query: state.query.isEmpty ? null : state.query,
        platforms: state.selectedPlatforms.isEmpty
            ? null
            : state.selectedPlatforms,
        regions: state.selectedRegions.isEmpty ? null : state.selectedRegions,
        retroAchievementsOnly: state.retroAchievementsOnly,
        page: page,
        maxResults: pageSize,
      );
    }

    if (_filteredAll == null) {
      final matches = await _listedMatches();
      if (request != _request) {
        return SearchResult.empty(page: page);
      }
      _filteredAll = _narrow(matches);
    }
    final all = _filteredAll!;
    final start = (page - 1) * pageSize;
    final end = start + pageSize;
    final slice = start >= all.length
        ? const <RomEntry>[]
        : all.sublist(start, end > all.length ? all.length : end);
    final totalPages = all.isEmpty ? 1 : (all.length / pageSize).ceil();
    return SearchResult(
      entries: slice,
      totalResults: all.length,
      currentPage: page,
      totalPages: totalPages,
      currentResults: slice.length,
    );
  }

  Future<List<IgdbCatalogEntry>> _buildIgdbList() async {
    final index = _index();
    final platforms = _igdbPlatformsForFilter();
    if (platforms.isEmpty) return const [];

    _catalogKeys ??= await _db.catalogTitleKeysByPlatform();

    final igdbPlatforms = state.selectedPlatforms.isEmpty
        ? _index().completePlatforms.toList()
        : {
            for (final p in platforms)
              if (canonicalIgdbPlatform(p) != null) canonicalIgdbPlatform(p)!,
          }.toList();

    final catalogByIgdb = <String, Set<String>>{};
    for (final entry in _catalogKeys!.entries) {
      final canonical = canonicalIgdbPlatform(entry.key);
      if (canonical == null) continue;
      catalogByIgdb.putIfAbsent(canonical, () => {}).addAll(entry.value);
    }

    return index.unmatchedGaps(
      igdbPlatforms: igdbPlatforms,
      catalogKeysByPlatform: catalogByIgdb,
      filters: state.igdbFilters,
      query: state.query.isEmpty ? null : state.query,
    );
  }

  List<String> _igdbPlatformsForFilter() {
    if (state.selectedPlatforms.isNotEmpty) return state.selectedPlatforms;
    return _index().completePlatforms.toList();
  }

  Future<List<RomEntry>> _listedMatches() {
    return _db.listMatches(
      query: state.query.isEmpty ? null : state.query,
      platforms: state.selectedPlatforms.isEmpty
          ? null
          : state.selectedPlatforms,
      regions: state.selectedRegions.isEmpty ? null : state.selectedRegions,
      retroAchievementsOnly: state.retroAchievementsOnly,
    );
  }

  List<RomEntry> _narrow(List<RomEntry> entries) {
    final terms = _excludeTerms();
    var list = entries;
    if (terms.isNotEmpty) {
      list = list.where((entry) => !titleExcluded(entry.title, terms)).toList();
    }
    if (state.scoreOnly || state.igdbDiscoveryOnly) {
      list = _applyScores(list);
    }
    if (state.oneGameOneRom) list = pickOnePerGame(list);
    return list;
  }

  List<RomEntry> _applyScores(List<RomEntry> entries) {
    final index = _index();
    final filters = state.igdbFilters;
    final minDisplay = state.minimumScore <= 0 ? null : state.minimumScore / 10;
    if (state.igdbDiscoveryOnly) {
      return entries.where((entry) {
        final record = index.recordForTitle(entry.platform, entry.title);
        if (record == null) return false;
        final reason = index.rejectReason(record, filters);
        return reason == IgdbRejectReason.lowVotes &&
            record.rating >= state.discoveryMinScore &&
            record.ratingCount >= 5;
      }).toList();
    }
    return entries
        .where(
          (entry) => index.keepRomEntry(
            entry.platform,
            entry.title,
            filters: filters,
            minimumDisplayScore: minDisplay,
          ),
        )
        .toList();
  }

  void invalidateScoreFilter() {
    if (!state.scoreOnly && !state.igdbDiscoveryOnly) return;
    _filteredAll = null;
    _filteredIgdb = null;
    if (state.result != null) search();
  }

  void invalidateIgdbViews() {
    _filteredIgdb = null;
    _catalogKeys = null;
    if (state.result != null) search();
  }

  void invalidateExcludeTerms() {
    _filteredAll = null;
    if (state.result != null) search();
  }

  Future<List<String>> resolveSelectedSlugs() async {
    final selection = state.selection;
    if (!selection.active) return const [];
    if (!selection.all) return selection.picked.toList();
    final all =
        _filteredAll ??
        (_usesLocalList && !state.igdbGapsOnly
            ? _narrow(await _listedMatches())
            : await _listedMatches());
    final slugs = all.map((entry) => entry.slug);
    return slugs.where((slug) => !selection.excluded.contains(slug)).toList();
  }

  void startSelecting(String slug) {
    state = state.copyWith(selection: state.selection.start(slug));
  }

  void toggleSelected(String slug) {
    state = state.copyWith(selection: state.selection.toggle(slug));
  }

  void selectAll() {
    state = state.copyWith(selection: state.selection.selectAll());
  }

  void clearSelection() {
    state = state.copyWith(selection: BatchSelection.empty);
  }

  void setSelectedPlatforms(List<String> platforms) {
    _filteredAll = null;
    _filteredIgdb = null;
    _catalogKeys = null;
    state = state.copyWith(selectedPlatforms: platforms);
  }

  void setSelectedRegions(List<String> regions) {
    _filteredAll = null;
    state = state.copyWith(selectedRegions: regions);
  }

  void setRetroAchievementsOnly(bool value) {
    _filteredAll = null;
    state = state.copyWith(retroAchievementsOnly: value);
  }

  void setScoreOnly(bool value) {
    _filteredAll = null;
    state = state.copyWith(scoreOnly: value, igdbDiscoveryOnly: false);
  }

  void setMinimumScore(double value) {
    _filteredAll = null;
    _filteredIgdb = null;
    state = state.copyWith(minimumScore: value);
  }

  void setMinIgdbVotes(int value) {
    _filteredAll = null;
    _filteredIgdb = null;
    state = state.copyWith(minIgdbVotes: value);
  }

  void setIgdbGapsOnly(bool value) {
    _filteredIgdb = null;
    state = state.copyWith(
      igdbGapsOnly: value,
      igdbDiscoveryOnly: value ? false : state.igdbDiscoveryOnly,
      scoreOnly: value ? false : state.scoreOnly,
    );
  }

  void setIgdbDiscoveryOnly(bool value) {
    _filteredAll = null;
    _filteredIgdb = null;
    state = state.copyWith(
      igdbDiscoveryOnly: value,
      igdbGapsOnly: value ? false : state.igdbGapsOnly,
      scoreOnly: value ? false : state.scoreOnly,
    );
  }

  void setDiscoveryMinScore(double value) {
    _filteredAll = null;
    _filteredIgdb = null;
    state = state.copyWith(discoveryMinScore: value);
  }

  void setOneGameOneRom(bool value) {
    _filteredAll = null;
    state = state.copyWith(oneGameOneRom: value);
  }

  void clearFilters() {
    _filteredAll = null;
    _filteredIgdb = null;
    _catalogKeys = null;
    state = state.copyWith(
      selectedPlatforms: [],
      selectedRegions: [],
      retroAchievementsOnly: false,
      scoreOnly: false,
      minimumScore: 60,
      minIgdbVotes: 10,
      igdbGapsOnly: false,
      igdbDiscoveryOnly: false,
      discoveryMinScore: 80,
      oneGameOneRom: false,
    );
  }

  void reset() {
    _filteredAll = null;
    _filteredIgdb = null;
    _catalogKeys = null;
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final db = ref.watch(romDatabaseProvider);
  final notifier = SearchNotifier(
    db,
    () => ref.read(igdbSyncProvider).index,
    () => ref.read(settingsProvider).excludeTerms,
  );
  ref.listen(igdbSyncProvider.select((sync) => sync.indexRevision), (
    previous,
    next,
  ) {
    if (previous != next) {
      notifier.invalidateScoreFilter();
      notifier.invalidateIgdbViews();
    }
  });
  ref.listen(
    settingsProvider.select((settings) => settings.excludeTerms.join('\u0001')),
    (previous, next) {
      if (previous != next) notifier.invalidateExcludeTerms();
    },
  );
  return notifier;
});
