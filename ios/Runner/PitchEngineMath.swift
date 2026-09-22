import Foundation

/// Pure synthesis math, ported 1:1 from android/.../PitchEngine.kt's top-level functions so the
/// two native engines stay behaviorally identical. Kept free of AVFoundation types so it's plain,
/// easily-inspected arithmetic - the only place that can differ between platforms is how the
/// audio callback itself is wired up (AVAudioSourceNode here vs. AudioTrack on Android).
enum PitchEngineMath {
    /// Nearest zone (by key-range distance) to the target frequency - always returns a zone if
    /// the list is non-empty, even for a frequency that falls outside every zone's key range.
    static func pickZone(_ zones: [Sf2Zone], _ frequency: Double) -> Sf2Zone? {
        guard !zones.isEmpty else { return nil }
        let key = 69 + 12 * log2(frequency / 440.0)
        return zones.min { a, b in
            distance(key, a) < distance(key, b)
        }
    }

    private static func distance(_ key: Double, _ zone: Sf2Zone) -> Double {
        let clamped = min(max(key, Double(zone.keyLo)), Double(zone.keyHi))
        return abs(key - clamped)
    }

    /// Linear-interpolated read of one sample from a zone's PCM at a fractional frame position,
    /// scaled by the zone's stored gain. Reading past the end (a non-looping zone that's
    /// finished) yields silence rather than garbage.
    static func sampleAt(_ zone: Sf2Zone, _ position: Double) -> Double {
        let idx = Int(position)
        let frac = position - Double(idx)
        let s0 = idx >= 0 && idx < zone.pcm.count ? Double(zone.pcm[idx]) : 0.0
        let s1 = idx + 1 >= 0 && idx + 1 < zone.pcm.count ? Double(zone.pcm[idx + 1]) : s0
        return (s0 + (s1 - s0) * frac) / 32768.0 * zone.gain
    }

    /// Whether a struck/decaying zone (piano) has been sustained long enough to re-strike it.
    /// Framed in real output frames, not the zone's own (pitch-dependent) sample-advance rate, so
    /// the note re-strikes on a wall-clock timer regardless of which pitch it's playing.
    static func shouldRetrigger(_ zone: Sf2Zone, _ framesSinceRetrigger: Int64, _ sampleRateOut: Int) -> Bool {
        zone.retriggerSeconds > 0.0 && Double(framesSinceRetrigger) >= zone.retriggerSeconds * Double(sampleRateOut)
    }

    /// Multiplier to apply to a zone's playback rate for a sine-LFO vibrato at the given phase
    /// and depth (in cents) - 1.0 (no change) at phase 0, swinging up to depthCents above/below.
    static func vibratoMultiplier(_ phase: Double, _ depthCents: Double) -> Double {
        pow(2.0, depthCents / 1200.0 * sin(phase))
    }

    /// The vibrato multiplier actually applied to a zone's playback rate: exactly 1.0 (no effect
    /// whatsoever) unless vibrato is both turned on AND the zone supports it (piano never does,
    /// regardless of the toggle).
    static func effectiveVibrato(_ vibratoEnabled: Bool, _ zone: Sf2Zone, _ phase: Double, _ depthCents: Double) -> Double {
        vibratoEnabled && zone.vibratoCapable ? vibratoMultiplier(phase, depthCents) : 1.0
    }
}
