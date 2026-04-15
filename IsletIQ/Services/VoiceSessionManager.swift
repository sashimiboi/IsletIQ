#if os(iOS)
import Foundation
import Speech
import AVFoundation
import UIKit

@Observable
@MainActor
final class VoiceSessionManager: NSObject, AVAudioPlayerDelegate {
    // MARK: - Public State

    var state: VoiceState = .idle
    var audioLevel: Float = 0
    var currentTranscript = ""
    var responseText = ""
    var errorMessage: String?

    /// Called when a full exchange completes (user message + agent response)
    var onExchange: ((String, String) -> Void)?

    // MARK: - Dependencies

    private var agentClient: AgentClient?
    private var agentName = "orchestrator"
    private var sessionId: String?
    private var context: String?
    private let ttsClient = ElevenLabsClient()

    // MARK: - Audio

    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var displayLink: CADisplayLink?

    // MARK: - Silence Detection

    private var speechDetected = false
    private var silenceStart: Date?
    private let silenceThreshold: Float = -40
    private let silenceDuration: TimeInterval = 1.5

    // MARK: - TTS

    private var ttsTask: Task<Void, Never>?
    private var isPlayingAudio = false
    private var lastUserMessage = ""

    // MARK: - Lifecycle

    func startSession(
        agentClient: AgentClient,
        agentName: String,
        sessionId: String?,
        context: String?
    ) {
        self.agentClient = agentClient
        self.agentName = agentName
        self.sessionId = sessionId
        self.context = context
        self.errorMessage = nil

        startListening()
    }

    func endSession() {
        stopEverything()
        state = .idle
        audioLevel = 0
        currentTranscript = ""
        responseText = ""
    }

    func updateVoice(_ voiceId: String) {
        Task { await ttsClient.setVoice(voiceId) }
    }

    func interruptSpeaking() {
        ttsTask?.cancel()
        ttsTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        displayLink?.invalidate()
        displayLink = nil
        isPlayingAudio = false
        if !lastUserMessage.isEmpty && !responseText.isEmpty {
            onExchange?(lastUserMessage, responseText)
        }
        startListening()
    }

    // MARK: - Listening

