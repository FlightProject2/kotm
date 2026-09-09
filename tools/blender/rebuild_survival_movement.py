"""Rebuild KOTM's survival-game locomotion on the shipped character rig.

Run with Blender 5.2 and ``KOTM_Character_Animated.blend`` loaded. The script
replaces walk/run, adds prone/crawl/roll clips, rebuilds fitted rifle movement,
updates the manifest, refreshes the GLB, and saves the editable source.
"""
import bpy
import json
import os
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AUTHORING = os.path.abspath(os.path.join(REPO, "..", "character"))
sys.path.insert(0, HERE)
sys.path.insert(1, AUTHORING)

import animation_library as locomotion
import equipment_pose_fix as pose
import equipment_weapons_vehicle as equipment
import stance_library
from refresh_exports import refresh

stance_library.locomotion = locomotion
rig = bpy.data.objects["KOTM_Character_Rig"]
scene = bpy.context.scene


def animation_info(action):
    info = {
        "duration_seconds": action.get("duration_seconds"),
        "loop": bool(action.get("loop", False)),
        "speed_mps": action.get("recommended_controller_speed_mps", 0),
    }
    if action.get("foot_contact_phases"):
        info["foot_contact_phases"] = {"left": 0.0, "right": 0.5}
    for prop in ("stance_cycle_fraction", "steps_per_second", "step_length_m", "gait_revision"):
        if prop in action:
            info[prop] = action[prop]
    return info


def replace(name):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)


def combine_upper(source, reference, name):
    frames = round(source.frame_range[1] - source.frame_range[0])
    first = source.frame_range[0]

    def sample(t):
        pose.reset(rig)
        rig.animation_data.action = source
        scene.frame_set(round(first + t * frames))
        bpy.context.view_layer.update()
        body_basis = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
        rig.animation_data.action = None
        for bone_name, matrix in body_basis.items():
            rig.pose.bones[bone_name].matrix_basis = matrix
        for bone_name, matrix in reference["basis"].items():
            rig.pose.bones[bone_name].matrix_basis = matrix
        bpy.context.view_layer.update()

    replace(name)
    action = equipment.bake_callback(rig, name, frames, sample, bool(source.get("loop", False)))
    action["recommended_controller_speed_mps"] = source.get("recommended_controller_speed_mps", 0)
    action["duration_seconds"] = source.get("duration_seconds", frames / locomotion.FPS)
    action["loop"] = bool(source.get("loop", False))
    action["gait_revision"] = "Prone rifle posture layered over the grounded crawl; support hand is contact-corrected in Godot."
    return action

equipment.reset(rig)
actions = {action.name: action for action in bpy.data.actions if action.name.startswith("KOTM_")}
print("REBUILDING_SURVIVAL_LOCOMOTION", flush=True)
actions.update(locomotion.create_animations(rig))

# Rebuild crouch and every standing rifle gait from the corrected base cycles.
actions = stance_library.create_stances(rig, actions)

# Prone rifle variants inherit the fitted ready/aim arms in the horizontal chest
# frame. The runtime support-hand modifier then closes any remaining contact gap.
for weapon_key, prefix in (("AR75", "AR75"), ("HuntingRifle", "Hunting")):
    for ready, suffix in ((True, "Prone_Ready"), (False, "Prone_Aim")):
        reference = stance_library._upper(rig, ready, weapon_key)
        pose.reset(rig)
        actions[f"KOTM_{prefix}_{suffix}"] = combine_upper(
            actions["KOTM_Prone_Idle"], reference, f"KOTM_{prefix}_{suffix}")
        actions[f"KOTM_{prefix}_{suffix}_Crawl"] = combine_upper(
            actions["KOTM_Prone_Crawl"], reference, f"KOTM_{prefix}_{suffix}_Crawl")

pose.reset(rig)
rig.animation_data.action = None
scene.frame_set(1)
scene.frame_start = 1
scene.frame_end = 91

manifest_path = os.path.join(AUTHORING, "asset_manifest.json")
with open(manifest_path, encoding="utf-8") as source:
    manifest = json.load(source)
manifest["animations"] = {
    action.name: animation_info(action)
    for action in bpy.data.actions
    if action.name.startswith("KOTM_")
}
manifest["locomotion_revision"] = {
    "style": "Grounded 2016 survival battle-royale locomotion",
    "run": "Close rib-level arm drive, relaxed hands, forward athletic lean and matched opposite arm/leg cadence.",
    "prone": "0.55 m gameplay capsule with idle, crawl and left/right roll actions.",
    "camera": "3.05 m run boom, 0.50 m shoulder offset and 76 degree run FOV.",
}
for path in (manifest_path, os.path.join(AUTHORING, "godot", "assets", "asset_manifest.json")):
    with open(path, "w", encoding="utf-8") as output:
        json.dump(manifest, output, indent=2)

refresh()
pose.reset(rig)
rig.animation_data.action = None
rig["animation_library"] = ", ".join(sorted(manifest["animations"]))
scene["locomotion_reference"] = "Grounded 2016 survival-game run/walk camera and prone movement; authored from supplied KOTM/H1Z1 references."
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(AUTHORING, "KOTM_Character_Animated.blend"))
print("SURVIVAL_MOVEMENT_COMPLETE", len(manifest["animations"]), flush=True)
