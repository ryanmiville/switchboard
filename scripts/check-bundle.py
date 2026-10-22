"""Check the actual built app's browser registration without registering it."""

import pathlib
import plistlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
with (root / "Switchboard/Switchboard.entitlements").open("rb") as source:
    entitlements = plistlib.load(source)
    assert entitlements.get("com.apple.security.app-sandbox") is False
    assert entitlements.get("com.apple.security.automation.apple-events") is True

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
    assert info.get("LSUIElement") is True, "Switchboard must stay out of the Dock"
    assert info.get("NSAppleEventsUsageDescription"), "Browser Automation usage description is missing"
    assert (app / "Contents/MacOS" / info["CFBundleExecutable"]).is_file()
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)], check=True
    )
    architectures = subprocess.check_output(
        ["lipo", "-archs", str(app / "Contents/MacOS" / info["CFBundleExecutable"])], text=True
    ).split()
    for architecture in architectures:
        signature = subprocess.run(
            ["codesign", "--display", "--verbose=4", "--architecture", architecture, str(app)],
            capture_output=True, text=True, check=True,
        ).stderr
        assert f"Identifier={info['CFBundleIdentifier']}\n" in signature, "Signing identity differs from bundle ID"
        flags = re.search(r"flags=0x([0-9a-f]+)", signature)
        assert flags and int(flags.group(1), 16) & 0x10000, "Hardened runtime is missing"
        embedded = plistlib.loads(subprocess.check_output(
            ["codesign", "--display", "--entitlements", "-", "--xml", "--architecture", architecture, str(app)],
            stderr=subprocess.DEVNULL,
        ))
        assert embedded.get("com.apple.security.app-sandbox") is not True, "App Sandbox must stay disabled"
        assert embedded.get("com.apple.security.automation.apple-events") is True, "Signed Automation entitlement is missing"
    print(f"Bundle checks passed: {app.name} ({app.parent.name})")
