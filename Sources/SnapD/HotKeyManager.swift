import AppKit
import Carbon

enum HotKeyAction: String, CaseIterable {
    case region, full, long, window, pin
    var id: UInt32 {
        switch self { case .region: return 1; case .full: return 2; case .long: return 3; case .window: return 4; case .pin: return 5 }
    }
    var title: String {
        switch self {
        case .region: return "区域截图"
        case .full: return "全屏截图"
        case .long: return "长截图（滚动）"
        case .window: return "窗口截图"
        case .pin: return "贴图（剪贴板图片）"
        }
    }
    var defaultConfig: HotKeyConfig {
        switch self {
        case .region: return HotKeyConfig(keyCode: 2, carbonMods: UInt32(optionKey))                 // ⌥D
        case .full: return HotKeyConfig(keyCode: 2, carbonMods: UInt32(optionKey | shiftKey))        // ⌥⇧D
        case .long: return HotKeyConfig(keyCode: 37, carbonMods: UInt32(optionKey))                  // ⌥L
        case .window: return HotKeyConfig(keyCode: 13, carbonMods: UInt32(optionKey))                 // ⌥W
        case .pin: return HotKeyConfig(keyCode: 35, carbonMods: UInt32(optionKey))                   // ⌥P
        }
    }
}

struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var carbonMods: UInt32

    static func load(_ action: HotKeyAction) -> HotKeyConfig {
        if let data = UserDefaults.standard.data(forKey: "hotkey.\(action.rawValue)"),
           let cfg = try? JSONDecoder().decode(HotKeyConfig.self, from: data) { return cfg }
        return action.defaultConfig
    }
    func save(for action: HotKeyAction) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "hotkey.\(action.rawValue)") }
    }
    static func resetAll() {
        for a in HotKeyAction.allCases { a.defaultConfig.save(for: a) }
    }
    /// e.g. "⌥⇧D", "⌃⌘S"
    var display: String {
        var s = ""
        if carbonMods & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonMods & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonMods & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonMods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
    /// Build from an NSEvent keyDown
    static func from(event: NSEvent) -> HotKeyConfig? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        // Require at least one modifier (function keys exempted: keyCode 96...122 range rough check in caller not needed)
        guard mods != 0 else { return nil }
        return HotKeyConfig(keyCode: UInt32(event.keyCode), carbonMods: mods)
    }
}

enum KeyNames {
    static let map: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",
        16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",
        30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",
        45:"N",46:"M",47:".",49:"Space",50:"`",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",107:"F14",109:"F10",111:"F12",
        113:"F15",118:"F4",119:"F2",120:"F1",122:"F1",
        123:"←",124:"→",125:"↓",126:"↑",36:"↩",48:"⇥",51:"⌫",53:"Esc",
    ]
    static func name(for code: UInt32) -> String { map[code] ?? "Key\(code)" }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var refs: [EventHotKeyRef?] = []
    private var handlerInstalled = false
    var onAction: ((HotKeyAction) -> Void)?

    func registerAll() {
        // Unregister previous (when user changes shortcuts)
        for ref in refs { if let ref = ref { UnregisterEventHotKey(ref) } }
        refs = []
        if !handlerInstalled {
            handlerInstalled = true
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event = event else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                let action = HotKeyAction.allCases.first { $0.id == hkID.id }
                DispatchQueue.main.async { if let a = action { HotKeyManager.shared.onAction?(a) } }
                return noErr
            }, 1, &eventType, nil, nil)
        }
        for action in HotKeyAction.allCases {
            let cfg = HotKeyConfig.load(action)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x534E4150), id: action.id) // 'SNAP'
            RegisterEventHotKey(cfg.keyCode, cfg.carbonMods, hkID, GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
    }
}
