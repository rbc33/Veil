import AppKit

class MovableWindow: NSWindow {
    private var dragging = false
    private let headerHeight: CGFloat = 38

    override func sendEvent(_ event: NSEvent) {
        let h = contentView?.frame.height ?? frame.height
        let inHeader = event.locationInWindow.y >= h - headerHeight
        switch event.type {
        case .leftMouseDown:
            dragging = inHeader
        case .leftMouseUp:
            dragging = false
        case .leftMouseDragged where dragging:
            let o = frame.origin
            setFrameOrigin(NSPoint(x: o.x + event.deltaX, y: o.y - event.deltaY))
            return
        default: break
        }
        super.sendEvent(event)
    }
}
