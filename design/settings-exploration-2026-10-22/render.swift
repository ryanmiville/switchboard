import AppKit

// Isolated, static design study. No production sources or personal configuration are loaded.
// Run from the repository root: swift design/settings-exploration-2026-10-22/render.swift

let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

struct Concept {
    let slug: String
    let name: String
    let axis: String
    let benefit: String
    let cost: String
    var dark = false
}

let concepts = [
    Concept(slug: "01-familiar-sidebar", name: "Familiar sidebar", axis: "Persistent category navigation",
            benefit: "A quiet, familiar home for every setting.", cost: "The sidebar uses space even with only a few categories."),
    Concept(slug: "02-toolbar-panes", name: "Toolbar panes", axis: "Traditional Mac preferences",
            benefit: "The most conventional, compact native settings structure.", cost: "Moving between categories hides the other panes."),
    Concept(slug: "03-table-and-inspector", name: "Table + inspector", axis: "Scan many rules, edit one",
            benefit: "Fast comparison and precise editing as the rule list grows.", cost: "A wider window and a more technical feel."),
    Concept(slug: "04-sentence-rules", name: "Sentence rules", axis: "Readable, inline rule construction",
            benefit: "Rules read like a sentence and stay editable in place.", cost: "Long patterns and profile names need more space."),
    Concept(slug: "05-browser-first", name: "Browser first", axis: "Organize around destinations",
            benefit: "Makes the browser and profile relationship unmistakable.", cost: "Filtered views need visible global rule numbers to preserve priority."),
    Concept(slug: "06-focused-cards", name: "Focused cards", axis: "One expanded rule at a time",
            benefit: "Comfortable editing without a permanent inspector.", cost: "Expanding a rule reduces the number visible at once."),
    Concept(slug: "07-compact-utility", name: "Compact utility", axis: "Small window, direct controls",
            benefit: "A small, efficient companion to the menu bar.", cost: "Less room for explanations or large rule collections.", dark: true),
    Concept(slug: "08-routing-workbench", name: "Routing workbench", axis: "Keep testing next to rules",
            benefit: "A persistent URL test explains the first matching rule.", cost: "The testing area takes space during simple edits.", dark: true),
    Concept(slug: "09-essentials", name: "Essentials", axis: "Daily settings first, details one click away",
            benefit: "A calm landing page for defaults, login, and the shortcut.", cost: "Rule editing lives a level deeper."),
    Concept(slug: "10-sheet-editor", name: "Sheet editor", axis: "Progressive disclosure with an edit sheet",
            benefit: "A clean list with a focused form for deliberate edits.", cost: "A sheet temporarily interrupts comparison between rules."),
]

struct DemoRule {
    let pattern: String
    let condition: String
    let browser: String
    let profile: String
}

let demoRules = [
    DemoRule(pattern: "gitlab.com", condition: "Domain", browser: "Chrome", profile: "Horizon 3"),
    DemoRule(pattern: "atlassian.net", condition: "Domain", browser: "Chrome", profile: "Horizon 3"),
    DemoRule(pattern: "youtube.com", condition: "Domain", browser: "Helium", profile: "Ryan"),
    DemoRule(pattern: "docs.google.com", condition: "Domain", browser: "Chrome", profile: "Horizon 3"),
    DemoRule(pattern: "/personal/", condition: "Contains", browser: "Helium", profile: "Ryan"),
]

func rgb(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: alpha)
}

final class StudyView: NSView {
    override var isFlipped: Bool { true }
    let concept: Int
    var dark: Bool { concepts[concept].dark }
    var ink: NSColor { dark ? rgb(0xEEEEF1) : rgb(0x24262A) }
    var secondary: NSColor { dark ? rgb(0xAAAAB2) : rgb(0x71747B) }
    var faint: NSColor { dark ? rgb(0x797C85) : rgb(0x96999F) }
    var surface: NSColor { dark ? rgb(0x27282C) : rgb(0xFFFFFF) }
    var base: NSColor { dark ? rgb(0x202125) : rgb(0xF7F7F9) }
    var sidebarFill: NSColor { dark ? rgb(0x2C2D32) : rgb(0xEEEFF2) }
    var line: NSColor { dark ? rgb(0xFFFFFF, 0.10) : rgb(0x161B26, 0.10) }
    var accent: NSColor { dark ? rgb(0x659FFF) : rgb(0x087AFF) }
    var selection: NSColor { dark ? rgb(0x325484) : rgb(0xDCEAFF) }
    let green = rgb(0x2A9951)
    var ox: CGFloat = 0
    var oy: CGFloat = 0
    var win = NSRect.zero
    var warnings: [String] = []

