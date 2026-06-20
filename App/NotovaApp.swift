import SwiftUI

@main
struct NotovaApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.session)
                .task {
                    // Decide signed-in vs signed-out from any stored token. In
                    // UI-test mode the container already seeds a signed-in
                    // session, so this is a cheap no-op there.
                    if case .loading = container.session.phase {
                        await container.session.restore()
                    }
                }
        }
    }
}
