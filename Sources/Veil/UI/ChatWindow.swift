import AppKit
import WebKit

class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper

    override init() {
        let savedStr = UserDefaults.standard.string(forKey: "windowFrame")
        let defaultFrame = NSRect(x: 0, y: 0, width: 800, height: 620)
        var initialFrame = defaultFrame
        var shouldCenter = true
        if let s = savedStr {
            let f = NSRectFromString(s)
            if f.width > 100 && f.height > 100 { initialFrame = f; shouldCenter = false }
        }

        window = MovableWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden    = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden     = true
        window.level = .floating
        if shouldCenter { window.center() }
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let visualEffect = NSVisualEffectView(frame: window.contentLayoutRect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]

        webView = WKWebViewWrapper(frame: visualEffect.bounds)
        webView.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(webView.view)
        window.contentView = visualEffect
        super.init()
        window.delegate = self
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.sharingType = .none
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification)   { saveFrame() }
    func windowWillClose(_ notification: Notification) {}

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "windowFrame")
    }
}