    init(_ index: Int) {
        concept = index
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 840))
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    required init?(coder: NSCoder) { fatalError() }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x + ox, y: y + oy, width: w, height: h)
    }
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
             _ fill: NSColor, radius: CGFloat = 8, border: NSColor? = nil) {
        let p = NSBezierPath(roundedRect: rect(x, y, w, h), xRadius: radius, yRadius: radius)
        fill.setFill(); p.fill()
        if let border { border.setStroke(); p.lineWidth = 0.75; p.stroke() }
    }
    func ruleLine(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        line.setFill(); rect(x, y, w, 0.75).fill()
    }
    func vertical(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat) {
        line.setFill(); rect(x, y, 0.75, h).fill()
    }

    @discardableResult
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
              size: CGFloat = 13, weight: NSFont.Weight = .regular,
              color: NSColor? = nil, align: NSTextAlignment = .left,
              lines: Int = 1, mono: Bool = false) -> CGFloat {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                        : NSFont.systemFont(ofSize: size, weight: weight)
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        style.lineSpacing = lines > 1 ? 3 : 0
        let height = ceil(size * 1.42) * CGFloat(lines) + 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color ?? ink, .paragraphStyle: style,
        ]
        (s as NSString).draw(in: rect(x, y, w, height), withAttributes: attributes)
        return height
    }
    func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 16,
                _ color: NSColor? = nil, weight: NSFont.Weight = .regular) {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else {
            warnings.append("Missing symbol: \(name)"); return
        }
        let image = NSImage(size: NSSize(width: size + 3, height: size + 3), flipped: true) { r in
            source.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            (color ?? self.secondary).setFill(); r.fill(using: .sourceIn); return true
        }
        image.draw(in: rect(x, y, size + 3, size + 3), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
    }
    func icon(_ browser: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 25) {
        let path = browser == "Chrome" ? "/Applications/Google Chrome.app/Contents/Resources/app.icns"
                                      : "/Applications/Helium.app/Contents/Resources/app.icns"
        if let image = NSImage(contentsOfFile: path) {
            image.draw(in: rect(x, y, size, size), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        } else { symbol("globe", x, y, size - 3, accent) }
    }
    func button(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                primary: Bool = false, small: Bool = false) {
        let h: CGFloat = small ? 25 : 30
        box(x, y, w, h, primary ? (dark ? rgb(0x267DF3) : rgb(0x087AFF)) : surface,
            radius: 6, border: primary ? nil : line)
        text(title, x + 6, y + (small ? 4 : 6), w - 12, size: small ? 12 : 13,
             weight: primary ? .medium : .regular, color: primary ? .white : ink, align: .center)
    }
    func popup(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
               browser: String? = nil, h: CGFloat = 30) {
        box(x, y, w, h, dark ? rgb(0x3A3B41) : rgb(0xFDFDFE), radius: 6, border: line)
        var inset: CGFloat = 10
        if let browser { icon(browser, x + 7, y + (h - 20)/2, 20); inset = 32 }
        text(title, x + inset, y + (h - 18)/2, w - inset - 26, size: 13)
        symbol("chevron.up.chevron.down", x + w - 21, y + (h - 13)/2, 10, secondary, weight: .semibold)
    }
    func field(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
               placeholder: Bool = false, mono: Bool = false) {
        box(x, y, w, 31, dark ? rgb(0x222327) : .white, radius: 6, border: line)
        text(value, x + 10, y + 6, w - 20, size: 13, color: placeholder ? faint : ink, mono: mono)
    }
    func toggle(_ x: CGFloat, _ y: CGFloat, on: Bool = true) {
        box(x, y, 32, 19, on ? rgb(0x087AFF) : faint, radius: 9.5)
        let r = rect(x + (on ? 15 : 2), y + 2, 15, 15)
        NSColor.white.setFill(); NSBezierPath(ovalIn: r).fill()
    }
    func keycap(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 111) {
        box(x, y, w, 29, dark ? rgb(0x35363C) : rgb(0xF7F8FA), radius: 6, border: line)
        text(title, x + 6, y + 6, w - 12, size: 12, weight: .medium, align: .center)
    }
    func pill(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
              color: NSColor? = nil) {
        let c = color ?? accent
        box(x, y, w, 23, c.withAlphaComponent(dark ? 0.16 : 0.08), radius: 5)
        text(title, x + 5, y + 4, w - 10, size: 11, weight: .medium, color: c, align: .center)
    }
    func header(_ title: String, _ subtitle: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        text(title, x, y, w, size: 24, weight: .bold)
        text(subtitle, x, y + 36, w, size: 13, color: secondary)
    }
    func saveStatus(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 170) {
        symbol("checkmark.circle.fill", x, y, 12, dark ? rgb(0x75C991) : green)
        text("All changes saved", x + 20, y - 1, w - 20, size: 11, color: secondary)
    }

    func window(_ width: CGFloat = 1080, _ height: CGFloat = 724, title: String,
                toolbarHeight: CGFloat = 54) {
        ox = (1200 - width) / 2; oy = (840 - height) / 2
        win = NSRect(x: 0, y: 0, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = rgb(0x18202C, dark ? 0.45 : 0.20)
        shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.shadowBlurRadius = 28; shadow.set()
        box(0, 0, width, height, base, radius: 12)
        NSGraphicsContext.restoreGraphicsState()
        NSBezierPath(roundedRect: rect(0, 0, width, height), xRadius: 12, yRadius: 12).addClip()
        box(0, 0, width, toolbarHeight, dark ? rgb(0x2B2C30) : rgb(0xF0F1F3), radius: 0)
        ruleLine(0, toolbarHeight, width)
        for (i, c) in [rgb(0xFF5F57), dark ? rgb(0x54555A) : rgb(0xD5D6D9), dark ? rgb(0x54555A) : rgb(0xD5D6D9)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: rect(20 + CGFloat(i) * 20, 21, 12, 12)).fill()
        }
        text(title, 108, 19, width - 216, size: 13, weight: .semibold, align: .center)
    }

    func sidebar(active: Int, width: CGFloat = 200, start: CGFloat = 54) {
        box(0, start, width, win.height - start, sidebarFill, radius: 0)
        vertical(width, start, win.height - start)
        text("SWITCHBOARD", 23, start + 24, width - 40, size: 10, weight: .semibold, color: faint)
        let items = [("General", "gearshape"), ("Routing Rules", "arrow.triangle.branch"),
                     ("Browsers & Profiles", "globe"), ("Quick Switch", "keyboard")]
        for (i, item) in items.enumerated() {
            let y = start + 51 + CGFloat(i) * 38
            if active == i { box(12, y - 4, width - 24, 33, selection, radius: 6) }
            symbol(item.1, 24, y + 3, 15, active == i ? accent : secondary)
            text(item.0, 50, y + 3, width - 63, size: 12, weight: active == i ? .semibold : .regular)
        }
    }
    func paneToolbar(active: Int = 1) {
        let items = [("General", "gearshape"), ("Routing", "arrow.triangle.branch"),
                     ("Browsers", "globe"), ("Quick Switch", "keyboard")]
        let total: CGFloat = 360
        let start = (win.width - total) / 2
        for (i, item) in items.enumerated() {
            let x = start + CGFloat(i) * 90
            if active == i { box(x + 3, 35, 84, 63, selection, radius: 8) }
            symbol(item.1, x + 34, 43, 22, active == i ? accent : secondary)
            text(item.0, x, 77, 90, size: 11, weight: active == i ? .semibold : .regular,
                 color: active == i ? accent : secondary, align: .center)
        }
    }
    func segments(_ labels: [String], active: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
        box(x, y, w, 29, dark ? rgb(0x35363A) : rgb(0xE8E9ED), radius: 7)
        let itemW = w / CGFloat(labels.count)
        for (i, label) in labels.enumerated() {
            if i == active { box(x + CGFloat(i)*itemW + 2, y + 2, itemW - 4, 25,
                                 dark ? rgb(0x5A5C63) : .white, radius: 5, border: line) }
            text(label, x + CGFloat(i)*itemW + 2, y + 6, itemW - 4, size: 12,
                 weight: i == active ? .medium : .regular, color: i == active ? ink : secondary, align: .center)
        }
    }
    func defaultDestination(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, compact: Bool = false) {
        box(x, y, w, compact ? 64 : 78, surface, radius: 9, border: line)
        icon("Helium", x + 16, y + (compact ? 18 : 23), 30)
        text("Default destination", x + 59, y + 13, w - 295, size: 12, weight: .semibold)
        text("For links that don’t match a rule", x + 59, y + 34, w - 295, size: 11, color: secondary)
        popup("Helium · Ryan", x + w - 223, y + (compact ? 17 : 24), 206, browser: "Helium")
    }
    func tester(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, result: Bool = false) {
        text("Test a URL", x, y, 160, size: 12, weight: .semibold)
        field(result ? "https://gitlab.com/horizon3/project" : "https://example.com", x, y + 25, w,
              placeholder: !result)
        if result {
            symbol("arrow.turn.down.right", x + 2, y + 71, 13, accent)
            text("Rule 1  →  Chrome · Horizon 3", x + 25, y + 70, w - 25, size: 12, color: secondary)
        }
    }
    func listRow(_ rule: DemoRule, number: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                 selected: Bool = false, detail: Bool = true) {
        if selected { box(x, y, w, 61, selection, radius: 7) }
        text(String(number), x + 12, y + 23, 22, size: 11, weight: .medium, color: faint)
        text(rule.pattern, x + 44, y + 11, w * 0.45 - 38, size: 13, weight: .medium)
        if detail { text(rule.condition, x + 44, y + 33, 130, size: 11, color: secondary) }
        icon(rule.browser, x + w - 216, y + 19, 23)
        text(rule.profile, x + w - 184, y + 12, 152, size: 12, weight: .medium)
        text(rule.browser, x + w - 184, y + 32, 152, size: 11, color: secondary)
        symbol("chevron.right", x + w - 20, y + 24, 9, faint)
    }

    func table(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, rows: Int = 5, selected: Int? = nil,
               rowHeight: CGFloat = 48, narrow: Bool = false) {
        let h = 34 + CGFloat(rows) * rowHeight
        box(x, y, w, h, surface, radius: 8, border: line)
        let patternX = x + 45
        let matchX = x + w * (narrow ? 0.53 : 0.47)
        let destX = x + w * (narrow ? 0.72 : 0.65)
        text("#", x + 15, y + 10, 24, size: 10, weight: .medium, color: secondary)
        text("URL pattern", patternX, y + 10, w * 0.38, size: 10, weight: .medium, color: secondary)
        text("Match", matchX, y + 10, 90, size: 10, weight: .medium, color: secondary)
        text("Destination", destX, y + 10, w * 0.3, size: 10, weight: .medium, color: secondary)
        ruleLine(x, y + 34, w)
        for i in 0..<rows {
            let r = demoRules[i % demoRules.count]
            let ry = y + 34 + CGFloat(i) * rowHeight
            if selected == i { box(x + 3, ry + 3, w - 6, rowHeight - 6, selection, radius: 5) }
            else if i % 2 == 1 { box(x + 1, ry, w - 2, rowHeight, dark ? rgb(0xFFFFFF,0.025) : rgb(0xF7F8FA), radius: 0) }
            text("\(i + 1)", x + 15, ry + (rowHeight - 16)/2, 24, size: 11, color: faint)
            text(r.pattern, patternX, ry + (rowHeight - 18)/2, matchX - patternX - 18, size: 12, weight: .medium)
            text(r.condition, matchX, ry + (rowHeight - 18)/2, destX - matchX - 14, size: 11, color: secondary)
            icon(r.browser, destX, ry + (rowHeight - 23)/2, 23)
            text(narrow ? r.profile : "\(r.browser) · \(r.profile)", destX + 31,
                 ry + (rowHeight - 18)/2, x + w - destX - 42, size: 12)
        }
    }

    func inspector(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, showTitle: Bool = true) {
        var yy = y
        if showTitle {
            text("Rule 1", x, yy, w, size: 11, weight: .medium, color: secondary)
            text("gitlab.com", x, yy + 23, w, size: 21, weight: .semibold)
            yy += 77
        }
        text("MATCH", x, yy, w, size: 10, weight: .semibold, color: secondary)
        text("Match type", x, yy + 29, w, size: 12)
        popup("Domain", x, yy + 51, w)
        text("Domain", x, yy + 100, w, size: 12)
        field("gitlab.com", x, yy + 122, w)
        text("Includes subdomains, such as docs.gitlab.com.", x, yy + 164, w, size: 11, color: secondary, lines: 2)
        ruleLine(x, yy + 213, w)
        text("OPEN IN", x, yy + 236, w, size: 10, weight: .semibold, color: secondary)
        popup("Google Chrome", x, yy + 265, w, browser: "Chrome")
        popup("Horizon 3", x, yy + 306, w)
        text("Profile 2", x + 2, yy + 346, w, size: 10, color: faint)
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSGradient(starting: dark ? rgb(0x3B414B) : rgb(0xE9EEF4),
                                    ending: dark ? rgb(0x282D35) : rgb(0xD5DEE9))!
        background.draw(in: bounds, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        switch concept {
        case 0: familiarSidebar()
        case 1: toolbarPanes()
        case 2: tableInspector()
        case 3: sentences()
        case 4: browserFirst()
        case 5: focusedCards()
        case 6: compactUtility()
        case 7: workbench()
        case 8: essentials()
        default: sheetEditor()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func familiarSidebar() {
        window(title: "Routing Rules")
        sidebar(active: 1)
        let x: CGFloat = 232, w: CGFloat = 814
        header("Routing Rules", "Choose where your links open. Rules are checked from top to bottom.", x, 83, w)
        defaultDestination(x, 158, w, compact: true)
        text("Rules", x, 250, 200, size: 14, weight: .semibold)
        button("+  Add Rule", x + w - 105, 243, 105, primary: true)
        box(x, 288, w, 305, surface, radius: 9, border: line)
        for i in 0..<5 {
            listRow(demoRules[i], number: i + 1, x + 3, 288 + CGFloat(i)*61, w - 6)
            if i != 4 { ruleLine(x + 46, 349 + CGFloat(i)*61, w - 62) }
        }
        tester(x, 617, w)
        saveStatus(x, 690)
    }
    func toolbarPanes() {
        window(960, 690, title: "Routing", toolbarHeight: 112)
        paneToolbar()
        let x: CGFloat = 48, w: CGFloat = 864
        defaultDestination(x, 145, w, compact: true)
        text("Routing rules", x, 241, w, size: 15, weight: .semibold)
        text("First match wins. Drag rules to change their priority.", x, 266, w, size: 12, color: secondary)
        table(x, 302, w, selected: 0, rowHeight: 42)
        button("+", x, 554, 31, small: true)
        button("−", x + 37, 554, 31, small: true)
        button("Edit Rule…", x + w - 112, 552, 112)
        ruleLine(x, 604, w)
        text("Test a URL", x, 628, 90, size: 12, weight: .medium)
        field("https://example.com", x + 100, 620, w - 100, placeholder: true)
    }
    func tableInspector() {
        window(1100, 724, title: "Routing Rules")
        let x: CGFloat = 26, w: CGFloat = 704
        header("Routing Rules", "The first matching rule determines the destination.", x, 81, w)
        button("+  Add Rule", 614, 83, 116, primary: true)
        table(x, 164, w, selected: 0, rowHeight: 50, narrow: true)
        symbol("arrow.up.arrow.down", x + 3, 466, 13, secondary)
        text("Drag rows to reorder", x + 25, 466, 250, size: 11, color: secondary)
        defaultDestination(x, 513, w, compact: true)
        tester(x, 603, w, result: true)
        vertical(756, 54, 670)
        box(757, 55, 343, 669, dark ? sidebarFill : rgb(0xF0F1F4), radius: 0)
        inspector(783, 85, 290)
        ruleLine(783, 613, 290)
        symbol("trash", 783, 642, 14, secondary)
        text("Delete Rule", 807, 642, 200, size: 12, color: secondary)
        saveStatus(783, 686)
    }
    func sentences() {
        window(1040, 710, title: "Routing")
        segments(["General", "Routing", "Quick Switch"], active: 1, 342, 68, 356)
        header("Send every link to the right place.", "Build rules in plain language. The first match wins.", 48, 126, 944)
        button("+  Add Rule", 872, 137, 120, primary: true)
        for i in 0..<4 {
            let r = demoRules[i]
            let yy: CGFloat = 213 + CGFloat(i)*83
            box(48, yy, 944, 69, surface, radius: 8, border: line)
            text("\(i + 1)", 63, yy + 26, 25, size: 11, color: faint)
            text("If URL", 100, yy + 26, 50, size: 12, color: secondary)
            popup(r.condition.lowercased() == "domain" ? "domain is" : "contains", 150, yy + 20, 108)
            field(r.pattern, 270, yy + 20, 204)
            text("open in", 494, yy + 26, 61, size: 12, color: secondary)
            popup(r.profile, 554, yy + 20, 153)
            text("in", 723, yy + 26, 21, size: 12, color: secondary)
            popup(r.browser, 747, yy + 20, 172, browser: r.browser)
            symbol("ellipsis", 946, yy + 25, 14, secondary)
        }
        icon("Helium", 61, 576, 23)
        text("Everything else", 100, 578, 200, size: 12, weight: .medium)
        text("opens in", 490, 578, 64, size: 12, color: secondary)
        popup("Ryan", 554, 570, 153)
        text("in", 723, 578, 21, size: 12, color: secondary)
        popup("Helium", 747, 570, 172, browser: "Helium")
        ruleLine(48, 632, 944)
        text("Test a URL", 48, 659, 90, size: 12, weight: .medium)
        field("https://example.com", 148, 651, 844, placeholder: true)
    }
    func browserFirst() {
        window(title: "Browsers & Profiles")
        let side: CGFloat = 262
        box(0, 54, side, 670, sidebarFill, radius: 0); vertical(side, 54, 670)
        text("DESTINATIONS", 24, 84, 210, size: 10, weight: .semibold, color: faint)
        box(12, 122, 238, 70, selection, radius: 8)
        icon("Chrome", 27, 141, 32)
        text("Horizon 3", 72, 138, 160, size: 14, weight: .semibold)
        text("Google Chrome", 72, 160, 160, size: 11, color: secondary)
        icon("Helium", 27, 223, 32)
        text("Ryan", 72, 220, 160, size: 14, weight: .medium)
        text("Helium", 72, 242, 160, size: 11, color: secondary)
        pill("Default", 162, 223, 67)
        ruleLine(24, 287, 214)
        symbol("list.number", 27, 312, 15, secondary)
        text("All Rules", 56, 313, 170, size: 12)
        symbol("gearshape", 27, 354, 15, secondary)
        text("General", 56, 355, 170, size: 12)
        symbol("keyboard", 27, 396, 15, secondary)
        text("Quick Switch", 56, 397, 170, size: 12)
        let x: CGFloat = 298, w: CGFloat = 746
        icon("Chrome", x, 88, 49)
        text("Horizon 3", x + 65, 87, w - 65, size: 25, weight: .bold)
        text("Google Chrome · Profile 2", x + 65, 125, w - 65, size: 12, color: secondary)
        text("Links that open here", x, 194, 480, size: 15, weight: .semibold)
        button("+  Add Rule", x + w - 113, 187, 113, primary: true)
        box(x, 238, w, 230, surface, radius: 9, border: line)
        for (position, index) in [0,1,3].enumerated() {
            let yy = 238 + CGFloat(position) * 76
            text("\(index + 1)", x + 18, yy + 27, 25, size: 11, color: faint)
            text(demoRules[index].pattern, x + 55, yy + 18, w - 110, size: 14, weight: .medium)
            text("Domain and subdomains", x + 55, yy + 43, w - 110, size: 11, color: secondary)
            symbol("chevron.right", x + w - 27, yy + 31, 10, faint)
            if position < 2 { ruleLine(x + 55, yy + 76, w - 72) }
        }
        symbol("info.circle", x, 491, 13, secondary)
        text("Numbers show global priority. Reorder from All Rules.", x + 23, 491, w - 23, size: 12, color: secondary)
        box(x, 548, w, 104, surface, radius: 9, border: line)
        symbol("star.fill", x + 18, 571, 15, rgb(0xD89A1A))
        text("Quick Switch favorite", x + 47, 569, 400, size: 13, weight: .medium)
        text("Appears at the top of the profile picker.", x + 47, 596, 450, size: 12, color: secondary)
        toggle(x + w - 50, 574)
        saveStatus(x, 687)
    }
    func focusedCards() {
        window(1010, 740, title: "Routing Rules")
        let x: CGFloat = 45, w: CGFloat = 920
        text("Routing Rules", x, 82, w, size: 25, weight: .bold)
        text("First match wins. Expand a rule to make changes.", x, 122, w, size: 13, color: secondary)
        button("+  Add Rule", x + w - 117, 88, 117, primary: true)
        box(x, 171, w, 260, surface, radius: 10, border: accent.withAlphaComponent(0.42))
        pill("1", x + 18, 190, 27)
        text("gitlab.com", x + 59, 192, 400, size: 16, weight: .semibold)
        symbol("chevron.up", x + w - 35, 196, 11, secondary)
        ruleLine(x + 18, 232, w - 36)
        text("When the URL", x + 24, 258, 130, size: 12, weight: .medium)
        popup("Domain", x + 158, 250, 144)
        field("gitlab.com", x + 316, 250, w - 340)
        text("Includes matching subdomains.", x + 316, 292, w - 340, size: 11, color: secondary)
        text("Open in", x + 24, 345, 130, size: 12, weight: .medium)
        popup("Google Chrome", x + 158, 337, 282, browser: "Chrome")
        popup("Horizon 3", x + 454, 337, w - 478)
        text("Browser", x + 160, 381, 250, size: 10, color: faint)
        text("Profile", x + 456, 381, 250, size: 10, color: faint)
        for i in 1..<3 {
            let yy = 445 + CGFloat(i-1)*71
            box(x, yy, w, 58, surface, radius: 8, border: line)
            text("\(i+1)", x + 23, yy + 20, 25, size: 11, color: faint)
            text(demoRules[i].pattern, x + 60, yy + 18, 390, size: 13, weight: .medium)
            icon(demoRules[i].browser, x + 560, yy + 17, 24)
            text("\(demoRules[i].browser) · \(demoRules[i].profile)", x + 595, yy + 19, 275, size: 12, color: secondary)
            symbol("chevron.down", x + w - 35, yy + 23, 10, faint)
        }
        defaultDestination(x, 602, w, compact: true)
        text("General", x, 697, 70, size: 12, color: accent)
        text("Quick Switch", x + 88, 697, 110, size: 12, color: accent)
        text("Test a URL…", x + w - 104, 697, 104, size: 12, color: accent, align: .right)
    }
    func compactUtility() {
        window(740, 630, title: "Routing Rules")
        segments(["General", "Rules", "Quick Switch"], active: 1, 153, 77, 434)
        text("Routing Rules", 30, 134, 400, size: 20, weight: .semibold)
        button("+  Add Rule", 590, 132, 120, primary: true)
        text("First match wins.", 30, 168, 500, size: 12, color: secondary)
        box(30, 204, 680, 246, surface, radius: 8, border: line)
        for i in 0..<4 {
            let yy: CGFloat = 205 + CGFloat(i)*61
            listRow(demoRules[i], number: i + 1, 31, yy, 678)
            if i < 3 { ruleLine(75, yy + 61, 617) }
        }
        text("Default", 32, 484, 160, size: 12, weight: .medium)
        popup("Helium · Ryan", 423, 476, 287, browser: "Helium")
        ruleLine(30, 531, 680)
        symbol("magnifyingglass", 40, 563, 14, secondary)
        field("Test an HTTP or HTTPS URL", 67, 553, 643, placeholder: true)
        saveStatus(30, 602)
    }
    func workbench() {
        window(1100, 740, title: "Routing Rules")
        text("Routing Rules", 28, 82, 500, size: 24, weight: .bold)
        text("First matching rule wins", 28, 120, 500, size: 12, color: secondary)
        button("+  Add Rule", 950, 84, 122, primary: true)
        table(28, 163, 1044, selected: 0, rowHeight: 43)
        text("Drag rules to reorder", 31, 429, 300, size: 11, color: secondary)
        text("Default: Helium · Ryan", 772, 429, 300, size: 12, color: secondary, align: .right)
        ruleLine(0, 472, 1100)
        box(0, 473, 1100, 267, rgb(0x26282E), radius: 0)
        text("URL Test", 28, 496, 300, size: 16, weight: .semibold)
        pill("Preview only", 956, 495, 116, color: rgb(0xA9ABB4))
        field("https://gitlab.com/horizon3/project", 28, 532, 1044, mono: true)
        box(28, 586, 1044, 98, rgb(0x303640), radius: 9, border: rgb(0x659FFF,0.3))
        symbol("checkmark.circle.fill", 46, 608, 17, rgb(0x75C991))
        text("Rule 1 matches", 76, 603, 390, size: 14, weight: .semibold)
        text("Domain gitlab.com", 76, 631, 400, size: 12, color: secondary)
        symbol("arrow.right", 541, 623, 17, secondary)
        icon("Chrome", 590, 609, 43)
        text("Horizon 3", 647, 604, 350, size: 15, weight: .semibold)
        text("Google Chrome · Profile 2", 647, 632, 360, size: 12, color: secondary)
        text("Later rules are skipped after the first match. Testing doesn’t open the link.", 30, 704, 800, size: 11, color: secondary)
    }
    func essentials() {
        window(1000, 724, title: "General")
        sidebar(active: 0, width: 195)
        let x: CGFloat = 231, w: CGFloat = 733
        header("General", "The essentials for opening links and switching profiles.", x, 87, w)
        text("OPENING LINKS", x + 1, 167, w, size: 10, weight: .semibold, color: secondary)
        defaultDestination(x, 191, w)
        box(x, 284, w, 67, surface, radius: 9, border: line)
        symbol("arrow.triangle.branch", x + 18, 306, 19, accent)
        text("Routing rules", x + 56, 298, 330, size: 13, weight: .medium)
        text("5 rules, checked in order", x + 56, 320, 330, size: 11, color: secondary)
        button("Manage Rules…", x + w - 147, 302, 128)
        text("QUICK SWITCH", x + 1, 383, w, size: 10, weight: .semibold, color: secondary)
        box(x, 407, w, 121, surface, radius: 9, border: line)
        symbol("keyboard", x + 18, 427, 19, accent)
        text("Open the current tab in another profile", x + 56, 427, w - 220, size: 13)
        keycap("⌃  ⌥  Space", x + w - 132, 421)
        ruleLine(x + 56, 462, w - 74)
        icon("Helium", x + 58, 481, 22)
        text("Ryan", x + 89, 484, 160, size: 12)
        icon("Chrome", x + 241, 481, 22)
        text("Horizon 3", x + 272, 484, 180, size: 12)
        text("Edit Favorites…", x + w - 129, 484, 111, size: 12, color: accent, align: .right)
        text("STARTUP", x + 1, 561, w, size: 10, weight: .semibold, color: secondary)
        box(x, 585, w, 72, surface, radius: 9, border: line)
        text("Launch Switchboard at login", x + 18, 598, w - 80, size: 13, weight: .medium)
        text("Starts in the menu bar with Settings closed.", x + 18, 621, w - 80, size: 11, color: secondary)
        toggle(x + w - 51, 609)
        saveStatus(x, 690)
    }
    func sheetEditor() {
        window(1010, 740, title: "Routing", toolbarHeight: 112)
        paneToolbar()
        defaultDestination(40, 145, 930, compact: true)
        text("Routing Rules", 40, 247, 600, size: 16, weight: .semibold)
        button("+  Add Rule", 850, 239, 120, primary: true)
        table(40, 294, 930, selected: 0, rowHeight: 45)
        text("First matching rule wins.", 40, 590, 600, size: 12, color: secondary)
        tester(40, 632, 930)
        box(0, 112, 1010, 628, rgb(0x1E2530,0.18), radius: 0)
        // Attached sheet: form actions commit or cancel a draft rule, not global settings.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = rgb(0x000000,0.26)
        shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width:0,height:-10); shadow.set()
        box(247, 111, 516, 548, surface, radius: 10)
        NSGraphicsContext.restoreGraphicsState()
        text("Edit Rule", 275, 140, 460, size: 19, weight: .semibold)
        text("Choose which links match and where they open.", 275, 174, 460, size: 12, color: secondary)
        ruleLine(275, 210, 460)
        text("Match", 275, 239, 150, size: 12, weight: .medium)
        popup("Domain", 421, 230, 314)
        text("Domain", 275, 287, 150, size: 12, weight: .medium)
        field("gitlab.com", 421, 278, 314)
        text("Also matches subdomains of gitlab.com.", 421, 320, 314, size: 11, color: secondary)
        ruleLine(275, 363, 460)
        text("Browser", 275, 396, 150, size: 12, weight: .medium)
        popup("Google Chrome", 421, 387, 314, browser: "Chrome")
        text("Profile", 275, 445, 150, size: 12, weight: .medium)
        popup("Horizon 3", 421, 436, 314)
        text("Profile 2 in Google Chrome", 421, 477, 314, size: 11, color: secondary)
        box(275, 523, 460, 45, rgb(0x087AFF,0.06), radius: 6)
        symbol("info.circle", 288, 537, 13, accent)
        text("Rule 1 is checked before all other rules.", 311, 537, 410, size: 11, color: secondary)
        ruleLine(247, 593, 516)
        button("Cancel", 530, 612, 92)
        button("Done", 633, 612, 102, primary: true)
    }
}

var manifest: [[String: Any]] = []
for (index, concept) in concepts.enumerated() {
    let view = StudyView(index)
    let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.appearance = view.appearance
    window.displayIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1680,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let file = output.appendingPathComponent("screenshots/\(concept.slug).png")
    try rep.representation(using: .png, properties: [:])!.write(to: file)
    manifest.append(["number": index + 1, "slug": concept.slug, "name": concept.name,
                     "axis": concept.axis, "benefit": concept.benefit, "cost": concept.cost,
                     "dark": concept.dark, "file": "screenshots/\(concept.slug).png"])
    if !view.warnings.isEmpty { print("\(concept.slug): \(Set(view.warnings).sorted())") }
    print("Rendered \(file.lastPathComponent)")
}
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("concepts.json"))
