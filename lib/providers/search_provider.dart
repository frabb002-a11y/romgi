import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/metadata/moby_score_index.dart';
import '../services/rom_database_service.dart';
import '../utils/rom_pick.dart';
import 'api_provider.dart';
import 'moby_provider.dart';
import 'settings_provider.dart';

class SearchState {
  final String query;
  final List<String> selectedPlatforms;
  final List<String> selectedRegions;
  final bool retroAchievementsOnly;
  final bool mobyScoreOnly;
  final double minimumMobyScore;
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
    this.mobyScoreOnly = false,
    this.minimumMobyScore = 0,
    this.oneGameOneRom = false,
    this.result,
    this.isLoading = false,
    this.error,
    this.selection = BatchSelection.empty,
  });

  int get selectedCount => selection.count(result?.totalResults ?? 0);

  SearchState copyWith({
    String? query,
    List<String>? selectedPlatforms,
    List<String>? selectedRegions,
    bool? retroAchievementsOnly,
    bool? mobyScoreOnly,
    double? minimumMobyScore,
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
      mobyScoreOnly: mobyScoreOnly ?? this.mobyScoreOnly,
      minimumMobyScore: minimumMobyScore ?? this.minimumMobyScore,
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
  final MobyScoreIndex Function() _index;
  final List<String> Function() _excludeTerms;
  List<RomEntry>? _filteredAll;
  int _request = 0;

  SearchNotifier(this._db, this._index, this._excludeTerms)
    : super(const SearchState());

  bool get _usesLocalList =>
      state.mobyScoreOnly || state.oneGameOneRom || _excludeTerms().isNotEmpty;

  Future<void> search({String? query}) async {
    final request = ++_request;
    _filteredAll = null;
    state = state.copyWith(
      query: query ?? state.query,
      isLoading: true,
      clearError: true,
      selection: BatchSelection.empty,
    );

    try {
      final result = await _load(page: 1);
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

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final nextPage = currentResult.currentPage + 1;
      final result = await _load(page: nextPage);
      final combinedEntries = [...currentResult.entries, ...result.entries];
      state = state.copyWith(
        result: SearchResult(
          entries: combinedEntries,
          totalResults: result.totalResults,
          currentPage: result.currentPage,
          totalPages: result.totalPages,
          currentResults: combinedEntries.length,
        ),
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(error: error, isLoading: false);
    }
  }

  Future<SearchResult> _load({required int page}) async {
    const pageSize = 100;
    if (!_usesLocalList) {
      _filteredAll = null;
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

    _filteredAll ??= _narrow(await _listedMatches());
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
    if (state.mobyScoreOnly) list = _applyScores(list);
    if (state.oneGameOneRom) list = pickOnePerGame(list);
    return list;
  }

  List<RomEntry> _applyScores(List<RomEntry> entries) {
    final index = _index();
    final minimum = state.minimumMobyScore <= 0 ? null : state.minimumMobyScore;
    return entries
        .where(
          (entry) => index.keep(entry.platform, entry.title, minimum: minimum),
        )
        .toList();
  }

  void invalidateScoreFilter() {
    if (!state.mobyScoreOnly) return;
    _filteredAll = null;
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
        (_usesLocalList
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

  void setMobyScoreOnly(bool value) {
    _filteredAll = null;
    state = state.copyWith(mobyScoreOnly: value);
  }

  void setMinimumMobyScore(double value) {
    _filteredAll = null;
    state = state.copyWith(minimumMobyScore: value);
  }

  void setOneGameOneRom(bool value) {
    _filteredAll = null;
    state = state.copyWith(oneGameOneRom: value);
  }

  void clearFilters() {
    _filteredAll = null;
    state = state.copyWith(
      selectedPlatforms: [],
      selectedRegions: [],
      retroAchievementsOnly: false,
      mobyScoreOnly: false,
      minimumMobyScore: 0,
      oneGameOneRom: false,
    );
  }

  void reset() {
    _filteredAll = null;
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final db = ref.watch(romDatabaseProvider);
  final notifier = SearchNotifier(
    db,
    () => ref.read(mobySyncProvider).index,
    () => ref.read(settingsProvider).excludeTerms,
  );
  ref.listen(mobySyncProvider.select((sync) => sync.indexRevision), (
    previous,
    next,
  ) {
    if (previous != next) notifier.invalidateScoreFilter();
  });
  ref.listen(
    settingsProvider.select((settings) => settings.excludeTerms.join('\u0001')),
    (previous, next) {
      if (previous != next) notifier.invalidateExcludeTerms();
    },
  );
  return notifier;
});
