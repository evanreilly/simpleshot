import AppKit

/// Keeps the editable original separate from the single, overwritten PNG export.
@MainActor
final class AnnotationAutosaver {
    private(set) var savedURL: URL?
    private let store: AnnotationSessionStore
    private let service = ScreenshotService()

    init(store: AnnotationSessionStore, savedURL: URL?) {
        self.store = store
        self.savedURL = savedURL
    }

    func save(model: AnnotationModel, directory: URL) throws {
        // Preserve editable work even if the export directory is unavailable.
        try store.save(image: model.image, strokes: model.strokes, displaySize: model.displaySize, savedURL: savedURL)
        let previousURL = savedURL
        let rendered = model.renderedImage()
        if let url = savedURL, url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path {
            try service.overwrite(rendered, at: url)
        } else {
            // A changed destination creates one new file; subsequent edits overwrite it.
            savedURL = try service.save(rendered, in: directory)
        }
        if previousURL != savedURL {
            try store.save(image: model.image, strokes: model.strokes, displaySize: model.displaySize, savedURL: savedURL)
        }
    }
}
