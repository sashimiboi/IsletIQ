import Foundation

@Observable
class AuthManager {
    var isLoggedIn: Bool { token != nil }
    var token: String? { APIConfig.authToken }
    var userName: String = ""
    var userEmail: String = ""
    var userTier: String = "trial"
    var isLoading = false
    var error: String?

    struct AuthResponse: Codable {
        let token: String
        let user_id: Int
        let email: String
        let name: String?
        let tier: String
    }

    struct UserProfile: Codable {
        let id: Int
        let email: String
        let name: String?
        let tier: String
        let devices: [String: String]?
        let trial_ends_at: String?
    }

    func register(email: String, password: String, name: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(APIConfig.baseURL)/auth/register") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "name": name
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 200 {
                let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
                APIConfig.authToken = auth.token
                userName = auth.name ?? ""
                userEmail = auth.email
                userTier = auth.tier
                return true
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    error = json["detail"] as? String ?? "Registration failed"
                }
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func login(email: String, password: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(APIConfig.baseURL)/auth/login") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email, "password": password
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 200 {
                let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
                APIConfig.authToken = auth.token
                userName = auth.name ?? ""
                userEmail = auth.email
                userTier = auth.tier
                return true
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    error = json["detail"] as? String ?? "Login failed"
                }
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func fetchProfile() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/me") else { return }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            userName = profile.name ?? ""
            userEmail = profile.email
            userTier = profile.tier
        } catch {}
    }

    func logout() {
        APIConfig.authToken = nil
        userName = ""
        userEmail = ""
        userTier = "trial"
    }
}
