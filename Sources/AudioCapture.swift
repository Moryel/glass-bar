import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Listens to Spotify's output with a Core Audio process tap (macOS 14.2+) and splits it into frequency bands;
/// the sound bar moves with these bands. Nothing is recorded, only the level is measured. On first use macOS
/// asks for "system audio recording" permission; without it, or if the tap can't be set up, `isRunning` stays false.
final class AudioCapture: ObservableObject {
    static let shared = AudioCapture()
    static let bandCount = 14
    /// Sensitivity and Smoothness from the menu; written on the main thread, read on the audio queue.
    static var dynamicRange: Float = 24
    static var decay: Float = 0.8

    /// Called on the main thread for each new measurement. Drawn straight into layers instead of SwiftUI publishing:
    /// ~23 updates a second through SwiftUI pushed CPU use to ~10%.
    var onLevels: (([Float]) -> Void)?
    @Published private(set) var isRunning = false

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private let audioQueue = DispatchQueue(label: "GlassBar.audio", qos: .userInteractive)
    private var lastAttempt = Date.distantPast

    /// Called every second: sets the tap up if it should be on (retrying every 5 s on failure), tears it down otherwise.
    func update(isOn: Bool) {
        if isOn {
            guard tap == kAudioObjectUnknown, Date().timeIntervalSince(lastAttempt) > 5 else { return }
            lastAttempt = Date()
            if #available(macOS 14.2, *) { startCapture() }
        } else if tap != kAudioObjectUnknown {
            stopCapture()
        }
    }

    @available(macOS 14.2, *)
    private func startCapture() {
        let processes = Self.spotifyProcesses()
        guard !processes.isEmpty else { SystemControl.log("audio capture: no Spotify audio process"); return }
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processes)
        tapDescription.name = "GlassBar"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tap)
        guard tapStatus == noErr else { SystemControl.log("audio capture: couldn't create tap (\(tapStatus))"); tap = kAudioObjectUnknown; return }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        let channelCount = max(1, Int(format.mChannelsPerFrame)), sampleRate = format.mSampleRate > 0 ? Float(format.mSampleRate) : 48000

        var deviceDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GlassBar",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapDescription.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        if let outputUID = Self.defaultOutputDeviceUID() {
            deviceDescription[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            deviceDescription[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        let aggregateStatus = AudioHardwareCreateAggregateDevice(deviceDescription as CFDictionary, &aggregateDevice)
        guard aggregateStatus == noErr else { SystemControl.log("audio capture: couldn't create device (\(aggregateStatus))"); stopCapture(); return }

        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate, channelCount: channelCount)
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateDevice, audioQueue) { [weak self] _, input, _, _, _ in
            let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = bufferList.first, let data = buffer.mData else { return }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channelCount
            if let levels = analyzer.process(data.assumingMemoryBound(to: Float.self), frameCount: frameCount) {
                DispatchQueue.main.async { self?.onLevels?(levels) }
            }
        }
        let start = status == noErr ? AudioDeviceStart(aggregateDevice, ioProc) : status
        guard start == noErr else { SystemControl.log("audio capture: couldn't start (\(start))"); stopCapture(); return }
        isRunning = true
        SystemControl.log("audio capture: on (\(processes.count) Spotify processes)")
    }

    private func stopCapture() {
        if let ioProc, aggregateDevice != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDevice, ioProc)
            AudioDeviceDestroyIOProcID(aggregateDevice, ioProc)
        }
        ioProc = nil
        if aggregateDevice != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateDevice) }
        if tap != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
        aggregateDevice = kAudioObjectUnknown
        tap = kAudioObjectUnknown
        isRunning = false
        onLevels?([Float](repeating: 0, count: Self.bandCount))
    }

    // MARK: Core Audio objects

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Core Audio objects of the Spotify processes that output audio (the main app and its helpers).
    private static func spotifyProcesses() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var processObjects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &processObjects) == noErr else { return [] }
        return processObjects.filter { processObject in
            var b = address(kAudioProcessPropertyBundleID)
            var bundleID: CFString? = nil
            var k = UInt32(MemoryLayout<CFString?>.size)
            guard AudioObjectGetPropertyData(processObject, &b, 0, nil, &k, &bundleID) == noErr, let bundleID else { return false }
            return (bundleID as String).hasPrefix("com.spotify.")
        }
    }

    private static func defaultOutputDeviceUID() -> String? {
        var a = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &device) == noErr else { return nil }
        var u = address(kAudioDevicePropertyDeviceUID)
        var uid: CFString? = nil
        var k = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &u, 0, nil, &k, &uid) == noErr else { return nil }
        return uid as String?
    }
}

