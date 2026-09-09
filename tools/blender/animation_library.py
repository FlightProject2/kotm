"""Human-cadence, baked in-place locomotion for KOTM's anatomy-fitted rig.

Usage: actions = create_animations(bpy.data.objects['KOTM_Character_Rig'])

Sampling solves anatomical knee planes and heel/ball foot contacts. The
resulting actions animate deform-bone local transforms only: no IK solver,
custom property, driver, or control animation is required in the game engine.
The master stays fixed; the game moves the character controller. Jump includes
vertical pelvis/feet motion, but no root translation. Jump is a one-shot;
other clips loop with an identical endpoint sample.
"""
import math
import bpy
from mathutils import Vector, Matrix, Quaternion

FPS = 30
SPECS = {
    'Idle': {'frames': 90, 'loop': True, 'speed': 0.0},
    'Walk_in_place': {'frames': 28, 'loop': True, 'speed': 1.5, 'stance': .57},
    'Jog_in_place': {'frames': 22, 'loop': True, 'speed': 3.5, 'stance': .31},
    'Run_in_place': {'frames': 18, 'loop': True, 'speed': 6.5, 'stance': .225},
    'Crouch_idle': {'frames': 90, 'loop': True, 'speed': 0.0},
    'Jump_in_place': {'frames': 42, 'loop': False, 'speed': 0.0},
    'Prone_idle': {'frames': 60, 'loop': True, 'speed': 0.0},
    'Prone_crawl': {'frames': 36, 'loop': True, 'speed': 1.0},
    'Prone_roll_l': {'frames': 28, 'loop': False, 'speed': 0.0},
    'Prone_roll_r': {'frames': 28, 'loop': False, 'speed': 0.0},
}
ACTION_NAMES = {'Idle': 'KOTM_Idle', 'Walk_in_place': 'KOTM_Walk', 'Jog_in_place': 'KOTM_Jog',
                'Run_in_place': 'KOTM_Run', 'Crouch_idle': 'KOTM_Crouch_Idle',
                'Jump_in_place': 'KOTM_Jump', 'Prone_idle': 'KOTM_Prone_Idle',
                'Prone_crawl': 'KOTM_Prone_Crawl', 'Prone_roll_l': 'KOTM_Prone_Roll_L',
                'Prone_roll_r': 'KOTM_Prone_Roll_R'}


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t*t*(3-2*t)


def _lerp(a, b, t):
    return a+(b-a)*t


def _curve(t, points):
    """Piecewise cubic Hermite curve with explicit value/phase-derivative keys."""
    if t <= points[0][0]:return points[0][1]
    for a,b in zip(points,points[1:]):
        if t <= b[0]:
            span=b[0]-a[0];u=(t-a[0])/span
            return ((2*u**3-3*u*u+1)*a[1]+(u**3-2*u*u+u)*span*a[2]
                    +(-2*u**3+3*u*u)*b[1]+(u**3-u*u)*span*b[2])
    return points[-1][1]


def _reset(rig):
    for bone in rig.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_mode = 'QUATERNION'
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)
    for side in ('l', 'r'):
        rig['arm_ik.'+side] = 0.0
        rig['leg_ik.'+side] = 0.0
    rig.update_tag()


def _rotate_world(rig, name, angles):
    """Rest-space X/Y/Z rotations, in degrees, converted into the bone frame."""
    q = Quaternion((0, 0, 1), math.radians(angles[2])) @ Quaternion((0, 1, 0), math.radians(angles[1])) @ Quaternion((1, 0, 0), math.radians(angles[0]))
    rest = rig.data.bones[name].matrix_local.to_quaternion()
    rig.pose.bones[name].rotation_quaternion = rest.inverted() @ q @ rest


def _local_x(rig, name, angle):
    rig.pose.bones[name].rotation_quaternion = Quaternion((1, 0, 0), math.radians(angle))


def _translate_world(rig, name, delta):
    bone = rig.pose.bones[name]
    bone.location = bone.bone.matrix_local.to_3x3().inverted() @ Vector(delta)


