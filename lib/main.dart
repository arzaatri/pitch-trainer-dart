import 'package:flutter/material.dart';

import 'controllers/guess_controller.dart';
import 'controllers/tune_controller.dart';
import 'pitch_engine.dart';
import 'screens/guess_screen.dart';
import 'screens/tune_screen.dart';
import 'sound_font.dart';
import 'theme.dart';
import 'widgets/analytics_sheet.dart';
import 'widgets/settings_sheet.dart';

void main() {
  runApp(const PitchTrainerApp());
}

class PitchTrainerApp extends StatelessWidget {
  const PitchTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pitch Trainer',
      theme: buildAppTheme(),
      home: const PitchHome(),
    );
  }
}

enum _Panel { tune, guess }

class PitchHome extends StatefulWidget {
  const PitchHome({super.key});

  @override
  State<PitchHome> createState() => _PitchHomeState();
}

class _PitchHomeState extends State<PitchHome> with WidgetsBindingObserver {
  final TuneController _tuneController = TuneController();
  final GuessController _guessController = GuessController();
  _Panel _panel = _Panel.tune;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_tuneController.init(), _guessController.init()]);
    if (!mounted) return;
    setState(() => _ready = true);
    // Kick off the initially-selected panel's audio, matching the LaunchedEffect(panel) below.
    _tuneController.onVisible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ON_STOP/ON_START equivalent: pause audio the moment the app is backgrounded (Home button,
    // app switch), not just when the widget tree is disposed.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _tuneController.onAppBackground();
      _guessController.onAppBackground();
    } else if (state == AppLifecycleState.resumed) {
      _tuneController.onAppForeground();
      _guessController.onAppForeground();
    }
  }

  Future<void> _switchPanel(_Panel panel) async {
    if (panel == _panel) return;
    setState(() => _panel = panel);
    // Fade the outgoing panel's tone all the way out - and wait for the hardware to actually
    // finish playing it, not just for the software fade to finish - before the incoming one
    // starts ramping up, so the two engines are never audible at once.
    switch (panel) {
      case _Panel.tune:
        _guessController.onHidden();
        await waitUntilSilent(_guessController.isAudible);
        _tuneController.onVisible();
      case _Panel.guess:
        _tuneController.onHidden();
        await waitUntilSilent(_tuneController.isAudible);
        _guessController.onVisible();
    }
  }

  Future<void> _showSettings() async {
    // Instrument is a single shared preference (not per Tune/Guess panel), so both controllers'
    // engines are updated together regardless of which sheet is open.
    Future<void> onSelectInstrument(Instrument instrument) async {
      await _tuneController.selectInstrument(instrument);
      await _guessController.selectInstrument(instrument);
    }

    Future<void> onToggleVibrato() async {
      await _tuneController.toggleVibrato();
      await _guessController.toggleVibrato();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ListenableBuilder(
        listenable: _panel == _Panel.tune ? _tuneController : _guessController,
        builder: (context, _) => _panel == _Panel.tune
            ? SettingsSheet(
                title: 'Tune Settings',
                active: _tuneController.settings,
                onToggleCell: _tuneController.toggleCell,
                onToggleRow: _tuneController.toggleRow,
                onToggleColumn: _tuneController.toggleColumn,
                onReset: _tuneController.resetSettings,
                instrument: _tuneController.instrument,
                onSelectInstrument: onSelectInstrument,
                isVibratoEnabled: _tuneController.isVibratoEnabled,
                onToggleVibrato: onToggleVibrato,
              )
            : SettingsSheet(
                title: 'Guess Settings',
                active: _guessController.settings,
                onToggleCell: _guessController.toggleCell,
                onToggleRow: _guessController.toggleRow,
                onToggleColumn: _guessController.toggleColumn,
                onReset: _guessController.resetSettings,
                instrument: _guessController.instrument,
                onSelectInstrument: onSelectInstrument,
                isVibratoEnabled: _guessController.isVibratoEnabled,
                onToggleVibrato: onToggleVibrato,
              ),
      ),
    );
  }

  Future<void> _showAnalytics() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _panel == _Panel.tune ? const TuneAnalyticsSheet() : const GuessAnalyticsSheet(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tuneController.onHidden();
    _guessController.onHidden();
    _tuneController.dispose();
    _guessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(backgroundColor: darkGray, body: Center(child: CircularProgressIndicator(color: accentGold)));
    }

    return Scaffold(
      backgroundColor: darkGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _panelButton('Tune', _panel == _Panel.tune, () => _switchPanel(_Panel.tune))),
                  const SizedBox(width: 8),
                  Expanded(child: _panelButton('Guess', _panel == _Panel.guess, () => _switchPanel(_Panel.guess))),
                ],
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _panel == _Panel.tune ? _tuneController : _guessController,
                builder: (context, _) => _panel == _Panel.tune ? _difficultyRow() : _guessModeRow(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _showAnalytics,
                    icon: const Icon(Icons.bar_chart, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _showSettings,
                    icon: const Icon(Icons.settings, color: Colors.white),
                  ),
                ],
              ),
              Expanded(
                child: _panel == _Panel.tune
                    ? TuneScreen(controller: _tuneController)
                    : GuessScreen(controller: _guessController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _difficultyRow() {
    return Row(
      children: [
        for (final d in Difficulty.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _modeButton(d.label, _tuneController.difficulty == d, () => _tuneController.selectDifficulty(d)),
            ),
          ),
      ],
    );
  }

  Widget _guessModeRow() {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _modeButton('Normal', !_guessController.isEasyMode, () {
              if (_guessController.isEasyMode) _guessController.toggleEasyMode();
            }),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _modeButton('Easy', _guessController.isEasyMode, () {
              if (!_guessController.isEasyMode) _guessController.toggleEasyMode();
            }),
          ),
        ),
      ],
    );
  }

  Widget _panelButton(String label, bool selected, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? accentGold : surfaceGray,
        foregroundColor: selected ? darkGray : Colors.white,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _modeButton(String label, bool selected, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? accentGold.withValues(alpha: 0.15) : Colors.transparent,
        foregroundColor: selected ? accentGold : Colors.white70,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
