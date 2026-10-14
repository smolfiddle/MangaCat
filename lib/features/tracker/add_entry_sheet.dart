import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/models/entry.dart';

class AddEntryResult {
  const AddEntryResult({required this.title, required this.artist, required this.status});

  final String title;
  final String artist;
  final EntryStatus status;
}

Future<AddEntryResult?> showAddEntrySheet(
  BuildContext context, {
  String initialTitle = '',
}) {
  return showModalBottomSheet<AddEntryResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => AddEntrySheet(initialTitle: initialTitle),
  );
}

class AddEntrySheet extends StatefulWidget {
  const AddEntrySheet({super.key, required this.initialTitle});

  final String initialTitle;

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _artistController = TextEditingController();
  EntryStatus _status = EntryStatus.none;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      AddEntryResult(
        title: title,
        artist: _artistController.text.trim(),
        status: _status,
      ),
    );
  }

  void _skipArtist() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      AddEntryResult(title: title, artist: '', status: _status),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Add title', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Title'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _artistController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Artist (optional)',
              suffixIcon: TextButton(
                onPressed: _skipArtist,
                child: const Text('Skip'),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Status', style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EntryStatus.values.map((EntryStatus status) {
              return ChoiceChip(
                label: Text(status.label),
                selected: _status == status,
                onSelected: (_) => setState(() => _status = status),
                labelStyle: TextStyle(
                  color: _status == status ? Colors.white : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppShape.chipRadius),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
