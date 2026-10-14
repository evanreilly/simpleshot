import AppKit

struct ScreenSelection: Sendable {
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let rect: CGRect
}

@MainActor
final class RegionSelectionController {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<ScreenSelection?, Never>?
    private var completed = false
    private var keyMonitor: Any?
    private var precisionActive = false

    func select(precision: Bool = false) async -> ScreenSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.completed = false
            self.precisionActive = precision
            self.presentOverlays(precision: precision)
        }
    }

    @discardableResult
    func restartPrecisionSelection() -> Bool {
        guard precisionActive, !completed, continuation != nil else { return false }
        for panel in panels { (panel.contentView as? RegionSelectionView)?.resetSelection() }
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        }
        CaptureCursor.crosshair.set()
        return true
    }

    private func presentOverlays(precision: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let panel = SelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true

            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.precision = precision
            view.onBegin = { [weak self, weak view] in
                for panel in self?.panels ?? [] {
                    if let other = panel.contentView as? RegionSelectionView, other !== view { other.resetSelection() }
                }
            }
            view.canStartSelection = { [weak self, weak view] in
                !(self?.panels.contains {
                    guard let other = $0.contentView as? RegionSelectionView, other !== view else { return false }
                    return other.precision && other.hasValidSelection
                } ?? false)
            }
            view.onComplete = { [weak self, weak panel] localRect in
                guard let self, let panel else { return }
                let screenRect = panel.convertToScreen(localRect)
                guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    self.finish(with: nil)
                    return
                }
                self.finish(with: ScreenSelection(
                    displayID: displayID,
                    displayFrame: screen.frame,
                    rect: screenRect.standardized
                ))
            }
            view.onCancel = { [weak self] in self?.finish(with: nil) }
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            panels.append(panel)
        }
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            panel.makeKey()
        }
        CaptureCursor.crosshair.push()
        // Activation can briefly leave the preview/settings window as key.
        // Route capture controls to the overlay throughout the selection session.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, !self.completed, [53, 36, 76, 123, 124, 125, 126].contains(event.keyCode),
                      let panel = self.panels.first(where: { $0.isKeyWindow })
                        ?? self.panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
                      let view = panel.contentView as? RegionSelectionView else { return false }
                if event.keyCode != 53 && !view.precision { return false }
                view.keyDown(with: event)
                return true
            }
            return handled ? nil : event
        }
    }

    private func finish(with selection: ScreenSelection?) {
        guard !completed else { return }
        completed = true
        precisionActive = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        NSCursor.pop()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        continuation?.resume(returning: selection)
        continuation = nil
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private enum CaptureCursor {
    static let crosshair: NSCursor = {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 16, y: 1))
            path.line(to: NSPoint(x: 16, y: 31))
            path.move(to: NSPoint(x: 1, y: 16))
            path.line(to: NSPoint(x: 31, y: 16))
            NSColor.white.setStroke()
            path.lineWidth = 3
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }()
}

enum PrecisionSelectionEdge: CaseIterable {
    case left, right, bottom, top
    @MainActor var cursor: NSCursor {
        switch self {
        case .left, .right: .resizeLeftRight
        case .bottom, .top: .resizeUpDown
        }
    }
}

