import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.phase {
        case .loading:
            ProgressView()
                .accessibilityIdentifier("root.loading")
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabView()
        }
    }
}

/// The signed-in home: Record / Notes / Integrations / Settings.
struct MainTabView: View {
    var body: some View {
        TabView {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "mic.circle.fill")
                }
                .accessibilityIdentifier("tab.record")

            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
                .accessibilityIdentifier("tab.notes")

            IntegrationsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }
                .accessibilityIdentifier("tab.integrations")

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("tab.settings")
        }
    }
}

#Preview {
    let container = AppContainer()
    return RootView()
        .environment(container)
        .environment(container.session)
}
