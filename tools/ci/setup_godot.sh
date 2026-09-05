#!/usr/bin/env bash
# Downloads the pinned Godot editor binary (Linux x86_64) for headless checks.
set -euo pipefail
VER=4.6.3-stable
DIR="${KOTM_SCRATCH:-$(dirname "$0")/../../scratch}/godot"
BIN="$DIR/Godot_v${VER}_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  curl -sSL -o "$DIR/godot.zip" "https://github.com/godotengine/godot/releases/download/${VER}/Godot_v${VER}_linux.x86_64.zip"
  unzip -oq "$DIR/godot.zip" -d "$DIR"
  chmod +x "$BIN"
fi
echo "$BIN"
