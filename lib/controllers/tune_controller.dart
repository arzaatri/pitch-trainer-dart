import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../note_utils.dart';
import '../pitch_engine.dart';
import '../settings_store.dart';
import '../sound_font.dart';
import '../stats_store.dart';

enum Difficulty {
  easy('Easy', 30, 5, 30),
  medium('Medium', 20, 5, 20),
  hard('Hard', 10, 10, 10);

  final String label;
  final int startStepCents;
  final int maxStartSteps;
  final int moveStepCents;
  const Difficulty(this.label, this.startStepCents, this.maxStartSteps, this.moveStepCents);
}

final _random = Random();

/// Direct port of the Android app's TuneViewModel. Mirrors its state and lifecycle handling
/// (onVisible/onHidden/onAppForeground/onAppBackground/togglePause -> refreshAudio) exactly, on
/// top of the native [PitchEngine] instead of a Kotlin AudioTrack held directly.
class TuneController extends ChangeNotifier {
  final PitchEngine _engine = PitchEngine();
  bool _isPanelVisible = false;
  bool _isAppInForeground = true;
  bool _initialized = false;

  List<bool> settings = SettingsStore.defaultSettings();

  bool isPaused = false;
  Difficulty difficulty = Difficulty.hard;
  int targetToneIndex = tones.indexOf('A');
  int targetOctave = 4;
  double targetFreq = 440.0;
  double userFreq = 440.0;
  String feedback = 'Adjust the pitch';
  bool isComplete = false;
  bool isShowingCorrectTone = true;

  Instrument instrument = Instrument.sine;
  bool isVibratoEnabled = false;

  String get targetNoteName => noteLabel(targetToneIndex, targetOctave);

  Future<void> init() async {
    await _engine.create();
    settings = await SettingsStore.load(prefKeyTuneSettings);
    final storedDifficulty = await SettingsStore.getString(prefKeyTuneDifficulty, Difficulty.hard.name);
    difficulty = Difficulty.values.firstWhere((d) => d.name == storedDifficulty, orElse: () => Difficulty.hard);
    final storedInstrument = await SettingsStore.getString(prefKeyInstrument, Instrument.sine.name);
    instrument = Instrument.values.firstWhere((i) => i.name == storedInstrument, orElse: () => Instrument.sine);
    if (instrument != Instrument.sine) unawaited(_loadInstrument(instrument));
    isVibratoEnabled = await SettingsStore.getBoolean(prefKeyVibrato, false);
    await _engine.setVibratoEnabled(isVibratoEnabled);
    _initialized = true;
    generateNewTask();
  }

  Future<void> selectInstrument(Instrument newInstrument) async {
    if (newInstrument == instrument) return;
    instrument = newInstrument;
    notifyListeners();
    await SettingsStore.putString(prefKeyInstrument, newInstrument.name);
    await _loadInstrument(newInstrument);
  }

  Future<void> toggleVibrato() async {
    isVibratoEnabled = !isVibratoEnabled;
    notifyListeners();
    await SettingsStore.putBoolean(prefKeyVibrato, isVibratoEnabled);
    await _engine.setVibratoEnabled(isVibratoEnabled);
  }

  /// Parsing the soundfont asset is only needed off the Sine default, and takes a few hundred ms,
  /// so it's kept off generateNewTask/init's critical path.
  Future<void> _loadInstrument(Instrument instrument) async {
    final zones = await SoundFontBank.zonesFor(instrument);
    await _engine.setInstrument(zones);
  }

  void onVisible() {
    _isPanelVisible = true;
    _refreshAudio();
    _engine.updateFrequency(isComplete && isShowingCorrectTone ? targetFreq : userFreq);
  }

  void onHidden() {
    _isPanelVisible = false;
    _refreshAudio();
  }

  void onAppForeground() {
    _isAppInForeground = true;
    _refreshAudio();
  }

  void onAppBackground() {
    _isAppInForeground = false;
    _refreshAudio();
  }

