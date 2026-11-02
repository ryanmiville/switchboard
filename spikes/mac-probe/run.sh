#!/usr/bin/env bash
# Answers, on a Mac, whether a windowless accessory Rune app receives http/https links the way
# Switchboard needs. It builds a throwaway "Switchboard Probe.app" in a temporary folder, sends
# it links with `open -a`, and prints what arrived. It never changes the default browser and
# removes the probe when done.
#
#   spikes/mac-probe/run.sh          run every probe and print a report to paste back
#   spikes/mac-probe/run.sh --keep   leave the app in ~/Applications to try it as the default browser
set -uo pipefail
cd "$(dirname "$0")"

[[ "$(uname)" == Darwin ]] || { echo "run.sh needs macOS" >&2; exit 2; }
command -v cargo >/dev/null || { echo "install Rust first: https://rustup.rs" >&2; exit 2; }

ID=com.ryanmiville.switchboard-probe
LOG="$HOME/Library/Logs/switchboard-probe.log"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KEEP=0; [[ "${1:-}" == --keep ]] && KEEP=1
if (( KEEP )); then DEST="$HOME/Applications"; else DEST="$(mktemp -d)"; fi
APP="$DEST/Switchboard Probe.app"

echo "==> building"
cargo build --release 2>&1 | tail -3 || exit 1

echo "==> bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp target/release/switchboard-probe "$APP/Contents/MacOS/switchboard-probe"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleName</key><string>Switchboard Probe</string>
  <key>CFBundleExecutable</key><string>switchboard-probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Web site URL</string>
    <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>HTML document</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.html</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad hoc signing failed"
"$LSREGISTER" -f "$APP"

quit_probe() {
  osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP/Contents/MacOS" >/dev/null || return 0; sleep 0.5; done
  pkill -f "$APP/Contents/MacOS"; echo "note: the probe ignored Quit and was killed"
}
wait_for() { for _ in $(seq 1 20); do grep -qF -- "$1" "$LOG" 2>/dev/null && return 0; sleep 0.5; done; return 1; }
check() { if wait_for "$2"; then echo "PASS  $1"; else echo "FAIL  $1 (expected log line containing: $2)"; fi; }

quit_probe; rm -f "$LOG"
COLD='https://example.com/cold?token=abc#frag'
ODD='https://EXAMPLE.com/Path/%7Euser?q=a%20b&x=%E2%9C%93'

echo "==> probes"
open -a "$APP" "$COLD"
check "a cold launch receives the link that launched it" "url $COLD"
sleep 1
open -a "$APP" 'http://example.org/warm'
check "a running app receives a second http link" "url http://example.org/warm"
open -a "$APP" "$ODD"
check "the link arrives exactly as sent (case, escapes)" "url $ODD"
open -a "$APP"
check "reopening the running app calls on_reopen" "reopen"
sleep 1
launches=$(grep -c ' launch ' "$LOG" 2>/dev/null || echo 0)
[[ "$launches" == 1 ]] && echo "PASS  all links went to one process" || echo "FAIL  $launches processes launched"
pid=$(pgrep -f "$APP/Contents/MacOS" | head -1)
echo "info  app type: $(lsappinfo info -only ApplicationType -app "$ID" 2>/dev/null || echo unknown) (UIElement means no Dock icon)"
echo "info  macOS $(sw_vers -productVersion), $(uname -m), pid ${pid:-none}"
quit_probe

echo; echo "==> raw log"; cat "$LOG" 2>/dev/null

if (( KEEP )); then
  cat <<NOTE

The probe stays in ~/Applications. To try real link delivery: System Settings → Desktop & Dock →
Default web browser → Switchboard Probe, click a link in another app, then read $LOG.
Switch the default back to Switchboard afterwards, then remove the probe:
  "$LSREGISTER" -u "$APP" && rm -rf "$APP"
NOTE
else
  "$LSREGISTER" -u "$APP"; rm -rf "$DEST"
fi
echo; echo "Paste everything from '==> probes' down back into the session."
