import SwiftUI

struct DeviceCardView: View {
    @EnvironmentObject private var session: SessionStore
    let device: UIDevice
    let haMode: HaMode
    let onOpenDetails: () -> Void
    let onAfterCommand: () -> Void

    @State private var isSending = false
    @State private var alertMessage: String?

    var body: some View {
        let label = getPrimaryLabel(for: device)
        let preset = getDevicePreset(label: label)
        let active = isDeviceActive(label: label, device: device)
        let backgroundStyle: AnyShapeStyle = {
            if active {
                return AnyShapeStyle(LinearGradient(colors: preset.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                return AnyShapeStyle(preset.inactiveBackground)
            }
        }()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(active ? .black : .gray)
                Spacer()
            }
            Text(device.name)
                .font(.headline)
                .foregroundColor(active ? .primary : .secondary)
            Text(secondaryText(for: device))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let action = primaryAction(for: label, device: device) {
                Button(action: { Task { await sendCommand(action) } }) {
                    HStack {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(primaryActionLabel(for: label, device: device))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .disabled(isSending)
                .background(active ? preset.iconActiveBackground : Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.05))
        )
        .onTapGesture { onOpenDetails() }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func sendCommand(_ command: DeviceCommand) async {
        guard !isSending else { return }
        guard let ha = session.connection(for: haMode) else {
            alertMessage = haMode == .cloud
                ? "Dinodia Cloud is not ready yet. The homeowner needs to finish setting up remote access for this property."
                : "We cannot find your Dinodia Hub on the home Wi-Fi. It looks like you are away from home—switch to Dinodia Cloud to control your place."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            try await HACommandHandler.handle(ha: ha, entityId: device.entityId, command: command)
            await MainActor.run {
                onAfterCommand()
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
