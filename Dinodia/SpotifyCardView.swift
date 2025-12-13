import SwiftUI

struct SpotifyCardView: View {
    @StateObject private var store = SpotifyStore()

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.playback?.trackName ?? (store.isLoggedIn ? "No track playing" : "Connect to Spotify"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    if store.isLoggedIn {
                        Button(action: { store.showDevicePicker = true; Task { await store.loadDevices() } }) {
                            Label(store.playback?.deviceName ?? "Device", systemImage: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
                if store.isLoggingIn || store.isLoadingPlayback {
                    ProgressView()
                        .tint(.white)
                }
                Button(action: { store.isLoggedIn ? store.openSpotifyApp() : store.startLogin() }) {
                    Text(store.isLoggedIn ? "Open" : "Login")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(16)
                }
                .foregroundColor(.white)
            }
            HStack(spacing: 24) {
                Button(action: { Task { await store.skipPrevious() } }) {
                    Image(systemName: "backward.fill")
                }
                Button(action: { Task { await store.togglePlayPause() } }) {
                    Image(systemName: store.playback?.isPlaying == true ? "pause.fill" : "play.fill")
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(Circle())
                }
                Button(action: { Task { await store.skipNext() } }) {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title2)
            .foregroundColor(.white)
        }
        .padding()
        .background(LinearGradient(colors: [Color.green.opacity(0.8), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(24)
        .sheet(isPresented: $store.showDevicePicker) {
            NavigationStack {
                List(store.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.type)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if device.isActive {
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await store.transfer(to: device) } }
                }
                .navigationTitle("Spotify Devices")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { store.showDevicePicker = false }
                    }
                }
            }
        }
        .alert("Spotify", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var subtitle: String {
        if !store.isLoggedIn {
            if !store.isSpotifyInstalled {
                return "Spotify app is not installed."
            }
            return "Log in to control music from this device."
        }
        if let playback = store.playback {
            if let artist = playback.artistName, let album = playback.albumName {
                return "\(artist) • \(album)"
            }
            return playback.artistName ?? playback.albumName ?? "Spotify"
        }
        return "Start playing music in Spotify."
    }

    private var artwork: some View {
        ZStack {
            if let url = store.playback?.coverURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Color.white.opacity(0.2)
                }
            } else {
                Color.white.opacity(0.2)
                Text("♫")
                    .font(.title)
                    .foregroundColor(.white)
            }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(12)
    }
}
