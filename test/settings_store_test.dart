import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_pitch_trainer/note_utils.dart';
import 'package:dart_pitch_trainer/settings_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaultSettings enables G3-E5 and disables outside that range', () {
    final defaults = SettingsStore.defaultSettings();
    expect(defaults.length, totalNotes);
    expect(defaults[noteSlot(tones.indexOf('A'), 4)], isTrue); // A4, comfortable middle
    expect(defaults[noteSlot(tones.indexOf('C'), 6)], isFalse); // high caution
    expect(defaults[noteSlot(tones.indexOf('E'), 3)], isFalse); // low caution (E3 = 164.81Hz, below G3)
  });

  test('load returns defaults when nothing has been saved', () async {
    final loaded = await SettingsStore.load(prefKeyTuneSettings);
    expect(loaded, SettingsStore.defaultSettings());
  });

  test('save/load round-trips an arbitrary bitset via the packed hex encoding', () async {
    final active = List<bool>.filled(totalNotes, false);
    active[0] = true;
    active[totalNotes - 1] = true;
    active[17] = true;

    await SettingsStore.save(prefKeyGuessSettings, active);
    final loaded = await SettingsStore.load(prefKeyGuessSettings);

    expect(loaded, active);
  });

  test('encoding matches the original Android app format (14 bytes, hex string)', () async {
    final active = List<bool>.filled(totalNotes, false);
    active[0] = true; // bit 0 of byte 0 -> "01"
    await SettingsStore.save(prefKeyTuneSettings, active);

    final prefs = await SharedPreferences.getInstance();
    final hex = prefs.getString(prefKeyTuneSettings)!;
    expect(hex.length, 12); // 6 bytes ((totalNotes=48 + 7) ~/ 8) * 2 hex chars
    expect(hex.startsWith('01'), isTrue);
  });

  test('string and boolean preference helpers persist values', () async {
    await SettingsStore.putString(prefKeyInstrument, 'PIANO');
    expect(await SettingsStore.getString(prefKeyInstrument, 'SINE'), 'PIANO');

    await SettingsStore.putBoolean(prefKeyVibrato, true);
    expect(await SettingsStore.getBoolean(prefKeyVibrato, false), isTrue);
  });
}
