"""Rig the supplied snow UTV, preserving the established 0.9-scale rider fit.

blender -b --factory-startup --python tools/blender/build_snowmobile.py -- SOURCE.blend
The GLB contains a two-second mechanical demonstration; gameplay drives the same pivots.
"""
import bpy, sys, math, json
from pathlib import Path
from mathutils import Matrix, Vector

REPO = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else REPO.parent.parent.parent / 'blender - king of the mountain assets' / 'Snow-mobile-utv.blend'
ART = REPO / 'art/vehicles'
OUT = REPO / 'assets/models/kotm'
ART.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
(ART / '.gdignore').write_text('')
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
for obj in list(bpy.data.objects):
    if obj.type != 'MESH':
        bpy.data.objects.remove(obj, do_unlink=True)
transform = Matrix.Rotation(-math.pi / 2, 4, 'Z') @ Matrix.Scale(.9, 4) @ Matrix.Translation(Vector((-6, 0, 0)))
meshes = list(bpy.context.scene.objects)
worlds = {o: o.matrix_world.copy() for o in meshes}
for obj in meshes:
    obj.data = obj.data.copy()
    obj.data.transform(transform @ worlds[obj])
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.hide_render = False
    obj.hide_viewport = False
    obj.hide_set(False)
ground = min(v.co.z for o in meshes for v in o.data.vertices)
for obj in meshes:
    obj.data.transform(Matrix.Translation((0, 0, -ground)))
def point(p):
    return transform @ Vector(p) - Vector((0, 0, ground))
def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_world = Matrix.Translation(Vector(location))
    obj.empty_display_type = 'ARROWS'
    obj.empty_display_size = .10
    return obj
def parent_keep(obj, parent):
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
def centred_pivot(name, objects, parent):
    vertices = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    centre = Vector(tuple((min(v[i] for v in vertices) + max(v[i] for v in vertices)) / 2 for i in range(3)))
    pivot = empty(name, centre, parent)
    for o in objects:
        parent_keep(o, pivot)
    return pivot
root = empty('KOTM_Snowmobile')
root['forward_axis'] = 'glTF +Z / Blender -Y'
root['source_asset'] = SOURCE.name
root['rig_version'] = 1
body = empty('BodySuspension', parent=root)
for obj in meshes:
    parent_keep(obj, body)
steer = empty('HandlebarsSteer', point((6.30, 0, 1.15)), body)
for obj in meshes:
    if obj.name.split('.')[0] in ['Handlebar', 'Grip', 'Lever', 'MirrorArm', 'Mirror', 'BarStem']:
        parent_keep(obj, steer)
skis = []
for side, suffix, sign in [('L', '', 1), ('R', '.001', -1)]:
    pivot = empty('SkiSteer_' + side, point((7.35, sign * .5, .11)), root)
    skis.append(pivot)
    for name in ['Ski', 'SkiKeel', 'SkiLoop', 'SkiSaddle', 'Spindle']:
        parent_keep(bpy.data.objects[name + suffix], pivot)
    # Measured wrist bone origins from the canonical KOTM_Snowmobile_Seated pose.
    empty('HandGrip_' + side, (sign * .378946, -.191599, 1.065712 - ground), steer)
    empty('FootRest_' + side, point((6.03, sign * .36, .40)) + Vector((0, .06, .105)), body)
empty('SeatDriver', (0, .19, -ground), body)
empty('SeatPassenger', (0, 1.0, -ground), body)
empty('SeatSurface', point((5.79, 0, .82)), body)
track_root = empty('TrackAssembly', parent=root)
wheel_pivots = []
for i, name in enumerate(['DriveSprocket', 'RearIdler', 'Bogie', 'Bogie.001', 'Bogie.002']):
    pivot = centred_pivot('TrackWheel_L_%03d' % i, [bpy.data.objects[name]], track_root)
    pivot['wheel_radius'] = .117 if i < 2 else .063
    wheel_pivots.append(pivot)
for obj in meshes:
    if obj.name.split('.')[0] in ['TrackBelt', 'TrackLugs', 'Rail', 'RearShock', 'RearArm']:
        parent_keep(obj, track_root)
