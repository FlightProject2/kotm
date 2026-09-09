# Survival movement and parachute

The character movement pass uses the 2016 survival-battle-royale reference as a
style target while keeping travel authoritative in the Godot motor. The Blender
actions are in-place; the motor owns velocity, stamina, collision and network
replication.

## Controls and states

- `WASD` uses the rebuilt walk, jog and run cycles. The run camera pulls back to
  a 3.05 m boom, 0.50 m shoulder offset and 76° field of view while sprinting.
- `Z` toggles prone. Prone uses a 0.55 m capsule, `KOTM_Prone_Idle` while still
  and `KOTM_Prone_Crawl` while moving.
- Tapping `A` or `D` while prone starts the corresponding in-place side roll.
  The motor supplies the lateral travel, so the animation cannot move the
  networked capsule twice.
- Aiming uses fitted rifle variants (`KOTM_AR75_Prone_Ready`,
  `KOTM_AR75_Prone_Aim`, and their crawl variants; hunting-rifle equivalents
  are exported too). The support-hand contact modifier remains enabled for
  weapon grips.
- While parachuting, the character selects `KOTM_Parachute_Glide`. The
  parachute model provides `HandSocket_L`, `HandSocket_R`, `HarnessSocket`,
  deploy, glide and left/right steering actions. The runtime canopy scales in
  during the first 0.55 seconds and follows the steering input.

## Authoring and validation

`tools/blender/animation_library.py` contains the deterministic procedural
poses and `tools/blender/rebuild_survival_movement.py` rebuilds the source blend,
manifest and Godot GLB. `tools/blender/build_kotm_parachute_cloud.py` is the
repeatable local parachute authoring script used alongside the Higgsfield 3D
Jutsu scene.

The focused checks are:

```text
py -3 tools/test_local.py tests/scene/test_motor.gd tests/scene/test_player_input.gd tests/scene/test_parachute.gd tests/scene/test_prone_pose.gd
```

`test_prone_pose.gd` verifies that the exported clip names are present and that
the driven prone pose lowers the head and switches to crawl/roll states. The
parachute test verifies the GLB root, sockets and imported animation player.
