import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Dinodia")
                    .font(.largeTitle).fontWeight(.semibold)
                ProgressView().progressViewStyle(.circular)
            }
        }
    }
}
