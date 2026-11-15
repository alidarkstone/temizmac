import SwiftUI

@main
struct TemizMacApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup("TemizMac") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 540)
        }
        .windowStyle(.titleBar)
    }
}
