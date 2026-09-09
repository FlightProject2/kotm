extends Node3D
var failures: Array[String] = []
var manager: WindowManager

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func ray(a: Vector3, b: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1|32))

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	manager = WindowManager.new()
	add_child(manager)
	var fixture := Node3D.new()
	fixture.name = "Fixture"
	add_child(fixture)
	var specs: Array = []
	for i in 4:
		specs.append({"transform":Transform3D(Basis.IDENTITY,Vector3(i*4,1.5,0)),"size":Vector3(1.2,1.2,.03)})
	manager.register_building(fixture,specs)
	var legacy := (load(KOTMWorldStyle.path("res://world/prefabs/buildings/house_small.tscn")) as PackedScene).instantiate() as Node3D
	legacy.name = "LegacyHouse"
	var legacy_panes := WindowAssetAdapter.prepare(legacy)
	add_child(legacy)
	legacy.position.x = 25
	manager.register_building(legacy,legacy_panes)
	var frontier := FrontierExpansion.instantiate_asset("frontier_house_ranch_sage")
	frontier.name = "FrontierHouse"
	var frontier_panes := WindowAssetAdapter.prepare(frontier)
	add_child(frontier)
	frontier.position.x = 45
	manager.register_building(frontier,frontier_panes)
	var resort := FrontierExpansion.instantiate_asset("frontier_resort_timber_cabin")
	resort.name = "ResortCabin"
	var resort_panes := WindowAssetAdapter.prepare(resort)
	add_child(resort)
	resort.position.x = 65
	manager.register_building(resort,resort_panes)
	for mesh: MeshInstance3D in frontier.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			check(mesh.mesh.surface_get_material(surface).resource_name != "KOTM_glass","Original embedded glass is removed from static mesh")
	var registration := manager.finish_registration()
	check(legacy_panes.size() > 0,"Legacy window panes discovered")
	check(frontier_panes.size() == 2,"Frontier window specs discovered")
	check(resort_panes.size() == 2,"Resort cabin window specs discovered")
	check(manager.broken.is_empty(),"All panes start intact")
	check(not manager.is_processing(),"Zero idle pane processing")
	# The headless dummy renderer does not retain MultiMesh GPU transforms.
	if DisplayServer.get_name() != "headless":
		for pane: Dictionary in manager.panes:
			var rendered: Transform3D = pane.visual.multimesh.get_instance_transform(pane.slot)
			check(rendered.basis.get_scale().abs().distance_to(pane.size) < .0001,"Rotated glass retains local width/height/thickness")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := ray(Vector3(0,1.5,2),Vector3(0,1.5,-1))
	check(manager.pane_for_hit(hit) == 0,"Bullet ray hits intact pane")
	var projectile_system := ProjectileSystem.new()
	add_child(projectile_system)
	var projectile := ProjectileSystem.Proj.new()
	projectile.pos = Vector3(0,1.5,0)
	projectile_system._impact(projectile,hit)
	check(manager.broken.has(0),"Projectile impact shatters pane")
	check(not manager.break_hit(hit,"bullet"),"Repeated bullet impact is idempotent")
	await get_tree().physics_frame
	check(ray(Vector3(0,1.5,2),Vector3(0,1.5,-1)).is_empty(),"Broken pane removes bullet collision")
	check(manager.melee(Vector3(4,1.5,1),Vector3.FORWARD,1.5),"Punch within reach shatters pane")
	check(not manager.melee(Vector3(12,1.5,3),Vector3.FORWARD,1.5),"Punch beyond reach leaves pane intact")
	check(manager.break_in_radius(Vector3(8,1.5,2),2.2) == 1,"Nearby blast breaks exactly the near pane")
	check(not manager.broken.has(3),"Distant blast leaves far pane intact")
	check(manager.break_in_radius(Vector3(8,1.5,2),2.2) == 0,"Repeated blast is idempotent")
	var aperture_checks := 0
	for pane: Dictionary in manager.panes:
		if pane.building == "Fixture":
			continue
		var xf: Transform3D = pane.transform
		var size: Vector3 = pane.size
		var thin := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		var normal: Vector3 = xf.basis[thin]
		var a := xf.origin+normal*.45
		var b := xf.origin-normal*.45
		hit = ray(a,b)
		check(manager.pane_for_hit(hit) == pane.id,"Authored intact aperture catches ray: "+str(pane.building))
		manager.break_pane(pane.id,xf.origin,normal)
		await get_tree().physics_frame
		check(ray(a,b).is_empty(),"Authored broken aperture has no hidden wall collider: "+str(pane.building))
		aperture_checks += 1
	manager._receive_snapshot([3])
	check(manager.broken.has(3),"Late-join snapshot applies broken state")
	var before := manager.broken.size()
	manager._receive_snapshot([3])
	check(manager.broken.size() == before,"Snapshot replay is idempotent")
	check(manager.shards.size() <= WindowManager.MAX_SHARDS,"Debris pool remains bounded")
	await get_tree().create_timer(1.6).timeout
	check(not manager.is_processing(),"Debris processing sleeps after effects expire")
	print("KOTM_WINDOW_CHECK="+JSON.stringify({"issues":failures,"registration":registration,"apertures":aperture_checks,"broken":manager.broken.size(),"max_shards":WindowManager.MAX_SHARDS,"zero_idle_processing":not manager.is_processing()}))
	get_tree().quit(0 if failures.is_empty() else 1)
