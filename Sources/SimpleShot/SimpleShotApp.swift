import SwiftUI

@main
struct SimpleShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.coordinator)
                .environmentObject(appDelegate.hotKeys)
        }
    }
}
