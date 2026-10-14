import 'dart:convert';
import 'dart:typed_data';

import 'csv_codec.dart';
import 'fingerprint.dart';
import 'models/audit_record.dart';
import 'models/entry.dart';
import 'saf_gateway.dart';
import 'workspace_db.dart';

class SourceMissingException implements Exception {
  const SourceMissingException(this.uri);

  final String uri;

  @override
  String toString() => 'CSV file not found: $uri';
}

class OpenReport {
  const OpenReport({
    required this.warnings,
    required this.reloadedFromCsv,
    required this.workspaceRebuilt,
  });

  final List<String> warnings;
  final bool reloadedFromCsv;
  final bool workspaceRebuilt;
}

class ListRepository {
  ListRepository._(this.sourceUri, this._saf, this._db);

  final String sourceUri;
  final SafGateway _saf;
  final WorkspaceDb _db;

  bool workspaceRebuilt = false;
  String displayName = '';

  static const String _kLastSavedSize = 'last_saved_size';
  static const String _kLastSavedMtime = 'last_saved_mtime';

  static Future<ListRepository> open({
    required String uri,
    required SafGateway saf,
  }) async {
    final SafDocument stat = await saf.stat(uri);
    if (!stat.exists) throw SourceMissingException(uri);
    WorkspaceDb db;
    var rebuilt = false;
    try {
      db = await WorkspaceDb.open(uri);
    } catch (_) {
      rebuilt = true;
      db = await WorkspaceDb.open(uri, recreate: true);
    }
    final repo = ListRepository._(uri, saf, db);
    repo.workspaceRebuilt = rebuilt;
    repo.displayName = stat.name;
    return repo;
  }

  Future<OpenReport> load() async {
    final warnings = <String>[];
    final SafDocument stat = await _saf.stat(sourceUri);
    if (!stat.exists) throw SourceMissingException(sourceUri);
    displayName = stat.name;
    var reloaded = false;

    final bool firstImport = await _db.metaGet('advanced_mode') == null;
    if (firstImport) {
      await _importCsv(warnings, stat);
    } else {
      final FileFingerprint? lastSaved = await lastSavedFingerprint();
      final current = FileFingerprint(stat.size, stat.mtimeMs);
      if (lastSaved == null || lastSaved != current) {
        await _importCsv(warnings, stat);
        reloaded = true;
      }
    }
    return OpenReport(
      warnings: warnings,
      reloadedFromCsv: reloaded,
      workspaceRebuilt: workspaceRebuilt,
    );
  }

  Future<OpenReport> reloadFromCsv() async {
    final warnings = <String>[];
    final SafDocument stat = await _saf.stat(sourceUri);
    if (!stat.exists) throw SourceMissingException(sourceUri);
    await _importCsv(warnings, stat);
    return OpenReport(
      warnings: warnings,
      reloadedFromCsv: true,
      workspaceRebuilt: false,
    );
  }

  Future<void> _importCsv(List<String> warnings, SafDocument stat) async {
    final Uint8List bytes = await _saf.readBytes(sourceUri);
    final CsvLoadReport report = MangaCatCsv.decode(bytes);
    warnings.addAll(report.warnings);
    await _db.replaceAll(report.entries);
    await _db.metaSet('advanced_mode', report.advanced ? '1' : '0');
    await _db.metaSet(_kLastSavedSize, '${stat.size}');
    await _db.metaSet(_kLastSavedMtime, '${stat.mtimeMs}');
    await _db.metaSet('dirty', '0');
    displayName = stat.name;
    await _db.metaSet('display_name', displayName);
    final int maxId = report.entries.fold<int>(0, (int m, Entry e) => e.id > m ? e.id : m);
    final int storedNext = int.tryParse(await _db.metaGet('next_id') ?? '') ?? 0;
    await _db.metaSet('next_id', '${maxId + 1 > storedNext ? maxId + 1 : storedNext}');
  }

  Future<List<Entry>> entries() => _db.entriesAll();

  Future<Entry?> entryById(int id) => _db.entryById(id);

  Future<List<Entry>> addEntries(
    List<EntryDraft> drafts, {
    bool batch = false,
    bool audit = true,
  }) async {
    final now = DateTime.now();
    final created = <Entry>[];
    await _db.db.transaction((txn) async {
      for (final draft in drafts) {
        final int id = await _db.takeNextId(txn);
        final entry = Entry(
          id: id,
          title: draft.title,
          artist: draft.artist,
          status: draft.status,
          rating: draft.rating,
          progress: draft.progress,
          notes: draft.notes,
          createdAt: now,
          updatedAt: now,
        );
        await _db.insertEntry(entry, txn);
        created.add(entry);
      }
    });
    if (!audit) return created;
    if (created.length == 1 && !batch) {
      final entry = created.single;
      await _db.addAudit(
        AuditRecord(
          seq: 0,
          ts: now,
          action: AuditAction.add,
          entryId: entry.id,
          summary: "Added '${entry.title}' (#${entry.id})",
          snapshots: <Entry>[entry],
        ),
      );
    } else if (created.isNotEmpty) {
      await _db.addAudit(
        AuditRecord(
          seq: 0,
          ts: now,
          action: AuditAction.batchAdd,
          entryId: null,
          summary: 'Added ${created.length} titles',
          snapshots: created,
        ),
      );
    }
    return created;
  }

