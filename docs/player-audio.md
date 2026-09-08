# Contextual player audio

The 22 supplied WAV recordings are integrated into the real `Character`, on the same event path for players and bots. The authoritative simulation sends `Events.player_sound(event, position, character_id, volume)` through `Net.fx_all`; each peer plays a nearby spatial sound. No stamina rules, health values, movement speeds or collision shapes were changed for audio.

Open `game/audio/audio_test_yard.tscn` in Godot 4.6.3 and press **F6** to test using the actual playable character. WASD moves, Shift sprints, C crouches, Space jumps, LMB punches and F tests the labelled locked door. H applies a real nonlethal hit, G toggles gas damage, K kills and P respawns. Mouse looks; Escape releases the pointer. Walk across the labelled floor strips and into the metal fence. The overlay identifies the last recording actually played.

| Context | Behaviour / supplied recording |
|---|---|
| Ground movement | Left/right strikes follow the active animation's contact phases (including moving-fire/reload lower-body gait), alternating the supplied light-left and normal-right recordings on hard floor. When visual phase is unavailable, stride is derived from the manifest's native speed × cycle duration ÷ 2. Crouching uses lower gain. Idle, airborne, dead, blocked and vehicle travel are silent. |
| Grass / wood / metal | Respective walking samples; small playback pitch variation for the single supplied sample per surface. |
| Water | Two alternating shallow-water variants; deeper-water sample in deep tagged volumes. These are wading sound volumes, not a swimming implementation. |
| Accepted jump | Jump voice only when the motor accepts the jump; holding Space does not repeat it. |
| Fists | Punch 1 / 2 on accepted fist swings, respecting combat cooldown. Other melee weapons keep their existing behaviour. |
| Nonlethal damage | Hurt voice, at most once every 0.75 s. Bleeding and whiteout do not incorrectly trigger bullet hurt or gas coughs. |
| Death | One of three death voices, once per death. Replaces the generated death grunt and interrupts breathing/coughing. |
| Gas damage | Light cough first, deeper coughing after at least four seconds of uninterrupted exposure. At most one cough request every 4.5 s. Leaving exposure for over 1.8 s resets the sequence. |
| Sustained sprint | The two “out of stamina” recordings provide exertion breathing after seven seconds of actual sprint movement, at most every six seconds. The game has no stamina meter: this is an exertion cue and never stops or slows the player. |
| Fence | One of two metal rattles on actual collision with a tagged metal fence, at most every 1.25 s. |
| Locked door | The supplied latch sound on a fresh F interaction facing a tagged locked door within 2.2 m, after existing loot/vehicle interactions. At most every 1.5 s. |

## Authoring surfaces and contacts

Put `audio_surface` metadata on a physics collider or its parent. Supported string values: `hard`, `grass`, `wood`, `metal`, `shallow_water`, `deep_water`. Untagged geometry uses `hard`; the floor is sampled beneath the grounded character by a short world-layer ray. The snowy outdoor terrain uses the supplied soft grass step as an explicit fallback because no dedicated snow sample was supplied. Cabin/barn surfaces, known wooden crates and wooden farm fences are tagged `wood`; known car wrecks and barrels are tagged `metal`. Other building floors retain the neutral hard-surface sounds. Add finer audio regions when new terrain recordings/materials are authored.

For water, attach `game/audio/audio_water_area.gd` to an `Area3D`, add a collision shape and choose `shallow_water` or `deep_water` in its exported property. It detects player-layer bodies. Overlapping deep water takes priority; removing/exiting a volume clears its override. Water changes only footstep selection.

Metal fences require boolean `audio_fence = true` on the actual collider or parent; ordinary wooden farm fences and unrelated metal props are not labelled as metal fences. Doors require boolean `audio_locked_door = true` on the solid door collider or parent. Existing open doorway frames are deliberately not locked-door triggers. New tagged examples are contained in the test yard; this change does not add doors or bodies of water to the main map.

## Mix and networking

Player sounds have their own bounded pool of 24 positional players, with 35 m maximum footstep distance and 50 m for other cues, and inverse-square attenuation. Crouch footstep gain is 0.22 versus 0.58 walking / 0.85 sprinting. Voice priority is death > hurt > coughing > exertion/jump. Lower-priority voices cannot interrupt higher ones; nearby gunfire uses the separate existing gun pool. Variants avoid immediate repeats per character/event and use a dedicated random generator, leaving gameplay/ballistics randomness untouched. Effects use the existing unreliable cosmetic network channel; no client-side state can cause authoritative damage or movement through audio.

`CharacterAudio.sound_requested` exposes accepted gameplay sound requests. `AudioManager.player_sound_played` exposes the recording that actually passed priority/pool arbitration. Scene tests observe these signals, exercise real physics/health/combat/interaction hooks, and check the 22 resources, variant cycling and bounded voice pool.

Gait entries in the character manifest provide `duration_seconds`, `recommended_controller_speed_mps` (or `speed_mps`) and `foot_contact_phases` (`left: 0.0`, `right: 0.5`). The reviewed walk/jog/run/crouch cycles yield native step lengths of 0.70 / 1.283 / 1.95 / 0.48 m respectively. Runtime animation rate changes naturally change the sound cadence; ready/aim gait transitions preserve phase. The distance fallback is for missing/unavailable visual phase, and does not hardcode a single footstep interval across gaits.

Run: `godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_player_audio`

## Sources

`assets/audio/player/manifest.json` records all original user-provided basenames, SHA-256 hashes, PCM parameters, duration and byte size. WAVs are byte-for-byte copies, totalling 2,580,296 bytes; runtime mixing and pitch variation do not modify them. `tools/import_player_audio.py SOURCE_DIRECTORY` reproducibly copies only these explicit 22 files. The recordings were supplied as project assets and are not labelled CC0 or relicensed by this integration.
