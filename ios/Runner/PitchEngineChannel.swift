import Flutter

/// Bridges Dart's PitchEngine interface (lib/pitch_engine.dart) to one or more native
/// [PitchEngine] instances, keyed by an id Dart hands back on every call after `create` - mirrors
/// android/.../PitchEngineChannel.kt exactly, down to the wire format for `setInstrument`'s zone
/// data (SF2 parsing happens in Dart on both platforms).
///
/// This is an application-level channel (see AppDelegate.swift), not a registered FlutterPlugin -
/// there's no plugin package here, just a single app-owned native feature, so a plain
/// FlutterMethodChannel with this as its call handler is all that's needed.
final class PitchEngineChannel: NSObject {
    static let channelName = "com.arzaatri.dart_pitch_trainer/pitch_engine"

    private var engines: [Int: PitchEngine] = [:]
    private var nextId = 0

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "create" {
            let id = nextId
            nextId += 1
            engines[id] = PitchEngine()
            result(id)
            return
        }

        guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int, let engine = engines[id] else {
            result(FlutterError(code: "UNKNOWN_ENGINE", message: "No PitchEngine for the given id", details: nil))
            return
        }

        switch call.method {
        case "start":
            engine.start()
            result(nil)
        case "stop":
            engine.stop()
            result(nil)
        case "release":
            engine.release()
            engines.removeValue(forKey: id)
            result(nil)
        case "updateFrequency":
            guard let frequency = args["frequency"] as? Double else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing frequency", details: nil))
                return
            }
            engine.updateFrequency(frequency)
            result(nil)
        case "setVibratoEnabled":
            guard let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing enabled", details: nil))
                return
            }
            engine.setVibratoEnabled(enabled)
            result(nil)
        case "setInstrument":
            guard let rawZones = args["zones"] as? [[String: Any]] else {
                result(FlutterError(code: "BAD_ARGS", message: "Missing zones", details: nil))
                return
            }
            engine.setInstrument(rawZones.map(Self.decodeZone))
            result(nil)
        case "isAudible":
            result(engine.isAudible())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func decodeZone(_ map: [String: Any]) -> Sf2Zone {
        let pcmData = (map["pcm"] as? FlutterStandardTypedData)?.data ?? Data()
        // Composed byte-by-byte rather than bound directly to Int16 - Data's raw bytes aren't
        // guaranteed 2-byte aligned, so a direct bindMemory(to: Int16.self) would be undefined
        // behavior. Bytes arrive little-endian from Dart's Int16List.buffer.asUint8List().
        var pcm = [Int16](repeating: 0, count: pcmData.count / 2)
        pcmData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            for i in 0..<pcm.count {
                let lo = UInt16(rawBuffer[i * 2])
                let hi = UInt16(rawBuffer[i * 2 + 1])
                pcm[i] = Int16(bitPattern: lo | (hi << 8))
            }
        }
        return Sf2Zone(
            keyLo: map["keyLo"] as? Int ?? 0,
            keyHi: map["keyHi"] as? Int ?? 0,
            rootFrequency: map["rootFrequency"] as? Double ?? 440.0,
            gain: map["gain"] as? Double ?? 1.0,
            sampleRate: map["sampleRate"] as? Int ?? 44100,
            loop: map["loop"] as? Bool ?? false,
            loopStart: map["loopStart"] as? Int ?? 0,
            loopEnd: map["loopEnd"] as? Int ?? pcm.count,
            pcm: pcm,
            retriggerSeconds: map["retriggerSeconds"] as? Double ?? 0.0,
            vibratoCapable: map["vibratoCapable"] as? Bool ?? false
        )
    }
}
