import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/text_utils.dart';
import '../../data/models/entry.dart';
import '../../data/saf_gateway.dart';
import '../../state/providers.dart';
import '../../state/tracker_controller.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanCandidate {
  _ScanCandidate({required this.name, required this.inList});

  final String name;
  final bool inList;
  bool selected = true;
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  String? _dirUri;
  String _dirName = '';
  List<_ScanCandidate> _candidates = <_ScanCandidate>[];
  bool _loading = false;
  String? _error;
  bool _hideDuplicates = false;

  Future<void> _pickDirectory() async {
    final saf = ref.read(safGatewayProvider);
    try {
      final dir = await saf.pickDirectory();
      if (dir == null) return;
      setState(() {
        _dirUri = dir.uri;
        _dirName = dir.name;
        _loading = true;
        _error = null;
      });
      await _loadChildren(dir.uri);
    } on SafException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _loadChildren(String uri) async {
    final saf = ref.read(safGatewayProvider);
    final extensions = ref.read(settingsStoreProvider).scanExtensions;
    final List<SafChild> children = await saf.listChildren(uri);
    final List<Entry> entries =
        ref.read(trackerControllerProvider).value?.entries ?? const <Entry>[];
    final existing = entries.map((Entry e) => normalizeForMatch(e.title)).toSet();

    final candidates = <_ScanCandidate>[];
    for (final child in children) {
      if (child.isDirectory) {
        candidates.add(
          _ScanCandidate(
            name: child.name,
            inList: existing.contains(normalizeForMatch(child.name)),
          ),
        );
        continue;
      }
      final lower = child.name.toLowerCase();
      final dot = lower.lastIndexOf('.');
      if (dot <= 0) continue;
      final extension = lower.substring(dot + 1);
      if (!extensions.contains(extension)) continue;
      final name = child.name.substring(0, dot);
      if (name.trim().isEmpty) continue;
      candidates.add(
        _ScanCandidate(
          name: name,
          inList: existing.contains(normalizeForMatch(name)),
        ),
      );
    }
    candidates.sort(
      (_ScanCandidate a, _ScanCandidate b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _candidates = candidates;
      _loading = false;
    });
  }

  Future<void> _import() async {
    final selected = _candidates
        .where((_ScanCandidate candidate) => candidate.selected)
        .toList(growable: false);
    if (selected.isEmpty) return;

    final duplicates = selected.where((_ScanCandidate c) => c.inList).length;
    var skipDuplicates = false;
    if (duplicates > 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Already in this list'),
          content: Text(
            '$duplicates selected ${duplicates == 1 ? 'item already exists' : 'items already exist'}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop('skip'),
              child: const Text('Skip them'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('add'),
              child: const Text('Add anyway'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      skipDuplicates = choice == 'skip';
    }

    final toAdd = selected
        .where((_ScanCandidate c) => !(skipDuplicates && c.inList))
        .toList(growable: false);
    final skipped = selected.length - toAdd.length;
    if (toAdd.isNotEmpty) {
      await ref.read(trackerControllerProvider.notifier).batchAddTitles(
            toAdd.map((_ScanCandidate c) => c.name).toList(growable: false),
          );
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${toAdd.length} · Skipped $skipped'),
        duration: const Duration(seconds: 4),
        action: toAdd.isEmpty
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  ref.read(trackerControllerProvider.notifier).undoLast();
                },
              ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _hideDuplicates
        ? _candidates.where((_ScanCandidate c) => !c.inList).toList(growable: false)
        : _candidates;
    final selectedCount =
        _candidates.where((_ScanCandidate c) => c.selected).length;
    final duplicateCount = _candidates.where((_ScanCandidate c) => c.inList).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan folder')),
      body: Column(
        children: <Widget>[
          if (_dirUri == null)
            Expanded(child: _intro())
          else ...<Widget>[
            ListTile(
              leading: const Icon(Icons.folder_open_rounded, color: AppColors.accent),
              title: Text(_dirName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_candidates.length} candidates'),
              trailing: TextButton(
                onPressed: _pickDirectory,
                child: const Text('Change'),
              ),
            ),
            if (duplicateCount > 0)
              SwitchListTile(
                dense: true,
                title: const Text('Hide items already in the list'),
                value: _hideDuplicates,
                onChanged: (bool value) => setState(() => _hideDuplicates = value),
              ),
            const Divider(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _errorView()
                      : visible.isEmpty
                          ? const Center(
                              child: Text(
                                'Nothing to import here.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (BuildContext context, int index) {
                                final candidate = visible[index];
                                return CheckboxListTile(
                                  value: candidate.selected,
                                  onChanged: (bool? value) {
                                    setState(() => candidate.selected = value ?? false);
                                  },
                                  title: Text(candidate.name),
                                  subtitle: candidate.inList
                                      ? const Text(
                                          'in list',
                                          style: TextStyle(
                                            color: AppColors.accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        )
                                      : null,
                                  controlAffinity: ListTileControlAffinity.leading,
                                );
                              },
                            ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selectedCount == 0 ? null : _import,
                    child: Text('Import $selectedCount'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _intro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.folder_copy_outlined, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Pick a folder to catalogue.\n'
              'Each subfolder and matching file becomes one entry.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickDirectory,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose folder'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.statusDropped, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, color: AppColors.statusDropped, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _pickDirectory,
              child: const Text('Re-grant folder access'),
            ),
          ],
        ),
      ),
    );
  }
}
