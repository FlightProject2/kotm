"""Reject missing character data and give each browser export immutable filenames."""
import hashlib
import json
from pathlib import Path
import re
import sys

out = Path(sys.argv[1])
revision = sys.argv[2]
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("Expected a full Git commit SHA")
pack = out / "index.pck"
payload = pack.read_bytes()
for required in (b"KOTM_Character.glb", b"asset_manifest.json", b"kotm_character_rig.gd",
                 b"KOTM_SnowTruck.glb", b"KOTM_Snowmobile.glb"):
    if required not in payload:
        raise SystemExit(f"Export is missing required runtime asset: {required!r}")
info = json.loads(Path("assets/characters/kotm/asset_manifest.json").read_text())
if len(info["animations"]) < 42:
    raise SystemExit("Character animation manifest is incomplete")
build = {"commit": revision, "pck_sha256": hashlib.sha256(payload).hexdigest(),
         "character_sha256": hashlib.sha256(Path("assets/characters/kotm/KOTM_Character.glb").read_bytes()).hexdigest(),
         "animation_count": len(info["animations"])}
(out / "build-info.json").write_text(json.dumps(build, indent=2) + "\n")
# Godot derives WASM/PCK names from executable; rewrite the shell and every
# generated index.* name together so cached assets from older builds cannot mix.
stem = "kotm-" + revision[:12]
html = (out / "index.html").read_text()
html = html.replace('"index"', json.dumps(stem)).replace("index.", stem + ".")
for path in list(out.glob("index.*")):
    if path.name != "index.html":
        path.rename(path.with_name(stem + path.name[5:]))
(out / "index.html").write_text(html)
(out / ".nojekyll").touch()
print(json.dumps(build, indent=2))
