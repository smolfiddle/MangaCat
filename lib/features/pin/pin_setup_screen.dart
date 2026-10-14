import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../state/pin_controller.dart';
import 'pin_pad.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  String _first = '';
  bool _confirming = false;
  String? _error;
  bool _busy = false;

  bool get _canSubmit => _pin.length >= 4 && _pin.length <= 6 && !_busy;

  void _onDigit(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
        _error = null;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _error = 'PINs do not match. Start again.';
        _pin = '';
        _first = '';
        _confirming = false;
      });
      return;
    }
    setState(() => _busy = true);
    await ref.read(pinControllerProvider.notifier).completeSetup(_pin);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.pets, size: 48, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('MangaCat', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  _confirming ? 'Confirm your PIN' : 'Choose a 4–6 digit PIN',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                Shaker(trigger: _error ?? '', child: PinDots(length: _pin.length)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 20,
                  child: _busy
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          _error ?? '',
                          style: const TextStyle(
                            color: AppColors.statusDropped,
                            fontSize: 13,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                PinKeypad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  enabled: !_busy,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShape.chipRadius),
                    ),
                  ),
                  child: Text(_confirming ? 'Create PIN' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