/// FFT over 1024-sample windows; logarithmic bands from 50 Hz to 14 kHz, each 0…1.
/// Each band is scaled both against its own recent peak (the Sensitivity range) and against the strongest band:
/// beats move bands individually, but constant treble (hi-hats) doesn't stay pinned at the top.
/// Independent of volume; bars drop in silence (below -75 dB). A result is returned every other window (~23/s).
private final class SpectrumAnalyzer {
    private let n = 1024, log2n: vDSP_Length = 10
    private let channelCount: Int
    private let fftSetup: FFTSetup
    private let window: [Float]
    private var samples: [Float]
    private var sampleCount = 0
    private var peaks = [Float](repeating: -60, count: AudioCapture.bandCount)
    private var overallPeak: Float = -60
    private var counter = 0
    private var smoothed = [Float](repeating: 0, count: AudioCapture.bandCount)
    private let bandEdges: [Int]

    init(sampleRate: Float, channelCount: Int) {
        self.channelCount = channelCount
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        samples = [Float](repeating: 0, count: n)
        let count = AudioCapture.bandCount, partialWord = 512, binWidth = sampleRate / 1024
        bandEdges = (0...count).map { i in
            let f = 50 * pow(14000 / 50, Float(i) / Float(count))
            return min(partialWord - 1, max(1, Int(f / binWidth)))
        }
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func process(_ p: UnsafePointer<Float>, frameCount: Int) -> [Float]? {
        var result: [Float]?
        for i in 0..<frameCount {
            var t: Float = 0
            for k in 0..<channelCount { t += p[i * channelCount + k] }
            samples[sampleCount] = t / Float(channelCount)
            sampleCount += 1
            if sampleCount == n {
                sampleCount = 0
                let levels = analyze()
                counter += 1
                if counter % 2 == 0 { result = levels }
            }
        }
        return result
    }

    private func analyze() -> [Float] {
        let partialWord = n / 2
        let x = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: partialWord), imaginary = [Float](repeating: 0, count: partialWord)
        var magnitudes = [Float](repeating: 0, count: partialWord)
        real.withUnsafeMutableBufferPointer { g in
            imaginary.withUnsafeMutableBufferPointer { s in
                var z = DSPSplitComplex(realp: g.baseAddress!, imagp: s.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: partialWord) { vDSP_ctoz($0, 2, &z, 1, vDSP_Length(partialWord)) }
                }
                vDSP_fft_zrip(fftSetup, &z, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&z, 1, &magnitudes, 1, vDSP_Length(partialWord))
            }
        }
        let db: [Float] = (0..<AudioCapture.bandCount).map { i in
            let a = bandEdges[i], b = max(a + 1, bandEdges[i + 1])
            let mean = magnitudes[a..<b].reduce(0, +) / Float(b - a)
            return 20 * log10(mean + 1e-7)
        }
        overallPeak = max(db.max() ?? -100, overallPeak - 0.15)
        for i in smoothed.indices {
            peaks[i] = max(db[i], peaks[i] - 0.25)
            let dynamicRange = AudioCapture.dynamicRange, decay = AudioCapture.decay
            // a mix of its own peak (beats) and the strongest band (so treble doesn't look louder than bass)
            let relative = min(1, max(0, (db[i] - (peaks[i] - dynamicRange)) / dynamicRange))
            let overall = min(1, max(0, (db[i] - (overallPeak - 30)) / 30))
            // the exponent suppresses mid levels: only strong moments rise
            let target = db[i] < -75 ? 0 : pow(relative * 0.55 + overall * 0.45, 1.8)
            // fast rise, slow fall (like classic equalizers)
            smoothed[i] = target > smoothed[i] ? smoothed[i] + (target - smoothed[i]) * 0.6 : smoothed[i] * decay + target * (1 - decay)
        }
        return smoothed
    }
}
