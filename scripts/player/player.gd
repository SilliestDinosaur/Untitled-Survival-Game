extends CharacterBody3D
## First-person player: mouse look, walk/sprint/jump, swimming, fall damage, head bob,
## footsteps, and actions: swing (destroy / hunt) with the held tool, Interact to harvest by hand,
## pick up and drop items, eat. World changes go through GameActions (host-authoritative later).

signal landed(impact: float)
signal hint(text: String)   ## short messages for the HUD ("Too hard to break by hand")
signal hit_landed           ## a swing connected with something

const REACH := 3.2
const PICKUP_SCENE_LAYER := 2

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var swim_speed := 3.4
@export var jump_velocity := 5.4
@export var ground_accel := 11.0
@export var air_accel := 2.5
@export var coyote_time := 0.12        ## can still jump this long after walking off a ledge
@export var jump_buffer := 0.15        ## jump pressed slightly before landing still counts
@export var safe_fall_speed := 11.0    ## landing faster than this hurts
@export var fall_damage_per_ms := 7.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/Interact
@onready var stats: PlayerStats = $Stats

var player_id := Game.LOCAL_PLAYER
var active := false
var spawn_point := Vector3.ZERO
var swimming := false
var underwater := false
## What the crosshair is on: {} or {name, label, resource/chunk | animal | pickup, actions}.
var looking_at := {}
var inventory: Inventory
var viewmodel: Viewmodel
var is_sprinting := false   ## animals hear you from farther away
var _rng := RandomNumberGenerator.new()
var _swing_cooldown := 0.0
var _interact_cooldown := 0.0
var _shake := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _exhausted := false
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _bob_time := 0.0
var _bob_amount := 0.0
var _last_step := 0
var _land_dip := 0.0
var _fov_kick := 0.0


func _ready() -> void:
	ray.add_exception(self)
	_rng.randomize()
	inventory = Game.inventory_of(player_id)
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	viewmodel.strike.connect(_on_strike)
	viewmodel.grab.connect(_on_grab)
	inventory.changed.connect(func() -> void: viewmodel.hold(inventory.selected_item()))
	inventory.tool_broke.connect(func(id: String) -> void:
		hint.emit("Your %s broke!" % ItemDB.display_name(id))
		Audio.play("clink", -2.0, 0.6))
	reset_inventory()
	stats.damaged.connect(func(amount: float) -> void: _shake = minf(_shake + amount / 20.0, 1.0))
	set_active(false)


## Everything about the player that goes into a save file.
func to_save_data() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"pitch": head.rotation.x,
		"health": stats.health,
		"hunger": stats.hunger,
		"stamina": stats.stamina,
		"effects": stats.effects.duplicate(),
		"inventory": inventory.to_data(),
	}


func apply_save_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
	rotation = Vector3(0, float(d.get("yaw", 0.0)), 0)
	head.rotation.x = float(d.get("pitch", 0.0))
	velocity = Vector3.ZERO
	stats.health = float(d.get("health", stats.max_health))
	stats.hunger = float(d.get("hunger", stats.max_hunger))
	stats.stamina = float(d.get("stamina", stats.max_stamina))
	stats.effects = d.get("effects", {})
	if d.has("inventory"):
		inventory.from_data(d.inventory)
	elif d.has("items"):   # older saves: item counts only
		inventory.clear(true)
		var items: Dictionary = d.items
		for id: String in items:
			inventory.add(id, int(items[id]), true)


## Fresh start: just a rock in hand (also used after dying).
func reset_inventory() -> void:
	inventory.clear(true)
	inventory.add("rock", 1, true)
	inventory.select(0)


