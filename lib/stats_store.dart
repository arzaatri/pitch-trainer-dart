import 'package:shared_preferences/shared_preferences.dart';

import 'note_utils.dart';

const String _prefKeyTuneStats = 'tune_stats';
const String _prefKeyGuessStats = 'guess_stats';

const int _tuneFields = 5; // flat, correct, sharp, sumAbsFlatCents, sumAbsSharpCents
const int _guessFields = 3; // correct, close, wrong

enum BreakdownMode { overall, byTone, byOctave, byToneOctave }

class TuneStatsRow {
  final String label;
  final int flat;
  final int correct;
  final int sharp;
  final double avgFlatCents;
  final double avgSharpCents;

  TuneStatsRow({
    required this.label,
    required this.flat,
    required this.correct,
    required this.sharp,
    required this.avgFlatCents,
    required this.avgSharpCents,
  });
}

class GuessStatsRow {
  final String label;
  final int correct;
  final int close;
  final int wrong;

  GuessStatsRow({required this.label, required this.correct, required this.close, required this.wrong});
}

enum GuessOutcome { correct, close, wrong }

/// Aggregated (not per-event log) attempt counters, keyed by note slot (0..47). Only touched
/// slots are stored, so footprint stays tiny no matter how many attempts happen. Encoding matches
/// the original Android app's format exactly ("slot:v,v,v;slot:v,v,v;...").
class StatsStore {
  StatsStore._();

  static Future<void> recordTune(int toneIndex, int octave, int diffCents) async {
    final slot = noteSlot(toneIndex, octave);
    final stats = await _loadMap(_prefKeyTuneStats, _tuneFields);
    final row = stats.putIfAbsent(slot, () => List<int>.filled(_tuneFields, 0));
    if (diffCents < 0) {
      row[0] += 1;
      row[3] += -diffCents;
    } else if (diffCents > 0) {
      row[2] += 1;
      row[4] += diffCents;
    } else {
      row[1] += 1;
    }
    await _saveMap(_prefKeyTuneStats, stats);
  }

  static Future<void> recordGuess(int toneIndex, int octave, GuessOutcome outcome) async {
    final slot = noteSlot(toneIndex, octave);
    final stats = await _loadMap(_prefKeyGuessStats, _guessFields);
    final row = stats.putIfAbsent(slot, () => List<int>.filled(_guessFields, 0));
    switch (outcome) {
      case GuessOutcome.correct:
        row[0] += 1;
      case GuessOutcome.close:
        row[1] += 1;
      case GuessOutcome.wrong:
        row[2] += 1;
    }
    await _saveMap(_prefKeyGuessStats, stats);
  }

  static Future<List<TuneStatsRow>> tuneRows(BreakdownMode mode) async {
    final stats = await _loadMap(_prefKeyTuneStats, _tuneFields);
    switch (mode) {
      case BreakdownMode.overall:
        return [_buildTuneRow('Overall', stats.values)];
      case BreakdownMode.byTone:
        return [
          for (var toneIndex = 0; toneIndex < tones.length; toneIndex++)
            _buildTuneRow(
              displayName(tones[toneIndex]),
              stats.entries.where((e) => toneIndexOf(e.key) == toneIndex).map((e) => e.value),
            ),
        ];
      case BreakdownMode.byOctave:
        return [
          for (final octave in octaveRange)
            _buildTuneRow(
              'Octave $octave',
              stats.entries.where((e) => octaveOf(e.key) == octave).map((e) => e.value),
            ),
        ];
      case BreakdownMode.byToneOctave:
        final slots = stats.keys.toList()
          ..sort((a, b) {
            final byOctave = octaveOf(a).compareTo(octaveOf(b));
            return byOctave != 0 ? byOctave : toneIndexOf(a).compareTo(toneIndexOf(b));
          });
        return [
          for (final slot in slots)
            _buildTuneRow(noteLabel(toneIndexOf(slot), octaveOf(slot)), [stats[slot]!]),
        ];
    }
  }

  static Future<List<GuessStatsRow>> guessRows(BreakdownMode mode) async {
    final stats = await _loadMap(_prefKeyGuessStats, _guessFields);
    switch (mode) {
      case BreakdownMode.overall:
        return [_buildGuessRow('Overall', stats.values)];
      case BreakdownMode.byTone:
        return [
          for (var toneIndex = 0; toneIndex < tones.length; toneIndex++)
            _buildGuessRow(
              displayName(tones[toneIndex]),
              stats.entries.where((e) => toneIndexOf(e.key) == toneIndex).map((e) => e.value),
            ),
        ];
      case BreakdownMode.byOctave:
        return [
          for (final octave in octaveRange)
            _buildGuessRow(
              'Octave $octave',
              stats.entries.where((e) => octaveOf(e.key) == octave).map((e) => e.value),
            ),
        ];
      case BreakdownMode.byToneOctave:
        final slots = stats.keys.toList()
          ..sort((a, b) {
            final byOctave = octaveOf(a).compareTo(octaveOf(b));
            return byOctave != 0 ? byOctave : toneIndexOf(a).compareTo(toneIndexOf(b));
          });
        return [
          for (final slot in slots)
            _buildGuessRow(noteLabel(toneIndexOf(slot), octaveOf(slot)), [stats[slot]!]),
        ];
    }
  }

  static TuneStatsRow _buildTuneRow(String label, Iterable<List<int>> entries) {
    var flat = 0, correct = 0, sharp = 0, sumFlat = 0, sumSharp = 0;
    for (final e in entries) {
      flat += e[0];
      correct += e[1];
      sharp += e[2];
      sumFlat += e[3];
      sumSharp += e[4];
    }
    return TuneStatsRow(
      label: label,
      flat: flat,
      correct: correct,
      sharp: sharp,
      avgFlatCents: flat > 0 ? sumFlat / flat : 0.0,
      avgSharpCents: sharp > 0 ? sumSharp / sharp : 0.0,
    );
  }

  static GuessStatsRow _buildGuessRow(String label, Iterable<List<int>> entries) {
    var correct = 0, close = 0, wrong = 0;
    for (final e in entries) {
      correct += e[0];
      close += e[1];
      wrong += e[2];
    }
    return GuessStatsRow(label: label, correct: correct, close: close, wrong: wrong);
  }

  static Future<Map<int, List<int>>> _loadMap(String key, int fields) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final map = <int, List<int>>{};
    if (raw == null) return map;
    for (final entry in raw.split(';')) {
      if (entry.trim().isEmpty) continue;
      final parts = entry.split(':');
      if (parts.length < 2) continue;
      final slot = int.tryParse(parts[0]);
      if (slot == null) continue;
      final valuesStr = entry.substring(parts[0].length + 1);
      final values = valuesStr.split(',').map((v) => int.tryParse(v) ?? 0).toList();
      if (values.length == fields) map[slot] = values;
    }
    return map;
  }

  static Future<void> _saveMap(String key, Map<int, List<int>> map) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = map.entries.map((e) => '${e.key}:${e.value.join(',')}').join(';');
    await prefs.setString(key, encoded);
  }
}
