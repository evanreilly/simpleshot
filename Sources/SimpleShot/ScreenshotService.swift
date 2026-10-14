import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotError: LocalizedError {
    case noDisplay
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: "SimpleShot could not find a display to capture."
        case .pngEncodingFailed: "SimpleShot could not encode the screenshot as PNG."
        }
    }
}

struct ScreenshotService {
    func verifyPermission() async throws {
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func captureDisplay(containing point: CGPoint) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(point) }) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }

        let filter = filter(for: display, from: content)
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func captureRegion(_ selection: ScreenSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenshotError.noDisplay
        }

        let displayFrame = selection.displayFrame
        let filter = filter(for: display, from: content)
        let scale = CGFloat(filter.pointPixelScale)
        let sourceRect = CGRect(
            x: selection.rect.minX - displayFrame.minX,
            y: displayFrame.maxY - selection.rect.maxY,
            width: selection.rect.width,
            height: selection.rect.height
        )

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int(sourceRect.width * scale))
        configuration.height = max(1, Int(sourceRect.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func filter(for display: SCDisplay, from content: SCShareableContent) -> SCContentFilter {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter {
            $0.bundleIdentifier == ownBundleIdentifier
        }
        return SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
    }

    @MainActor
    func copyToClipboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    func save(_ image: CGImage, in directory: URL, suffix: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let suffixPart = suffix.map { " \($0)" } ?? ""
        var url = directory.appendingPathComponent("Screenshot \(formatter.string(from: Date()))\(suffixPart).png")
        if FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("Screenshot \(formatter.string(from: Date())) \(UUID().uuidString)\(suffixPart).png")
        }
        try overwrite(image, at: url)
        return url
    }

    func overwrite(_ image: CGImage, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }
}
