import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let selector = RegionSelector()
    private let scrollCap = ScrollCapture()
    private var editors: [EditorController] = []
    private let settings = SettingsController()
    private var menuItems: [HotKeyAction: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Store.ensureDir()
        checkScreenPermission()
        setupMenuBar()
        setupHotKeys()
        // First-launch hint
        if !UserDefaults.standard.bool(forKey: "launchedOnce") {
            UserDefaults.standard.set(true, forKey: "launchedOnce")
            let a = NSAlert()
            a.messageText = "SnapD 已启动（在顶部菜单栏）"
            a.informativeText = "默认快捷键（可在菜单「快捷键设置…」里改）：\n• Option + D：区域截图（主快捷键）\n• Option + Shift + D：全屏截图\n• Option + W：当前窗口截图\n• Option + L：长截图（自动滚动拼接）\n• Option + P：把剪贴板图片贴在桌面\n\n首次使用请在 系统设置 → 隐私与安全性 里给 SnapD 开启「屏幕录制」和「辅助功能」，然后重启 SnapD。"
            a.addButton(withTitle: "知道了")
            a.runModal()
        }
    }

    /// Without Screen Recording permission macOS only hands us the desktop wallpaper — no app windows.
    /// (Ad-hoc signed builds change identity every rebuild, so the grant must be redone after reinstall.)
    private func checkScreenPermission() {
        if CGPreflightScreenCaptureAccess() { return }
        CGRequestScreenCaptureAccess()
        let a = NSAlert()
        a.messageText = "SnapD 还没有「屏幕录制」权限"
        a.informativeText = "没有这个权限时只能截到桌面，截不到任何 App 的窗口。请在 系统设置 → 隐私与安全性 → 屏幕录制 里把 SnapD 打开（如果列表里已有，先删掉再重新添加 /Applications 里的 SnapD），然后退出并重新打开 SnapD。"
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapD")
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.target = self; i.keyEquivalentModifierMask = mods; return i
        }
        func hotItem(_ action: HotKeyAction, _ sel: Selector) -> NSMenuItem {
            let i = item("\(action.title)  \(HotKeyConfig.load(action).display)", sel); menuItems[action] = i; return i
        }
        menu.addItem(hotItem(.region, #selector(regionCapture)))
        menu.addItem(hotItem(.full, #selector(fullCapture)))
        menu.addItem(hotItem(.window, #selector(windowCapture)))
        menu.addItem(hotItem(.long, #selector(longCapture)))
        menu.addItem(item("延迟 3 秒区域截图", #selector(delayedRegion)))
        menu.addItem(.separator())
        menu.addItem(hotItem(.pin, #selector(pinClipboard)))
        menu.addItem(item("打开截图文件夹", #selector(openFolder)))
        menu.addItem(item("选择保存文件夹…", #selector(chooseFolder)))
        menu.addItem(item("快捷键设置…", #selector(openSettings), ",", [.command]))
        menu.addItem(.separator())
        menu.addItem(item("退出 SnapD", #selector(quit), "q", [.command]))
        statusItem.menu = menu
        settings.onChange = { [weak self] in self?.refreshMenuShortcuts() }
    }

    private func refreshMenuShortcuts() {
        for (action, item) in menuItems { item.title = "\(action.title)  \(HotKeyConfig.load(action).display)" }
    }

    @objc func openSettings() { settings.show() }

    private func setupHotKeys() {
        let hk = HotKeyManager.shared
        hk.onAction = { [weak self] action in
            switch action {
            case .region: self?.regionCapture()
            case .full: self?.fullCapture()
            case .long: self?.longCapture()
            case .window: self?.windowCapture()
            case .pin: self?.pinClipboard()
            }
        }
        hk.registerAll()
    }

    private func present(_ image: NSImage?) {
        guard let image = image else {
            NSSound.beep(); return
        }
        // Auto-save to the save folder (Desktop by default) and auto-copy, no "完成" step needed
        if Store.autoSave { _ = Store.save(image) }
        if Store.autoCopy { Store.copyToClipboard(image) }
        Store.notify(title: "SnapD", body: "截图已自动保存")
        let ed = EditorController(image: image)
        editors.append(ed)
        ed.show()
    }

    @objc func regionCapture() {
        selector.onSelect = { [weak self] rect in
            // tiny delay so overlay fully disappears before capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.present(CaptureEngine.capture(rectCG: rect)) }
        }
        selector.show()
    }
    @objc func delayedRegion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.regionCapture() }
    }
    @objc func fullCapture() { present(CaptureEngine.captureFullScreen()) }
    @objc func windowCapture() { present(CaptureEngine.captureFrontWindow()) }
    @objc func longCapture() {
        selector.onSelect = { [weak self] rect in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.scrollCap.onFinish = { img in self?.present(img) }
                self?.scrollCap.start(regionCG: rect)
            }
        }
        selector.show()
    }
    @objc func pinClipboard() {
        if let img = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            PinWindow.show(image: img)
        } else { NSSound.beep() }
    }
    @objc func openFolder() { Store.ensureDir(); NSWorkspace.shared.open(Store.saveDir) }
    @objc func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "saveDir") }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
