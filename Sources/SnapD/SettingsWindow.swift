import AppKit

/// Shortcut settings: click "修改", then press the new key combo. Saved instantly and hotkeys re-register live.
final class SettingsController: NSObject {
    private var window: NSWindow?
    private var buttons: [HotKeyAction: NSButton] = [:]
    private var monitor: Any?
    private var recording: HotKeyAction?
    var onChange: (() -> Void)?

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh(); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "SnapD 快捷键设置"
        win.center()
        let stack = NSStackView(frame: NSRect(x: 20, y: 20, width: 380, height: 260))
        stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .leading

        let hint = NSTextField(labelWithString: "点「修改」后按下新组合键（至少带一个 ⌃/⌥/⇧/⌘），Esc 取消。改完立即生效。")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2; hint.preferredMaxLayoutWidth = 380
        stack.addArrangedSubview(hint)

        for action in HotKeyAction.allCases {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let label = NSTextField(labelWithString: action.title)
            label.frame = NSRect(x: 0, y: 0, width: 130, height: 20)
            label.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let btn = NSButton(title: HotKeyConfig.load(action).display, target: self, action: #selector(startRecording(_:)))
            btn.bezelStyle = .rounded
            btn.widthAnchor.constraint(equalToConstant: 130).isActive = true
            // tag via identifier
            btn.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            buttons[action] = btn
            let change = NSButton(title: "修改", target: self, action: #selector(startRecording(_:)))
            change.bezelStyle = .rounded; change.identifier = btn.identifier
            row.addArrangedSubview(label); row.addArrangedSubview(btn); row.addArrangedSubview(change)
            stack.addArrangedSubview(row)
        }

        let reset = NSButton(title: "恢复默认（⌥D 等）", target: self, action: #selector(resetAll))
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)

        win.contentView?.addSubview(stack)
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    private func refresh() { for (a, b) in buttons { b.title = HotKeyConfig.load(a).display } }

    @objc private func startRecording(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let action = HotKeyAction(rawValue: raw) else { return }
        stopMonitor()
        recording = action
        buttons[action]?.title = "请按快捷键…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let act = self.recording else { return event }
            if event.keyCode == 53 { // Esc cancels
                self.stopMonitor(); self.recording = nil; self.refresh(); return nil
            }
            guard let cfg = HotKeyConfig.from(event: event) else {
                NSSound.beep() // no modifier pressed
                return nil
            }
            // Conflict check
            for other in HotKeyAction.allCases where other != act {
                if HotKeyConfig.load(other) == cfg {
                    let a = NSAlert(); a.messageText = "快捷键冲突"; a.informativeText = "\(cfg.display) 已经是「\(other.title)」的快捷键了，换一个吧。"
                    a.runModal(); self.stopMonitor(); self.recording = nil; self.refresh(); return nil
                }
            }
            cfg.save(for: act)
            self.stopMonitor(); self.recording = nil
            HotKeyManager.shared.registerAll()
            self.refresh(); self.onChange?()
            return nil
        }
    }

    private func stopMonitor() { if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }

    @objc private func resetAll() {
        HotKeyConfig.resetAll()
        HotKeyManager.shared.registerAll()
        refresh(); onChange?()
    }
}
