import AppKit

final class RegionSelector: NSObject {
    private var window: NSWindow?
    private var view: SelectorView?
    var onSelect: ((CGRect) -> Void)? // rect in CG coords (top-left origin, points)
    var onCancel: (() -> Void)?

    func show() {
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        // Appear in the current Space even when another app (e.g. Muse/Chrome) is fullscreen,
        // instead of yanking the user back to the desktop Space
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = false
        let v = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.onDone = { [weak self] appKitRect in
            self?.close()
            guard let rect = appKitRect, rect.width >= 8, rect.height >= 8 else { self?.onCancel?(); return }
            // AppKit (bottom-left) -> CG (top-left)
            let screenH = screen.frame.height
            let cg = CGRect(x: rect.origin.x, y: screenH - rect.origin.y - rect.height, width: rect.width, height: rect.height)
            self?.onSelect?(cg)
        }
        w.contentView = v
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w; view = v
    }
    private func close() { window?.orderOut(nil); window = nil; view = nil }
}

final class SelectorView: NSView {
    var onDone: ((NSRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSRect?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }

    override func draw(_ dirtyRect: NSRect) {
        guard let r = current else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: bounds).fill()
            drawHint(); return
        }
        // redraw dim with a hole over the selection
        let path = NSBezierPath(rect: bounds); path.append(NSBezierPath(rect: r))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill(); path.fill()
        NSColor.systemRed.setStroke()
        let border = NSBezierPath(rect: r); border.lineWidth = 1.5; border.stroke()
        let label = "\(Int(r.width)) × \(Int(r.height))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        var labelRect = NSRect(x: r.minX, y: r.maxY + 6, width: size.width + 12, height: 20)
        if labelRect.maxY > bounds.maxY { labelRect.origin.y = r.maxY - 26 }
        NSColor.black.withAlphaComponent(0.75).setFill(); NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        label.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 3), withAttributes: attrs)
    }
    private func drawHint() {
        let text = "拖动选择截图区域  •  Esc 取消  •  松开鼠标完成"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white]
        let s = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - s.width)/2, y: bounds.height/2 + 40), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); current = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let s = start else { return }
        let p = convert(event.locationInWindow, from: nil)
        current = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { onDone?(current) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?(nil) } else { super.keyDown(with: event) }
    }
}
