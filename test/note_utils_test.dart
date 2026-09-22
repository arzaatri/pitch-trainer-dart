import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pitch_trainer/note_utils.dart';

void main() {
  // The original Kotlin formula's "-9" constant was calibrated for a C-based tone ordering
  // (C=0...A=9) but applied to the A-based `tones` list (A=0), so every note played a tritone
  // away from its label since the app's first commit. Fixed in this port: A4 genuinely = 440Hz.
  test('frequencyOf matches A4 = 440Hz reference (bug fixed vs. the original Kotlin app)', () {
    expect(frequencyOfToneOctave(tones.indexOf('A'), 4), closeTo(440.0, 1e-9));
  });

  test('frequencyOf one octave up doubles frequency', () {
    final a4 = frequencyOfToneOctave(tones.indexOf('A'), 4);
    final a5 = frequencyOfToneOctave(tones.indexOf('A'), 5);
    expect(a5, closeTo(a4 * 2, 1e-9));
  });

  test('noteSlot/toneIndexOf/octaveOf round-trip', () {
    for (var octave = octaveRangeStart; octave <= octaveRangeEnd; octave++) {
      for (var toneIndex = 0; toneIndex < tones.length; toneIndex++) {
        final slot = noteSlot(toneIndex, octave);
        expect(toneIndexOf(slot), toneIndex);
        expect(octaveOf(slot), octave);
      }
    }
  });

  test('noteSlot covers a dense 0..totalNotes-1 range', () {
    final slots = <int>{};
    for (final octave in octaveRange) {
      for (var toneIndex = 0; toneIndex < tones.length; toneIndex++) {
        slots.add(noteSlot(toneIndex, octave));
      }
    }
    expect(slots, Set.from(List.generate(totalNotes, (i) => i)));
  });

  test('displayName shows enharmonic pairs for sharps only', () {
    expect(displayName('A#'), 'A#/Bb');
    expect(displayName('A'), 'A');
  });

  test('high/low caution boundaries', () {
    expect(isHighCautionNote(tones.indexOf('F'), 5), isTrue);
    expect(isHighCautionNote(tones.indexOf('E'), 5), isFalse);
    expect(isLowCautionNote(tones.indexOf('G'), 3), isFalse);
    expect(isLowCautionNote(tones.indexOf('F#'), 3), isTrue);
  });

  // Regression coverage for a second, previously-invisible bug: `tones` used to start at A, so
  // octave numbers rolled over at A instead of C - only A/A#/B matched a piano's octave numbering,
  // and C through G# each sounded a full octave higher than their label (e.g. "C4" played real
  // C5). Reordering `tones` to the standard C-based ordering fixed it; these pin every octave-4
  // note to its real piano frequency, and pin the caution thresholds to the exact frequencies
  // their own warning text names ("F5 upward", "below G3").
  group('octave boundaries match standard piano/tuner convention', () {
    test('every octave-4 note matches its real-world frequency', () {
      const expected = {
        'C': 261.63,
        'C#': 277.18,
        'D': 293.66,
        'D#': 311.13,
        'E': 329.63,
        'F': 349.23,
        'F#': 369.99,
        'G': 392.00,
        'G#': 415.30,
        'A': 440.00,
        'A#': 466.16,
        'B': 493.88,
      };
      for (final entry in expected.entries) {
        expect(
          frequencyOfToneOctave(tones.indexOf(entry.key), 4),
          closeTo(entry.value, 0.01),
          reason: '${entry.key}4 should be ${entry.value}Hz',
        );
      }
    });

    test('high-caution threshold is exactly real F5, matching its own warning text', () {
      expect(frequencyOfToneOctave(tones.indexOf('F'), 5), closeTo(698.46, 0.01));
    });

    test('low-caution threshold is exactly real G3, matching its own warning text', () {
      expect(frequencyOfToneOctave(tones.indexOf('G'), 3), closeTo(196.00, 0.01));
    });
  });
}
