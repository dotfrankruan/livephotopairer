import SwiftUI

@main
struct LivePhotoPairerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
    }
}
