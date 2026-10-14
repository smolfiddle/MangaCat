import 'dart:convert';

import 'entry.dart';

enum AuditAction {
  add('add', 'Added'),
  edit('edit', 'Edited'),
  delete('delete', 'Deleted'),
  batchAdd('batch_add', 'Batch added'),
  restore('restore', 'Restored');

  const AuditAction(this.value, this.label);

  final String value;
  final String label;

  static AuditAction parse(String raw) {
    for (final action in AuditAction.values) {
      if (action.value == raw) return action;
    }
    return AuditAction.edit;
  }
}

class AuditRecord {
  const AuditRecord({
    required this.seq,
    required this.ts,
    required this.action,
    required this.entryId,
    required this.summary,
    required this.snapshots,
  });

  final int seq;
  final DateTime ts;
  final AuditAction action;
  final int? entryId;
  final String summary;
  final List<Entry> snapshots;

  Map<String, Object?> toDb() => <String, Object?>{
        'ts': ts.millisecondsSinceEpoch,
        'action': action.value,
        'entry_id': entryId,
        'snapshot_json': jsonEncode(snapshots.map((e) => e.toSnapshot()).toList()),
        'summary': summary,
      };

  factory AuditRecord.fromDb(Map<String, Object?> row) {
    final raw = row['snapshot_json'] as String?;
    final decoded = raw == null || raw.isEmpty ? const <Object?>[] : jsonDecode(raw) as List<dynamic>;
    return AuditRecord(
      seq: (row['seq'] as num).toInt(),
      ts: DateTime.fromMillisecondsSinceEpoch((row['ts'] as num).toInt()),
      action: AuditAction.parse((row['action'] as String?) ?? ''),
      entryId: (row['entry_id'] as num?)?.toInt(),
      summary: (row['summary'] as String?) ?? '',
      snapshots: decoded
          .whereType<Map<String, dynamic>>()
          .map(Entry.fromSnapshot)
          .toList(growable: false),
    );
  }
}
