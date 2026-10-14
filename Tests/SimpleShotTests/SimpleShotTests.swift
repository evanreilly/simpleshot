import XCTest
import Carbon
@testable import SimpleShot

final class SimpleShotTests: XCTestCase {
    @MainActor
    func testFinderOpeningRequiresConfirmedDestination() {
        let expected = URL(fileURLWithPath: "/Users/example/screenshots", isDirectory: true)
        XCTAssertTrue(FinderFolderOpener.confirmsDirectory("/Users/example/screenshots/", expected: expected))
        XCTAssertFalse(FinderFolderOpener.confirmsDirectory(nil, expected: expected))
        XCTAssertFalse(FinderFolderOpener.confirmsDirectory("", expected: expected))
        XCTAssertFalse(FinderFolderOpener.confirmsDirectory("/Users/example", expected: expected))
        XCTAssertFalse(FinderFolderOpener.confirmsDirectory("/", expected: expected))
    }

    @MainActor
    func testFinderScriptCompilesAndPathIsPassedAsData() throws {
        let script = try XCTUnwrap(NSAppleScript(source: FinderFolderOpener.scriptSource))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
        let path = "/tmp/Screenshots with spaces \"quotes\" \\ slash\nand newline"
        let event = FinderFolderOpener.event(for: URL(fileURLWithPath: path))
        let arguments = try XCTUnwrap(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
        XCTAssertEqual(arguments.atIndex(1)?.stringValue, path)
        XCTAssertEqual(event.paramDescriptor(forKeyword: AEKeyword(keyASSubroutineName))?.stringValue, "openscreenshotfolder")
    }

    @MainActor
    func testThicknessSurvivesToolChangesAndNewScreenshotsForSession() throws {
        let suite = "SimpleShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let model = AnnotationModel(image: image, onCopy: { _ in })
        model.preferences = settings
        model.chooseTool(.line)
        model.updateSelected(width: 11)
        model.chooseTool(.rectangle)
        XCTAssertEqual(model.lineWidth, 11)
        model.chooseTool(.highlighter)
        XCTAssertEqual(model.lineWidth, 28)
        model.updateSelected(width: 36)
        model.chooseTool(.arrow)
        XCTAssertEqual(model.lineWidth, 11)
        model.chooseTool(.highlighter)
        XCTAssertEqual(model.lineWidth, 36)
        let nextScreenshot = AnnotationModel(image: image, onCopy: { _ in })
        let controller = AnnotationWindowController(model: nextScreenshot, settings: settings)
        XCTAssertEqual(nextScreenshot.lineWidth, 11)
        nextScreenshot.chooseTool(.highlighter)
        XCTAssertEqual(nextScreenshot.lineWidth, 36)
        controller.close()
        let nextLaunch = AppSettings(defaults: defaults)
        XCTAssertEqual(nextLaunch.strokeWidth(highlighter: false), 6)
        XCTAssertEqual(nextLaunch.strokeWidth(highlighter: true), 28)
        settings.defaultLineWidth = 9
        model.chooseTool(.line)
        XCTAssertEqual(model.lineWidth, 9)
        XCTAssertEqual(AppSettings(defaults: defaults).defaultLineWidth, 9)
    }

    @MainActor
    func testMarqueeCanStartOutsideImageWithoutScalingAnnotations() throws {
        let imageSize = CGSize(width: 400, height: 300)
        let rect = AnnotationCanvasGeometry.imageRect(imageSize: imageSize, canvasSize: CGSize(width: 880, height: 500))
        XCTAssertEqual(rect, CGRect(x: 240, y: 0, width: 400, height: 300))
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = AnnotationModel(image: try XCTUnwrap(context.makeImage()), onCopy: { _ in })
        model.beginStroke(at: CGPoint(x: 0.2, y: 0.2))
        model.continueStroke(at: CGPoint(x: 0.8, y: 0.8))
        model.finishStroke()
        let original = model.strokes[0].points
        model.chooseTool(.select)
        let outside = AnnotationCanvasGeometry.normalized(CGPoint(x: 50, y: 400), imageRect: rect, clamp: false)
        XCTAssertLessThan(outside.x, 0)
        XCTAssertGreaterThan(outside.y, 1)
        model.beginInteraction(at: outside)
        model.updateInteraction(at: AnnotationCanvasGeometry.normalized(CGPoint(x: 700, y: 0), imageRect: rect, clamp: false))
        XCTAssertEqual(model.marquee?.minX, -190)
        XCTAssertEqual(model.selectedIDs.count, 1)
        model.endInteraction()
        XCTAssertEqual(model.strokes[0].points, original)
        model.beginInteraction(at: AnnotationCanvasGeometry.normalized(CGPoint(x: 320, y: 60), imageRect: rect, clamp: false))
        model.updateInteraction(at: AnnotationCanvasGeometry.normalized(CGPoint(x: 360, y: 90), imageRect: rect, clamp: false))
        model.endInteraction()
        XCTAssertEqual(model.strokes[0].points[0].x, 0.3, accuracy: 0.001)
        XCTAssertEqual(model.strokes[0].points[0].y, 0.3, accuracy: 0.001)
        XCTAssertEqual(model.renderedImage().width, 400)
        XCTAssertEqual(AnnotationCanvasGeometry.normalized(CGPoint(x: 50, y: 400), imageRect: rect, clamp: true), CGPoint(x: 0, y: 1))
        let scrolledContent = AnnotationCanvasGeometry.imageRect(imageSize: imageSize, canvasSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(scrolledContent.origin, .zero)
    }

    @MainActor
    func testPrecisionEdgeCursorsAndSingleAxisDragging() throws {
        for edge in PrecisionSelectionEdge.allCases {
            let view = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            view.precision = true
            var captured: CGRect?
            view.onComplete = { captured = $0 }
            func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
            view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 250)))
            let point: CGPoint
            let expected: CGRect
            switch edge {
            case .left:
                point = CGPoint(x: 92, y: 175)
                expected = CGRect(x: 150, y: 100, width: 150, height: 150)
            case .right:
                point = CGPoint(x: 308, y: 175)
                expected = CGRect(x: 100, y: 100, width: 250, height: 150)
            case .bottom:
                point = CGPoint(x: 200, y: 92)
                expected = CGRect(x: 100, y: 150, width: 200, height: 100)
            case .top:
                point = CGPoint(x: 200, y: 258)
                expected = CGRect(x: 100, y: 100, width: 200, height: 200)
            }
            XCTAssertEqual(view.cursor(at: point), edge.cursor)
            view.mouseDown(with: mouse(.leftMouseDown, point))
            XCTAssertEqual(view.selectionCursor, edge.cursor)
            let destination = CGPoint(x: point.x + 50, y: point.y + 50)
            view.mouseDragged(with: mouse(.leftMouseDragged, destination))
            view.mouseUp(with: mouse(.leftMouseUp, destination))
            XCTAssertNil(captured)
            let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("Capture") })
            button.performClick(nil)
            XCTAssertEqual(captured, expected)
        }
    }

    func testPrecisionEdgesClampAndCornersTakePriority() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(PrecisionSelectionGeometry.edge(at: CGPoint(x: 108, y: 108), in: rect))
        let minimum = PrecisionSelectionGeometry.resized(rect, edge: .left, dx: 500, dy: 500, within: bounds)
        XCTAssertEqual(minimum.width, 4)
        XCTAssertEqual(minimum.maxX, rect.maxX)
        XCTAssertEqual(minimum.height, rect.height)
        let maximum = PrecisionSelectionGeometry.resized(rect, edge: .top, dx: 500, dy: 900, within: bounds)
        XCTAssertEqual(maximum.maxY, bounds.maxY)
        XCTAssertEqual(maximum.width, rect.width)
    }

    @MainActor
    func testPrecisionWaitsForConfirmationAndCornerCanResize() throws {
        let view = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.precision = true
        let drawingCursor = view.selectionCursor
        var captured: CGRect?
        view.onComplete = { captured = $0 }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 250)))
        XCTAssertEqual(view.selectionCursor, drawingCursor)
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 250)))
        XCTAssertEqual(view.selectionCursor, NSCursor.openHand)
        XCTAssertNil(captured)
        // The full 36-point corner target must show the same cursor as its drag action,
        // including outside the visible box and beyond the former 12-point radius.
        let nearCorner = CGPoint(x: 315, y: 265)
        XCTAssertEqual(view.cursor(at: nearCorner), NSCursor.openHand)
        XCTAssertEqual(PrecisionSelectionGeometry.cornerIndex(at: nearCorner, in: CGRect(x: 100, y: 100, width: 200, height: 150)), 2)
        XCTAssertEqual(view.cursor(at: CGPoint(x: 340, y: 290)), NSCursor.openHand)
        view.mouseDown(with: mouse(.leftMouseDown, nearCorner))
        XCTAssertEqual(view.selectionCursor, NSCursor.closedHand)
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 350, y: 280)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 350, y: 280)))
        XCTAssertEqual(view.selectionCursor, NSCursor.openHand)
        XCTAssertNil(captured)
        let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("Capture") })
        XCTAssertFalse(button.isHidden)
        button.performClick(nil)
        XCTAssertEqual(captured, CGRect(x: 100, y: 100, width: 250, height: 180))
        captured = nil
        // Dragging away from the frame moves it; it must never replace the selection.
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 500, y: 500)))
        XCTAssertEqual(view.selectionCursor, NSCursor.closedHand)
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 520, y: 520)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 520, y: 520)))
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        view.keyDown(with: enter)
        XCTAssertEqual(captured, CGRect(x: 120, y: 120, width: 250, height: 180))
        view.resetSelection()
        XCTAssertEqual(view.selectionCursor, drawingCursor)
        captured = nil
        view.keyDown(with: enter)
        XCTAssertNil(captured)
    }

    func testPrecisionCornersClampingAndMovement() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let rect = CGRect(x: 100, y: 100, width: 200, height: 150)
        let corners = PrecisionSelectionGeometry.corners(rect)
        XCTAssertEqual(corners.count, 4)
        for index in corners.indices {
            let opposite = corners[(index + 2) % 4]
            XCTAssertEqual(PrecisionSelectionGeometry.rect(from: opposite, to: corners[index], within: bounds), rect)
        }
        let reversed = PrecisionSelectionGeometry.rect(from: CGPoint(x: 400, y: 400), to: CGPoint(x: 50, y: 60), within: bounds)
        XCTAssertEqual(reversed, CGRect(x: 50, y: 60, width: 350, height: 340))
        let clamped = PrecisionSelectionGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 900, y: 700), within: bounds)
        XCTAssertEqual(clamped.maxX, 800)
        XCTAssertEqual(clamped.maxY, 600)
        let moved = PrecisionSelectionGeometry.moved(rect, dx: 900, dy: -900, within: bounds)
        XCTAssertEqual(moved, CGRect(x: 600, y: 0, width: 200, height: 150))
    }

    @MainActor
    func testDefaultThicknessPersistsAndPopulatesTools() throws {
        let suite = "SimpleShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.defaultLineWidth, 6)
        XCTAssertEqual(settings.defaultHighlightWidth, 28)
        settings.defaultLineWidth = 12
        settings.defaultHighlightWidth = 40
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.defaultLineWidth, 12)
        XCTAssertEqual(restored.defaultHighlightWidth, 40)
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = AnnotationModel(image: try XCTUnwrap(context.makeImage()), onCopy: { _ in })
        model.preferences = restored
        model.chooseTool(.arrow)
        XCTAssertEqual(model.lineWidth, 12)
        model.chooseTool(.highlighter)
        XCTAssertEqual(model.lineWidth, 40)
    }

    @MainActor
    func testAutosaveOverwritesSamePNGAndRetainsEditableOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationSessionStore(url: folder.appendingPathComponent("session.json"))
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let original = try XCTUnwrap(context.makeImage())
        let model = AnnotationModel(image: original, onCopy: { _ in })
        let outputDirectory = folder.appendingPathComponent("screenshots")
        let saver = AnnotationAutosaver(store: store, savedURL: nil)
        try saver.save(model: model, directory: outputDirectory)
        let url = try XCTUnwrap(saver.savedURL)
        let originalData = try Data(contentsOf: url)
        model.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        model.continueStroke(at: CGPoint(x: 0.8, y: 0.8))
        model.finishStroke()
        try saver.save(model: model, directory: outputDirectory)
        XCTAssertEqual(saver.savedURL, url)
        XCTAssertNotEqual(try Data(contentsOf: url), originalData)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.3, url)
        XCTAssertEqual(restored.1.count, 1)
        XCTAssertEqual(NSBitmapImageRep(cgImage: restored.0).colorAt(x: 50, y: 50)?.alphaComponent, 0)
        let reopenedSaver = AnnotationAutosaver(store: store, savedURL: restored.3)
        model.clear()
        try reopenedSaver.save(model: model, directory: outputDirectory)
        XCTAssertEqual(try Data(contentsOf: url), originalData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).count, 1)
        let newDirectory = folder.appendingPathComponent("new-location")
        try reopenedSaver.save(model: model, directory: newDirectory)
        XCTAssertEqual(reopenedSaver.savedURL?.deletingLastPathComponent().path, newDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testSharedColorAndThicknessFollowTool() throws {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = AnnotationModel(image: try XCTUnwrap(context.makeImage()), onCopy: { _ in })
        model.chooseTool(.highlighter)
        XCTAssertTrue(model.usesHighlighterColor)
        XCTAssertEqual(model.lineWidth, 28)
        model.chooseColor(.yellow, highlighter: model.usesHighlighterColor)
        XCTAssertEqual(model.activeColor.hex, NSColor.yellow.hex)
        model.beginStroke(at: CGPoint(x: 0.1, y: 0.1))
        model.continueStroke(at: CGPoint(x: 0.8, y: 0.8))
        model.finishStroke()
        model.chooseTool(.arrow)
        XCTAssertFalse(model.usesHighlighterColor)
        XCTAssertEqual(model.lineWidth, 6)
        model.chooseTool(.select)
        model.beginInteraction(at: CGPoint(x: 0.5, y: 0.5))
        model.endInteraction()
        XCTAssertTrue(model.usesHighlighterColor)
        XCTAssertEqual(model.lineWidth, 28)
        XCTAssertEqual(model.activeColor.hex, NSColor.yellow.hex)
    }

    @MainActor
    func testTextOverflowAlignmentAndFreshPlaceholder() throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let model = AnnotationModel(image: image, onCopy: { _ in })
        model.chooseTool(.text)
        model.beginInteraction(at: CGPoint(x: 0.1, y: 0.1))
        model.endInteraction()
        XCTAssertEqual(model.selected?.text, "text")
        XCTAssertEqual(model.pendingTextReplacementID, model.selectedID)
        model.updateSelected(text: "One two three four five six seven")
        XCTAssertNil(model.pendingTextReplacementID)
        model.beginTextResize()
        model.resizeText(to: CGSize(width: 100, height: 30))
        model.finishTextResize()
        let object = try XCTUnwrap(model.selected)
        XCTAssertEqual(object.bounds(in: model.displaySize, referenceSize: model.displaySize).height, 30)
        XCTAssertGreaterThan(object.contentBounds(in: model.displaySize, referenceSize: model.displaySize).height, 60)
        let pixels = NSBitmapImageRep(cgImage: model.renderedImage())
        var overflowPixels = 0
        for y in 65..<230 {
            for x in 40..<140 {
                if (pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { overflowPixels += 1 }
            }
        }
        XCTAssertGreaterThan(overflowPixels, 100, "Wrapped text below the resize box must remain visible in exports")
        model.updateSelected(text: "Hi", justification: .left)
        let leftImage = try XCTUnwrap(model.renderedImage().dataProvider?.data) as Data
        model.updateSelected(justification: .center)
        let centerImage = try XCTUnwrap(model.renderedImage().dataProvider?.data) as Data
        model.updateSelected(justification: .right)
        let rightImage = try XCTUnwrap(model.renderedImage().dataProvider?.data) as Data
        XCTAssertNotEqual(leftImage, centerImage)
        XCTAssertNotEqual(centerImage, rightImage)
        XCTAssertEqual(model.selected?.textBoxSize, CGSize(width: 100, height: 30))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationSessionStore(url: folder.appendingPathComponent("session.json"))
        try store.save(image: image, strokes: model.strokes, displaySize: model.displaySize)
        XCTAssertEqual(try store.load()?.1.first?.justification, .right)
        model.chooseTool(.text)
        model.beginInteraction(at: CGPoint(x: 0.6, y: 0.2))
        model.endInteraction()
        XCTAssertEqual(model.selected?.text, "text")
        XCTAssertEqual(model.selected?.justification, .left)
    }

    @MainActor
    func testMarqueeGroupMoveDeleteAndUndo() throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = AnnotationModel(image: try XCTUnwrap(context.makeImage()), onCopy: { _ in })
        for x in [0.2, 0.4, 0.8] {
            model.chooseTool(.line)
            model.beginInteraction(at: CGPoint(x: x, y: 0.2))
            model.updateInteraction(at: CGPoint(x: x + 0.1, y: 0.3))
            model.endInteraction()
        }
        let original = model.strokes.map(\.points)
        model.chooseTool(.select)
        model.beginInteraction(at: CGPoint(x: 0.1, y: 0.1))
        model.updateInteraction(at: CGPoint(x: 0.6, y: 0.4))
        XCTAssertNotNil(model.marquee)
        model.endInteraction()
        XCTAssertNil(model.marquee)
        XCTAssertEqual(model.selectedIDs.count, 2)
        model.beginInteraction(at: CGPoint(x: 0.3, y: 0.25))
        model.updateInteraction(at: CGPoint(x: 0.4, y: 0.45))
        model.endInteraction()
        XCTAssertEqual(model.strokes[0].points[0].x, 0.3, accuracy: 0.001)
        XCTAssertEqual(model.strokes[1].points[0].y, 0.4, accuracy: 0.001)
        XCTAssertEqual(model.strokes[2].points, original[2])
        model.undo()
        XCTAssertEqual(model.strokes.map(\.points), original)
        model.beginInteraction(at: CGPoint(x: 0.6, y: 0.4))
        model.updateInteraction(at: CGPoint(x: 0.1, y: 0.1))
        model.endInteraction()
        XCTAssertEqual(model.selectedIDs.count, 2)
        model.deleteSelected()
        XCTAssertEqual(model.strokes.count, 1)
        model.undo()
        XCTAssertEqual(model.strokes.count, 3)
    }

    @MainActor
    func testTextBoxResizePersistsAndUndoRestoresSize() throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let model = AnnotationModel(image: image, onCopy: { _ in })
        model.chooseTool(.text)
        model.beginInteraction(at: CGPoint(x: 0.1, y: 0.2))
        model.endInteraction()
        let initialSize = model.selected?.textBoxSize
        model.updateSelected(text: "Text that wraps onto several lines")
        model.beginTextResize()
        model.resizeText(to: CGSize(width: 120, height: 160))
        model.resizeText(to: CGSize(width: 100, height: 180))
        model.finishTextResize()
        let box = try XCTUnwrap(model.selected).bounds(in: model.displaySize, referenceSize: model.displaySize)
        XCTAssertEqual(box.origin, CGPoint(x: 40, y: 60))
        XCTAssertEqual(box.size, CGSize(width: 100, height: 180))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationSessionStore(url: folder.appendingPathComponent("session.json"))
        try store.save(image: image, strokes: model.strokes, displaySize: model.displaySize)
        XCTAssertEqual(try store.load()?.1.first?.textBoxSize, box.size)
        XCTAssertEqual(model.renderedImage().height, 300)
        model.undo()
        XCTAssertEqual(model.strokes.first?.textBoxSize, initialSize)
    }

    @MainActor
    func testMarkupColorsPersistAndDefaultsOverride() throws {
        let suite = "SimpleShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.lastMarkupColor = "123456"
        settings.lastHighlightColor = "ABCDEF"
        var restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.markupColor(highlighter: false).hex, "123456")
        XCTAssertEqual(restored.markupColor(highlighter: true).hex, "ABCDEF")
        settings.defaultMarkupColor = "FF0000"
        settings.defaultHighlightColor = "FFFF00"
        settings.useDefaultMarkupColor = true
        settings.useDefaultHighlightColor = true
        restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.markupColor(highlighter: false).hex, "FF0000")
        XCTAssertEqual(restored.markupColor(highlighter: true).hex, "FFFF00")
        restored.useDefaultMarkupColor = false
        XCTAssertEqual(restored.markupColor(highlighter: false).hex, "123456")
    }

    @MainActor
    func testHighlighterAndKeyboardEditing() throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let model = AnnotationModel(image: try XCTUnwrap(context.makeImage()), onCopy: { _ in })
        let suite = "SimpleShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AnnotationWindowController(model: model, settings: AppSettings(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        model.chooseTool(.highlighter)
        model.chooseColor(.yellow, highlighter: true)
        model.beginInteraction(at: CGPoint(x: 0.1, y: 0.5))
        model.updateInteraction(at: CGPoint(x: 0.5, y: 0.5))
        model.updateInteraction(at: CGPoint(x: 0.9, y: 0.5))
        model.endInteraction()
        XCTAssertEqual(model.selected?.points.count, 3)
        let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: model.renderedImage()).colorAt(x: 200, y: 150)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(pixel.blueComponent, 0.5)
        XCTAssertLessThan(pixel.blueComponent, 0.9)
        func key(_ code: UInt16, _ chars: String, _ modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            window.sendEvent(event)
        }
        key(51, "\u{7f}")
        XCTAssertTrue(model.strokes.isEmpty)
        key(6, "z", .control)
        XCTAssertEqual(model.strokes.count, 1)
        key(6, "z", .command)
        XCTAssertTrue(model.strokes.isEmpty)
        model.chooseTool(.text)
        model.beginInteraction(at: CGPoint(x: 0.2, y: 0.2))
        model.endInteraction()
        XCTAssertEqual(model.editingTextID, model.selectedID)
        model.chooseTool(.arrow)
        XCTAssertNil(model.editingTextID)
        controller.close()
    }

    @MainActor
    func testTextRendersAndEditsRefreshClipboard() async throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let original = try XCTUnwrap(context.makeImage())
        var copies = 0
        let model = AnnotationModel(image: original, onCopy: { _ in copies += 1 })
        model.tool = .text
        model.beginInteraction(at: CGPoint(x: 0.1, y: 0.1))
        model.endInteraction()
        model.updateSelected(text: "Test", fontSize: 32)
        let rendered = NSBitmapImageRep(cgImage: model.renderedImage())
        var visiblePixels = 0
        for y in 30..<80 {
            for x in 40..<140 {
                if (rendered.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { visiblePixels += 1 }
            }
        }
        XCTAssertGreaterThan(visiblePixels, 100, "Text must render at the same top-left location as the preview")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(copies, 1)
        model.updateSelected(text: "Edited")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(copies, 2)
    }

    @MainActor
    func testShapesTextMovementUndoAndPersistence() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = try XCTUnwrap(bitmap.cgImage)
        let model = AnnotationModel(image: image, displaySize: CGSize(width: 400, height: 300), onCopy: { _ in })
        for kind in [AnnotationKind.arrow, .line, .rectangle, .ellipse, .text] {
            model.tool = kind
            model.beginInteraction(at: CGPoint(x: 0.2, y: 0.2))
            model.updateInteraction(at: CGPoint(x: 0.6, y: 0.6))
            model.endInteraction()
        }
        model.updateSelected(text: "Hello\nScreenshot", fontSize: 32)
        XCTAssertEqual(model.strokes.count, 5)
        XCTAssertEqual(model.selected?.text, "Hello\nScreenshot")
        let original = model.strokes.last!.points
        model.tool = .select
        model.beginInteraction(at: CGPoint(x: 0.21, y: 0.21))
        model.updateInteraction(at: CGPoint(x: 0.31, y: 0.41))
        model.endInteraction()
        XCTAssertEqual(model.selected?.kind, .text)
        XCTAssertEqual(model.strokes.last!.points[0].x, 0.3, accuracy: 0.001)
        model.undo()
        XCTAssertEqual(model.strokes.last!.points, original)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AnnotationSessionStore(url: directory.appendingPathComponent("session.json"))
        try store.save(image: image, strokes: model.strokes, displaySize: model.displaySize)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.1.map(\.kind), [.arrow, .line, .rectangle, .ellipse, .text])
        XCTAssertEqual(restored.1.last?.fontSize, 32)
        XCTAssertEqual(restored.1.last?.text, "Hello\nScreenshot")
        XCTAssertEqual(model.renderedImage().width, 800)
        XCTAssertTrue(model.strokes[0].hitTest(CGPoint(x: 160, y: 120), size: model.displaySize, referenceSize: model.displaySize))
        XCTAssertFalse(model.strokes[0].hitTest(CGPoint(x: 390, y: 10), size: model.displaySize, referenceSize: model.displaySize))
        model.clear()
        XCTAssertTrue(model.strokes.isEmpty)
        model.undo()
        XCTAssertEqual(model.strokes.count, 5)
        // Older sessions lack the new optional object fields.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        var legacy = try XCTUnwrap(json["strokes"] as? [[String: Any]])
        for index in legacy.indices {
            legacy[index].removeValue(forKey: "kind")
            legacy[index].removeValue(forKey: "text")
            legacy[index].removeValue(forKey: "fontSize")
        }
        json["strokes"] = legacy
        try JSONSerialization.data(withJSONObject: json).write(to: store.url)
        XCTAssertTrue(try XCTUnwrap(store.load()).1.allSatisfy { $0.kind == .pen })
    }

    @MainActor
    func testSoundAndMutePersistAcrossSettingsInstances() throws {
        let suite = "SimpleShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.captureMuted)
        XCTAssertEqual(settings.captureSoundID, CaptureSound.screenshot.id)
        let alternative = try XCTUnwrap(settings.availableSounds.first { $0.name == "Glass" })
        settings.captureSoundID = alternative.id
        settings.captureMuted = true
        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.captureMuted)
        XCTAssertEqual(restored.captureSoundID, alternative.id)
        restored.captureMuted = false
        XCTAssertFalse(AppSettings(defaults: defaults).captureMuted)
        defaults.set("/missing/sound.aif", forKey: "captureSound")
        XCTAssertEqual(AppSettings(defaults: defaults).captureSoundID, CaptureSound.screenshot.id)
    }

    @MainActor
    func testAnnotationsSurviveReloadAndClearPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AnnotationSessionStore(url: directory.appendingPathComponent("session.json"))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = try XCTUnwrap(bitmap.cgImage)
        let displaySize = CGSize(width: 4, height: 4)
        let model = AnnotationModel(image: image, displaySize: displaySize, onCopy: { _ in }, onChange: { image, strokes in
            do { try store.save(image: image, strokes: strokes, displaySize: displaySize) }
            catch { XCTFail("Session save failed: \(error)") }
        })
        model.beginStroke(at: CGPoint(x: 0.2, y: 0.3))
        model.continueStroke(at: CGPoint(x: 0.8, y: 0.7))
        model.finishStroke()
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.0.width, 8)
        XCTAssertEqual(restored.2, displaySize)
        XCTAssertEqual(restored.1.count, 1)
        XCTAssertEqual(restored.1[0].points, model.strokes[0].points)
        let reopened = AnnotationModel(image: restored.0, displaySize: restored.2, strokes: restored.1, onCopy: { _ in })
        XCTAssertEqual(reopened.displaySize, displaySize)
        XCTAssertEqual(reopened.renderedImage().width, 8)
        let controller = AnnotationWindowController(model: reopened, settings: AppSettings())
        controller.close()
        XCTAssertEqual(reopened.strokes.count, 1)
        model.clear()
        XCTAssertEqual(try store.load()?.1.count, 0)
    }

    @MainActor
    func testOnlyEnabledMatchingSystemShortcutBlocksRegistration() {
        let key: [String: Any] = [
            kHISymbolicHotKeyCode as String: NSNumber(value: kVK_ANSI_3),
            kHISymbolicHotKeyModifiers as String: NSNumber(value: cmdKey | shiftKey),
            kHISymbolicHotKeyEnabled as String: NSNumber(value: true)
        ]
        let modifiers = UInt32(cmdKey | shiftKey)
        XCTAssertTrue(HotKeyManager.isSystemReserved(code: UInt32(kVK_ANSI_3), modifiers: modifiers, keys: [key]))
        XCTAssertFalse(HotKeyManager.isSystemReserved(code: UInt32(kVK_ANSI_4), modifiers: modifiers, keys: [key]))
        XCTAssertFalse(HotKeyManager.isSystemReserved(code: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey), keys: [key]))
        var disabled = key
        disabled[kHISymbolicHotKeyEnabled as String] = NSNumber(value: false)
        XCTAssertFalse(HotKeyManager.isSystemReserved(code: UInt32(kVK_ANSI_3), modifiers: modifiers, keys: [disabled]))
        XCTAssertNotEqual(HotKeyManager.registrationMessage(OSStatus(eventHotKeyExistsErr)), "Ready")
    }

    func testAspectFitLandscapeImage() {
        let fitted = CGSize(width: 2000, height: 1000).aspectFit(in: CGSize(width: 800, height: 800))
        XCTAssertEqual(fitted.width, 800, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 400, accuracy: 0.001)
    }

    func testAspectFitPortraitImage() {
        let fitted = CGSize(width: 1000, height: 2000).aspectFit(in: CGSize(width: 800, height: 600))
        XCTAssertEqual(fitted.width, 300, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 600, accuracy: 0.001)
    }
}
