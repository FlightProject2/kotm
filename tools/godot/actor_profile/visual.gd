extends CharacterVisuals
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _setup_studio() -> void:
	studio_rig = KOTMCharacterRig.new()
	studio_rig.name = "StudioRig"
	add_child(studio_rig)
	studio_rig.setup(get_node("Model"))
	studio_rig.apply_loadout(character.cosmetics)
	var lower_layer := preload("res://game/character/locomotion_layer.gd").new()
	lower_layer.character = character
	lower_layer.rig = studio_rig
	skeleton.add_child(lower_layer)
	aim_spine = AimSpineModifier.new()
	aim_spine.weights = {"spine_01": 0.35, "spine_02": 0.65, "head": 0.0}
	skeleton.add_child(aim_spine)
	# Other weapon classes retain the existing procedural hold until their own fitted clips
	# are authored. This modifier is disabled for both studio rifles.
	arm_pose = ArmPoseModifier.new()
	skeleton.add_child(arm_pose)
	var facing := preload("res://game/character/kotm_pose_modifier.gd").new()
	facing.character = character
	facing.rig = studio_rig
	facing.visual = self
	skeleton.add_child(facing)
	leg_ik = preload("res://game/character/directional_leg_ik.gd").new()
	leg_ik.character = character
	leg_ik.rig = studio_rig
	skeleton.add_child(leg_ik)
	studio_rig.finish_modifiers()
	vehicle_contact = preload("res://game/character/vehicle_contact_ik.gd").new()
	vehicle_contact.name = "VehicleContact"
	vehicle_contact.character = character
	vehicle_contact.rig = studio_rig
	skeleton.add_child(vehicle_contact)
	weapon_holder = WeaponHolder.new()
	weapon_holder.name = "HandR"
	weapon_holder.bone_name = "hand.r"
	weapon_holder.character = character
	weapon_holder.studio_rig = studio_rig
	skeleton.add_child(weapon_holder)
	character.fired.connect(func(_v: float, _h: float) -> void: weapon_holder.fire_effects())
	hat = studio_rig.roots.get(studio_rig.wardrobe.head)
	mask = studio_rig.roots.get(studio_rig.wardrobe.face)
	_build_canopy()
	anim = preload("res://tools/godot/actor_profile/animation.gd").new()
	anim.name = "Anim"
	character.add_child.call_deferred(anim)
func _process_studio() -> void:
	var clock := Time.get_ticks_usec()
	super._process_studio()
	PROFILE.record("visual.state_update", clock)
