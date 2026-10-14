import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../data/csv_codec.dart';
import '../../data/list_repository.dart';
import '../../data/models/entry.dart';
import '../../data/saf_gateway.dart';
import '../../state/providers.dart';
import '../../state/tracker_controller.dart';
import '../history/history_screen.dart';
import '../scan/scan_screen.dart';
import 'add_entry_sheet.dart';
import 'entry_detail_sheet.dart';
import 'list_settings_sheet.dart';
import 'tracker_widgets.dart';

enum _TrackerMenu { scan, sort, showId, filters, history, save, listSettings }

class TrackerScreen extends ConsumerStatefulWidget {
  const TrackerScreen({super.key, required this.uri, required this.name});

  final String uri;
  final String name;

  @override
  ConsumerState<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends ConsumerState<TrackerScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<int> _selected = <int>{};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final controller = ref.read(trackerControllerProvider.notifier);
    try {
      final report = await controller.open(uri: widget.uri, name: widget.name);
      if (!mounted) return;
      final notices = <String>[...report.warnings];
      if (report.workspaceRebuilt) {
        notices.add('Local history was reset after a corrupt workspace.');
      }
      if (report.reloadedFromCsv) {
        notices.add('Reloaded from file.');
      }
      if (notices.isNotEmpty) {
        _snack(notices.join('\n'));
      }
      if (report.conflict) {
        await _resolveConflict();
      }
      if (!mounted) return;
      if (ref.read(settingsStoreProvider).autofocusSearch) {
        _searchFocus.requestFocus();
      }
    } on SourceMissingException {
      if (mounted) _showSourceMissing();
    } on CsvFormatException catch (error) {
      if (mounted) _showFatal(error.message);
    } on SafException catch (error) {
      if (mounted) _showFatal('Could not open the list: ${error.message}');
    }
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _snackWithUndo(String message) {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(trackerControllerProvider.notifier);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
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
  }

  Future<void> _showSourceMissing() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('File not found'),
        content: const Text(
          'The CSV could not be found. It may have been moved or deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove from recents'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (remove == true) {
      await ref.read(recentsStoreProvider).remove(widget.uri);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _showFatal(String message) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Cannot open this list'),
        content: Text(message),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => ref.read(trackerControllerProvider.notifier).setQuery(value),
    );
  }

  Future<void> _snackUndoAfter(Future<void> action, String message) async {
    await action;
    if (!mounted) return;
    _snackWithUndo(message);
  }

  Future<void> _toggleCompleted(Entry entry) async {
    await ref.read(trackerControllerProvider.notifier).toggleCompleted(entry);
    if (!mounted) return;
    _snackWithUndo(
      entry.status == EntryStatus.completed
          ? "Marked unread: '${entry.title}'"
          : "Marked completed: '${entry.title}'",
    );
  }

  Future<void> _deleteOne(Entry entry) => _snackUndoAfter(
        ref.read(trackerControllerProvider.notifier).deleteEntries(<int>[entry.id]),
        "Deleted '${entry.title}'",
      );

  Future<void> _deleteSelection() async {
    final ids = _selected.toList(growable: false);
    setState(_selected.clear);
    await _snackUndoAfter(
      ref.read(trackerControllerProvider.notifier).deleteEntries(ids),
      ids.length == 1 ? 'Deleted 1 entry' : 'Deleted ${ids.length} entries',
    );
  }

  Future<void> _setStatusForSelection(EntryStatus status) async {
    final ids = _selected.toList(growable: false);
    setState(_selected.clear);
    await _snackUndoAfter(
      ref.read(trackerControllerProvider.notifier).setStatusMany(ids, status),
      'Updated ${ids.length} ${ids.length == 1 ? 'entry' : 'entries'}',
    );
  }

  Future<void> _openDetail(Entry entry) async {
    final deleted = await showEntryDetailSheet(context, entry.id);
    if (deleted == true && mounted) {
      _snackWithUndo("Deleted '${entry.title}'");
    }
  }

  Future<void> _promptAdd(String initialTitle) async {
    final result = await showAddEntrySheet(context, initialTitle: initialTitle);
    if (result == null || !mounted) return;
    final created = await ref.read(trackerControllerProvider.notifier).addEntry(
          title: result.title,
          artist: result.artist,
          status: result.status,
        );
    if (!mounted) return;
    _debounce?.cancel();
    _search.clear();
    ref.read(trackerControllerProvider.notifier).setQuery('');
    _searchFocus.requestFocus();
    _snackWithUndo("Added '${created.title}'");
  }