func set_active(on: bool) -> void:
	active = on
	looking_at = {}
	set_physics_process(on)
	set_process(on)
	set_process_unhandled_input(on)
	camera.current = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0022 * Settings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		viewmodel.add_sway(event.relative)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.select(inventory.selected + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.select(inventory.selected - 1)
	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			inventory.select(i)
	if event.is_action_pressed("drop") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		drop_selected(Input.is_key_pressed(KEY_CTRL))

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	swimming = global_position.y + 1.0 < Game.SEA_LEVEL
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	# Timers that make jumping feel forgiving.
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buffer = jump_buffer if Input.is_action_just_pressed("jump") else maxf(_jump_buffer - delta, 0.0)

	if stats.stamina <= 0.0:
		_exhausted = true
	elif stats.stamina > 25.0:
		_exhausted = false
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.1 and not _exhausted and on_floor and not swimming

	var speed := walk_speed
	if swimming:
		speed = swim_speed
	elif sprinting:
		speed = sprint_speed

	if swimming:
		# Float near the surface; hold jump to rise, otherwise bob at chest height.
		var target_y := Game.SEA_LEVEL - 1.35
		var up := 3.0 if Input.is_action_pressed("jump") else (target_y - global_position.y) * 2.0
		velocity.y = lerpf(velocity.y, up, 1.0 - exp(-4.0 * delta))
		_jump_buffer = 0.0
	else:
		if not on_floor:
			velocity.y -= _gravity * delta
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote = 0.0

	var accel := ground_accel if (on_floor or swimming) else air_accel
	var w := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, w)
	velocity.z = lerpf(velocity.z, dir.z * speed, w)

	var fall_speed := -velocity.y
	move_and_slide()

	# Landing: camera dip, thud, fall damage.
	if is_on_floor() and not _was_on_floor and not swimming:
		_land_dip = clampf(fall_speed * 0.012, 0.0, 0.25)
		if fall_speed > 3.0:
			Audio.land(fall_speed / 12.0)
		if fall_speed > safe_fall_speed:
			stats.take_damage((fall_speed - safe_fall_speed) * fall_damage_per_ms)
		landed.emit(fall_speed)
	_was_on_floor = is_on_floor()

	# Keep the player on the map, and catch anyone who falls through the world.
	global_position.x = clampf(global_position.x, 4.0, Game.WORLD_SIZE - 4.0)
	global_position.z = clampf(global_position.z, 4.0, Game.WORLD_SIZE - 4.0)
	if global_position.y < -40.0:
		respawn()

	is_sprinting = sprinting and input != Vector2.ZERO
	stats.tick(delta, is_sprinting)
	_update_camera(delta, sprinting, input)
	_update_looking_at()
	_update_actions(delta)


func _update_camera(delta: float, sprinting: bool, input: Vector2) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := (is_on_floor() or swimming) and horizontal > 0.5 and input != Vector2.ZERO
	_bob_amount = lerpf(_bob_amount, 1.0 if moving else 0.0, 1.0 - exp(-8.0 * delta))
	if moving:
		_bob_time += delta * horizontal * (0.9 if swimming else 1.45)

	# A footstep each time the bob reaches its lowest point.
	var step := int(_bob_time / PI)
	if step != _last_step:
		_last_step = step
		if moving:
			var surface := "water" if swimming else Game.world_gen.get_surface(global_position.x, global_position.z)
			Audio.footstep(surface, 1.25 if sprinting else 0.9)

	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))
	var bob_scale := 0.6 if swimming else 1.0
	var bob := Vector3(cos(_bob_time) * 0.035, -absf(sin(_bob_time)) * 0.06, 0.0) * _bob_amount * bob_scale
	# Screen shake when hurt (decays quickly).
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.08
	camera.position = bob + Vector3(0, -_land_dip, 0) + shake

	_fov_kick = lerpf(_fov_kick, 9.0 if sprinting and horizontal > 6.0 else 0.0, 1.0 - exp(-6.0 * delta))
	camera.fov = Settings.fov + _fov_kick
	viewmodel.update_motion(delta, _bob_time, _bob_amount)
	underwater = camera.global_position.y < Game.SEA_LEVEL - 0.05


