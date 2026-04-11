import Foundation

actor AgentClient {
    private let baseURL: String

    init(baseURL: String = APIConfig.baseURLSync) {
        self.baseURL = baseURL
    }

    struct ChatRequest: Codable {
        let message: String
        let agent: String
        let session_id: String?
        let model_id: String?
        let image_base64: String?
        let images_base64: [String]?
        let timezone: String?
    }

    struct PendingAction: Codable {
        let type: String
        let data: [String: Double]?  // For meal: calories, carbs_g, protein_g, fat_g

        // Flexible data access
        private enum CodingKeys: String, CodingKey { case type, data }
    }

    struct ChatResponse: Codable {
        let response: String
        let session_id: String?
        let agent: String?
        let thinking: [ThinkingStepResponse]?
        let tools_used: [String]?
        let pending_actions: [PendingActionRaw]?
    }

    struct PendingActionRaw: Codable {
        let type: String?
        let data: AnyCodableDict?
    }

    // Helper to decode arbitrary JSON dicts
    struct AnyCodableDict: Codable {
        let values: [String: AnyCodableValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: AnyCodableValue].self) {
                values = dict
            } else {
                values = [:]
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(values)
        }

        func string(_ key: String) -> String? {
            if case .string(let v) = values[key] { return v }
            return nil
        }
        func double(_ key: String) -> Double? {
            if case .double(let v) = values[key] { return v }
            if case .int(let v) = values[key] { return Double(v) }
            return nil
        }
    }

    enum AnyCodableValue: Codable {
        case string(String)
        case double(Double)
        case int(Int)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(String.self) { self = .string(v) }
            else if let v = try? c.decode(Int.self) { self = .int(v) }
            else if let v = try? c.decode(Double.self) { self = .double(v) }
            else if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else { self = .null }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let v): try c.encode(v)
            case .double(let v): try c.encode(v)
            case .int(let v): try c.encode(v)
            case .bool(let v): try c.encode(v)
            case .null: try c.encodeNil()
            }
        }
    }

    struct ThinkingStepResponse: Codable {
        let type: String?
        let content: String?
        let tool_call: ToolCallInfo?
    }

    struct ToolCallInfo: Codable {
        let name: String?
        let display_name: String?
        let output: String?
        let status: String?
    }

    struct AgentInfo: Codable {
        let id: String
        let name: String
        let description: String?
    }

    // MARK: - Send Message with Context

    func sendMessage(message: String, agent: String, sessionId: String? = nil, context: String? = nil, imagesBase64: [String]? = nil, imageBase64: String? = nil) async throws -> ChatResponse {
        guard let url = URL(string: "\(baseURL)/chat") else {
            throw AgentError.serverError("Invalid URL: \(baseURL)/chat")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        request.timeoutInterval = 120

        // Inject context into the message so the agent sees it
        var fullMessage = message
        if let ctx = context, !ctx.isEmpty {
            fullMessage = """
            [PATIENT CONTEXT - Use this data to answer the question]
            \(ctx)
            [END CONTEXT]

            \(message)
            """
        }

        let body = ChatRequest(
            message: fullMessage,
            agent: agent,
            session_id: sessionId,
            model_id: nil,
            image_base64: imageBase64,
            images_base64: imagesBase64,
            timezone: TimeZone.current.identifier
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentError.serverError("Status \(statusCode): \(body.prefix(200))")
        }

        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    // MARK: - Stream Message (SSE)

    func streamMessage(message: String, agent: String, sessionId: String? = nil, context: String? = nil, imageBase64: String? = nil, onEvent: @escaping (StreamEvent) -> Void) async throws {
        guard let url = URL(string: "\(baseURL)/chat/stream") else {
            throw AgentError.serverError("Invalid URL: \(baseURL)/chat/stream")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        APIConfig.applyAuth(to: &request)
        request.timeoutInterval = 120

        var fullMessage = message
        if let ctx = context, !ctx.isEmpty {
            fullMessage = "[PATIENT CONTEXT]\n\(ctx)\n[END CONTEXT]\n\n\(message)"
        }

        let body = ChatRequest(
            message: fullMessage,
            agent: agent,
            session_id: sessionId,
            model_id: nil,
            image_base64: imageBase64,
            images_base64: nil,
            timezone: TimeZone.current.identifier
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentError.serverError("Stream failed")
        }

        // var buffer = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonStr = String(line.dropFirst(6))
                if let data = jsonStr.data(using: .utf8),
                   let event = try? JSONDecoder().decode(SSEEvent.self, from: data) {
                    let streamEvent = StreamEvent(
                        type: event.resolvedType,
                        content: event.resolvedContent,
                        toolName: event.tool?.display_name ?? event.tool?.name ?? event.tool_name,
                        sessionId: event.session_id,
                        pendingActions: event.pending_actions
                    )
                    onEvent(streamEvent)
                }
            }
        }
    }

    struct SSEEvent: Codable {
        // Backend sends "event" not "type"
        let event: String?
        let type: String?
        let content: String?
        let text: String?
        let data: String?          // text_delta content
        let tool_name: String?
        let tool: SSEToolInfo?     // tool_call/tool_result info
        let session_id: String?
        let agent: String?
        let message: String?       // error message
        let pending_actions: [PendingActionRaw]?  // sent with done event

        var resolvedType: String { event ?? type ?? "unknown" }
        var resolvedContent: String { data ?? content ?? text ?? message ?? "" }
    }

    struct SSEToolInfo: Codable {
        let name: String?
        let display_name: String?
        let output: String?
    }

    struct StreamEvent {
        let type: String      // "start", "text_delta", "tool_call", "tool_result", "done", "error"
        let content: String
        let toolName: String?
        let sessionId: String?
        let pendingActions: [PendingActionRaw]?
    }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    enum AgentError: LocalizedError {
        case serverError(String)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .serverError(let msg): "Server error: \(msg)"
            case .noResponse: "No response from agent"
            }
        }
    }
}
