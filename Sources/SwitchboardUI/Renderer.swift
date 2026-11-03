import AppKit
import SwiftUI

/// Draws a SwiftUI view to PNG without showing anything: the app's `--snap` and the UI tests use
/// it. A window hosts the view, so the AppKit controls it contains draw too (ImageRenderer leaves
/// those as placeholders, and cacheDisplay draws nothing for a view outside a window). The window
/// is never ordered on screen.
@MainActor
public enum Renderer {
    /// Every image is drawn at this scale, whatever the display, so machines agree on its size.
    public static let scale: CGFloat = 2

    public static func render<V: View>(_ view: V, size: CGSize, dark: Bool) async throws -> Pixels {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        window.contentView = host
        // SwiftUI and the AppKit views it hosts settle over a few run loop turns.
        for _ in 0..<6 {
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bounds = host.bounds
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw RenderError("Couldn’t allocate a \(bounds.width)×\(bounds.height) bitmap.") }
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { throw RenderError("The bitmap has no image.") }
        let pixels = try Pixels(image)
        if pixels.isBlank { throw RenderError("The view drew nothing: every pixel is the same colour.") }
        return pixels
    }

    /// Renders the named scene in one theme to `url`.
    public static func snap(scene name: String, dark: Bool, to url: URL) async throws {
        let scene = try Scenes.make(name)
        defer { scene.remove() }
        let pixels = try await render(scene.view, size: scene.size, dark: dark)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pixels.png().write(to: url)
    }
}

public struct RenderError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// RGBA8, premultiplied, in sRGB, so a rendered image and a decoded PNG compare byte for byte.
public struct Pixels: Sendable {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: Self.colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw RenderError("Couldn’t draw a \(width)×\(height) image.") }
        self.init(width: width, height: height, bytes: bytes)
    }

    public init(png data: Data) throws {
        guard let image = NSBitmapImageRep(data: data)?.cgImage else { throw RenderError("Not a PNG image.") }
        try self.init(image)
    }

    private static var colorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    public var isBlank: Bool {
        guard bytes.count >= 4 else { return true }
        for index in 4..<bytes.count where bytes[index] != bytes[index % 4] { return false }
        return true
    }

    /// The number of changed pixels, and an image of this one dimmed with each changed pixel in red.
    public func difference(from other: Pixels, tolerance: Int) -> (Int, Pixels) {
        var diff = bytes
        var changed = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            var moved = false
            for channel in 0..<4
            where abs(Int(bytes[pixel + channel]) - Int(other.bytes[pixel + channel])) > tolerance {
                moved = true
            }
            if moved {
                changed += 1
                diff[pixel] = 255
                diff[pixel + 1] = 0
                diff[pixel + 2] = 0
                diff[pixel + 3] = 255
            } else {
                for channel in 0..<3 { diff[pixel + channel] /= 4 }
            }
        }
        return (changed, Pixels(width: width, height: height, bytes: diff))
    }

    public func png() throws -> Data {
        var bytes = bytes
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image,
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError("Couldn’t encode a \(width)×\(height) PNG.") }
        return data
    }
}
