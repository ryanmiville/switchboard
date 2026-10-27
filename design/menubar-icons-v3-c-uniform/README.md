# C — matching sockets

Corrects the uneven socket sizes in the previous C preview. All three circular
sockets now use radius 1.1 and stroke width 1.05 on the 18-point canvas.
The lower-left socket shrinks to match the other two. Its cable endpoint moves
to the outer edge so the round cable cap does not fill the socket opening.
The panel, plug, other socket positions, and cable control points are preserved.

`previews/C-size-correction.png` compares the previous and revised versions,
including 18-point and 16-point light/dark samples. Transparent PNGs and SVG/PDF
masters are in the corresponding folders. No app assets are replaced.

Regenerate with `swift design/menubar-icons-v3-c-uniform/generate.swift`.
