import AppKit
import SwiftUI

enum AnnotationKind: String, Codable, CaseIterable {
    case select = "Select", pen = "Pen", line = "Line", arrow = "Arrow"
    case rectangle = "Box", ellipse = "Ellipse", text = "Text"
    case highlighter = "Highlighter"
    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .text: "textformat"
        case .highlighter: "highlighter"
        }
    }
}

enum TextJustification: String, Codable, CaseIterable {
    case left, center, right
    var alignment: NSTextAlignment {
        switch self { case .left: .left; case .center: .center; case .right: .right }
    }
    var icon: String { "text.align" + rawValue }
}

struct AnnotationStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var kind: AnnotationKind = .pen
    var text: String = ""
    var fontSize: CGFloat = 24
    var textBoxSize: CGSize?
    var justification: TextJustification = .left

    func path(in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let start = points.first else { return path }
        let a = CGPoint(x: start.x * size.width, y: start.y * size.height)
        let end = points.last ?? start
        let b = CGPoint(x: end.x * size.width, y: end.y * size.height)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x-a.x), height: abs(b.y-a.y))
        switch kind {
        case .rectangle: path.addRect(rect)
        case .ellipse: path.addEllipse(in: rect)
        case .text, .select: break
        default:
            path.move(to: a)
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
            if points.count == 1 { path.addLine(to: CGPoint(x: a.x + 0.01, y: a.y)) }
            if kind == .arrow {
                let angle = atan2(b.y-a.y, b.x-a.x)
                let length = min(hypot(b.x-a.x, b.y-a.y) * 0.4, max(12, width * 4) * size.width / 1000)
                for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                    path.move(to: b)
                    path.addLine(to: CGPoint(x: b.x-length*cos(angle+offset), y: b.y-length*sin(angle+offset)))
                }
            }
        }
        return path
    }

    func textAttributes(in size: CGSize, referenceSize: CGSize) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = justification.alignment
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: fontSize * size.width / max(referenceSize.width, 1), weight: .semibold),
                .foregroundColor: color, .paragraphStyle: paragraph]
    }

    // The box controls wrapping width, not clipping height.
    func contentBounds(in size: CGSize, referenceSize: CGSize) -> CGRect {
        var rect = bounds(in: size, referenceSize: referenceSize)
        guard kind == .text else { return rect }
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes(in: size, referenceSize: referenceSize))
        let lineHeight = fontSize * size.width / max(referenceSize.width, 1) * 1.25
        rect.size.height = max(rect.height, ceil(measured.height) + lineHeight)
        return rect
    }

    func bounds(in size: CGSize, referenceSize: CGSize) -> CGRect {
        if kind == .text, let point = points.first {
            if let textBoxSize {
                let scale = size.width / max(referenceSize.width, 1)
                return CGRect(x: point.x * size.width, y: point.y * size.height,
                              width: textBoxSize.width * scale, height: textBoxSize.height * scale)
            }
            let dimensions = (text as NSString).size(withAttributes: textAttributes(in: size, referenceSize: referenceSize))
            return CGRect(x: point.x * size.width, y: point.y * size.height,
                          width: max(dimensions.width, 12), height: max(dimensions.height, 12))
        }
        return path(in: size).boundingBoxOfPath
    }

    func hitTest(_ point: CGPoint, size: CGSize, referenceSize: CGSize) -> Bool {
        if kind == .text { return contentBounds(in: size, referenceSize: referenceSize).insetBy(dx: -5, dy: -5).contains(point) }
        return path(in: size).copy(strokingWithWidth: max(10, width * size.width / 1000 + 8),
                                  lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }

    func draw(in context: CGContext, size: CGSize, referenceSize: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        if kind == .text, let point = points.first {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            if textBoxSize != nil {
                let rect = contentBounds(in: size, referenceSize: referenceSize)
                (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                       attributes: textAttributes(in: size, referenceSize: referenceSize))
            } else {
                (text as NSString).draw(at: CGPoint(x: point.x * size.width, y: point.y * size.height),
                                       withAttributes: textAttributes(in: size, referenceSize: referenceSize))
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            if kind == .highlighter { context.setAlpha(0.35) }
            context.addPath(path(in: size))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width * size.width / 1000)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }
}

@MainActor
final class AnnotationModel: ObservableObject {
    let image: CGImage
    let displaySize: CGSize
    @Published var strokes: [AnnotationStroke]
    @Published var tool: AnnotationKind = .pen
    @Published var selectedIDs: Set<UUID> = []
    var selectedID: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        set { selectedIDs = newValue.map { [$0] } ?? [] }
    }
    @Published var marquee: CGRect?
    var selectionBounds: CGRect? {
        let boxes = strokes.filter { selectedIDs.contains($0.id) }.map {
            $0.bounds(in: displaySize, referenceSize: displaySize).insetBy(dx: -4, dy: -4)
        }
        return boxes.reduce(nil) { result, box in result.map { $0.union(box) } ?? box }
    }
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 6
    private var sessionLineWidth: CGFloat = 6
    private var sessionHighlightWidth: CGFloat = 28
    @Published var fontSize: CGFloat = 24
    @Published var textDraft = ""
    @Published var editingTextID: UUID?
    var pendingTextReplacementID: UUID?
    var preferences: AppSettings?
    @Published var highlightColor: NSColor = .systemYellow
    @Published var saveError: String?
    var usesHighlighterColor: Bool { selected?.kind == .highlighter || (selected == nil && tool == .highlighter) }
    var activeColor: NSColor { usesHighlighterColor ? highlightColor : selectedColor }
    func chooseTool(_ kind: AnnotationKind) {
        editingTextID = nil
        selectedID = nil
        tool = kind
        selectedColor = preferences?.markupColor(highlighter: false) ?? selectedColor
        highlightColor = preferences?.markupColor(highlighter: true) ?? highlightColor
        lineWidth = preferences?.strokeWidth(highlighter: kind == .highlighter)
            ?? (kind == .highlighter ? sessionHighlightWidth : sessionLineWidth)
    }
    func chooseColor(_ color: NSColor, highlighter: Bool) {
        if highlighter { highlightColor = color; preferences?.lastHighlightColor = color.hex }
        else { selectedColor = color; preferences?.lastMarkupColor = color.hex }
        if let selected, (selected.kind == .highlighter) == highlighter { updateSelected(color: color) }
    }
    @Published private var history: [[AnnotationStroke]] = []
    var canUndo: Bool { !history.isEmpty }
    var selected: AnnotationStroke? { strokes.first { $0.id == selectedID } }
    private let onCopy: (CGImage) -> Void
    private let onChange: (CGImage, [AnnotationStroke]) -> Void
    private var copyTask: Task<Void, Never>?
    private var dragStart: CGPoint?
    private var originalPoints: [UUID: [CGPoint]] = [:]
    private var isMarquee = false
    private var moveCheckpointed = false

    init(image: CGImage, displaySize: CGSize? = nil, strokes: [AnnotationStroke] = [], onCopy: @escaping (CGImage) -> Void, onChange: @escaping (CGImage, [AnnotationStroke]) -> Void = { _, _ in }) {
        self.image = image
        self.displaySize = displaySize ?? CGSize(width: image.width, height: image.height)
        self.strokes = strokes
        self.onCopy = onCopy
        self.onChange = onChange
    }

    private func checkpoint() { history.append(strokes); if history.count > 100 { history.removeFirst() } }

    func beginStroke(at point: CGPoint) {
        checkpoint()
        let object = AnnotationStroke(points: [point], color: tool == .highlighter ? highlightColor : selectedColor, width: lineWidth,
                                      kind: tool == .select ? .pen : tool,
                                      text: tool == .text ? "text" : "", fontSize: fontSize,
                                      textBoxSize: tool == .text ? CGSize(width: 220, height: 80) : nil)
        strokes.append(object)
        selectedID = object.id
        if tool == .text { pendingTextReplacementID = object.id }
    }

    func continueStroke(at point: CGPoint) {
        guard let index = strokes.firstIndex(where: { $0.id == selectedID }) else { return }
        if strokes[index].kind == .pen || strokes[index].kind == .highlighter { strokes[index].points.append(point) }
        else if strokes[index].kind != .text { strokes[index].points = [strokes[index].points[0], point] }
    }

    func finishStroke() { scheduleClipboardUpdate() }

    func beginInteraction(at point: CGPoint) {
        dragStart = point
        moveCheckpointed = false
        if tool == .select {
            let location = CGPoint(x: point.x * displaySize.width, y: point.y * displaySize.height)
            let hit = strokes.last { $0.hitTest(location, size: displaySize, referenceSize: displaySize) }?.id
            let insideGroup = selectedIDs.count > 1 && (selectionBounds?.contains(location) ?? false)
            isMarquee = hit == nil && !insideGroup
            if isMarquee {
                selectedIDs = []
                marquee = CGRect(origin: location, size: .zero)
            } else if !insideGroup, let hit, !selectedIDs.contains(hit) {
                selectedID = hit
            }
            originalPoints = Dictionary(uniqueKeysWithValues: strokes.filter { selectedIDs.contains($0.id) }.map { ($0.id, $0.points) })
            if let object = selected {
                if object.kind == .highlighter { highlightColor = object.color }
                else { selectedColor = object.color }
                lineWidth = object.width
                fontSize = object.fontSize; textDraft = object.text
            }
        } else { beginStroke(at: point) }
    }

    func updateInteraction(at point: CGPoint) {
        guard let start = dragStart else { return }
        if tool == .select {
            if isMarquee {
                let rect = CGRect(x: min(start.x, point.x) * displaySize.width,
                                  y: min(start.y, point.y) * displaySize.height,
                                  width: abs(point.x-start.x) * displaySize.width,
                                  height: abs(point.y-start.y) * displaySize.height)
                marquee = rect
                selectedIDs = Set(strokes.filter {
                    rect.intersects($0.contentBounds(in: displaySize, referenceSize: displaySize).insetBy(dx: -2, dy: -2))
                }.map(\.id))
                return
            }
            guard !selectedIDs.isEmpty else { return }
            if !moveCheckpointed { checkpoint(); moveCheckpointed = true }
            for index in strokes.indices {
                if let original = originalPoints[strokes[index].id] {
                    strokes[index].points = original.map { CGPoint(x: $0.x + point.x-start.x, y: $0.y + point.y-start.y) }
                }
            }
        } else { continueStroke(at: point) }
    }

    func endInteraction() {
        dragStart = nil
        marquee = nil
        finishStroke()
        if tool == .text {
            textDraft = selected?.text ?? ""
            tool = .select
            editingTextID = selectedID
        }
    }

    func updateSelected(color: NSColor? = nil, width: CGFloat? = nil, text: String? = nil, fontSize: CGFloat? = nil, justification: TextJustification? = nil) {
        if let color {
            if selected?.kind == .highlighter { highlightColor = color }
            else { selectedColor = color }
        }
        if let width {
            lineWidth = width
            if usesHighlighterColor { sessionHighlightWidth = width }
            else { sessionLineWidth = width }
            preferences?.rememberStrokeWidth(width, highlighter: usesHighlighterColor)
        }
        if let text { textDraft = text; pendingTextReplacementID = nil }
        if let fontSize { self.fontSize = fontSize }
        guard let index = strokes.firstIndex(where: { $0.id == selectedID }) else { return }
        checkpoint()
        if let color { strokes[index].color = color }
        if let width { strokes[index].width = width }
        if let text, strokes[index].kind == .text { strokes[index].text = text }
        if let fontSize { strokes[index].fontSize = fontSize }
        if let justification { strokes[index].justification = justification }
        scheduleClipboardUpdate()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        strokes = previous; selectedID = nil; editingTextID = nil
        scheduleClipboardUpdate()
    }

    func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        checkpoint(); strokes.removeAll { selectedIDs.contains($0.id) }; selectedID = nil; editingTextID = nil
        scheduleClipboardUpdate()
    }

    func beginTextResize() { checkpoint() }
    func resizeText(to size: CGSize) {
        guard let index = strokes.firstIndex(where: { $0.id == selectedID }), strokes[index].kind == .text else { return }
        strokes[index].textBoxSize = CGSize(width: max(40, size.width), height: max(30, size.height))
    }
    func finishTextResize() { scheduleClipboardUpdate() }

    func clear() {
        guard !strokes.isEmpty else { return }
        checkpoint(); strokes.removeAll(); selectedID = nil; editingTextID = nil
        scheduleClipboardUpdate()
    }

    func renderedImage() -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        for stroke in strokes { stroke.draw(in: context, size: size, referenceSize: displaySize) }
        return context.makeImage()!
    }

    private func scheduleClipboardUpdate() {
        onChange(image, strokes)
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            onCopy(renderedImage())
        }
    }
}