  Future<void> _save() async {
    final state = ref.read(trackerControllerProvider).value;
    try {
      final doc = await ref.read(trackerControllerProvider.notifier).saveToCsv();
      if (!mounted) return;
      _snack('Saved to ${doc.name.isNotEmpty ? doc.name : state?.name ?? 'CSV'}');
    } on SafException catch (error) {
      if (mounted) _showSaveError(error.message);
    } on SourceMissingException {
      if (mounted) _showSaveError('The file could not be found.');
    }
  }

  Future<void> _showSaveError(String message) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Could not save'),
        content: Text('$message\n\nRe-pick a destination or remove this list from recents.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('Remove from recents'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('repick'),
            child: const Text('Re-pick file'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      await ref.read(recentsStoreProvider).remove(widget.uri);
      if (mounted) Navigator.of(context).maybePop();
    } else if (choice == 'repick') {
      try {
        final doc = await ref.read(trackerControllerProvider.notifier).saveToNewFile();
        if (mounted) _snack('Saved to ${doc.name}');
      } on SafException catch (error) {
        if (mounted) _showSaveError(error.message);
      }
    }
  }

  Future<void> _manualRefresh() async {
    try {
      final result = await ref.read(trackerControllerProvider.notifier).checkExternal();
      if (!mounted) return;
      switch (result) {
        case ExternalCheckResult.unchanged:
          _snack('Up to date.');
        case ExternalCheckResult.reloaded:
          _snack('Reloaded from file.');
        case ExternalCheckResult.conflict:
          await _resolveConflict();
      }
    } on SourceMissingException {
      if (mounted) _showSourceMissing();
    }
  }

