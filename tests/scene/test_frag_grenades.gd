extends TestCase
const GRENADES = preload("res://game/combat/grenade_system.gd")
var _nodes: Array[Node] = []

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	tree.root.add_child(body)
	_nodes.append(body)
	return body

func _character(position: Vector3, id: int) -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = position
	ch.character_id = id
	tree.root.add_child(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	_nodes.append(ch)
	return ch

func _setup_system():
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	var ps := ProjectileSystem.new()
	tree.root.add_child(ps)
	_nodes.append(ps)
	await settle(2)
	var system = GRENADES.instance
	system.set_physics_process(false)
	return system

func _cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await settle(2)

func _input(ch: Character, pressed: bool, dt := 0.1) -> void:
	ch.prev_input = ch.input
	ch.input = CharacterInput.new()
	ch.input.aim_dir = Vector3.FORWARD
	ch.input.set_button(CharacterInput.B_FIRE, pressed)
	ch.combat.tick(dt)

func test_slot_six_throw_consumes_one_and_holding_does_not_repeat() -> void:
	var system = await _setup_system()
	var ch := _character(Vector3(0, 0.05, 0), 701)
	ch.inventory.give_throwable("frag_grenade", 2)
	ch.inventory.select(5)
	_input(ch, true)
	assert_eq(ch.inventory.throwables.frag_grenade, 1)
	assert_eq(system.grenades.size(), 1)
	var id: int = system.grenades.keys()[0]
	assert_near(system.grenades[id].remaining, 4.0, 0.000001, "authored fuse")
	assert_true(system.grenades[id].body.velocity.z < -18.0, "throw follows aim")
	for i in 20:
		_input(ch, true)
	assert_eq(system.grenades.size(), 1, "one press throws one grenade")
	assert_eq(ch.inventory.throwables.frag_grenade, 1)
	_input(ch, false)
	_input(ch, true)
	assert_eq(ch.inventory.throwables.frag_grenade, 0)
	assert_eq(system.grenades.size(), 2)
	_input(ch, false, 1.0)
	_input(ch, true)
	assert_eq(system.grenades.size(), 2, "empty stack cannot throw")
	assert_eq(ch.combat.shot_counter, 0, "throw never enters gun ammo/recoil path")
	assert_false(ch.visual.weapon_holder.flash.visible, "throw has no rifle muzzle flash")
	await _cleanup()

func test_bounce_fuse_and_cosmetic_lifetime() -> void:
	var system = await _setup_system()
	_box(Vector3(0, 1, -2), Vector3(8, 3, 0.25))
	await settle(2)
	var ch := _character(Vector3(0, 0.05, 0), 702)
	ch.input.aim_dir = Vector3.FORWARD
	var id: int = system.throw_frag(ch)
	var body: CharacterBody3D = system.grenades[id].body
	var max_forward := 0.0
	for i in 239:
		system.advance(1.0 / 60.0)
		if is_instance_valid(body):
			max_forward = minf(max_forward, body.global_position.z)
	assert_true(max_forward > -1.94, "swept sphere bounces in front of wall instead of tunnelling")
	assert_eq(system.detonations, 0, "does not explode before four-second fuse")
	system.advance(0.03)
	assert_eq(system.detonations, 1)
	assert_false(system.grenades.has(id))
	assert_eq(system.explosions.size(), 1)
	system.detonate(id)
	assert_eq(system.detonations, 1, "repeated request is idempotent")
	system._on_exploded(id, Vector3.ZERO, 8.0)
	assert_eq(system.explosions.size(), 1, "reliable duplicate does not duplicate FX")
	system.advance(1.2)
	assert_true(system.explosions.is_empty())
	assert_false(system.is_physics_processing(), "no idle grenade callback after effects expire")
	await _cleanup()

func test_authored_radial_damage_cover_and_thrower_credit() -> void:
	var system = await _setup_system()
	var definition: Dictionary = ItemCatalog.get_item("frag_grenade").def
	assert_near(GRENADES.damage_at_distance(0, definition), 100)
	assert_near(GRENADES.damage_at_distance(3, definition), 100)
	assert_near(GRENADES.damage_at_distance(5.5, definition), 50)
	assert_near(GRENADES.damage_at_distance(8, definition), 0)
	assert_near(GRENADES.damage_at_distance(20, definition), 0)
	var shooter := _character(Vector3(20, 0, 0), 703)
	var inner := _character(Vector3(2, 0, 0), 704)
	var outer := _character(Vector3(5.5, 0, 0), 705)
	var outside := _character(Vector3(9, 0, 0), 706)
	var covered := _character(Vector3(0, 0, -4), 707)
	_box(Vector3(0, 1.2, -2), Vector3(4, 2.4, 0.3))
	await settle(2)
	var id: int = system.throw_frag(shooter)
	system.grenades[id].body.global_position = Vector3(0, 0.9, 0)
	system.detonate(id)
	assert_false(inner.alive(), "100-damage inner radius")
	assert_true(inner.last_hit_by == shooter, "kill credited to thrower")
	assert_near(outer.health.hp, 50, 0.01, "linear authored inner/outer falloff")
	assert_near(outside.health.hp, 100, 0.001, "outside radius unaffected")
	assert_near(covered.health.hp, 100, 0.001, "solid wall blocks blast damage")
	assert_near(shooter.health.hp, 100, 0.001)
	await _cleanup()

func test_actual_blast_breaks_nearby_panes_and_client_events_never_damage() -> void:
	var system = await _setup_system()
	var manager := WindowManager.new()
	tree.root.add_child(manager)
	_nodes.append(manager)
	var building := Node3D.new()
	tree.root.add_child(building)
	_nodes.append(building)
	manager.register_building(building, [
		{"transform": Transform3D(Basis.IDENTITY, Vector3(2, 1.5, 0)), "size": Vector3(1.2, 1.2, 0.03)},
		{"transform": Transform3D(Basis.IDENTITY, Vector3(15, 1.5, 0)), "size": Vector3(1.2, 1.2, 0.03)}])
	manager.finish_registration()
	var shooter := _character(Vector3(20, 0, 0), 708)
	await settle(2)
	var id: int = system.throw_frag(shooter)
	system.grenades[id].body.global_position = Vector3(0, 0.9, 0)
	system.detonate(id)
	assert_true(manager.broken.has(0), "actual frag blast breaks near glass")
	assert_false(manager.broken.has(1), "far glass remains intact")
	var victim := _character(Vector3(0, 0, 0), 709)
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", 65530), OK)
	var client_api := MultiplayerAPI.create_default_interface()
	client_api.multiplayer_peer = peer
	tree.set_multiplayer(client_api, system.get_path())
	assert_false(system.multiplayer.is_server())
	assert_eq(system.throw_frag(shooter), -1, "client cannot originate authoritative grenade")
	system._on_thrown(999, shooter.character_id, Vector3(0, 0.9, 0), Vector3.ZERO, 0.001)
	system.advance(0.02)
	system.detonate(999)
	assert_near(victim.health.hp, 100, 0.001, "client fuse/prediction cannot apply damage")
	assert_true(system.grenades.has(999), "client awaits reliable server explosion")
	Net._dispatch("grenade_exploded", [999, Vector3(0, 0.9, 0), 8.0])
	assert_false(system.grenades.has(999), "reliable server event removes predicted grenade")
	assert_near(victim.health.hp, 100, 0.001, "network cosmetic event never applies damage")
	peer.close()
	tree.set_multiplayer(null, system.get_path())
	await _cleanup()
