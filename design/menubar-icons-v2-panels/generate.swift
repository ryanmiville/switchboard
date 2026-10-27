import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Six panel variants combining the v1 panel frames with v1 #17's jack and plug.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fm = FileManager.default
for directory in ["svg", "pdf", "png", "previews"] {
    try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
}

struct Mark {
    let path: CGPath
    let svg: String
    let weight: CGFloat?
}

struct Icon {
    let name: String
    let slug: String
    var marks: [Mark]
}

func path(_ commands: String, _ points: [(String, [CGFloat])], weight: CGFloat = 1.8) -> Mark {
    let p = CGMutablePath()
    for (kind, v) in points {
        switch kind {
        case "M": p.move(to: CGPoint(x: v[0], y: v[1]))
        case "L": p.addLine(to: CGPoint(x: v[0], y: v[1]))
        case "C": p.addCurve(to: CGPoint(x: v[4], y: v[5]), control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
        default: fatalError("Unknown command")
        }
    }
    return Mark(path: p, svg: "<path d=\"\(commands)\"/>", weight: weight)
}

func wire(_ d: String, _ points: [(String, [CGFloat])], _ weight: CGFloat = 1.9) -> Mark {
    path(d, points, weight: weight)
}

func jack(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat = 1.85, _ weight: CGFloat = 1.5) -> Mark {
    Mark(path: CGPath(ellipseIn: CGRect(x: x-radius, y: y-radius, width: 2*radius, height: 2*radius), transform: nil),
         svg: "<circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(radius)\"/>", weight: weight)
}

func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, weight: CGFloat? = nil) -> Mark {
    Mark(path: CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil),
         svg: "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\"/>", weight: weight)
}

func plug(_ x: CGFloat, _ y: CGFloat, angle: CGFloat = 0, width: CGFloat = 2.9, height: CGFloat = 4) -> [Mark] {
    let rect = CGRect(x: -width/2, y: -height/2, width: width, height: height)
    var transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle * .pi / 180)
    let body = CGPath(roundedRect: rect, cornerWidth: 0.7, cornerHeight: 0.7, transform: &transform)
    let tip = CGPath(rect: CGRect(x: -0.65, y: height/2-0.05, width: 1.3, height: 0.6), transform: &transform)
    let group = "transform=\"translate(\(x) \(y)) rotate(\(angle))\""
    return [Mark(path: body, svg: "<rect \(group) x=\"\(-width/2)\" y=\"\(-height/2)\" width=\"\(width)\" height=\"\(height)\" rx=\"0.7\"/>", weight: nil),
            Mark(path: tip, svg: "<rect \(group) x=\"-0.65\" y=\"\(height/2-0.05)\" width=\"1.3\" height=\"0.6\"/>", weight: nil)]
}

func draw(_ icon: Icon, in ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: size/18, y: size/18)
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for mark in icon.marks {
        ctx.addPath(mark.path)
        if let weight = mark.weight { ctx.setLineWidth(weight); ctx.strokePath() }
        else { ctx.fillPath() }
    }
    ctx.restoreGState()
}

