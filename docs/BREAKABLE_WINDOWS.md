# Breakable building windows

Building windows start intact each match. Punch a pane within melee reach, shoot it, or detonate a frag grenade nearby to shatter it. The pane disappears with a short glass sound and fragments; the opening then admits bullets and movement where its dimensions permit. Window state stays broken for the match and reaches clients that join later.

The active snow map (`kotm-live`) has 431 panes across 34 spatial batches. The original project map (`kotm`) has 326 panes across 29 batches. Existing buildings, the frontier building kit and the resort cabins use the same behavior. The six frontier building models have actual carved facade openings in their editable Blender sources, which the resort cabins inherit. Legacy full-wall collision boxes are split around their window openings at load time.

`game/world/window_manager.gd` owns state, render batches and PhysicsServer shapes. It allocates one static physics body and one MultiMesh per occupied 96 m cell rather than a node/body per pane. Intact windows do no per-frame processing. A shared 96-fragment pool and three audio players activate briefly on breaks, then sleep. Static scenery batching excludes breakable glass. `window_asset_adapter.gd` extracts existing panes and frontier/resort window specifications before the scenery meshes are merged.

Server-only punch, projectile impact and grenade radius checks generate reliable `window_broken` events through the existing network event system. The authority supplies late-join snapshots. Repeated hits and repeated snapshots are idempotent. Clients cannot call the authority-only snapshot receiver over RPC or originate authoritative break events. Snapshot replay is verified locally; this pass did not include a two-machine multiplayer session.

## Validation and review

Run Godot with the project path and these normal scenes:

- `res://game/dev/qa_breakable_windows.tscn`: punch, projectile, near/far blast, replay, idle behavior and ten real legacy/frontier/resort aperture checks. Native rendering also checks stored MultiMesh local dimensions; the headless renderer does not store GPU transforms.
- `res://game/dev/qa_world_windows.tscn`: builds the actual map, checks every intact window is hit by a ray, breaks it, and checks the opening contains no hidden wall collider.
- `res://game/dev/window_feature_capture.tscn -- --window-output=<absolute directory>`: captures an actual game ranch before shooting, after a bullet, during a real frag detonation, and after the fragments clear.

Reviewed captures are in `../character/style_revision/renders/windows/` from the project root: `windows_01_intact.png`, `windows_02_bullet.png`, `windows_03_frag_blast.png`, and `windows_04_open_apertures.png`. Numerical reports are beside the style revision README. Both project behavior suites and the native transform check pass. Full-map aperture audits confirm all 431 active-map and 326 original-map openings clear after shattering.
