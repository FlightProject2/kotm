"""Build the supplied four-track snow truck for Godot, without editing its source.

Blender --background --python tools/blender/build_snow_truck.py [-- --render]
Set KOTM_TRUCK_SOURCE to relocate the supplied Snow-truck .blend.
The mesh stays at its authored size; Blender -Y / glTF +Z is forward.
"""
from pathlib import Path
import bpy, math, os, json, sys
from mathutils import Vector, Matrix

REPO = Path(__file__).resolve().parents[2]
SOURCE = Path(os.environ.get('KOTM_TRUCK_SOURCE', 'E:/Users/Scott/Documents/blender - king of the mountain assets/Snow-truck .blend'))
ART = REPO / 'art/vehicles'
OUT = REPO / 'assets/models/kotm/KOTM_SnowTruck.glb'
ART.mkdir(parents=True, exist_ok=True)
OUT.parent.mkdir(parents=True, exist_ok=True)
GROUND = .014510628
ROT = Matrix.Rotation(-math.pi / 2, 4, 'Z')
TRANS = Matrix.Translation((0, 0, GROUND)) @ ROT

def point(v): return TRANS @ Vector(v)

def empty(name, pos=(0, 0, 0), parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.empty_display_type = 'ARROWS'; o.empty_display_size = .07
    o.location = pos
    if parent: parent_keep(o, parent)
    return o

def parent_keep(o, p):
    bpy.context.view_layer.update()
    w = o.matrix_world.copy(); o.parent = p
    o.matrix_parent_inverse = Matrix.Identity(4); o.matrix_world = w
    bpy.context.view_layer.update()

def cube(name, pos, size, mat, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o=bpy.context.object; o.name=name; o.scale=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat: o.data.materials.append(mat)
    if parent: parent_keep(o,parent)
    return o

def center(o):
    return sum((o.matrix_world @ Vector(c) for c in o.bound_box), Vector()) / 8

def material(name, color, metallic=0, roughness=.5):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=color
    p.inputs['Metallic'].default_value=metallic; p.inputs['Roughness'].default_value=roughness
    p.inputs['Alpha'].default_value=color[3]
    if 'Weight' in p.inputs: p.inputs['Weight'].default_value=1
    m.diffuse_color=color
    return m

def finish_action(o, clip):
    a=o.animation_data.action; a.name=clip+'__'+o.name; a.use_fake_user=True
    for layer in a.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for k in curve.keyframe_points:k.interpolation='LINEAR'
    track=o.animation_data.nla_tracks.new(); track.name=clip
    track.strips.new(clip, 1, a); o.animation_data.action=None

def animate(o, clip, frames, fn, paths):
    rest=o.matrix_basis.copy()
    for f in range(frames+1):
        fn(f/frames)
        for path in paths:o.keyframe_insert(path,frame=f+1)
    finish_action(o,clip); o.matrix_basis=rest

def convex_hull(points):
    pts=sorted(set(points))
    def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lo=[]; hi=[]
    for p in pts:
        while len(lo)>1 and cross(lo[-2],lo[-1],p)<=0:lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi)>1 and cross(hi[-2],hi[-1],p)<=0:hi.pop()
        hi.append(p)
    return list(reversed(lo[:-1]+hi[:-1])) # clockwise: upper run travels forward

def path_sampler(pts):
    lengths=[(pts[(i+1)%len(pts)]-p).length for i,p in enumerate(pts)]
    total=sum(lengths)
    def sample(distance):
        d=distance%total
        for i,length in enumerate(lengths):
            if d<=length:
                t=(pts[(i+1)%len(pts)]-pts[i]).normalized()
                return pts[i]+t*d,t
            d-=length
        return pts[0],(pts[1]-pts[0]).normalized()
    return total,sample

def orient_tread(o,pos,tangent):
    x=Vector((1,0,0)); y=-tangent; z=x.cross(y).normalized()
    m=Matrix((x,y,z)).transposed().to_4x4();m.translation=pos
    o.matrix_basis=m

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
sc=bpy.context.scene; sc.frame_start=1; sc.frame_end=61; sc.render.fps=30
source_meshes=[o for o in bpy.data.objects if o.type=='MESH' and o.name!='Ground']
source_world={o.name:o.matrix_world.copy() for o in source_meshes}
source_tracks={k:bpy.data.objects['Track_'+k].matrix_world.copy() for k in ['FL','FR','RL','RR']}
for o in source_meshes:
    o.data=o.data.copy();o.data.transform(TRANS @ source_world[o.name])
    o.parent=None;o.matrix_parent_inverse=Matrix.Identity(4);o.matrix_world=Matrix.Identity(4)
    o.animation_data_clear();o.hide_viewport=False;o.hide_render=False;o.hide_set(False)
for o in list(bpy.data.objects):
    if o not in source_meshes:bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
root=empty('KOTM_SnowTruck');root['source_asset']=SOURCE.name
root['forward_axis']='Blender -Y / Godot +Z';root['meters_per_unit']=1.0
body=empty('BodySuspension',parent=root)
for o in source_meshes:parent_keep(o,body)

# Ordinary alpha glass survives glTF import; transmission-only glass hides the driver
# in renderers without screen-space refraction. Keep the original window openings.
glass=material('CabinGlass_Clear',(.55,.74,.80,.095),.05,.15)
p=glass.node_tree.nodes.get('Principled BSDF');p.inputs['Transmission Weight'].default_value=0
glass.surface_render_method='BLENDED';glass.use_backface_culling=True
for o in source_meshes:
    if o.name.startswith('Glass_'):
        o.data.materials.clear();o.data.materials.append(glass)
    for m in o.data.materials:
        if m and m.use_nodes:
            p=m.node_tree.nodes.get('Principled BSDF')
            if p and 'Weight' in p.inputs:p.inputs['Weight'].default_value=1

# Cut the actual door panels out of the shell, preserving their authored shape.
shell=bpy.data.objects['BodyShell']
doors=[]
for side,sign in [('L',1),('R',-1)]:
    cutter=cube('DoorCut',point((-.10,.865*sign,1.435)),(.24,1.27,1.23),None)
    panel=shell.copy();panel.data=shell.data.copy();sc.collection.objects.link(panel);panel.name='DoorShell_'+side
    for obj,operation in [(panel,'INTERSECT'),(shell,'DIFFERENCE')]:
        bpy.context.view_layer.objects.active=obj
        mod=obj.modifiers.new('Separate operable door','BOOLEAN');mod.operation=operation;mod.solver='EXACT';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    pivot=empty('DoorPivot_'+side,point((.535,.865*sign,1.05)),body);doors.append((pivot,sign))
    parent_keep(panel,pivot)
    for base in ['Glass_SideF','DoorCard','Handle','Armrest','Mirror','MirrorArm']:
        obj=bpy.data.objects.get(base+('' if sign==1 else '.001'))
        if obj:parent_keep(obj,pivot)

# Steering wheel spins about its oblique column, while the sockets follow it.
bpy.data.objects['SteeringWheel'].name='SteeringWheel_Rim'
steer=empty('SteeringWheel',point((-.22,.45,1.50)),body)
steer.rotation_euler.x=-math.radians(23)
for name in ['SteeringWheel_Rim','WheelHub']:
    if bpy.data.objects.get(name):parent_keep(bpy.data.objects[name],steer)

fit={'coordinate_system':'Blender Z up, -Y forward, metres','driver_root':[.45,.43,0],
     'seat_surface_z':1.03+GROUND,'pelvis_z':1.15+GROUND,
     'hand_grips':{'L':[.60,.265,1.565+GROUND],'R':[.30,.265,1.565+GROUND]},
     'foot_rests':{'L':[.55,-.20,.87+GROUND],'R':[.35,-.20,.87+GROUND]}}
seat=empty('SeatDriver',fit['driver_root'],body)
seat['origin_semantics']='Avatar ground/root anchor; KOTM_Truck_Seated supplies pelvis and limbs.'
seat['character_clip']='KOTM_Truck_Seated'
empty('SeatPassenger',(-.45,.43,0),body)
empty('SeatSurface',(.45,.43,fit['seat_surface_z']),body)
for side in ['L','R']:
    empty('HandGrip_'+side,fit['hand_grips'][side],steer)
    empty('FootRest_'+side,fit['foot_rests'][side],body)
empty('DriverExit',point((-.40,1.55,0)),root)
empty('PassengerExit',point((-.40,-1.55,0)),root)

# Add two rubber blades, hinged at the lower windscreen edge.
wipers=[];rubber=bpy.data.materials['Rubber']
for side,sign in [('L',1),('R',-1)]:
    pivot=empty('WiperPivot_'+side,point((.478,.33*sign,1.555)),body)
    pivot.rotation_euler.x=-math.radians(32)
    blade=cube('WiperBlade_'+side,(0,0,0),(.023,.015,.31),rubber)
    blade.parent=pivot;blade.matrix_parent_inverse=Matrix.Identity(4);blade.location=(.085,0,.17)
    arm=cube('WiperArm_'+side,(0,0,0),(.014,.014,.20),bpy.data.materials['Steel'])
    arm.parent=pivot;arm.matrix_parent_inverse=Matrix.Identity(4);arm.location=(.04,0,.075);arm.rotation_euler.y=.48
    wipers.append(pivot)

track_wheels=[];track_steer=[];treads=[];track_mounts=[]
for key in ['FL','FR','RL','RR']:
    source_mat=source_tracks[key]
    wheel_center=point(source_mat @ Vector((.05,0,.8)))
    if key.startswith('F'):
        steering=empty('WheelSteer_'+key,wheel_center,root);track_steer.append(steering)
        track_mounts.append(steering)
        assembly=empty('TrackAssembly_'+key,(0,0,0),steering)
    else:
        assembly=empty('TrackAssembly_'+key,(0,0,0),root);track_mounts.append(assembly)
    # The neutral source tracks were pitched. Reuse wheel centres and build a belt
    # wrapping the idlers and drive sprocket, including their visible outer edges.
    src_points=[]
    for x,z,r in [(-.55,.16,.166),(.05,.8,.195),(.55,.16,.166)]:
        for i in range(48):
            a=2*math.pi*i/48;src_points.append((x+r*math.cos(a),z+r*math.sin(a)))
    hull=convex_hull(src_points)
    pts=[point(source_mat @ Vector((x,0,z))) for x,z in hull]
    total,sample=path_sampler(pts)
    for i,pos in enumerate(pts):empty('TrackPath_'+key+'_%03d'%i,pos,assembly)
    assembly['path_length_m']=total;assembly['tread_count']=32
    # Closed belt skin, with linked solid lugs above it.
    vertices=[];faces=[]
    for i,pos in enumerate(pts):
        tangent=(pts[(i+1)%len(pts)]-pts[(i-1)%len(pts)]).normalized()
        outward=Vector((1,0,0)).cross(-tangent).normalized()
        for lateral,depth in [(-.205,-.018),(.205,-.018),(-.205,.008),(.205,.008)]:
            vertices.append(pos+Vector((lateral,0,0))+outward*depth)
    for i in range(len(pts)):
        j=(i+1)%len(pts)
        faces.extend([(4*i,4*j,4*j+1,4*i+1),(4*i+2,4*i+3,4*j+3,4*j+2),
                      (4*i,4*i+2,4*j+2,4*j),(4*i+1,4*j+1,4*j+3,4*i+3)])
    mesh=bpy.data.meshes.new('ContinuousBelt_'+key);mesh.from_pydata(vertices,[],faces);mesh.materials.append(rubber)
    belt=bpy.data.objects.new('TrackBelt_'+key,mesh);sc.collection.objects.link(belt);parent_keep(belt,assembly)
    for o in list(bpy.data.objects):
        if not o.name.startswith('Track_'+key+'_'):continue
        if o.name.endswith(('_Belt','_Lugs')):bpy.data.objects.remove(o,do_unlink=True);continue
        if any(label in o.name for label in ['Bogie','Idler','Sprocket']):
            pivot=empty('TrackWheel_'+key+'_'+o.name.split('_',2)[2].replace('.','_'),center(o),assembly)
            parent_keep(o,pivot);radius=.18 if 'Sprocket' in o.name else (.15 if 'Idler' in o.name else .105)
            pivot['radius_m']=radius;track_wheels.append((pivot,radius,total))
        else:parent_keep(o,assembly)
    for i in range(32):
        pos,tangent=sample(total*i/32)
        tread=cube('TrackTread_'+key+'_%03d'%i,(0,0,0),(.43,.060,.022),rubber)
        tread.parent=assembly;tread.matrix_parent_inverse=Matrix.Identity(4)
        # assembly has identity world transform in the neutral rig.
        orient_tread(tread,pos,tangent)
        treads.append((tread,total,sample,total*i/32))

# Game-ready transform animation clips, grouped by NLA track name on export.
for o,total,sample,offset in treads:
    def run(t,o=o,total=total,sample=sample,offset=offset):
        p,tangent=sample(offset+total*t);orient_tread(o,p,tangent)
    animate(o,'KOTM_Truck_Drive',60,run,['location','rotation_euler'])
for o,r,total in track_wheels:
    animate(o,'KOTM_Truck_Drive',60,lambda t,o=o,r=r,total=total:setattr(o.rotation_euler,'x',total*t/r),['rotation_euler'])
for o in track_steer:
    animate(o,'KOTM_Truck_Steer',60,lambda t,o=o:setattr(o.rotation_euler,'z',.35*math.sin(2*math.pi*t)),['rotation_euler'])
rest=steer.rotation_euler.copy()
animate(steer,'KOTM_Truck_Steer',60,lambda t:setattr(steer.rotation_euler,'y',-1.5*math.sin(2*math.pi*t)),['rotation_euler'])
for pivot,sign in doors:
    animate(pivot,'KOTM_Truck_Doors',60,lambda t,o=pivot,s=sign:setattr(o.rotation_euler,'z',-s*1.05*math.sin(math.pi*t)**2),['rotation_euler'])
for pivot in wipers:
    animate(pivot,'KOTM_Truck_Wipers',48,lambda t,o=pivot:setattr(o.rotation_euler,'y',.80*math.sin(math.pi*t)**2),['rotation_euler'])
animate(body,'KOTM_Truck_Suspension',60,lambda t:setattr(body.location,'z',.022*math.sin(4*math.pi*t)),['location'])
sc.frame_set(1);bpy.context.view_layer.update()
root['clips']='KOTM_Truck_Drive;KOTM_Truck_Steer;KOTM_Truck_Doors;KOTM_Truck_Wipers;KOTM_Truck_Suspension'
points=[o.matrix_world @ Vector(v) for o in bpy.data.objects if o.type=='MESH' for v in o.bound_box]
track_ground_adjust=-min(p.z for p in points)
for o in track_mounts:o.location.z+=track_ground_adjust
bpy.context.view_layer.update()
points=[o.matrix_world @ Vector(v) for o in bpy.data.objects if o.type=='MESH' for v in o.bound_box]
lo=Vector([min(p[i] for p in points) for i in range(3)]);hi=Vector([max(p[i] for p in points) for i in range(3)])
fit['bounds_blender']={'min':list(lo),'max':list(hi)}
fit['driver_root_blender']=fit['driver_root']
fit['hand_grips_blender']=fit['hand_grips']
fit['foot_rests_blender']=fit['foot_rests']
fit['source']=str(SOURCE);fit['clip']='KOTM_Truck_Seated'
(ART/'truck_fit.json').write_text(json.dumps(fit,indent=2)+'\n')
for o in bpy.data.objects:o.select_set(o.type in {'MESH','EMPTY'})
bpy.context.view_layer.objects.active=root
kwargs=dict(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True,
            export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',
            export_frame_range=False,export_force_sampling=True,export_extras=True,
            export_materials='EXPORT',export_skins=False,export_cameras=False,export_lights=False)
bpy.ops.export_scene.gltf(**kwargs)
sc.render.engine='CYCLES';sc.cycles.samples=24
sc.world.color=(.30,.30,.30)
floor_mat=material('Preview_Snow',(.68,.74,.79,1),0,.9)
floor=cube('Preview_Ground',(0,0,-.08),(20,20,.1),floor_mat);floor.hide_set(True)
for name,loc,power,size in [('Preview_Key',(4,-4,6),2000,5),('Preview_Fill',(-4,-1,4),1400,4),('Preview_Rim',(0,5,5),1800,4)]:
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(name,d);sc.collection.objects.link(o);o.location=loc
    o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
cam_data=bpy.data.cameras.new('Preview_Camera');cam=bpy.data.objects.new('Preview_Camera',cam_data);sc.collection.objects.link(cam)
cam.location=(5,-6,3.6);cam.rotation_euler=(Vector((0,0,1.1))-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.lens=44;sc.camera=cam
sc.render.resolution_x=1200;sc.render.resolution_y=900;sc.render.resolution_percentage=100
sc.render.filepath=str(ART/'KOTM_SnowTruck_preview.png')
sc.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'KOTM_SnowTruck.blend'))
if '--render' in sys.argv:bpy.ops.render.render(write_still=True)
print('TRUCK_BUILT',json.dumps({'glb':str(OUT),'bytes':OUT.stat().st_size,'fit':fit}))
