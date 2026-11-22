import AppKit

final class PinWindow: NSWindow {
    static var pins: [PinWindow] = []
    static func show(image: NSImage) {
        var size = image.size
        let maxDim: CGFloat = 520
        if max(size.width, size.height) > maxDim {
            let s = maxDim / max(size.width, size.height)
            size = NSSize(width: size.width * s, height: size.height * s)
        }
        let win = PinWindow(contentRect: NSRect(origin: NSPoint(x: 120 + CGFloat(pins.count * 24), y: 300), size: size),
                            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        win.level = .floating; win.isMovableByWindowBackground = true; win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let iv = NSImageView(frame: NSRect(origin: .zero, size: size)); iv.image = image; iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        win.contentView = iv
        win.makeKeyAndOrderFront(nil)
        pins.append(win)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { close(); PinWindow.pins.removeAll { $0 == self }; return }
        super.mouseDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "复制", action: #selector(copyImage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "保存", action: #selector(saveImage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "关闭贴图 (双击也可)", action: #selector(closePin), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }
    @objc private func copyImage() { if let iv = contentView as? NSImageView, let img = iv.image { Store.copyToClipboard(img) } }
    @objc private func saveImage() { if let iv = contentView as? NSImageView, let img = iv.image { _ = Store.save(img, prefix: "Pin") } }
    @objc private func closePin() { close(); PinWindow.pins.removeAll { $0 == self } }
    override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = event.deltaY > 0 ? 1.08 : 0.92
        var f = frame; let cx = f.midX, cy = f.midY
        f.size = NSSize(width: max(60, f.width * factor), height: max(40, f.height * factor))
        f.origin = NSPoint(x: cx - f.width/2, y: cy - f.height/2)
        setFrame(f, display: true)
    }
}
