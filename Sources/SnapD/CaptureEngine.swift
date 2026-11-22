import AppKit
import CoreGraphics

enum CaptureEngine {
    /// Capture a rect in CG coordinates (origin top-left of main display, points)
    static func capture(rectCG: CGRect) -> NSImage? {
        guard let cg = CGWindowListCreateImage(rectCG, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else { return nil }
        return NSImage(cgImage: cg, size: rectCG.size)
    }

    static func captureFullScreen() -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let f = screen.frame
        let rect = CGRect(x: f.origin.x, y: 0, width: f.width, height: f.height)
        return capture(rectCG: rect)
    }

    /// Capture the frontmost app's main window
    static func captureFrontWindow() -> NSImage? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            if let ownerPid = info[kCGWindowOwnerPID as String] as? Int, ownerPid == Int(pid),
               let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
               let layer = info[kCGWindowLayer as String] as? Int, layer == 0 {
                let rect = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                  width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
                if rect.width > 50 && rect.height > 50 {
                    return capture(rectCG: rect)
                }
            }
        }
        return nil
    }

    static func requestPermission() {
        // Triggers macOS Screen Recording prompt on modern macOS
        _ = CGRequestScreenCaptureAccess()
    }
}
