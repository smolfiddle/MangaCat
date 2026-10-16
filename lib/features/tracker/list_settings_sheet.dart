import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../data/models/entry.dart';
import '../../state/tracker_controller.dart';

Future<void> showListSettingsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => const ListSettingsSheet(),
  );
}

class ListSettingsSheet extends ConsumerWidget {
  const ListSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackerControllerProvider).value;
    if (state == null) return const SizedBox.shrink();
    final controller = ref.read(trackerControllerProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('List settings', style: Theme.of(context).textTheme.titleMedium),
            ),
            const _SectionHeader('Columns'),
            SwitchListTile(
              title: const Text('Advanced mode'),
              subtitle: const Text(
                'Adds status, rating, progress, and notes to the CSV',
              ),
              value: state.advanced,
              onChanged: (bool value) => _confirmAdvanced(context, controller, value),
            ),
            SwitchListTile(
              title: const Text('Show ID'),
              subtitle: const Text('Display #id on each row'),
              value: state.showId,
              onChanged: controller.setShowId,
            ),
            const _SectionHeader('Default sort'),
            for (final pref in SortPref.values)
              _ChoiceTile(
                label: pref.label,
                selected: state.sort == pref,
                onTap: () => controller.setSort(pref),
              ),
            const _SectionHeader('Default filter'),
            _ChoiceTile(
              label: 'All statuses',
              selected: state.defaultStatusFilter == null,
              onTap: () => controller.setDefaultStatusFilter(null),
            ),
            for (final status in EntryStatus.values)
              _ChoiceTile(
                label: status.label,
                selected: state.defaultStatusFilter == status,
                onTap: () => controller.setDefaultStatusFilter(status),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAdvanced(
    BuildContext context,
    TrackerController controller,
    bool value,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(value ? 'Enable advanced mode?' : 'Disable advanced mode?'),
        content: Text(
          value
              ? 'Advanced columns (status, rating, progress, notes) will be added '
                  'to the CSV on next save.'
              : 'Advanced columns will be removed from the CSV on next save. '
                  'The data stays in the local workspace and comes back when you '
                  're-enable advanced mode.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.setAdvanced(value);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