  Future<Entry> updateEntry(Entry next, {bool audit = true}) async {
    final Entry? previous = await _db.entryById(next.id);
    final Entry updated = next.copyWith(updatedAt: DateTime.now());
    await _db.updateEntry(updated);
    if (audit && previous != null) {
      await _db.addAudit(
        AuditRecord(
          seq: 0,
          ts: updated.updatedAt,
          action: AuditAction.edit,
          entryId: updated.id,
          summary: "Edited '${updated.title}' (#${updated.id})",
          snapshots: <Entry>[previous],
        ),
      );
    }
    return updated;
  }

  Future<void> deleteEntries(List<Entry> removed, {bool audit = true}) async {
    if (removed.isEmpty) return;
    await _db.deleteIds(removed.map((Entry e) => e.id));
    if (!audit) return;
    final now = DateTime.now();
    final String summary = removed.length == 1
        ? "Deleted '${removed.single.title}' (#${removed.single.id})"
        : 'Deleted ${removed.length} entries';
    await _db.addAudit(
      AuditRecord(
        seq: 0,
        ts: now,
        action: AuditAction.delete,
        entryId: removed.length == 1 ? removed.single.id : null,
        summary: summary,
        snapshots: removed,
      ),
    );
  }

  Future<Entry> restoreEntry(Entry snapshot, {bool audit = true}) async {
    final Entry? occupying = await _db.entryById(snapshot.id);
    final int id = occupying == null ? snapshot.id : await _db.takeNextId();
    final Entry restored = snapshot.copyWith(id: id, updatedAt: DateTime.now());
    await _db.insertEntry(restored);
    if (!audit) return restored;
    await _db.addAudit(
      AuditRecord(
        seq: 0,
        ts: restored.updatedAt,
        action: AuditAction.restore,
        entryId: restored.id,
        summary: "Restored '${restored.title}' (#${restored.id})",
        snapshots: <Entry>[restored],
      ),
    );
    return restored;
  }

  Future<String> exportCsv({required bool advanced}) async {
    final entries = await _db.entriesAll();
    return MangaCatCsv.encode(entries, advanced: advanced);
  }

  Future<SafDocument> saveCsv({required bool advanced}) async {
    final String csv = await exportCsv(advanced: advanced);
    final SafDocument doc = await _saf.writeBytes(
      sourceUri,
      Uint8List.fromList(utf8.encode(csv)),
    );
    await _db.metaSet(_kLastSavedSize, '${doc.size}');
    await _db.metaSet(_kLastSavedMtime, '${doc.mtimeMs}');
    await _db.metaSet('dirty', '0');
    return doc;
  }

  Future<FileFingerprint> sourceFingerprint() async {
    final SafDocument stat = await _saf.stat(sourceUri);
    if (!stat.exists) throw SourceMissingException(sourceUri);
    return FileFingerprint(stat.size, stat.mtimeMs);
  }

  Future<FileFingerprint?> lastSavedFingerprint() async {
    final String? size = await _db.metaGet(_kLastSavedSize);
    final String? mtime = await _db.metaGet(_kLastSavedMtime);
    if (size == null || mtime == null) return null;
    return FileFingerprint(int.tryParse(size) ?? -1, int.tryParse(mtime) ?? -1);
  }

  Future<void> acceptExternalState() async {
    final SafDocument stat = await _saf.stat(sourceUri);
    if (!stat.exists) return;
    await _db.metaSet(_kLastSavedSize, '${stat.size}');
    await _db.metaSet(_kLastSavedMtime, '${stat.mtimeMs}');
  }

  Future<bool> isDirty() async => await _db.metaGet('dirty') == '1';

  Future<void> markDirty() => _db.metaSet('dirty', '1');

  Future<Map<String, String>> metaAll() => _db.metaAll();

  Future<String?> metaGet(String key) => _db.metaGet(key);

  Future<void> metaSet(String key, String value) => _db.metaSet(key, value);

  Future<List<AuditRecord>> audit({AuditAction? action}) => _db.auditAll(action: action);

  Future<void> clearAudit() => _db.clearAudit();

  Future<void> close() => _db.close();
}
