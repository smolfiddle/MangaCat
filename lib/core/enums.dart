enum SortPref {
  name('name', 'Name'),
  id('id', 'ID'),
  recent('recent', 'Recently added');

  const SortPref(this.value, this.label);

  final String value;
  final String label;

  static SortPref parse(String? raw) {
    for (final pref in SortPref.values) {
      if (pref.value == raw) return pref;
    }
    return SortPref.recent;
  }
}

enum ReadFilterMode {
  off,
  completedOnly,
  notPlanned;

  String get label => switch (this) {
        ReadFilterMode.off => 'Read: off',
        ReadFilterMode.completedOnly => 'Read = Completed only',
        ReadFilterMode.notPlanned => 'Read = any except Planned',
      };

  ReadFilterMode get next => switch (this) {
        ReadFilterMode.off => ReadFilterMode.completedOnly,
        ReadFilterMode.completedOnly => ReadFilterMode.notPlanned,
        ReadFilterMode.notPlanned => ReadFilterMode.off,
      };

  bool matches(String statusValue) => switch (this) {
        ReadFilterMode.off => true,
        ReadFilterMode.completedOnly => statusValue == 'completed',
        ReadFilterMode.notPlanned => statusValue != 'planned',
      };
}
