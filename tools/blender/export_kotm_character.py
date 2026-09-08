"""Export the edited KOTM master with Blender 5.2.

blender --background art/character/KOTM_Character_Animated.blend \
    --python tools/blender/export_kotm_character.py

Exports the existing baked clips and shared skeleton. It does not rebuild poses.
"""
from pathlib import Path
import bpy

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "assets" / "characters" / "kotm"
COLLECTIONS = (
    "01_BODY", "02_FACE_AND_HAIR", "03_DEFAULT_CLOTHING",
    "07_FITTED_EQUIPMENT", "08_WEAPONS", "10_BLANK_TEMPLATES",
)


def export(path, objects, animated):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["KOTM_Character_Rig"]
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        use_visible=False, export_animations=animated,
        export_animation_mode="ACTIONS", export_frame_range=False,
        export_def_bones=True, export_leaf_bone=False, export_skins=True,
        export_extras=True, export_apply=False, export_vertex_color="MATERIAL",
        export_anim_slide_to_zero=True, export_optimize_animation_size=True,
        export_anim_single_armature=True,
    )


def main():
    rig = bpy.data.objects["KOTM_Character_Rig"]
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    if rig.animation_data:
        rig.animation_data.action = None
        for track in rig.animation_data.nla_tracks:
            track.mute = True
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    bpy.context.scene.frame_set(1)
    for col in bpy.data.collections:
        col.hide_viewport = False
        col.hide_render = False
    for obj in bpy.data.objects:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.hide_set(False)
    assembled = [rig] + [obj for name in COLLECTIONS
                        for obj in bpy.data.collections[name].all_objects]
    export(OUT / "KOTM_Character.glb", assembled, True)
    for root in bpy.data.collections["10_BLANK_TEMPLATES"].objects:
        if root.type != "EMPTY":
            continue
        filename = "KOTM_Beanie.glb" if root.name == "EQ_Beanie" else (
            "KOTM_Template_" + root.name.removeprefix("EQ_Template_") + ".glb")
        export(OUT / "templates" / filename,
               [rig, root, *root.children_recursive], False)
    print("KOTM_CHARACTER_EXPORT_COMPLETE")


if __name__ == "__main__":
    main()
