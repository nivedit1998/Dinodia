import SwiftUI

struct TenantSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isSaving = false
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
                .disabled(isSaving)
            }
        }
        .navigationTitle("Settings")
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func updatePassword() async {
        guard let role = session.user?.role else { return }
        isSaving = true
        defer { isSaving = false }
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
}
