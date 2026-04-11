#if os(iOS)
import Foundation

actor ElevenLabsClient {
    private let modelId = "eleven_flash_v2_5"
    // Rachel - clear, professional female voice
    private let voiceId = "21m00Tcm4TlvDq8ikWAM"
    private let outputFormat = "mp3_44100_128"

    private var apiKey: String {
        KeychainHelper.load(key: "elevenlabs_api_key") ?? ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    /// Fetch complete MP3 audio for the given text.
    func synthesize(text: String) async throws -> Data {
        let key = apiKey
        print("[ElevenLabs] Requesting TTS, key=\(key.isEmpty ? "MISSING" : "***\(key.suffix(6))"), text=\(text.prefix(50))")
        guard !key.isEmpty else {
            throw ElevenLabsError.notConfigured
        }

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

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[ElevenLabs] Response status: \(code), size: \(data.count) bytes")

        guard code == 200 else {
            if let detail = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[ElevenLabs] Error: \(detail)")
            }
            throw ElevenLabsError.serverError(code)
        }

        return data
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
