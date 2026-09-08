# Editable KOTM character

Open `KOTM_Character_Animated.blend` in Blender 5.2. It contains the complete
editable body, shared rig, 42 baked clips, default white tank and boxers,
ten blank wardrobe templates, finished KOTM beanie and fitted equipment.
Textures are packed into the file. The full body is retained in the hidden
`00_EDITABLE_FULL_BODY` collection for editing and weight transfer.

The AR and hunting-rifle ADS actions use a shouldered sight line: the buttpad
sits in the shoulder pocket, the right eye follows the sights, and both palms
remain fitted to their grips in standing, moving, crouched and firing clips.

`KOTM_AR75_SolidStock.blend` is the independent rifle with the stock opening
filled and the lower adjustment latch removed.

Godot ignores this directory so installing Blender is not required to play.
The runtime uses the checked-in GLB files under `assets/characters/kotm`.
From the repository root, re-export an edited master with:

```sh
blender --background art/character/KOTM_Character_Animated.blend --python tools/blender/export_kotm_character.py
```

This exports the existing baked animation library and all wardrobe templates.
If you change garment coverage, update `asset_manifest.json` body masks and
test the corresponding outfit while aiming, crouching, running and seated.
Keep the 54 deform bone names and bind pose consistent across attachments.

The anatomical base is adapted from Blender Studio Human Base Meshes 1.4.1
(realistic male by Dan Ulrich and contributors, CC0). Supplied project gear
remains project-supplied content; this directory does not assign it a new license.
