import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/enums.dart';
import '../core/text_utils.dart';
import '../data/list_repository.dart';
import '../data/models/audit_record.dart';
import '../data/models/entry.dart';
import '../data/models/recent_list.dart';
import '../data/saf_gateway.dart';
import 'providers.dart';

class TrackerState {
  const TrackerState({
    required this.uri,
    required this.name,
    required this.entries,
    required this.dirty,
    required this.advanced,
    required this.showId,
    required this.sort,
    required this.defaultStatusFilter,
    required this.query,
    required this.statusFilter,
    required this.readFilter,
    required this.canUndo,
  });

  factory TrackerState.empty() => const TrackerState(
        uri: '',
        name: '',
        entries: <Entry>[],
        dirty: false,
        advanced: false,
        showId: true,
        sort: SortPref.recent,
        defaultStatusFilter: null,
        query: '',
        statusFilter: null,
        readFilter: ReadFilterMode.off,
        canUndo: false,
      );

  final String uri;
  final String name;
  final List<Entry> entries;
  final bool dirty;
  final bool advanced;
  final bool showId;
  final SortPref sort;
  final EntryStatus? defaultStatusFilter;
  final String query;
  final EntryStatus? statusFilter;
  final ReadFilterMode readFilter;
  final bool canUndo;

  static const Object _unset = Object();

  TrackerState copyWith({
    String? uri,
    String? name,
    List<Entry>? entries,
    bool? dirty,
    bool? advanced,
    bool? showId,
    SortPref? sort,
    Object? defaultStatusFilter = _unset,
    String? query,
    Object? statusFilter = _unset,
    ReadFilterMode? readFilter,
    bool? canUndo,
  }) {
    return TrackerState(
      uri: uri ?? this.uri,
      name: name ?? this.name,
      entries: entries ?? this.entries,
      dirty: dirty ?? this.dirty,
      advanced: advanced ?? this.advanced,
      showId: showId ?? this.showId,
      sort: sort ?? this.sort,
      defaultStatusFilter: identical(defaultStatusFilter, _unset)
          ? this.defaultStatusFilter
          : defaultStatusFilter as EntryStatus?,
      query: query ?? this.query,
      statusFilter:
          identical(statusFilter, _unset) ? this.statusFilter : statusFilter as EntryStatus?,
      readFilter: readFilter ?? this.readFilter,
      canUndo: canUndo ?? this.canUndo,
    );
  }
}

enum ExternalCheckResult { unchanged, reloaded, conflict }

class TrackerController extends AsyncNotifier<TrackerState> {
  ListRepository? _repo;
  Future<void> Function()? _undo;

  @override
  Future<TrackerState> build() async => TrackerState.empty();

  ListRepository get _requireRepo {
    final repo = _repo;
    if (repo == null) throw StateError('No list is open.');
    return repo;
  }

  TrackerState get _data => state.requireValue;

  bool get isOpen => _repo != null;

  Future<OpenReport> open({required String uri, required String name}) async {
    await close();
    state = const AsyncLoading<TrackerState>();
    ListRepository? repo;
    try {
      repo = await ListRepository.open(uri: uri, saf: ref.read(safGatewayProvider));
      final report = await repo.load();
      final meta = await repo.metaAll();
      final entries = await repo.entries();
      _repo = repo;
      _undo = null;
      final String? defaultFilterRaw =
          meta['default_filter'] == null || meta['default_filter'] == 'all'
              ? null
              : meta['default_filter'];
      final defaultFilter =
          defaultFilterRaw == null ? null : EntryStatus.fromCsv(defaultFilterRaw);
      state = AsyncData(
        TrackerState(
          uri: uri,
          name: repo.displayName.isNotEmpty ? repo.displayName : name,
          entries: entries,
          dirty: meta['dirty'] == '1',
          advanced: meta['advanced_mode'] == '1',
          showId: meta['show_id'] != '0',
          sort: SortPref.parse(meta['sort_pref']),
          defaultStatusFilter: defaultFilter,
          query: '',
          statusFilter: defaultFilter,
          readFilter: ReadFilterMode.off,
          canUndo: false,
        ),
      );
      await _touchRecents();
      return report;
    } catch (error, stack) {
      if (repo != null) {
        try {
          await repo.close();
        } catch (_) {
          // The workspace is already going away.
        }
      }
      state = AsyncError<TrackerState>(error, stack);
      rethrow;
    }
  }

  Future<void> close() async {
    final repo = _repo;
    _repo = null;
    _undo = null;
    if (repo != null) {
      try {
        await repo.close();
      } catch (_) {
        // The database is already going away.
      }
    }
    state = AsyncData(TrackerState.empty());
  }