@MainActor
final class AnnotationWindowController: NSWindowController {
    init(model: AnnotationModel, settings: AppSettings, onOpenSettings: @escaping () -> Void = {}) {
        model.preferences = settings
        model.selectedColor = settings.markupColor(highlighter: false)
        model.highlightColor = settings.markupColor(highlighter: true)
        if model.selectedIDs.isEmpty {
            model.lineWidth = settings.strokeWidth(highlighter: model.tool == .highlighter)
        }
        let rootView = AnnotationEditorView(model: model, settings: settings, onOpenSettings: onOpenSettings)
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let contentSize = CGSize(width: min(max(model.displaySize.width, 880), available.width - 40),
                                 height: min(max(model.displaySize.height + 200, 360), available.height - 70))
        let window = AnnotationWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SimpleShot"
        window.model = model
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private final class AnnotationWindow: NSWindow {
    weak var model: AnnotationModel?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let typing = firstResponder is NSTextView
            if event.charactersIgnoringModifiers?.lowercased() == "z",
               modifiers == .control || (modifiers == .command && !typing) {
                model?.undo()
                return
            }
            if [51, 117].contains(event.keyCode), !typing, model?.selectedIDs.isEmpty == false {
                model?.deleteSelected()
                return
            }
            if event.keyCode == 53, model?.editingTextID != nil {
                model?.editingTextID = nil
                makeFirstResponder(contentView)
                return
            }
        }
        super.sendEvent(event)
    }
}

private struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationModel
    @ObservedObject var settings: AppSettings
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 6) {
                    Button { settings.openSaveDirectory() } label: {
                        Label(settings.saveDirectory.path, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                    }.help("Open screenshot folder in Finder")
                    Button("Change Default Location") { settings.chooseSaveDirectory() }
                        .fixedSize().help("Choose where screenshots are saved")
                }.padding(.horizontal, 150)
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                        .disabled(!model.canUndo)
                    Spacer()
                    Button { settings.captureMuted.toggle() } label: {
                        Image(systemName: settings.captureMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(settings.captureMuted ? "Unmute capture sound" : "Mute capture sound")
                    .accessibilityLabel(settings.captureMuted ? "Unmute capture sound" : "Mute capture sound")
                    Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                }
            }.padding(.horizontal, 10).padding(.vertical, 4)
            Divider()
            VStack(spacing: 8) {
                ZStack {
                    HStack(spacing: 6) {
                        ForEach(AnnotationKind.allCases, id: \.self) { kind in
                            Button { model.chooseTool(kind) } label: {
                                Image(systemName: kind.icon).frame(width: 22)
                                    .foregroundStyle(model.tool == kind ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(MarkupControlStyle())
                            .background(model.tool == kind ? Color.accentColor.opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .help(kind.rawValue).accessibilityLabel(kind.rawValue)
                        }
                    }
                    HStack(spacing: 8) {
                        InlineColorPicker(title: model.usesHighlighterColor ? "Highlighter color" : "Line / shape color",
                            color: Binding(get: { model.activeColor },
                            set: { model.chooseColor($0, highlighter: model.usesHighlighterColor) }), compact: true)
                        HStack(spacing: 4) {
                            Image(systemName: "lineweight").font(.caption)
                            Slider(value: Binding(get: { model.lineWidth }, set: { model.updateSelected(width: $0) }),
                                   in: 2...60).frame(width: 64).accessibilityLabel("Line thickness")
                        }
                        .padding(.horizontal, 6).frame(height: 30)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .help("Line thickness")
                        Spacer()
                        Button("Clear Annotations", systemImage: "trash") { model.clear() }
                            .buttonStyle(MarkupControlStyle())
                            .disabled(model.strokes.isEmpty)
                    }
                }
                if let error = model.saveError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(.horizontal, 10).padding(.vertical, 4)
            Divider()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: NSImage(cgImage: model.image, size: model.displaySize))
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: model.displaySize.width, height: model.displaySize.height)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
                        .overlay { AnnotationCanvas(model: model) }
                        .overlay(alignment: .top) {
                            if model.tool == .select, model.marquee == nil, let object = model.selected, object.kind == .text {
                                InlineTextAnnotation(model: model, object: object)
                                    .frame(width: model.displaySize.width, height: model.displaySize.height, alignment: .topLeading)
                            }
                        }
                }.background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    if model.tool == .select, !model.selectedIDs.isEmpty {
                        Button("Delete selected", systemImage: "trash") { model.deleteSelected() }
                            .buttonStyle(MarkupControlStyle())
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
                }
            }
        }
        .frame(minWidth: 880, minHeight: 360)
    }
}

