import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/format.dart';
import '../../data/csv_codec.dart';
import '../../data/models/recent_list.dart';
import '../../data/saf_gateway.dart';
import '../../state/home_controller.dart';
import '../../state/providers.dart';
import '../settings/settings_screen.dart';
import '../tracker/tracker_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _openList(RecentList list) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackerScreen(uri: list.uri, name: list.name),
      ),
    );
    if (mounted) ref.read(homeControllerProvider.notifier).refresh();
  }

  Future<void> _openExisting() async {
    final saf = ref.read(safGatewayProvider);
    try {
      final doc = await saf.pickFile();
      if (doc == null) return;
      await ref.read(recentsStoreProvider).upsert(
            RecentList(
              uri: doc.uri,
              name: doc.name,
              count: 0,
              lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
              dirty: false,
            ),
          );
      if (!mounted) return;
      await _openList(
        RecentList(
          uri: doc.uri,
          name: doc.name,
          count: 0,
          lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
          dirty: false,
        ),
      );
    } on SafException catch (error) {
      if (mounted) _snack(error.message);
    }
  }

  Future<void> _createNew() async {
    final saf = ref.read(safGatewayProvider);
    try {
      final doc = await saf.createFile(suggestedName: 'MangaCat.csv');
      if (doc == null) return;
      final header = MangaCatCsv.encode(const [], advanced: false);
      await saf.writeBytes(doc.uri, Uint8List.fromList(utf8.encode(header)));
      if (!mounted) return;
      await _openList(
        RecentList(
          uri: doc.uri,
          name: doc.name.isNotEmpty ? doc.name : 'MangaCat.csv',
          count: 0,
          lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
          dirty: false,
        ),
      );
    } on SafException catch (error) {
      if (mounted) _snack(error.message);
    }
  }

  Future<void> _addSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Open existing CSV'),
              onTap: () {
                Navigator.of(context).pop();
                _openExisting();
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Create new CSV'),
              onTap: () {
                Navigator.of(context).pop();
                _createNew();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFromRecents(RecentList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove from recents?'),
        content: Text(
          'The workspace for "${list.name}" is kept and the CSV is never deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(homeControllerProvider.notifier).remove(list.uri);
    if (mounted) _snack('Removed from recents. The CSV is untouched.');
  }

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(homeControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MangaCat'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSheet,
        tooltip: 'Add list',
        child: const Icon(Icons.add_rounded),
      ),
      body: Stack(
        children: <Widget>[
          if (recents.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.pets, size: 56, color: AppColors.textSecondary),
                    SizedBox(height: 16),
                    Text(
                      'No lists yet.\nOpen or create a CSV to start your catalogue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _ContinueCard(
                    list: recents.first,
                    onTap: () => _openList(recents.first),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(
                    'All lists',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                for (final list in recents) _tile(list),
              ],
            ),
          Positioned(
            right: 8,
            bottom: 24,
            child: IgnorePointer(
              child: Text(
                'カタログ',
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(RecentList list) {
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${list.count} ${list.count == 1 ? 'entry' : 'entries'} · '
        'opened ${formatDay(DateTime.fromMillisecondsSinceEpoch(list.lastOpenedMs))}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: list.dirty
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
              ),
            )
          : null,
      onTap: () => _openList(list),
      onLongPress: () => _removeFromRecents(list),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.list, required this.onTap});

  final RecentList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.play_circle_outline_rounded, color: AppColors.accent, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Continue',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