func _update_looking_at() -> void:
	looking_at = {}
	if not ray.is_colliding():
		return
	var body := ray.get_collider() as CollisionObject3D
	if not body or ray.get_collision_point().distance_to(camera.global_position) > REACH + 0.6:
		return
	if body.has_meta("pickup"):
		var pid: String = body.get_meta("pickup")
		if Game.pickups.has(pid):
			var p: Dictionary = Game.pickups[pid]
			looking_at = {"name": "%s%s" % [ItemDB.display_name(p.item), (" x%d" % p.count) if int(p.count) > 1 else ""],
				"label": "Dropped item", "pickup": pid, "interact": "Pick up"}
		return
	if body.has_meta("animal"):
		var animal: Node = body.get_meta("animal")
		looking_at = {
			"name": animal.species.name,
			"label": "Carcass" if animal.dead else animal.species.label,
			"animal": animal,
			"interact": "Butcher" if animal.dead else "",
			"attack": "" if animal.dead else "Attack",
		}
		return
	if body.get_parent() is TerrainChunk:
		var chunk := body.get_parent() as TerrainChunk
		var res: Dictionary = chunk.resource_from_hit(body, ray.get_collider_shape())
		if not res.is_empty():
			looking_at = {
				"name": Game.flora.resource_name(res),
				"label": FloraLibrary.KINDS[res.kind].label,
				"resource": res,
				"chunk": chunk,
				"interact": _interact_verb(res),
				"attack": _attack_verb(res),
			}


func _interact_verb(r: Dictionary) -> String:
	if r.kind == "cache":
		return "Open"
	var key := ItemDB.harvest_key(r.kind)
	if key == "":
		return ""
	if key in ["mushroom", "herb", "pebbles"]:
		return "Pick up"
	if Game.is_harvested(r.id):
		return "(nothing left yet)"
	match key:
		"berry": return "Pick berries"
		"fruit_tree": return "Shake for fruit"
		"tree", "conifer": return "Gather sticks"
		"cactus": return "Cut flesh"
	return "Gather"


func _attack_verb(r: Dictionary) -> String:
	if r.kind == "cache":
		return ""
	match ItemDB.target_type(r.kind):
		"tree": return "Chop"
		"rock": return "Mine"
	return "Break"


func respawn() -> void:
	global_position = spawn_point + Vector3.UP * 1.5
	velocity = Vector3.ZERO
	stats.reset()


# --- Actions --------------------------------------------------------------------------

func _update_actions(delta: float) -> void:
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	_interact_cooldown = maxf(_interact_cooldown - delta, 0.0)
	var focused := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	if not focused or viewmodel.is_busy():
		return
	if Input.is_action_pressed("interact") and _interact_cooldown <= 0.0 and looking_at.get("interact", "") != "":
		_interact_cooldown = 0.35
		viewmodel.reach()
		return
	if not Input.is_action_pressed("attack") or _swing_cooldown > 0.0:
		return
	var item := inventory.selected_item()
	if item != "" and ItemDB.info(item).kind == "food":
		_swing_cooldown = 0.6
		viewmodel.eat(func() -> void:
			var res := GameActions.eat(player_id, stats)
			if res.get("ok", false):
				Audio.play(Audio.sfx.munch, -4.0)
				if res.first_time:
					var e: Dictionary = ItemDB.EFFECTS[res.effect]
					hint.emit("%s: %s" % [e.name, e.desc])
				elif ItemDB.info(res.id).get("health", 0.0) < 0.0:
					hint.emit("That didn't sit well..."))
		return
	if item != "" and ItemDB.info(item).kind != "tool":
		return   # holding a material: nothing to swing
	var tool := ItemDB.tool_stats(item)
	_swing_cooldown = tool.cooldown
	viewmodel.swing(tool.cooldown, String(tool.type))
	Audio.play("swoosh", -10.0)


## The viewmodel's swing reached the target.
func _on_strike() -> void:
	if not ray.is_colliding() or ray.get_collision_point().distance_to(camera.global_position) > REACH:
		return
	var point := ray.get_collision_point()
	var look := looking_at
	if look.has("animal") and not is_instance_valid(look.animal):
		return   # the animal was removed (e.g. despawned) mid-swing
	if look.has("animal"):
		var animal: Node = look.animal
		if animal.dead:
			hint.emit("Press %s to butcher" % Settings.code_label(Settings.binding_of("interact")))
			return
		hit_landed.emit()
		var res := GameActions.hit_animal(player_id, animal, global_position)
		Audio.play_3d("thud", point)
		Effects.chips(get_parent(), point, Color(0.65, 0.12, 0.12), 6, 0.05)
		return
	if look.has("resource"):
		_hit_resource(look.chunk, look.resource, point)