private struct InlineTextAnnotation: View {
    @ObservedObject var model: AnnotationModel
    let object: AnnotationStroke
    @FocusState private var focused: Bool
    @State private var resizeStart: CGSize?
    private var rect: CGRect { object.bounds(in: model.displaySize, referenceSize: model.displaySize) }
    private var contentRect: CGRect { object.contentBounds(in: model.displaySize, referenceSize: model.displaySize) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.editingTextID == object.id {
                BoxedTextEditor(model: model, object: object, size: contentRect.size)
                    .id(object.id)
                    .frame(width: rect.width, height: contentRect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            Rectangle().stroke(Color.accentColor, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY).allowsHitTesting(false)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10)).padding(4).background(.regularMaterial)
                .contentShape(Rectangle())
                .offset(x: rect.maxX - 9, y: rect.maxY - 9)
                .help("Drag to resize text box")
                .accessibilityLabel("Resize text box")
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("inlineTextBox")).onChanged { value in
                    if resizeStart == nil { resizeStart = rect.size; model.beginTextResize() }
                    guard let initial = resizeStart else { return }
                    model.resizeText(to: CGSize(width: initial.width + value.translation.width,
                                                height: initial.height + value.translation.height))
                }.onEnded { _ in resizeStart = nil; model.finishTextResize() })
            HStack(spacing: 6) {
                Stepper(value: Binding(get: { model.fontSize }, set: { model.updateSelected(fontSize: $0) }), in: 8...144, step: 2) {
                    Text("\(Int(model.fontSize)) pt").monospacedDigit()
                }.frame(width: 100)
                HStack(spacing: 2) {
                    ForEach(TextJustification.allCases, id: \.self) { justification in
                        Button { model.updateSelected(justification: justification) } label: {
                            Image(systemName: justification.icon)
                                .foregroundStyle(object.justification == justification ? Color.accentColor : Color.primary)
                        }.help("Align " + justification.rawValue)
                            .accessibilityLabel("Align " + justification.rawValue)
                    }
                }
                Button(model.editingTextID == object.id ? "Done" : "Edit") {
                    if model.editingTextID == object.id { model.editingTextID = nil; focused = false }
                    else { model.editingTextID = object.id }
                }
            }
            .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .offset(x: max(0, min(rect.minX, model.displaySize.width - 280)),
                    y: max(0, rect.minY - 38))
            .zIndex(10)
        }
        .coordinateSpace(name: "inlineTextBox")
    }
}