def _state(rig):
    body = max((o for o in rig.children if o.type == 'MESH' and 'body' in o.name.lower()),
               key=lambda o: len(o.data.vertices), default=None)
    feet = {}
    for side in ('l', 'r'):
        sign = 1 if side == 'l' else -1
        foot = rig.data.bones['foot.'+side]
        ankle = foot.head_local.copy()
        ball = foot.tail_local.copy()
        forward = ball-ankle
        forward.z = 0
        forward.normalize()
        lateral = Vector((0, 0, 1)).cross(forward).normalized()
        ids = [v.index for v in body.data.vertices
               if (body.matrix_world@v.co).z < .071 and (body.matrix_world@v.co).x*sign > .07] if body else []
        foot_vertices = [body.matrix_world@body.data.vertices[i].co for i in ids] if body else []
        heel_y = max((p.y for p in foot_vertices), default=ankle.y+.042)
        feet[side] = {'ankle': ankle, 'ball': ball, 'lateral': lateral,
                      'heel': Vector((ankle.x, heel_y-.010, .005)),
                      'rotation': foot.matrix_local.to_quaternion(), 'indices': ids}
    return {'rig': rig, 'body': body, 'feet': feet, 'contacts': {}, 'targets': {}, 'foot_matrices': {}, 'solve_errors': {}}


def _leg_frame(axis, lateral):
    y=axis.normalized();x=(lateral-y*lateral.dot(y)).normalized();z=x.cross(y).normalized()
    return Matrix((x,y,z)).transposed()


def _solve_leg(state, side, matrix):
    """Fixed-length two-bone solve with the actual kneecap facing forward.

    The base mesh's almost straight leg has an arbitrary tiny rest-plane bend.
    Using that bend as a roll reference twists the thighs. The anatomical rest
    knee hinge is the lateral X axis, independent of those tiny offsets.
    """
    rig=state['rig'];bpy.context.view_layer.update()
    thigh=rig.pose.bones['thigh.'+side];calf=rig.pose.bones['calf.'+side]
    hip=thigh.head.copy();target=matrix.translation.copy();v=target-hip
    requested=v.length;direction=v.normalized();a=thigh.bone.length;b=calf.bone.length
    distance=max(abs(a-b)+.00001,min(a+b-.00001,requested))
    reached=hip+direction*distance
    pole=Vector(((1 if side=='l' else -1)*state.get('knee_width',.13),-.60,hip.z-.34))
    bend=pole-hip; bend-=direction*bend.dot(direction);bend.normalize()
    along=(a*a-b*b+distance*distance)/(2*distance)
    knee=hip+direction*along+bend*math.sqrt(max(0,a*a-along*along))
    axes=[(knee-hip).normalized(),(reached-knee).normalized()]
    lateral=axes[0].cross(axes[1]).normalized()
    if lateral.x<0:lateral.negate()
    for bone,axis,origin in [(thigh,axes[0],hip),(calf,axes[1],knee)]:
        rest_axis=(bone.bone.tail_local-bone.bone.head_local).normalized()
        q=_leg_frame(axis,lateral)@_leg_frame(rest_axis,Vector((1,0,0))).transposed()@bone.bone.matrix_local.to_3x3()
        transform=q.to_4x4();transform.translation=origin;bone.matrix=transform
        bpy.context.view_layer.update()
    terminal=matrix.copy();terminal.translation=reached;rig.pose.bones['foot.'+side].matrix=terminal
    state['solve_errors'][side]=(reached-target).length
    state['targets'][side]=target
    state['foot_matrices'][side]=matrix.copy()
    bpy.context.view_layer.update()


