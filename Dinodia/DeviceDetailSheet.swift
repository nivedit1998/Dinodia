import SwiftUI
import Combine

struct DeviceDetailSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let device: UIDevice
    let haMode: HaMode
    let linkedSensors: [UIDevice]
    let relatedDevices: [UIDevice]?
    let allowSensorHistory: Bool

    @State private var isSending = false
    @State private var alertMessage: String?
    @State private var selectedSensorId: String?
    @State private var selectedBucket: HistoryBucket = .daily
    @State private var historyPoints: [HistoryPoint] = []
    @State private var historyUnit: String?
    @State private var historyLoading = false
    @State private var historyError: String?
    @State private var brightnessValue: Double = 0
    @State private var cameraRefresh = Date()

    private var selectedSensor: UIDevice? {
        guard let id = selectedSensorId else { return nil }
        return linkedSensors.first { $0.entityId == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    controls
                    if !linkedSensors.isEmpty {
                        sensorSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(device.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                brightnessValue = Double(brightnessPercent(for: device) ?? 0)
                if selectedSensorId == nil {
                    selectedSensorId = linkedSensors.first?.entityId
                }
                if allowSensorHistory {
                    Task { await loadHistory() }
                }
            }
            .onChange(of: selectedSensorId) { _, _ in
                Task { await loadHistory() }
            }
            .onChange(of: selectedBucket) { _, _ in
                Task { await loadHistory() }
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                cameraRefresh = Date()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(getPrimaryLabel(for: device))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(device.name)
                .font(.title2)
                .fontWeight(.bold)
            Text(device.areaName ?? "Unassigned area")
                .foregroundColor(.secondary)
            Text("State: \(device.state)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var controls: some View {
        let label = getPrimaryLabel(for: device)
        switch label {
        case "Light":
            VStack(alignment: .leading, spacing: 16) {
                Button(action: { Task { await send(.lightToggle) } }) {
                    Text(device.state.lowercased() == "on" ? "Turn off" : "Turn on")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brightness \(Int(brightnessValue))%")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Slider(value: $brightnessValue, in: 0...100, step: 1) { editing in
                        if !editing {
                            let value = brightnessValue
                            Task { await send(.lightSetBrightness, value: value) }
                        }
                    }
                }
            }
        case "Blind":
            HStack(spacing: 12) {
                Button("Open") { Task { await send(.blindOpen) } }
                Button("Close") { Task { await send(.blindClose) } }
            }
            .buttonStyle(.bordered)
            .disabled(isSending)
        case "Spotify":
            VStack(spacing: 12) {
                HStack {
                    Button(action: { Task { await send(.mediaPrevious) } }) { Text("Prev") }
                    Button(action: { Task { await send(.mediaPlayPause) } }) { Text(device.state.lowercased() == "playing" ? "Pause" : "Play") }
                    Button(action: { Task { await send(.mediaNext) } }) { Text("Next") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
            }
        case "TV", "Speaker":
            VStack(spacing: 12) {
                Button(action: { Task { await send(label == "TV" ? .tvTogglePower : .speakerTogglePower) } }) {
                    Text(device.state.lowercased() == "on" ? "Power off" : "Power on")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
                HStack {
                    Button("Vol -") { Task { await send(.mediaVolumeDown) } }
                    Button("Vol +") { Task { await send(.mediaVolumeUp) } }
                }
                .buttonStyle(.bordered)
                .disabled(isSending)
            }
        case "Doorbell":
            cameraView(for: device)
        case "Home Security":
            securityCameraGrid
        default:
            attributesSection
        }
    }

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attributes")
                .font(.headline)
            ForEach(device.attributes.keys.sorted(), id: \.self) { key in
                if let value = device.attributes[key]?.anyValue {
                    Text("\(key): \(String(describing: value))")
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func cameraView(for device: UIDevice) -> some View {
        if let ha = session.connection(for: haMode), let url = cameraURL(for: device.entityId, ha: ha) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Live View")
                    .font(.headline)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(16)
                    case .failure:
                        Text("Unable to load camera")
                            .foregroundColor(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .cornerRadius(16)
            }
        } else {
            Text("Camera view unavailable")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var securityCameraGrid: some View {
        if let cameras = relatedDevices, !cameras.isEmpty, let ha = session.connection(for: haMode) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cameras")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(cameras, id: \.entityId) { cam in
                        VStack(alignment: .leading, spacing: 8) {
                            if let url = cameraURL(for: cam.entityId, ha: ha) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 120)
                                            .clipped()
                                            .cornerRadius(12)
                                    case .failure:
                                        Text("Unavailable")
                                            .frame(maxWidth: .infinity, minHeight: 120)
                                            .background(Color(.tertiarySystemBackground))
                                            .cornerRadius(12)
                                    default:
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 120)
                                    }
                                }
                            }
                            Text(cam.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked Sensors")
                .font(.headline)
            if allowSensorHistory {
                sensorHistoryControls
                historyContent
            } else {
                ForEach(linkedSensors, id: \.entityId) { sensor in
                    VStack(alignment: .leading) {
                        Text(sensor.name)
                            .font(.subheadline)
                        Text(sensor.state)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }

    private var sensorHistoryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if linkedSensors.count > 1 {
                Picker("Sensor", selection: Binding(
                    get: { selectedSensorId ?? linkedSensors.first?.entityId ?? "" },
                    set: { selectedSensorId = $0 }
                )) {
                    ForEach(linkedSensors, id: \.entityId) { sensor in
                        Text(sensor.name).tag(sensor.entityId)
                    }
                }
                .pickerStyle(.menu)
            }
            HStack {
                ForEach(HistoryBucket.allCases, id: \.self) { bucket in
                    Button(bucketLabel(bucket)) { selectedBucket = bucket }
                        .font(.caption)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(selectedBucket == bucket ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground))
                        .cornerRadius(999)
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if historyLoading {
            ProgressView("Loading history…")
        } else if let error = historyError {
            Text(error)
                .foregroundColor(.secondary)
                .font(.caption)
        } else if historyPoints.isEmpty {
            Text("No history yet.")
                .foregroundColor(.secondary)
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(historyPoints) { point in
                    HStack {
                        Text(point.label)
                            .font(.footnote)
                        Spacer()
                        Text("\(String(format: "%.2f", point.value))\(historyUnit.map { " \($0)" } ?? "")")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func bucketLabel(_ bucket: HistoryBucket) -> String {
        switch bucket {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    private func cameraURL(for entityId: String, ha: HaConnectionLike) -> URL? {
        let ts = cameraRefresh.timeIntervalSince1970
        guard let encodedEntity = entityId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedToken = ha.longLivedToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let urlString = "\(ha.baseUrl)/api/camera_proxy/\(encodedEntity)?token=\(encodedToken)&ts=\(ts)"
        return URL(string: urlString)
    }

    private func loadHistory() async {
        guard allowSensorHistory, let sensor = selectedSensor, let userId = session.user?.id else { return }
        historyLoading = true
        historyError = nil
        do {
            let result = try await MonitoringHistoryService.fetchHistory(userId: userId, entityId: sensor.entityId, bucket: selectedBucket)
            await MainActor.run {
                historyPoints = result.points
                historyUnit = result.unit
                historyLoading = false
            }
        } catch {
            await MainActor.run {
                historyPoints = []
                historyUnit = nil
                historyError = error.localizedDescription
                historyLoading = false
            }
        }
    }

    private func send(_ command: DeviceCommand, value: Double? = nil) async {
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
            try await HACommandHandler.handle(ha: ha, entityId: device.entityId, command: command, value: value)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