  Future<OpenReport> reloadFromCsv() async {
    final repo = _requireRepo;
    final report = await repo.reloadFromCsv();
    final entries = await repo.entries();
    final advanced = await repo.metaGet('advanced_mode') == '1';
    _undo = null;
    state = AsyncData(
      _data.copyWith(entries: entries, dirty: false, advanced: advanced, canUndo: false),
    );
    await _touchRecents();
    return report;
  }

  Future<void> _touchRecents() async {
    final data = _data;
    if (data.uri.isEmpty) return;
    await ref.read(recentsStoreProvider).upsert(
          RecentList(
            uri: data.uri,
            name: data.name,
            count: data.entries.length,
            lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
            dirty: data.dirty,
          ),
        );
  }

  Future<void> _afterMutation(Future<void> Function()? undo) async {
    final repo = _requireRepo;
    await repo.markDirty();
    _undo = undo;
    final entries = await repo.entries();
    state = AsyncData(
      _data.copyWith(entries: entries, dirty: true, canUndo: undo != null),
    );
    await _touchRecents();
  }

  bool _sameEntry(Entry a, Entry b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.status == b.status &&
      a.rating == b.rating &&
      a.progress == b.progress &&
      a.notes == b.notes;

  Future<Entry> addEntry({
    required String title,
    String artist = '',
    EntryStatus status = EntryStatus.none,
  }) async {
    final repo = _requireRepo;
    final created = (await repo.addEntries(
      <EntryDraft>[EntryDraft(title: title, artist: artist, status: status)],
    ))
        .single;
    await _afterMutation(() async {
      await repo.deleteEntries(<Entry>[created], audit: false);
    });
    return created;
  }

  Future<List<Entry>> batchAddTitles(List<String> titles) async {
    final repo = _requireRepo;
    if (titles.isEmpty) return const <Entry>[];
    final created = await repo.addEntries(
      titles.map((String t) => EntryDraft(title: t)).toList(),
      batch: true,
    );
    await _afterMutation(() async {
      await repo.deleteEntries(created, audit: false);
    });
    return created;
  }

  Future<void> updateEntry(Entry entry) async {
    final repo = _requireRepo;
    Entry? previous;
    for (final e in _data.entries) {
      if (e.id == entry.id) {
        previous = e;
        break;
      }
    }
    if (previous == null || _sameEntry(previous, entry)) return;
    final prev = previous;
    await repo.updateEntry(entry);
    await _afterMutation(() async {
      await repo.updateEntry(prev, audit: false);
    });
  }

  Future<void> toggleCompleted(Entry entry) async {
    final next = entry.copyWith(
      status: entry.status == EntryStatus.completed
          ? EntryStatus.none
          : EntryStatus.completed,
      updatedAt: DateTime.now(),
    );
    await updateEntry(next);
  }

  Future<void> deleteEntries(List<int> ids) async {
    final repo = _requireRepo;
    final removed = _data.entries
        .where((Entry e) => ids.contains(e.id))
        .toList(growable: false);
    if (removed.isEmpty) return;
    await repo.deleteEntries(removed);
    await _afterMutation(() async {
      for (final entry in removed) {
        await repo.restoreEntry(entry, audit: false);
      }
    });
  }

  Future<void> setStatusMany(List<int> ids, EntryStatus status) async {
    final repo = _requireRepo;
    final previous = <Entry>[];
    final next = <Entry>[];
    for (final entry in _data.entries) {
      if (!ids.contains(entry.id)) continue;
      previous.add(entry);
      next.add(entry.copyWith(status: status, updatedAt: DateTime.now()));
    }
    if (next.isEmpty) return;
    for (final entry in next) {
      await repo.updateEntry(entry);
    }
    await _afterMutation(() async {
      for (final entry in previous) {
        await repo.updateEntry(entry, audit: false);
      }
    });
  }

  Future<List<Entry>> restoreFromAudit(AuditRecord record) async {
    final repo = _requireRepo;
    final restored = <Entry>[];
    for (final snapshot in record.snapshots) {
      restored.add(await repo.restoreEntry(snapshot));
    }
    await _afterMutation(() async {
      await repo.deleteEntries(restored, audit: false);
    });
    return restored;
  }

  Future<void> undoLast() async {
    final undo = _undo;
    final repo = _repo;
    if (undo == null) return;
    if (repo == null) {
      _undo = null;
      if (state.hasValue) {
        state = AsyncData(_data.copyWith(canUndo: false));
      }
      return;
    }
    _undo = null;
    try {
      await undo();
    } catch (_) {
      _undo = undo;
      if (state.hasValue) {
        state = AsyncData(_data.copyWith(canUndo: true));
      }
      return;
    }
    await repo.markDirty();
    final entries = await repo.entries();
    state = AsyncData(_data.copyWith(entries: entries, dirty: true, canUndo: false));
    await _touchRecents();
  }

  Future<SafDocument> saveToCsv() async {
    final repo = _requireRepo;
    final doc = await repo.saveCsv(advanced: _data.advanced);
    state = AsyncData(_data.copyWith(dirty: false));
    await _touchRecents();
    return doc;
  }

  Future<SafDocument> saveToNewFile() async {
    final repo = _requireRepo;
    final saf = ref.read(safGatewayProvider);
    final suggested = _data.name.toLowerCase().endsWith('.csv')
        ? _data.name
        : '${_data.name}.csv';
    final doc = await saf.createFile(suggestedName: suggested);
    if (doc == null) {
      throw const SafException(SafErrorKind.io, 'No destination was chosen.');
    }
    final csv = await repo.exportCsv(advanced: _data.advanced);
    final written = await saf.writeBytes(doc.uri, Uint8List.fromList(utf8.encode(csv)));
    final newRepo = await ListRepository.open(uri: doc.uri, saf: saf);
    await newRepo.load();
    final oldUri = repo.sourceUri;
    await repo.close();
    _repo = newRepo;
    _undo = null;
    await ref.read(recentsStoreProvider).remove(oldUri);
    try {
      await saf.releasePermission(oldUri);
    } catch (_) {
      // A session grant disappears with the process; nothing else to do.
    }
    state = AsyncData(
      _data.copyWith(
        uri: doc.uri,
        name: written.name.isNotEmpty ? written.name : suggested,
        dirty: false,
        canUndo: false,
      ),
    );
    await _touchRecents();
    return written;
  }

  Future<ExternalCheckResult> checkExternal() async {
    final repo = _repo;
    if (repo == null) return ExternalCheckResult.unchanged;
    final current = await repo.sourceFingerprint();
    final lastSaved = await repo.lastSavedFingerprint();
    if (lastSaved != null && lastSaved.matches(current)) {
      return ExternalCheckResult.unchanged;
    }
    if (_data.dirty) return ExternalCheckResult.conflict;
    await reloadFromCsv();
    return ExternalCheckResult.reloaded;
  }

  Future<void> acceptExternalState() async {
    await _requireRepo.acceptExternalState();
  }

  Future<void> setAdvanced(bool value) async {
    final repo = _requireRepo;
    await repo.metaSet('advanced_mode', value ? '1' : '0');
    await repo.markDirty();
    state = AsyncData(_data.copyWith(advanced: value, dirty: true));
    await _touchRecents();
  }

  Future<void> setShowId(bool value) async {
    await _requireRepo.metaSet('show_id', value ? '1' : '0');
    state = AsyncData(_data.copyWith(showId: value));
  }

  Future<void> setSort(SortPref pref) async {
    await _requireRepo.metaSet('sort_pref', pref.value);
    state = AsyncData(_data.copyWith(sort: pref));
  }

  Future<void> setDefaultStatusFilter(EntryStatus? status) async {
    await _requireRepo.metaSet('default_filter', status?.value ?? 'all');
    state = AsyncData(_data.copyWith(defaultStatusFilter: status));
  }

  void setQuery(String query) {
    state = AsyncData(_data.copyWith(query: query));
  }

  void setStatusFilter(EntryStatus? status) {
    state = AsyncData(_data.copyWith(statusFilter: status));
  }

  void setReadFilter(ReadFilterMode mode) {
    state = AsyncData(_data.copyWith(readFilter: mode));
  }

  void cycleReadFilter() {
    state = AsyncData(_data.copyWith(readFilter: _data.readFilter.next));
  }

  Future<List<AuditRecord>> history({AuditAction? action}) =>
      _requireRepo.audit(action: action);

  Future<void> clearHistory() => _requireRepo.clearAudit();
}

final AsyncNotifierProvider<TrackerController, TrackerState> trackerControllerProvider =
    AsyncNotifierProvider<TrackerController, TrackerState>(TrackerController.new);

final Provider<List<Entry>> visibleEntriesProvider = Provider<List<Entry>>((Ref ref) {
  final data = ref.watch(trackerControllerProvider).value;
  if (data == null) return const <Entry>[];
  final normalizedQuery = normalizeForMatch(data.query);
  final list = data.entries.where((Entry entry) {
    if (data.statusFilter != null && entry.status != data.statusFilter) return false;
    if (!data.readFilter.matches(entry.status.value)) return false;
    if (normalizedQuery.isNotEmpty) {
      final titleHit = normalizeForMatch(entry.title).contains(normalizedQuery);
      final artistHit = normalizeForMatch(entry.artist).contains(normalizedQuery);
      if (!titleHit && !artistHit) return false;
    }
    return true;
  }).toList();
  switch (data.sort) {
    case SortPref.name:
      list.sort(
        (Entry a, Entry b) =>
            normalizeForMatch(a.title).compareTo(normalizeForMatch(b.title)),
      );
    case SortPref.id:
      list.sort((Entry a, Entry b) => a.id.compareTo(b.id));
    case SortPref.recent:
      list.sort((Entry a, Entry b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
  }
  return list;
});