  void togglePause() {
    isPaused = !isPaused;
    notifyListeners();
    _refreshAudio();
  }

  void _refreshAudio() {
    if (_isPanelVisible && _isAppInForeground && !isPaused) {
      _engine.start();
    } else {
      _engine.stop();
    }
  }

  Future<bool> isAudible() => _engine.isAudible();

  @override
  void dispose() {
    _engine.release();
    super.dispose();
  }

  void selectDifficulty(Difficulty d) {
    if (d == difficulty) return;
    difficulty = d;
    unawaited(SettingsStore.putString(prefKeyTuneDifficulty, d.name));
    // The in-progress offset was generated for the old step size and may no longer be reachable
    // (e.g. 80c isn't a multiple of a 30c step), so start a fresh round. Since the abandoned round
    // was never submitted, it was never recorded to stats either.
    generateNewTask();
  }

  void generateNewTask() {
    isComplete = false;
    feedback = 'Adjust the pitch';
    isShowingCorrectTone = true;

    final activeSlots = [for (var i = 0; i < settings.length; i++) if (settings[i]) i];
    final slot = activeSlots.isNotEmpty
        ? activeSlots[_random.nextInt(activeSlots.length)]
        : noteSlot(tones.indexOf('A'), 4);
    targetToneIndex = toneIndexOf(slot);
    targetOctave = octaveOf(slot);
    targetFreq = frequencyOf(slot);

    final steps = 1 + _random.nextInt(difficulty.maxStartSteps);
    final sign = _random.nextBool() ? 1 : -1;
    final offsetCents = steps * difficulty.startStepCents * sign;
    userFreq = targetFreq * pow(2.0, offsetCents / 1200.0);
    _engine.updateFrequency(userFreq);
    notifyListeners();
  }

  void adjustPitch(int direction) {
    if (isComplete) return;
    userFreq *= pow(2.0, (direction * difficulty.moveStepCents) / 1200.0);
    _engine.updateFrequency(userFreq);
    notifyListeners();
  }

  /// Post-submission only: switches the playing reference tone between the correct note and the
  /// note the user actually tuned to.
  void toggleCorrectTone() {
    isShowingCorrectTone = !isShowingCorrectTone;
    _engine.updateFrequency(isShowingCorrectTone ? targetFreq : userFreq);
    notifyListeners();
  }

  void submit() {
    isComplete = true;
    _engine.updateFrequency(targetFreq);

    final diffCents = (1200 * log(userFreq / targetFreq) / ln2).round();
    if (diffCents == 0) {
      feedback = 'Perfect Match!';
    } else if (diffCents.abs() == difficulty.moveStepCents) {
      feedback = 'Close! You were off by $diffCents cents';
    } else {
      feedback = 'You were off by $diffCents cents';
    }
    unawaited(StatsStore.recordTune(targetToneIndex, targetOctave, diffCents));
    notifyListeners();
  }

  void nextNote() => generateNewTask();

  void toggleCell(int toneIndex, int octave) {
    final slot = noteSlot(toneIndex, octave);
    settings[slot] = !settings[slot];
    notifyListeners();
    _persistSettings();
  }

  void toggleRow(int toneIndex) {
    final slots = [for (final o in octaveRange) noteSlot(toneIndex, o)];
    final allOn = slots.every((s) => settings[s]);
    for (final s in slots) {
      settings[s] = !allOn;
    }
    notifyListeners();
    _persistSettings();
  }

  void toggleColumn(int octave) {
    final slots = [for (var t = 0; t < tones.length; t++) noteSlot(t, octave)];
    final allOn = slots.every((s) => settings[s]);
    for (final s in slots) {
      settings[s] = !allOn;
    }
    notifyListeners();
    _persistSettings();
  }

  void resetSettings() {
    settings = SettingsStore.defaultSettings();
    notifyListeners();
    _persistSettings();
  }

  void _persistSettings() {
    unawaited(SettingsStore.save(prefKeyTuneSettings, settings));
  }

  bool get isInitialized => _initialized;
}