def _foot(state, side, x, y_offset=0, lift=0, pitch=0, toe_counter=False, toe_out=6):
    rig, f = state['rig'], state['feet'][side]
    ankle = f['ankle'].copy()
    ankle.x = x
    ankle.y += y_offset
    ankle.z += lift
    sign=1 if side=='l' else -1
    source_forward=f['ball']-f['ankle']
    yaw=Quaternion((0,0,1),math.radians(sign*toe_out)-math.atan2(source_forward.x,-source_forward.y))
    rotation = Quaternion(yaw@f['lateral'], math.radians(pitch))
    # Roll around the ball during push-off, and around the heel on contact.
    # This retains the physical contact point instead of spinning at the ankle.
    pivot = f['ball'] if pitch >= 0 else f['heel']
    pivot=f['ankle']+yaw@(pivot-f['ankle'])
    delta = (pivot + rotation@(f['ankle']-pivot)) - f['ankle']
    ankle += delta
    matrix = Matrix.LocRotScale(ankle, rotation@yaw@f['rotation'], Vector((1, 1, 1)))
    if toe_counter and pitch > 0:
        rest = rig.data.bones['ball.'+side].matrix_local.to_quaternion()
        rig.pose.bones['ball.'+side].rotation_quaternion = rest.inverted() @ Quaternion(f['lateral'], math.radians(-pitch*float(toe_counter))) @ rest
    _solve_leg(state,side,matrix)


def _hands(rig, curl=10):
    for side in ('l', 'r'):
        for finger in ('thumb', 'index', 'middle', 'ring', 'pinky'):
            for segment in (1, 2, 3):
                _local_x(rig, f'{finger}_{segment:02d}.{side}', curl*.4 if finger == 'thumb' else curl)


def _idle(state, t, crouch=False):
    rig = state['rig']
    breath = math.sin(math.tau*t)
    if crouch:
        _translate_world(rig, 'pelvis', (0, .068, -.247+.0025*breath))
        _rotate_world(rig, 'pelvis', (8, 0, 0))
        _rotate_world(rig, 'spine_01', (5+.35*breath, 0, 0))
        _rotate_world(rig, 'chest', (4, 0, 0))
        _rotate_world(rig, 'head', (-9, 0, 0))
    else:
        _translate_world(rig, 'pelvis', (.002*math.sin(math.tau*t), 0, -.022+.0018*breath))
        _rotate_world(rig, 'spine_02', (-.45*breath, 0, 0))
        _rotate_world(rig, 'chest', (.65*breath, 0, 0))
    for side in ('l', 'r'):
        sign = 1 if side == 'l' else -1
        _rotate_world(rig, 'upperarm.'+side, (-19 if crouch else -3, sign*13, 0))
        _local_x(rig, 'lowerarm.'+side, -58 if crouch else -13)
        _foot(state, side, sign*(.15 if crouch else .145))
        state['contacts'][side] = True
    _hands(rig, 24 if crouch else 14)


