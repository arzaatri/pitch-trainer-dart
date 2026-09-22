import AVFoundation
import AudioToolbox

/// iOS counterpart to android/.../PitchEngine.kt, built on AVAudioEngine + AVAudioSourceNode
/// instead of AudioTrack (MODE_STREAM). The fade/crossfade/vibrato/retrigger math is identical
/// (see PitchEngineMath.swift) - only the platform audio plumbing differs.
///
/// UNVERIFIED ON DEVICE: this file was written on a Windows machine with no Mac/Xcode available
/// to build or run it. The logic mirrors the proven Android engine line-for-line, but two iOS-
/// specific pieces need validation on real hardware before shipping:
///   1. `isAudible()`'s AVAudioTime sample-time comparison, which stands in for Android's direct
///      `AudioTrack.playbackHeadPosition` query - AVAudioEngine has no equivalent "frames actually
///      played" API, so this approximates it via the output node's last render time plus the
///      session's reported output latency.
///   2. Whether AVAudioSession needs an explicit category/mode configuration (done once in
///      AppDelegate) to avoid being silenced by the ringer switch or interrupted by other audio.
final class PitchEngine {
    static let maxCrossfadeWaitMs: Int64 = 500

    private let sampleRate: Double = 44100
    private let fadeDurationMs: Double = 50
    private let vibratoRateHz: Double = 5.5
    private let vibratoDepthCents: Double = 30.0
    private let fadeSamples: Int

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!

    // Concurrency note: these are read/written from both the real-time audio render thread and
    // whichever thread Flutter dispatches method calls on (typically the main thread). This
    // mirrors the original Kotlin engine's reliance on @Volatile fields - a memory-visibility
    // guarantee, not a lock - rather than heavier synchronization, since the render callback must
    // never block or allocate. Swift has no direct @Volatile equivalent; plain property access
    // is used the same way here, which is standard (if informal) practice for real-time audio
    // callbacks. A torn read only ever affects a single transient audio frame, never safety.
    private var frequency: Double = 440.0
    private var pendingFrequency: Double?
    private var targetAmplitude: Double = 0.0
    private var teardownRequested = false

    private var zones: [Sf2Zone] = []
    private var pendingZones: [Sf2Zone]?
    private var currentZone: Sf2Zone?
    private var samplePos: Double = 0.0
    private var framesSinceRetrigger: Int64 = 0

    private var vibratoEnabled = false
    private var vibratoPhase: Double = 0.0

    private var phase: Double = 0.0
    private var amplitude: Double = 0.0
    private var started = false

    // Hardware-audible tracking: the AVAudioEngine equivalent of Android's
    // framesWritten/lastAudibleFrame pair, expressed in the output node's own AVAudioTime
    // sample-time domain (AudioTrack exposes a played-frame position directly; AVAudioEngine
    // doesn't, so sample time is the closest available clock to compare against).
    private var lastAudibleSampleTime: Double = 0
    private var outputLatencySamples: Double = 0

    init() {
        fadeSamples = Int(sampleRate * fadeDurationMs / 1000.0)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, timestamp, frameCount, audioBufferList in
            self?.render(frameCount: Int(frameCount), timestamp: timestamp, audioBufferList: audioBufferList) ?? noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
    }

