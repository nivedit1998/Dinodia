import SwiftUI

private let allAreasKey = "ALL"
private let allAreasLabel = "All Areas"

struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    let role: Role

    var body: some View {
        if let user = session.user {
            DashboardContentView(userId: user.id, role: role, haMode: session.haMode)
                .id("\(user.id)-\(session.haMode.rawValue)")
        } else {
            ProgressView()
        }
    }
}

private struct DashboardContentView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store: DeviceStore

    let role: Role
    let userId: Int
    let haMode: HaMode

    @State private var selectedDevice: UIDevice?
    @State private var selectedArea: String = allAreasKey
    @State private var showAreaSheet = false
    @State private var showMenu = false
    @State private var areaPrefLoaded = false

    init(userId: Int, role: Role, haMode: HaMode) {
        _store = StateObject(wrappedValue: DeviceStore(userId: userId, mode: haMode))
        self.userId = userId
        self.role = role
        self.haMode = haMode
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let maxColumns = isLandscape ? 4 : 2
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error = store.errorMessage, store.devices.isEmpty {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                    deviceGrid(maxColumns: maxColumns)
                    spotifyCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .refreshable {
                await store.refresh(background: false)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                Button(action: { showMenu = true }) {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("Dinodia", isPresented: $showMenu) {
                Button(haMode == .cloud ? "Switch to Home Mode" : "Switch to Cloud Mode") {
                    toggleMode()
                }
                Button("Logout", role: .destructive) {
                    session.logout()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $selectedDevice) { device in
                let sensors = linkedSensors(for: device)
                DeviceDetailSheet(
                    device: device,
                    haMode: haMode,
                    linkedSensors: sensors,
                    relatedDevices: relatedDevices(for: device),
                    allowSensorHistory: !sensors.isEmpty
                )
                .environmentObject(session)
            }
            .onAppear { loadAreaPreference() }
            .onChange(of: selectedArea) { _, newValue in
                saveAreaPreference(value: newValue)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    showAreaSheet = true
                } label: {
                    HStack {
                        Text(selectedArea == allAreasKey ? allAreasLabel : selectedArea)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                    }
                }
                Spacer()
                Text(haMode == .cloud ? "Cloud Mode" : "Home Mode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if store.isRefreshing {
                Text("Refreshing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let last = store.lastUpdated {
                Text("Updated \(relativeDescription(for: last))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .confirmationDialog("Select area", isPresented: $showAreaSheet) {
            Button(allAreasLabel) { selectedArea = allAreasKey }
            ForEach(areaOptions, id: \.self) { area in
                Button(area) { selectedArea = area }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filteredDevices: [UIDevice] {
        store.devices.filter { device in
            guard let area = device.areaName?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty else { return false }
            if selectedArea != allAreasKey, area != selectedArea { return false }
            return !normalizeLabel(device.label).isEmpty || !(device.labels ?? []).isEmpty
        }
    }

    private func deviceGrid(maxColumns: Int) -> some View {
        let sections = buildDeviceSections(filteredDevices)
        let rows = buildSectionLayoutRows(sections, maxColumns: maxColumns)
        return VStack(spacing: 16) {
            if rows.isEmpty {
                Text(store.isRefreshing ? "Loading devices…" : "No devices available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(section.span, maxColumns)), spacing: 12) {
                                    ForEach(section.devices, id: \.entityId) { device in
                                        DeviceCardView(
                                            device: device,
                                            haMode: haMode,
                                            onOpenDetails: { selectedDevice = device },
                                            onAfterCommand: { Task { await store.refresh(background: true) } }
                                        )
                                        .environmentObject(session)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var spotifyCard: some View {
        SpotifyCardView()
    }

    private var areaOptions: [String] {
        let names = Set(store.devices.compactMap { ($0.area ?? $0.areaName)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return names.sorted()
    }

    private func loadAreaPreference() {
        guard role == .TENANT else { return }
        let key = "tenant_selected_area_\(userId)"
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            selectedArea = stored
        }
        areaPrefLoaded = true
    }

    private func saveAreaPreference(value: String) {
        guard role == .TENANT, areaPrefLoaded else { return }
        let key = "tenant_selected_area_\(userId)"
        UserDefaults.standard.set(value, forKey: key)
    }

    private func toggleMode() {
        let next: HaMode = haMode == .cloud ? .home : .cloud
        Task {
            await DeviceStore.clearCache(for: userId, mode: next)
            session.setHaMode(next)
        }
    }

    private func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func linkedSensors(for device: UIDevice) -> [UIDevice] {
        guard let id = device.deviceId, !id.isEmpty else { return [] }
        return store.devices.filter { $0.deviceId == id && $0.entityId != device.entityId && isSensorDevice($0) }
    }

    private func relatedDevices(for device: UIDevice) -> [UIDevice]? {
        let label = getPrimaryLabel(for: device)
        if label == "Home Security" {
            return store.devices.filter { getPrimaryLabel(for: $0) == "Home Security" }
        }
        return nil
    }
}
