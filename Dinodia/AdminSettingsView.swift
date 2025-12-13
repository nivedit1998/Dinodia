import SwiftUI

struct AdminSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""

    @State private var haUsername: String = ""
    @State private var haBaseUrl: String = ""
    @State private var haCloudUrl: String = ""
    @State private var haPassword: String = ""
    @State private var haToken: String = ""

    @State private var isSavingPassword = false
    @State private var isSavingHa = false
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section("Account") {
                Text("Logged in as \(session.user?.username ?? "")")
                Button(role: .destructive) {
                    session.logout()
                } label: {
                    Text("Logout")
                }
            }

            Section("Change Password") {
                SecureField("Current password", text: $currentPassword)
                SecureField("New password", text: $newPassword)
                SecureField("Confirm new password", text: $confirmNewPassword)
                Button("Update password") {
                    Task { await updatePassword() }
                }
                .disabled(isSavingPassword)
            }

            Section("Dinodia Hub") {
                TextField("HA username", text: $haUsername)
                TextField("Dinodia Hub URL (home Wi-Fi)", text: $haBaseUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Dinodia Cloud URL (Nabu Casa)", text: $haCloudUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("New Dinodia Hub password (optional)", text: $haPassword)
                SecureField("New Dinodia Hub long-lived token (optional)", text: $haToken)
                Button("Update Dinodia Hub settings") {
                    Task { await updateHaSettings() }
                }
                .disabled(isSavingHa)
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadInitialValues() }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func loadInitialValues() {
        guard let connection = session.haConnection else { return }
        haUsername = connection.haUsername
        haBaseUrl = connection.baseUrl
        haCloudUrl = connection.cloudUrl ?? ""
    }

    private func updatePassword() async {
        guard let role = session.user?.role else { return }
        isSavingPassword = true
        defer { isSavingPassword = false }
        do {
            try await AuthService.changePassword(role: role, currentPassword: currentPassword, newPassword: newPassword, confirmPassword: confirmNewPassword)
            alertMessage = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmNewPassword = ""
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func updateHaSettings() async {
        guard let user = session.user else { return }
        isSavingHa = true
        defer { isSavingHa = false }
        do {
            let updated = try await DinodiaService.updateHaSettings(.init(
                adminId: user.id,
                haUsername: haUsername,
                haBaseUrl: haBaseUrl,
                haCloudUrl: haCloudUrl,
                haPassword: haPassword.isEmpty ? nil : haPassword,
                haLongLivedToken: haToken.isEmpty ? nil : haToken
            ))
            session.updateConnection(updated)
            alertMessage = "Dinodia Hub settings updated."
            haPassword = ""
            haToken = ""
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
