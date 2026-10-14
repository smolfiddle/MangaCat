import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int dkLen,
) {
  final Hmac hmac = Hmac(sha256, password);
  final int blocks = (dkLen + 31) ~/ 32;
  final out = Uint8List(blocks * 32);
  final block = Uint8List(4);
  for (var b = 1; b <= blocks; b++) {
    block[0] = (b >> 24) & 0xff;
    block[1] = (b >> 16) & 0xff;
    block[2] = (b >> 8) & 0xff;
    block[3] = b & 0xff;
    var u = Uint8List.fromList(
      hmac.convert(<int>[...salt, ...block]).bytes,
    );
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.setRange((b - 1) * 32, b * 32, t);
  }
  return Uint8List.sublistView(out, 0, dkLen);
}

Uint8List _deriveInIsolate(List<Object> args) {
  return pbkdf2Sha256(
    utf8.encode(args[0] as String),
    args[1] as Uint8List,
    args[2] as int,
    32,
  );
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class PinService {
  PinService(this._prefs);

  final SharedPreferences _prefs;

  static const String _kSalt = 'pin_salt';
  static const String _kHash = 'pin_hash';
  static const String _kIterations = 'pin_iterations';
  static const String _kFailures = 'pin_failures';
  static const String _kCooldownUntil = 'pin_cooldown_until';

  static const int defaultIterations = 100000;
  static const int maxFailures = 5;
  static const Duration cooldown = Duration(seconds: 30);

  int get iterations => _prefs.getInt(_kIterations) ?? defaultIterations;

  bool get hasPin =>
      (_prefs.getString(_kHash)?.isNotEmpty ?? false) &&
      (_prefs.getString(_kSalt)?.isNotEmpty ?? false);

  Future<void> setPin(String pin) async {
    final Uint8List salt = _randomSalt();
    final Uint8List hash = await derive(pin, salt, iterations);
    await _prefs.setString(_kSalt, base64Encode(salt));
    await _prefs.setString(_kHash, base64Encode(hash));
    await _prefs.setInt(_kIterations, iterations);
    await resetFailures();
  }

  Future<bool> verify(String pin) async {
    final String? saltB64 = _prefs.getString(_kSalt);
    final String? hashB64 = _prefs.getString(_kHash);
    if (saltB64 == null || hashB64 == null) return false;
    final Uint8List derived = await derive(pin, base64Decode(saltB64), iterations);
    final Uint8List expected = base64Decode(hashB64);
    return _constantTimeEquals(derived, expected);
  }

  Future<Uint8List> derive(String pin, Uint8List salt, int iterations) {
    return compute(_deriveInIsolate, <Object>[pin, salt, iterations]);
  }

  bool get isCoolingDown => remainingCooldown > Duration.zero;

  Duration get remainingCooldown {
    final int until = _prefs.getInt(_kCooldownUntil) ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (until <= now) return Duration.zero;
    return Duration(milliseconds: until - now);
  }

  int get failures => _prefs.getInt(_kFailures) ?? 0;

  Future<void> registerFailure() async {
    final int next = failures + 1;
    if (next >= maxFailures) {
      await _prefs.setInt(
        _kCooldownUntil,
        DateTime.now().add(cooldown).millisecondsSinceEpoch,
      );
      await _prefs.setInt(_kFailures, 0);
    } else {
      await _prefs.setInt(_kFailures, next);
    }
  }

  Future<void> resetFailures() async {
    await _prefs.setInt(_kFailures, 0);
    await _prefs.remove(_kCooldownUntil);
  }

  static Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
  }
}