def _gait(state, t, clip='Walk_in_place'):
    rig=state['rig'];spec=SPECS[clip];stance=spec['stance']
    running=clip=='Run_in_place';jogging=clip=='Jog_in_place';airborne=running or jogging
    # A planted contact travels backwards at exactly controller speed.
    # Flight supplies the remaining world travel without cycling the legs faster.
    travel=spec['speed']*spec['frames']/FPS*stance
    front=-.355 if running else -.355 if jogging else -.388
    back=front+travel;phase=t%.5
    if airborne:
        low=.799 if running else .823;strike=.862 if running else .877
        push=.849 if running else .865;apex=.894 if running else .901
        hip_z=_curve(phase,[(0,strike,-.34),(.48*stance,low,0),
                            (stance,push,.34),((stance+.5)/2,apex,0),(.5,strike,-.34)])
        # Leave extension reserve through terminal swing and toe-off. This is
        # an authored hip trajectory adjustment, not a clamped/stretched leg.
        hip_z-=.020 if running else .010
        lean=8 if running else 5
        _translate_world(rig,'pelvis',(.010*math.sin(math.tau*t),.018,hip_z-.946))
        _rotate_world(rig,'pelvis',(lean,1.4*math.sin(math.tau*t),5*math.cos(math.tau*t)))
        _rotate_world(rig,'spine_01',(3 if running else 2,0,-2*math.cos(math.tau*t)))
        _rotate_world(rig,'chest',(1,0,-5*math.cos(math.tau*t)))
        _rotate_world(rig,'head',(-lean,0,2*math.cos(math.tau*t)))
    else:
        _translate_world(rig,'pelvis',(.022*math.sin(math.tau*t),.014,-.053-.018*math.cos(4*math.pi*t)))
        _rotate_world(rig,'pelvis',(1.5,2.0*math.sin(math.tau*t),4*math.cos(math.tau*t)))
        _rotate_world(rig,'spine_02',(1,0,-2*math.cos(math.tau*t)))
        _rotate_world(rig,'chest',(0,0,-3*math.cos(math.tau*t)))
        _rotate_world(rig,'head',(-1,0,1.7*math.cos(math.tau*t)))
    state['knee_width']=.12
    for side,sign in [('l',1),('r',-1)]:
        p=(t+(0 if side=='l' else .5))%1
        contact=p<=stance
        strike_pitch=-5 if running else -7 if jogging else -12
        push_pitch=53 if running else 43 if jogging else 29
        if contact:
            u=p/stance;y=front+travel*u;lift=0
            pitch=strike_pitch*(1-_smooth(u/.24))+push_pitch*_smooth((u-.48)/.52)
            toe_counter=_smooth((u-.36)/.16)
        else:
            u=(p-stance)/(1-stance)
            velocity=spec['speed']*spec['frames']/FPS*(1-stance)
            if airborne:
                # Heel folds toward the seat first, then the knee advances;
                # the lower leg extends and retracts before ground contact.
                y=_curve(u,[(0,back,velocity),(.16,back+.075,0),
                            (.51,.035,-1.55),(.80,front-.105,0),(1,front,velocity)])
                height=.40 if running else .285
                lift=_curve(u,[(0,0,.75),(.27,height,0),(.53,height*.84,-.45),
                               (.83,.075,-.68),(1,0,-.55)])
                pitch=_curve(u,[(0,push_pitch,0),(.32,18,0),(.66,-12,0),(1,strike_pitch,0)])
            else:
                y=_curve(u,[(0,back,velocity),(.18,back+.025,0),(.78,front-.032,0),(1,front,velocity)])
                lift=_curve(u,[(0,0,.32),(.35,.105,0),(.75,.07,-.22),(1,0,-.24)])
                pitch=_curve(u,[(0,push_pitch,0),(.42,4,-35),(1,strike_pitch,0)])
            toe_counter=1-_smooth(u/.22)
        _foot(state,side,sign*(.095 if airborne else .112),y,max(0,lift),pitch,toe_counter,4 if airborne else 7)
        state['contacts'][side]=contact
        swing=math.cos(math.tau*(p-.05))
        # 2016 survival-game cadence: elbows remain bent, hands pass close to the
        # lower ribs, and each arm counters the opposite knee without flaring.
        arm_swing = (31 if running else 25 if jogging else 19) * swing - (5 if running else 3)
        _rotate_world(rig,'clavicle.'+side,(0,sign*(2.2 if running else 1.2),-sign*2.0*swing))
        _rotate_world(rig,'upperarm.'+side,(arm_swing,sign*(9 if airborne else 10),-sign*3))
        _local_x(rig,'lowerarm.'+side,-84-5*swing if running else -70-7*swing if jogging else -24-5*swing)
        _local_x(rig,'hand.'+side,2*math.sin(math.tau*p))
    _hands(rig,34 if airborne else 18)


