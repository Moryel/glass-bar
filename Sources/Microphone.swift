import AVFoundation
import Combine

// Microphone level while Siri listens (only while the Siri pill is open; nothing is recorded or sent anywhere).
// macOS asks for microphone permission on first use.
final class Microphone: ObservableObject {
    static let shared = Microphone()
    /// 0…1, smoothed
    @Published var level: Double = 0
    /// false without permission or when not working: the wave falls back to its old self-animating form
    @Published var isRunning = false
    private var engine: AVAudioEngine?
    private var rawLevel: Double = 0
    /// ambient noise level (dB): drops quickly to silence, rises very slowly with sound; speech is measured above it
    private var noiseFloor: Float = -50

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in if granted { DispatchQueue.main.async { self.startEngine() } } }
        default: SystemControl.log("microphone: no permission")
        }
    }

    private func startEngine() {
        guard engine == nil else { return }
        let m = AVAudioEngine()
        let input = m.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let samples = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var total: Float = 0
            for i in 0..<n { total += samples[i] * samples[i] }
            let rms = sqrt(total / Float(max(1, n)))
            let db = 20 * log10(max(rms, 1e-6))
            DispatchQueue.main.async {
                // background noise: the floor drops quickly in quiet moments and adapts slowly to constant sound
                self.noiseFloor += (db - self.noiseFloor) * (db < self.noiseFloor ? 0.3 : 0.004)
                // 8 dB above the floor (start of speech) … 32 dB above → 0…1; anything below is zero
                let v = Double(min(1, max(0, (db - self.noiseFloor - 8) / 24)))
                // fast rise, slow fall (like the wave on iOS)
                self.rawLevel = v > self.rawLevel ? self.rawLevel + (v - self.rawLevel) * 0.6 : self.rawLevel + (v - self.rawLevel) * 0.15
                self.level = self.rawLevel
            }
        }
        do {
            try m.start()
            engine = m
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            SystemControl.log("microphone: couldn't start (\(error.localizedDescription))")
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        rawLevel = 0
        level = 0
        noiseFloor = -50
    }
}
