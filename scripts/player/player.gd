extends CharacterBody3D
## First-person player: mouse look, walk/sprint/jump, swimming, fall damage, head bob,
## footsteps, and actions: swing (destroy / hunt) with the held tool, Interact to harvest by hand,
## pick up and drop items, eat. World changes go through GameActions (host-authoritative later).

signal landed(impact: float)
signal hint(text: String)   ## short messages for the HUD ("Too hard to break by hand")
signal hit_landed           ## a swing connected with something
signal open_crafting(kind: String)   ## Interact on a station: open its crafting panel
signal open_chest(structure_id: String)   ## Interact on a chest: open it beside the satchel
signal cave_chest(index: int)    ## Interact with a cave's supply chest
signal crafting_started      ## a crafting minigame began (the satchel should close)

const REACH := 3.2
const PICKUP_SCENE_LAYER := 2
const STEP_UP := 0.36   ## the highest ledge (a stair tread, a log) the body walks up without jumping

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
var _kick := Vector3.ZERO     ## camera rotation knocked by a blow (pitch, yaw, roll), springing back
var _lean := 0.0              ## roll into a strafe
var _cold := 0.0
var _heat := 0.0
var _exposure_timer := 0.0
## While holding a placeable: {ok, reason, pos, yaw, name}
var placement := {}
var _snapped_level := 0   ## storey the building preview is on (for the prompt)
var _ghost: MeshInstance3D
var _place_turns := 0   ## quarter turns from Rotate (R) for the piece being placed
## The building wheel's pick for the Building Plan: a shape (GameActions.SHAPES) in a material (GameActions.MATERIALS).
var build_choice := {"shape": "wall", "mat": "wood", "page": 0}   ## the wheel's picks (and per page, "decor<page>")
var wheel_open := false   ## set by the building wheel while it's up (placing waits until it closes)
var crafting: Node = null  ## the crafting minigame you're at (CraftSession), if any: you stand still while it runs
var _ghost_kind := ""
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D


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
	stats.damaged.connect(func(amount: float) -> void:
		_shake = minf(_shake + amount / 20.0, 1.0)
		kick(Vector3(randf_range(0.02, 0.04), randf_range(-0.03, 0.03), randf_range(-0.04, 0.04)) * clampf(amount / 15.0, 0.4, 1.5)))
	Game.impact.connect(_on_impact)
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
		"warmth": stats.warmth,
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
	stats.warmth = float(d.get("warmth", stats.max_warmth))
	stats.effects = d.get("effects", {})
	if d.has("inventory"):
		inventory.from_data(d.inventory)
	elif d.has("items"):   # older saves: item counts only
		inventory.clear(true)
		var items: Dictionary = d.items
		for id: String in items:
			inventory.add(id, int(items[id]), true)


## Fresh start: just a rock in hand (also used after dying).
## Dying drops everything you carried where you fall, and leaves you with a rock.
func reset_inventory() -> void:
	if Net.is_client():
		Net.request("reset", {"pos": global_position})
		inventory.select(0)
		return
	GameActions.drop_all(inventory, global_position)
	inventory.clear(true)
	inventory.add("rock", 1, true)
	inventory.select(0)


## Craft a recipe: a minigame for cooking, ingots and tools (`times` in a row), at once for everything else.
## The answer comes back through `done` ({ok, reason, out, made}) for an instant craft; a minigame reports its
## own progress on screen.
func craft(r: Dictionary, times: int, done: Callable) -> void:
	if CraftSession.mode_for(r) < 0:
		Net.request("craft", {"recipe": r.id, "pos": global_position, "times": times}, done)
		return
	if crafting:
		return
	var problem := CraftSession.problem(self, r)
	if problem != "":
		done.call({"ok": false, "reason": problem})
		return
	crafting_started.emit()
	var session := CraftSession.new()
	get_parent().add_child(session)
	session.begin(self, r, times)


