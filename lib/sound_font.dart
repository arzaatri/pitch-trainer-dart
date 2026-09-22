import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

enum Instrument {
  sine('Sine'),
  violin('Violin'),
  piano('Piano');

  final String label;
  const Instrument(this.label);
}

/// One playable sample region extracted from a .sf2 SoundFont preset: a chunk of 16-bit mono
/// PCM covering a MIDI key range, resampled at synthesis time (see the native pitch engine) to
/// hit this app's continuous, non-tempered target frequencies rather than just the pitch it was
/// recorded at.
class Sf2Zone {
  final int keyLo;
  final int keyHi;
  final int sampleRate;
  final bool loop;
  final int loopStart;
  final int loopEnd;
  final Int16List pcm;

  /// Piano samples are a struck, decaying note rather than a bowed/sustained one, so looping or
  /// holding them for as long as the user holds a note sounds wrong - instead the note is
  /// re-struck from the start this often. 0 = never (violin's natural sustain loop is used as-is).
  final double retriggerSeconds;

  /// Whether this zone is a bowed/sustained instrument it makes sense to wobble the pitch of -
  /// piano can't and doesn't get a vibrato toggle.
  final bool vibratoCapable;

  final double rootFrequency;
  final double gain;

  Sf2Zone({
    required this.keyLo,
    required this.keyHi,
    required int rootKey,
    required int pitchCorrectionCents,
    required this.sampleRate,
    required this.loop,
    required this.loopStart,
    required this.loopEnd,
    required int attenuationCb,
    required this.pcm,
    this.retriggerSeconds = 0.0,
    this.vibratoCapable = false,
  })  : rootFrequency = 440.0 * pow(2.0, (rootKey - 69 + pitchCorrectionCents / 100.0) / 12.0),
        gain = pow(10.0, -attenuationCb / 200.0).toDouble();
}

/// Lazily parses just the Violin and Piano presets out of the bundled GeneralUser GS soundfont
/// and caches the resulting zones - the rest of the ~31MB bank is never kept resident, only the
/// PCM these two presets actually reference.
class SoundFontBank {
  SoundFontBank._();

  static const String _assetName = 'assets/GeneralUserGS.sf2';
  static const int _gmPiano = 0;
  static const int _gmViolin = 40;
  static const double _pianoRetriggerSeconds = 3.0;

  static List<Sf2Zone>? _piano;
  static List<Sf2Zone>? _violin;
  static Future<List<Sf2Zone>>? _loading;

  /// Parses the asset on first call for a non-Sine instrument (a few hundred ms).
  static Future<List<Sf2Zone>> zonesFor(Instrument instrument) async {
    if (instrument == Instrument.sine) return const [];
    if (_piano == null) {
      _loading ??= _loadAndParse();
      await _loading;
    }
    return instrument == Instrument.piano ? _piano! : _violin!;
  }

  static Future<List<Sf2Zone>> _loadAndParse() async {
    final data = await rootBundle.load(_assetName);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    _piano = Sf2Parser.extractZones(bytes, _gmPiano, retriggerSeconds: _pianoRetriggerSeconds);
    _violin = Sf2Parser.extractZones(bytes, _gmViolin, vibratoCapable: true);
    return const [];
  }
}

class _Chunk {
  final String id;
  final int start;
  final int end;
  _Chunk(this.id, this.start, this.end);
}

/// Minimal reader for the subset of the SF2 RIFF format needed to pull sample-based zones out of
/// a General MIDI preset: chunk headers, the preset -> instrument -> sample generator chain, and
/// raw PCM. Modulators and envelopes aren't read (the pitch engine supplies its own fade/crossfade
/// envelope instead, and we never send velocity/controller events for them to react to).
class Sf2Parser {
  Sf2Parser._();

  static const int _genInstrument = 41;
  static const int _genKeyRange = 43;
  static const int _genAttenuation = 48;
  static const int _genCoarseTune = 51;
  static const int _genFineTune = 52;
  static const int _genSampleId = 53;
  static const int _genSampleModes = 54;
  static const int _genRootKey = 58;

  static List<_Chunk> _readChunks(ByteData buf, Uint8List bytes, int from, int to) {
    final chunks = <_Chunk>[];
    var pos = from;
    while (pos + 8 <= to) {
      final id = ascii.decode(bytes.sublist(pos, pos + 4));
      final size = buf.getInt32(pos + 4, Endian.little);
      final dataStart = pos + 8;
      chunks.add(_Chunk(id, dataStart, dataStart + size));
      pos = dataStart + size + (size & 1); // chunks are padded to an even size
    }
    return chunks;
  }

  static String _listType(Uint8List bytes, _Chunk chunk) =>
      ascii.decode(bytes.sublist(chunk.start, chunk.start + 4));

  /// Reads igen/pgen records [genLo, genHi) into oper->amount. Every generator except keyRange is
  /// a plain signed 16-bit amount; keyRange packs (lo, hi) into the low/high bytes instead, so
  /// it's left as the raw unsigned word for the caller to unpack.
  static Map<int, int> _readGens(ByteData buf, List<int> genRecords, int genLo, int genHi) {
    final gens = <int, int>{};
    for (var i = genLo; i < genHi; i++) {
      final oper = buf.getUint16(genRecords[i], Endian.little);
      final raw = buf.getUint16(genRecords[i] + 2, Endian.little);
      gens[oper] = oper == _genKeyRange ? raw : buf.getInt16(genRecords[i] + 2, Endian.little);
    }
    return gens;
  }

