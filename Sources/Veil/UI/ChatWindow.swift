import AppKit
import WebKit

class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        window = MovableWindow(
            contentRect: frame,
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
        window.center()
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active

        webView = WKWebViewWrapper(frame: visualEffect.bounds)
        webView.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(webView.view)
        window.contentView = visualEffect
        super.init()
        window.delegate = self
    }

    func showAndFocus() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.sharingType = .none
    }

    func windowWillClose(_ notification: Notification) {}
}
