import Carbon

private var _hotKeyCallback: (() -> Void)?

private func hotKeyProc(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    _hotKeyCallback?()
    return noErr
}

class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(callback: @escaping () -> Void) {
        _hotKeyCallback = callback
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyProc, 1, &spec, nil, &handler)
        let hkID = EventHotKeyID(signature: OSType(0x5645494C), id: 1) // 'VEIL'
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
    }
}
