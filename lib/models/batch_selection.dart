/// Browse multiselect. [all] means every match for the current query,
/// minus [excluded]. Otherwise [picked] is the explicit set.
class BatchSelection {
  final bool active;
  final bool all;
  final Set<String> picked;
  final Set<String> excluded;

  const BatchSelection({
    this.active = false,
    this.all = false,
    this.picked = const {},
    this.excluded = const {},
  });

  static const empty = BatchSelection();

  int count(int total) {
    if (!active) return 0;
    if (all) {
      final value = total - excluded.length;
      if (value < 0) return 0;
      if (value > total) return total;
      return value;
    }
    return picked.length;
  }

  bool contains(String slug) {
    if (!active) return false;
    if (all) return !excluded.contains(slug);
    return picked.contains(slug);
  }

  BatchSelection start(String slug) {
    return BatchSelection(active: true, picked: {slug});
  }

  BatchSelection selectAll() {
    return const BatchSelection(active: true, all: true);
  }

  BatchSelection toggle(String slug) {
    if (!active) return start(slug);
    if (all) {
      final next = Set<String>.from(excluded);
      if (!next.add(slug)) next.remove(slug);
      return BatchSelection(active: true, all: true, excluded: next);
    }
    final next = Set<String>.from(picked);
    if (!next.add(slug)) next.remove(slug);
    if (next.isEmpty) return empty;
    return BatchSelection(active: true, picked: next);
  }
}
