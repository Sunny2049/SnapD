import AppKit

enum Store {
    static var saveDir: URL {
        if let s = UserDefaults.standard.string(forKey: "saveDir"), !s.isEmpty {
            // Migration: early builds stored the old default (~/Pictures/SnapD), which then
            // silently overrode the Desktop default the user asked for. Treat that stored
            // value as "no choice made" and drop it; a folder the user picks later via the
            // menu is a different path and sticks.
            let oldDefault = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SnapD").path
            if s != oldDefault { return URL(fileURLWithPath: s) }
            UserDefaults.standard.removeObject(forKey: "saveDir")
        }
        // Default save location: the Desktop (user request 2026-11-22)
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }
    static var autoCopy: Bool { UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true }
    static var autoSave: Bool { UserDefaults.standard.object(forKey: "autoSave") as? Bool ?? true }

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
    }

    @discardableResult
    static func save(_ image: NSImage, prefix: String = "SnapD") -> URL? {
        ensureDir()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = saveDir.appendingPathComponent("\(prefix)-\(fmt.string(from: Date())).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try png.write(to: url); return url } catch { return nil }
    }

    static func copyToClipboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func notify(title: String, body: String) {
        // Lightweight feedback: sound + floating toast via NSAlert is too heavy; use Notification Center if available via process is complex.
        // We just play a shutter-like sound.
        NSSound(named: "Pop")?.play()
        _ = title; _ = body
    }
}

extension NSImage {
    func cropped(to cgRect: CGRect) -> NSImage? {
        guard let cg = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // cgRect is in points at scale 1 relative to image pixels / scale
        let scale = CGFloat(cg.width) / self.size.width
        let r = CGRect(x: cgRect.origin.x * scale, y: cgRect.origin.y * scale,
                       width: cgRect.width * scale, height: cgRect.height * scale)
        guard let sub = cg.cropping(to: r) else { return nil }
        return NSImage(cgImage: sub, size: cgRect.size)
    }
    var cgImageRef: CGImage? { self.cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
