import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: AuthUser?
    @Published var haMode: HaMode = .home
    @Published var isLoading: Bool = true
    @Published var haConnection: HaConnection?

    private let storageKey = "dinodia_session_v1"

    init() {
        loadSession()
    }

    private func loadSession() {
        defer { isLoading = false }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        do {
            let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
            user = payload.user
            haMode = payload.haMode
            haConnection = payload.haConnection
        } catch {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    private func saveSession() {
        guard let currentUser = user else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        let payload = SessionPayload(user: currentUser, haMode: haMode, haConnection: haConnection)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func login(username: String, password: String) async throws {
        let loggedInUser = try await AuthService.login(username: username, password: password)
        let (_, connection) = try await DinodiaService.getUserWithHaConnection(userId: loggedInUser.id)
        if let existingId = user?.id, existingId != loggedInUser.id {
            await DeviceStore.clearAll(for: existingId)
        }
        await DeviceStore.clearAll(for: loggedInUser.id)
        user = loggedInUser
        haConnection = connection
        haMode = .home
        saveSession()
    }

    func logout() {
        let userId = user?.id
        user = nil
        haMode = .home
        haConnection = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        if let userId {
            Task { await DeviceStore.clearAll(for: userId) }
        }
        Task { await AuthService.logoutRemote() }
    }

    func setHaMode(_ mode: HaMode) {
        haMode = mode
        saveSession()
    }

    func updateConnection(_ connection: HaConnection) {
        haConnection = connection
        saveSession()
    }

    func connection(for mode: HaMode) -> HaConnectionLike? {
        guard let connection = haConnection else { return nil }
        let raw = (mode == .cloud ? connection.cloudUrl : connection.baseUrl) ?? ""
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        return HaConnectionLike(baseUrl: trimmed, longLivedToken: connection.longLivedToken)
    }
}
