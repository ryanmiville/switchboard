import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Preview-only icon exploration. All geometry uses an 18-point, top-left-origin grid.
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
    let tip = CGPath(rect: CGRect(x: -0.65, y: height/2-0.05, width: 1.3, height: 1.05), transform: &transform)
    let group = "transform=\"translate(\(x) \(y)) rotate(\(angle))\""
    return [Mark(path: body, svg: "<rect \(group) x=\"\(-width/2)\" y=\"\(-height/2)\" width=\"\(width)\" height=\"\(height)\" rx=\"0.7\"/>", weight: nil),
            Mark(path: tip, svg: "<rect \(group) x=\"-0.65\" y=\"\(height/2-0.05)\" width=\"1.3\" height=\"1.05\"/>", weight: nil)]
}

let classic = wire("M4 11.65 C4.7 7.2 12.2 -0.1 14 2.65", [("M", [4,11.65]), ("C", [4.7,7.2,12.2,-0.1,14,2.65])], 2)
let plugged = wire("M4 11 C4.6 7.2 12.3 -0.1 14 2.7", [("M", [4,11]), ("C", [4.6,7.2,12.3,-0.1,14,2.7])], 2)

let icons: [Icon] = [
    Icon(name: "Original patchbay", slug: "original-patchbay", marks:
        [jack(4,4.5,1.3,1.35),jack(14,10,1.3,1.35),jack(14,14.5,1.3,1.35),plugged] + plug(4,13) + plug(14,4.7)),
    Icon(name: "Four sockets", slug: "four-sockets", marks:
        [jack(4,4.5,1.75),jack(14,13.5,1.75),classic,jack(4,13.5),jack(14,4.5)]),
    Icon(name: "Classic cable", slug: "classic-cable", marks:
        [classic,jack(4,13.5),jack(14,4.5)]),
    Icon(name: "Plugged in", slug: "plugged-in", marks:
        [plugged] + plug(4,13) + plug(14,4.7)),
    Icon(name: "Spare socket", slug: "spare-socket", marks:
        [jack(4,4.5,1.75),plugged] + plug(4,13) + plug(14,4.7)),

    Icon(name: "Cable bridge", slug: "cable-bridge", marks:
        [wire("M4 11.45 C4 2.1 14 2.1 14 11.45", [("M",[4,11.45]),("C",[4,2.1,14,2.1,14,11.45])],2),jack(4,13.3),jack(14,13.3)]),
    Icon(name: "Return loop", slug: "return-loop", marks:
        [wire("M11.65 4.5 C0.8 1.5 0.8 16.5 11.65 13.5",[("M",[11.65,4.5]),("C",[0.8,1.5,0.8,16.5,11.65,13.5])],2),jack(13.5,4.5),jack(13.5,13.5)]),
    Icon(name: "Soft S", slug: "soft-s", marks:
        [wire("M3.5 11.65 C3.5 3.5 14.5 14.5 14.5 6.35",[("M",[3.5,11.65]),("C",[3.5,3.5,14.5,14.5,14.5,6.35])],2),jack(3.5,13.5),jack(14.5,4.5)]),
    Icon(name: "Sweeping patch", slug: "sweeping-patch", marks:
        [wire("M3.6 10.95 C3.6 3 7.7 2 10.5 3.5 C11.5 4 11.8 5.2 12.55 5.2",[("M",[3.6,10.95]),("C",[3.6,3,7.7,2,10.5,3.5]),("C",[11.5,4,11.8,5.2,12.55,5.2])],2),jack(3.6,12.8),jack(14.4,5.2)]),
    Icon(name: "Elbow cable", slug: "elbow-cable", marks:
        [wire("M4 11 L4 7.5 C4 5.4 5.4 4 7.5 4 L12 4",[("M",[4,11]),("L",[4,7.5]),("C",[4,5.4,5.4,4,7.5,4]),("L",[12,4])],2)] + plug(4,13) + plug(14,4,angle:-90)),

    Icon(name: "Rounded panel", slug: "rounded-panel", marks:
        [box(1.5,1.5,15,15,3,weight:1.25),jack(5,5,1.15,1.2),jack(13,13,1.15,1.2),wire("M5 11.85 C5 8.2 10.3 2.4 13 3.85",[("M",[5,11.85]),("C",[5,8.2,10.3,2.4,13,3.85])],1.65),jack(5,13,1.15,1.2),jack(13,5,1.15,1.2)]),
    Icon(name: "Open panel", slug: "open-panel", marks:
        [wire("M1.75 6 L1.75 2 L6 2 M12 16 L16.25 16 L16.25 12",[("M",[1.75,6]),("L",[1.75,2]),("L",[6,2]),("M",[12,16]),("L",[16.25,16]),("L",[16.25,12])],1.4),wire("M5 11.2 C5.7 7.8 11 2.4 13 3.8",[("M",[5,11.2]),("C",[5.7,7.8,11,2.4,13,3.8])],1.9),jack(5,13,1.8),jack(13,5.6,1.8)]),
    Icon(name: "Three-way patch", slug: "three-way-patch", marks:
        [wire("M4 11.2 C4 7 7 1.7 9 2.7",[("M",[4,11.2]),("C",[4,7,7,1.7,9,2.7])],1.9),jack(4,13,1.8),jack(9,4.5,1.8),jack(14,13,1.8)]),
    Icon(name: "Patch row", slug: "patch-row", marks:
        [wire("M3.5 11.6 C3.5 2.2 14.5 2.2 14.5 11.6",[("M",[3.5,11.6]),("C",[3.5,2.2,14.5,2.2,14.5,11.6])],1.9),jack(3.5,13,1.4,1.35),jack(9,13,1.4,1.35),jack(14.5,13,1.4,1.35)]),
    Icon(name: "Split panel", slug: "split-panel", marks:
        [box(1.5,1.5,15,15,2.5,weight:1.2),wire("M1.8 9.6 L5.3 9.6 M11.8 9.6 L16.2 9.6",[("M",[1.8,9.6]),("L",[5.3,9.6]),("M",[11.8,9.6]),("L",[16.2,9.6])],1.15),jack(5,5,1.15,1.2),jack(13,13,1.15,1.2),wire("M5 11.85 C5.5 8 10.6 2.2 13 3.85",[("M",[5,11.85]),("C",[5.5,8,10.6,2.2,13,3.85])],1.65),jack(5,13,1.15,1.2),jack(13,5,1.15,1.2)]),

    Icon(name: "Angled leads", slug: "angled-leads", marks:
        [wire("M4.8 11.2 C7 5.7 9.6 2 12.8 4.2",[("M",[4.8,11.2]),("C",[7,5.7,9.6,2,12.8,4.2])],2)] + plug(4,13,angle:25,width:3.2,height:3.6) + plug(14,5.6,angle:-42,width:3.2,height:3.6)),
    Icon(name: "Jack and plug", slug: "jack-and-plug", marks:
        [wire("M4.2 11 C4.4 7 11.8 0.3 14 2.7",[("M",[4.2,11]),("C",[4.4,7,11.8,0.3,14,2.7])],2.1),jack(4.2,13.3,2.25,1.6)] + plug(14,4.7,width:3.2)),
    Icon(name: "Send cable", slug: "send-cable", marks:
        [wire("M4 11 C4 5.5 8.5 3.8 14 3.8 M11.5 1.3 L14 3.8 L11.5 6.3",[("M",[4,11]),("C",[4,5.5,8.5,3.8,14,3.8]),("M",[11.5,1.3]),("L",[14,3.8]),("L",[11.5,6.3])],1.9),jack(4,13,2)]),
    Icon(name: "Port selector", slug: "port-selector", marks:
        [wire("M5.65 9 C9.5 9 8.8 4.5 12.35 4.5",[("M",[5.65,9]),("C",[9.5,9,8.8,4.5,12.35,4.5])],1.9),jack(3.8,9),jack(14.2,4.5),jack(14.2,13.5)]),
    Icon(name: "Two routes", slug: "two-routes", marks:
        [wire("M4 3.4 C5.5 0.8 12.5 0.8 14 3.4 M4 14.6 C5.5 17.2 12.5 17.2 14 14.6",[("M",[4,3.4]),("C",[5.5,0.8,12.5,0.8,14,3.4]),("M",[4,14.6]),("C",[5.5,17.2,12.5,17.2,14,14.6])],1.75),jack(4,5,1.6,1.4),jack(14,5,1.6,1.4),jack(4,13,1.6,1.4),jack(14,13,1.6,1.4)])
]

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

