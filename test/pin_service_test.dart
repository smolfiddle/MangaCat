import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangacat/data/pin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String hex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pbkdf2 matches published HMAC-SHA256 vectors', () {
    expect(
      hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1, 32)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 2, 32)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
    expect(
      hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 4096, 32)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
  });

  test('setPin and verify roundtrip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'pin_iterations': 1000});
    final prefs = await SharedPreferences.getInstance();
    final service = PinService(prefs);
    expect(service.hasPin, isFalse);
    await service.setPin('1234');
    expect(service.hasPin, isTrue);
    expect(await service.verify('1234'), isTrue);
    expect(await service.verify('9999'), isFalse);
  });

  test('cooldown after five failures, then reset', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'pin_iterations': 1000});
    final prefs = await SharedPreferences.getInstance();
    final service = PinService(prefs);
    await service.setPin('1234');
    for (var i = 0; i < 4; i++) {
      await service.registerFailure();
    }
    expect(service.isCoolingDown, isFalse);
    await service.registerFailure();
    expect(service.isCoolingDown, isTrue);
    expect(service.remainingCooldown.inSeconds, greaterThan(25));
    expect(service.failures, 0);
    await service.resetFailures();
    expect(service.isCoolingDown, isFalse);
  });

  test('iterations default to 100000', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final service = PinService(prefs);
    expect(service.iterations, 100000);
  });
}
