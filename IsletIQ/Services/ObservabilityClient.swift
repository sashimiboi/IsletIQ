import Foundation

actor ObservabilityClient {
    private let baseURL: String

    init(baseURL: String = APIConfig.baseURLSync) {
        self.baseURL = baseURL
    }

    func fetchTraces(limit: Int = 50) async -> [[String: Any]] {
        return await fetchJSON("/api/traces?limit=\(limit)", key: "traces")
    }

    func fetchLogs(limit: Int = 100, level: String = "all") async -> [[String: Any]] {
        return await fetchJSON("/api/logs?limit=\(limit)&level=\(level)", key: "logs")
    }

    func fetchMetrics(sessionId: String? = nil) async -> [String: Any] {
        let qs = sessionId.map { "?session_id=\($0)" } ?? ""
        guard let url = URL(string: "\(baseURL)/api/metrics\(qs)") else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {}
        return [:]
    }

    func fetchEvalsSummary(sessionId: String? = nil) async -> [String: Any] {
        let qs = sessionId.map { "?session_id=\($0)" } ?? ""
        guard let url = URL(string: "\(baseURL)/api/evals/summary\(qs)") else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {}
        return [:]
    }

    func fetchObservability() async -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/observability") else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {}
        return [:]
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func fetchJSON(_ path: String, key: String) async -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)\(path)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json[key] as? [[String: Any]] {
                return items
            }
        } catch {}
        return []
    }
}