let black = CGColor(gray: 0, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

func png(_ name: String, width: CGFloat, height: CGFloat, scale: CGFloat = 2, render: (CGContext) -> Void) throws {
    let ctx = CGContext(data: nil, width: Int(width*scale), height: Int(height*scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    render(ctx)
    NSGraphicsContext.restoreGraphicsState()
    let image = ctx.makeImage()!
    let out = CGImageDestinationCreateWithURL(root.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fatalError("PNG export failed") }
}

func fill(_ ctx: CGContext, _ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
    ctx.setFillColor(color.cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

func text(_ value: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
    (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

let ink = NSColor(calibratedWhite: 0.10, alpha: 1)
let muted = NSColor(calibratedWhite: 0.43, alpha: 1)
let paper = NSColor(calibratedWhite: 0.97, alpha: 1)
let dark = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)

let panel = box(1.35, 1.35, 15.3, 15.3, 3, weight: 1.15)
let cable = wire(
    "M5.15 10.55 C5.35 7.45 11.6 1.95 13.1 3.95",
    [("M", [5.15,10.55]), ("C", [5.35,7.45,11.6,1.95,13.1,3.95])], 1.75)
let connectedJack = jack(5.15, 12.55, 1.95, 1.4)
let connectedPlug = plug(13.1, 5.75, width: 2.8, height: 3.6)
let upperSpare = jack(4.7, 5.1, 1.1, 1.05)
let lowerSpare = jack(13.2, 12.8, 1.1, 1.05)
let divider = wire(
    "M1.9 9.4 L3.35 9.4 M9.6 9.4 L16.1 9.4",
    [("M", [1.9,9.4]), ("L", [3.35,9.4]), ("M", [9.6,9.4]), ("L", [16.1,9.4])], 1.05)
let core = [cable, connectedJack] + connectedPlug

let icons: [Icon] = [
    Icon(name: "Clean panel", slug: "clean-panel", marks: [panel] + core),
    Icon(name: "One spare socket", slug: "one-spare-socket", marks: [panel, lowerSpare] + core),
    Icon(name: "Two spare sockets", slug: "two-spare-sockets", marks: [panel, upperSpare, lowerSpare] + core),
    Icon(name: "Clean split panel", slug: "clean-split-panel", marks: [panel, divider] + core),
    Icon(name: "Split + one socket", slug: "split-one-socket", marks: [panel, divider, lowerSpare] + core),
    Icon(name: "Split + two sockets", slug: "split-two-sockets", marks: [panel, divider, upperSpare, lowerSpare] + core),
]
let letters = ["A", "B", "C", "D", "E", "F"]

func tile(_ index: Int, _ ctx: CGContext, x: CGFloat, y: CGFloat) {
    let icon = icons[index]
    let width: CGFloat = 212
    fill(ctx, CGRect(x: x, y: y, width: width, height: 290), .white, radius: 14)
    text(letters[index], at: CGPoint(x: x+15, y: y+12), size: 15, weight: .semibold, color: muted)
    draw(icon, in: ctx, x: x+63, y: y+39, size: 86, color: black)
    text(icon.name, at: CGPoint(x: x+14, y: y+146), size: 13.5, weight: .semibold, color: ink)
    for (row, size) in [CGFloat(18), CGFloat(16)].enumerated() {
        let rowY = y+190+CGFloat(row*44)
        text("\(Int(size)) pt", at: CGPoint(x: x+14, y: rowY+9), size: 10, weight: .medium, color: muted)
        fill(ctx, CGRect(x: x+51, y: rowY, width: 67, height: 32), NSColor(calibratedWhite: 0.93, alpha: 1), radius: 6)
        fill(ctx, CGRect(x: x+128, y: rowY, width: 67, height: 32), dark, radius: 6)
        draw(icon, in: ctx, x: x+51+(67-size)/2, y: rowY+(32-size)/2, size: size, color: black)
        draw(icon, in: ctx, x: x+128+(67-size)/2, y: rowY+(32-size)/2, size: size, color: white)
    }
}

var manifest: [[String: Any]] = []
for (index, icon) in icons.enumerated() {
    // No part of a stroked path may be clipped by the 18-point template canvas.
    for mark in icon.marks {
        let halfWidth = (mark.weight ?? 0)/2
        let bounds = mark.path.boundingBoxOfPath.insetBy(dx: -halfWidth, dy: -halfWidth)
        precondition(CGRect(x: 0, y: 0, width: 18, height: 18).contains(bounds))
    }
    let stem = letters[index] + "-" + icon.slug
    let fragments = icon.marks.map { mark in
        let style = mark.weight.map { "fill=\"none\" stroke=\"black\" stroke-width=\"\($0)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" } ?? "fill=\"black\""
        return "<g \(style)>\(mark.svg)</g>"
    }.joined(separator: "\n")
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\">\n<title>Switchboard — \(letters[index]): \(icon.name)</title>\n\(fragments)\n</svg>\n"
    try svg.write(to: root.appendingPathComponent("svg/\(stem).svg"), atomically: true, encoding: .utf8)
    for (variant, color) in [("black", black), ("white", white)] {
        for scale: CGFloat in [1,2,4] {
            let suffix = scale == 1 ? "" : "@\(Int(scale))x"
            try png("png/\(stem)-\(variant)\(suffix).png", width: 18, height: 18, scale: scale) {
                draw(icon, in: $0, x: 0, y: 0, size: 18, color: color)
            }
        }
    }
    let consumer = CGDataConsumer(url: root.appendingPathComponent("pdf/\(stem).pdf") as CFURL)!
    var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
    let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
    pdf.beginPDFPage(nil)
    pdf.translateBy(x: 0, y: 18)
    pdf.scaleBy(x: 1, y: -1)
    draw(icon, in: pdf, x: 0, y: 0, size: 18, color: black)
    pdf.endPDFPage()
    pdf.closePDF()
    try png("previews/\(stem).png", width: 236, height: 314) {
        fill($0, CGRect(x: 0, y: 0, width: 236, height: 314), paper)
        tile(index, $0, x: 12, y: 12)
    }
    manifest.append(["letter": letters[index], "name": icon.name, "stem": stem, "logicalSize": 18])
}

for row in 0..<2 {
    try png("previews/board-\(row+1).png", width: 700, height: 364) { ctx in
        fill(ctx, CGRect(x: 0, y: 0, width: 700, height: 364), paper)
        let title = row == 0 ? "A–C · Rounded panel + 17’s jack and plug" : "D–F · Split panel + 17’s jack and plug"
        text(title, at: CGPoint(x: 20, y: 17), size: 17, weight: .semibold, color: ink)
        for column in 0..<3 { tile(row*3+column, ctx, x: CGFloat(20+column*224), y: 54) }
    }
}

try png("previews/all-six.png", width: 700, height: 704) { ctx in
    fill(ctx, CGRect(x: 0, y: 0, width: 700, height: 704), paper)
    text("SWITCHBOARD / PANEL + JACK & PLUG", at: CGPoint(x: 20, y: 18), size: 18, weight: .semibold, color: ink)
    text("Enlarged above; 18 pt and 16 pt on light and dark below.", at: CGPoint(x: 20, y: 47), size: 12, color: muted)
    for row in 0..<2 {
        for column in 0..<3 { tile(row*3+column, ctx, x: CGFloat(20+column*224), y: CGFloat(84+row*306)) }
    }
}

try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("manifest.json"))
print("Created six panel variants with transparent PNGs, SVG/PDF masters and 18/16-point light/dark preview boards.")

