"""Add the fitted truck clip to an existing canonical character master.

blender -b CHARACTER.blend --python tools/blender/build_vehicle_rider.py
Requires art/vehicles/truck_fit.json from build_snow_truck.py.
Preserves all pre-existing clips and the shared deform skeleton.
"""
import bpy, sys, math, json
from pathlib import Path
from mathutils import Vector, Matrix
sys.path.insert(0, str(Path(__file__).parent))
import vehicle_pose_math as pose
import export_kotm_character as exporter

REPO = Path(__file__).resolve().parents[2]
fit = json.loads((REPO / 'art/vehicles/truck_fit.json').read_text(encoding='utf-8-sig'))
rig = bpy.data.objects['KOTM_Character_Rig']
for track in rig.animation_data.nla_tracks:
    track.mute = True
root = Vector(fit['driver_root_blender'])
def seated(phase=0):
    pose.reset(rig)
    pose.set_bone_position(rig, 'pelvis', (0, .005, fit['seat_surface_z'] + .12 - root.z))
    for name, angle in [('spine_01', 3), ('spine_02', 2), ('chest', 2), ('head', -5)]:
        pose.rotate_world_axes(rig, name, (angle, 0, 0))
    reports = []
    for side, sign in [('l', 1), ('r', -1)]:
        wrist = Vector(fit['hand_grips_blender'][side.upper()]) - root
        hand = pose.anatomical_hand_matrix(rig, side, wrist, (0, -1, 0), (0, 0, 1))
        reports.append(pose.solve_two_bone(rig, 'upperarm.' + side, 'lowerarm.' + side, wrist,
            Vector((sign * .39, -.09, 1.33)), 'hand.' + side, hand))
        ankle = Vector(fit['foot_rests_blender'][side.upper()]) - root
        foot = rig.data.bones['foot.' + side].matrix_local.copy()
        foot.translation = ankle
        reports.append(pose.solve_two_bone(rig, 'thigh.' + side, 'calf.' + side, ankle,
            Vector((sign * .17, -.60, fit['seat_surface_z'] - .05)), 'foot.' + side, foot))
        pose._curl(rig, side, (62, 67, 38))
    return max(r['target_error_m'] for r in reports)

error = seated()
pose_report = {'max_limb_target_error_m': error, 'bones_blender': {
    name: list(rig.pose.bones[name].head) for name in ['pelvis', 'head', 'hand.l', 'hand.r', 'foot.l', 'foot.r']}}
if error > .015:
    raise RuntimeError('Truck rider limb target is out of reach: %s' % error)
samples = {b.name: b.matrix.copy() for b in rig.pose.bones}
pose.reset(rig)
old = bpy.data.actions.get('KOTM_Truck_Seated')
if old:
    bpy.data.actions.remove(old)
action = bpy.data.actions.new('KOTM_Truck_Seated')
action.use_fake_user = True
rig.animation_data.action = action
for frame in (1, 31, 61):
    for bone in rig.pose.bones:
        if not (bone.bone.use_deform or bone.name == 'master'):
            continue
        kwargs = {} if not bone.parent else {'parent_matrix': samples[bone.parent.name],
            'parent_matrix_local': bone.parent.bone.matrix_local}
        basis = bone.bone.convert_local_to_pose(samples[bone.name], bone.bone.matrix_local, invert=True, **kwargs)
        loc, rot, scale = basis.decompose()
        bone.location = loc
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = rot
        bone.scale = scale
        for channel in ['location', 'rotation_quaternion', 'scale']:
            bone.keyframe_insert(channel, frame=frame, group=bone.name)
action['loop'] = True
action['fps'] = 30
action['duration_seconds'] = 2.0
action['baked'] = 'Driver wrist and ankle targets, unchanged canonical deform skeleton'
pose.reset(rig)
bpy.context.scene.frame_set(1)
destination = REPO / 'art/character/KOTM_Character_Animated.blend'
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(destination), compress=True)
# Export only the character GLB: wardrobe files already share this unchanged bind pose.
for col in bpy.data.collections:
    col.hide_viewport = col.hide_render = False
for obj in bpy.data.objects:
    obj.hide_viewport = obj.hide_render = False
    obj.hide_set(False)
objects = [rig] + [obj for name in exporter.COLLECTIONS for obj in bpy.data.collections[name].all_objects]
exporter.export(REPO / 'assets/characters/kotm/KOTM_Character.glb', objects, True)
manifest_path = REPO / 'assets/characters/kotm/asset_manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['animations']['KOTM_Truck_Seated'] = {'duration_seconds': 2.0, 'loop': True, 'speed_mps': 0}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
(REPO / 'art/vehicles/rider_fit_validation.json').write_text(json.dumps(pose_report, indent=2))
print('VEHICLE_RIDER_COMPLETE', json.dumps(pose_report))
