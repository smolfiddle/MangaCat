import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangacat/data/csv_codec.dart';
import 'package:mangacat/data/list_repository.dart';
import 'package:mangacat/data/models/audit_record.dart';
import 'package:mangacat/data/models/entry.dart';
import 'package:mangacat/data/workspace_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_saf.dart';

String uniqueUri(String label) =>
    'content://test/${DateTime.now().microsecondsSinceEpoch}-$label.csv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('load imports the CSV into a fresh workspace', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('import');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n2,Beta,\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    final report = await repo.load();
    expect(report.workspaceRebuilt, isFalse);
    expect(report.reloadedFromCsv, isFalse);
    final entries = await repo.entries();
    expect(entries.map((Entry e) => e.id), <int>[1, 2]);
    expect(entries.first.artist, 'Ann');
    expect(await repo.metaGet('advanced_mode'), '0');
    expect(await repo.isDirty(), isFalse);
    await repo.close();
  });

  test('workspace wins on reopen when the file is unchanged', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('reopen');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    await repo.addEntries(<EntryDraft>[const EntryDraft(title: 'Local only')]);
    await repo.markDirty();
    await repo.close();

    final reopened = await ListRepository.open(uri: uri, saf: saf);
    final report = await reopened.load();
    expect(report.reloadedFromCsv, isFalse);
    final entries = await reopened.entries();
    expect(entries.length, 2);
    expect(await reopened.isDirty(), isTrue);
    await reopened.close();
  });

  test('external file change reloads with external winner', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('external');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    final before = await repo.sourceFingerprint();
    expect(await repo.lastSavedFingerprint(), before);

    saf.put(uri, 'id,title,artist\r\n9,FromPC,Mallory\r\n');
    expect(await repo.sourceFingerprint(), isNot(before));

    final report = await repo.reloadFromCsv();
    expect(report.reloadedFromCsv, isTrue);
    final entries = await repo.entries();
    expect(entries.single.id, 9);
    expect(entries.single.title, 'FromPC');
    expect(await repo.isDirty(), isFalse);
    await repo.close();
  });

  test('external change with unsaved edits opens as a conflict', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('conflict');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    await repo.addEntries(<EntryDraft>[const EntryDraft(title: 'Local only')]);
    await repo.markDirty();
    await repo.close();

    saf.put(uri, 'id,title,artist\r\n9,FromPC,Mallory\r\n');
    final reopened = await ListRepository.open(uri: uri, saf: saf);
    final report = await reopened.load();
    expect(report.conflict, isTrue);
    expect(report.reloadedFromCsv, isFalse);
    final entries = await reopened.entries();
    expect(entries.length, 2);
    expect(await reopened.isDirty(), isTrue);
    await reopened.close();
  });

  test('ids are never reused after deletion', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('ids');
    saf.put(uri, 'id,title,artist\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    final created = await repo.addEntries(<EntryDraft>[
      const EntryDraft(title: 'A'),
      const EntryDraft(title: 'B'),
    ]);
    expect(created.map((Entry e) => e.id), <int>[1, 2]);
    await repo.deleteEntries(<Entry>[created.last]);
    final next = await repo.addEntries(<EntryDraft>[const EntryDraft(title: 'C')]);
    expect(next.single.id, 3);
    await repo.close();
  });

  test('save writes CRLF CSV, clears dirty, and roundtrips', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('save');
    saf.put(uri, 'id,title,artist\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    await repo.addEntries(<EntryDraft>[
      const EntryDraft(title: 'Hello, World', artist: 'Ann'),
    ]);
    await repo.markDirty();
    final doc = await repo.saveCsv(advanced: false);
    expect(doc.name, isNotEmpty);
    final written = utf8.decode(saf.files[uri]!);
    expect(written, startsWith('id,title,artist\r\n'));
    expect(written, contains('1,"Hello, World",Ann'));
    expect(await repo.isDirty(), isFalse);
    final decoded = MangaCatCsv.decode(saf.files[uri]!);
    expect(decoded.entries.single.title, 'Hello, World');
    await repo.close();
  });

  test('advanced toggle persists in meta and changes export', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('advanced');
    saf.put(uri, 'id,title,artist\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    await repo.addEntries(<EntryDraft>[
      const EntryDraft(title: 'Alpha', artist: 'Ann', status: EntryStatus.completed, rating: 4),
    ]);
    await repo.metaSet('advanced_mode', '1');
    final csv = await repo.exportCsv(advanced: true);
    expect(csv.split('\r\n').first, 'id,title,artist,status,rating,progress,notes');
    expect(csv, contains('completed'));
    await repo.metaSet('advanced_mode', '0');
    final simple = await repo.exportCsv(advanced: false);
    expect(simple.split('\r\n').first, 'id,title,artist');
    expect(await repo.entries(), hasLength(1));
    await repo.close();
  });

  test('delete then restore keeps the original id when free', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('restore');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    final entries = await repo.entries();
    await repo.deleteEntries(<Entry>[entries.single]);
    expect(await repo.entries(), isEmpty);
    final restored = await repo.restoreEntry(entries.single);
    expect(restored.id, 1);
    expect((await repo.entries()).single.title, 'Alpha');
    await repo.close();
  });

  test('restore uses a new id when the original is occupied', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('restore-occupied');
    saf.put(uri, 'id,title,artist\r\n1,Alpha,Ann\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    final snapshot = (await repo.entries()).single;
    await repo.deleteEntries(<Entry>[snapshot]);
    final first = await repo.restoreEntry(snapshot);
    final second = await repo.restoreEntry(snapshot);
    expect(first.id, 1);
    expect(second.id, isNot(1));
    await repo.close();
  });

  test('audit retention keeps the newest 500 records', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('audit');
    saf.put(uri, 'id,title,artist\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    final db = await WorkspaceDb.open(uri);
    for (var i = 0; i < 505; i++) {
      await db.addAudit(
        AuditRecord(
          seq: 0,
          ts: DateTime.now(),
          action: AuditAction.edit,
          entryId: i,
          summary: 'entry $i',
          snapshots: const <Entry>[],
        ),
      );
    }
    final records = await db.auditAll();
    expect(records.length, 500);
    expect(records.first.seq, 505);
    expect(records.last.seq, 6);
    await db.close();
    await repo.close();
  });

  test('batch add records one audit row', () async {
    final saf = FakeSaf();
    final uri = uniqueUri('batch');
    saf.put(uri, 'id,title,artist\r\n');
    final repo = await ListRepository.open(uri: uri, saf: saf);
    await repo.load();
    await repo.addEntries(
      <EntryDraft>[
        const EntryDraft(title: 'A'),
        const EntryDraft(title: 'B'),
        const EntryDraft(title: 'C'),
      ],
      batch: true,
    );
    final records = await repo.audit();
    expect(records.length, 1);
    expect(records.single.action, AuditAction.batchAdd);
    expect(records.single.snapshots.length, 3);
    await repo.close();
  });
}
