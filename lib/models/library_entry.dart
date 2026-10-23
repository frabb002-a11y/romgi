import '../utils/archive_files.dart';
import 'download_task.dart';

/// One file the library is showing. [ghost] is decided by the file length,
/// not by a stored flag.
class LibraryEntry {
  final DownloadTask task;
  final bool ghost;

  /// False when the file was found on disk without a download row.
  /// Those rows can be removed or deleted, but not filled in.
  final bool tracked;

  const LibraryEntry({
    required this.task,
    required this.ghost,
    required this.tracked,
  });

  String? get path => task.filePath;

  bool get canInstall => ghost && tracked && task.link.url.isNotEmpty;

  bool get canConvert {
    final filePath = path;
    if (ghost || filePath == null) return false;
    final slash = filePath.replaceAll('\\', '/');
    final name = slash.split('/').last;
    return canGhostFilename(name);
  }
}
