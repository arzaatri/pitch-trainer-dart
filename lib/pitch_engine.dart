import 'package:flutter/services.dart';

import 'sound_font.dart';

const MethodChannel _channel = MethodChannel('com.arzaatri.dart_pitch_trainer/pitch_engine');

/// Upper bound on how long a caller should ever wait on isAudible() before giving up and
/// starting the next engine anyway - a safety net in case a device never advances its playback
/// position for some reason. Better to risk a rare overlap than hang forever.
const int maxCrossfadeWaitMs = 500;

/// Dart-side handle for a native (Kotlin AudioTrack / Swift AVAudioEngine) real-time tone
/// synthesis engine. Mirrors the original Android app's PitchEngine class one-to-one: the
/// sample-accurate crossfade, vibrato, and SF2 sample playback all happen natively, off the Dart
/// VM, so a single Flutter frame hiccup can never cause an audible click.
///
/// SF2 zones are parsed in Dart ([SoundFontBank]) and shipped over the channel as already-decoded
/// data, so the native side never touches the soundfont asset directly.
class PitchEngine {
  int? _id;

  /// Must be called (and awaited) before any other method.
  Future<void> create() async {
    _id = await _channel.invokeMethod<int>('create');
  }

  int get _requireId {
    final id = _id;
    if (id == null) {
      throw StateError('PitchEngine.create() must be awaited before use');
    }
    return id;
  }

  /// Fades the tone in. See the native engine for why the underlying audio stream is created
  /// once and left running (silent) between notes rather than stopped and restarted.
  Future<void> start() => _channel.invokeMethod('start', {'id': _requireId});

  /// Fades the tone to silence but keeps the audio stream open for a click-free resume.
  Future<void> stop() => _channel.invokeMethod('stop', {'id': _requireId});

  /// Fades out and fully tears down the audio stream. Call when this engine is done for good.
  Future<void> release() => _channel.invokeMethod('release', {'id': _requireId});

  Future<void> updateFrequency(double frequency) =>
      _channel.invokeMethod('updateFrequency', {'id': _requireId, 'frequency': frequency});

  Future<void> setVibratoEnabled(bool enabled) =>
      _channel.invokeMethod('setVibratoEnabled', {'id': _requireId, 'enabled': enabled});

  Future<void> setInstrument(List<Sf2Zone> zones) => _channel.invokeMethod('setInstrument', {
        'id': _requireId,
        'zones': [for (final z in zones) _encodeZone(z)],
      });

  /// True while audio that was written earlier is still physically queued in the hardware and
  /// hasn't finished playing yet, even if the engine has already faded to silence in software -
  /// i.e. it's not yet safe for a second engine to start without the two briefly overlapping.
  Future<bool> isAudible() async =>
      (await _channel.invokeMethod<bool>('isAudible', {'id': _requireId})) ?? false;

  Map<String, Object> _encodeZone(Sf2Zone z) => {
        'keyLo': z.keyLo,
        'keyHi': z.keyHi,
        'rootFrequency': z.rootFrequency,
        'gain': z.gain,
        'sampleRate': z.sampleRate,
        'loop': z.loop,
        'loopStart': z.loopStart,
        'loopEnd': z.loopEnd,
        'pcm': z.pcm.buffer.asUint8List(z.pcm.offsetInBytes, z.pcm.lengthInBytes),
        'retriggerSeconds': z.retriggerSeconds,
        'vibratoCapable': z.vibratoCapable,
      };
}

/// Polls isAudible() instead of waiting a fixed guessed duration, since how long hardware
/// playback actually lags behind what's been written varies by device/audio route.
Future<void> waitUntilSilent(Future<bool> Function() isAudible) async {
  final deadline = DateTime.now().add(const Duration(milliseconds: maxCrossfadeWaitMs));
  while (await isAudible() && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 5));
  }
}