    private func startListening() {
        audioPlayer?.stop()
        audioPlayer = nil
        displayLink?.invalidate()
        displayLink = nil
        stopRecognition()

        state = .listening
        currentTranscript = ""
        speechDetected = false
        silenceStart = nil

        let engine = AVAudioEngine()
        self.audioEngine = engine

        configureAudioSessionForRecording()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            Task { @MainActor [weak self] in
                self?.processAudioLevel(buffer: buffer)
            }
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                    self.speechDetected = true
                    self.silenceStart = nil
                }
                if result?.isFinal == true {
                    self.onSpeechFinished()
                }
                if error != nil && self.speechDetected {
                    self.onSpeechFinished()
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[VoiceSession] Engine start error: \(error)")
            self.errorMessage = "Microphone error"
            self.state = .idle
        }
    }

    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))

        let normalized = max(0, min(1, (db + 45) / 35))
        // Fast attack, slower decay for responsive animation
        if normalized > audioLevel {
            audioLevel = audioLevel * 0.3 + normalized * 0.7  // fast rise
        } else {
            audioLevel = audioLevel * 0.8 + normalized * 0.2  // slow fall
        }

        if state == .listening && speechDetected {
            if db < silenceThreshold {
                if silenceStart == nil {
                    silenceStart = Date()
                } else if Date().timeIntervalSince(silenceStart!) >= silenceDuration {
                    onSpeechFinished()
                }
            } else {
                silenceStart = nil
            }
        }
    }

    private func onSpeechFinished() {
        guard state == .listening else { return }

        if currentTranscript.isEmpty {
            if speechDetected {
                errorMessage = "Didn't catch that"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.errorMessage = nil
                }
            }
            startListening()
            return
        }

        stopRecognition()
        stopEngine()
        state = .processing
        audioLevel = 0

        lastUserMessage = currentTranscript
        sendToBackend(currentTranscript)
    }

    // MARK: - Backend Communication

    private func sendToBackend(_ text: String) {
        guard let client = agentClient else { return }

        responseText = ""

        ttsTask = Task { [weak self] in
            guard let self else { return }

            do {
                var fullMessage = text
                if let ctx = self.context, !ctx.isEmpty {
                    fullMessage = "[PATIENT CONTEXT]\n\(ctx)\n[END CONTEXT]\n\n\(text)"
                }

                print("[VoiceSession] Sending to backend: \(self.agentName)")

                try await client.streamMessage(
                    message: fullMessage,
                    agent: self.agentName,
                    sessionId: self.sessionId,
                    context: nil
                ) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch event.type {
                        case "text_delta":
                            self.responseText += event.content
                        case "done":
                            if let sid = event.sessionId { self.sessionId = sid }
                            self.speakFullResponse()
                        case "error":
                            self.errorMessage = "Agent error"
                            self.startListening()
                        default:
                            break
                        }
                    }
                }
            } catch {
                print("[VoiceSession] Backend error: \(error)")
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Connection lost"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.errorMessage = nil
                        self?.startListening()
                    }
                }
            }
        }
    }

    // MARK: - TTS

    private func speakFullResponse() {
        let text = stripMarkdown(responseText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            onAllAudioComplete()
            return
        }

        state = .speaking
        isPlayingAudio = true

        Task { [weak self] in
            guard let self else { return }
            do {
                // Cap at 2000 chars for TTS (ElevenLabs limit considerations)
                let ttsText = String(text.prefix(2000))
                print("[VoiceSession] TTS: \(ttsText.count) chars")
                let mp3Data = try await self.ttsClient.synthesize(text: ttsText)
                if Task.isCancelled { return }

                await MainActor.run { [weak self] in
                    self?.playMP3(data: mp3Data)
                }
            } catch {
                print("[VoiceSession] TTS error: \(error)")
                await MainActor.run { [weak self] in
                    self?.isPlayingAudio = false
                    self?.onAllAudioComplete()
                }
            }
        }
    }

    private func stripMarkdown(_ text: String) -> String {
        var result = text
        // Remove bold/italic markers
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        // Remove headers
        result = result.replacingOccurrences(of: "### ", with: "")
        result = result.replacingOccurrences(of: "## ", with: "")
        result = result.replacingOccurrences(of: "# ", with: "")
        // Remove bullet points
        result = result.replacingOccurrences(of: "- ", with: "")
        // Remove code blocks
        result = result.replacingOccurrences(of: "```", with: "")
        return result
    }

    private func playMP3(data: Data) {
        configureAudioSessionForPlayback()

        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()
            self.audioPlayer = player

            print("[VoiceSession] Playing MP3: \(data.count) bytes, duration=\(player.duration)s")

            player.play()
            startPlaybackMetering()
        } catch {
            print("[VoiceSession] AVAudioPlayer error: \(error)")
            isPlayingAudio = false
            onAllAudioComplete()
        }
    }

    private func startPlaybackMetering() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(pollPlaybackLevel))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func pollPlaybackLevel() {
        guard let p = audioPlayer, p.isPlaying else { return }
        p.updateMeters()
        let db = p.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (db + 45) / 35))
        if normalized > audioLevel {
            audioLevel = audioLevel * 0.3 + normalized * 0.7
        } else {
            audioLevel = audioLevel * 0.75 + normalized * 0.25
        }
    }

    // AVAudioPlayerDelegate - called when playback finishes
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.audioLevel = 0
            self.isPlayingAudio = false
            print("[VoiceSession] Playback finished (success=\(flag))")
            self.onAllAudioComplete()
        }
    }

    private func onAllAudioComplete() {
        audioLevel = 0
        if !lastUserMessage.isEmpty && !responseText.isEmpty {
            onExchange?(lastUserMessage, responseText)
        }
        startListening()
    }

    // MARK: - Audio Session

    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[VoiceSession] Record session error: \(error)")
        }
    }

    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[VoiceSession] Playback session error: \(error)")
        }
    }

    // MARK: - Cleanup

    private func stopRecognition() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func stopEngine() {
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }
        audioEngine = nil
    }

    private func stopEverything() {
        ttsTask?.cancel()
        ttsTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        displayLink?.invalidate()
        displayLink = nil
        stopRecognition()
        stopEngine()
        isPlayingAudio = false
    }
}
#endif
