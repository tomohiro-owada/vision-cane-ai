import SwiftUI

@main
struct VisionCaneAIApp: App {
    @StateObject private var guideViewModel = GuideViewModel()

    init() {
        // Ensure the app never falls back to a "sleep" state while guiding.
        // The LiDAR + camera loop must keep running even when the screen is off.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(guideViewModel)
                .preferredColorScheme(.dark) // High contrast for low vision users.
        }
    }
}
