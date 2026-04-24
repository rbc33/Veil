import AppKit

func captureScreenBase64(maxWidth: Int = 1440) -> String? {
    let cg = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    if cg == nil {
        CGRequestScreenCaptureAccess()
        return nil
    }
    guard let cg = cg else { return nil }
    let w = cg.width, h = cg.height
    let scale = w > maxWidth ? Double(maxWidth) / Double(w) : 1.0
    let tw = max(1, Int(Double(w) * scale)), th = max(1, Int(Double(h) * scale))
    guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
    guard let resized = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: resized)
    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png.base64EncodedString()
}
