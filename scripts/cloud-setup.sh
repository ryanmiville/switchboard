#!/usr/bin/env bash
# Setup script for Switchboard in a Claude Code cloud environment (Ubuntu 24.04). Paste it into the
# environment's settings (cloud environment menu → Edit → Setup script). It runs as root at the
# start of each session, one directory above the repository.
#
# A session gets:
#   - Swift on PATH, matching the Swift that Xcode 26.4 ships, so `scripts/check` runs the Linux
#     subset (the Foundation-only targets). The macOS targets still need a Mac (CI's macOS job).
#   - ~/reference/switchboard-rs: the paused Rust rewrite at RUST_REF, the reference architecture
#     the swift-next branch ports.
#   - ~/reference/switchboard-current: the current Swift app at CURRENT_REF, for SwiftUI and AppKit
#     code to copy from.
# It works for every branch of the repository: main ignores the references.
#
# Overrides, for trying it outside an environment: SWIFT_PREFIX (default /opt/swift-$SWIFT_VERSION),
# PROFILE_SCRIPT (default /etc/profile.d/switchboard-dev.sh) and REFERENCE (default ~/reference).

set -uo pipefail

SWIFT_VERSION=6.3.3   # Xcode 26.4's Swift is 6.3; keep swift-format's output the same as CI's
RUST_REF=3b565e276e1bff623ad8b8e07ebb8628f536ba96      # rune-rewrite when it was paused
CURRENT_REF=43338ec784a52ff60ffe4a06aa1844ca026e5781   # main when swift-next started
REPOSITORY=https://github.com/ryanmiville/switchboard
SWIFT_PREFIX="${SWIFT_PREFIX:-/opt/swift-$SWIFT_VERSION}"
PROFILE_SCRIPT="${PROFILE_SCRIPT:-/etc/profile.d/switchboard-dev.sh}"
REFERENCE="${REFERENCE:-$HOME/reference}"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'setup: WARNING: %s\n' "$*" >&2; WARNINGS+=("$*"); }
WARNINGS=()
export DEBIAN_FRONTEND=noninteractive

# Swift's Linux runtime dependencies (swift.org's list for Ubuntu 24.04), plus python3 for
# scripts/lint.py and gnupg to verify the toolchain's signature.
packages=(binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev
          libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config python3
          tzdata unzip zlib1g-dev)
missing=()
for p in "${packages[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  log "apt: ${missing[*]}"
  { apt-get update -qq && apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null; } \
    || { echo "setup: apt-get install failed: ${missing[*]}" >&2; exit 1; }
fi

log "swift $SWIFT_VERSION"
if [ -x "$SWIFT_PREFIX/usr/bin/swift" ]; then
  echo "already installed in $SWIFT_PREFIX"
else
  url="https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04.tar.gz"
  work=$(mktemp -d)
  # Verified against swift.org's published keys before anything is unpacked.
  if curl -sSfL --proto '=https' "$url" -o "$work/swift.tar.gz" \
    && curl -sSfL --proto '=https' "$url.sig" -o "$work/swift.tar.gz.sig" \
    && curl -sSfL --proto '=https' --compressed https://www.swift.org/keys/all-keys.asc -o "$work/keys.asc" \
    && mkdir -m 700 "$work/gnupg" \
    && gpg --batch --quiet --no-autostart --homedir "$work/gnupg" --import "$work/keys.asc" 2>/dev/null \
    && gpg --batch --quiet --no-autostart --homedir "$work/gnupg" --verify "$work/swift.tar.gz.sig" "$work/swift.tar.gz" 2>/dev/null
  then
    mkdir -p "$SWIFT_PREFIX" && tar xzf "$work/swift.tar.gz" -C "$SWIFT_PREFIX" --strip-components=1 \
      || warn "could not unpack Swift into $SWIFT_PREFIX"
  else
    warn "could not download or verify Swift $SWIFT_VERSION from swift.org"
  fi
  rm -r -- "$work"
fi

mkdir -p "$(dirname "$PROFILE_SCRIPT")"
cat > "$PROFILE_SCRIPT" <<EOF
# Written by Switchboard's cloud setup script.
export PATH="$SWIFT_PREFIX/usr/bin:\$PATH"
EOF
if [ "$PROFILE_SCRIPT" = /etc/profile.d/switchboard-dev.sh ]; then
  # Non-login shells skip /etc/profile.d.
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    grep -qs 'profile.d/switchboard-dev.sh' "$rc" && continue
    [ -s "$rc" ] && [ -n "$(tail -c 1 "$rc")" ] && echo >> "$rc"
    echo '. /etc/profile.d/switchboard-dev.sh' >> "$rc"
  done
fi
export PATH="$SWIFT_PREFIX/usr/bin:$PATH"

if [ -f switchboard/Package.swift ]; then
  log "swift package resolve"
  (cd switchboard && swift package resolve >/dev/null 2>&1) || warn "swift package resolve failed"
fi

# A checkout of one commit, without history. Skipped when it is already there.
reference() {
  local name=$1 ref=$2 dir="$REFERENCE/$1"
  log "reference: $name at ${ref:0:7}"
  [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$ref" ] && { echo "already there"; return; }
  mkdir -p "$dir"
  { git -C "$dir" init -q && git -C "$dir" fetch -q --depth 1 "$REPOSITORY" "$ref" \
      && git -C "$dir" checkout -q --detach FETCH_HEAD; } || warn "could not fetch $name into $dir"
}
reference switchboard-rs "$RUST_REF"
reference switchboard-current "$CURRENT_REF"

log "check"
printf '%-14s %s\n' swift "$(swift --version 2>/dev/null | head -1 || echo missing)" \
  swift-format "$(swift format --version 2>/dev/null || echo missing)" \
  python3 "$(python3 --version 2>/dev/null || echo missing)"
if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n%d warning(s):\n' "${#WARNINGS[@]}"; printf '  - %s\n' "${WARNINGS[@]}"
fi
exit 0
