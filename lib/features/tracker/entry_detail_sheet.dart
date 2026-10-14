import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/models/entry.dart';
import '../../state/tracker_controller.dart';
import 'tracker_widgets.dart';

Future<bool?> showEntryDetailSheet(BuildContext context, int entryId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => EntryDetailSheet(entryId: entryId),
  );
}

class EntryDetailSheet extends ConsumerStatefulWidget {
  const EntryDetailSheet({super.key, required this.entryId});

  final int entryId;

  @override
  ConsumerState<EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends ConsumerState<EntryDetailSheet> {
  Entry? _entry;
  Timer? _debounce;
  late final TextEditingController _title = TextEditingController();
  late final TextEditingController _artist = TextEditingController();
  late final TextEditingController _progress = TextEditingController();
  late final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(trackerControllerProvider).value;
    for (final entry in state?.entries ?? const <Entry>[]) {
      if (entry.id == widget.entryId) {
        _entry = entry;
        break;
      }
    }
    final entry = _entry;
    if (entry != null) {
      _title.text = entry.title;
      _artist.text = entry.artist;
      _progress.text = entry.progress;
      _notes.text = entry.notes;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _artist.dispose();
    _progress.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _advanced =>
      ref.read(trackerControllerProvider).value?.advanced ?? false;

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _save);
  }

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null) return;
    final next = entry.copyWith(
      title: _title.text.trim().isEmpty ? entry.title : _title.text.trim(),
      artist: _artist.text.trim(),
      progress: _progress.text,
      notes: _notes.text,
      updatedAt: DateTime.now(),
    );
    _entry = next;
    await ref.read(trackerControllerProvider.notifier).updateEntry(next);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _delete() async {
    final entry = _entry;
    if (entry == null) return;
    await ref.read(trackerControllerProvider.notifier).deleteEntries(<int>[entry.id]);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _title,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => _scheduleSave(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _artist,
              decoration: const InputDecoration(labelText: 'Artist'),
              onChanged: (_) => _scheduleSave(),
            ),
            if (_advanced) ...<Widget>[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Status', style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EntryStatus.values.map((EntryStatus status) {
                  final selected = entry.status == status;
                  return ChoiceChip(
                    label: Text(status.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _entry = entry.copyWith(status: status);
                      });
                      _save();
                    },
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Rating', style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: RatingStars(
                  rating: entry.rating,
                  onChanged: (int rating) {
                    setState(() {
                      _entry = entry.copyWith(rating: rating);
                    });
                    _save();
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _progress,
                maxLength: kProgressMaxChars,
                decoration: const InputDecoration(
                  labelText: 'Progress',
                  hintText: 'e.g. ch. 143',
                ),
                onChanged: (_) => _scheduleSave(),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _notes,
                maxLength: kNotesMaxChars,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
                onChanged: (_) => _scheduleSave(),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Created ${formatDateTime(entry.createdAt)}\n'
              'Updated ${formatDateTime(entry.updatedAt)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.statusDropped),
              label: const Text(
                'Delete entry',
                style: TextStyle(color: AppColors.statusDropped),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
