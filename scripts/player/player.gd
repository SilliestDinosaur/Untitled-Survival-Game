extends CharacterBody3D
## First-person player: mouse look, walk/sprint/jump, swimming, fall damage,
## head bob, footsteps, gathering / hunting with the held tool, and "what am I looking at".

signal landed(impact: float)
signal hint(text: String)   ## short messages for the HUD ("Too hard to break by hand")

const REACH := 3.2

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

var active := false
var spawn_point := Vector3.ZERO
var swimming := false
var underwater := false
## What the crosshair is on: {} or {"name", "label", "resource"}.
var looking_at := {}
var inventory := Inventory.new()
var viewmodel: Viewmodel
var _rng := RandomNumberGenerator.new()
var _swing_cooldown := 0.0
var is_sprinting := false   ## animals hear you from farther away

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
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	viewmodel.strike.connect(_on_strike)
	inventory.changed.connect(func() -> void: viewmodel.hold(inventory.selected_item()))
	reset_inventory()
	set_active(false)


## Fresh start: just a rock in hand (also used after dying).
func reset_inventory() -> void:
	inventory.clear()
	inventory.add("rock", 1)
	inventory.select(0)


func set_active(on: bool) -> void:
	active = on
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
		head.rotate_x(-event.relative.y * sens)
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
	camera.position = bob + Vector3(0, -_land_dip, 0)

	_fov_kick = lerpf(_fov_kick, 9.0 if sprinting and horizontal > 6.0 else 0.0, 1.0 - exp(-6.0 * delta))
	camera.fov = Settings.fov + _fov_kick
	viewmodel.update_motion(delta, _bob_time, _bob_amount)
	underwater = camera.global_position.y < Game.SEA_LEVEL - 0.05


func _update_looking_at() -> void:
	looking_at = {}
	if not ray.is_colliding():
		return
	var body := ray.get_collider() as CollisionObject3D
	if body and body.has_meta("animal"):
		var animal: Node = body.get_meta("animal")
		looking_at = {
			"name": animal.species.name,
			"label": "Carcass" if animal.dead else animal.species.label,
			"animal": animal,
		}
		return
	if body and body.get_parent() is TerrainChunk:
		var res: Dictionary = (body.get_parent() as TerrainChunk).resource_from_hit(body, ray.get_collider_shape())
		if not res.is_empty():
			looking_at = {
				"name": Game.flora.display_name(res.kind),
				"label": FloraLibrary.KINDS[res.kind].label,
				"resource": res,
				"chunk": body.get_parent(),
			}


func respawn() -> void:
	global_position = spawn_point + Vector3.UP * 1.5
	velocity = Vector3.ZERO
	stats.reset()



# --- Gathering, hunting, eating -------------------------------------------------

func _update_actions(delta: float) -> void:
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	var focused := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	if not focused or not Input.is_action_pressed("attack"):
		return
	if viewmodel.is_busy() or _swing_cooldown > 0.0:
		return
	var item := inventory.selected_item()
	if item != "" and ItemDB.info(item).kind == "food":
		_eat(item)
		return
	var tool := ItemDB.tool_stats(item)
	_swing_cooldown = tool.cooldown
	viewmodel.swing(tool.cooldown)
	Audio.play("swoosh", -10.0)


func _eat(item: String) -> void:
	var info := ItemDB.info(item)
	viewmodel.eat(func() -> void:
		if not inventory.remove(item, 1):
			return
		stats.eat(info.get("food", 0.0))
		var hp: float = info.get("health", 0.0)
		if hp > 0.0:
			stats.health = minf(stats.max_health, stats.health + hp)
		elif hp < 0.0:
			stats.take_damage(-hp)
			hint.emit("Raw meat doesn't sit well...")
		Audio.play(Audio.sfx.munch, -4.0))


## Called by the viewmodel at the moment the swing lands.
func _on_strike() -> void:
	if not ray.is_colliding() or ray.get_collision_point().distance_to(camera.global_position) > REACH:
		return
	var point := ray.get_collision_point()
	var item := inventory.selected_item()
	var look := looking_at
	if look.has("animal"):
		var animal: Node = look.animal
		if animal.dead:
			var res := Gathering.hit_carcass(animal, item, inventory, _rng)
			Audio.play_3d("thud", point, -2.0)
			Effects.chips(get_parent(), point, Color(0.6, 0.15, 0.15), 8, 0.06)
			if res.destroyed:
				animal.consume_carcass()
		else:
			animal.take_hit(ItemDB.tool_stats(item).damage, global_position)
			Audio.play_3d("thud", point)
			Effects.chips(get_parent(), point, Color(0.65, 0.12, 0.12), 6, 0.05)
		return
	if look.has("resource"):
		_hit_resource(look.chunk, look.resource, item, point)


func _hit_resource(chunk: TerrainChunk, r: Dictionary, item: String, point: Vector3) -> void:
	var res := Gathering.hit_resource(chunk, r.index, item, inventory, _rng)
	var target: String = res.target
	var pal: WorldPalette = Game.palette
	if res.blocked:
		Audio.play_3d("clink", point, -6.0, 0.7)
		hint.emit("Too hard to break by hand - use a rock")
		return
	match target:
		"tree":
			Audio.play_3d("chop", point)
			Effects.chips(get_parent(), point, pal.bark.lightened(0.15), 8, 0.07)
		"rock":
			Audio.play_3d("clink", point, -2.0)
			Effects.chips(get_parent(), point, pal.ore_crystal if r.kind == "ore" else pal.rock.lightened(0.1), 9, 0.07, 4.0)
		_:
			Audio.play_3d("rustle", point)
			Effects.chips(get_parent(), point, pal.bush_leaves, 10, 0.06, 2.5)
	if res.destroyed:
		var mesh := chunk.get_resource_mesh(r.index)
		var xf: Transform3D = r.transform
		chunk.remove_resource(r.index)
		if mesh:
			if target == "tree":
				Effects.fall_tree(get_parent(), mesh, xf, xf.origin - global_position, pal.bark)
			else:
				Effects.crumble(get_parent(), mesh, xf)
	else:
		chunk.wobble(r.index)
