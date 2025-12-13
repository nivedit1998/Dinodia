import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        if let user = session.user {
            switch user.role {
            case .ADMIN:
                AdminTabView()
            case .TENANT:
                TenantTabView()
            }
        } else {
            ProgressView()
        }
    }
}

private struct AdminTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(role: .ADMIN)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }

            NavigationStack {
                AdminSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

private struct TenantTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(role: .TENANT)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }

            NavigationStack {
                TenantSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
