import AppKit

class ShortcutRecorder: NSObject {
    let field: NSTextField
    private var recording = false
    private var monitor: Any?
    private var pending: RecordingShortcut = .current
    var onChange: ((RecordingShortcut) -> Void)?

    override init() {
        field = NSTextField(frame: NSRect(x: 0, y: 0, width: 110, height: 22))
        super.init()
        field.isEditable = false
        field.isSelectable = false
        field.alignment = .center
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.stringValue = RecordingShortcut.current.displayString
        field.toolTip = "Click to record a new shortcut"
        field.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    @objc private func clicked() {
        recording ? stopRecording(save: false) : startRecording()
    }

    private func startRecording() {
        pending = RecordingShortcut.current
        recording = true
        field.stringValue = "Press shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            self?.handle(e)
            return nil
        }
    }

    private func stopRecording(save: Bool) {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        field.stringValue = pending.displayString
        if save { RecordingShortcut.current = pending; onChange?(pending) }
    }

    private func handle(_ e: NSEvent) {
        if e.type == .flagsChanged {
            let m = e.modifierFlags.intersection([.command, .option, .control, .shift])
            pending = RecordingShortcut(modifiers: m, key: "")
            field.stringValue = m.isEmpty ? "Press shortcut…" : pending.displayString + " ↩"
            return
        }
        switch e.keyCode {
        case 53: // Escape — cancel
            pending = RecordingShortcut.current
            stopRecording(save: false)
        case 36, 76: // Return/Enter — confirm modifier-only
            stopRecording(save: true)
        default:
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let chars = e.charactersIgnoringModifiers ?? ""
            guard let scalar = chars.unicodeScalars.first, scalar.value < 0xF700 else { return }
            pending = RecordingShortcut(modifiers: mods, key: String(chars).lowercased())
            stopRecording(save: true)
        }
    }
}