func _hit_resource(chunk: TerrainChunk, r: Dictionary, point: Vector3) -> void:
	var res := GameActions.hit_resource(player_id, chunk, r.index, _rng)
	var target: String = res.target
	var pal: WorldPalette = Game.palette
	if res.blocked:
		Audio.play_3d("clink", point, -6.0, 0.7)
		if res.get("use_interact", false):
			hint.emit("Press %s to open" % Settings.code_label(Settings.binding_of("interact")))
		elif res.need_tier >= 0:
			hint.emit("Needs a %s pickaxe or better" % ItemDB.tier_info(res.need_tier).name)
		else:
			hint.emit("Too hard to break by hand. Use a rock or a pickaxe.")
		return
	hit_landed.emit()
	_drop_overflow(res.items, point)
	match target:
		"tree":
			Audio.play_3d("chop", point)
			Effects.chips(get_parent(), point, pal.bark.lightened(0.15), 8, 0.07)
		"rock":
			Audio.play_3d("clink", point, -2.0)
			var col := pal.rock.lightened(0.1)
			if r.kind.begins_with("ore") or r.kind.begins_with("gem"):
				col = ItemDB.tier_info(int(r.kind.right(1))).color
			Effects.chips(get_parent(), point, col, 9, 0.07, 4.0)
		_:
			Audio.play_3d("rustle", point)
			Effects.chips(get_parent(), point, pal.bush_leaves, 10, 0.06, 2.5)
	if res.destroyed:
		_remove_visual(chunk, r)
	else:
		chunk.wobble(r.index)


## Interact: the viewmodel's hand reached out.
func _on_grab() -> void:
	var look := looking_at
	if look.has("pickup"):
		if GameActions.pick_up(player_id, look.pickup) > 0:
			Audio.play(Audio.sfx.pickup, -6.0)
		else:
			hint.emit("Your satchel is full")
		return
	if look.has("animal"):
		if not is_instance_valid(look.animal):
			return
		var res := GameActions.harvest_carcass(player_id, look.animal, _rng)
		if res.get("ok", false):
			Audio.play_3d("thud", look.animal.global_position, -6.0)
			_drop_overflow(res.items, look.animal.global_position)
			if res.destroyed:
				look.animal.consume_carcass()
		return
	if look.has("resource"):
		var chunk: TerrainChunk = look.chunk
		var r: Dictionary = look.resource
		var res := GameActions.harvest_resource(player_id, chunk, r.index, _rng)
		if res.empty:
			hint.emit("Nothing to gather here right now")
			return
		if not res.ok:
			return
		_drop_overflow(res.items, r.transform.origin + Vector3.UP * 0.5)
		Audio.play_3d("rustle", r.transform.origin + Vector3.UP * 0.5, -4.0, 1.2)
		if res.picked_up:
			_remove_visual(chunk, r)
		else:
			chunk.wobble(r.index)


func _remove_visual(chunk: TerrainChunk, r: Dictionary) -> void:
	var mesh := chunk.get_resource_mesh(r.index)
	var xf: Transform3D = r.transform
	chunk.remove_resource(r.index)
	if mesh:
		if FloraLibrary.category_of(r.kind) == "tree":
			Effects.fall_tree(get_parent(), mesh, xf, xf.origin - global_position, Game.palette.bark)
		else:
			Effects.crumble(get_parent(), mesh, xf)


## Whatever didn't fit in the satchel lands on the ground.
func _drop_overflow(items: Dictionary, at: Vector3) -> void:
	var dropped := false
	for k: String in items:
		if k.begins_with("_overflow_"):
			GameActions.spawn_pickup(k.trim_prefix("_overflow_"), items[k], -1, at + Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4)))
			dropped = true
	if dropped:
		hint.emit("Satchel full - some items fell on the ground")


## Q drops one of the held item (Ctrl+Q drops the whole stack).
func drop_selected(whole_stack := false) -> void:
	drop_slot(inventory.selected, whole_stack)


func drop_slot(slot: int, whole_stack := true) -> void:
	var s: Dictionary = inventory.slots[slot]
	if s.is_empty():
		return
	var fwd := -camera.global_transform.basis.z
	var pos := camera.global_position + fwd * 1.2
	var ground: float = Game.world_gen.get_height(pos.x, pos.z)
	pos.y = maxf(ground, Game.SEA_LEVEL) + 0.15
	GameActions.drop(player_id, slot, int(s.count) if whole_stack else 1, pos)
	Audio.play(Audio.sfx.click, -8.0, 0.8)
