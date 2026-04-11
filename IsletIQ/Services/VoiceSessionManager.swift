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
    private var playerNode: AVAudioPlayerNode?
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
    private var lastUserMessage = ""

    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44100,
        channels: 1,
        interleaved: false
    )!

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

    func interruptSpeaking() {
        ttsTask?.cancel()
        ttsTask = nil
        stopPlayback()
        sentenceQueue.removeAll()
        sentenceBuffer = ""
        isPlayingAudio = false
        // Save partial response
        if !lastUserMessage.isEmpty && !responseText.isEmpty {
            onExchange?(lastUserMessage, responseText)
        }
        startListening()
    }

    // MARK: - Listening

    private func startListening() {
        stopPlayback()
        stopRecognition()

        state = .listening
        currentTranscript = ""
        speechDetected = false
        silenceStart = nil

        // Fresh engine for recording
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

        let normalized = max(0, min(1, (db + 50) / 40))
        audioLevel = audioLevel * 0.7 + normalized * 0.3

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
                    context: nil
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

        let terminators: [Character] = [".", "!", "?"]
        while let idx = sentenceBuffer.lastIndex(where: { terminators.contains($0) }) {
            let afterIdx = sentenceBuffer.index(after: idx)
            if afterIdx == sentenceBuffer.endIndex || sentenceBuffer[afterIdx] == " " {
                let sentence = String(sentenceBuffer[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                sentenceBuffer = String(sentenceBuffer[afterIdx...]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty {
                    sentenceQueue.append(sentence)
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

                    await MainActor.run { [weak self] in
                        self?.updatePlaybackLevel(from: chunk)
                    }
                }

                if Task.isCancelled { return }

                await MainActor.run { [weak self] in
                    self?.scheduleAndPlay(pcmData: allPCMData)
                }
            } catch {
                print("[VoiceSession] TTS error: \(error)")
                await MainActor.run { [weak self] in
                    guard let self else { return }
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
        let sampleCount = pcmData.count / 2
        guard sampleCount > 0 else {
            isPlayingAudio = false
            if !sentenceQueue.isEmpty {
                playNextSentence()
            } else {
                onAllAudioComplete()
            }
            return
        }

        // Set up fresh engine for playback
        configureAudioSessionForPlayback()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        self.audioEngine = engine
        self.playerNode = player

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(sampleCount))
        else { return }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let floatData = buffer.floatChannelData![0]

        pcmData.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[VoiceSession] Playback engine error: \(error)")
            isPlayingAudio = false
            onAllAudioComplete()
            return
        }

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.sentenceQueue.isEmpty {
                    self.playNextSentence()
                } else {
                    self.isPlayingAudio = false
                    if self.sentenceBuffer.isEmpty {
                        self.onAllAudioComplete()
                    }
                }
            }
        }

        player.play()
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
        let normalized = min(1, rms * 4)
        audioLevel = audioLevel * 0.6 + normalized * 0.4
    }

    private func onAllAudioComplete() {
        audioLevel = 0
        // Save the exchange to chat
        if !lastUserMessage.isEmpty && !responseText.isEmpty {
            onExchange?(lastUserMessage, responseText)
        }
        // Auto-continue
        startListening()
    }

    // MARK: - Audio Session

    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
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

    private func stopPlayback() {
        playerNode?.stop()
        playerNode = nil
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
        stopPlayback()
        stopRecognition()
        stopEngine()
        sentenceQueue.removeAll()
        sentenceBuffer = ""
        isPlayingAudio = false
    }
}
#endif
