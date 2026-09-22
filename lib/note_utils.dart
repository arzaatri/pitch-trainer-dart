import 'dart:math';

// DEVIATION FROM THE ANDROID APP: the original Kotlin TONES list started at A. Combined with the
// "-9" in the original frequency formula (see frequencyOfToneOctave below), that meant octave
// numbers rolled over at A instead of C, so only A/A#/B matched a piano's octave numbering - C
// through G# all sounded a full octave higher than their label (e.g. the app's "C4" played real
// C5, 523.25Hz, not 261.63Hz). Reordered here to the standard C-based ordering so octave
// boundaries land where every piano/tuner puts them, matching frequencyOfToneOctave's formula
// (which turns out to be the correct standard scientific-pitch-notation formula all along, just
// calibrated for this ordering) and the high/low caution thresholds' own "F5"/"G3" wording below.
const List<String> tones = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

// Restricted to 3-6: outside this range the synthesized tone is unpleasant to listen to.
const int octaveRangeStart = 3;
const int octaveRangeEnd = 6; // inclusive
const int octaveCount = 4; // octaveRangeEnd - octaveRangeStart + 1
const int totalNotes = 12 * octaveCount; // 48

/// Iterable octave range (3, 4, 5, 6), mirroring Kotlin's OCTAVE_RANGE for loop use.
const List<int> octaveRange = [3, 4, 5, 6];

const Map<String, String> _displayNames = {
  'A#': 'A#/Bb',
  'C#': 'C#/Db',
  'D#': 'D#/Eb',
  'F#': 'F#/Gb',
  'G#': 'G#/Ab',
};

String displayName(String tone) => _displayNames[tone] ?? tone;

/// Flat index 0..(totalNotes-1) encoding a (tone, octave) pair, relative to the octave range's
/// floor so the storage array stays densely packed regardless of where the range starts.
int noteSlot(int toneIndex, int octave) => (octave - octaveRangeStart) * 12 + toneIndex;

int toneIndexOf(int slot) => slot % 12;
int octaveOf(int slot) => slot ~/ 12 + octaveRangeStart;

/// Standard scientific-pitch-notation formula: `toneIndex` is C-based (C=0,...,B=11, see `tones`
/// above), "-9" is A's position in that ordering, and octave 4 is anchored so A4 = 440Hz. This is
/// the original Kotlin app's exact formula - it was already correct, just paired with the wrong
/// (A-based) tone ordering there. See `tones`'s doc comment for the bug this fixes.
double frequencyOfToneOctave(int toneIndex, int octave) {
  final n = toneIndex - 9 + (octave - 4) * 12;
  return 440.0 * pow(2.0, n / 12.0);
}

double frequencyOf(int slot) => frequencyOfToneOctave(toneIndexOf(slot), octaveOf(slot));

String noteLabel(int toneIndex, int octave) => '${displayName(tones[toneIndex])}$octave';

/// F5 and everything above it is high-pitched enough to be unpleasant to listen to.
bool isHighCautionNote(int toneIndex, int octave) =>
    octave > 5 || (octave == 5 && toneIndex >= tones.indexOf('F'));

bool isHighCautionSlot(int slot) => isHighCautionNote(toneIndexOf(slot), octaveOf(slot));

/// Below G3 can be difficult to hear clearly on some device speakers.
bool isLowCautionNote(int toneIndex, int octave) =>
    octave < 3 || (octave == 3 && toneIndex < tones.indexOf('G'));

bool isLowCautionSlot(int slot) => isLowCautionNote(toneIndexOf(slot), octaveOf(slot));
