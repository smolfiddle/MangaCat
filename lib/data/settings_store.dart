import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _kRelock = 'relock_on_background';
  static const String _kAutofocus = 'autofocus_search';
  static const String _kExtensions = 'scan_extensions';
  static const String _kGestureHint = 'gesture_hint_shown';

  bool get gestureHintShown => _prefs.getBool(_kGestureHint) ?? false;

  Future<void> markGestureHintShown() => _prefs.setBool(_kGestureHint, true);

  bool get relockOnBackground => _prefs.getBool(_kRelock) ?? false;

  Future<void> setRelockOnBackground(bool value) => _prefs.setBool(_kRelock, value);

  bool get autofocusSearch => _prefs.getBool(_kAutofocus) ?? true;

  Future<void> setAutofocusSearch(bool value) => _prefs.setBool(_kAutofocus, value);

  List<String> get scanExtensions {
    final String? raw = _prefs.getString(_kExtensions);
    if (raw == null) return kDefaultScanExtensions;
    return _parseExtensions(raw);
  }

  Future<void> setScanExtensions(List<String> extensions) =>
      _prefs.setString(_kExtensions, extensions.join(','));

  static List<String> parseExtensionInput(String raw) => _parseExtensions(raw);

  static List<String> _parseExtensions(String raw) {
    final result = raw
        .split(',')
        .map((String e) => e.trim().toLowerCase())
        .map((String e) => e.startsWith('.') ? e.substring(1) : e)
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();
    return result.isEmpty ? kDefaultScanExtensions : result;
  }
}
