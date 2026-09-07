"""Convert the studio's .blend assets to glTF for Godot (run with Blender's Python module: bpy).

  BLEND_SRC=<dir with .blend files> python3 tools/blender/convert_blends.py

For each file the root hierarchy is recentred (footprint centre at the origin, base on the
ground for vehicles, centre of mass for hand-held items), geometry-node/bevel modifiers are
applied by the exporter, and socket empties (Helmet_Socket, Backpack_Socket ...) are written to
assets/models/sockets.json so the game can attach models exactly where the artist placed them.
Do NOT name this file inspect.py or similar: Blender's start-up imports stdlib modules by name.
"""
import bpy, os, json, sys
from mathutils import Vector

SRC = os.environ.get("BLEND_SRC", "/root/.claude/uploads/a1244e25-7d30-5395-b674-6edf0cdbb7ee")
OUT = os.environ.get("GLB_OUT", "/home/user/kotm/assets/models")
# file-name fragment -> (output name, ground the base?)
TARGETS = {
    "AR75": ("ar75", False),
    "militarybackpack": ("military_backpack", False),
    "motorcyclehelmet": ("motorcycle_helmet", False),
    "Snowtruck": ("snow_truck", True),
    "Snowmobile": ("snowmobile", True),
}

def bounds(objs):
    pts = []
    for o in objs:
        if o.type == 'MESH':
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx

sockets = {}
os.makedirs(OUT, exist_ok=True)
for fname in sorted(os.listdir(SRC)):
    if not fname.endswith(".blend"):
        continue
    key = next((k for k in TARGETS if k in fname), None)
    if key is None:
        continue
    out_name, ground = TARGETS[key]
    bpy.ops.wm.open_mainfile(filepath=os.path.join(SRC, fname))
    # scene dressing (ground planes, cameras, lights) is not part of the asset
    for o in [o for o in bpy.data.objects if o.type in ('CAMERA', 'LIGHT') or o.name.lower().startswith(('ground', 'plane', 'floor'))]:
        bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    roots = [o for o in bpy.data.objects if o.parent is None and (o.type == 'MESH' or o.children)]
    mn, mx = bounds(meshes)
    centre = (mn + mx) * 0.5
    shift = Vector((-centre.x, -centre.y, -mn.z if ground else -centre.z))
    # move every root so the model sits at the origin (sockets move with their parents or alone)
    for o in bpy.data.objects:
        if o.parent is None:
            o.location = o.location + shift
    bpy.context.view_layer.update()
    # sockets: world transform after the shift, in glTF (Y-up) axes: (x, z, -y)
    for o in bpy.data.objects:
        if o.type == 'EMPTY' and 'socket' in o.name.lower():
            p = o.matrix_world.translation
            sockets.setdefault(out_name, {})[o.name] = [round(p.x, 4), round(p.z, 4), round(-p.y, 4)]
    mn2, mx2 = bounds(meshes)
    size = mx2 - mn2
    tris = sum(sum(len(pg.vertices) - 2 for pg in o.data.polygons) for o in meshes)
    sockets.setdefault(out_name, {})["_size_yup"] = [round(size.x, 3), round(size.z, 3), round(size.y, 3)]
    sockets[out_name]["_tris"] = tris
    for o in bpy.data.objects:
        o.select_set(o.type in ('MESH', 'EMPTY'))
    path = os.path.join(OUT, out_name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=False, export_skins=False, export_yup=True,
                              export_materials="EXPORT", export_image_format="AUTO")
    print("CONVERTED %s -> %s  tris=%d size_yup=%s  %d KB" % (fname, out_name, tris, sockets[out_name]["_size_yup"], os.path.getsize(path) // 1024))
with open(os.path.join(OUT, "sockets.json"), "w") as f:
    json.dump(sockets, f, indent=2)
print("SOCKETS", json.dumps(sockets))
