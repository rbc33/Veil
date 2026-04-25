import AppKit

struct RecordingShortcut {
    var modifiers: NSEvent.ModifierFlags
    var key: String // empty = modifier-only

    static let `default`        = RecordingShortcut(modifiers: [.command, .option], key: "")
    static let defaultCapture   = RecordingShortcut(modifiers: [.command, .shift], key: "")

    static func load(prefix: String, fallback: RecordingShortcut) -> RecordingShortcut {
        let raw = UserDefaults.standard.integer(forKey: "\(prefix)Modifiers")
        guard raw != 0 else { return fallback }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(raw))
            .intersection([.command, .option, .control, .shift])
        let key = UserDefaults.standard.string(forKey: "\(prefix)Key") ?? ""
        return RecordingShortcut(modifiers: mods, key: key)
    }

    static func save(_ s: RecordingShortcut, prefix: String) {
        UserDefaults.standard.set(Int(s.modifiers.rawValue), forKey: "\(prefix)Modifiers")
        UserDefaults.standard.set(s.key, forKey: "\(prefix)Key")
    }

    static var current: RecordingShortcut {
        get { load(prefix: "shortcut", fallback: .default) }
        set { save(newValue, prefix: "shortcut") }
    }

    static var capture: RecordingShortcut {
        get { load(prefix: "captureShortcut", fallback: .defaultCapture) }
        set { save(newValue, prefix: "captureShortcut") }
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
