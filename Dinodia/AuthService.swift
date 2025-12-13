import Foundation

enum AuthServiceError: LocalizedError {
    case invalidInput
    case endpointUnavailable
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Enter both username and password to sign in."
        case .endpointUnavailable:
            return "Login is not available right now. Please try again in a moment."
        case .custom(let message):
            return message
        }
    }
}

private struct AuthResponse: Codable {
    let ok: Bool
    let user: AuthUser?
    let error: String?
}

struct AuthService {
    static func login(username: String, password: String) async throws -> AuthUser {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw AuthServiceError.invalidInput
        }

        var request = URLRequest(url: EnvConfig.authBaseURL.appendingPathComponent("auth-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(EnvConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(EnvConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = [
            "username": trimmedUsername,
            "password": password,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.custom("We could not log you in right now. Please try again.")
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AuthResponse.self, from: data)

        guard httpResponse.statusCode == 200, decoded.ok, let user = decoded.user else {
            if httpResponse.statusCode == 401 || decoded.error?.lowercased().contains("invalid") == true {
                throw AuthServiceError.custom("We could not log you in. Check your username and password and try again.")
            }
            if let error = decoded.error, !error.isEmpty {
                throw AuthServiceError.custom(error)
            }
            throw AuthServiceError.custom("We could not log you in right now. Please try again.")
        }

        return user
    }

    static func changePassword(role: Role, currentPassword: String, newPassword: String, confirmPassword: String) async throws {
        let path = role == .ADMIN ? "auth/admin/change-password" : "auth/tenant/change-password"
        var request = URLRequest(url: EnvConfig.authBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(EnvConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(EnvConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: String] = [
            "currentPassword": currentPassword,
            "newPassword": newPassword,
            "confirmNewPassword": confirmPassword,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthServiceError.custom("We could not update that password. Please check your details and try again.")
        }
    }

    static func logoutRemote() async {
        var request = URLRequest(url: EnvConfig.authBaseURL.appendingPathComponent("auth/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(EnvConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(EnvConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{}".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: request)
    }
}
