package com.arzaatri.dart_pitch_trainer

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bridges Dart's PitchEngine interface (lib/pitch_engine.dart) to one or more native
 * [PitchEngine] instances, keyed by an id Dart hands back on every call after `create`. Two
 * instances exist at once in practice - one each for the Tune and Guess panels - so they can
 * crossfade independently exactly like the original Android app's two AudioTracks.
 *
 * SF2 zones are parsed in Dart (lib/sound_font.dart) rather than natively, so `setInstrument`
 * receives already-resolved zone data (including precomputed rootFrequency/gain) instead of a
 * raw asset to parse.
 */
class PitchEngineChannel : MethodChannel.MethodCallHandler {
    private val engines = mutableMapOf<Int, PitchEngine>()
    private val nextId = AtomicInteger(0)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            val id = nextId.getAndIncrement()
            engines[id] = PitchEngine()
            result.success(id)
            return
        }

        val id = call.argument<Int>("id")
        val engine = id?.let { engines[it] }
        if (engine == null) {
            result.error("UNKNOWN_ENGINE", "No PitchEngine for id $id", null)
            return
        }

        when (call.method) {
            "start" -> {
                engine.start()
                result.success(null)
            }
            "stop" -> {
                engine.stop()
                result.success(null)
            }
            "release" -> {
                engine.release()
                engines.remove(id)
                result.success(null)
            }
            "updateFrequency" -> {
                val frequency = call.argument<Double>("frequency")!!
                engine.updateFrequency(frequency)
                result.success(null)
            }
            "setVibratoEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")!!
                engine.setVibratoEnabled(enabled)
                result.success(null)
            }
            "setInstrument" -> {
                @Suppress("UNCHECKED_CAST")
                val rawZones = call.argument<List<Map<String, Any>>>("zones")!!
                engine.setInstrument(rawZones.map { decodeZone(it) })
                result.success(null)
            }
            "isAudible" -> result.success(engine.isAudible())
            else -> result.notImplemented()
        }
    }

    private fun decodeZone(map: Map<String, Any>): Sf2Zone {
        val pcmBytes = map["pcm"] as ByteArray
        val pcm = ShortArray(pcmBytes.size / 2)
        ByteBuffer.wrap(pcmBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcm)
        return Sf2Zone(
            keyLo = (map["keyLo"] as Number).toInt(),
            keyHi = (map["keyHi"] as Number).toInt(),
            rootFrequency = (map["rootFrequency"] as Number).toDouble(),
            gain = (map["gain"] as Number).toDouble(),
            sampleRate = (map["sampleRate"] as Number).toInt(),
            loop = map["loop"] as Boolean,
            loopStart = (map["loopStart"] as Number).toInt(),
            loopEnd = (map["loopEnd"] as Number).toInt(),
            pcm = pcm,
            retriggerSeconds = (map["retriggerSeconds"] as Number).toDouble(),
            vibratoCapable = map["vibratoCapable"] as Boolean,
        )
    }

    /** Releases every still-open engine - called when the Flutter engine is torn down so no
     * AudioTrack playback threads are leaked past the activity's lifetime. */
    fun releaseAll() {
        engines.values.forEach { it.release() }
        engines.clear()
    }
}
