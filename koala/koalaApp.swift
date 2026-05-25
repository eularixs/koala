import SwiftUI

@main
struct koalaApp: App {
    var body: some Scene {
        WindowGroup {
            KoalaRootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
