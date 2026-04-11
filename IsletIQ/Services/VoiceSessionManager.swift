#if os(iOS)
import Foundation
import Speech
import AVFoundation

@Observable
@MainActor
final class VoiceSessionManager {
    // MARK: - Public State

    var state: VoiceState = .idle
    var audioLevel: Float = 0
    var currentTranscript = ""
    var responseText = ""
    var errorMessage: String?

    // MARK: - Dependencies

    private var agentClient: AgentClient?
    private var agentName = "orchestrator"
    private var sessionId: String?
    private var context: String?
    private let ttsClient = ElevenLabsClient()

    // MARK: - Audio Engine (shared for mic + playback)

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Silence Detection

    private var speechDetected = false
    private var silenceStart: Date?
    private let silenceThreshold: Float = -40 // dB
    private let silenceDuration: TimeInterval = 1.5

    // MARK: - TTS

    private var ttsTask: Task<Void, Never>?
    private var sentenceBuffer = ""
    private var sentenceQueue: [String] = []
    private var isPlayingAudio = false
    private var playbackFormat: AVAudioFormat?

    // MARK: - Lifecycle

    init() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )
        if let fmt = playbackFormat {
            audioEngine.connect(playerNode, to: mainMixer, format: fmt)
        }
    }

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

    func interruptSpeaking() {
        ttsTask?.cancel()
        ttsTask = nil
        playerNode.stop()
        sentenceQueue.removeAll()
        sentenceBuffer = ""
        isPlayingAudio = false
        startListening()
    }

    // MARK: - Listening

    private func startListening() {
        stopRecognition()
        state = .listening
        currentTranscript = ""
        speechDetected = false
        silenceStart = nil

        configureAudioSession()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
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
                    self.silenceStart = nil // reset silence timer on new speech
                }
                if result?.isFinal == true {
                    self.onSpeechFinished()
                }
                if error != nil && self.speechDetected {
                    self.onSpeechFinished()
                }
            }
        }

        if !audioEngine.isRunning {
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                print("[VoiceSession] Engine start error: \(error)")
                self.errorMessage = "Microphone error"
                self.state = .idle
            }
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

        // Normalize to 0-1 range (roughly -60dB to -10dB range)
        let normalized = max(0, min(1, (db + 50) / 40))

        // Smooth
        audioLevel = audioLevel * 0.7 + normalized * 0.3

        // Silence detection
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
        guard state == .listening, !currentTranscript.isEmpty else {
            if state == .listening && !speechDetected {
                // No speech detected at all, keep listening
                return
            }
            if state == .listening && currentTranscript.isEmpty {
                errorMessage = "Didn't catch that"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.errorMessage = nil
                }
                startListening()
                return
            }
            return
        }

        stopRecognition()
        state = .processing
        audioLevel = 0

        let transcript = currentTranscript
        sendToBackend(transcript)
    }

    // MARK: - Backend Communication

    private func sendToBackend(_ text: String) {
        guard let client = agentClient else { return }

        responseText = ""
        sentenceBuffer = ""
        sentenceQueue.removeAll()

        ttsTask = Task { [weak self] in
            guard let self else { return }

            do {
                var fullMessage = text
                if let ctx = self.context, !ctx.isEmpty {
                    fullMessage = "[PATIENT CONTEXT]\n\(ctx)\n[END CONTEXT]\n\n\(text)"
                }

                try await client.streamMessage(
                    message: fullMessage,
                    agent: self.agentName,
                    sessionId: self.sessionId,
                    context: nil // context already embedded in message
                ) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch event.type {
                        case "text_delta":
                            self.responseText += event.content
                            self.bufferForTTS(event.content)
                        case "done":
                            if let sid = event.sessionId { self.sessionId = sid }
                            self.flushTTSBuffer()
                        case "error":
                            self.errorMessage = "Agent error"
                            self.startListening()
                        default:
                            break
                        }
                    }
                }
            } catch {
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

    // MARK: - TTS Sentence Chunking

    private func bufferForTTS(_ text: String) {
        sentenceBuffer += text

        // Split on sentence boundaries
        let terminators: [Character] = [".", "!", "?"]
        while let idx = sentenceBuffer.lastIndex(where: { terminators.contains($0) }) {
            let afterIdx = sentenceBuffer.index(after: idx)
            // Only split if terminator is followed by space or is at end
            if afterIdx == sentenceBuffer.endIndex || sentenceBuffer[afterIdx] == " " {
                let sentence = String(sentenceBuffer[...idx])
                sentenceBuffer = String(sentenceBuffer[afterIdx...]).trimmingCharacters(in: .whitespaces)
                if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sentenceQueue.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !isPlayingAudio {
                        playNextSentence()
                    }
                }
                break
            } else {
                break
            }
        }
    }

    private func flushTTSBuffer() {
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceBuffer = ""
        if !remaining.isEmpty {
            sentenceQueue.append(remaining)
        }
        if !isPlayingAudio && !sentenceQueue.isEmpty {
            playNextSentence()
        } else if !isPlayingAudio && sentenceQueue.isEmpty {
            // Response complete, no more audio to play
            onAllAudioComplete()
        }
    }

    // MARK: - TTS Playback

    private func playNextSentence() {
        guard !sentenceQueue.isEmpty else {
            isPlayingAudio = false
            onAllAudioComplete()
            return
        }

        let sentence = sentenceQueue.removeFirst()
        isPlayingAudio = true
        state = .speaking

        Task { [weak self] in
            guard let self else { return }
            do {
                var allPCMData = Data()
                for try await chunk in await self.ttsClient.streamSpeech(text: sentence) {
                    if Task.isCancelled { return }
                    allPCMData.append(chunk)

                    // Calculate playback audio level from PCM
                    await MainActor.run { [weak self] in
                        self?.updatePlaybackLevel(from: chunk)
                    }
                }

                if Task.isCancelled { return }

                // Schedule the complete audio buffer for playback
                await MainActor.run { [weak self] in
                    self?.scheduleAndPlay(pcmData: allPCMData)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // TTS failed - skip to next sentence or finish
                    self.isPlayingAudio = false
                    if !self.sentenceQueue.isEmpty {
                        self.playNextSentence()
                    } else {
                        self.onAllAudioComplete()
                    }
                }
            }
        }
    }

    private func scheduleAndPlay(pcmData: Data) {
        guard let format = playbackFormat else { return }

        // Convert 16-bit PCM to float32 for AVAudioPlayerNode
        let sampleCount = pcmData.count / 2 // 16-bit = 2 bytes per sample
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))
        else { return }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let floatData = buffer.floatChannelData![0]

        pcmData.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        // Ensure engine is running for playback
        if !audioEngine.isRunning {
            configureAudioSession()
            audioEngine.prepare()
            try? audioEngine.start()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Buffer finished playing
                if !self.sentenceQueue.isEmpty {
                    self.playNextSentence()
                } else {
                    self.isPlayingAudio = false
                    // Check if there's more text buffering
                    if self.sentenceBuffer.isEmpty {
                        self.onAllAudioComplete()
                    }
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func updatePlaybackLevel(from chunk: Data) {
        guard chunk.count >= 2 else { return }
        var sum: Float = 0
        let sampleCount = chunk.count / 2
        chunk.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let f = Float(samples[i]) / 32768.0
                sum += f * f
            }
        }
        let rms = sqrt(sum / Float(max(sampleCount, 1)))
        let normalized = min(1, rms * 4) // scale up for visibility
        audioLevel = audioLevel * 0.6 + normalized * 0.4
    }

    private func onAllAudioComplete() {
        audioLevel = 0
        // Auto-continue conversation
        startListening()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[VoiceSession] Audio session error: \(error)")
        }
    }

    // MARK: - Cleanup

    private func stopRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func stopEverything() {
        ttsTask?.cancel()
        ttsTask = nil
        playerNode.stop()
        stopRecognition()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        sentenceQueue.removeAll()
        sentenceBuffer = ""
        isPlayingAudio = false
    }
}
#endif