func set_active(on: bool) -> void:
	if not on and crafting:
		crafting.stop(true)   # leaving the world: drop the crafting view straight away
	active = on
	looking_at = {}
	set_physics_process(on)
	set_process(on)
	set_process_unhandled_input(on)
	camera.current = on
	if _ghost and not on:
		_ghost.visible = false
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if crafting:
		return
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

## Moves the body, and walks up any step it would otherwise stop at: when the body is pressed against
## something on the ground, it tries again raised by STEP_UP, walks on at the speed it wants to go, then
## drops back onto whatever it reached.
func _move_with_steps(delta: float, desired: Vector3) -> void:
	var before := global_transform
	var was_on_floor := is_on_floor()
	move_and_slide()
	if swimming or not was_on_floor or not is_on_wall() or desired.length() < 0.01:
		return
	var slid := global_transform
	global_transform = before
	if _climb(desired * delta, before.origin):
		return
	global_transform = slid


## One attempt at a step: up, forward, then down onto the ground there. Keeps the step only if the
## body got most of the way along the wanted walk and landed on something walkable.
func _climb(wanted: Vector3, start: Vector3) -> bool:
	var up := Vector3.UP * STEP_UP
	if test_move(global_transform, up):
		return false   # no room above
	global_position += up
	move_and_collide(wanted)
	var down := move_and_collide(Vector3.DOWN * (STEP_UP + 0.1))
	if down == null:
		return false   # nothing under the step: it's a drop, not a step
	# The rounded foot lands on a tread's edge, so the contact normal is tilted; what matters is that the
	# body rose and kept most of its forward walk.
	var rose := global_position.y - start.y
	var progress := Vector2(global_position.x - start.x, global_position.z - start.z).length()
	return rose > 0.05 and progress >= wanted.length() * 0.5


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var was_swimming := swimming
	swimming = not Game.in_cave and global_position.y + 1.0 < Game.SEA_LEVEL
	if swimming and not was_swimming and velocity.y < -2.0:   # into the water
		Effects.splash(get_parent(), Vector3(global_position.x, Game.SEA_LEVEL, global_position.z), clampf(-velocity.y / 8.0, 0.6, 1.6))
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if not crafting else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	# Timers that make jumping feel forgiving.
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buffer = jump_buffer if Input.is_action_just_pressed("jump") and not crafting else maxf(_jump_buffer - delta, 0.0)

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
	_move_with_steps(delta, Vector3(dir.x, 0.0, dir.z) * speed)

	# Landing: camera dip, thud, fall damage.
	if is_on_floor() and not _was_on_floor and not swimming:
		_land_dip = clampf(fall_speed * 0.018, 0.0, 0.35)
		if fall_speed > 4.0:
			kick(Vector3(-clampf(fall_speed * 0.004, 0.0, 0.06), 0.0, randf_range(-0.01, 0.01)))
		if fall_speed > 3.0:
			Audio.land(fall_speed / 12.0)
		if fall_speed > 5.0:
			_kick_dust(clampf(fall_speed / 10.0, 0.6, 1.6), 8)
		if fall_speed > safe_fall_speed:
			stats.take_damage((fall_speed - safe_fall_speed) * fall_damage_per_ms)
		landed.emit(fall_speed)
	_was_on_floor = is_on_floor()

	# Keep the player on the map, and catch anyone who falls through the world.
	global_position.x = clampf(global_position.x, 4.0, Game.WORLD_SIZE - 4.0)
	global_position.z = clampf(global_position.z, 4.0, Game.WORLD_SIZE - 4.0)
	if global_position.y < -40.0 and not Game.in_cave:
		respawn()

	is_sprinting = sprinting and input != Vector2.ZERO
	_exposure_timer -= delta
	if _exposure_timer <= 0.0:
		_exposure_timer = 0.5
		_update_exposure()
	stats.tick(delta, is_sprinting, _cold, _heat)
	_update_camera(delta, sprinting, input)
	_update_looking_at()
	_update_placement()
	_update_actions(delta)


