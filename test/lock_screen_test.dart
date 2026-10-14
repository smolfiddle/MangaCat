import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangacat/app.dart';
import 'package:mangacat/data/pin_service.dart';
import 'package:mangacat/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_saf.dart';

class FakePinService extends PinService {
  FakePinService(super.prefs);

  @override
  bool get hasPin => true;

  @override
  Future<bool> verify(String pin) async => pin == '1234';

  @override
  Future<void> setPin(String pin) async {}

  @override
  bool get isCoolingDown => false;

  @override
  Duration get remainingCooldown => Duration.zero;

  @override
  Future<void> registerFailure() async {}

  @override
  Future<void> resetFailures() async {}
}

class FakeSetupPinService extends PinService {
  FakeSetupPinService(super.prefs);

  String? _pin;

  @override
  bool get hasPin => _pin != null;

  @override
  Future<void> setPin(String pin) async {
    _pin = pin;
  }

  @override
  Future<bool> verify(String pin) async => pin == _pin;

  @override
  bool get isCoolingDown => false;

  @override
  Duration get remainingCooldown => Duration.zero;

  @override
  Future<void> registerFailure() async {}

  @override
  Future<void> resetFailures() async {}
}

void main() {
  testWidgets('lock gate rejects a wrong PIN and unlocks with the right one',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pin_hash': 'hash',
      'pin_salt': 'salt',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          safGatewayProvider.overrideWithValue(FakeSaf()),
          pinServiceProvider.overrideWith((Ref ref) => FakePinService(prefs)),
        ],
        child: const MangaCatApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);

    for (final digit in <String>['0', '0', '0', '0']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

    for (final digit in <String>['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.textContaining('No lists yet'), findsOneWidget);
  });

  testWidgets('first launch runs PIN setup before anything else',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'pin_iterations': 10});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          safGatewayProvider.overrideWithValue(FakeSaf()),
          pinServiceProvider.overrideWith((Ref ref) => FakeSetupPinService(prefs)),
        ],
        child: const MangaCatApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a 4–6 digit PIN'), findsOneWidget);
    expect(find.textContaining('No lists yet'), findsNothing);

    for (final digit in <String>['5', '5', '5', '5']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your PIN'), findsOneWidget);

    for (final digit in <String>['5', '5', '5', '5']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Create PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create PIN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No lists yet'), findsOneWidget);
  });
}
