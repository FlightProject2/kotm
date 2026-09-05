#!/usr/bin/env bash
# Re-vendors Terrain3D into addons/terrain_3d keeping only desktop binaries.
set -euo pipefail
VER=v1.0.2-stable
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="${KOTM_SCRATCH:-$ROOT/scratch}/terrain3d"; mkdir -p "$TMP"
curl -sSL -o "$TMP/t3d.zip" "https://github.com/TokisanGames/Terrain3D/releases/download/${VER}/Terrain3D_${VER}.zip"
rm -rf "$TMP/x" && unzip -oq "$TMP/t3d.zip" -d "$TMP/x"
rm -rf "$ROOT/addons/terrain_3d" && cp -r "$TMP/x/addons/terrain_3d" "$ROOT/addons/terrain_3d"
rm -f "$ROOT"/addons/terrain_3d/bin/libterrain.{android,ios,web}.*
echo "Vendored Terrain3D $VER; now trim [libraries] in addons/terrain_3d/terrain.gdextension to windows/linux/macos."
