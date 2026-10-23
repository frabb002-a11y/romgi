import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../models/models.dart';
import '../services/services.dart';
import '../utils/archive_files.dart';
import 'download_provider.dart';

class LibraryState {
  final List<LibraryEntry> entries;
  final String? selectedPlatform;
  final String searchQuery;
  final bool isLoading;

  const LibraryState({
    this.entries = const [],
    this.selectedPlatform,
    this.searchQuery = '',
    this.isLoading = false,
  });

  LibraryState copyWith({
    List<LibraryEntry>? entries,
    String? selectedPlatform,
    bool clearPlatform = false,
    String? searchQuery,
    bool? isLoading,
  }) {
    return LibraryState(
      entries: entries ?? this.entries,
      selectedPlatform: clearPlatform
          ? null
          : (selectedPlatform ?? this.selectedPlatform),
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<LibraryEntry> get realEntries =>
      entries.where((entry) => !entry.ghost).toList();

  List<LibraryEntry> get ghostEntries =>
      entries.where((entry) => entry.ghost).toList();

  List<LibraryEntry> filtered({required bool ghosts}) {
    var result = ghosts ? ghostEntries : realEntries;
    if (selectedPlatform != null &&
        result.any((entry) => entry.task.platform == selectedPlatform)) {
      result = result
          .where((entry) => entry.task.platform == selectedPlatform)
          .toList();
    }
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where(
            (entry) =>
                entry.task.title.toLowerCase().contains(query) ||
                entry.task.platform.toLowerCase().contains(query),
          )
          .toList();
    }
    return result;
  }

  List<String> platformsFor({required bool ghosts}) {
    final source = ghosts ? ghostEntries : realEntries;
    final names = source.map((entry) => entry.task.platform).toSet().toList();
    names.sort();
    return names;
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final DatabaseService _db;
  final StorageService _storage;

  LibraryNotifier(this._db, this._storage) : super(const LibraryState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final completed = await _db.getCompletedDownloads();
    final ignored = await _db.ignoredPaths();
    final active = await _db.getActiveDownloads();
    final activePaths = active
        .map((task) => task.filePath)
        .whereType<String>()
        .map(path.normalize)
        .toSet();

    final entries = <LibraryEntry>[];
    final known = <String>{};

    for (final task in completed) {
      final filePath = task.filePath;
      if (filePath == null) {
        await _db.deleteDownload(task.id);
        continue;
      }
      final normalized = path.normalize(filePath);
      if (ignored.contains(filePath) || ignored.contains(normalized)) {
        continue;
      }
      if (activePaths.contains(normalized)) continue;
      final stat = await _stat(filePath);
      if (!stat.exists) {
        await _db.deleteDownload(task.id);
        continue;
      }
      final name = path.basename(filePath);
      if (_skipName(name)) continue;
      entries.add(
        LibraryEntry(
          task: task,
          ghost: !stat.directory && stat.length == 0,
          tracked: true,
        ),
      );
      known.add(normalized);
    }

    final roots = await _storage.libraryDirectories();
    for (final root in roots) {
      if (!await root.exists()) continue;
      final platform = path.basename(root.path);
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        final normalized = path.normalize(entity.path);
        if (known.contains(normalized)) continue;
        if (ignored.contains(entity.path) || ignored.contains(normalized)) {
          continue;
        }
        if (activePaths.contains(normalized)) continue;
        final name = path.basename(entity.path);
        if (_skipName(name)) continue;
        final length = await entity.length();
        entries.add(
          LibraryEntry(
            task: _untrackedTask(
              filePath: entity.path,
              name: name,
              platform: platform,
              length: length,
            ),
            ghost: length == 0,
            tracked: false,
          ),
        );
        known.add(normalized);
      }
    }

    entries.sort((a, b) {
      final aTime = a.task.completedAt ?? a.task.createdAt;
      final bTime = b.task.completedAt ?? b.task.createdAt;
      return bTime.compareTo(aTime);
    });

    if (!mounted) return;
    state = state.copyWith(entries: entries, isLoading: false);
  }

  Future<void> removeFromLibrary(List<LibraryEntry> items) async {
    for (final item in items) {
      final filePath = item.path;
      if (filePath != null) await _db.ignorePath(filePath);
      if (item.tracked) await _db.deleteDownload(item.task.id);
    }
    await refresh();
  }

  Future<void> deleteFiles(List<LibraryEntry> items) async {
    for (final item in items) {
      final filePath = item.path;
      if (filePath != null) {
        await _deletePath(filePath);
        await _db.unignorePath(filePath);
      }
      if (item.tracked) await _db.deleteDownload(item.task.id);
    }
    await refresh();
  }

  Future<int> convertToGhosts(List<LibraryEntry> items) async {
    var converted = 0;
    for (final item in items) {
      final filePath = item.path;
      if (!item.canConvert || filePath == null) continue;
      final file = File(filePath);
      if (!await file.exists()) continue;
      await file.writeAsBytes(const [], flush: true);
      converted++;
    }
    await refresh();
    return converted;
  }

  /// Drops the ghost row and the empty file so a real download can take the
  /// same slug. Returns the entries that are ready to queue.
  Future<List<LibraryEntry>> prepareInstall(List<LibraryEntry> items) async {
    final ready = <LibraryEntry>[];
    for (final item in items) {
      if (!item.canInstall) continue;
      final filePath = item.path;
      if (filePath != null) {
        await _deletePath(filePath);
        await _db.unignorePath(filePath);
      }
      await _db.deleteDownload(item.task.id);
      ready.add(item);
    }
    await refresh();
    return ready;
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedPlatform(String? platform) {
    if (platform == null) {
      state = state.copyWith(clearPlatform: true);
    } else {
      state = state.copyWith(selectedPlatform: platform);
    }
  }

  Future<void> verifyFiles() => refresh();

  Future<void> cleanupMissingFiles() => refresh();
}

bool _skipName(String name) {
  final lower = name.toLowerCase();
  if (lower.startsWith('.')) return true;
  if (lower.endsWith('.m3u')) return true;
  if (lower.contains('.extract-')) return true;
  return isArchiveFilename(name);
}

Future<({bool exists, bool directory, int length})> _stat(String filePath) async {
  final type = await FileSystemEntity.type(filePath, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return (exists: false, directory: false, length: 0);
  }
  if (type == FileSystemEntityType.directory) {
    return (exists: true, directory: true, length: -1);
  }
  if (type != FileSystemEntityType.file) {
    return (exists: false, directory: false, length: 0);
  }
  return (exists: true, directory: false, length: await File(filePath).length());
}

DownloadTask _untrackedTask({
  required String filePath,
  required String name,
  required String platform,
  required int length,
}) {
  final dot = name.lastIndexOf('.');
  final title = dot > 0 ? name.substring(0, dot) : name;
  return DownloadTask(
    id: 'untracked:$filePath',
    slug: 'local:$filePath',
    title: title,
    platform: platform,
    link: DownloadLink(
      name: name,
      type: 'Game',
      format: dot > 0 ? name.substring(dot + 1) : '',
      url: '',
      filename: name,
      host: '',
      size: length,
      sizeStr: length == 0 ? 'Ghost' : '',
      sourceUrl: '',
    ),
    status: DownloadStatus.completed,
    progress: 1,
    filePath: filePath,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<void> _deletePath(String filePath) async {
  final type = await FileSystemEntity.type(filePath, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await Directory(filePath).delete(recursive: true);
  } else if (type == FileSystemEntityType.file) {
    await File(filePath).delete();
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((
  ref,
) {
  final db = ref.watch(databaseServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return LibraryNotifier(db, storage);
});

/// Provider for all downloaded slugs (for badge display).
/// Watches libraryProvider to auto-refresh when library changes.
final downloadedSlugsProvider = FutureProvider<Set<String>>((ref) async {
  final libraryState = ref.watch(libraryProvider);
  if (libraryState.entries.isNotEmpty || !libraryState.isLoading) {
    return libraryState.entries
        .where((entry) => entry.tracked)
        .map((entry) => entry.task.slug)
        .toSet();
  }
  final db = ref.watch(databaseServiceProvider);
  final completed = await db.getCompletedDownloads();
  return completed.map((task) => task.slug).toSet();
});
