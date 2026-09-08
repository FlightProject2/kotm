"""Model the baseball cap asset in Blender and export it for Godot (run with bpy).

  python3 tools/blender/make_baseball_cap.py

Built parametrically rather than by hand so the proportions stay editable: a six-panel crown
(the panel ridges are a cosine modulation of the radius, fading out at the button), a cupped
peak that droops and curves down at the corners, a sweatband, and a rear adjuster strap.

Blender is Z-up with the peak pointing along -Y; the glTF exporter's Y-up conversion turns that
into +Z, which is the direction the mannequin faces in skeleton space, so the game needs no
corrective rotation. Writes assets/models/baseball_cap.glb and merges its socket into
assets/models/sockets.json (Cap_Socket is the centre of the head opening, i.e. where it rests).

Do NOT name this file inspect.py or similar: Blender's start-up imports stdlib modules by name.
"""
import bpy, bmesh, math, os, json
from mathutils import Vector

OUT = os.environ.get("GLB_OUT", "/home/user/kotm/assets/models")
NAME = "baseball_cap"

# head-fitting dimensions in metres (the mannequin's head measures about 0.19 m across)
RX = 0.098          # half width, ear to ear
RY = 0.107          # half depth, front to back
HZ = 0.085          # crown height above the opening
SEG = 36            # segments around
RINGS = 12          # rings from button to brim
PANEL_RIDGE = 0.022 # six-panel bulge as a fraction of the radius
PEAK_ARC = math.radians(68)
PEAK_REACH = 0.090
PEAK_DROP = 0.025
PEAK_CAMBER = 0.017
PEAK_THICK = 0.005
BAND_H = 0.026

bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgba, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


MAT_CROWN = material("CapCrown", (0.12, 0.17, 0.34, 1.0), 0.88)
MAT_PEAK = material("CapPeak", (0.10, 0.14, 0.29, 1.0), 0.82)
MAT_ACCENT = material("CapAccent", (0.86, 0.72, 0.33, 1.0), 0.60)


def add_object(name, verts, faces, mat, smooth=True):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    return obj


def solidify(obj, thickness, offset=-1.0):
    m = obj.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


def ridge(theta, phi):
    """Six-panel bulge, faded out at the button so the panels meet in a point."""
    return 1.0 + PANEL_RIDGE * math.cos(6.0 * theta) * math.sin(phi)


def crown_point(theta, phi, scale=1.0):
    """A point on the crown surface. phi runs 0 at the button to pi/2 at the brim."""
    # a fuller shoulder than a hemisphere: the crown stands up before it turns down to the brim
    s = math.sin(phi) ** 0.72
    r = ridge(theta, phi) * scale
    return Vector((RX * s * math.sin(theta) * r, RY * s * math.cos(theta) * r, HZ * math.cos(phi) ** 1.18))


# ---------------------------------------------------------------- crown
verts = [Vector((0.0, 0.0, HZ))]
faces = []
for i in range(1, RINGS + 1):
    phi = (i / RINGS) * (math.pi * 0.5)
    for j in range(SEG):
        verts.append(crown_point(2.0 * math.pi * j / SEG, phi))
for j in range(SEG):
    faces.append([0, 1 + (j + 1) % SEG, 1 + j])
for i in range(RINGS - 1):
    a = 1 + i * SEG
    b = a + SEG
    for j in range(SEG):
        j2 = (j + 1) % SEG
        faces.append([a + j, a + j2, b + j2, b + j])
crown = add_object("Crown", verts, faces, MAT_CROWN)
solidify(crown, 0.004)

# ---------------------------------------------------------------- peak
NU, NV = 26, 8
pv, pf = [], []
# The peak is a loft off the head's front arc: every rib runs straight forward (-Y), reaching
# PEAK_REACH at the centre and tapering to a lip at the corners. Ribs that never cross keep the
# surface free of the folds a radial fan produces, and the brim never sits wider than the head.
# The droop scales with how far a rib actually extends, so the corners stay level with the band.
for iu in range(NU + 1):
    u = -1.0 + 2.0 * iu / NU
    a = u * PEAK_ARC
    inner = Vector((-RX * math.sin(a), -RY * math.cos(a), 0.012))
    k = a * (math.pi * 0.5) / PEAK_ARC
    ext = PEAK_REACH * (0.08 + 0.92 * math.cos(k) ** 0.45)
    outer = inner + Vector((0.0, -ext, 0.0))
    for iv in range(NV + 1):
        v = iv / NV
        p = inner.lerp(outer, v)
        p.z -= (PEAK_DROP * v ** 1.7 + PEAK_CAMBER * (u * u) * v) * (ext / PEAK_REACH)
        pv.append(p)
