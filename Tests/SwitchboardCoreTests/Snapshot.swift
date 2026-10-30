import AppKit
import SwiftUI
import Testing

// Renders SwiftUI views to PNG and compares them with goldens in Tests/SwitchboardCoreTests/Snapshots.
//
//   make snapshots                     render every scene into .build/snapshots and compare
//   SNAPSHOT_RECORD=1 make snapshots   rewrite the goldens from this Mac
//
// Pixels depend on the macOS version and the Mac's appearance settings, so goldens are compared only
// locally. With CI set, scenes are rendered and written to .build/snapshots but not compared.
@MainActor
enum Snapshot {
    // Every image is drawn at 2x, whatever the display, so Retina and non-Retina Macs agree on size.
    static let scale: CGFloat = 2
    // A pixel counts as changed when any channel moves by more than this many levels.
    static let channelTolerance = 8
    // A snapshot fails when more than this share of its pixels changed.
    static let pixelTolerance = 0.001

    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Snapshots")
    static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/snapshots")

    // A window hosts the view, so the AppKit controls it contains draw too. ImageRenderer leaves those as
    // placeholders, and cacheDisplay draws nothing for a view outside a window. The window is never shown.
    static func render<V: View>(_ view: V, size: CGSize, dark: Bool) async throws -> Pixels {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        let host = NSHostingView(rootView: view)
        window.contentView = host
        // SwiftUI and the AppKit views it hosts settle over a few run loop turns. A toolbar installed by
        // the view can resize the window, so restore the content size each time.
        for _ in 0..<5 {
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
                pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw SnapshotError("Couldn’t allocate a \(bounds.width)×\(bounds.height) bitmap.") }
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { throw SnapshotError("The bitmap has no image.") }
        let pixels = try Pixels(image)
        if pixels.isBlank {
            throw SnapshotError(
                "The view drew nothing: every pixel is the same colour. cacheDisplay may not have rendered the hosting view on this macOS version."
            )
        }
        return pixels
    }

    // Writes the image to .build/snapshots, then compares it with its golden unless recording or on CI.
    static func check(
        _ name: String, _ pixels: Pixels, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let png = try pixels.png()
        let failures = output.appendingPathComponent("failures")
        let actualURL = failures.appendingPathComponent("\(name)-actual.png")
        let diffURL = failures.appendingPathComponent("\(name)-diff.png")
        try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent("\(name).png"))
        try? FileManager.default.removeItem(at: actualURL)
        try? FileManager.default.removeItem(at: diffURL)

        let golden = goldens.appendingPathComponent("\(name).png")
        let environment = ProcessInfo.processInfo.environment
        if let record = environment["SNAPSHOT_RECORD"], !record.isEmpty, record != "0" {
            try png.write(to: golden)
            return
        }
        if environment["CI"] != nil { return }
        guard let data = try? Data(contentsOf: golden) else {
            try png.write(to: golden)
            Issue.record(
                Comment(rawValue: "Recorded a new golden at \(golden.path). Review it, then commit it."),
                sourceLocation: sourceLocation)
            return
        }
        guard let goldenImage = NSBitmapImageRep(data: data)?.cgImage else {
            throw SnapshotError("Couldn’t read the golden at \(golden.path).")
        }
        let expected = try Pixels(goldenImage)
        guard expected.width == pixels.width, expected.height == pixels.height else {
            try png.write(to: actualURL)
            Issue.record(
                Comment(
                    rawValue:
                        "\(name) is \(pixels.width)×\(pixels.height) px; its golden is \(expected.width)×\(expected.height). Actual: \(actualURL.path)"
                ), sourceLocation: sourceLocation)
            return
        }
        let (changed, diff) = pixels.difference(from: expected, tolerance: channelTolerance)
        let share = Double(changed) / Double(pixels.width * pixels.height)
        guard share > pixelTolerance else { return }
        try png.write(to: actualURL)
        try diff.png().write(to: diffURL)
        Issue.record(
            Comment(
                rawValue: """
                    \(name) differs from its golden in \(changed) pixels (\(String(format: "%.2f", share * 100))%).
                      golden: \(golden.path)
                      actual: \(actualURL.path)
                      diff:   \(diffURL.path)
                    If the change is intended, rerun with SNAPSHOT_RECORD=1 and review the golden diff.
                    """), sourceLocation: sourceLocation)
    }
}

struct SnapshotError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// RGBA8, premultiplied, in sRGB, so a rendered image and a decoded PNG compare byte for byte.
struct Pixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    init(_ image: CGImage) throws {
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
        guard drawn else { throw SnapshotError("Couldn’t draw a \(width)×\(height) image.") }
        self.init(width: width, height: height, bytes: bytes)
    }

    private static var colorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    var isBlank: Bool {
        guard bytes.count >= 4 else { return true }
        for index in 4..<bytes.count where bytes[index] != bytes[index % 4] { return false }
        return true
    }

    // The number of changed pixels, and an image of this one dimmed with each changed pixel in red.
    func difference(from other: Pixels, tolerance: Int) -> (Int, Pixels) {
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

    func png() throws -> Data {
        var bytes = bytes
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: Self.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image,
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw SnapshotError("Couldn’t encode a \(width)×\(height) PNG.") }
        return data
    }
}
