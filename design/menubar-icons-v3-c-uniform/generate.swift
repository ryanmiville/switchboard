import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// C revision: all three sockets share exactly the same radius and stroke.
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
let radius: CGFloat = 1.1
let socketStroke: CGFloat = 1.05
let socketCenters: [CGPoint] = [CGPoint(x: 4.7, y: 5.1), CGPoint(x: 13.2, y: 12.8), CGPoint(x: 5.15, y: 12.55)]
let sockets = socketCenters.map { jack($0.x, $0.y, radius, socketStroke) }
let revised = Icon(name: "C · Matching sockets", slug: "C-matching-sockets", marks:
    [panel,
     wire("M5.15 10.925 C5.35 7.45 11.6 1.95 13.1 3.95", [("M",[5.15,10.925]),("C",[5.35,7.45,11.6,1.95,13.1,3.95])],1.75)]
    + sockets + plug(13.1,5.75,width:2.8,height:3.6))
let original = Icon(name: "Previous C", slug: "previous-c", marks:
    [panel,jack(4.7,5.1,1.1,1.05),jack(13.2,12.8,1.1,1.05),
     wire("M5.15 10.55 C5.35 7.45 11.6 1.95 13.1 3.95",[("M",[5.15,10.55]),("C",[5.35,7.45,11.6,1.95,13.1,3.95])],1.75),
     jack(5.15,12.55,1.95,1.4)] + plug(13.1,5.75,width:2.8,height:3.6))

for mark in revised.marks {
    let halfWidth = (mark.weight ?? 0)/2
    precondition(CGRect(x:0,y:0,width:18,height:18).contains(mark.path.boundingBoxOfPath.insetBy(dx:-halfWidth,dy:-halfWidth)))
}
precondition(sockets.allSatisfy { $0.path.boundingBoxOfPath.width == sockets[0].path.boundingBoxOfPath.width && $0.weight == socketStroke })

let fragments = revised.marks.map { mark in
    let style = mark.weight.map { "fill=\"none\" stroke=\"black\" stroke-width=\"\($0)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" } ?? "fill=\"black\""
    return "<g \(style)>\(mark.svg)</g>"
}.joined(separator:"\n")
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\">\n<title>Switchboard C — matching sockets</title>\n\(fragments)\n</svg>\n"
try svg.write(to:root.appendingPathComponent("svg/C-matching-sockets.svg"),atomically:true,encoding:.utf8)
for (variant,color) in [("black",black),("white",white)] {
    for scale: CGFloat in [1,2,4] {
        let suffix = scale == 1 ? "" : "@\(Int(scale))x"
        try png("png/C-matching-sockets-\(variant)\(suffix).png",width:18,height:18,scale:scale) {
            draw(revised,in:$0,x:0,y:0,size:18,color:color)
        }
    }
}
let consumer=CGDataConsumer(url:root.appendingPathComponent("pdf/C-matching-sockets.pdf") as CFURL)!
var bounds=CGRect(x:0,y:0,width:18,height:18)
let pdf=CGContext(consumer:consumer,mediaBox:&bounds,nil)!
pdf.beginPDFPage(nil)
pdf.translateBy(x:0,y:18)
pdf.scaleBy(x:1,y:-1)
draw(revised,in:pdf,x:0,y:0,size:18,color:black)
pdf.endPDFPage()
pdf.closePDF()

func card(_ icon:Icon,_ ctx:CGContext,x:CGFloat,label:String) {
    fill(ctx,CGRect(x:x,y:60,width:324,height:325),.white,radius:14)
    text(label,at:CGPoint(x:x+18,y:76),size:14,weight:.semibold,color:ink)
    draw(icon,in:ctx,x:x+107,y:112,size:110,color:black)
    for (row,size) in [CGFloat(18),CGFloat(16)].enumerated() {
        let y:CGFloat=272+CGFloat(row*48)
        text("\(Int(size)) pt",at:CGPoint(x:x+22,y:y+9),size:11,color:muted)
        fill(ctx,CGRect(x:x+84,y:y,width:88,height:32),NSColor(calibratedWhite:0.93,alpha:1),radius:6)
        fill(ctx,CGRect(x:x+188,y:y,width:88,height:32),dark,radius:6)
        draw(icon,in:ctx,x:x+84+(88-size)/2,y:y+(32-size)/2,size:size,color:black)
        draw(icon,in:ctx,x:x+188+(88-size)/2,y:y+(32-size)/2,size:size,color:white)
    }
}
try png("previews/C-size-correction.png",width:700,height:405) { ctx in
    fill(ctx,CGRect(x:0,y:0,width:700,height:405),paper)
    text("C · All three sockets now match",at:CGPoint(x:20,y:18),size:18,weight:.semibold,color:ink)
    card(original,ctx,x:20,label:"Previous")
    card(revised,ctx,x:356,label:"Revised")
}
print("Exported C with three identical sockets and a cable joint adjusted to preserve the socket opening.")

