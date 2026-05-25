import SwiftUI

@main
struct koalaApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