  Future<void> _resolveConflict() async {
    final load = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('The CSV changed outside the app.'),
        content: const Text(
          'Load the file (external changes win) or keep your unsaved edits?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Load file'),
          ),
        ],
      ),
    );
    if (!mounted || load == null) return;
    if (load) {
      await ref.read(trackerControllerProvider.notifier).reloadFromCsv();
      if (mounted) _snack('Reloaded from file.');
    } else {
      await ref.read(trackerControllerProvider.notifier).acceptExternalState();
      if (mounted) _snack('Keeping your edits. Save to CSV to update the file.');
    }
  }

  Future<void> _showSortDialog() async {
    final controller = ref.read(trackerControllerProvider.notifier);
    final current = ref.read(trackerControllerProvider).value?.sort ?? SortPref.recent;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sort by'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: SortPref.values.map((SortPref pref) {
            return ListTile(
              dense: true,
              title: Text(pref.label),
              trailing: pref == current
                  ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 20)
                  : null,
              onTap: () {
                controller.setSort(pref);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext context) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final state = ref.watch(trackerControllerProvider).value;
          if (state == null) return const SizedBox.shrink();
          final controller = ref.read(trackerControllerProvider.notifier);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text('Status', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('All'),
                      selected: state.statusFilter == null,
                      onSelected: (_) => controller.setStatusFilter(null),
                    ),
                    for (final status in EntryStatus.values)
                      ChoiceChip(
                        label: Text(status.label),
                        selected: state.statusFilter == status,
                        onSelected: (_) => controller.setStatusFilter(status),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Read definition', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ReadFilterMode.values.map((ReadFilterMode mode) {
                    return ChoiceChip(
                      label: Text(mode.label),
                      selected: state.readFilter == mode,
                      onSelected: (_) => controller.setReadFilter(mode),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(trackerControllerProvider);
    final state = asyncState.value;
    return Scaffold(
      appBar: _buildAppBar(state),
      floatingActionButton: state != null && state.query.isEmpty
          ? FloatingActionButton(
              onPressed: () => _promptAdd(''),
              tooltip: 'Add series',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: asyncState.when(
        data: (TrackerState state) => _buildBody(state),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => _buildError(error),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(TrackerState? state) {
    if (_selected.isNotEmpty) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: <Widget>[
          PopupMenuButton<EntryStatus>(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Set status',
            onSelected: _setStatusForSelection,
            itemBuilder: (BuildContext context) => EntryStatus.values.map((EntryStatus status) {
              return PopupMenuItem<EntryStatus>(
                value: status,
                child: Row(
                  children: <Widget>[
                    StatusDot(status: status),
                    const SizedBox(width: 10),
                    Text(status.label),
                  ],
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deleteSelection,
          ),
        ],
      );
    }
    return AppBar(
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              state?.name.isNotEmpty == true ? state!.name : widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state?.dirty ?? false)
            Container(
              margin: const EdgeInsets.only(left: 8),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
      actions: <Widget>[
        PopupMenuButton<_TrackerMenu>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (menu) {
            switch (menu) {
              case _TrackerMenu.scan:
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
                );
              case _TrackerMenu.sort:
                _showSortDialog();
              case _TrackerMenu.showId:
                final shown = ref.read(trackerControllerProvider).value?.showId ?? true;
                ref.read(trackerControllerProvider.notifier).setShowId(!shown);
              case _TrackerMenu.filters:
                _showFilterSheet();
              case _TrackerMenu.history:
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
                );
              case _TrackerMenu.save:
                _save();
              case _TrackerMenu.listSettings:
                showListSettingsSheet(context, ref);
            }
          },
          itemBuilder: (BuildContext context) {
            final showId = state?.showId ?? true;
            return <PopupMenuEntry<_TrackerMenu>>[
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.scan,
                child: Text('Scan folder'),
              ),
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.sort,
                child: Text('Sort'),
              ),
              PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.showId,
                child: Row(
                  children: <Widget>[
                    const Expanded(child: Text('Show ID')),
                    if (showId)
                      const Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.filters,
                child: Text('Filters'),
              ),
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.history,
                child: Text('History'),
              ),
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.save,
                child: Text('Save to CSV'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<_TrackerMenu>(
                value: _TrackerMenu.listSettings,
                child: Text('List settings'),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildError(Object error) {
    final String message = switch (error) {
      SourceMissingException _ => 'The CSV could not be found.',
      CsvFormatException e => e.message,
      _ => 'Something went wrong while opening this list.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, color: AppColors.statusDropped, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TrackerState state) {
    final visible = ref.watch(visibleEntriesProvider);
    final query = state.query.trim();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: 'Search title or artist/studio/org',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: state.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _debounce?.cancel();
                        _search.clear();
                        ref.read(trackerControllerProvider.notifier).setQuery('');
                      },
                    ),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        _FilterChips(state: state),
        Expanded(
          child: query.isEmpty && state.entries.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _manualRefresh,
                  child: Column(
                    children: <Widget>[
                      if (query.isNotEmpty && visible.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'In your list',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      Expanded(
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: <Widget>[
                                  if (query.isEmpty) ...<Widget>[
                                    const SizedBox(height: 80),
                                    const Center(
                                      child: Text(
                                        'No entries match the filters.',
                                        style: TextStyle(color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: visible.length,
                                itemBuilder: (BuildContext context, int index) =>
                                    _row(state, visible[index]),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
        if (query.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _promptAdd(query),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'Add "$query"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.pets, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'Add your first title',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _promptAdd(''),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add title'),
          ),
        ],
      ),
    );
  }

  Widget _row(TrackerState state, Entry entry) {
    return Dismissible(
      key: ValueKey<int>(entry.id),
      background: _swipeBackground(
        alignment: Alignment.centerLeft,
        color: AppColors.statusCompleted,
        icon: Icons.check_rounded,
      ),
      secondaryBackground: _swipeBackground(
        alignment: Alignment.centerRight,
        color: AppColors.statusDropped,
        icon: Icons.delete_outline_rounded,
      ),
      confirmDismiss: (DismissDirection direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _toggleCompleted(entry);
        } else {
          await _deleteOne(entry);
        }
        return false;
      },
      child: EntryRow(
        entry: entry,
        showId: state.showId,
        advanced: state.advanced,
        selected: _selected.contains(entry.id),
        selectionMode: _selected.isNotEmpty,
        onTap: () {
          if (_selected.isNotEmpty) {
            setState(() {
              if (!_selected.remove(entry.id)) _selected.add(entry.id);
            });
          } else {
            _openDetail(entry);
          }
        },
        onLongPress: () => setState(() => _selected.add(entry.id)),
      ),
    );
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      color: color.withValues(alpha: 0.25),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: color),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(trackerControllerProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: <Widget>[
          ChoiceChip(
            label: const Text('All'),
            selected: state.statusFilter == null,
            onSelected: (_) => controller.setStatusFilter(null),
          ),
          for (final status in EntryStatus.values) ...<Widget>[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(status.label),
              selected: state.statusFilter == status,
              onSelected: (_) => controller.setStatusFilter(status),
            ),
          ],
          const SizedBox(width: 8),
          FilterChip(
            avatar: state.readFilter == ReadFilterMode.off
                ? null
                : const Icon(Icons.done_rounded, size: 16, color: Colors.white),
            label: Text(state.readFilter.label),
            selected: state.readFilter != ReadFilterMode.off,
            onSelected: (_) => controller.cycleReadFilter(),
          ),
        ],
      ),
    );
  }
}
