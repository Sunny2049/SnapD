import AppKit
import CoreGraphics

/// Pre-rendered RGBA buffer for fast row comparisons during stitching.
struct FrameBuf {
    let image: CGImage
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]
    init?(_ img: CGImage) {
        image = img; width = img.width; height = img.height
        bytesPerRow = width * 4
        var buf = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buf
    }
    /// CGContext buffer is bottom-up: buffer row 0 = image bottom. We index by image row (top=0).
    func rowHash(imageRow y: Int) -> Int {
        let by = height - 1 - y
        guard by >= 0, by < height else { return 0 }
        var h = 1469598103
        var x = 0
        while x < width {
            let off = by * bytesPerRow + x * 4
            h = (h ^ Int(data[off])) &* 16777619
            h = (h ^ Int(data[off + 1])) &* 16777619
            x += 16 // sample every 16th pixel: fast and discriminative enough
        }
        return h
    }
}

/// Long / scrolling capture:
/// 1. user selects a region (the scrollable viewport)
/// 2. capture frame 0, then repeatedly send scroll-wheel events to the region centre
/// 3. stitch each new frame under the previous by finding the largest vertical overlap
/// 4. stops when a frame matches the previous one (bottom reached), after 40 frames,
///    or when the user clicks the finish button in the floating panel.
final class ScrollCapture: NSObject {
    private var regionCG: CGRect = .zero
    private var frames: [FrameBuf] = []
    private var timer: Timer?
    private var panel: NSPanel?
    var onFinish: ((NSImage?) -> Void)?

    func start(regionCG: CGRect) {
        self.regionCG = regionCG
        frames = []
        showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.captureFrame(first: true)
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.step() }
        }
    }

    private func showPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 78),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "SnapD 长截图中…"
        p.level = .screenSaver; p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let label = NSTextField(labelWithString: "正在自动向下滚动并拼接\n不要操作鼠标/键盘")
        label.frame = NSRect(x: 12, y: 36, width: 206, height: 36); label.font = .systemFont(ofSize: 12)
        let btn = NSButton(title: "完成长截图", target: self, action: #selector(finishEarly))
        btn.frame = NSRect(x: 12, y: 8, width: 206, height: 26); btn.bezelStyle = .rounded
        p.contentView?.addSubview(label); p.contentView?.addSubview(btn)
        if let screen = NSScreen.main { p.setFrameOrigin(NSPoint(x: screen.frame.maxX - 250, y: screen.frame.maxY - 110)) }
        p.orderFront(nil); panel = p
    }

    @objc private func finishEarly() { finish() }

    private func step() {
        scrollDown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.captureFrame(first: false) }
    }

    private func scrollDown() {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let ev = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1,
                               wheel1: -Int32(regionCG.height * 0.75), wheel2: 0, wheel3: 0) else { return }
        ev.location = CGPoint(x: regionCG.midX, y: regionCG.midY)
        ev.post(tap: .cghidEventTap)
    }

    private func captureFrame(first: Bool) {
        guard let img = CaptureEngine.capture(rectCG: regionCG), let cg = img.cgImageRef, let buf = FrameBuf(cg) else {
            if first { finish() }; return
        }
        if let last = frames.last, last.width == buf.width, last.height == buf.height,
           last.rowHash(imageRow: last.height / 2) == buf.rowHash(imageRow: buf.height / 2),
           last.rowHash(imageRow: 10) == buf.rowHash(imageRow: 10),
           last.rowHash(imageRow: last.height - 10) == buf.rowHash(imageRow: buf.height - 10) {
            finish(); return // page didn't move -> bottom reached
        }
        frames.append(buf)
        if frames.count >= 40 { finish() }
    }

    /// Largest k such that bottom k rows of base == top k rows of next.
    private func overlap(base: FrameBuf, next: FrameBuf) -> Int {
        let maxK = min(base.height, next.height) - 10
        guard maxK > 24 else { return 0 }
        var k = maxK
        while k > 24 {
            let ok = [0, k / 2, k - 1].allSatisfy { off in
                base.rowHash(imageRow: base.height - k + off) == next.rowHash(imageRow: off)
            }
            if ok { return k }
            k -= 2
        }
        return 0
    }

    private func stitch() -> NSImage? {
        guard var result = frames.first?.image else { return nil }
        var resultBuf = frames.first
        for next in frames.dropFirst() {
            let ov = resultBuf.map { overlap(base: $0, next: next) } ?? 0
            let addH = next.height - ov
            guard addH > 0 else { continue }
            guard let bottom = next.image.cropping(to: CGRect(x: 0, y: ov, width: next.width, height: addH)) else { continue }
            let totalH = result.height + addH
            guard let ctx = CGContext(data: nil, width: result.width, height: totalH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            // CGContext origin is bottom-left: existing image goes on top, new strip at bottom.
            ctx.draw(result, in: CGRect(x: 0, y: addH, width: result.width, height: result.height))
            ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: next.width, height: addH))
            if let merged = ctx.makeImage() { result = merged; resultBuf = FrameBuf(merged) }
        }
        return NSImage(cgImage: result, size: NSSize(width: CGFloat(result.width), height: CGFloat(result.height)))
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        panel?.close(); panel = nil
        let img = stitch()
        frames = []
        onFinish?(img)
    }
}
