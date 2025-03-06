import AVFoundation
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let audioSession = AVAudioSession.sharedInstance()
    do {
      // Configure the audio session for simultaneous recording and playback
      try audioSession.setCategory(.playAndRecord,
                                   mode: .voiceChat,
                                   options: [.defaultToSpeaker, .allowBluetooth])
      
      // Instead of using a fixed value, you can experiment with different low buffer durations.
      // Here we choose 3ms (0.003s) as a starting point; adjust as needed.
      let preferredBufferDuration = 0.003
      try audioSession.setPreferredIOBufferDuration(preferredBufferDuration)
      
      // Match your sample rate with your recording settings.
      try audioSession.setPreferredSampleRate(16000)
      
      // Activate the audio session.
      try audioSession.setActive(true)
      
      // Log the actual session settings to help with further tuning.
      print("✅ Audio session configured:")
      print("   - Preferred IO Buffer Duration: \(preferredBufferDuration) s")
      print("   - Actual IO Buffer Duration: \(audioSession.ioBufferDuration) s")
      print("   - Sample Rate: \(audioSession.sampleRate) Hz")
      print("   - Input Latency: \(audioSession.inputLatency) s")
      print("   - Output Latency: \(audioSession.outputLatency) s")
      
    } catch {
      print("❌ Failed to configure AVAudioSession: \(error)")
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
