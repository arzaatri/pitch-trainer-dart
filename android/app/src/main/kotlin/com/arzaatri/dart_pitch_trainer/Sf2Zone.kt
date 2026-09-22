package com.arzaatri.dart_pitch_trainer

/**
 * One playable sample region for a SoundFont instrument. Unlike the original Android app, SF2
 * parsing happens in Dart (dart_pitch_trainer's lib/sound_font.dart) so the platform channel only
 * ever hands over already-resolved zones - rootFrequency and gain arrive precomputed instead of
 * the raw rootKey/pitchCorrectionCents/attenuationCb generators.
 */
class Sf2Zone(
    val keyLo: Int,
    val keyHi: Int,
    val rootFrequency: Double,
    val gain: Double,
    val sampleRate: Int,
    val loop: Boolean,
    val loopStart: Int,
    val loopEnd: Int,
    val pcm: ShortArray,
    val retriggerSeconds: Double,
    val vibratoCapable: Boolean,
)
