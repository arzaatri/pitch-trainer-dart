package com.arzaatri.dart_pitch_trainer

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.*

/** Nearest zone (by key-range distance) to the target frequency - always returns a zone if the
 * list is non-empty, even for a frequency that falls outside every zone's key range. */
internal fun pickZone(zones: List<Sf2Zone>, frequency: Double): Sf2Zone? {
    if (zones.isEmpty()) return null
    val key = 69 + 12 * log2(frequency / 440.0)
    return zones.minByOrNull { z -> abs(key - key.coerceIn(z.keyLo.toDouble(), z.keyHi.toDouble())) }
}

/** Linear-interpolated read of one sample from a zone's PCM at a fractional frame position,
 * scaled by the zone's stored gain. Reading past the end (a non-looping zone that's finished)
 * yields silence rather than garbage. */
internal fun sampleAt(zone: Sf2Zone, position: Double): Float {
    val idx = position.toInt()
    val frac = position - idx
    val s0 = zone.pcm.getOrElse(idx) { 0 }
    val s1 = zone.pcm.getOrElse(idx + 1) { s0 }
    return ((s0 + (s1 - s0) * frac) / 32768.0 * zone.gain).toFloat()
}

/** Whether a struck/decaying zone (piano) has been sustained long enough to re-strike it. Framed
 * in real output frames, not the zone's own (pitch-dependent) sample-advance rate, so the note
 * re-strikes on a wall-clock timer regardless of which pitch it's playing. */
internal fun shouldRetrigger(zone: Sf2Zone, framesSinceRetrigger: Long, sampleRateOut: Int): Boolean =
    zone.retriggerSeconds > 0.0 && framesSinceRetrigger >= zone.retriggerSeconds * sampleRateOut

/** Multiplier to apply to a zone's playback rate for a sine-LFO vibrato at the given phase and
 * depth (in cents) - 1.0 (no change) at phase 0, swinging up to depthCents above/below that. */
internal fun vibratoMultiplier(phase: Double, depthCents: Double): Double = 2.0.pow(depthCents / 1200.0 * sin(phase))

/** The vibrato multiplier actually applied to a zone's playback rate: exactly 1.0 (no effect
 * whatsoever) unless vibrato is both turned on AND the zone supports it (piano never does,
 * regardless of the toggle). */
internal fun effectiveVibrato(vibratoEnabled: Boolean, zone: Sf2Zone, phase: Double, depthCents: Double): Double =
    if (vibratoEnabled && zone.vibratoCapable) vibratoMultiplier(phase, depthCents) else 1.0

class PitchEngine {
    companion object {
        private const val SAMPLE_RATE = 44100
        private const val FADE_DURATION_MS = 50L
        private const val VIBRATO_RATE_HZ = 5.5
        private const val VIBRATO_DEPTH_CENTS = 30.0

        /** Upper bound on how long a caller should ever wait on isAudible() before giving up and
         * starting the next engine anyway - a safety net in case a device never advances
         * playbackHeadPosition for some reason. Better to risk a rare overlap than hang forever. */
        const val MAX_CROSSFADE_WAIT_MS = 500L
    }

    private val fadeSamples = ((SAMPLE_RATE * FADE_DURATION_MS) / 1000L).toInt()

    @Volatile private var frequency = 440.0
    @Volatile private var pendingFrequency: Double? = null
    @Volatile private var targetAmplitude = 0.0
    @Volatile private var teardownRequested = false
    private var playerThread: Thread? = null

    // Empty = plain sine (the original behavior). Swapped the same way as frequency - staged as
    // pending and only adopted once the tone has ducked to silence, so switching instruments
    // mid-note can't click the same way an instant frequency jump would.
    @Volatile private var zones: List<Sf2Zone> = emptyList()
    @Volatile private var pendingZones: List<Sf2Zone>? = null
    private var currentZone: Sf2Zone? = null
    private var samplePos = 0.0
    private var framesSinceRetrigger = 0L

    // Not staged as pending like frequency/instrument - it's a continuous rate modulation, so
    // toggling it produces at most a smooth pitch drift, not a waveform-value discontinuity.
    @Volatile private var vibratoEnabled = false
    private var vibratoPhase = 0.0

    fun setInstrument(newZones: List<Sf2Zone>) {
        if (newZones == zones) return
        pendingZones = newZones
    }

    fun setVibratoEnabled(enabled: Boolean) {
        vibratoEnabled = enabled
    }

    // AudioTrack (MODE_STREAM) buffers several already-written frames ahead of what's actually
    // reaching the speaker, and how far ahead varies by device/audio route - a fixed estimated
    // gap isn't reliable. So instead we track exactly which frame was the last audible one, and
    // isAudible() compares that against the hardware's real playback position, so callers know
    // precisely (not approximately) when it's safe to start a second engine.
    @Volatile private var framesWritten = 0L
    @Volatile private var lastAudibleFrame = 0L