for iu in range(NU):
    for iv in range(NV):
        a = iu * (NV + 1) + iv
        b = a + (NV + 1)
        pf.append([a, a + 1, b + 1, b])
peak = add_object("Peak", pv, pf, MAT_PEAK)
solidify(peak, PEAK_THICK)

# ---------------------------------------------------------------- panel seams
# Six stitched seams from the button to the brim, one down the centre front and one down the
# centre back, as narrow ribbons standing proud of the crown. The cosine bulge alone is only a
# couple of millimetres and reads as nothing at gameplay distance; the piping is what says "cap".
SEAM_HALF = math.radians(1.6)
SEAM_RINGS = 10
sev, sef = [], []
for panel in range(6):
    ts = panel * math.pi / 3.0
    base = len(sev)
    for i in range(SEAM_RINGS + 1):
        phi = 0.16 + (i / SEAM_RINGS) * (math.pi * 0.5 - 0.16)
        sev.append(crown_point(ts - SEAM_HALF, phi, 1.004))
        sev.append(crown_point(ts + SEAM_HALF, phi, 1.004))
    for i in range(SEAM_RINGS):
        a = base + i * 2
        sef.append([a, a + 1, a + 3, a + 2])
seams = add_object("Seams", sev, sef, MAT_ACCENT)
solidify(seams, 0.0016, offset=1.0)

# ---------------------------------------------------------------- sweatband
bv, bf = [], []
for j in range(SEG):
    theta = 2.0 * math.pi * j / SEG
    r = ridge(theta, math.pi * 0.5) * 1.012
    x, y = RX * math.sin(theta) * r, RY * math.cos(theta) * r
    bv.append(Vector((x, y, 0.014)))
    bv.append(Vector((x, y, 0.014 - BAND_H)))
for j in range(SEG):
    j2 = (j + 1) % SEG
    bf.append([j * 2, j2 * 2, j2 * 2 + 1, j * 2 + 1])
band = add_object("Sweatband", bv, bf, MAT_ACCENT)
solidify(band, 0.004)

# ---------------------------------------------------------------- rear adjuster strap
sv, sf = [], []
STRAP_ARC = math.radians(26)
NS = 8
for k in range(NS + 1):
    a = -STRAP_ARC + 2.0 * STRAP_ARC * k / NS
    r = ridge(a, math.pi * 0.5) * 1.022
    x, y = RX * math.sin(a) * r, RY * math.cos(a) * r
    sv.append(Vector((x, y, 0.022)))
    sv.append(Vector((x, y, -0.002)))
for k in range(NS):
    sf.append([k * 2, (k + 1) * 2, (k + 1) * 2 + 1, k * 2 + 1])
strap = add_object("Strap", sv, sf, MAT_ACCENT, smooth=False)
solidify(strap, 0.004)

# ---------------------------------------------------------------- button
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.0085, segments=14, ring_count=8, location=(0, 0, HZ + 0.003))
button = bpy.context.active_object
button.name = "Button"
button.data.materials.append(MAT_ACCENT)
bpy.ops.object.shade_smooth()

# ---------------------------------------------------------------- export
objs = [crown, peak, seams, band, strap, button]
pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
size = mx - mn
tris = sum(sum(len(pg.vertices) - 2 for pg in o.data.polygons) for o in objs)

for o in bpy.data.objects:
    o.select_set(o in objs)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, NAME + ".glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                          export_animations=False, export_skins=False, export_yup=True,
                          export_materials="EXPORT", export_image_format="AUTO")

# sockets are in glTF (Y-up) axes: (x, z, -y). The cap rests by its opening, which is the origin.
sockets_path = os.path.join(OUT, "sockets.json")
sockets = {}
if os.path.exists(sockets_path):
    with open(sockets_path) as f:
        sockets = json.load(f)
sockets[NAME] = {
    "Cap_Socket": [0.0, 0.0, 0.0],
    "_size_yup": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
    "_tris": tris,
}
with open(sockets_path, "w") as f:
    json.dump(sockets, f, indent=2)
print("BUILT %s  tris=%d  size_yup=%s  %d KB" % (NAME, tris, sockets[NAME]["_size_yup"], os.path.getsize(path) // 1024))
