import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var hotKeys: HotKeyManager
    @AppStorage("shortcutSetupCompleted") private var setupCompleted = false
    @State private var showFinderHelp = false

    var body: some View {
        Form {
            permissionSection
            Section("Markup defaults") {
                LabeledContent("Default line thickness") {
                    Slider(value: $settings.defaultLineWidth, in: 2...60, step: 1).frame(width: 150)
                    Text("\(Int(settings.defaultLineWidth))").monospacedDigit().frame(width: 28)
                }
                LabeledContent("Default highlighter thickness") {
                    Slider(value: $settings.defaultHighlightWidth, in: 2...60, step: 1).frame(width: 150)
                    Text("\(Int(settings.defaultHighlightWidth))").monospacedDigit().frame(width: 28)
                }
                Toggle("Use a default line / shape color", isOn: $settings.useDefaultMarkupColor)
                InlineColorPicker(title: "Default line / shape color", color: Binding(
                    get: { NSColor(hex: settings.defaultMarkupColor) ?? .systemRed },
                    set: { settings.defaultMarkupColor = $0.hex }))
                Toggle("Use a default highlighter color", isOn: $settings.useDefaultHighlightColor)
                InlineColorPicker(title: "Default highlighter color", color: Binding(
                    get: { NSColor(hex: settings.defaultHighlightColor) ?? .systemYellow },
                    set: { settings.defaultHighlightColor = $0.hex }))
                Text("Otherwise, the last chosen color is remembered separately for markup and highlighting. Defaults apply when opening the preview or switching tools; existing annotations are unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Capture sound") {
                Picker("Sound", selection: $settings.captureSoundID) {
                    ForEach(settings.availableSounds) { sound in
                        Text(sound.name).tag(sound.id)
                    }
                }
                HStack {
                    Toggle("Mute capture sound", isOn: $settings.captureMuted)
                    Spacer()
                    Button("Play Sound", systemImage: "play.fill") { settings.playCaptureSound() }
                        .disabled(settings.captureMuted)
                }
            }
            Section("Shortcuts") {
                LabeledContent("Precision region capture", value: "⌘⇧2")
                Text(hotKeys.precisionStatus).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Capture region to clipboard", value: "⌘⇧4")
                Text(hotKeys.regionStatus).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Reopen last screenshot and annotate", value: "⌘⇧3")
                Text(hotKeys.displayStatus).font(.caption).foregroundStyle(.secondary)
                Text("Open Keyboard Shortcuts → Screenshots. Uncheck ‘Save picture of screen as a file’ (⌘⇧3) and ‘Save picture of selected area as a file’ (⌘⇧4), then click Done. Return here and check the shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Keyboard Settings") { hotKeys.openKeyboardSettings() }
                    Button("Check Shortcuts") { hotKeys.register() }
                    if !setupCompleted {
                        Button("Finish Setup") { setupCompleted = true }
                            .disabled(!hotKeys.isReady)
                    }
                }
            }

            Section("Save location") {
                Text(settings.saveDirectory.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack {
                    Button("Choose…") { settings.chooseSaveDirectory() }
                    Button("Open Folder") { coordinator.openSaveDirectory() }
                    Button("Add to Finder") {
                        settings.ensureSaveDirectoryExists()
                        NSWorkspace.shared.activateFileViewerSelecting([settings.saveDirectory])
                        showFinderHelp = true
                    }
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 660, height: 570)
        .onAppear { coordinator.checkPermissionOnSettingsOpen() }
        .alert("Add this folder to Finder", isPresented: $showFinderHelp) {
            Button("OK") {}
        } message: {
            Text("Finder is showing the folder. Drag it into the Favorites section of Finder’s sidebar. macOS does not provide apps a supported API to change Finder Favorites automatically.")
        }
    }

    private var permissionSection: some View {
        Section("Screen recording permission") {
            Label(coordinator.isCheckingPermission ? "Checking screen capture access…" :
                    coordinator.screenCaptureAllowed ? "Screen capture access verified" : "Screen capture access needs attention",
                  systemImage: coordinator.screenCaptureAllowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(coordinator.screenCaptureAllowed ? Color.green : Color.primary)
            Text(coordinator.permissionMessage).font(.caption).foregroundStyle(.secondary)
            HStack {
                if !coordinator.screenCaptureAllowed {
                    Button("Request Screen Access") { coordinator.requestScreenAccess() }
                        .disabled(coordinator.isCheckingPermission)
                }
                Button("Check Again") { coordinator.checkPermissionOnSettingsOpen() }
                    .disabled(coordinator.isCheckingPermission)
                Button("Open System Settings") { coordinator.requestPermission() }
            }
        }
    }
}