struct PrecisionSelectionGeometry {
    static func edgeHitRect(_ edge: PrecisionSelectionEdge, in rect: CGRect) -> CGRect {
        switch edge {
        case .left: CGRect(x: rect.minX - 12, y: rect.minY, width: 24, height: rect.height)
        case .right: CGRect(x: rect.maxX - 12, y: rect.minY, width: 24, height: rect.height)
        case .bottom: CGRect(x: rect.minX, y: rect.minY - 12, width: rect.width, height: 24)
        case .top: CGRect(x: rect.minX, y: rect.maxY - 12, width: rect.width, height: 24)
        }
    }
    static func edge(at point: CGPoint, in rect: CGRect) -> PrecisionSelectionEdge? {
        guard cornerIndex(at: point, in: rect) == nil else { return nil }
        func distance(_ edge: PrecisionSelectionEdge) -> CGFloat {
            switch edge {
            case .left: abs(point.x - rect.minX)
            case .right: abs(point.x - rect.maxX)
            case .bottom: abs(point.y - rect.minY)
            case .top: abs(point.y - rect.maxY)
            }
        }
        return PrecisionSelectionEdge.allCases.filter { edgeHitRect($0, in: rect).contains(point) }
            .min { distance($0) < distance($1) }
    }
    static func resized(_ rect: CGRect, edge: PrecisionSelectionEdge, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
        var result = rect
        switch edge {
        case .left:
            result.origin.x = min(max(rect.minX + dx, bounds.minX), rect.maxX - 4)
            result.size.width = rect.maxX - result.minX
        case .right:
            result.size.width = min(max(rect.maxX + dx, rect.minX + 4), bounds.maxX) - rect.minX
        case .bottom:
            result.origin.y = min(max(rect.minY + dy, bounds.minY), rect.maxY - 4)
            result.size.height = rect.maxY - result.minY
        case .top:
            result.size.height = min(max(rect.maxY + dy, rect.minY + 4), bounds.maxY) - rect.minY
        }
        return result
    }
    static func cornerHitRect(_ corner: CGPoint) -> CGRect {
        CGRect(x: corner.x - 18, y: corner.y - 18, width: 36, height: 36)
    }
    static func cornerIndex(at point: CGPoint, in rect: CGRect) -> Int? {
        let points = corners(rect)
        return points.indices.filter { cornerHitRect(points[$0]).contains(point) }
            .min { hypot(points[$0].x-point.x, points[$0].y-point.y) < hypot(points[$1].x-point.x, points[$1].y-point.y) }
    }
    static func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    static func rect(from a: CGPoint, to b: CGPoint, within bounds: CGRect) -> CGRect {
        let end = CGPoint(x: min(max(b.x, bounds.minX), bounds.maxX), y: min(max(b.y, bounds.minY), bounds.maxY))
        return CGRect(x: min(a.x, end.x), y: min(a.y, end.y), width: abs(end.x-a.x), height: abs(end.y-a.y))
    }
    static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
        CGRect(x: min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width),
               y: min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }
}

