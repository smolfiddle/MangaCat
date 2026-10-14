import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/recent_list.dart';

class RecentsStore {
  RecentsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'recents_v1';

  List<RecentList> all() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <RecentList>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <RecentList>[];
      final lists = decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentList.fromJson)
          .toList();
      lists.sort((RecentList a, RecentList b) => b.lastOpenedMs.compareTo(a.lastOpenedMs));
      return lists;
    } catch (_) {
      return const <RecentList>[];
    }
  }

  RecentList? get last {
    final lists = all();
    return lists.isEmpty ? null : lists.first;
  }

  Future<void> upsert(RecentList entry) async {
    final lists = all().where((RecentList r) => r.uri != entry.uri).toList()..add(entry);
    await _write(lists);
  }

  Future<void> remove(String uri) async {
    final lists = all().where((RecentList r) => r.uri != uri).toList();
    await _write(lists);
  }

  Future<void> touch(
    String uri, {
    String? name,
    int? count,
    bool? dirty,
  }) async {
    final lists = all();
    final index = lists.indexWhere((RecentList r) => r.uri == uri);
    if (index < 0) return;
    lists[index] = lists[index].copyWith(
      name: name,
      count: count,
      dirty: dirty,
      lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _write(lists);
  }

  Future<void> _write(List<RecentList> lists) async {
    await _prefs.setString(
      _key,
      jsonEncode(lists.map((RecentList e) => e.toJson()).toList()),
    );
  }
}
