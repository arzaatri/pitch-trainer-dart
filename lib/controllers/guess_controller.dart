import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../note_utils.dart';
import '../pitch_engine.dart';
import '../settings_store.dart';
import '../sound_font.dart';
import '../stats_store.dart';

enum GuessFeedback { none, correct, close, wrong }

final _random = Random();

/// Direct port of the Android app's GuessViewModel.
class GuessController extends ChangeNotifier {
  final PitchEngine _engine = PitchEngine();
  bool _isPanelVisible = false;
  bool _isAppInForeground = true;
  bool _initialized = false;

  List<bool> settings = SettingsStore.defaultSettings();

  bool isPaused = false;

  int targetToneIndex = tones.indexOf('A');
  int targetOctave = 4;
  double targetFreq = 440.0;

  int guessToneIndex = tones.indexOf('C');
  int guessOctave = 4;

  bool isComplete = false;
  GuessFeedback feedback = GuessFeedback.none;
  double guessedFreq = 440.0;
  bool isShowingCorrectTone = true;

  bool isEasyMode = false;

  Instrument instrument = Instrument.sine;
  bool isVibratoEnabled = false;

  String get targetNoteName => noteLabel(targetToneIndex, targetOctave);

  /// Easy mode's letter wheel is restricted to whichever half of the chromatic scale (relative
  /// to A) the target tone falls in, so guessing still takes some listening.
  (int, int) get easyToneRange {
    final half = tones.length ~/ 2;
    return targetToneIndex < half ? (0, half) : (half, tones.length);
  }

  Future<void> init() async {
    await _engine.create();
    settings = await SettingsStore.load(prefKeyGuessSettings);
    isEasyMode = await SettingsStore.isGuessEasyModeEnabled();
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

  Future<void> _loadInstrument(Instrument instrument) async {
    final zones = await SoundFontBank.zonesFor(instrument);
    await _engine.setInstrument(zones);
  }

  void onVisible() {
    _isPanelVisible = true;
    _refreshAudio();
    _engine.updateFrequency(isComplete && !isShowingCorrectTone ? guessedFreq : targetFreq);
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

  void generateNewTask() {
    isComplete = false;
    feedback = GuessFeedback.none;
    isShowingCorrectTone = true;

    final activeSlots = [for (var i = 0; i < settings.length; i++) if (settings[i]) i];
    final slot = activeSlots.isNotEmpty
        ? activeSlots[_random.nextInt(activeSlots.length)]
        : noteSlot(tones.indexOf('A'), 4);
    targetToneIndex = toneIndexOf(slot);
    targetOctave = octaveOf(slot);
    targetFreq = frequencyOf(slot);
    _applyEasyModeConstraints();
    _engine.updateFrequency(targetFreq);
    notifyListeners();
  }

  /// In easy mode the octave wheel is locked to the target's octave, and the letter wheel is
  /// limited to whichever half of the chromatic scale the target falls in.
  void _applyEasyModeConstraints() {
    if (!isEasyMode) return;
    guessOctave = targetOctave;
    final (lo, hi) = easyToneRange;
    if (guessToneIndex < lo || guessToneIndex >= hi) guessToneIndex = lo;
  }

  void selectGuessTone(int toneIndex) {
    guessToneIndex = toneIndex;
    notifyListeners();
  }

  void selectGuessOctave(int octave) {
    guessOctave = octave;
    notifyListeners();
  }

  void submit() {
    isComplete = true;
    guessedFreq = frequencyOf(noteSlot(guessToneIndex, guessOctave));
    isShowingCorrectTone = true;
    final distance = (noteSlot(targetToneIndex, targetOctave) - noteSlot(guessToneIndex, guessOctave)).abs();
    feedback = switch (distance) {
      0 => GuessFeedback.correct,
      1 => GuessFeedback.close,
      _ => GuessFeedback.wrong,
    };
    final outcome = switch (feedback) {
      GuessFeedback.correct => GuessOutcome.correct,
      GuessFeedback.close => GuessOutcome.close,
      _ => GuessOutcome.wrong,
    };
    unawaited(StatsStore.recordGuess(targetToneIndex, targetOctave, outcome));
    _engine.updateFrequency(targetFreq);
    notifyListeners();
  }

  /// Post-submission only: switches the playing reference tone between the correct note and the
  /// note the user guessed.
  void toggleCorrectTone() {
    isShowingCorrectTone = !isShowingCorrectTone;
    _engine.updateFrequency(isShowingCorrectTone ? targetFreq : guessedFreq);
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

  void toggleEasyMode() {
    isEasyMode = !isEasyMode;
    unawaited(SettingsStore.setGuessEasyModeEnabled(isEasyMode));
    // Easy mode doesn't change which notes are reachable, just how the guess wheels behave, so
    // the in-progress target and its audio stay put; only the wheels need re-clamping.
    _applyEasyModeConstraints();
    notifyListeners();
  }

  void _persistSettings() {
    unawaited(SettingsStore.save(prefKeyGuessSettings, settings));
  }

  bool get isInitialized => _initialized;
}
