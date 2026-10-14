import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var coordinator = CaptureCoordinator(settings: settings)
    let hotKeys = HotKeyManager()
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.onPermissionNeeded = { [weak self] in self?.openSettings() }
        coordinator.onOpenSettings = { [weak self] in self?.openSettings() }

        hotKeys.onRegionCapture = { [weak self] in self?.coordinator.captureRegion() }
        hotKeys.onPrecisionCapture = { [weak self] in self?.coordinator.captureRegion(precision: true) }
        hotKeys.onDisplayCapture = { [weak self] in self?.coordinator.openLastScreenshot() }
        hotKeys.register()

        configureStatusItem()
        settings.ensureSaveDirectoryExists()
        if !UserDefaults.standard.bool(forKey: "shortcutSetupCompleted") || !hotKeys.isReady {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hotKeys.register()
        if settingsWindow?.isVisible == true { coordinator.checkPermissionOnSettingsOpen() }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SimpleShot")

        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Region", action: #selector(captureRegion), keyEquivalent: "")
        menu.addItem(withTitle: "Precision Capture", action: #selector(precisionCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Annotate Last Screenshot", action: #selector(openLastScreenshot), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit SimpleShot", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func captureRegion() { coordinator.captureRegion() }
    @objc private func precisionCapture() { coordinator.captureRegion(precision: true) }
    @objc private func openLastScreenshot() { coordinator.openLastScreenshot() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 570),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SimpleShot Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView()
                .environmentObject(settings).environmentObject(coordinator).environmentObject(hotKeys))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        coordinator.checkPermissionOnSettingsOpen()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