## A puff of whatever's underfoot: sand, snow, dirt (landing hard, running on loose ground).
func _kick_dust(size: float, count: int) -> void:
	if Game.in_cave or swimming:
		return
	var p := global_position
	var col: Color
	match Game.world_gen.get_surface(p.x, p.z):
		"sand": col = Game.palette.sand
		"snow": col = Game.palette.snow
		"rock": col = Game.palette.rock_light
		_: col = Game.palette.sand.darkened(0.15)
	Effects.dust(get_parent(), p + Vector3(0, 0.1, 0), col.lightened(0.1), count, 0.35 * size, 0.6 * size)


## A blow landed: the arm hangs for a beat and the view jolts with it.
func _blow(weight: float) -> void:
	viewmodel.hit_stop(0.035 + 0.035 * weight)
	kick(Vector3(0.012 * weight, randf_range(-0.006, 0.006) * weight, randf_range(-0.012, 0.012) * weight))


## Knock the camera (radians of pitch, yaw, roll); it springs back by itself.
func kick(by: Vector3) -> void:
	if Settings.camera_shake:
		_kick += by


## Something heavy landed nearby (a tree coming down, a piece finished): a shake that fades with distance.
func _on_impact(at: Vector3, strength: float) -> void:
	if not active:
		return
	var d := global_position.distance_to(at)
	var s := strength * clampf(1.0 - d / 25.0, 0.0, 1.0)
	if s > 0.01:
		_shake = minf(_shake + s * 0.6, 1.0)
		kick(Vector3(s * 0.02, 0.0, randf_range(-1.0, 1.0) * s * 0.02))


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
			if sprinting and surface in ["sand", "snow"] and not Game.in_cave:
				_kick_dust(0.5, 3)

	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))
	var bob_scale := 0.6 if swimming else 1.0
	var bob := Vector3(cos(_bob_time) * 0.035, -absf(sin(_bob_time)) * 0.06, 0.0) * _bob_amount * bob_scale
	# Screen shake when hurt (decays quickly).
	_shake = maxf(_shake - delta * 2.5, 0.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.08
	if not Settings.camera_shake:
		shake = Vector3.ZERO
	camera.position = bob + Vector3(0, -_land_dip, 0) + shake
	# Blows knock the view and it springs back; strafing leans into the turn a little.
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	var lean_to := -input.x * (0.03 if sprinting else 0.015) if Settings.camera_shake and is_on_floor() else 0.0
	_lean = lerpf(_lean, lean_to, 1.0 - exp(-6.0 * delta))
	camera.rotation = Vector3(_kick.x, _kick.y, _kick.z + _lean)

	_fov_kick = lerpf(_fov_kick, 9.0 if sprinting and horizontal > 6.0 else 0.0, 1.0 - exp(-6.0 * delta))
	camera.fov = Settings.fov + _fov_kick
	viewmodel.update_motion(delta, _bob_time, _bob_amount)
	underwater = not Game.in_cave and camera.global_position.y < Game.SEA_LEVEL - 0.05


## What the crosshair says about a building piece. The hammer shows its health (or, on a blueprint, how far it's
## built and what it needs) and builds or repairs it; the right tool for its material knocks it down.
func _piece_look(sid: String, st: Dictionary) -> Dictionary:
	var name := ItemDB.display_name(st.kind)
	var tool_type: String = ItemDB.tool_stats(inventory.selected_item()).get("type", "")
	var look := {"name": name, "label": "Building piece", "structure": sid}
	if GameActions.is_decor(st.kind):
		look.label = {"furniture": "Furniture", "lights": "Light", "storage": "Storage"}.get(String(GameActions.DECOR[st.kind].page), "Furniture")
	var hp := GameActions.piece_health(st)
	if GameActions.is_blueprint(st):
		look.name = "%s blueprint" % name
		look.label = "Blueprint · %d%% built" % roundi(float(st.get("built", 0.0)) * 100.0)
		if tool_type == "hammer":
			look.label += " · costs %s" % _cost_text(GameActions.PIECE_COSTS.get(st.kind, {}))
			look.attack = "Build"
		elif tool_type != "plan":
			look.attack = "Take down"
	else:
		if tool_type == "hammer":
			look.label = "Health %d / %d" % [ceili(hp.x), roundi(hp.y)]
			if hp.x < hp.y - 0.01:
				look.attack = "Repair"
		elif tool_type == GameActions.BREAK_TOOL[GameActions.piece_mat(st.kind)]:
			look.label = "Health %d / %d" % [ceili(hp.x), roundi(hp.y)]
			look.attack = "Take down" if GameActions.is_decor(st.kind) else "Knock down"
		if GameActions.DECOR.get(st.kind, {}).has("slots"):
			look.chest = sid
			look.interact = "Open"
		if st.kind in GameActions.DOOR_KINDS:
			look.door = sid
			look.interact = "Close" if bool(st.get("open", false)) else "Open"
	return look


static func _cost_text(items: Dictionary) -> String:
	var parts: Array[String] = []
	for item: String in items:
		parts.append("%d %s" % [int(items[item]), ItemDB.display_name(item)])
	return ", ".join(parts)


func _update_looking_at() -> void:
	looking_at = {}
	if not ray.is_colliding():
		return
	var body := ray.get_collider() as CollisionObject3D
	if not body or ray.get_collision_point().distance_to(camera.global_position) > REACH + 0.6:
		return
	if body.has_meta("cave_chest"):
		var cid := int(body.get_meta("cave_chest"))
		var opened: bool = Game.looted.has("cave_chest_%d" % cid)
		looking_at = {"name": "Supply chest", "label": "Chest", "cave_chest": cid, "interact": "" if opened else "Open"}
		return
	if body.has_meta("pickup"):
		var pid: String = body.get_meta("pickup")
		if Game.pickups.has(pid):
			var p: Dictionary = Game.pickups[pid]
			looking_at = {"name": "%s%s" % [ItemDB.display_name(p.item), (" x%d" % p.count) if int(p.count) > 1 else ""],
				"label": "Dropped item", "pickup": pid, "interact": "Pick up"}
		return
	if body.has_meta("structure"):
		var sid: String = body.get_meta("structure")
		if Game.structures.has(sid):
			var st: Dictionary = Game.structures[sid]
			if GameActions.is_building(st.kind):
				looking_at = _piece_look(sid, st)
			elif st.kind in Recipes.STATION_NAMES and st.kind != "":
				looking_at = {"name": ItemDB.display_name(st.kind), "label": "Crafting station", "structure": sid,
					"station": st.kind, "interact": "Craft", "attack": "Pack up"}
			else:
				looking_at = {"name": ItemDB.display_name(st.kind), "label": "Structure", "structure": sid, "attack": "Pack up"}
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
	if key in ItemDB.PICKUP_KEYS:
		return "Uproot" if key == "sapling" else "Pick up"
	if Game.is_harvested(r.id):
		return "(nothing left yet)"
	match key:
		"berry": return "Pick berries"
		"fruit_tree": return "Shake for fruit"
		"tree", "conifer": return "Gather sticks"
		"cactus": return "Cut flesh"
		"agave", "bush", "reeds": return "Pull fiber"
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
	if not focused or viewmodel.is_busy() or crafting:
		return
	if Input.is_action_pressed("interact") and not wheel_open and _interact_cooldown <= 0.0 and looking_at.get("interact", "") != "":
		_interact_cooldown = 0.35
		viewmodel.reach()
		return
	if not Input.is_action_pressed("attack") or _swing_cooldown > 0.0:
		return
	var item := inventory.selected_item()
	if item != "" and ItemDB.tool_stats(item).get("type", "") == "plan":
		_swing_cooldown = 0.3
		if wheel_open:
			return
		if placement.get("ok", false):
			var at: Vector3 = placement.pos
			Net.request("place_blueprint", {"kind": placement.kind, "pos": at, "yaw": placement.yaw}, func(res: Dictionary) -> void:
				if res.get("ok", false):
					Audio.play_3d("click", at, -4.0, 1.1)
				elif res.get("reason", "") != "":
					hint.emit(res.reason))
		elif placement.get("reason", "") != "":
			hint.emit(placement.reason)
		return
	if item != "" and ItemDB.info(item).kind == "placeable" and looking_at.is_empty():
		_swing_cooldown = 0.4
		if placement.get("ok", false):
			var at: Vector3 = placement.pos
			Net.request("place", {"slot": inventory.selected, "pos": at, "yaw": placement.yaw}, func(res: Dictionary) -> void:
				if res.get("ok", false):
					Audio.play_3d("thud", at, -2.0, 0.8)
					Effects.dust(get_parent(), at + Vector3.UP * 0.15, Game.palette.sand.darkened(0.1), 6, 0.45, 0.6)
				elif res.get("reason", "") != "":
					hint.emit(res.reason))
		elif placement.get("reason", "") != "":
			hint.emit(placement.reason)
		return
	if item != "" and ItemDB.info(item).kind == "food":
		_swing_cooldown = 0.6
		viewmodel.eat(func() -> void:
			Net.request("consume", {"slot": inventory.selected}, func(taken: Dictionary) -> void:
				if not taken.get("ok", false):
					return
				var res := GameActions.apply_food(stats, String(taken.id))
				Audio.play(Audio.sfx.munch, -4.0)
				if res.first_time:
					var e: Dictionary = ItemDB.EFFECTS[res.effect]
					hint.emit("%s: %s" % [e.name, e.desc])
				elif ItemDB.info(res.id).get("health", 0.0) < 0.0:
					hint.emit("That didn't sit well...")))
		return
	if item != "" and ItemDB.info(item).kind != "tool":
		return   # holding a material: nothing to swing
	var tool := ItemDB.tool_stats(item)
	_swing_cooldown = tool.cooldown
	viewmodel.swing(tool.cooldown, String(tool.type))
	Net.note_swing()
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
		_blow(0.9)
		# Fighting something that fights back is combat; chasing down prey is a hunt.
		if animal.state in [animal.State.ATTACK, animal.State.WARN] or animal.species.role == "defensive":
			Music.combat_ping(0.8)
		else:
			Music.hunt_ping(0.8)
		Net.request("hit_animal", {"animal": animal.net_id, "slot": inventory.selected, "from": global_position})
		Audio.play_3d("thud", point)
		Effects.blood(get_parent(), point, point - global_position + Vector3.UP * 0.3, 1.0)
		return
	if look.has("structure"):
		hit_landed.emit()
		_blow(0.6)
		var hammer: bool = ItemDB.tool_stats(inventory.selected_item()).get("type", "") == "hammer"
		Audio.play_3d("clink" if hammer else "chop", point, -2.0, 1.15 if hammer else 0.8)
		var smat := GameActions.piece_mat(String(Game.structures.get(look.structure, {}).get("kind", "")))
		var scol: Color = Effects.MAT_DUST.get(smat, Game.palette.bark.lightened(0.2))
		if smat == "wood":
			Effects.splinters(get_parent(), point, scol.lightened(0.1), scol.darkened(0.2), 5)
		else:
			Effects.shards(get_parent(), point, scol, 6)
		Net.request("hit_structure", {"structure": look.structure, "slot": inventory.selected}, func(res: Dictionary) -> void:
			if res.get("packed", false):
				hint.emit("Packed up the %s" % ItemDB.display_name(res.kind))
			elif res.get("finished", false):
				hint.emit("Finished building")
			elif res.get("destroyed", false):
				hint.emit("Knocked down the %s" % ItemDB.display_name(res.kind))
			elif res.get("removed", false):
				hint.emit("Took down the blueprint")
			elif not res.get("ok", false) and res.get("reason", "") != "":
				hint.emit(res.reason))
		return
	if look.has("resource"):
		_hit_resource(look.chunk, look.resource, point)


func _hit_resource(_chunk: TerrainChunk, r: Dictionary, point: Vector3) -> void:
	var args := {"id": r.id, "kind": r.kind, "key": r.key, "slot": inventory.selected, "pos": point, "from": global_position}
	Net.request("hit_resource", args, func(res: Dictionary) -> void: _on_hit_resource(res, r, point))


## The result of a swing at a tree / rock / plant: sounds, chips and hints. (How the thing
## itself changes, wobbling or falling, is applied by World for everyone who can see it.)
func _on_hit_resource(res: Dictionary, r: Dictionary, point: Vector3) -> void:
	if not res.has("target"):
		return
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
	if not res.get("ok", false):
		return
	hit_landed.emit()
	_blow(1.0 if target in ["tree", "rock"] else 0.4)
	_drop_overflow(res.items, point)
	match target:
		"tree":
			Audio.play_3d("chop", point)
			var bark := Effects.bark_color(r.kind)
			Effects.splinters(get_parent(), point, bark.lightened(0.45), bark, 8)
			if Effects.has_leaves(r.kind) and FloraLibrary.category_of(r.kind) == "tree":
				var top := Vector3(point.x, (r.transform as Transform3D).origin.y + 3.5, point.z)
				Effects.leaves(get_parent(), top, Effects.leaf_color(r.kind), 4, 1.2)
		"rock":
			Audio.play_3d("clink", point, -2.0)
			var col := pal.rock.lightened(0.1)
			if r.kind.begins_with("ore") or r.kind.begins_with("gem"):
				col = ItemDB.tier_info(int(r.kind.right(1))).color
			Effects.shards(get_parent(), point, col, 9)
			if r.kind.begins_with("ore") or r.kind.begins_with("gem"):
				Effects.sparks(get_parent(), point, col.lightened(0.3), 5, 3.0)
		_:
			Audio.play_3d("rustle", point)
			Effects.leaves(get_parent(), point, Effects.leaf_color(r.kind), 7, 0.3)
			Effects.chips(get_parent(), point, Effects.leaf_color(r.kind), 5, 0.05, 2.0)


## Interact: the viewmodel's hand reached out.
func _on_grab() -> void:
	var look := looking_at
	if look.has("cave_chest"):
		cave_chest.emit(int(look.cave_chest))
		return
	if look.has("door"):
		Net.request("toggle_door", {"structure": look.door})
		return
	if look.has("chest"):
		open_chest.emit(String(look.chest))
		return
	if look.has("station"):
		open_crafting.emit(String(look.station))
		return
	if look.has("pickup"):
		var ppos: Array = Game.pickups.get(look.pickup, {}).get("pos", [])
		Net.request("pick_up", {"pickup": look.pickup}, func(res: Dictionary) -> void:
			if int(res.get("got", 0)) > 0:
				Audio.play(Audio.sfx.pickup, -6.0)
				if ppos.size() == 3:
					Effects.twinkle(get_parent(), Vector3(ppos[0], ppos[1], ppos[2]) + Vector3(0, 0.25, 0), Color(1.0, 0.92, 0.6), 5, 0.7)
			else:
				hint.emit("Your satchel is full"))
		return
	if look.has("animal"):
		if not is_instance_valid(look.animal):
			return
		var animal: Node = look.animal
		Net.request("carcass", {"animal": animal.net_id, "slot": inventory.selected}, func(res: Dictionary) -> void:
			if res.get("ok", false) and is_instance_valid(animal):
				Audio.play_3d("thud", animal.global_position, -6.0)
				_drop_overflow(res.items, animal.global_position))
		return
	if look.has("resource"):
		var r: Dictionary = look.resource
		var at: Vector3 = r.transform.origin + Vector3.UP * 0.5
		var args := {"id": r.id, "kind": r.kind, "key": r.key, "pos": at, "from": global_position}
		Net.request("harvest_resource", args, func(res: Dictionary) -> void:
			if res.get("empty", false):
				hint.emit("Nothing to gather here right now")
			elif res.get("ok", false):
				_drop_overflow(res.items, at)
				Audio.play_3d("rustle", at, -4.0, 1.2))


## Whatever didn't fit in the satchel was dropped on the ground (by whoever ran the action).
func _drop_overflow(items: Dictionary, _at: Vector3) -> void:
	for k: String in items:
		if k.begins_with("_overflow_"):
			hint.emit("Satchel full - some items fell on the ground")
			return


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
	Net.request("drop", {"slot": slot, "amount": int(s.count) if whole_stack else 1, "pos": pos})
	Audio.play(Audio.sfx.click, -8.0, 0.8)


# --- Placing stations -----------------------------------------------------------------

## What the held item places: a station's kind, the building wheel's piece for the Building Plan, or "".
func held_build_kind() -> String:
	var item := inventory.selected_item()
	if item == "":
		return ""
	var info := ItemDB.info(item)
	if info.get("kind", "") == "placeable":
		return String(info.station)
	if ItemDB.tool_stats(item).get("type", "") == "plan":
		var page := int(build_choice.get("page", 0))
		if page > 0:
			return String(build_choice.get("decor%d" % page, BuildWheel.page_items(page)[0]))
		return GameActions.piece_kind(String(build_choice.shape), String(build_choice.mat))
	return ""


func _update_placement() -> void:
	var kind_now := held_build_kind()
	if kind_now == "" or not active or wheel_open:
		placement = {}
		if _ghost:
			_ghost.visible = false
		return
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var pos := Vector3.INF
	# Building pieces snap to whatever the crosshair is on: the ground, a foundation's top, a wall face.
	if GameActions.is_building(kind_now) and ray.is_colliding() and ray.get_collision_point().distance_to(from) <= REACH + 2.0:
		var hit := ray.get_collision_point()
		if ray.get_collider().name != "TerrainBody" and not ray.get_collider().has_meta("structure") and ray.get_collider().get_parent() is TerrainChunk:
			hit = Vector3.INF   # plants and rocks don't count: aim at the ground behind them instead
		if hit != Vector3.INF:
			pos = hit
	if pos == Vector3.INF:
		# March along the view ray until it meets the ground (max ~6 m); else 3 m ahead.
		var d := 0.5
		while d < 6.0:
			var p := from + dir * d
			if p.y <= Game.world_gen.get_height(p.x, p.z):
				pos = p
				break
			d += 0.2
	if pos == Vector3.INF:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		pos = global_position + flat * 3.0
	if not GameActions.is_building(kind_now) or GameActions.is_decor(kind_now):
		# A station (or furniture, a light...) stands on the ground, or on the top of a floor when that's what you're
		# aiming at.
		pos.y = Game.world_gen.get_height(pos.x, pos.z)
		if ray.is_colliding() and ray.get_collider().has_meta("structure") and ray.get_collision_normal().y > 0.7 \
				and ray.get_collision_point().distance_to(from) <= REACH + 2.0:
			var top := ray.get_collision_point()
			var under := GameActions.floor_under(top)
			if not under.is_empty():
				pos = top
				pos.y = float(under.pos[1]) + GameActions.FLOOR_TOP   # exactly on its top, not in it
	if Input.is_action_just_pressed("rotate_piece"):
		_place_turns = (_place_turns + 1) % 4
	var yaw := rotation.y + PI + _place_turns * PI * 0.5
	var kind := kind_now
	if GameActions.is_building(kind) and not GameActions.is_decor(kind):
		# Building pieces snap to the grid (and walls to a foundation edge).
		var prefer := float(placement.get("yaw", -1.0)) if placement.get("kind", "") == kind else -1.0
		var snap := GameActions.snap_piece(kind, pos, prefer, rotation.y)
		pos = snap.pos
		yaw = snap.yaw
		if kind in GameActions.EDGE_KINDS:
			yaw += PI * (_place_turns % 2)   # a wall stays on its edge, so Rotate flips which face looks out
		else:
			yaw += _place_turns * PI * 0.5
		_snapped_level = int(snap.get("level", 0))
	yaw = fposmod(yaw, TAU)
	var flat_dist := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	var reason := GameActions.placement_problem(pos, kind, yaw)
	if reason == "" and flat_dist < 1.2:
		reason = "Too close to you"
	if reason == "" and GameActions.is_building(kind) and not GameActions.is_decor(kind) and _overlaps_player(pos, kind, yaw):
		reason = "You're standing there"
	var level := int(_snapped_level)
	var label := ItemDB.display_name(kind)
	if GameActions.is_building(kind):
		label += " blueprint"
		if level > 0:
			label += " (level %d)" % (level + 1)
	placement = {"ok": reason == "", "reason": reason, "pos": pos, "yaw": yaw, "name": label, "kind": kind}
	if not _ghost:
		_ghost = MeshInstance3D.new()
		_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost_ok_mat = _ghost_material(Color(0.55, 1.0, 0.6, 0.45))
		_ghost_bad_mat = _ghost_material(Color(1.0, 0.4, 0.35, 0.45))
		get_parent().add_child(_ghost)
	if _ghost_kind != kind:
		_ghost_kind = kind
		_ghost.mesh = StructureModels.get_model(kind, _ghost_ok_mat, _ghost_ok_mat).body
	_ghost.visible = true
	_ghost.material_override = _ghost_ok_mat if placement.ok else _ghost_bad_mat
	_ghost.global_position = pos
	_ghost.rotation = Vector3(0, yaw, 0)


## Would a piece at pos overlap the player's body (feet to head, about 0.4 m around)?
func _overlaps_player(pos: Vector3, kind: String, yaw: float) -> bool:
	var half := Vector2(GameActions.CELL * 0.5, GameActions.CELL * 0.5)
	if kind in GameActions.EDGE_KINDS:
		half = Vector2(GameActions.CELL * 0.5, 0.15) if absf(sin(yaw)) < 0.5 else Vector2(0.15, GameActions.CELL * 0.5)
	elif kind in GameActions.COVER_KINDS:
		half = Vector2(GameActions.CELL * 0.5, GameActions.CELL * 0.5)
	var lo := pos.y - 0.2
	var hi := pos.y + 3.2
	var feet := global_position.y
	var top := feet + 1.85
	if top < lo or feet > hi:
		return false
	return absf(global_position.x - pos.x) < half.x + 0.4 and absf(global_position.z - pos.z) < half.y + 0.4


func _ghost_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


# --- Cold & warmth ----------------------------------------------------------------------

const FIRE_WARMTH_RANGE := 7.0

## How cold it is here right now, and how much nearby fire (or a held torch) warms you.
func _update_exposure() -> void:
	var p := global_position
	var gen: WorldGen = Game.world_gen
	var night := 1.0 - Game.daylight()
	if Game.in_cave:
		# Underground there is no sun; the cold and dark are worst without a light in hand.
		_cold = 0.5 if inventory.selected_item() == "torch" else 1.3
		_heat = 0.0
		if inventory.selected_item() == "torch":
			_heat += 0.45
		return
	var h := gen.get_height(p.x, p.z)
	var w := gen.get_biome_weights(gen.get_climate(p.x, p.z, h))
	var cold_biome := 0.0
	for b: int in WorldGen.COLD_BIOMES:
		cold_biome += w.get(b, 0.0)
	cold_biome = maxf(cold_biome, smoothstep(45.0, 75.0, h))   # thin, cold air up high
	_cold = night * 0.8 + cold_biome * (0.7 + night * 1.0)
	if swimming:
		_cold += 1.2
	_heat = 0.0
	if inventory.selected_item() == "torch":
		_heat += 0.45
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if not st.kind in ["campfire", "forge"]:
			continue
		var sp: Array = st.pos
		var d := p.distance_to(Vector3(sp[0], sp[1], sp[2]))
		if d < FIRE_WARMTH_RANGE:
			_heat += (8.0 if st.kind == "campfire" else 5.0) * (1.0 - d / FIRE_WARMTH_RANGE * 0.6)
	if _heat > 1.0:
		_cold = 0.0   # standing by a fire: no chill at all
