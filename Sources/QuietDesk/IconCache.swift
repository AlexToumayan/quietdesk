import AppKit

/// Bounded cache of Finder-style icons, pre-rendered at the one size the desktop draws them.
/// `NSWorkspace.icon(forFile:)` resolves the icon from the file's type and metadata (it does not
/// read document contents, and the process-wide dataless-file policy in main.swift guarantees
/// it can never trigger a cloud download). The multi-resolution NSImage it returns is rendered
/// once into a small 2x bitmap and discarded, so each cached icon costs a few tens of KB.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let limit = 600

    func icon(for url: URL, size: CGFloat) -> NSImage {
        let key = "\(Int(size))|\(url.path)"
        if let image = cache[key] { return image }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let image = render(source, size: size)
        if cache.count >= limit { cache.removeAll() }
        cache[key] = image
        return image
    }

    private func render(_ source: NSImage, size: CGFloat) -> NSImage {
        let scale: CGFloat = 2   // Retina; on a 1x display AppKit downsamples on draw
        let pixels = Int(size * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    func invalidate(_ url: URL) { cache = cache.filter { !$0.key.hasSuffix("|\(url.path)") } }
    func removeAll() { cache.removeAll() }
}
