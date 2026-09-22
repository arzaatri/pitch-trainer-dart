import 'package:shared_preferences/shared_preferences.dart';

import 'note_utils.dart';

const int _bytesNeeded = (totalNotes + 7) ~/ 8; // 14 bytes for 108 bits

const String prefKeyTuneSettings = 'tune_settings';
const String prefKeyGuessSettings = 'guess_settings';
const String prefKeyTuneDifficulty = 'tune_difficulty';
const String prefKeyInstrument = 'instrument';
const String prefKeyVibrato = 'vibrato_enabled';
const String _prefKeyHighPitchWarningDismissed = 'high_pitch_warning_dismissed';
const String _prefKeyLowPitchWarningDismissed = 'low_pitch_warning_dismissed';
const String _prefKeyGuessEasyMode = 'guess_easy_mode';

/// Persists the 48-slot (12 tones x 4 octaves) active-note set as a packed bitset, hex-encoded
/// into a single short SharedPreferences string instead of a note-name list. The encoding is
/// byte-for-byte identical to the original Android app's format.
class SettingsStore {
  SettingsStore._();

  /// Defaults to the comfortable middle of the range: G3-E5 inclusive.
  static List<bool> defaultSettings() =>
      List.generate(totalNotes, (slot) => !isHighCautionSlot(slot) && !isLowCautionSlot(slot));

  static Future<bool> isGuessEasyModeEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_prefKeyGuessEasyMode) ?? false;

  static Future<void> setGuessEasyModeEnabled(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(_prefKeyGuessEasyMode, enabled);

  static Future<List<bool>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final hex = prefs.getString(key);
    if (hex == null) return defaultSettings();
    return _decode(hex);
  }

  static Future<bool> isHighPitchWarningDismissed() async =>
      (await SharedPreferences.getInstance()).getBool(_prefKeyHighPitchWarningDismissed) ?? false;

  static Future<void> setHighPitchWarningDismissed(bool dismissed) async =>
      (await SharedPreferences.getInstance()).setBool(_prefKeyHighPitchWarningDismissed, dismissed);

  static Future<bool> isLowPitchWarningDismissed() async =>
      (await SharedPreferences.getInstance()).getBool(_prefKeyLowPitchWarningDismissed) ?? false;

  static Future<void> setLowPitchWarningDismissed(bool dismissed) async =>
      (await SharedPreferences.getInstance()).setBool(_prefKeyLowPitchWarningDismissed, dismissed);

  static Future<void> save(String key, List<bool> active) async =>
      (await SharedPreferences.getInstance()).setString(key, _encode(active));

  static Future<String> getString(String key, String defaultValue) async =>
      (await SharedPreferences.getInstance()).getString(key) ?? defaultValue;

  static Future<void> putString(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  static Future<bool> getBoolean(String key, bool defaultValue) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? defaultValue;

  static Future<void> putBoolean(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);

  static String _encode(List<bool> active) {
    final bytes = List<int>.filled(_bytesNeeded, 0);
    for (var slot = 0; slot < active.length; slot++) {
      if (active[slot]) {
        bytes[slot ~/ 8] |= 1 << (slot % 8);
      }
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<bool> _decode(String hex) {
    if (hex.length < _bytesNeeded * 2) return defaultSettings();
    return List.generate(totalNotes, (slot) {
      final byteIndex = slot ~/ 8;
      final byte = int.parse(hex.substring(byteIndex * 2, byteIndex * 2 + 2), radix: 16);
      return (byte & (1 << (slot % 8))) != 0;
    });
  }
}