def _jump(state, t):
    rig = state['rig']
    flight = .28 <= t <= .80
    if t < .16:
        amount = _smooth(t/.16)
        height, squat, arm = _lerp(-.022, -.19, amount), amount, _lerp(-3, 21, amount)
    elif t < .28:
        amount = _smooth((t-.16)/.12)
        height, squat, arm = _lerp(-.19, 0, amount), 1-amount, _lerp(21, -80, amount)
    elif flight:
        u = (t-.28)/.52
        height = .34*4*u*(1-u)
        squat = 0
        arm = -80-23*math.sin(math.pi*u)
    elif t < .89:
        amount = _smooth((t-.80)/.09)
        height, squat, arm = _lerp(0, -.15, amount), amount, _lerp(-80, -18, amount)
    else:
        amount = _smooth((t-.89)/.11)
        height, squat, arm = _lerp(-.15, -.022, amount), 1-amount, _lerp(-18, -3, amount)
    _translate_world(rig, 'pelvis', (0, .045*squat, height))
    _rotate_world(rig, 'pelvis', (5*squat, 0, 0))
    _rotate_world(rig, 'spine_01', (5*squat, 0, 0))
    _rotate_world(rig, 'head', (-6*squat, 0, 0))
    for side in ('l', 'r'):
        sign = 1 if side == 'l' else -1
        if flight:
            u = (t-.28)/.52
            tuck = math.sin(math.pi*u)**2
            pitch=20*(1-_smooth(u/.25))+6*math.sin(math.pi*u)-10*_smooth((u-.65)/.35)
            _foot(state, side, sign*.13, .045*tuck, height+.10*tuck, pitch,1-_smooth(u/.12))
        else:
            pitch=20*_smooth((t-.20)/.08) if t<.28 else -10*(1-_smooth((t-.80)/.05)) if t>=.80 else 0
            _foot(state, side, sign*.13,0,0,pitch,pitch>0)
        state['contacts'][side] = not flight
        _rotate_world(rig, 'upperarm.'+side, (arm, sign*13, 0))
        _local_x(rig, 'lowerarm.'+side, -13-15*math.sin(math.pi*t)**2)
    _hands(rig, 16)


def _solve_chain(rig, upper_name, lower_name, terminal_name, target, pole):
    """Place a two-bone limb in armature space while retaining the rig's twist."""
    bpy.context.view_layer.update()
    upper = rig.pose.bones[upper_name]
    lower = rig.pose.bones[lower_name]
    start = upper.head.copy()
    vector = Vector(target) - start
    requested = vector.length
    direction = vector.normalized()
    a, b = upper.bone.length, lower.bone.length
    distance = max(abs(a-b)+.00001, min(a+b-.00001, requested))
    reached = start + direction * distance
    bend = Vector(pole) - start
    bend -= direction * bend.dot(direction)
    if bend.length_squared < .000001:
        bend = Vector((1, 0, 0))
    bend.normalize()
    along = (a*a-b*b+distance*distance)/(2*distance)
    joint = start + direction*along + bend*math.sqrt(max(0, a*a-along*along))
    axes = ((joint-start).normalized(), (reached-joint).normalized())
    normal = axes[0].cross(axes[1]).normalized()
    if normal.length_squared < .000001:
        normal = upper.bone.matrix_local.to_3x3().col[0].normalized()
    for bone, axis, origin in ((upper, axes[0], start), (lower, axes[1], joint)):
        rest_axis = (bone.bone.tail_local-bone.bone.head_local).normalized()
        rest_normal = bone.bone.matrix_local.to_3x3().col[0].normalized()
        rotation = _leg_frame(axis, normal) @ _leg_frame(rest_axis, rest_normal).transposed() @ bone.bone.matrix_local.to_3x3()
        matrix = rotation.to_4x4()
        matrix.translation = origin
        bone.matrix = matrix
        bpy.context.view_layer.update()
    hand = rig.pose.bones[terminal_name]
    matrix = hand.matrix.copy()
    matrix.translation = reached
    hand.matrix = matrix
    bpy.context.view_layer.update()


