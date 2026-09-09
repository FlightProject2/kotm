"""Build the KOTM ram-air parachute in Higgsfield 3D Jutsu.

This script is intentionally self-contained. Higgsfield injects ``bpy`` and
``artifacts``; the committed scene becomes the editable source and GLB export.
"""
import bpy
import math
from mathutils import Vector


for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 72
if scene.world is None:
    scene.world = bpy.data.worlds.new("KOTM_Parachute_World")
scene.world.color = (0.012, 0.016, 0.024)


def material(name, color, metallic=0.0, roughness=0.75):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


FABRIC_RED = material("Fabric_Red", (0.50, 0.012, 0.018), roughness=0.88)
FABRIC_FADED = material("Fabric_Red_Faded", (0.72, 0.035, 0.025), roughness=0.92)
FABRIC_BLACK = material("Fabric_Black", (0.008, 0.010, 0.014), roughness=0.92)
FABRIC_WHITE = material("Fabric_White", (0.72, 0.72, 0.68), roughness=0.9)
SEAM = material("Seams", (0.12, 0.016, 0.020), roughness=0.96)
LINE = material("Suspension_Lines", (0.58, 0.55, 0.44), roughness=0.72)
METAL = material("Riser_Metal", (0.09, 0.10, 0.12), metallic=0.65, roughness=0.3)
FLOOR = material("Preview_Floor", (0.018, 0.022, 0.032), roughness=0.72)

root = bpy.data.objects.new("KOTM_Parachute_Root", None)
bpy.context.collection.objects.link(root)

SPAN = 5.4
CELL_COUNT = 11
FRONT_Y, MID_Y, REAR_Y = -0.98, -0.03, 0.98


def arch_z(x):
    unit = x / (SPAN * 0.5)
    return 1.05 - 0.40 * unit * unit


