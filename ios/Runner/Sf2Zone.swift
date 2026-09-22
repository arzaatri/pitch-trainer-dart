import Foundation

/// One playable sample region for a SoundFont instrument. Mirrors android/.../Sf2Zone.kt: SF2
/// parsing happens in Dart (lib/sound_font.dart), so this only ever receives already-resolved
/// zones - rootFrequency and gain arrive precomputed instead of raw SF2 generators.
struct Sf2Zone: Equatable {
    let keyLo: Int
    let keyHi: Int
    let rootFrequency: Double
    let gain: Double
    let sampleRate: Int
    let loop: Bool
    let loopStart: Int
    let loopEnd: Int
    let pcm: [Int16]

    /// Piano samples are a struck, decaying note rather than a bowed/sustained one, so looping or
    /// holding them for as long as the user holds a note sounds wrong - instead the note is
    /// re-struck from the start this often. 0 = never (violin's natural sustain loop is used as-is).
    let retriggerSeconds: Double

    /// Whether this zone is a bowed/sustained instrument it makes sense to wobble the pitch of -
    /// piano can't and doesn't get a vibrato toggle.
    let vibratoCapable: Bool
}