def _prone(state, t, crawling=False, tucked=False):
    """Grounded chest-down posture with alternating elbow-and-knee crawl."""
    rig = state['rig']
    breath = math.sin(math.tau*t)
    sway = math.sin(math.tau*t)
    _translate_world(rig, 'pelvis', ((.020*sway if crawling else 0), .035, -.605+.008*abs(sway)))
    _rotate_world(rig, 'pelvis', (86, (3.5*sway if crawling else 0), (2.0*math.cos(math.tau*t) if crawling else 0)))
    _rotate_world(rig, 'spine_01', (-3+.8*breath, 0, 0))
    _rotate_world(rig, 'spine_02', (5+.8*breath, 0, 0))
    _rotate_world(rig, 'chest', (5, 0, 0))
    _rotate_world(rig, 'neck_01', (-7, 0, 0))
    _rotate_world(rig, 'head', (-12, 0, 0))
    bpy.context.view_layer.update()

    pelvis = rig.pose.bones['pelvis'].head.copy()
    for side, sign in (('l', 1), ('r', -1)):
        phase = (t + (0 if side == 'l' else .5)) % 1
        wave = math.cos(math.tau*phase)
        if tucked:
            hand_target = (sign*.22, pelvis.y-.48, .25)
            elbow_pole = (sign*.42, pelvis.y-.18, .25)
        else:
            hand_target = (sign*(.24+.025*wave), pelvis.y-.78-.20*wave if crawling else pelvis.y-.82, .16+.025*max(0,-wave))
            elbow_pole = (sign*.46, pelvis.y-.34, .18)
        _solve_chain(rig, 'upperarm.'+side, 'lowerarm.'+side, 'hand.'+side, hand_target, elbow_pole)
        ankle_y = pelvis.y+.72-.18*wave if crawling else pelvis.y+.76
        ankle_z = .13+.055*max(0,wave) if crawling else .13
        _solve_chain(rig, 'thigh.'+side, 'calf.'+side, 'foot.'+side,
                     (sign*.17, ankle_y, ankle_z), (sign*.29, pelvis.y+.32, .12))
        _local_x(rig, 'ball.'+side, -9)
    _hands(rig, 28 if tucked else 18)


def _prone_roll(state, t, side):
    rig = state['rig']
    _prone(state, 0.0, False, True)
    bpy.context.view_layer.update()
    pelvis = rig.pose.bones['pelvis']
    pivot = pelvis.head.copy()
    roll = Matrix.Rotation(side * math.tau * _smooth(t), 4, 'Y')
    pelvis.matrix = Matrix.Translation(pivot) @ roll @ Matrix.Translation(-pivot) @ pelvis.matrix
    bpy.context.view_layer.update()


def _ground_contacts(state):
    """Keep stance foot soles on the floor after heel/toe roll and IK."""
    body = state['body']
    bpy.context.view_layer.update()
    if not body:
        return
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    corrections = {}
    for side, contact in state['contacts'].items():
        if state['feet'][side]['indices']:
            minimum = min((body.matrix_world@mesh.vertices[i].co).z for i in state['feet'][side]['indices'])
            if contact or minimum<.001:corrections[side] = .001-minimum
    evaluated.to_mesh_clear()
    for side, delta in corrections.items():
        matrix = state['foot_matrices'][side].copy()
        matrix.translation.z += delta
        _solve_leg(state,side,matrix)
    bpy.context.view_layer.update()


def sample_pose(rig, clip, t, state=None):
    """Public QA helper; generate one procedural pose before bake/export."""
    state = state or _state(rig)
    _reset(rig)
    bpy.context.view_layer.update()
    state['contacts'] = {}
    state['targets'] = {}
    state['foot_matrices'] = {}
    state['solve_errors'] = {}
    state['knee_width']=.14
    if clip == 'Idle':
        _idle(state, t)
    elif clip == 'Crouch_idle':
        _idle(state, t, True)
    elif clip in ('Walk_in_place', 'Jog_in_place', 'Run_in_place'):
        _gait(state, t, clip)
    elif clip == 'Jump_in_place':
        _jump(state, t)
    elif clip == 'Prone_idle':
        _prone(state, t)
    elif clip == 'Prone_crawl':
        _prone(state, t, True)
    elif clip == 'Prone_roll_l':
        _prone_roll(state, t, -1)
    elif clip == 'Prone_roll_r':
        _prone_roll(state, t, 1)
    else:
        raise ValueError(clip)
    if not clip.startswith('Prone_'):
        _ground_contacts(state)
    return state


