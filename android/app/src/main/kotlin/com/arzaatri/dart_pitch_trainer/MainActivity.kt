package com.arzaatri.dart_pitch_trainer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val PITCH_ENGINE_CHANNEL = "com.arzaatri.dart_pitch_trainer/pitch_engine"

class MainActivity : FlutterActivity() {
    private val pitchEngineChannel = PitchEngineChannel()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PITCH_ENGINE_CHANNEL)
            .setMethodCallHandler(pitchEngineChannel)
    }

    override fun onDestroy() {
        pitchEngineChannel.releaseAll()
        super.onDestroy()
    }
}
