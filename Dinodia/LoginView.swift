import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Dinodia Portal")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                VStack(spacing: 16) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: handleLogin) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Login")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .disabled(isLoading)
                .foregroundColor(.white)
                .background(Color.accentColor)
                .cornerRadius(14)

                Spacer()
            }
            .padding()
        }
    }

    private func handleLogin() {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await session.login(username: username, password: password)
            } catch {
                errorMessage = friendlyError(for: error)
            }
            isLoading = false
        }
    }

    private func friendlyError(for error: Error) -> String {
        if let authError = error as? AuthServiceError, let description = authError.errorDescription {
            return description
        }
        return error.localizedDescription.isEmpty
            ? "We could not log you in right now. Please try again."
            : error.localizedDescription
    }
}
