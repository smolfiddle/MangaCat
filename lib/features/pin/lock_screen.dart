import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../state/pin_controller.dart';
import 'pin_pad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  int _shakeTick = 0;

  bool get _canSubmit => _pin.length >= 4 && _pin.length <= 6 && !_busy;

  void _onDigit(String digit) {
    if (_pin.length >= 6 || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    final result = await ref.read(pinControllerProvider.notifier).verify(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      switch (result) {
        case PinVerifyResult.ok:
          _error = null;
        case PinVerifyResult.wrong:
          _error = 'Wrong PIN. Try again.';
          _shakeTick++;
          HapticFeedback.heavyImpact();
        case PinVerifyResult.lockedOut:
          _error = 'Too many attempts.';
          _shakeTick++;
          HapticFeedback.heavyImpact();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(pinControllerProvider);
    final cooldown =
        gate is PinLocked ? gate.remaining : Duration.zero;
    final cooling = cooldown > Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('MangaCat', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Enter your PIN', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 32),
                Shaker(trigger: _shakeTick, child: PinDots(length: _pin.length)),
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
                          cooling
                              ? 'Too many attempts. Try again in '
                                  '${cooldown.inSeconds}s.'
                              : (_error ?? ''),
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
                  enabled: !_busy && !cooling,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _canSubmit && !cooling ? _submit : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
