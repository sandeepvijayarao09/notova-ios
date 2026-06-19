import SwiftUI

struct RootView: View {
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

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("tab.settings")
        }
    }
}

#Preview {
    RootView()
        .environment(AppContainer())
}
