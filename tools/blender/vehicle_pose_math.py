"""Direct anatomical limb solving for weapon and vehicle poses.

Drop-in entry points: weapon_pose, seated_pose, bake_callback.  Targets are in
armature coordinates (the avatar root's coordinates), matching the equipment
markers after subtracting SeatDriver.  The solver computes the elbow/knee
position directly from a preferred bend point, so calibrated Blender IK pole
angles cannot unexpectedly invert the bend plane. No constraints are needed.
"""
import math
import bpy
from mathutils import Matrix, Vector, Quaternion
from mathutils.bvhtree import BVHTree

_grip_angle_cache={}
_grip_quaternion_cache={}
_transition_cache={}


def reset(rig):
    rig.animation_data_create()
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = 'QUATERNION'
    for side in ('l', 'r'):
        rig['arm_ik.'+side] = 0.0
        rig['leg_ik.'+side] = 0.0
    rig.update_tag()
    bpy.context.view_layer.update()


def rotate_world_axes(rig, name, angles):
    rest = rig.data.bones[name].matrix_local.to_quaternion()
    q = Quaternion((0,0,1), math.radians(angles[2])) @ Quaternion((0,1,0), math.radians(angles[1])) @ Quaternion((1,0,0), math.radians(angles[0]))
    bone = rig.pose.bones[name]
    bone.rotation_mode = 'QUATERNION'
    bone.rotation_quaternion = rest.inverted() @ q @ rest


def set_bone_position(rig, name, position, world=False):
    """Set a bone head's position, independent of its local rotation axes."""
    point = Vector(position)
    if world:
        point = rig.matrix_world.inverted() @ point
    matrix = rig.pose.bones[name].matrix.copy()
    matrix.translation = point
    rig.pose.bones[name].matrix = matrix
    bpy.context.view_layer.update()


def _frame(y, normal):
    y = Vector(y).normalized()
    x = Vector(normal)
    x = (x-y*x.dot(y)).normalized()
    if x.length < .5:
        x = y.orthogonal().normalized()
    z = x.cross(y).normalized()
    return Matrix((x,y,z)).transposed()


def anatomical_hand_matrix(rig, side, position, long_axis, palm_back):
    """Map the actual mesh's dorsal hand normal, not arbitrary bone-local Z."""
    bone = rig.data.bones['hand.'+side]
    rest_y = (bone.tail_local-bone.head_local).normalized()
    sign = 1 if side == 'l' else -1
    dorsal = Vector((sign,0,0))
    rest_z = (dorsal-rest_y*dorsal.dot(rest_y)).normalized()
    rest_x = rest_y.cross(rest_z).normalized()
    source_frame = Matrix((rest_x,rest_y,rest_z)).transposed()
    target_y = Vector(long_axis).normalized()
    target_z = Vector(palm_back)
    target_z = (target_z-target_y*target_z.dot(target_y)).normalized()
    target_x = target_y.cross(target_z).normalized()
    target_frame = Matrix((target_x,target_y,target_z)).transposed()
    rotation = target_frame @ source_frame.transposed() @ bone.matrix_local.to_3x3()
    matrix = rotation.to_4x4()
    matrix.translation = Vector(position)
    return matrix


def hand_at_contact(rig, side, contact, long_axis, palm_back, along_palm=0):
    """Place the real palm pad on a contact point, deriving the wrist offset."""
    # Palm face-set centroids on the supplied canonical anatomy. The offset
    # toward the palm surface distinguishes contact from the palm centreline.
    centre = Vector((.42194,-.09120,.90108)) if side=='l' else Vector((-.42177,-.09121,.90107))
    sign = 1 if side=='l' else -1
    pad = centre-Vector((sign*.012,0,0))
    bone = rig.data.bones['hand.'+side]
    pad += (bone.tail_local-bone.head_local).normalized()*along_palm
    matrix = anatomical_hand_matrix(rig,side,(0,0,0),long_axis,palm_back)
    delta_rotation = matrix.to_3x3() @ bone.matrix_local.to_3x3().inverted()
    wrist = Vector(contact)-delta_rotation@(pad-bone.head_local)
    matrix.translation=wrist
    return wrist,matrix


def solve_two_bone(rig, upper_name, lower_name, target, preferred_joint,
                   terminal_name=None, terminal_matrix=None):
    """Solve a chain with an explicit elbow/knee direction and rigid lengths."""
    bpy.context.view_layer.update()
    upper = rig.pose.bones[upper_name]
    lower = rig.pose.bones[lower_name]
    start = upper.head.copy()
    target = Vector(target)
    preferred_joint = Vector(preferred_joint)
    direction = target-start
    actual_distance = direction.length
    if actual_distance < 1e-5:
        direction = Vector((0,-1,0))
    else:
        direction.normalize()
    a, b = upper.bone.length, lower.bone.length
    distance = min(a+b-1e-5, max(abs(a-b)+1e-5, actual_distance))
    reached = start+direction*distance
    along = (a*a-b*b+distance*distance)/(2*distance)
    height = math.sqrt(max(0,a*a-along*along))
    bend = preferred_joint-start
    bend -= direction*bend.dot(direction)
    if bend.length < 1e-5:
        bend = direction.orthogonal()
    bend.normalize()
    joint = start+direction*along+bend*height
    desired_upper = (joint-start).normalized()
    desired_lower = (reached-joint).normalized()
    normal = desired_upper.cross(desired_lower).normalized()
    if normal.length < .5:
        normal = direction.cross(bend).normalized()
    rest_upper = (upper.bone.tail_local-upper.bone.head_local).normalized()
    rest_lower = (lower.bone.tail_local-lower.bone.head_local).normalized()
    rest_normal = rest_upper.cross(rest_lower).normalized()
    if rest_normal.length < .5:
        rest_normal = upper.bone.matrix_local.to_3x3().col[0]
    # Preserve the bone's roll offset within the anatomical bend plane.
    # This gives a stable shoulder and avoids concentrating every twist at the wrist.
    for bone, y_rest, y_new, origin in [(upper,rest_upper,desired_upper,start),
                                       (lower,rest_lower,desired_lower,joint)]:
        rotation = _frame(y_new,normal) @ _frame(y_rest,rest_normal).transposed() @ bone.bone.matrix_local.to_3x3()
        matrix = rotation.to_4x4()
        matrix.translation = origin
        bone.matrix = matrix
        bpy.context.view_layer.update()
    if terminal_name:
        terminal = rig.pose.bones[terminal_name]
        matrix = terminal_matrix.copy() if terminal_matrix is not None else terminal.matrix.copy()
        matrix.translation = reached
        terminal.matrix = matrix
        bpy.context.view_layer.update()
    return {'joint': joint, 'requested_target': target, 'reached_target': reached,
            'target_error_m': (reached-target).length}


def _curl(rig, side, amount=45, trigger=False):
    for finger in ('thumb','index','middle','ring','pinky'):
        for segment in (1,2,3):
            bone = rig.pose.bones[f'{finger}_{segment:02d}.{side}']
            base_angle = amount[segment-1] if isinstance(amount,(tuple,list)) else amount
            angle = base_angle*.36 if finger=='thumb' else 12 if trigger and finger=='index' else base_angle
            bone.rotation_mode = 'QUATERNION'
            bone.rotation_quaternion = Quaternion((1,0,0),math.radians(angle))


