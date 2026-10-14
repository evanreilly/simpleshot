import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let saveDirectory = "saveDirectory"
        static let captureSound = "captureSound"
        static let captureMuted = "captureMuted"
    }
    private let defaults: UserDefaults
    private var playingSound: NSSound?
    let availableSounds = CaptureSound.available
    private var sessionLineWidth: Double?
    private var sessionHighlightWidth: Double?
    @Published var defaultLineWidth: Double {
        didSet { defaults.set(defaultLineWidth, forKey: "defaultLineWidth"); sessionLineWidth = nil }
    }
    @Published var defaultHighlightWidth: Double {
        didSet { defaults.set(defaultHighlightWidth, forKey: "defaultHighlightWidth"); sessionHighlightWidth = nil }
    }
    func strokeWidth(highlighter: Bool) -> Double {
        highlighter ? (sessionHighlightWidth ?? defaultHighlightWidth) : (sessionLineWidth ?? defaultLineWidth)
    }
    func rememberStrokeWidth(_ width: Double, highlighter: Bool) {
        if highlighter { sessionHighlightWidth = width }
        else { sessionLineWidth = width }
    }
    @Published var lastMarkupColor: String { didSet { defaults.set(lastMarkupColor, forKey: "lastMarkupColor") } }
    @Published var lastHighlightColor: String { didSet { defaults.set(lastHighlightColor, forKey: "lastHighlightColor") } }
    @Published var defaultMarkupColor: String { didSet { defaults.set(defaultMarkupColor, forKey: "defaultMarkupColor") } }
    @Published var defaultHighlightColor: String { didSet { defaults.set(defaultHighlightColor, forKey: "defaultHighlightColor") } }
    @Published var useDefaultMarkupColor: Bool { didSet { defaults.set(useDefaultMarkupColor, forKey: "useDefaultMarkupColor") } }
    @Published var useDefaultHighlightColor: Bool { didSet { defaults.set(useDefaultHighlightColor, forKey: "useDefaultHighlightColor") } }
    func markupColor(highlighter: Bool) -> NSColor {
        NSColor(hex: highlighter
            ? (useDefaultHighlightColor ? defaultHighlightColor : lastHighlightColor)
            : (useDefaultMarkupColor ? defaultMarkupColor : lastMarkupColor)) ?? (highlighter ? .systemYellow : .systemRed)
    }

    @Published var captureSoundID: String {
        didSet { defaults.set(captureSoundID, forKey: Keys.captureSound) }
    }
    @Published var captureMuted: Bool {
        didSet {
            defaults.set(captureMuted, forKey: Keys.captureMuted)
            if captureMuted { playingSound?.stop() }
        }
    }

    func playCaptureSound() {
        guard !captureMuted else { return }
        let sound = availableSounds.first { $0.id == captureSoundID } ?? .screenshot
        playingSound?.stop()
        playingSound = NSSound(contentsOf: sound.url, byReference: true)
        playingSound?.play()
    }

    @Published var saveDirectory: URL {
        didSet {
            defaults.set(saveDirectory.path, forKey: Keys.saveDirectory)
            ensureSaveDirectoryExists()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedWidth = defaults.double(forKey: "defaultLineWidth")
        let savedHighlightWidth = defaults.double(forKey: "defaultHighlightWidth")
        defaultLineWidth = (2...60).contains(savedWidth) ? savedWidth : 6
        defaultHighlightWidth = (2...60).contains(savedHighlightWidth) ? savedHighlightWidth : 28
        lastMarkupColor = defaults.string(forKey: "lastMarkupColor") ?? "FF3B30"
        lastHighlightColor = defaults.string(forKey: "lastHighlightColor") ?? "FFCC00"
        defaultMarkupColor = defaults.string(forKey: "defaultMarkupColor") ?? "FF3B30"
        defaultHighlightColor = defaults.string(forKey: "defaultHighlightColor") ?? "FFCC00"
        useDefaultMarkupColor = defaults.bool(forKey: "useDefaultMarkupColor")
        useDefaultHighlightColor = defaults.bool(forKey: "useDefaultHighlightColor")
        let savedSound = defaults.string(forKey: Keys.captureSound)
        captureSoundID = CaptureSound.available.first { $0.id == savedSound }?.id ?? CaptureSound.screenshot.id
        captureMuted = defaults.bool(forKey: Keys.captureMuted)
        if let path = defaults.string(forKey: Keys.saveDirectory), !path.isEmpty {
            saveDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/SimpleShot", isDirectory: true)
        }
    }

    func ensureSaveDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: saveDirectory,
            withIntermediateDirectories: true
        )
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose where SimpleShot saves screenshots"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory

        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
        }
    }

    func openSaveDirectory() {
        ensureSaveDirectoryExists()
        FinderFolderOpener.open(saveDirectory)
    }
}

struct CaptureSound: Identifiable {
    let name: String
    let url: URL
    var id: String { url.path }
    static let screenshot = CaptureSound(name: "Screenshot (default)", url: URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"))
    static let available: [CaptureSound] = {
        let folders = ["/System/Library/Sounds", screenshot.url.deletingLastPathComponent().path]
        let sounds = folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
        }.filter { ["aif", "aiff", "caf", "wav"].contains($0.pathExtension.lowercased()) && $0 != screenshot.url }
         .map { CaptureSound(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
         .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return [screenshot] + sounds
    }()
}
