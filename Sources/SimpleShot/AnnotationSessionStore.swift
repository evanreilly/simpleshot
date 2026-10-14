import AppKit

struct AnnotationSessionStore {
    let url: URL

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SimpleShot/last-session.json")) {
        self.url = url
    }

    private struct Stroke: Codable {
        var points: [CGPoint]
        var rgba: [CGFloat]
        var width: CGFloat
        var kind: AnnotationKind?
        var text: String?
        var fontSize: CGFloat?
        var textBoxSize: CGSize?
        var justification: TextJustification?
    }
    private struct Session: Codable {
        var png: Data
        var strokes: [Stroke]
        var displaySize: CGSize?
        var savedURL: URL?
    }

    func save(image: CGImage, strokes: [AnnotationStroke], displaySize: CGSize? = nil, savedURL: URL? = nil) throws {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed
        }
        let session = Session(png: png, strokes: strokes.map {
            let color = $0.color.usingColorSpace(.deviceRGB) ?? .red
            return Stroke(points: $0.points, rgba: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], width: $0.width, kind: $0.kind, text: $0.text, fontSize: $0.fontSize, textBoxSize: $0.textBoxSize, justification: $0.justification)
        }, displaySize: displaySize, savedURL: savedURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }

    func load() throws -> (CGImage, [AnnotationStroke], CGSize?, URL?)? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
        guard session.strokes.allSatisfy({ $0.rgba.count == 4 }) else { throw CocoaError(.fileReadCorruptFile) }
        guard let image = NSBitmapImageRep(data: session.png)?.cgImage else { throw ScreenshotError.pngEncodingFailed }
        let strokes = session.strokes.map { stroke in
            AnnotationStroke(points: stroke.points,
                color: NSColor(deviceRed: stroke.rgba[0], green: stroke.rgba[1], blue: stroke.rgba[2], alpha: stroke.rgba[3]),
                width: stroke.width, kind: stroke.kind ?? .pen, text: stroke.text ?? "", fontSize: stroke.fontSize ?? 24, textBoxSize: stroke.textBoxSize, justification: stroke.justification ?? .left)
        }
        return (image, strokes, session.displaySize, session.savedURL)
    }
}
