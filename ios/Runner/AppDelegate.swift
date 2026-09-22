import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Kept alive for the app's lifetime since FlutterMethodChannel holds its handler weakly.
  private let pitchEngineChannel = PitchEngineChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // .playback (not .ambient/.soloAmbient) so the reference tone isn't silenced by the
    // ringer/mute switch - the whole point of Tune/Guess is comparing pitches by ear, which the
    // OS shouldn't be able to silently mute out from under the user. No microphone permission is
    // needed anywhere in this app; it only ever plays tones, never records.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: PitchEngineChannel.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler(pitchEngineChannel.handle)
  }
}
