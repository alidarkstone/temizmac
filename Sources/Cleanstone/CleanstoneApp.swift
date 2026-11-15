import SwiftUI

@main
struct CleanstoneApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup("Cleanstone") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 540)
        }
        .windowStyle(.titleBar)
    }
}