func tile(_ index: Int, _ ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat = 154) {
    let icon = icons[index]
    fill(ctx, CGRect(x: x, y: y, width: width, height: 206), .white, radius: 12)
    text(String(format: "%02d", index+1), at: CGPoint(x: x+12, y: y+10), size: 12, weight: .semibold, color: muted)
    draw(icon, in: ctx, x: x+(width-66)/2, y: y+31, size: 66, color: black)
    text(icon.name, at: CGPoint(x: x+12, y: y+111), size: 11.5, weight: .semibold, color: ink)
    fill(ctx, CGRect(x: x+10, y: y+141, width: 62, height: 32), NSColor(calibratedWhite: 0.93, alpha: 1), radius: 6)
    fill(ctx, CGRect(x: x+width-72, y: y+141, width: 62, height: 32), dark, radius: 6)
    draw(icon, in: ctx, x: x+32, y: y+148, size: 18, color: black)
    draw(icon, in: ctx, x: x+width-50, y: y+148, size: 18, color: white)
    text("18 pt · light / dark", at: CGPoint(x: x+24, y: y+182), size: 9.5, color: muted)
}

var manifest: [[String: Any]] = []
for (index, icon) in icons.enumerated() {
    let stem = String(format: "%02d", index+1) + "-" + icon.slug
    let fragments = icon.marks.map { mark in
        let style = mark.weight.map { "fill=\"none\" stroke=\"black\" stroke-width=\"\($0)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" } ?? "fill=\"black\""
        return "<g \(style)>\(mark.svg)</g>"
    }.joined(separator: "\n")
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\">\n<title>Switchboard — \(icon.name)</title>\n\(fragments)\n</svg>\n"
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
    try png("previews/\(stem).png", width: 178, height: 230) {
        fill($0, CGRect(x: 0, y: 0, width: 178, height: 230), paper)
        tile(index, $0, x: 12, y: 12)
    }
    manifest.append(["number": index+1, "name": icon.name, "stem": stem, "logicalSize": 18])
}

