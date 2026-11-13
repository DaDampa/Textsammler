import AppKit
import CryptoKit

/// Helpers for copied images: PNG conversion, thumbnails, and a fingerprint to spot duplicates.
enum ImageTools {
    /// The image on the clipboard as PNG data, if there is one.
    static func png(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    static func pixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// A small PNG for list rows, so the list never decodes full screenshots.
    static func thumbnail(_ data: Data, maxSide: CGFloat = 160) -> Data? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let small = NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        return png(from: small)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A drawn stand-in for a screenshot, for seed data and the self-test.
    static func sample(width: CGFloat = 640, height: CGFloat = 360, hue: CGFloat = 0.58) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSGradient(starting: NSColor(hue: hue, saturation: 0.5, brightness: 0.95, alpha: 1),
                       ending: NSColor(hue: hue + 0.08, saturation: 0.7, brightness: 0.6, alpha: 1))?.draw(in: rect, angle: -60)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: width * 0.12, dy: height * 0.2), xRadius: 12, yRadius: 12).fill()
            return true
        }
        return png(from: image) ?? Data()
    }
}
