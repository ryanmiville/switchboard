"""Build the local screenshot gallery, contact sheet, and download bundle."""

from pathlib import Path
import json
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
concepts = json.loads((ROOT / "concepts.json").read_text())
font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 21)
board = Image.new("RGB", (1600, 3000), (245, 246, 248))
draw = ImageDraw.Draw(board)
for index, concept in enumerate(concepts):
    x = index % 2 * 800
    y = index // 2 * 600
    with Image.open(ROOT / concept["file"]) as source:
        assert source.size == (2400, 1680)
        image = source.convert("RGB")
        image.thumbnail((784, 549), Image.Resampling.LANCZOS)
        board.paste(image, (x + 8, y + 7))
    draw.text((x + 29, y + 558), f"{index + 1:02d}  {concept['name']}", font=font, fill=(34, 40, 50))
board.save(ROOT / "overview.png")

short_names = ["Sidebar", "Toolbar", "Inspector", "Sentences", "Browsers", "Cards", "Compact", "Workbench", "Essentials", "Sheet"]
picker = "\n".join(
    f'<button class="proto-picker-item">{name}</button>' for name in short_names
)
template = (ROOT / "gallery-template.html").read_text()
gallery = template.replace("__CONCEPTS__", json.dumps(concepts)).replace("__PICKER__", picker)
(ROOT / "index.html").write_text(gallery)

with zipfile.ZipFile(ROOT / "switchboard-settings-10-mockups.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("index.html", gallery.replace(
        '<a href="switchboard-settings-10-mockups.zip" download>Download all 10</a>',
        '<a href="overview.png" target="_blank">Overview of all 10</a>',
    ))
    for name in ["overview.png", "concepts.json", "README.md"]:
        archive.write(ROOT / name, name)
    for concept in concepts:
        archive.write(ROOT / concept["file"], concept["file"])

assert len(concepts) == 10
assert len({c["name"] for c in concepts}) == 10
print("Packaged 10 screenshots, gallery, overview, and ZIP.")
