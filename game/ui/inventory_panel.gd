class_name InventoryPanel
extends PanelContainer
## In-match carried inventory and crafting, using the actual character's inventory/gear.
var hud: HUD
var columns: HBoxContainer
var carried: VBoxContainer
var recipes: VBoxContainer
var nearby: VBoxContainer
var capacity_label: Label
var open := false
var refresh_t := 0.0

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.055, 0.94)
	style.set_content_margin_all(28)
	add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	add_child(stack)
	var title := Label.new()
	title.text = "INVENTORY  /  TAB TO CLOSE"
	title.add_theme_font_size_override("font_size", 28)
	stack.add_child(title)
	capacity_label = Label.new()
	stack.add_child(capacity_label)
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	stack.add_child(columns)
	for label in ["VICINITY", "CARRIED", "CRAFTING"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(col)
		var heading := Label.new()
		heading.text = label
		heading.add_theme_font_size_override("font_size", 20)
		col.add_child(heading)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(280, 460)
		col.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		if label == "VICINITY": nearby = rows
		elif label == "CARRIED": carried = rows
		else: recipes = rows

func set_open(on: bool) -> void:
	if on and (not is_instance_valid(hud.character) or not hud.character.alive()):
		return
	open = on
	visible = on
	var ch := hud.character
	if is_instance_valid(ch):
		var source := ch.get_node_or_null("Input")
		if source:
			source.enabled = not on and ch.alive()
		var idle := CharacterInput.new()
		idle.yaw = ch.yaw
		idle.pitch = ch.pitch
		idle.aim_dir = ch.forward()
		ch.submit_input(idle)
	if hud.camera_rig:
		hud.camera_rig.look_enabled = not on and is_instance_valid(ch) and ch.alive()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not on and is_instance_valid(ch) and ch.alive() else Input.MOUSE_MODE_VISIBLE
	if on:
		refresh()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(hud.character) or not hud.character.alive():
		return
	# Pause, settings and match results own input while their menu is open.
	var source := hud.character.get_node_or_null("Input")
	if not open and ((source and not source.enabled) or (hud.camera_rig and not hud.camera_rig.look_enabled)):
		return
	if event.is_action_pressed("inventory") or (open and event.is_action_pressed("pause")):
		set_open(not open)
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if not open: return
	if not is_instance_valid(hud.character) or not hud.character.alive():
		set_open(false)
		return
	refresh_t -= dt
	if refresh_t <= 0:
		refresh_t = 0.5
		refresh()

func _button(parent: Control, text: String, action: Callable, enabled := true) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 36
	button.disabled = not enabled
	button.pressed.connect(action)
	parent.add_child(button)

func refresh() -> void:
	for parent in [nearby, carried, recipes]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	var ch := hud.character
	var inv := ch.inventory
	capacity_label.text = "%d / %d CARRY WEIGHT  |  %s  |  %s" % [ceili(inv.weight()), inv.capacity(), "HELMET EQUIPPED" if ch.health.has_helmet() else "NO HELMET", "ARMOUR EQUIPPED" if ch.health.has_armor() else "NO ARMOUR"]
	for i in inv.slots.size():
		var id := inv.slots[i]
		if id.is_empty(): continue
		_button(carried, "EQUIP  " + str(ItemCatalog.get_item(id).get("name", id)), func(): inv.select(i); refresh())
	for kind in ["ammo", "meds", "materials"]:
		var contents: Dictionary = inv.get(kind)
		for id in contents:
			if int(contents[id]) <= 0: continue
			var label := "%s  x%d" % [ItemCatalog.get_item(id).get("name", id), contents[id]]
			if kind == "meds":
				_button(carried, "USE  " + label, func(): ch.combat._use_med(id); refresh())
			else:
				var line := Label.new(); line.text = label; carried.add_child(line)
	for recipe in Crafting.RECIPES:
		var spec: Dictionary = Crafting.RECIPES[recipe]
		var costs := PackedStringArray()
		for id in spec.cost:
			costs.append("%s %d/%d" % [ItemCatalog.get_item(id).get("name", id), Crafting.count(ch, id), spec.cost[id]])
		_button(recipes, spec.name, func(): Crafting.make(ch, recipe); refresh(), Crafting.can_make(ch, recipe))
		var line := Label.new(); line.text = "\n".join(costs); recipes.add_child(line)
	var registry := ch.interaction.registry
	if registry:
		for entry in registry.entries.values():
			if entry.pos.distance_to(ch.global_position) <= CharacterInteraction.REACH:
				_button(nearby, "TAKE  " + LootTables.display_name(entry.item), func(): ch.interaction.take(entry); refresh())
