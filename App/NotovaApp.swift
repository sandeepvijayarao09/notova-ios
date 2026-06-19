import SwiftUI

@main
struct NotovaApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}