  static List<Sf2Zone> extractZones(
    Uint8List bytes,
    int program, {
    double retriggerSeconds = 0.0,
    bool vibratoCapable = false,
  }) {
    final buf = ByteData.sublistView(bytes);
    final top = _readChunks(buf, bytes, 12, bytes.length); // skip "RIFF" + size + "sfbk"
    final sdta = top.firstWhere((c) => c.id == 'LIST' && _listType(bytes, c) == 'sdta');
    final pdta = top.firstWhere((c) => c.id == 'LIST' && _listType(bytes, c) == 'pdta');
    final smpl = _readChunks(buf, bytes, sdta.start + 4, sdta.end).firstWhere((c) => c.id == 'smpl');
    final pdtaChunks = {
      for (final c in _readChunks(buf, bytes, pdta.start + 4, pdta.end)) c.id: c,
    };
    List<int> records(String id, int recordSize) {
      final c = pdtaChunks[id]!;
      final result = <int>[];
      for (var p = c.start; p < c.end; p += recordSize) {
        result.add(p);
      }
      return result;
    }

    // A preset's zone count is (next preset's bag index - this preset's bag index): phdr records
    // are guaranteed to be laid out with non-decreasing bag indices, and the file always has a
    // trailing terminal ("EOP") record, so "index + 1" is always safe here.
    final phdrRecords = records('phdr', 38);
    final presetIdx = phdrRecords.indexWhere(
      (r) => buf.getInt16(r + 20, Endian.little) == program && buf.getInt16(r + 22, Endian.little) == 0,
    );
    final presetBagLo = buf.getUint16(phdrRecords[presetIdx] + 24, Endian.little);
    final presetBagHi = buf.getUint16(phdrRecords[presetIdx + 1] + 24, Endian.little);
    final pbagRecords = records('pbag', 4);
    final pgenRecords = records('pgen', 4);

    int? instrumentIdx;
    for (var bagI = presetBagLo; bagI < presetBagHi; bagI++) {
      final genLo = buf.getUint16(pbagRecords[bagI], Endian.little);
      final genHi = buf.getUint16(pbagRecords[bagI + 1], Endian.little);
      final gen = _readGens(buf, pgenRecords, genLo, genHi)[_genInstrument];
      if (gen != null) {
        instrumentIdx = gen;
        break;
      }
    }

    final instRecords = records('inst', 22);
    final instBagLo = buf.getUint16(instRecords[instrumentIdx!] + 20, Endian.little);
    final instBagHi = buf.getUint16(instRecords[instrumentIdx + 1] + 20, Endian.little);
    final ibagRecords = records('ibag', 4);
    final igenRecords = records('igen', 4);
    final shdrRecords = records('shdr', 46);

    // The first instrument zone, if it has no sampleID generator of its own, sets default
    // generator values for every zone that follows it (a per-zone value still wins).
    Map<int, int> globalGens = {};
    final zones = <Sf2Zone>[];
    for (var bagI = instBagLo; bagI < instBagHi; bagI++) {
      final genLo = buf.getUint16(ibagRecords[bagI], Endian.little);
      final genHi = buf.getUint16(ibagRecords[bagI + 1], Endian.little);
      final zoneGens = _readGens(buf, igenRecords, genLo, genHi);
      final sampleId = zoneGens[_genSampleId];
      if (sampleId == null) {
        globalGens = zoneGens;
        continue;
      }
      final gens = {...globalGens, ...zoneGens};
      final shdr = shdrRecords[sampleId];
      final sampleStart = buf.getInt32(shdr + 20, Endian.little);
      final sampleEnd = buf.getInt32(shdr + 24, Endian.little);
      final loopStart = buf.getInt32(shdr + 28, Endian.little);
      final loopEnd = buf.getInt32(shdr + 32, Endian.little);
      final sampleRate = buf.getInt32(shdr + 36, Endian.little);
      final originalPitch = buf.getUint8(shdr + 40);
      final pitchCorrection = buf.getInt8(shdr + 41);

      final keyRange = gens[_genKeyRange] ?? 0x7F00; // default: whole keyboard, 0-127
      final sampleModes = gens[_genSampleModes] ?? 0;
      final pcm = Int16List(sampleEnd - sampleStart);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = buf.getInt16(smpl.start + (sampleStart + i) * 2, Endian.little);
      }

      zones.add(Sf2Zone(
        keyLo: keyRange & 0xFF,
        keyHi: (keyRange >> 8) & 0xFF,
        rootKey: gens[_genRootKey] ?? originalPitch,
        pitchCorrectionCents:
            pitchCorrection + (gens[_genCoarseTune] ?? 0) * 100 + (gens[_genFineTune] ?? 0),
        sampleRate: sampleRate,
        loop: sampleModes == 1 || sampleModes == 3,
        loopStart: loopStart - sampleStart,
        loopEnd: loopEnd - sampleStart,
        attenuationCb: gens[_genAttenuation] ?? 0,
        pcm: pcm,
        retriggerSeconds: retriggerSeconds,
        vibratoCapable: vibratoCapable,
      ));
    }
    return zones;
  }
}