private struct BoxedTextEditor: NSViewRepresentable {
    @ObservedObject var model: AnnotationModel
    let object: AnnotationStroke
    let size: CGSize
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: CGRect(origin: .zero, size: size))
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.allowsUndo = true
        view.delegate = context.coordinator
        let replacePlaceholder = model.pendingTextReplacementID == object.id
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
            if replacePlaceholder { view.selectAll(nil) }
        }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        if view.string != object.text { view.string = object.text }
        view.font = .systemFont(ofSize: object.fontSize, weight: .semibold)
        view.textColor = object.color
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = object.justification.alignment
        paragraph.lineBreakMode = .byWordWrapping
        view.defaultParagraphStyle = paragraph
        view.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: view.textStorage?.length ?? 0))
        view.typingAttributes = object.textAttributes(in: model.displaySize, referenceSize: model.displaySize)
        view.textContainer?.containerSize = CGSize(width: size.width, height: .greatestFiniteMagnitude)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AnnotationModel
        init(model: AnnotationModel) { self.model = model }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            model.updateSelected(text: view.string)
        }
    }
}

struct AnnotationCanvasGeometry {
    static func imageRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        CGRect(x: max(0, (canvasSize.width - imageSize.width) / 2), y: 0,
               width: imageSize.width, height: imageSize.height)
    }
    static func normalized(_ point: CGPoint, imageRect: CGRect, clamp: Bool) -> CGPoint {
        let x = (point.x - imageRect.minX) / max(imageRect.width, 1)
        let y = (point.y - imageRect.minY) / max(imageRect.height, 1)
        return CGPoint(x: clamp ? min(max(x, 0), 1) : x, y: clamp ? min(max(y, 0), 1) : y)
    }
}

private struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var model: AnnotationModel
    func makeNSView(context: Context) -> MarkupView { MarkupView(model: model) }
    func updateNSView(_ view: MarkupView, context: Context) {
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }

    final class MarkupView: NSView {
        let model: AnnotationModel
        private var anchor = CGPoint.zero
        private var interactionStarted = false
        private var imageRect: CGRect {
            AnnotationCanvasGeometry.imageRect(imageSize: model.displaySize, canvasSize: bounds.size)
        }
        override var isFlipped: Bool { true }
        init(model: AnnotationModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
            if model.tool != .select { addCursorRect(imageRect, cursor: .crosshair) }
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: imageRect.minX, y: imageRect.minY)
            for object in model.strokes where object.id != model.editingTextID {
                object.draw(in: context, size: model.displaySize, referenceSize: model.displaySize)
            }
            if model.tool == .select {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 3])
                for object in model.strokes where model.selectedIDs.contains(object.id) {
                    context.stroke(object.bounds(in: model.displaySize, referenceSize: model.displaySize).insetBy(dx: -4, dy: -4))
                }
                if model.selectedIDs.count > 1, let rect = model.selectionBounds { context.stroke(rect) }
                if let marquee = model.marquee {
                    context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
                    context.fill(marquee)
                    context.stroke(marquee)
                }
            }
        }
        private func point(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return AnnotationCanvasGeometry.normalized(p, imageRect: imageRect, clamp: model.tool != .select)
        }
        override func mouseDown(with event: NSEvent) {
            interactionStarted = model.tool == .select || imageRect.contains(convert(event.locationInWindow, from: nil))
            guard interactionStarted else { return }
            window?.makeFirstResponder(self)
            model.editingTextID = nil
            anchor = point(event)
            model.beginInteraction(at: anchor)
            if event.clickCount == 2, model.selected?.kind == .text { model.editingTextID = model.selectedID }
        }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDragged(with event: NSEvent) {
            guard interactionStarted else { return }
            var destination = point(event)
            if event.modifierFlags.contains(.shift), model.tool == .ellipse || model.tool == .rectangle {
                let dx = (destination.x - anchor.x) * imageRect.width
                let dy = (destination.y - anchor.y) * imageRect.height
                let side = min(abs(dx), abs(dy))
                destination = CGPoint(x: anchor.x + (dx < 0 ? -side : side) / max(imageRect.width, 1),
                                      y: anchor.y + (dy < 0 ? -side : side) / max(imageRect.height, 1))
            }
            model.updateInteraction(at: destination)
        }
        override func mouseUp(with event: NSEvent) {
            guard interactionStarted else { return }
            interactionStarted = false
            model.endInteraction()
        }
    }
}

extension CGSize {
    func aspectFit(in container: CGSize) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let scale = min(container.width / width, container.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
