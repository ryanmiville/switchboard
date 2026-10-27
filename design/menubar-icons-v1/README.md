# Switchboard menu-bar icon explorations

Twenty preview designs based on the actual bundled app icon:
`Switchboard/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png`.
The shared motifs are its arched patch cable, plug ends, and jack sockets.

Every design is drawn on an 18 × 18 point grid using native vector geometry,
without gradients, shading, miniature lettering, or color-dependent details.
The images in `previews/board-1.png` through `board-4.png` show an enlarged
symbol and 18-point samples on light and dark backgrounds. The preview boards
are exported at 2x, so their small samples are 36 physical pixels tall.

Files:

- `svg/`: twenty black vector masters, each 18 × 18 with transparency.
- `pdf/`: matching one-page, 18 × 18 point vector template images.
- `png/`: transparent black and white PNGs at 1x, 2x, and 4x.
- `previews/`: numbered individual previews, four comparison boards, and an overview.
- `manifest.json`: design numbers, names, and filenames.
- `generate.swift`: exact geometry and native renderer used for all formats.

Regenerate with `swift design/menubar-icons-v1/generate.swift` from the repository root.
These are design candidates only; no icon is installed or selected in the app.
If selected for production, set the NSImage's logical size to 18 × 18 and
`isTemplate = true` so macOS controls its tint.