def make_cell(index, x0, x1, mat):
    x0 += 0.015
    x1 -= 0.015
    verts = []
    for x in (x0, x1):
        for y in (FRONT_Y, MID_Y, REAR_Y):
            top = arch_z(x) + 0.12 * (1.0 - abs(y))
            thickness = 0.43 - 0.14 * max(0.0, y)
            verts.extend(((x, y, top), (x, y, top - thickness)))

    def vi(side, station, lower):
        return side * 6 + station * 2 + lower

    faces = []
    for station in range(2):
        faces.append((vi(0, station, 0), vi(1, station, 0), vi(1, station + 1, 0), vi(0, station + 1, 0)))
        faces.append((vi(0, station + 1, 1), vi(1, station + 1, 1), vi(1, station, 1), vi(0, station, 1)))
    faces.extend((
        (vi(0, 0, 1), vi(1, 0, 1), vi(1, 0, 0), vi(0, 0, 0)),
        (vi(0, 2, 0), vi(1, 2, 0), vi(1, 2, 1), vi(0, 2, 1)),
        (vi(0, 0, 0), vi(0, 1, 0), vi(0, 2, 0), vi(0, 2, 1), vi(0, 1, 1), vi(0, 0, 1)),
        (vi(1, 0, 1), vi(1, 1, 1), vi(1, 2, 1), vi(1, 2, 0), vi(1, 1, 0), vi(1, 0, 0)),
    ))
    mesh = bpy.data.meshes.new(f"CanopyCell_{index:02d}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(f"Canopy_Cell_{index:02d}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = root
    for face in mesh.polygons:
        face.use_smooth = True
    bevel = obj.modifiers.new("Soft_Fabric_Edges", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 2


def tube(name, points, radius, mat):
    curve = bpy.data.curves.new(name + "_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(mat)
    obj.parent = root
    return obj


palette = [FABRIC_BLACK, FABRIC_RED, FABRIC_FADED, FABRIC_RED, FABRIC_WHITE,
           FABRIC_FADED, FABRIC_WHITE, FABRIC_RED, FABRIC_FADED, FABRIC_RED, FABRIC_BLACK]
for cell in range(CELL_COUNT):
    x0 = -SPAN * 0.5 + SPAN * cell / CELL_COUNT
    x1 = -SPAN * 0.5 + SPAN * (cell + 1) / CELL_COUNT
    make_cell(cell + 1, x0, x1, palette[cell])
    xa, xb = x0 + 0.055, x1 - 0.055
    z0 = arch_z((x0 + x1) * 0.5) - 0.36
    z1 = arch_z((x0 + x1) * 0.5) - 0.07
    intake_mesh = bpy.data.meshes.new(f"Intake_{cell + 1:02d}_Mesh")
    intake_mesh.from_pydata(((xa, FRONT_Y - 0.018, z0), (xb, FRONT_Y - 0.018, z0),
                             (xb, FRONT_Y - 0.018, z1), (xa, FRONT_Y - 0.018, z1)), [], ((0, 1, 2, 3),))
    intake_mesh.materials.append(FABRIC_BLACK)
    intake = bpy.data.objects.new(f"Cell_Intake_{cell + 1:02d}", intake_mesh)
    bpy.context.collection.objects.link(intake)
    intake.parent = root

for rib in range(1, CELL_COUNT):
    x = -SPAN * 0.5 + SPAN * rib / CELL_COUNT
    tube(f"Rib_Seam_{rib:02d}", ((x, FRONT_Y, arch_z(x) + 0.015),
                                  (x, MID_Y, arch_z(x) + 0.135),
                                  (x, REAR_Y, arch_z(x) + 0.015)), 0.012, SEAM)

logo_curve = bpy.data.curves.new("KOTM_Mark_Curve", "FONT")
logo_curve.body = "KOTM"
logo_curve.align_x = "CENTER"
logo_curve.size = 0.42
logo_curve.extrude = 0.008
logo_curve.bevel_depth = 0.002
logo_curve.materials.append(FABRIC_WHITE)
logo = bpy.data.objects.new("KOTM_Canopy_Mark", logo_curve)
bpy.context.collection.objects.link(logo)
logo.rotation_euler = (math.radians(77), 0.0, 0.0)
logo.location = (0.0, 0.18, arch_z(0.0) + 0.15)
logo.parent = root

line_specs = (
    ((-2.20, 0.72, arch_z(-2.20) - 0.20), (-0.38, 0.03, -3.25)),
    ((-1.25, -0.66, arch_z(-1.25) - 0.30), (-0.30, -0.02, -3.25)),
    ((-1.05, 0.72, arch_z(-1.05) - 0.24), (-0.30, 0.05, -3.25)),
    ((-2.35, -0.60, arch_z(-2.35) - 0.26), (-0.38, -0.04, -3.25)),
    ((2.20, 0.72, arch_z(2.20) - 0.20), (0.38, 0.03, -3.25)),
    ((1.25, -0.66, arch_z(1.25) - 0.30), (0.30, -0.02, -3.25)),
    ((1.05, 0.72, arch_z(1.05) - 0.24), (0.30, 0.05, -3.25)),
    ((2.35, -0.60, arch_z(2.35) - 0.26), (0.38, -0.04, -3.25)),
)
for index, points in enumerate(line_specs, 1):
    tube(f"Suspension_Line_{index:02d}", points, 0.009, LINE)

for side in (-1, 1):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.105, minor_radius=0.018,
                                     major_segments=16, minor_segments=6,
                                     location=(side * 0.34, 0.03, -3.38), rotation=(math.pi / 2, 0, 0))
    grip = bpy.context.object
    grip.name = "Riser_Grip_L" if side < 0 else "Riser_Grip_R"
    grip.data.materials.append(METAL)
    grip.parent = root

for name, location in (("HandSocket_L", (-0.34, 0.03, -3.38)),
                       ("HandSocket_R", (0.34, 0.03, -3.38)),
                       ("HarnessSocket", (0.0, 0.0, -3.9))):
    socket = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(socket)
    socket.empty_display_type = "SPHERE"
    socket.empty_display_size = 0.05
    socket.location = location
    socket.parent = root


def stash_action(name, keys, loop=False):
    root.animation_data_create()
    action = bpy.data.actions.new(name)
    root.animation_data.action = action
    for frame, location, rotation, scale in keys:
        root.location = location
        root.rotation_euler = rotation
        root.scale = scale
        root.keyframe_insert("location", frame=frame, group="Root Motion")
        root.keyframe_insert("rotation_euler", frame=frame, group="Root Motion")
        root.keyframe_insert("scale", frame=frame, group="Root Motion")
    for layer in action.layers:
        for layered_strip in layer.strips:
            for bag in layered_strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "BEZIER"
                    if loop:
                        curve.modifiers.new("CYCLES")
    track = root.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(keys[0][0]), action)
    strip.action_frame_start = keys[0][0]
    strip.action_frame_end = keys[-1][0]
    strip.mute = True
    root.animation_data.action = None
    return action


deploy = stash_action("KOTM_Parachute_Deploy", (
    (1, (0, 0, -2.1), (math.radians(18), 0, 0), (0.08, 0.08, 0.08)),
    (10, (0, 0, -0.8), (math.radians(10), 0, 0), (0.42, 0.28, 0.35)),
    (22, (0, 0, 0.12), (math.radians(-5), 0, 0), (1.08, 0.92, 0.86)),
    (32, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
))
stash_action("KOTM_Parachute_Glide", (
    (1, (0, 0, 0), (math.radians(-2), 0, math.radians(-1)), (1, 1, 1)),
    (24, (0, 0, 0), (math.radians(2), 0, math.radians(1.5)), (1, 1, 1)),
    (48, (0, 0, 0), (math.radians(-2), 0, math.radians(-1)), (1, 1, 1)),
), loop=True)
stash_action("KOTM_Parachute_Steer_Left", (
    (1, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
    (12, (0, 0, -0.05), (math.radians(4), math.radians(-2), math.radians(18)), (1, 1, 1)),
    (24, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
))
stash_action("KOTM_Parachute_Steer_Right", (
    (1, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
    (12, (0, 0, -0.05), (math.radians(4), math.radians(2), math.radians(-18)), (1, 1, 1)),
    (24, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
))
showcase = stash_action("KOTM_Parachute_Showcase", (
    (1, (0, 0, -2.1), (math.radians(18), 0, 0), (0.08, 0.08, 0.08)),
    (10, (0, 0, -0.8), (math.radians(10), 0, 0), (0.42, 0.28, 0.35)),
    (22, (0, 0, 0.12), (math.radians(-5), 0, 0), (1.08, 0.92, 0.86)),
    (32, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
    (46, (0, 0, 0), (math.radians(2), 0, math.radians(10)), (1, 1, 1)),
    (58, (0, 0, 0), (math.radians(2), 0, math.radians(-10)), (1, 1, 1)),
    (72, (0, 0, 0), (0, 0, 0), (1, 1, 1)),
))
root.animation_data.action = showcase

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -4.35))
bpy.context.object.name = "Preview_Floor"
bpy.context.object.data.materials.append(FLOOR)


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.object.camera_add(location=(7.4, -8.8, 2.2))
camera = bpy.context.object
camera.name = "Delivery_Camera"
camera.data.lens = 52
point_at(camera, (0, 0, -1.3))
scene.camera = camera

for name, light_type, location, energy, size in (
    ("Key_Light", "AREA", (-4, -4, 5), 1100, 5.0),
    ("Fill_Light", "AREA", (4, -1, 1.5), 700, 4.0),
    ("Rim_Light", "AREA", (0, 4, 4), 950, 3.0),
):
    bpy.ops.object.light_add(type=light_type, location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    point_at(light, (0, 0, -1))

scene.frame_set(36)
preview = artifacts.file(name="kotm_parachute_preview.png", media_type="image/png")
scene.render.filepath = preview.path
bpy.ops.render.render(write_still=True)
preview.publish()

result = {
    "cells": CELL_COUNT,
    "span_m": SPAN,
    "objects": len(scene.objects),
    "actions": [a.name for a in bpy.data.actions if a.name.startswith("KOTM_Parachute_")],
    "hand_sockets": ["HandSocket_L", "HandSocket_R"],
    "harness_socket": "HarnessSocket",
    "frame_range": [scene.frame_start, scene.frame_end],
}