# The original lugs are one static mesh. Replace only these with equivalent individual
# rubber bars so the belt circulates around its idlers instead of rotating as a solid block.
old_lugs = bpy.data.objects['TrackLugs']
rubber = old_lugs.data.materials[0]
bpy.data.objects.remove(old_lugs, do_unlink=True)
front = point((6.00, 0, .25))
rear = point((4.60, 0, .25))
radius = .171
length = (front - rear).length
perimeter = 2 * length + 2 * math.pi * radius
empty('TrackPathFront_L', front, track_root)
empty('TrackPathRear_L', rear, track_root)
empty('TrackPathTop_L', front + Vector((0, 0, radius)), track_root)
def track_pose(distance):
    s = distance % perimeter
    if s < length:
        return rear + Vector((0, -s, radius)), 0.0
    s -= length
    if s < math.pi * radius:
        a = s / radius
        return front + Vector((0, -radius * math.sin(a), radius * math.cos(a))), a
    s -= math.pi * radius
    if s < length:
        return front + Vector((0, s, -radius)), math.pi
    a = (s - length) / radius
    return rear + Vector((0, radius * math.sin(a), -radius * math.cos(a))), math.pi + a
treads = []
for i in range(48):
    p, angle = track_pose(i * perimeter / 48)
    pivot = empty('TrackTread_L_%03d' % i, p, track_root)
    pivot.rotation_euler.x = angle
    pivot['track_phase'] = i / 48
    bpy.ops.mesh.primitive_cube_add(size=1)
    lug = bpy.context.object
    lug.name = 'TreadRubber_%03d' % i
    lug.scale = (.342, .050, .023)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    lug.data.materials.append(rubber)
    lug.parent = pivot
    lug.matrix_basis = Matrix.Identity(4)
    treads.append(pivot)
for mat in bpy.data.materials:
    if 'Glass' in mat.name:
        mat.use_nodes = True
        bs = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        bs.inputs['Base Color'].default_value = (.24, .40, .46, .20)
        bs.inputs['Alpha'].default_value = .20
        bs.inputs['Roughness'].default_value = .15
        mat.surface_render_method = 'BLENDED'
animated = [body, steer, *skis, *wheel_pivots, *treads]
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 61
for f in range(1, 62):
    t = (f - 1) / 60
    scene.frame_set(f)
    body.location.z = .012 * math.sin(t * 4 * math.pi)
    body.rotation_euler.y = .012 * math.sin(t * 2 * math.pi)
    steer.rotation_euler.z = .35 * math.sin(t * 2 * math.pi)
    for pivot in skis:
        pivot.rotation_euler.z = steer.rotation_euler.z
    for pivot in wheel_pivots:
        pivot.rotation_euler.x = 4 * math.pi * t
    for i, pivot in enumerate(treads):
        p, angle = track_pose(i * perimeter / 48 + t * perimeter)
        pivot.location = p
        pivot.rotation_euler.x = angle
    for obj in animated:
        obj.keyframe_insert('location', frame=f)
        obj.keyframe_insert('rotation_euler', frame=f)
for obj in animated:
    action = obj.animation_data.action
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    track = obj.animation_data.nla_tracks.new()
    track.name = 'Drive'
    strip = track.strips.new('Drive', 1, action)
    obj.animation_data.action = None
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'KOTM_Snowmobile.blend'), compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUT / 'KOTM_Snowmobile.glb'), export_format='GLB', export_animations=True,
    export_animation_mode='NLA_TRACKS', export_extras=True, export_apply=True, export_skins=False)
report = {'source': SOURCE.name, 'ground_shift': -ground, 'treads': len(treads), 'wheel_pivots': len(wheel_pivots),
    'track_radius': radius, 'track_length': length, 'driver_root_blender': [0, .19, -ground], 'animation': 'Drive'}
(ART / 'snowmobile_rig.json').write_text(json.dumps(report, indent=2))
print('SNOWMOBILE_RIG_COMPLETE', json.dumps(report))
