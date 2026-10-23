const archiveExtensions = {'.zip', '.7z', '.rar'};

/// True when [filename] is an archive Cocoon will not open.
bool isArchiveFilename(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  return archiveExtensions.contains(filename.substring(dot).toLowerCase());
}

/// A ghost keeps the link filename, so the name must already be the file
/// Cocoon would open. Archives are never ghosted.
bool canGhostFilename(String filename) {
  final trimmed = filename.trim();
  final dot = trimmed.lastIndexOf('.');
  if (dot <= 0 || dot == trimmed.length - 1) return false;
  return !isArchiveFilename(trimmed);
}
