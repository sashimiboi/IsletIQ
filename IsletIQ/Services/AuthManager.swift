import Foundation

extension Notification.Name {
    static let authStateDidChange = Notification.Name("IsletIQAuthStateDidChange")
    static let cohortDidChange = Notification.Name("IsletIQCohortDidChange")
    static let roleDidChange = Notification.Name("IsletIQRoleDidChange")
}

/// IsletIQ account role. Drives which home experience is shown after
/// onboarding: patient sees the existing TabView, provider/admin sees
/// the roster-first ProviderHomeView.
enum Role: String, Codable, CaseIterable, Identifiable {
    case patient
    case provider
    case admin

    var id: String { rawValue }
    var isProvider: Bool { self == .provider || self == .admin }
}

/// IsletIQ patient cohort. Drives which dashboard surfaces are visible —
/// pump / IOB / bolus are T1D-only; T2D and GLP-1 see cohort-appropriate
/// cards instead.
enum Cohort: String, Codable, CaseIterable, Identifiable {
    case t1d
    case t2d
    case glp1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .t1d: return "Type 1 Diabetes"
        case .t2d: return "Type 2 Diabetes"
        case .glp1: return "GLP-1 / Weight Management"
        }
    }

    var shortLabel: String {
        switch self {
        case .t1d: return "T1D"
        case .t2d: return "T2D"
        case .glp1: return "GLP-1"
        }
    }

    var tagline: String {
        switch self {
        case .t1d: return "CGM, pump, insulin, supplies"
        case .t2d: return "CGM, oral meds, weight, labs"
        case .glp1: return "Weekly injections, weight, side effects"
        }
    }

    var icon: String {
        switch self {
        case .t1d: return "drop.fill"
        case .t2d: return "pills.fill"
        case .glp1: return "syringe.fill"
        }
    }
}

@Observable
class AuthManager {
    static let cohortDefaultsKey = "userCohort"
    static let roleDefaultsKey = "userRole"

    /// Read the current user's cohort from UserDefaults without holding
    /// an AuthManager instance. Use this in views that gate UI on cohort
    /// but don't need observability. Defaults to T1D for fresh installs.
    static var currentCohort: Cohort {
        if let raw = UserDefaults.standard.string(forKey: cohortDefaultsKey),
           let c = Cohort(rawValue: raw) { return c }
        return .t1d
    }

    /// Read the current user's role from UserDefaults. Defaults to .patient.
    static var currentRole: Role {
        if let raw = UserDefaults.standard.string(forKey: roleDefaultsKey),
           let r = Role(rawValue: raw) { return r }
        return .patient
    }

    var isLoggedIn: Bool = APIConfig.authToken != nil
    var token: String? { APIConfig.authToken }
    var userName: String = ""
    var userEmail: String = ""
    var userTier: String = "trial"
    // Cohort is cached in UserDefaults so a freshly-instantiated AuthManager
    // (each view holds its own @State copy) restores the user's segment
    // without waiting on a /auth/me round trip.
    var userCohort: Cohort = {
        if let raw = UserDefaults.standard.string(forKey: AuthManager.cohortDefaultsKey),
           let c = Cohort(rawValue: raw) { return c }
        return .t1d
    }() {
        didSet {
            UserDefaults.standard.set(userCohort.rawValue, forKey: Self.cohortDefaultsKey)
        }
    }
    var userRole: Role = {
        if let raw = UserDefaults.standard.string(forKey: AuthManager.roleDefaultsKey),
           let r = Role(rawValue: raw) { return r }
        return .patient
    }() {
        didSet {
            UserDefaults.standard.set(userRole.rawValue, forKey: Self.roleDefaultsKey)
        }
    }
    var isLoading = false
    var error: String?

    struct AuthResponse: Codable {
        let access_token: String
        let token_type: String?
        let user: AuthUser?
    }

    struct AuthUser: Codable {
        let id: Int
        let email: String
        let name: String?
        let tier: String
        let cohort: String?
        let role: String?
    }

    struct UserProfile: Codable {
        let id: Int
        let email: String
        let name: String?
        let tier: String
        let cohort: String?
        let role: String?
        let devices: [String: String]?
        let trial_ends_at: String?
    }

    struct UserProfileEnvelope: Codable { let user: UserProfile }

    func register(
        email: String,
        password: String,
        name: String,
        cohort: Cohort = .t1d,
        role: Role = .patient,
        npi: String? = nil,
        organization: String? = nil
    ) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(APIConfig.baseURL)/auth/register") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "email": email,
            "password": password,
            "name": name,
            "cohort": cohort.rawValue,
            "role": role.rawValue,
        ]
        if role == .provider {
            if let n = npi, !n.isEmpty { body["npi"] = n }
            if let o = organization, !o.isEmpty { body["organization"] = o }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 200 {
                let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
                APIConfig.authToken = auth.access_token
                userName = auth.user?.name ?? ""
                userEmail = auth.user?.email ?? ""
                userTier = auth.user?.tier ?? "trial"
                if let raw = auth.user?.cohort, let c = Cohort(rawValue: raw) { userCohort = c }
                if let raw = auth.user?.role, let r = Role(rawValue: raw) { userRole = r }
                isLoggedIn = true
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
                APIConfig.authToken = auth.access_token
                userName = auth.user?.name ?? ""
                userEmail = auth.user?.email ?? ""
                userTier = auth.user?.tier ?? "trial"
                if let raw = auth.user?.cohort, let c = Cohort(rawValue: raw) { userCohort = c }
                if let raw = auth.user?.role, let r = Role(rawValue: raw) { userRole = r }
                isLoggedIn = true
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
            // /auth/me wraps the user in { "user": {...} }
            let envelope = try JSONDecoder().decode(UserProfileEnvelope.self, from: data)
            let profile = envelope.user
            userName = profile.name ?? ""
            userEmail = profile.email
            userTier = profile.tier
            if let raw = profile.cohort, let c = Cohort(rawValue: raw) { userCohort = c }
            if let raw = profile.role, let r = Role(rawValue: raw) {
                let changed = r != userRole
                userRole = r
                if changed { NotificationCenter.default.post(name: .roleDidChange, object: r) }
            }
        } catch {}
    }

    /// PUT /auth/profile to persist a new cohort. Returns true on 2xx.
    @discardableResult
    func updateCohort(_ cohort: Cohort) async -> Bool {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/profile") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIConfig.applyAuth(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["cohort": cohort.rawValue])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
            if ok {
                userCohort = cohort
                NotificationCenter.default.post(name: .cohortDidChange, object: cohort)
            }
            return ok
        } catch { return false }
    }

    func logout() {
        APIConfig.authToken = nil
        userName = ""
        userEmail = ""
        userTier = "trial"
        userCohort = .t1d
        userRole = .patient
        UserDefaults.standard.removeObject(forKey: Self.cohortDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.roleDefaultsKey)
        isLoggedIn = false
        NotificationCenter.default.post(name: .authStateDidChange, object: nil)
    }

    /// Call from any client when a request returns 401. Clears stale Keychain token
    /// and broadcasts so the root view swaps back to AuthView.
    static func handleUnauthorized() {
        APIConfig.authToken = nil
        NotificationCenter.default.post(name: .authStateDidChange, object: nil)
    }
}
