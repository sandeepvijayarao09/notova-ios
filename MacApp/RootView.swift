import NotovaCore
import SwiftUI

/// Top-level macOS layout: a sidebar (Record / Notes / Settings) and a detail pane.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.selection) { section in
                Label(section.rawValue, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Notova")
        } detail: {
            switch model.selection ?? .record {
            case .record: RecordView()
            case .notes: NotesView()
            case .settings: SettingsView()
            }
        }
    }
}
