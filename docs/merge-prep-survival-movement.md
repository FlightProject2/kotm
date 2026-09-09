# Merge preparation: survival movement and parachute

Target repository: `FlightProject2/kotm`

Target branch: `claude/h1z1-style-game-plan-7kzer5`

Base commit verified before preparation: `f3868fffc32fbfbbcb0fe2310856299b86f23792`

Suggested head branch: `codex/h1z1-survival-movement`

The branch retains the preceding local live-character-build merge
(`c63aacf`) on top of the verified remote base. That merge carries the earlier
map, 2016 mechanics, HUD, weapon, vehicle, and character work; the head commit
adds the movement, animation, and parachute pass described below.

## Payload

The change set contains the grounded run/walk rebuild, prone/crawl/roll state
and input, fitted rifle prone clips, run camera profile, parachute model wiring,
parachute deployment/steering, and focused scene tests. The authoring sources
and exported assets are kept beside the runtime changes so the GLB can be
rebuilt rather than hand-edited.

Runtime files:

- `game/character/character.gd`
- `game/character/player_input_source.gd`
- `game/character/character_motor.gd`
- `game/character/character_combat.gd`
- `game/camera/camera_rig.gd`
- `game/character/animation_driver.gd`
- `game/character/locomotion_layer.gd`
- `game/character/directional_leg_ik.gd`
- `game/character/running_arms.gd`
- `game/character/character_visuals.gd`
- `design/data/movement.json`

Tests and authoring:

- `tests/scene/test_motor.gd`
- `tests/scene/test_player_input.gd`
- `tests/scene/test_parachute.gd`
- `tests/scene/test_prone_pose.gd`
- `tools/blender/animation_library.py`
- `tools/blender/rebuild_survival_movement.py`
- `tools/blender/build_kotm_parachute_cloud.py`
- `docs/survival-movement.md`

Assets:

- `assets/models/kotm/KOTM_Parachute.glb`
- `art/character/KOTM_Parachute.blend`
- `assets/characters/kotm/KOTM_Character.glb`
- `art/character/KOTM_Character_Animated.blend`
- `assets/characters/kotm/asset_manifest.json`

The existing `assets/models/kotm/KOTM_AR75.glb` and
`assets/models/kotm/KOTM_AK47.glb` remain the solid weapon sources. The rig
adapter restores both under the authored hand attachment when the character
export only contains an empty socket, so muzzle and support-hand bindings stay
valid for either rifle.

## Verification command

Run the focused checks first with the repository's Godot runner. The helper
`tools/test_local.py` is a legacy wrapper and does not select the current
headless runner reliably.

```text
godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_motor
godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_player_input
godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_parachute
godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_prone_pose
```

Then run the complete suite with:

```text
godot --headless --path . --script res://tools/godot/run_tests.gd
```

The focused live checks used for this branch all pass, including the actor
cosmetics, gunplay, motor, prone pose, parachute, input, hand animation,
hitbox, slope, and vehicle-asset tests. The broader legacy suite still has
seven unrelated baseline failures in mechanics/projectile regression cases;
those reproduce in isolation and are outside this movement/export payload.

Open a PR against the target branch only after the exported GLB and source
blend have matching action lists and the focused checks pass.