final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onBegin: (() -> Void)?
    var canStartSelection: (() -> Bool)?
    var precision = false
    private var moveStart: CGPoint?
    private var moveRect: CGRect?
    private var dragging = false
    private var adjustingSelection = false
    private var resizeEdge: PrecisionSelectionEdge?
    var hasValidSelection: Bool {
        guard let rect = selectionRect else { return false }
        return rect.width >= 4 && rect.height >= 4
    }
    var selectionCursor: NSCursor {
        guard precision else { return CaptureCursor.crosshair }
        if dragging {
            if let resizeEdge { return resizeEdge.cursor }
            return adjustingSelection ? .closedHand : CaptureCursor.crosshair
        }
        if canStartSelection?() == false { return .openHand }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else { return CaptureCursor.crosshair }
        return .openHand
    }
    private func updateCursor(with event: NSEvent? = nil) {
        if let event {
            cursor(at: convert(event.locationInWindow, from: nil)).set()
        } else {
            selectionCursor.set()
        }
    }
    func cursor(at point: CGPoint) -> NSCursor {
        if precision, !dragging {
            if (!captureButton.isHidden && captureButton.frame.contains(point)) ||
                (!cancelButton.isHidden && cancelButton.frame.contains(point)) {
                return .arrow
            }
            if hasValidSelection, let rect = selectionRect,
               let edge = PrecisionSelectionGeometry.edge(at: point, in: rect) { return edge.cursor }
            return selectionCursor
        }
        return selectionCursor
    }
    private lazy var captureButton: NSButton = {
        let button = NSButton(title: "Capture ↵", target: self, action: #selector(confirm))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.isHidden = true
        button.setAccessibilityLabel("Capture selected region")
        addSubview(button)
        return button
    }()
    private lazy var cancelButton: NSButton = {
        let button = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        button.bezelStyle = .rounded
        button.isHidden = true
        addSubview(button)
        return button
    }()
    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return PrecisionSelectionGeometry.rect(from: startPoint, to: currentPoint, within: bounds)
    }
    func resetSelection() {
        startPoint = nil; currentPoint = nil
        dragging = false; adjustingSelection = false
        resizeEdge = nil
        if precision { captureButton.isHidden = true; cancelButton.isHidden = true }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    @objc private func confirm() {
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else { return }
        onComplete?(rect)
    }
    @objc private func cancel() { onCancel?() }
    private func updateButtons() {
        guard precision else { return }
        window?.invalidateCursorRects(for: self)
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4, !dragging else {
            captureButton.isHidden = true; cancelButton.isHidden = true
            return
        }
        let x = min(max(rect.maxX - 180, 4), bounds.maxX - 184)
        let y = rect.minY >= 56 ? rect.minY - 52 : min(rect.maxY + 22, bounds.maxY - 32)
        captureButton.frame = CGRect(x: x + 76, y: y, width: 104, height: 28)
        cancelButton.frame = CGRect(x: x, y: y, width: 72, height: 28)
        captureButton.isHidden = false; cancelButton.isHidden = false
    }
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(with: event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(with: event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(with: event) }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let rect = selectionRect, let currentPoint else {
            if precision {
                let hint = "Drag a region • Adjust corners • Enter to capture • ⌘⇧2 to restart • Esc to cancel" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
                let size = hint.size(withAttributes: attributes)
                hint.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 60), withAttributes: attributes)
            }
            return
        }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
        if precision {
            for corner in PrecisionSelectionGeometry.corners(rect) {
                let handle = NSBezierPath(ovalIn: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
                NSColor.white.setFill(); handle.fill()
                NSColor.black.setStroke(); handle.lineWidth = 1; handle.stroke()
            }
        }
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let label = CGRect(x: min(max(currentPoint.x + 18, 4), bounds.maxX - size.width - 16),
                           y: min(max(currentPoint.y - 30, 4), bounds.maxY - size.height - 12),
                           width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: label.minX + 6, y: label.minY + 4), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        // Once a precision frame exists it belongs to that display until ⌘⇧2 resets it.
        guard !precision || hasValidSelection || canStartSelection?() != false else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        onBegin?()
        dragging = true
        adjustingSelection = false
        resizeEdge = nil
        let point = convert(event.locationInWindow, from: nil)
        moveStart = nil; moveRect = nil
        if precision, hasValidSelection, let rect = selectionRect {
            let corners = PrecisionSelectionGeometry.corners(rect)
            if let index = PrecisionSelectionGeometry.cornerIndex(at: point, in: rect) {
                startPoint = corners[(index + 2) % 4]
                currentPoint = corners[index]
                adjustingSelection = true
                updateButtons()
                updateCursor(with: event)
                return
            } else {
                resizeEdge = PrecisionSelectionGeometry.edge(at: point, in: rect)
                moveStart = point; moveRect = rect
                adjustingSelection = true
                updateButtons()
                updateCursor(with: event)
                return
            }
        }
        startPoint = point
        currentPoint = startPoint
        updateButtons()
        updateCursor(with: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        selectionCursor.set()
        currentPoint = convert(event.locationInWindow, from: nil)
        if let moveStart, let moveRect, let point = currentPoint {
            let moved: CGRect
            if let resizeEdge {
                moved = PrecisionSelectionGeometry.resized(moveRect, edge: resizeEdge,
                    dx: point.x-moveStart.x, dy: point.y-moveStart.y, within: bounds)
            } else {
                moved = PrecisionSelectionGeometry.moved(moveRect, dx: point.x-moveStart.x, dy: point.y-moveStart.y, within: bounds)
            }
            startPoint = moved.origin
            currentPoint = CGPoint(x: moved.maxX, y: moved.maxY)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragging = false
        guard let rect = selectionRect else { return }
        if precision { updateButtons(); updateCursor(with: event); needsDisplay = true; return }
        if rect.width >= 4, rect.height >= 4 { onComplete?(rect) }
        else { onCancel?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else if precision, [36, 76].contains(event.keyCode) { confirm() }
        else if precision, let rect = selectionRect, [123, 124, 125, 126].contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
            let moved = PrecisionSelectionGeometry.moved(rect, dx: dx, dy: dy, within: bounds)
            startPoint = moved.origin; currentPoint = CGPoint(x: moved.maxX, y: moved.maxY)
            updateButtons(); needsDisplay = true
        }
        else { super.keyDown(with: event) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: selectionCursor)
        if precision {
            if !dragging, let rect = selectionRect, rect.width >= 4, rect.height >= 4 {
                addCursorRect(rect, cursor: .openHand)
                for edge in PrecisionSelectionEdge.allCases {
                    addCursorRect(PrecisionSelectionGeometry.edgeHitRect(edge, in: rect).intersection(bounds), cursor: edge.cursor)
                }
                for corner in PrecisionSelectionGeometry.corners(rect) {
                    addCursorRect(PrecisionSelectionGeometry.cornerHitRect(corner).intersection(bounds), cursor: .openHand)
                }
            }
            if !captureButton.isHidden { addCursorRect(captureButton.frame, cursor: .arrow) }
            if !cancelButton.isHidden { addCursorRect(cancelButton.frame, cursor: .arrow) }
        }
    }
}