    private val audioTrack = AudioTrack.Builder()
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
        .setAudioFormat(AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
        .setBufferSizeInBytes(AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT))
        .setTransferMode(AudioTrack.MODE_STREAM).build()

    /**
     * Changing `frequency` outright while the tone is audible would leave amplitude continuous
     * but make the sine's slope jump instantly at that sample - audible as a click/blip even
     * though there's no amplitude discontinuity. So instead of writing `frequency` directly, hand
     * the new value to the playback thread as pending: it ducks amplitude to 0, swaps the
     * frequency while silent (inaudible - it's being multiplied by zero), then ramps back up to
     * whatever amplitude it's supposed to be at. If already silent this settles in one sample.
     */
    fun updateFrequency(newFreq: Double) {
        if (newFreq == frequency) return
        pendingFrequency = newFreq
    }

    /**
     * Fades the tone in. The underlying AudioTrack/thread is created once and then left running
     * (silent) between notes - repeatedly calling AudioTrack.play()/stop() is what produced an
     * audible click, since each call re-engages the device's audio hardware. Callers that switch
     * between two PitchEngines (e.g. the Tune/Guess panels) should wait until the other engine's
     * isAudible() goes false before calling this, so the two never overlap.
     */
    fun start() {
        targetAmplitude = 1.0
        if (playerThread != null) return

        teardownRequested = false
        audioTrack.play()
        playerThread = Thread {
            var phase = 0.0
            var amplitude = 0.0
            val fadeStep = 1.0 / fadeSamples

            while (true) {
                val buffer = FloatArray(512)
                for (i in buffer.indices) {
                    val changingState = pendingFrequency != null || pendingZones != null
                    val effectiveTarget = if (changingState) 0.0 else targetAmplitude
                    amplitude = when {
                        amplitude < effectiveTarget -> (amplitude + fadeStep).coerceAtMost(effectiveTarget)
                        amplitude > effectiveTarget -> (amplitude - fadeStep).coerceAtLeast(effectiveTarget)
                        else -> amplitude
                    }
                    if (changingState && amplitude <= 0.0) {
                        pendingFrequency?.let { frequency = it; pendingFrequency = null }
                        pendingZones?.let { zones = it; pendingZones = null }
                        currentZone = pickZone(zones, frequency)
                        samplePos = 0.0
                        framesSinceRetrigger = 0L
                    }
                    val zone = currentZone
                    if (zone == null) {
                        buffer[i] = (sin(phase) * amplitude).toFloat()
                        phase += 2.0 * PI * frequency / SAMPLE_RATE
                    } else {
                        buffer[i] = sampleAt(zone, samplePos) * amplitude.toFloat()
                        val vibrato = effectiveVibrato(vibratoEnabled, zone, vibratoPhase, VIBRATO_DEPTH_CENTS)
                        samplePos += (frequency * vibrato / zone.rootFrequency) * (zone.sampleRate.toDouble() / SAMPLE_RATE)
                        vibratoPhase += 2.0 * PI * VIBRATO_RATE_HZ / SAMPLE_RATE
                        if (zone.loop && samplePos >= zone.loopEnd) samplePos -= (zone.loopEnd - zone.loopStart)
                        // Struck/decaying instruments (piano) re-strike the note on a timer
                        // instead of looping or holding forever - measured in real output frames
                        // so it's independent of the pitch-dependent rate samplePos advances at.
                        framesSinceRetrigger++
                        if (shouldRetrigger(zone, framesSinceRetrigger, SAMPLE_RATE)) {
                            samplePos = 0.0
                            framesSinceRetrigger = 0L
                        }
                    }
                    framesWritten++
                    if (amplitude > 0.0001) lastAudibleFrame = framesWritten
                }
                audioTrack.write(buffer, 0, buffer.size, AudioTrack.WRITE_BLOCKING)
                if (teardownRequested && pendingFrequency == null && pendingZones == null && amplitude <= 0.0) break
            }
            audioTrack.stop()
        }.also { it.start() }
    }

    /** Fades the tone to silence but keeps the audio stream open for a click-free resume. */
    fun stop() { targetAmplitude = 0.0 }

    /** True while audio that was written earlier is still physically queued in the hardware and
     * hasn't finished playing yet, even if we've already faded to silence in software - i.e. it's
     * not yet safe for a second engine to start without the two briefly overlapping in the speaker. */
    fun isAudible(): Boolean {
        val playedFrames = audioTrack.playbackHeadPosition.toLong() and 0xFFFFFFFFL
        return playedFrames < lastAudibleFrame
    }

    /** Fades out and fully tears down the audio stream. Call when this engine is done for good. */
    fun release() {
        targetAmplitude = 0.0
        teardownRequested = true
        playerThread?.join(200)
        playerThread = null
    }
}
