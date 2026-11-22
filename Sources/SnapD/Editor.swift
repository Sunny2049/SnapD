import AppKit
import Vision

// MARK: - Annotation shapes
enum Tool: String { case none, pen, line, rect, arrow, mosaic, text }
struct Shape {
    var tool: Tool
    var points: [NSPoint] = []
    var rect: NSRect = .zero
    var text: String = ""
    var color: NSColor = .systemRed
}

final class CanvasView: NSView {
    var image: NSImage
    var shapes: [Shape] = []
    var tool: Tool = .none
    var color: NSColor = .systemRed
    private var current: Shape?
    private var startPoint: NSPoint = .zero
    init(image: NSImage) { self.image = image; super.init(frame: NSRect(origin: .zero, size: image.size)) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { false }

    func flattened() -> NSImage {
        let img = NSImage(size: image.size)
        img.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        for s in shapes { drawShape(s) }
        if let c = current { drawShape(c) }
        img.unlockFocus()
        return img
    }
    private func drawShape(_ s: Shape) {
        s.color.setStroke(); s.color.setFill()
        switch s.tool {
        case .pen:
            guard s.points.count > 1 else { return }
            let p = NSBezierPath(); p.move(to: s.points[0])
            for pt in s.points.dropFirst() { p.line(to: pt) }
            p.lineWidth = 3; p.lineCapStyle = .round; p.stroke()
        case .line:
            guard s.points.count == 2 else { return }
            let p = NSBezierPath(); p.move(to: s.points[0]); p.line(to: s.points[1]); p.lineWidth = 3; p.lineCapStyle = .round; p.stroke()
        case .rect:
            let p = NSBezierPath(rect: s.rect); p.lineWidth = 3; p.stroke()
        case .arrow:
            guard s.points.count == 2 else { return }
            let a = s.points[0], b = s.points[1]
            let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = 3; p.stroke()
            let angle = atan2(b.y - a.y, b.x - a.x)
            let len: CGFloat = 14
            for da in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                let tip = NSPoint(x: b.x + len * cos(angle + da), y: b.y + len * sin(angle + da))
                let h = NSBezierPath(); h.move(to: b); h.line(to: tip); h.lineWidth = 3; h.stroke()
            }
        case .mosaic:
            // Solid-color smear (user's own suggestion, 2026-11-22: "just paint a
            // color over it"). Pixelation kept failing to cover text convincingly,
            // so the brush now paints an opaque black stroke along the drag path —
            // like a thick marker. Cannot fail: no sampling, pure vector stroke,
            // identical in live draw and in flattened().
            guard !s.points.isEmpty else { return }
            let p = NSBezierPath()
            p.move(to: s.points[0])
            for pt in s.points.dropFirst() { p.line(to: pt) }
            if s.points.count == 1 { p.line(to: s.points[0]) } // a click still leaves a dot
            p.lineWidth = 24; p.lineCapStyle = .round; p.lineJoinStyle = .round // user: a bit thinner (36 -> 24, 2026-11-22)
            NSColor.black.setStroke()
            p.stroke()
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: s.color]
            s.text.draw(at: s.rect.origin, withAttributes: attrs)
        case .none: break
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        for s in shapes { drawShape(s) }
        if let c = current { drawShape(c) }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil); startPoint = p
        if tool == .text {
            let alert = NSAlert(); alert.messageText = "输入文字"; alert.addButton(withTitle: "添加"); alert.addButton(withTitle: "取消")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24)); alert.accessoryView = field
            if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                shapes.append(Shape(tool: .text, rect: NSRect(origin: p, size: .zero), text: field.stringValue, color: color))
                needsDisplay = true
            }
            return
        }
        current = Shape(tool: tool, points: [p], rect: NSRect(origin: p, size: .zero), color: color)
    }
    override func mouseDragged(with event: NSEvent) {
        guard var c = current, tool != .none else { return }
        let p = convert(event.locationInWindow, from: nil)
        if tool == .pen || tool == .mosaic { c.points.append(p) }
        else if tool == .arrow || tool == .line { c.points = [startPoint, p] }
        else { c.rect = NSRect(x: min(startPoint.x, p.x), y: min(startPoint.y, p.y), width: abs(p.x-startPoint.x), height: abs(p.y-startPoint.y)) }
        current = c; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let c = current { shapes.append(c) }; current = nil; needsDisplay = true
    }
    func undo() { if !shapes.isEmpty { shapes.removeLast(); needsDisplay = true } }
}

