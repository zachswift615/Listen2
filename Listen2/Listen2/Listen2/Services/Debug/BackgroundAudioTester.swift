//
//  BackgroundAudioTester.swift
//  Listen2
//
//  Simple test to verify background audio works with a single long audio file.
//  If this works but sentence-by-sentence playback doesn't, the issue is gaps.
//

import Foundation
import AVFoundation
import MediaPlayer

/// Tests background audio by synthesizing and playing a single long audio file
@MainActor
final class BackgroundAudioTester: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var status: TestStatus = .idle
    @Published private(set) var progress: String = ""

    enum TestStatus: Equatable {
        case idle
        case synthesizing
        case playing
        case finished
        case error(String)
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    // MARK: - Private Properties

    private var player: AVAudioPlayer?
    private var tempFileURL: URL?
    private let voiceManager = VoiceManager()
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // Test text - about 60 seconds of audio
    private let testText = """
    The spreadsheet showed sixteen months and twelve days. I updated cell C47 with today's spending, eight dollars and forty-seven cents for a breakfast sandwich from Fido and coffee I shouldn't have bought, and watched the formula recalculate. The Funds Depleted date shifted forward by zero point zero two days. February 14th, 2027 became February 14th, 2027. The precision was meaningless but I tracked it anyway.

    Three spreadsheet tabs sat at the bottom of the screen. Remaining Runway. Hardware Investment Log. Daily Burn Rate. I'd been maintaining them for two years, updating every purchase down to the dollar. The Hardware Investment Log had stopped growing eight months ago at one hundred seventy-nine thousand, eight hundred forty-seven dollars and twenty-three cents. Everything after that went into the Burn Rate column. Two thousand four hundred per month. Rent, food, utilities, existence.

    I closed the laptop and opened it again. The Gmail tab was still there. Re: Staff Research Scientist, Applied AI Division. The recruiter had reached out personally. They'd seen my publications from my Stanford days, back when I published things people wanted to read. I'd written four versions of a response. Deleted all of them.

    The problem was the gap. Two years. They'd ask what I'd been doing. I could lie, consulting projects, independent research, but they'd want details. References. Published work. GitHub repos they could evaluate.
    """

    // MARK: - Initialization

    override init() {
        super.init()
        setupObservers()
    }

    // MARK: - Public Methods

    func startTest() async {
        status = .synthesizing
        progress = "Initializing TTS..."

        do {
            // Initialize Piper TTS
            let voice = voiceManager.bundledVoice()
            let provider = PiperTTSProvider(voiceID: voice.id, voiceManager: voiceManager)
            try await provider.initialize()

            progress = "Synthesizing ~60s of audio..."

            // Synthesize the long text
            let result = try await provider.synthesize(testText, speed: 1.0)

            progress = "Writing WAV file..."

            // Write to Documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let tempURL = documentsURL
                .appendingPathComponent("background_test_\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try result.audioData.write(to: tempURL)
            tempFileURL = tempURL

            progress = "Configuring audio session..."

            // Configure audio session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)

            // Log audio session state
            print("[BackgroundAudioTester] 🔊 Audio Session State:")
            print("  - Category: \(session.category.rawValue)")
            print("  - Mode: \(session.mode.rawValue)")
            print("  - Is Active: \(session.isOtherAudioPlaying ? "Other audio playing" : "Ready")")
            print("  - Route: \(session.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")

            progress = "Starting playback..."

            // Create and play
            player = try AVAudioPlayer(contentsOf: tempURL)
            player?.delegate = self
            player?.prepareToPlay()

            guard player?.play() == true else {
                throw NSError(domain: "BackgroundAudioTester", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"])
            }

            let duration = player?.duration ?? 0

            // Set up Now Playing Info (required for background audio on iOS)
            setupNowPlayingInfo(duration: duration)

            status = .playing
            progress = "Playing \(Int(duration))s audio. Lock screen now!"

            print("[BackgroundAudioTester] ✅ Started playing \(Int(duration))s test audio")
            print("[BackgroundAudioTester] 📱 Lock the screen now to test background playback")
            print("[BackgroundAudioTester] 🎵 Player isPlaying: \(player?.isPlaying ?? false)")

        } catch {
            status = .error(error.localizedDescription)
            progress = "Error: \(error.localizedDescription)"
            print("[BackgroundAudioTester] ❌ Test failed: \(error)")
        }
    }

    func playTestTone() async {
        status = .synthesizing
        progress = "Generating test tone..."

        do {
            // Generate 30 seconds of 440Hz sine wave at 44.1kHz
            let sampleRate = 44100
            let duration = 30.0
            let frequency = 440.0
            let frameCount = Int(Double(sampleRate) * duration)
            
            var pcmData = Data(count: frameCount * 2)
            pcmData.withUnsafeMutableBytes { buffer in
                let ptr = buffer.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    let t = Double(i) / Double(sampleRate)
                    let sample = Int16(32767.0 * sin(2.0 * .pi * frequency * t))
                    ptr[i] = sample
                }
            }
            
            // Create WAV header
            var wavData = Data()
            let dataSize = UInt32(pcmData.count)
            let fileSize = UInt32(36 + dataSize)
            
            wavData.append(contentsOf: "RIFF".utf8)
            wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
            wavData.append(contentsOf: "WAVE".utf8)
            wavData.append(contentsOf: "fmt ".utf8)
            wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // Mono
            wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
            wavData.append(withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // Byte rate
            wavData.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) }) // Block align
            wavData.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // Bits per sample
            wavData.append(contentsOf: "data".utf8)
            wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
            wavData.append(pcmData)
            
            // Write to Documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let tempURL = documentsURL
                .appendingPathComponent("tone_test_\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try wavData.write(to: tempURL)
            tempFileURL = tempURL
            
            // Play
            progress = "Configuring audio session..."
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            
            progress = "Playing test tone..."
            player = try AVAudioPlayer(contentsOf: tempURL)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            
            setupNowPlayingInfo(duration: player?.duration ?? 0)
            status = .playing
            
            print("[BackgroundAudioTester] ✅ Started playing test tone")
            
        } catch {
            status = .error(error.localizedDescription)
            progress = "Error: \(error.localizedDescription)"
            print("[BackgroundAudioTester] ❌ Test tone failed: \(error)")
        }
    }

    func stopTest() {
        player?.stop()
        player = nil
        clearNowPlayingInfo()
        cleanup()
        status = .idle
        progress = ""
    }

    // MARK: - Private Methods

    private func setupObservers() {
        let session = AVAudioSession.sharedInstance()

        // Monitor interruptions
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        // Monitor route changes
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            print("[BackgroundAudioTester] ⚠️ Interruption notification with no type")
            return
        }

        switch type {
        case .began:
            print("[BackgroundAudioTester] 🔴 INTERRUPTION BEGAN - this is why audio stopped!")
            progress = "⚠️ Interrupted! Check logs."
        case .ended:
            print("[BackgroundAudioTester] 🟢 Interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                print("[BackgroundAudioTester]   Should resume: \(options.contains(.shouldResume))")
            }
        @unknown default:
            print("[BackgroundAudioTester] ⚠️ Unknown interruption type: \(typeValue)")
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        print("[BackgroundAudioTester] 🔄 Route changed: \(routeChangeReasonString(reason))")

        let session = AVAudioSession.sharedInstance()
        print("[BackgroundAudioTester]   New route: \(session.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")
    }

    private func routeChangeReasonString(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "unknown(\(reason.rawValue))"
        }
    }

    private func setupNowPlayingInfo(duration: TimeInterval) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Background Audio Test"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Listen2"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        print("[BackgroundAudioTester] 📱 Set NowPlayingInfo for lock screen")
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player?.stop()
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension BackgroundAudioTester: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[BackgroundAudioTester] 🏁 audioPlayerDidFinishPlaying - success: \(flag)")
        Task { @MainActor in
            status = .finished
            progress = flag ? "✅ Completed!" : "⚠️ Finished with issues"
            clearNowPlayingInfo()
            cleanup()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[BackgroundAudioTester] ❌ Decode error: \(String(describing: error))")
        Task { @MainActor in
            status = .error(error?.localizedDescription ?? "Decode error")
            progress = "❌ Decode error"
            clearNowPlayingInfo()
            cleanup()
        }
    }

    nonisolated func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        print("[BackgroundAudioTester] 🔴 audioPlayerBeginInterruption called!")
    }

    nonisolated func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        print("[BackgroundAudioTester] 🟢 audioPlayerEndInterruption called with flags: \(flags)")
    }
}
