import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/audit_record.dart';
import '../../state/tracker_controller.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  AuditAction? _filter;
  List<AuditRecord> _records = <AuditRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await ref.read(trackerControllerProvider.notifier).history();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _restore(AuditRecord record) async {
    final controller = ref.read(trackerControllerProvider.notifier);
    final restored = await controller.restoreFromAudit(record);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          restored.length == 1
              ? "Restored '${restored.single.title}'"
              : 'Restored ${restored.length} entries',
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            messenger.hideCurrentSnackBar();
            controller.undoLast();
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _clearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes the audit log for this list. Entries stay untouched.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(trackerControllerProvider.notifier).clearHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == null
        ? _records
        : _records.where((AuditRecord r) => r.action == _filter).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear log',
            onPressed: _records.isEmpty ? null : _clearLog,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final action in AuditAction.values) ...<Widget>[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(action.label),
                    selected: _filter == action,
                    onSelected: (_) => setState(() => _filter = action),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No history yet.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (BuildContext context, int index) {
                          final record = filtered[index];
                          return ListTile(
                            leading: Icon(_iconFor(record.action), color: AppColors.textSecondary),
                            title: Text(record.summary, style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              formatDateTime(record.ts),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: record.action == AuditAction.delete
                                ? TextButton(
                                    onPressed: () => _restore(record),
                                    child: const Text('Restore'),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(AuditAction action) => switch (action) {
        AuditAction.add => Icons.add_circle_outline_rounded,
        AuditAction.edit => Icons.edit_outlined,
        AuditAction.delete => Icons.delete_outline_rounded,
        AuditAction.batchAdd => Icons.library_add_outlined,
        AuditAction.restore => Icons.restore_rounded,
      };
}