// MARK: - Editor window (preview + toolbar, appears right after capture)
final class EditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var barPanel: NSPanel?
    private var canvas: CanvasView?
    private var autoCloseWork: DispatchWorkItem?
    private var eventMonitor: Any?
    var image: NSImage

    init(image: NSImage) { self.image = image; super.init() }

    func show() {
        let maxW: CGFloat = 900, maxH: CGFloat = 620
        var size = image.size
        let scale = min(1, min(maxW / max(size.width,1), maxH / max(size.height,1)))
        size = NSSize(width: size.width * scale, height: size.height * scale)
        // Canvas works in image coordinates; put it in a scroll view and scale via frame trick:
        let canvas = CanvasView(image: image)
        canvas.frame = NSRect(origin: .zero, size: image.size)
        self.canvas = canvas

        // The editor window hugs the image exactly — the image may be small and the
        // window is just as small. The toolbar is NOT part of this window (see below).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.maxMagnification = 4; scroll.minMagnification = 0.1
        scroll.magnification = scale
        scroll.autoresizingMask = [.width, .height]

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        win.minSize = NSSize(width: 120, height: 100)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.title = "SnapD — \(Int(image.size.width)) × \(Int(image.size.height))"
        win.center(); win.level = .floating
        win.contentView = scroll
        win.delegate = self
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window = win

        // Toolbar: a separate floating dark bar, like the reference UI the user sent.
        // It hangs below the image window, right-aligned to it, and keeps its own
        // natural width — wider than a small image is fine, it just overflows.
        let bar = NSStackView()
        bar.orientation = .horizontal; bar.spacing = 6
        func btn(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b
        }
        // Order per user (2026-11-22): OCR first, pen second; no copy/save buttons
        // (captures already auto-copy and auto-save on capture).
        bar.addArrangedSubview(btn("提取文字", #selector(doOCR)))
        bar.addArrangedSubview(btn("画笔", #selector(setPen)))
        bar.addArrangedSubview(btn("直线", #selector(setLine)))
        bar.addArrangedSubview(btn("矩形", #selector(setRect)))
        bar.addArrangedSubview(btn("箭头", #selector(setArrow)))
        bar.addArrangedSubview(btn("马赛克", #selector(setMosaic)))
        bar.addArrangedSubview(btn("文字", #selector(setText)))
        bar.addArrangedSubview(btn("贴图", #selector(doPin)))
        bar.addArrangedSubview(btn("撤销", #selector(doUndo)))
        let barW = bar.fittingSize.width + 24
        let barH: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: barW, height: barH),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true
        let barBG = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: barW, height: barH))
        barBG.material = .hudWindow; barBG.state = .active
        barBG.wantsLayer = true; barBG.layer?.cornerRadius = 10; barBG.layer?.masksToBounds = true
        barBG.autoresizingMask = [.width, .height]
        bar.frame = NSRect(x: 12, y: (barH - bar.fittingSize.height) / 2, width: barW - 24, height: bar.fittingSize.height)
        bar.autoresizingMask = [.width]
        barBG.addSubview(bar)
        panel.contentView = barBG
        barPanel = panel
        positionBar()
        panel.orderFront(nil)
        // Auto-close after 5s only if the user does not interact; any interaction cancels it and the user closes manually
        let work = DispatchWorkItem { [weak self] in self?.window?.close() }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] e in
            if e.window === self?.window || e.window === self?.barPanel { self?.cancelAutoClose() }
            return e
        }
    }
    /// Keep the floating toolbar under the image window, right-aligned to it.
    /// The bar may be wider than the image — it overflows to the left, clamped to the screen.
    private func positionBar() {
        guard let win = window, let panel = barPanel else { return }
        let screen = win.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? win.frame
        let wf = win.frame, pf = panel.frame
        var x = wf.maxX - pf.width
        x = max(visible.minX + 4, min(x, visible.maxX - pf.width - 4))
        var y = wf.minY - pf.height - 8
        if y < visible.minY + 4 { // no room below: sit above the window, else overlay its bottom
            y = wf.maxY + 8 + 22 <= visible.maxY ? wf.maxY + 8 : wf.minY + 8
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func windowDidMove(_ notification: Notification) { positionBar() }
    func windowDidResize(_ notification: Notification) { positionBar() }
    private func cancelAutoClose() {
        autoCloseWork?.cancel(); autoCloseWork = nil
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }
    func windowWillClose(_ notification: Notification) { cancelAutoClose(); barPanel?.close() }
    @objc private func setPen() { canvas?.tool = .pen }
    @objc private func setLine() { canvas?.tool = .line }
    @objc private func setRect() { canvas?.tool = .rect }
    @objc private func setArrow() { canvas?.tool = .arrow }
    @objc private func setMosaic() { canvas?.tool = .mosaic }
    @objc private func setText() { canvas?.tool = .text }
    @objc private func doUndo() { canvas?.undo() }
    private func finalImage() -> NSImage { canvas?.flattened() ?? image }
    @objc private func doCopy() { Store.copyToClipboard(finalImage()); Store.notify(title: "SnapD", body: "已复制") }
    @objc private func doSave() { if let url = Store.save(finalImage()) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func doPin() { PinWindow.show(image: finalImage()) }
    @objc private func doOCR() {
        guard let cg = finalImage().cgImageRef else { return }
        let req = VNRecognizeTextRequest { req, _ in
            let text = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                let a = NSAlert(); a.messageText = "OCR 已复制到剪贴板"; a.informativeText = text.isEmpty ? "没有识别到文字" : String(text.prefix(500)); a.runModal()
            }
        }
        req.recognitionLanguages = ["zh-Hans", "en-US"]; req.recognitionLevel = .accurate
        DispatchQueue.global(qos: .userInitiated).async { try? VNImageRequestHandler(cgImage: cg).perform([req]) }
    }
}