def _bake_action(rig, clip, sampled, spec):
    action = bpy.data.actions.new(ACTION_NAMES[clip])
    action.use_fake_user = True
    action['kotm_generated_locomotion'] = True
    action['loop'] = spec['loop']
    action['fps'] = FPS
    action['duration_seconds'] = spec['frames']/FPS
    action['root_motion'] = 'In place: master fixed. Move the game character controller separately. Jump has baked vertical pelvis and foot motion.'
    action['recommended_controller_speed_mps'] = spec['speed']
    if 'stance' in spec:
        action['foot_contact_phases']='0.0 left; 0.5 right'
        action['stance_cycle_fraction']=spec['stance']
        action['steps_per_second']=2*FPS/spec['frames']
        action['step_length_m']=spec['speed']*spec['frames']/FPS/2
        action['gait_revision']='Anatomical forward knee hinge; matched native speed; heel/forefoot strike, toe-off, swing recovery'
    action['baked'] = 'Deform-bone local location/quaternion keys; no IK or driver evaluation required.'
    action['endpoint'] = 'Inclusive duplicate endpoint; play [first,last) when looping.' if spec['loop'] else 'One-shot action; hold its final sample only until the gameplay state changes.'
    rig.animation_data.action = action
    for i, matrices in enumerate(sampled):
        for bone in rig.pose.bones:
            if not bone.bone.use_deform:
                continue
            kwargs = {}
            if bone.parent:
                kwargs = {'parent_matrix': matrices[bone.parent.name],
                          'parent_matrix_local': bone.parent.bone.matrix_local}
            basis = bone.bone.convert_local_to_pose(matrices[bone.name],
                                                    bone.bone.matrix_local,
                                                    invert=True, **kwargs)
            location, rotation, scale = basis.decompose()
            bone.location = location
            bone.rotation_mode = 'QUATERNION'
            # Sign continuity prevents quaternion component curves from taking
            # a long interpolation path even when two poses are near each other.
            if bone.rotation_quaternion.dot(rotation) < 0:
                rotation.negate()
            bone.rotation_quaternion = rotation
            bone.keyframe_insert('location', frame=i+1, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=i+1, group=bone.name)
    # Sampled at 30 Hz; linear interpolation preserves stance trajectories.
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'
    return action


def create_animations(rig):
    """Create and return the game-ready locomotion and prone actions."""
    rig.animation_data_create()
    rig.animation_data.action = None
    scene = bpy.context.scene
    scene.render.fps = FPS
    state = _state(rig)
    actions = {}
    for clip, spec in SPECS.items():
        previous=bpy.data.actions.get(ACTION_NAMES[clip])
        if previous:bpy.data.actions.remove(previous)
        sampled = []
        rig.animation_data.action = None
        for i in range(spec['frames']+1):
            scene.frame_set(i+1)
            # Loop endpoints use exactly t=0, so numerical derivatives or
            # trigonometric rounding never introduce a loop seam.
            t = 0.0 if spec['loop'] and i == spec['frames'] else i/spec['frames']
            sample_pose(rig, clip, t, state)
            evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
            sampled.append({bone.name: bone.matrix.copy() for bone in evaluated.pose.bones})
        _reset(rig)
        for side in ('l', 'r'):
            rig['leg_ik.'+side] = 0.0
        rig.update_tag()
        bpy.context.view_layer.update()
        actions[ACTION_NAMES[clip]] = _bake_action(rig, clip, sampled, spec)
    rig.animation_data.action = None
    _reset(rig)
    for side in ('l', 'r'):
        rig['leg_ik.'+side] = 0.0
    rig['animation_library'] = ', '.join(actions)
    rig['animation_library_help'] = 'Ten baked actions at30FPS: standing locomotion, jump, prone idle/crawl, and left/right prone rolls. Master fixed; the game controller supplies travel.'
    rig.update_tag()
    scene.frame_set(1)
    bpy.context.view_layer.update()
    return actions
