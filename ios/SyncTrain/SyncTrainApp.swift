import SwiftUI

@main
struct SyncTrainApp: App {
    @StateObject private var playerManager = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerManager)
                .preferredColorScheme(.dark)
        }
    }
}
