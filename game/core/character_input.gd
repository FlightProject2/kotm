class_name CharacterInput
extends RefCounted
## One tick of intent for a character. Players build it from the InputMap + camera,
## bots build it from their brain. Packed to ~30 bytes for the network.

const B_SPRINT := 1
const B_JUMP := 2
const B_CROUCH := 4
const B_FIRE := 8
const B_AIM := 16
const B_RELOAD := 32
const B_INTERACT := 64
const B_FREE_LOOK := 128
const B_PRONE := 256

var tick: int = 0
var move: Vector2 = Vector2.ZERO      # x = strafe (+right), y = forward (+forward)
var yaw: float = 0.0                   # radians, body facing
var pitch: float = 0.0                 # radians, view pitch
var aim_dir: Vector3 = Vector3.FORWARD # world direction the muzzle should shoot along
var buttons: int = 0
var slot: int = -1                     # hotbar slot requested this tick, -1 = none
var use_med: int = 0                   # 0 none, 1 bandage, 2 first aid kit

func pressed(flag: int) -> bool:
	return (buttons & flag) != 0

func set_button(flag: int, on: bool) -> void:
	if on:
		buttons |= flag
	else:
		buttons &= ~flag

func pack() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_float(move.x); b.put_float(move.y)
	b.put_float(yaw); b.put_float(pitch)
	b.put_float(aim_dir.x); b.put_float(aim_dir.y); b.put_float(aim_dir.z)
	b.put_u16(buttons)
	b.put_8(slot)
	b.put_u8(use_med)
	return b.data_array

static func unpack(bytes: PackedByteArray) -> CharacterInput:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var i := CharacterInput.new()
	i.tick = b.get_u32()
	i.move = Vector2(b.get_float(), b.get_float())
	i.yaw = b.get_float(); i.pitch = b.get_float()
	i.aim_dir = Vector3(b.get_float(), b.get_float(), b.get_float())
	i.buttons = b.get_u16()
	i.slot = b.get_8()
	i.use_med = b.get_u8()
	return i

func duplicate_input() -> CharacterInput:
	return CharacterInput.unpack(pack())