let titles = ["01–05 · Closest to the app icon", "06–10 · Cable silhouettes", "11–15 · Patchboard variations", "16–20 · Plugs and routing"]
for row in 0..<4 {
    try png("previews/board-\(row+1).png", width: 826, height: 285) { ctx in
        fill(ctx, CGRect(x: 0, y: 0, width: 826, height: 285), paper)
        text(titles[row], at: CGPoint(x: 20, y: 16), size: 17, weight: .semibold, color: ink)
        for column in 0..<5 { tile(row*5+column, ctx, x: CGFloat(20+column*162), y: 59) }
    }
}

try png("previews/all-20.png", width: 826, height: 955) { ctx in
    fill(ctx, CGRect(x: 0, y: 0, width: 826, height: 955), paper)
    text("SWITCHBOARD / 20 MENU-BAR ICONS", at: CGPoint(x: 20, y: 18), size: 18, weight: .semibold, color: ink)
    text("Patch cables, plugs and sockets. Enlarged above; 18 pt on light and dark below.", at: CGPoint(x: 20, y: 47), size: 12, color: muted)
    for row in 0..<4 {
        for column in 0..<5 { tile(row*5+column, ctx, x: CGFloat(20+column*162), y: CGFloat(84+row*216)) }
    }
}

try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("manifest.json"))
print("Created \(icons.count) SVGs, PDFs, 1x/2x/4x transparent PNGs, and light/dark preview boards at \(root.path)")
