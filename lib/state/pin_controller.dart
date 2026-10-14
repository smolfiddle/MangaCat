import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pin_service.dart';
import 'providers.dart';

sealed class PinGateState {
  const PinGateState();
}

class PinSetupRequired extends PinGateState {
  const PinSetupRequired();
}

class PinLocked extends PinGateState {
  const PinLocked({this.remaining = Duration.zero});

  final Duration remaining;
}

class PinUnlocked extends PinGateState {
  const PinUnlocked();
}

enum PinVerifyResult { ok, wrong, lockedOut }

class PinController extends Notifier<PinGateState> {
  Timer? _ticker;

  PinService get _pin => ref.read(pinServiceProvider);

  @override
  PinGateState build() {
    ref.onDispose(() => _ticker?.cancel());
    if (!_pin.hasPin) return const PinSetupRequired();
    return _lockedState();
  }

  PinLocked _lockedState() => PinLocked(remaining: _pin.remainingCooldown);

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    if (!_pin.isCoolingDown) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final locked = _lockedState();
      state = locked;
      if (locked.remaining <= Duration.zero) {
        timer.cancel();
      }
    });
  }

  Future<PinVerifyResult> verify(String pin) async {
    if (_pin.isCoolingDown) {
      _startTickerIfNeeded();
      return PinVerifyResult.lockedOut;
    }
    final bool ok = await _pin.verify(pin);
    if (ok) {
      _ticker?.cancel();
      await _pin.resetFailures();
      state = const PinUnlocked();
      return PinVerifyResult.ok;
    }
    await _pin.registerFailure();
    if (_pin.isCoolingDown) {
      _startTickerIfNeeded();
      return PinVerifyResult.lockedOut;
    }
    return PinVerifyResult.wrong;
  }

  Future<void> completeSetup(String pin) async {
    await _pin.setPin(pin);
    state = const PinUnlocked();
  }

  Future<bool> changePin({required String current, required String next}) async {
    final bool ok = await _pin.verify(current);
    if (!ok) return false;
    await _pin.setPin(next);
    return true;
  }

  void lock() {
    if (!_pin.hasPin) return;
    state = _lockedState();
    _startTickerIfNeeded();
  }
}

final NotifierProvider<PinController, PinGateState> pinControllerProvider =
    NotifierProvider<PinController, PinGateState>(PinController.new);
