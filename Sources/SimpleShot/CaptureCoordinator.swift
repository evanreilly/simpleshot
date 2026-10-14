import AppKit
import ScreenCaptureKit
import Combine

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var screenCaptureAllowed = false
    @Published private(set) var isCheckingPermission = false
    @Published private(set) var permissionMessage = ""
    var onPermissionNeeded: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var capturePermissionRejected = false

    private let settings: AppSettings
    private let service = ScreenshotService()
    private let selector = RegionSelectionController()
    private var annotationController: AnnotationWindowController?
    private var annotationModel: AnnotationModel?
    private var autosaver: AnnotationAutosaver?
    private let sessionStore = AnnotationSessionStore()
    private var captureTask: Task<Void, Never>?
    private var directoryObserver: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
        directoryObserver = settings.$saveDirectory.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.saveAnnotations() }
        }
    }

    func captureRegion(precision: Bool = false) {
        guard captureTask == nil else {
            if precision { selector.restartPrecisionSelection() }
            return
        }
        guard checkCapturePermission() else { return }
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            guard let self, let selection = await selector.select(precision: precision) else { return }
            do {
                // Give WindowServer a moment to remove the selection overlay from the frame.
                try await Task.sleep(for: .milliseconds(80))
                let image = try await service.captureRegion(selection)
                permissionSucceeded()
                service.copyToClipboard(image)
                let savedURL = try service.save(image, in: settings.saveDirectory)
                setLastScreenshot(image, displaySize: selection.rect.size, savedURL: savedURL)
                settings.playCaptureSound()
            } catch {
                present(error)
            }
        }
    }

    func openLastScreenshot() {
        do {
            if annotationModel == nil {
                if let (image, strokes, displaySize, savedURL) = try sessionStore.load() {
                    setLastScreenshot(image, displaySize: displaySize, strokes: strokes, savedURL: savedURL)
                } else {
                    // Upgrade path: restore the most recent PNG saved by the earlier app.
                    let files = try FileManager.default.contentsOfDirectory(at: settings.saveDirectory,
                        includingPropertiesForKeys: [.contentModificationDateKey])
                    let latest = files.filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("Screenshot ") }
                        .sorted { lhs, rhs in
                            let a = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                            let b = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                            return a > b
                        }.first
                    if let latest, let image = NSBitmapImageRep(data: try Data(contentsOf: latest))?.cgImage {
                        setLastScreenshot(image, savedURL: latest)
                    }
                }
            }
            guard let model = annotationModel else {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "No screenshot yet"
                alert.informativeText = "Press ⌘⇧4 to capture a region, then ⌘⇧3 to annotate it."
                alert.runModal()
                return
            }
            if annotationController == nil { makeAnnotationWindow(model: model) }
            annotationController?.showWindow(nil)
        } catch {
            present(error)
        }
    }

    private func setLastScreenshot(_ image: CGImage, displaySize: CGSize? = nil, strokes: [AnnotationStroke] = [], savedURL: URL? = nil) {
        annotationController?.close()
        annotationController = nil
        autosaver = AnnotationAutosaver(store: sessionStore, savedURL: savedURL)
        annotationModel = AnnotationModel(image: image, displaySize: displaySize, strokes: strokes,
            onCopy: { [service] in service.copyToClipboard($0) },
            onChange: { [weak self] _, _ in self?.saveAnnotations() })
        persistSession(image, strokes: strokes)
    }

    private func persistSession(_ image: CGImage, strokes: [AnnotationStroke]) {
        do { try sessionStore.save(image: image, strokes: strokes, displaySize: annotationModel?.displaySize, savedURL: autosaver?.savedURL) }
        catch { present(error) }
    }

    func saveAnnotations() {
        guard let model = annotationModel else { return }
        do {
            try autosaver?.save(model: model, directory: settings.saveDirectory)
            model.saveError = nil
        } catch {
            model.saveError = "Could not auto-save: \(error.localizedDescription)"
        }
    }

    func openSaveDirectory() {
        settings.openSaveDirectory()
    }

    func requestPermission() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func checkPermissionOnSettingsOpen() {
        guard !isCheckingPermission else { return }
        // This status check never requests permission or blocks the capture shortcut.
        if CGPreflightScreenCaptureAccess() {
            verifyPermission()
        } else {
            screenCaptureAllowed = false
            permissionMessage = "Screen capture access is not currently confirmed. Click Request Screen Access to ask macOS for permission."
        }
    }

    func requestScreenAccess() {
        if CGRequestScreenCaptureAccess() { verifyPermission() }
        else {
            screenCaptureAllowed = false
            permissionMessage = "Enable SimpleShot in Screen Recording settings, then return here. macOS may require quitting and reopening after a permission change."
            requestPermission()
        }
    }

    func verifyPermission() {
        guard !isCheckingPermission, captureTask == nil else { return }
        isCheckingPermission = true
        Task { [weak self] in
            guard let self else { return }
            defer { isCheckingPermission = false }
            do {
                try await service.verifyPermission()
                permissionSucceeded()
            } catch {
                screenCaptureAllowed = false
                permissionMessage = "Screen capture verification failed: \(error.localizedDescription)"
            }
        }
    }

    private func permissionSucceeded() {
        screenCaptureAllowed = true
        capturePermissionRejected = false
        permissionMessage = "ScreenCaptureKit access verified."
        lastError = nil
    }

    private func checkCapturePermission() -> Bool {
        guard !isCheckingPermission else { return false }
        guard !capturePermissionRejected else {
            onPermissionNeeded?()
            return false
        }
        return true
    }

    private func makeAnnotationWindow(model: AnnotationModel) {
        let controller = AnnotationWindowController(
            model: model,
            settings: settings,
            onOpenSettings: { [weak self] in self?.onOpenSettings?() }
        )
        annotationController = controller
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
            capturePermissionRejected = true
            screenCaptureAllowed = false
            permissionMessage = "ScreenCaptureKit denied access to the running app. Enable SimpleShot in System Settings, then return here or click Check Again."
            onPermissionNeeded?()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
