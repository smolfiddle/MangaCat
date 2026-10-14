import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pin_service.dart';
import '../data/recents_store.dart';
import '../data/saf_gateway.dart';
import '../data/settings_store.dart';

final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => throw StateError('sharedPreferencesProvider must be overridden'),
);

final Provider<SafGateway> safGatewayProvider = Provider<SafGateway>(
  (Ref ref) => throw StateError('safGatewayProvider must be overridden'),
);

final Provider<PinService> pinServiceProvider = Provider<PinService>(
  (Ref ref) => PinService(ref.watch(sharedPreferencesProvider)),
);

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

final Provider<RecentsStore> recentsStoreProvider = Provider<RecentsStore>(
  (Ref ref) => RecentsStore(ref.watch(sharedPreferencesProvider)),
);