    private func render(
        frameCount: Int,
        timestamp: UnsafePointer<AudioTimeStamp>,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let raw = abl[0].mData else { return noErr }
        let buffer = raw.assumingMemoryBound(to: Float.self)

        let fadeStep = 1.0 / Double(fadeSamples)
        let bufferStartSampleTime = timestamp.pointee.mSampleTime
        var sawAudible = false
        var lastAudibleIndex = -1

        for i in 0..<frameCount {
            let changingState = pendingFrequency != nil || pendingZones != nil
            let effectiveTarget = changingState ? 0.0 : targetAmplitude
            if amplitude < effectiveTarget {
                amplitude = min(amplitude + fadeStep, effectiveTarget)
            } else if amplitude > effectiveTarget {
                amplitude = max(amplitude - fadeStep, effectiveTarget)
            }
            if changingState && amplitude <= 0.0 {
                if let f = pendingFrequency { frequency = f; pendingFrequency = nil }
                if let z = pendingZones { zones = z; pendingZones = nil }
                currentZone = PitchEngineMath.pickZone(zones, frequency)
                samplePos = 0.0
                framesSinceRetrigger = 0
            }

            let sample: Double
            if let zone = currentZone {
                sample = PitchEngineMath.sampleAt(zone, samplePos) * amplitude
                let vibrato = PitchEngineMath.effectiveVibrato(vibratoEnabled, zone, vibratoPhase, vibratoDepthCents)
                samplePos += (frequency * vibrato / zone.rootFrequency) * (Double(zone.sampleRate) / sampleRate)
                vibratoPhase += 2.0 * .pi * vibratoRateHz / sampleRate
                if zone.loop && samplePos >= Double(zone.loopEnd) {
                    samplePos -= Double(zone.loopEnd - zone.loopStart)
                }
                // Struck/decaying instruments (piano) re-strike the note on a timer instead of
                // looping or holding forever - measured in real output frames so it's independent
                // of the pitch-dependent rate samplePos advances at.
                framesSinceRetrigger += 1
                if PitchEngineMath.shouldRetrigger(zone, framesSinceRetrigger, Int(sampleRate)) {
                    samplePos = 0.0
                    framesSinceRetrigger = 0
                }
            } else {
                sample = sin(phase) * amplitude
                phase += 2.0 * .pi * frequency / sampleRate
            }
            buffer[i] = Float(sample)
            if amplitude > 0.0001 {
                sawAudible = true
                lastAudibleIndex = i
            }
        }

        if sawAudible {
            lastAudibleSampleTime = bufferStartSampleTime + Double(lastAudibleIndex) + 1 + outputLatencySamples
        }

        if teardownRequested && pendingFrequency == nil && pendingZones == nil && amplitude <= 0.0 {
            DispatchQueue.main.async { [weak self] in self?.stopEngineIfNeeded() }
        }

        return noErr
    }

    /// Swaps the instrument the same way Android does: staged as pending and only adopted once
    /// the tone has ducked to silence, so switching instruments mid-note can't click.
    func setInstrument(_ newZones: [Sf2Zone]) {
        if newZones.isEmpty && zones.isEmpty { return }
        pendingZones = newZones
    }

    func setVibratoEnabled(_ enabled: Bool) {
        vibratoEnabled = enabled
    }

    /// See PitchEngine.kt's doc comment on the equivalent method for why this is staged as
    /// pending (ducked to silence, swapped, ramped back up) instead of applied immediately.
    func updateFrequency(_ newFreq: Double) {
        if newFreq == frequency { return }
        pendingFrequency = newFreq
    }

    /// Fades the tone in. The underlying AVAudioEngine is started once and then left running
    /// (silent) between notes, mirroring Android's "never stop/restart AudioTrack mid-session"
    /// approach to avoid an audible click each time the hardware re-engages.
    func start() {
        targetAmplitude = 1.0
        if started { return }
        started = true
        teardownRequested = false
        outputLatencySamples = AVAudioSession.sharedInstance().outputLatency * sampleRate
        try? engine.start()
    }

    /// Fades the tone to silence but keeps the audio stream open for a click-free resume.
    func stop() {
        targetAmplitude = 0.0
    }

    /// True while audio that was written earlier is still physically queued in the hardware and
    /// hasn't finished playing yet, even if we've already faded to silence in software.
    func isAudible() -> Bool {
        guard let renderTime = engine.outputNode.lastRenderTime, renderTime.isSampleTimeValid else {
            return started && targetAmplitude > 0
        }
        return renderTime.sampleTime < Int64(lastAudibleSampleTime)
    }

    /// Fades out and fully tears down the audio stream. Call when this engine is done for good.
    func release() {
        targetAmplitude = 0.0
        teardownRequested = true
        // The render callback stops the engine itself once fully silent (see the
        // teardownRequested branch above); this is a safety net in case that path is never hit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.stopEngineIfNeeded() }
    }

    private func stopEngineIfNeeded() {
        guard started else { return }
        started = false
        engine.stop()
    }
}
