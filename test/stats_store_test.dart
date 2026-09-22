import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_pitch_trainer/note_utils.dart';
import 'package:dart_pitch_trainer/stats_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordTune buckets flat/correct/sharp and accumulates cent totals', () async {
    await StatsStore.recordTune(tones.indexOf('A'), 4, -10);
    await StatsStore.recordTune(tones.indexOf('A'), 4, -20);
    await StatsStore.recordTune(tones.indexOf('A'), 4, 5);
    await StatsStore.recordTune(tones.indexOf('A'), 4, 0);

    final rows = await StatsStore.tuneRows(BreakdownMode.overall);
    expect(rows.length, 1);
    expect(rows.first.flat, 2);
    expect(rows.first.correct, 1);
    expect(rows.first.sharp, 1);
    expect(rows.first.avgFlatCents, closeTo(15.0, 1e-9));
    expect(rows.first.avgSharpCents, closeTo(5.0, 1e-9));
  });

  test('recordGuess buckets by outcome', () async {
    await StatsStore.recordGuess(tones.indexOf('C'), 4, GuessOutcome.correct);
    await StatsStore.recordGuess(tones.indexOf('C'), 4, GuessOutcome.close);
    await StatsStore.recordGuess(tones.indexOf('C'), 4, GuessOutcome.wrong);
    await StatsStore.recordGuess(tones.indexOf('C'), 4, GuessOutcome.wrong);

    final rows = await StatsStore.guessRows(BreakdownMode.overall);
    expect(rows.single.correct, 1);
    expect(rows.single.close, 1);
    expect(rows.single.wrong, 2);
  });

  test('byTone/byOctave breakdowns only aggregate matching slots', () async {
    await StatsStore.recordGuess(tones.indexOf('A'), 4, GuessOutcome.correct);
    await StatsStore.recordGuess(tones.indexOf('A'), 5, GuessOutcome.wrong);
    await StatsStore.recordGuess(tones.indexOf('C'), 4, GuessOutcome.close);

    final byTone = await StatsStore.guessRows(BreakdownMode.byTone);
    final aRow = byTone[tones.indexOf('A')];
    expect(aRow.correct, 1);
    expect(aRow.wrong, 1);
    expect(aRow.close, 0);

    final byOctave = await StatsStore.guessRows(BreakdownMode.byOctave);
    final octave4Row = byOctave[octaveRange.indexOf(4)];
    expect(octave4Row.correct, 1);
    expect(octave4Row.close, 1);
  });

  test('persisted encoding matches the original "slot:v,v,v;..." format', () async {
    await StatsStore.recordGuess(tones.indexOf('A'), 4, GuessOutcome.correct);
    final slot = noteSlot(tones.indexOf('A'), 4);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('guess_stats'), '$slot:1,0,0');
  });
}
