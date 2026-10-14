import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import 'models/audit_record.dart';
import 'models/entry.dart';

class WorkspaceDb {
  WorkspaceDb._(this.db, this.filePath);

  final Database db;
  final String filePath;

  static Future<WorkspaceDb> open(String sourceUri, {bool recreate = false}) async {
    final String dir = await getDatabasesPath();
    final String digest = sha256.convert(utf8.encode(sourceUri)).toString();
    final String path = p.join(dir, '$digest.db');
    if (recreate) {
      await deleteDatabase(path);
    }
    final Database db = await openDatabase(path, version: 1, onCreate: _onCreate);
    return WorkspaceDb._(db, path);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entries(
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'none',
        rating INTEGER NOT NULL DEFAULT 0,
        progress TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_log(
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        action TEXT NOT NULL,
        entry_id INTEGER,
        snapshot_json TEXT NOT NULL,
        summary TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  Future<List<Entry>> entriesAll() async {
    final rows = await db.query('entries', orderBy: 'id ASC');
    return rows.map(Entry.fromDb).toList(growable: false);
  }

  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor txn) action) =>
      db.transaction(action);

  Future<Entry?> entryById(int id, [DatabaseExecutor? executor]) async {
    final ex = executor ?? db;
    final rows = await ex.query('entries', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return Entry.fromDb(rows.first);
  }

  Future<int> takeNextId([DatabaseExecutor? executor]) async {
    final DatabaseExecutor ex = executor ?? db;
    final metaRows = await ex.query('meta', where: 'key = ?', whereArgs: <Object?>['next_id']);
    final maxRows = await ex.rawQuery('SELECT MAX(id) AS m FROM entries');
    final int maxId = (maxRows.first['m'] as num?)?.toInt() ?? 0;
    var next = int.tryParse(
          metaRows.isEmpty ? '' : metaRows.first['value'] as String? ?? '',
        ) ??
        0;
    if (next <= maxId) next = maxId + 1;
    await ex.insert(
      'meta',
      <String, Object?>{'key': 'next_id', 'value': '${next + 1}'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return next;
  }

  Future<void> insertEntry(Entry entry, [DatabaseExecutor? executor]) async {
    final DatabaseExecutor ex = executor ?? db;
    await ex.insert(
      'entries',
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateEntry(Entry entry, [DatabaseExecutor? executor]) async {
    final ex = executor ?? db;
    await ex.update(
      'entries',
      entry.toDb(),
      where: 'id = ?',
      whereArgs: <Object?>[entry.id],
    );
  }

  Future<void> deleteIds(Iterable<int> ids, [DatabaseExecutor? executor]) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final ex = executor ?? db;
    final placeholders = List.filled(list.length, '?').join(', ');
    await ex.delete('entries', where: 'id IN ($placeholders)', whereArgs: list);
  }

  Future<void> replaceAll(List<Entry> entries) async {
    await db.transaction((txn) async {
      await txn.delete('entries');
      for (final entry in entries) {
        await txn.insert('entries', entry.toDb());
      }
    });
  }

  Future<void> addAudit(AuditRecord record, [DatabaseExecutor? executor]) async {
    final ex = executor ?? db;
    await ex.insert('audit_log', record.toDb());
    await ex.rawDelete(
      'DELETE FROM audit_log WHERE seq <= (SELECT MAX(seq) FROM audit_log) - $kAuditRetention',
    );
  }

  Future<List<AuditRecord>> auditAll({AuditAction? action}) async {
    final rows = await db.query(
      'audit_log',
      where: action == null ? null : 'action = ?',
      whereArgs: action == null ? null : <Object?>[action.value],
      orderBy: 'seq DESC',
    );
    return rows.map(AuditRecord.fromDb).toList(growable: false);
  }

  Future<void> clearAudit() async {
    await db.delete('audit_log');
  }

  Future<String?> metaGet(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: <Object?>[key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<Map<String, String>> metaAll() async {
    final rows = await db.query('meta');
    return <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> metaSet(String key, String value) async {
    await db.insert(
      'meta',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() => db.close();
}
