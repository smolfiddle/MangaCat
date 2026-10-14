class RecentList {
  const RecentList({
    required this.uri,
    required this.name,
    required this.count,
    required this.lastOpenedMs,
    required this.dirty,
  });

  final String uri;
  final String name;
  final int count;
  final int lastOpenedMs;
  final bool dirty;

  RecentList copyWith({String? name, int? count, int? lastOpenedMs, bool? dirty}) {
    return RecentList(
      uri: uri,
      name: name ?? this.name,
      count: count ?? this.count,
      lastOpenedMs: lastOpenedMs ?? this.lastOpenedMs,
      dirty: dirty ?? this.dirty,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'uri': uri,
        'name': name,
        'count': count,
        'last_opened_ms': lastOpenedMs,
        'dirty': dirty,
      };

  factory RecentList.fromJson(Map<String, Object?> json) => RecentList(
        uri: json['uri']! as String,
        name: (json['name'] as String?) ?? 'MangaCat.csv',
        count: (json['count'] as num?)?.toInt() ?? 0,
        lastOpenedMs: (json['last_opened_ms'] as num?)?.toInt() ?? 0,
        dirty: (json['dirty'] as bool?) ?? false,
      );
}
