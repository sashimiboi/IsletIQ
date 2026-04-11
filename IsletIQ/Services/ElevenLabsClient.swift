#if os(iOS)
import Foundation

actor ElevenLabsClient {
    // Flash v2.5 for lowest latency (~75ms inference)
    private let modelId = "eleven_flash_v2_5"
    // Rachel - clear, professional female voice
    private let voiceId = "21m00Tcm4TlvDq8ikWAM"
    private let outputFormat = "pcm_44100"

    private var apiKey: String {
        KeychainHelper.load(key: "elevenlabs_api_key") ?? ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    /// Stream PCM audio for the given text. Yields raw 16-bit PCM chunks at 44.1kHz mono.
    func streamSpeech(text: String) -> AsyncThrowingStream<Data, Error> {
        let key = apiKey
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream?output_format=\(outputFormat)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.7,
                "similarity_boost": 0.8,
                "style": 0.0,
                "use_speaker_boost": true,
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.finish(throwing: ElevenLabsError.serverError(code))
                        return
                    }

                    var buffer = Data()
                    let chunkSize = 4096

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }
                    // Flush remaining
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum ElevenLabsError: LocalizedError {
        case serverError(Int)
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .serverError(let code): "ElevenLabs error: HTTP \(code)"
            case .notConfigured: "ElevenLabs API key not set"
            }
        }
    }
}
#endif
