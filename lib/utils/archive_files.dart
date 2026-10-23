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

/// The file-type chip, such as `iso`. Null when it is not a plain extension.
String? formatExtension(String format) {
  final cleaned = format.trim().toLowerCase().replaceAll('.', '');
  if (cleaned.isEmpty || !RegExp(r'^[a-z0-9]+$').hasMatch(cleaned)) {
    return null;
  }
  return '.$cleaned';
}

/// A ghost download uses the link's file-type tag. `iso` can be ghosted
/// even when the hosted file is a zip. The tag itself has to be an archive
/// before the download is refused.
bool canGhostRelease({required String filename, required String format}) {
  final extension = formatExtension(format);
  if (extension != null) return !archiveExtensions.contains(extension);
  return canGhostFilename(filename);
}

/// Name written for a ghost. The tag replaces an archive extension, so a
/// MiNERVA zip tagged `iso` becomes `Game.iso`.
String ghostFilename({required String filename, required String format}) {
  final extension = formatExtension(format);
  var name = filename.trim().replaceAll('\\', '/').split('/').last;
  if (extension == null || name.isEmpty) return name;
  if (isArchiveFilename(name)) {
    name = name.substring(0, name.lastIndexOf('.'));
  }
  final dot = name.lastIndexOf('.');
  final current = dot > 0 ? name.substring(dot).toLowerCase() : '';
  if (current == extension) return name;
  if (current.isEmpty) return '$name$extension';
  return '${name.substring(0, dot)}$extension';
}
