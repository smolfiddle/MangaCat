import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/settings_store.dart';
import '../../state/pin_controller.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late bool _relock = ref.read(settingsStoreProvider).relockOnBackground;
  late bool _autofocus = ref.read(settingsStoreProvider).autofocusSearch;
  late String _extensions = ref.read(settingsStoreProvider).scanExtensions.join(', ');

  Future<void> _changePin() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const _ChangePinDialog(),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN changed.')),
      );
    }
  }

  Future<void> _editExtensions() async {
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ExtensionsDialog(initial: _extensions),
    );
    if (result == null) return;
    final parsed = SettingsStore.parseExtensionInput(result);
    await ref.read(settingsStoreProvider).setScanExtensions(parsed);
    if (mounted) {
      setState(() => _extensions = parsed.join(', '));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('Change PIN'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _changePin,
          ),
          SwitchListTile(
            title: const Text('Re-lock in background'),
            subtitle: const Text('Require the PIN again when returning'),
            value: _relock,
            onChanged: (bool value) async {
              await ref.read(settingsStoreProvider).setRelockOnBackground(value);
              if (mounted) setState(() => _relock = value);
            },
          ),
          const _SectionHeader('Tracker'),
          SwitchListTile(
            title: const Text('Autofocus search'),
            subtitle: const Text('Open the keyboard when a list opens'),
            value: _autofocus,
            onChanged: (bool value) async {
              await ref.read(settingsStoreProvider).setAutofocusSearch(value);
              if (mounted) setState(() => _autofocus = value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Scan extensions'),
            subtitle: Text(_extensions),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _editExtensions,
          ),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.pets, color: AppColors.accent),
            title: Text('MangaCat'),
            subtitle: Text('v$kAppVersion · Offline by design'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'No account, no network permission, no telemetry. '
              'Your lists live in plain CSV files you choose and own.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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

class _ExtensionsDialog extends StatefulWidget {
  const _ExtensionsDialog({required this.initial});

  final String initial;

  @override
  State<_ExtensionsDialog> createState() => _ExtensionsDialogState();
}

class _ExtensionsDialogState extends State<_ExtensionsDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan extensions'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'cbz, zip, epub'),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ChangePinDialog extends ConsumerStatefulWidget {
  const _ChangePinDialog();

  @override
  ConsumerState<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<_ChangePinDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _next.text.trim();
    if (next.length < 4 || next.length > 6) {
      setState(() => _error = 'New PIN must be 4–6 digits.');
      return;
    }
    if (next != _confirm.text.trim()) {
      setState(() => _error = 'New PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(pinControllerProvider.notifier).changePin(
          current: _current.text.trim(),
          next: next,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Wrong current PIN.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _current,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Current PIN'),
            obscureText: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'New PIN (4–6 digits)'),
            obscureText: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Confirm new PIN'),
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.statusDropped, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change'),
        ),
      ],
    );
  }
}
