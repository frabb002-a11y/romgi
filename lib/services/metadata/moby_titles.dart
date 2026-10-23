/// Key used to match a ROM title to a MobyGames title locally.
/// Region tags, disc markers, and dump flags live in brackets, so they
/// are stripped before the comparison.
String mobyTitleKey(String title) {
  var text = title.toLowerCase();
  text = text.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  text = text.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  text = text.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.startsWith('the ')) text = text.substring(4);
  return text;
}
