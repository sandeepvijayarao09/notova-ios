import SwiftUI

/// macOS entry point. Notova on the Mac is a native SwiftUI app that reuses the same
/// `NotovaCore` package (models, pipeline, on-device AI seams) as the iOS app — only the
/// UI and the audio/file plumbing are macOS-specific.
@main
struct NotovaMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowToolbarStyle(.unified)
    }
}
