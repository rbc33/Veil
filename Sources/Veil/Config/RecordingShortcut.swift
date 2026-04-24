import AppKit

struct RecordingShortcut {
    var modifiers: NSEvent.ModifierFlags
    var key: String // empty = modifier-only

    static let `default` = RecordingShortcut(modifiers: [.command, .option], key: "")

    static var current: RecordingShortcut {
        get {
            let raw = UserDefaults.standard.integer(forKey: "shortcutModifiers")
            guard raw != 0 else { return .default }
            let mods = NSEvent.ModifierFlags(rawValue: UInt(raw))
                .intersection([.command, .option, .control, .shift])
            let key = UserDefaults.standard.string(forKey: "shortcutKey") ?? ""
            return RecordingShortcut(modifiers: mods, key: key)
        }
        set {
            UserDefaults.standard.set(Int(newValue.modifiers.rawValue), forKey: "shortcutModifiers")
            UserDefaults.standard.set(newValue.key, forKey: "shortcutKey")
        }
    }

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += key.uppercased()
        return s.isEmpty ? "—" : s
    }

    var jsJSON: String {
        let c = modifiers.contains(.command)
        let o = modifiers.contains(.option)
        let t = modifiers.contains(.control)
        let s = modifiers.contains(.shift)
        let k = key.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"cmd\":\(c),\"opt\":\(o),\"ctrl\":\(t),\"shift\":\(s),\"key\":\"\(k)\"}"
    }
}
