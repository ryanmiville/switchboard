#!/usr/bin/env bash
# Setup script for the Switchboard rewrite (Swift → Rust on Rune) in a Claude Code cloud
# environment. Paste it into the environment's settings (cloud environment menu → Edit → Setup
# script). It runs at the start of each session, as root, one directory above the repository.
#
# A session gets:
#   - Rune's Linux build and run libraries, and software Vulkan, so headless `--snap` renders work
#   - Rust (stable, rustfmt, clippy) and cargo-nextest
#   - ~/reference/rune: Rune's docs, changelog and examples, for the agent to read
#   - switchboard-swift: the Swift app's CLI built from SWIFT_REF, the behaviour the rewrite must
#     match; its sources and tests are in ~/reference/switchboard-swift
#   - the repository's Cargo dependencies, once it has a Cargo.lock

set -uo pipefail

SWIFT_REF=8d4129a5dc435a0bf4dcf81e0981ae8d34808fdc   # the last all-Swift commit on main

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'setup: WARNING: %s\n' "$*" >&2; WARNINGS+=("$*"); }
WARNINGS=()
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
REF="$HOME/reference"
mkdir -p "$REF" "$HOME/.local/bin"

# Rune links libxkbcommon and libwayland-client; real windows need the XKB X11 library; wgpu
# renders on Mesa's software Vulkan (lavapipe) in a container with no GPU.
packages=(build-essential clang pkg-config libfontconfig1-dev libxkbcommon-dev libxkbcommon-x11-0
          libwayland-dev libvulkan1 mesa-vulkan-drivers)
missing=()
for p in "${packages[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  log "apt: ${missing[*]}"
  { apt-get update -qq && apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null; } \
    || { echo "setup: apt-get install failed: ${missing[*]}" >&2; exit 1; }
fi

log "rust"
command -v rustup >/dev/null || { echo "setup: rustup is missing from the image" >&2; exit 1; }
rustup component add rustfmt clippy >/dev/null 2>&1 || warn "rustup: no rustfmt/clippy"
if ! command -v cargo-nextest >/dev/null; then
  # Prebuilt, from the project's own release host; compiling it is the fallback.
  curl -sSfL --proto '=https' https://get.nexte.st/latest/linux | tar zxf - -C "$HOME/.cargo/bin" \
    || cargo install --locked cargo-nextest >/dev/null 2>&1 || warn "cargo-nextest: install failed"
fi

cat > /etc/profile.d/switchboard-dev.sh <<'EOF'
# Written by the environment's setup script.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json   # software Vulkan for --snap
EOF
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  grep -qs 'profile.d/switchboard-dev.sh' "$rc" && continue
  [ -s "$rc" ] && [ -n "$(tail -c 1 "$rc")" ] && echo >> "$rc"
  echo '. /etc/profile.d/switchboard-dev.sh' >> "$rc"
done

log "reference: Rune"
if [ -d "$REF/rune/.git" ]; then
  { git -C "$REF/rune" fetch -q --depth 1 origin dev && git -C "$REF/rune" reset -q --hard FETCH_HEAD; } \
    || warn "could not update ~/reference/rune"
else
  git clone -q --depth 1 --branch dev https://github.com/anomalyco/rune "$REF/rune" \
    || warn "could not clone Rune into ~/reference/rune"
fi

log "reference: the Swift Switchboard at ${SWIFT_REF:0:7}"
swift_dir="$REF/switchboard-swift"
if [ "$(git -C "$swift_dir" rev-parse HEAD 2>/dev/null)" != "$SWIFT_REF" ]; then
  mkdir -p "$swift_dir"
  { git -C "$swift_dir" init -q && git -C "$swift_dir" fetch -q --depth 1 \
      https://github.com/ryanmiville/switchboard "$SWIFT_REF" \
    && git -C "$swift_dir" checkout -q --detach FETCH_HEAD; } || warn "could not fetch the Swift version"
fi
# swiftly puts Swift on PATH for login shells only.
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"
if [ -x "$swift_dir/.build/debug/switchboard" ]; then
  :
elif command -v swift >/dev/null; then
  (cd "$swift_dir" && swift build --product switchboard >/dev/null 2>&1) \
    || warn "the Swift CLI didn't build (cd $swift_dir && swift build)"
else
  warn "no Swift toolchain in this image; switchboard-swift is unavailable"
fi
[ -x "$swift_dir/.build/debug/switchboard" ] \
  && ln -sfn "$swift_dir/.build/debug/switchboard" "$HOME/.local/bin/switchboard-swift"

if [ -f switchboard/Cargo.lock ]; then
  log "cargo fetch"
  (cd switchboard && cargo fetch --locked >/dev/null 2>&1) || warn "cargo fetch failed in switchboard"
fi

log "check"
printf '%-18s %s\n' rustc "$(rustc --version)" cargo-nextest "$(cargo nextest --version 2>/dev/null | head -1)" \
  switchboard-swift "$(command -v switchboard-swift || echo missing)"
[ -f /usr/share/vulkan/icd.d/lvp_icd.json ] || warn "no software Vulkan driver; headless renders will fail"
if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n%d warning(s):\n' "${#WARNINGS[@]}"; printf '  - %s\n' "${WARNINGS[@]}"
fi
exit 0
