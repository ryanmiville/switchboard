"""Check the actual built app's browser registration without registering it."""

import pathlib
import plistlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
with (root / "Switchboard/Switchboard.entitlements").open("rb") as source:
    assert plistlib.load(source).get("com.apple.security.app-sandbox") is False

for argument in sys.argv[1:]:
    app = pathlib.Path(argument)
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    schemes = {
        scheme
        for entry in info["CFBundleURLTypes"]
        for scheme in entry["CFBundleURLSchemes"]
    }
    assert {"http", "https"} <= schemes, "HTTP/HTTPS registration is missing"
    assert any(
        entry.get("LSHandlerRank") == "Default"
        and "public.html" in entry.get("LSItemContentTypes", [])
        for entry in info["CFBundleDocumentTypes"]
    ), "Default-browser document registration is missing"
    assert info["LSMinimumSystemVersion"] == "13.0"
    assert (app / "Contents/MacOS" / info["CFBundleExecutable"]).is_file()
    print(f"Bundle checks passed: {app.name} ({app.parent.name})")
