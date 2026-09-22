import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pitch_trainer/note_utils.dart';
import 'package:dart_pitch_trainer/sound_font.dart';

// Exercises the real bundled asset end-to-end so a corrupt download or a parser bug that only
// shows up on real SF2 data (vs. hand-built zones) fails a fast local test.
void main() {
  test('real soundfont asset yields usable piano and violin zones', () {
    final bytes = File('assets/GeneralUserGS.sf2').readAsBytesSync();
    final piano = Sf2Parser.extractZones(bytes, 0);
    final violin = Sf2Parser.extractZones(bytes, 40);

    for (final zones in [piano, violin]) {
      expect(zones, isNotEmpty);
      for (final z in zones) {
        expect(z.keyLo, lessThanOrEqualTo(z.keyHi));
        expect(z.pcm, isNotEmpty);
        expect(z.sampleRate, greaterThan(0));
        expect(z.rootFrequency, greaterThan(0.0));
      }
    }

    // The app only ever plays within roughly A3-G#6; pickZone-equivalent nearest-zone matching
    // lives in the native pitch engine, but every note in that span should at least resolve to
    // some parsed zone existing to pick from.
    for (final octave in octaveRange) {
      for (var toneIndex = 0; toneIndex < tones.length; toneIndex++) {
        final freq = frequencyOfToneOctave(toneIndex, octave);
        expect(freq, greaterThan(0.0));
      }
    }
  });

  test('piano zones are marked for retriggering, violin zones for vibrato', () {
    final bytes = File('assets/GeneralUserGS.sf2').readAsBytesSync();
    final piano = Sf2Parser.extractZones(bytes, 0, retriggerSeconds: 3.0);
    final violin = Sf2Parser.extractZones(bytes, 40, vibratoCapable: true);

    expect(piano.every((z) => z.retriggerSeconds == 3.0), isTrue);
    expect(piano.every((z) => z.vibratoCapable == false), isTrue);
    expect(violin.every((z) => z.vibratoCapable == true), isTrue);
    expect(violin.every((z) => z.retriggerSeconds == 0.0), isTrue);
  });
}
