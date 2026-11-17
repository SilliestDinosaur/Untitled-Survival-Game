class_name Animal
extends Node3D
## A four- (or two-) legged creature. Moves along the terrain (no physics, to stay cheap),
## steers around cliffs, water and trees, and reacts to the player according to its temperament:
## calm ones barely care, wary ones watch you then leave, skittish ones bolt, curious ones come
## closer. Herds share alarm. Territorial beasts warn first, then charge with a telegraphed hit.

signal removed(animal: Animal)

enum State { IDLE, GRAZE, WANDER, ALERT, FLEE, WARN, ATTACK, DEAD }

var species: FaunaLibrary.Species
var hp := 10.0
var dead := false
var carcass_hp := 0.0
var state := State.IDLE
var player: Node3D
var herd: Array = []          ## other members of this herd (shared array)
var leader: Animal = null     ## herd leader (null = I lead)
## Multiplayer: the host's id for this animal; on guests, animals are puppets that follow the
## host's positions instead of thinking for themselves.
var net_id := -1
var species_index := -1
var puppet := false
var targets: Array = []       ## players to notice (host with guests); empty = just `player`
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _target_cd := 0.0

var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _target := Vector3.ZERO
var _timer := 0.0
var _speed := 0.0
var _yaw := 0.0
var _desired_yaw := 0.0
var _gait := 0.0
var _attack_cd := 0.0
var _windup := -1.0
var _call_cd := 0.0
var _steer_cd := 0.0
var _look_yaw := 0.0
var _look_target := 0.0
var _look_cd := 0.0
var _breath := 0.0
var _rng := RandomNumberGenerator.new()
var _collider: StaticBody3D
var _world: Node


func setup(sp: FaunaLibrary.Species, pos: Vector3, p: Node3D) -> void:
	species = sp
	player = p
	hp = sp.hp
	_rng.randomize()
	_yaw = _rng.randf() * TAU
	_desired_yaw = _yaw
	position = pos
	_breath = _rng.randf() * TAU
	_call_cd = _rng.randf_range(4.0, 20.0)

	_body = Node3D.new()
	_body.position.y = sp.leg_len + sp.body_h * 0.25
	add_child(_body)
	_body.add_child(_mesh(sp.body_mesh))
	_head = Node3D.new()
	_head.position = sp.head_pivot
	_head.add_child(_mesh(sp.head_mesh))
	_body.add_child(_head)
	for off in sp.leg_offsets:
		var leg := Node3D.new()
		leg.position = off
		var hind: bool = off.z > 0.0 and sp.leg_offsets.size() == 4 and sp.hind_leg_mesh != null
		leg.add_child(_mesh(sp.hind_leg_mesh if hind else sp.leg_mesh))
		_body.add_child(leg)
		_legs.append(leg)

	# Hit box on the "interact" layer: the crosshair and tools can hit it, the player walks through.
	_collider = StaticBody3D.new()
	_collider.collision_layer = TerrainChunk.LAYER_INTERACT
	_collider.collision_mask = 0
	_collider.set_meta("animal", self)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(sp.body_w * 1.2, 0.4), sp.body_h * 1.2 + sp.leg_len * 0.6, maxf(sp.body_len * 1.3, 0.5))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, sp.body_h * 0.6 - shape.size.y * 0.5, -sp.body_len * 0.1)
	_collider.add_child(cs)
	_body.add_child(_collider)
	_enter(State.GRAZE if _rng.randf() < 0.6 else State.IDLE)


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


func _enter(s: State) -> void:
	state = s
	if s == State.ATTACK:
		Music.combat_ping(1.0)
	match s:
		State.IDLE:
			_timer = _rng.randf_range(2.0, 5.0)
		State.GRAZE:
			_timer = _rng.randf_range(5.0, 12.0)
		State.WANDER:
			_timer = 25.0
			_pick_wander_target()
		State.ALERT:
			_timer = _rng.randf_range(1.2, 2.5)
		State.FLEE:
			_timer = _rng.randf_range(5.0, 8.0)
			# Prey bolting from a nearby player sets the hunting mood (a little).
			if player and position.distance_to(player.global_position) < 25.0:
				Music.hunt_ping(0.15)
		State.WARN:
			_timer = 4.0
		State.ATTACK:
			_timer = 12.0
			_windup = -1.0


func _pick_wander_target() -> void:
	# Herd members drift toward their leader instead of wandering off alone.
	if is_instance_valid(leader) and not leader.dead:
		_target = leader.position + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
		return
	# Habitat: marsh animals drift toward the water's edge, cliff dwellers toward slopes.
	var best := position
	var best_score := -1e9
	for i in 8:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(8.0, 22.0)
		var t := position + Vector3(cos(a) * d, 0, sin(a) * d)
		var h: float = Game.world_gen.get_height(t.x, t.z)
		var max_h := 80.0 if species.habitat == "steep" else 55.0
		if h <= 2.0 or h >= max_h:
			continue
		var score := _rng.randf()
		match species.habitat:
			"water": score += 2.0 - minf(h, 8.0) * 0.25
			"steep": score += (1.0 - Game.world_gen.get_normal(t.x, t.z).y) * 6.0 + h * 0.01
		if score > best_score:
			best_score = score
			best = t
		if species.habitat == "":
			break
	_target = best


## Something scared a herd member: everyone nearby runs.
func alarm() -> void:
	if dead or species.flee_radius <= 0.0:
		return
	if state != State.FLEE:
		_enter(State.FLEE)


func _alarm_herd() -> void:
	for other in herd:
		if is_instance_valid(other) and other != self and other.position.distance_to(position) < 25.0:
			other.alarm()


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_step(delta)
		return
	if dead:
		return
	# With several players around, pay attention to whoever is closest.
	_target_cd -= delta
	if _target_cd <= 0.0 and targets.size() > 1:
		_target_cd = 0.5
		var best := 1e9
		for t in targets:
			if is_instance_valid(t):
				var d: float = (t as Node3D).global_position.distance_squared_to(position)
				if d < best:
					best = d
					player = t
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_call_cd -= delta
	_timer -= delta
	var to_player := player.global_position - position if player else Vector3(1e6, 0, 0)
	to_player.y = 0.0
	var dist := to_player.length()
	var sprinting: bool = player != null and bool(player.get("is_sprinting"))
	_perceive(dist, sprinting)

	var want_dir := Vector3.ZERO
	var want_speed := 0.0
	var graze := 0.0
	var alert := 0.0
	match state:
		State.IDLE, State.GRAZE:
			graze = 1.0 if state == State.GRAZE else 0.0
			if _timer <= 0.0:
				_enter(State.WANDER if _rng.randf() < 0.65 else (State.GRAZE if state == State.IDLE else State.IDLE))
		State.WANDER:
			var d := _target - position
			d.y = 0.0
			if d.length() < 1.2 or _timer <= 0.0:
				_enter(State.GRAZE if _rng.randf() < 0.6 else State.IDLE)
			else:
				want_dir = d.normalized()
				want_speed = species.walk_speed
		State.ALERT:
			# Stand still, head up, face the player; then decide.
			alert = 1.0
			_desired_yaw = atan2(-to_player.x, -to_player.z)
			if _timer <= 0.0:
				if species.temperament == "curious" and dist > 4.0 and not sprinting:
					_enter(State.WANDER)
					_target = player.global_position - to_player.normalized() * 4.0   # come closer for a look
				elif dist < species.flee_radius:
					_enter(State.FLEE)
					_alarm_herd()
					_call()
				else:
					_enter(State.GRAZE)
		State.FLEE:
			want_dir = -to_player.normalized() if dist > 0.01 else Vector3.FORWARD
			want_speed = species.run_speed
			if _timer <= 0.0 and dist > species.flee_radius * 1.8:
				_enter(State.IDLE)
		State.WARN:
			# Territorial: face the intruder, head low, snorting.
			alert = 1.0
			_desired_yaw = atan2(-to_player.x, -to_player.z)
			if _call_cd <= 0.0:
				_call_cd = 1.6
				_call(0.9)
			if dist < 3.6:
				_enter(State.ATTACK)
			elif dist > 12.0 or _timer <= 0.0:
				_enter(State.IDLE)
		State.ATTACK:
			if _timer <= 0.0 or dist > 30.0:
				_enter(State.IDLE)
			elif _windup >= 0.0:
				# Rearing back before the hit: the player can see it coming and step away.
				_windup -= delta
				_desired_yaw = atan2(-to_player.x, -to_player.z)
				if _windup < 0.0:
					if dist < 2.0 + species.size * 0.7:
						_bite()
					_attack_cd = 1.2
			elif dist > 1.5 + species.size * 0.6:
				want_dir = to_player.normalized()
				want_speed = species.run_speed
			elif _attack_cd <= 0.0:
				_windup = 0.45
				_call(0.8)

	_move(delta, want_dir, want_speed)
	_animate(delta, graze, alert)

	if _call_cd <= 0.0 and state in [State.IDLE, State.GRAZE, State.WANDER]:
		_call_cd = _rng.randf_range(10.0, 30.0)
		if dist < 60.0:
			_call()


## Decide whether the player is worth reacting to.
func _perceive(dist: float, sprinting: bool) -> void:
	if state in [State.FLEE, State.ATTACK, State.DEAD]:
		return
	if species.role == "defensive":
		if dist < 9.0 and state != State.WARN:
			_enter(State.WARN)
		return
	if species.flee_radius <= 0.0:
		return
	var radius := species.flee_radius * (1.7 if sprinting else 1.0)
	if dist < radius * 0.45:
		_enter(State.FLEE)   # far too close: bolt immediately
		_alarm_herd()
		_call()
	elif dist < radius and state != State.ALERT:
		if species.temperament == "calm" and not sprinting:
			return   # calm animals don't mind someone walking by
		_enter(State.ALERT)


## Move with a limited turn rate, steering around steep ground, water and trees.
func _move(delta: float, want_dir: Vector3, want_speed: float) -> void:
	_steer_cd -= delta
	if want_dir.length_squared() > 0.000001 and want_speed > 0.0 and _steer_cd <= 0.0:
		_steer_cd = 0.25
		_desired_yaw = _best_heading(want_dir)
	var turn_rate := (4.5 if want_speed > species.walk_speed * 1.5 else 2.2) * delta
	_yaw = rotate_toward(_yaw, _desired_yaw, turn_rate)
	# Slow down while turning sharply, speed up smoothly.
	var facing := cos(angle_difference(_yaw, _desired_yaw))
	_speed = lerpf(_speed, want_speed * clampf(facing, 0.25, 1.0), 1.0 - exp(-3.0 * delta))
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var next := position + forward * _speed * delta
	var h: float = Game.world_gen.get_height(next.x, next.z)
	if _speed > 0.01:
		if _walkable(next, h):
			position.x = next.x
			position.z = next.z
			_gait += _speed * delta / maxf(species.leg_len * 1.6, 0.2) * PI   # stride locked to distance
		else:
			_speed *= 0.5
			_steer_cd = 0.0
	position.y = lerpf(position.y, Game.world_gen.get_height(position.x, position.z), 1.0 - exp(-14.0 * delta))
	rotation = Vector3(0, _yaw, 0)


func _walkable(p: Vector3, h: float) -> bool:
	return h > 1.3 and h < 62.0 and Game.world_gen.get_normal(p.x, p.z).y > 0.7


## Pick the heading closest to `want` whose next few meters are walkable and free of trees.
func _best_heading(want: Vector3) -> float:
	var base := atan2(-want.x, -want.z)
	var look := maxf(2.5, species.body_len * 2.0)
	var best := base
	var best_score := -1e9
	for off in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]:
		var a: float = base + off
		var dir := Vector3(-sin(a), 0, -cos(a))
		var p := position + dir * look
		var h: float = Game.world_gen.get_height(p.x, p.z)
		if not _walkable(p, h):
			continue
		var score: float = -absf(off) - _obstacle_penalty(p)
		if score > best_score:
			best_score = score
			best = a
	return best


## Trees and rocks near a point (looked up in the loaded chunk's resource list).
func _obstacle_penalty(p: Vector3) -> float:
	if not _world:
		_world = get_node_or_null("/root/Main/World")
		if not _world:
			return 0.0
	var chunk = _world.get_chunk(_world.world_to_chunk(p))
	if not chunk:
		return 0.0
	var penalty := 0.0
	for r in chunk.resources:
		if r.get("removed", false) or not FloraLibrary.KINDS[r.kind].solid:
			continue
		var o: Vector3 = r.transform.origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < 1.6:
			penalty += (1.6 - d) * 2.0
	return penalty


func _animate(delta: float, graze: float, alert: float) -> void:
	var stride := clampf(_speed / maxf(species.run_speed, 0.1), 0.0, 1.0)
	var moving := clampf(_speed / 0.4, 0.0, 1.0)
	var swing := (0.32 + stride * 0.4) * moving
	# Walk: diagonal pairs together. Run: front pair and back pair together (bound).
	var phases := [0.0, PI, PI, 0.0] if stride < 0.55 else [0.0, 0.3, PI, PI + 0.3]
	if _legs.size() == 2:
		phases = [0.0, PI]
	for i in _legs.size():
		var ph: float = _gait + phases[i]
		_legs[i].rotation.x = lerp_angle(_legs[i].rotation.x, sin(ph) * swing, 1.0 - exp(-20.0 * delta))
	# Body: bob with the steps, breathe when still, lean into turns and slopes.
	_breath += delta * 1.7
	var base_y := species.leg_len + species.body_h * 0.25
	var bob := absf(sin(_gait)) * 0.05 * species.size * moving
	_body.position.y = base_y + bob + sin(_breath) * 0.006 * species.size * (1.0 - moving)
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var side := Vector3(-fwd.z, 0, fwd.x)
	var half := species.body_len * 0.5
	var g: WorldGen = Game.world_gen
	var pitch := atan2(g.get_height(position.x + fwd.x * half, position.z + fwd.z * half) - g.get_height(position.x - fwd.x * half, position.z - fwd.z * half), species.body_len)
	var roll := atan2(g.get_height(position.x + side.x * 0.4, position.z + side.z * 0.4) - g.get_height(position.x - side.x * 0.4, position.z - side.z * 0.4), 0.8)
	var turn_lean := clampf(angle_difference(_yaw, _desired_yaw), -0.6, 0.6) * stride * 0.25
	_body.rotation.x = lerpf(_body.rotation.x, pitch * 0.8, 1.0 - exp(-8.0 * delta))
	_body.rotation.z = lerpf(_body.rotation.z, roll * 0.6 + turn_lean, 1.0 - exp(-6.0 * delta))

	# Head: down to graze (with nibbles), up and still when alert, occasional glances.
	_look_cd -= delta
	if _look_cd <= 0.0:
		_look_cd = _rng.randf_range(1.5, 4.0)
		_look_target = _rng.randf_range(-0.5, 0.5) if moving < 0.5 and alert < 0.5 else 0.0
	_look_yaw = lerpf(_look_yaw, _look_target * (1.0 - graze), 1.0 - exp(-3.0 * delta))
	var head_pitch := graze * deg_to_rad(58.0) + graze * sin(_breath * 3.0) * 0.04
	if alert > 0.5:
		head_pitch = -0.2 if species.role != "defensive" else deg_to_rad(25.0)
	if state == State.FLEE:
		head_pitch = -0.1
	if _windup >= 0.0:
		head_pitch = deg_to_rad(40.0) * (1.0 - _windup / 0.45)
	_head.rotation.x = lerpf(_head.rotation.x, head_pitch, 1.0 - exp(-5.0 * delta))
	_head.rotation.y = _look_yaw


func _call(pitch := 1.0) -> void:
	if species.call_sound:
		Audio.play_3d(species.call_sound, global_position + Vector3.UP, -2.0, pitch * _rng.randf_range(0.95, 1.05))


func _bite() -> void:
	if not player:
		return
	var push := player.global_position - global_position
	push.y = 0.0
	var shove := push.normalized() * 6.0 + Vector3.UP * 2.5
	if player.has_method("hurt"):   # another player (we're the host): tell their game
		player.hurt(species.damage, shove)
		return
	if not player.has_method("respawn"):
		return
	player.stats.take_damage(species.damage)
	Music.combat_ping(1.0)
	player.velocity += shove


## Hit by the player.
func take_hit(damage: float, from: Vector3) -> void:
	if dead:
		return
	hp -= damage
	if hp <= 0.0:
		_die(from)
		_alarm_herd()
		return
	_call(1.15)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.06, 0.94, 1.06), 0.06)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
	if species.role == "defensive":
		_enter(State.ATTACK)
	else:
		_enter(State.FLEE)
		_alarm_herd()


func _die(from: Vector3) -> void:
	dead = true
	state = State.DEAD
	carcass_hp = 60.0 * species.yield_scale
	_call(0.7)
	var side := 1.0 if (from - global_position).dot(global_transform.basis.x) < 0.0 else -1.0
	var tw := create_tween()
	tw.tween_property(_body, "rotation:z", side * PI * 0.5, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_body, "rotation:x", 0.0, 0.3)
	tw.parallel().tween_property(_body, "position:y", species.body_w * 0.55, 0.5)
	tw.parallel().tween_property(_head, "rotation:x", deg_to_rad(15), 0.5)
	for i in _legs.size():
		tw.parallel().tween_property(_legs[i], "rotation:x", 0.15 * (1 if i % 2 == 0 else -1), 0.35)


## The carcass has been fully harvested.
func consume_carcass() -> void:
	if is_instance_valid(_collider):
		_collider.queue_free()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		removed.emit(self)
		queue_free())


# --- Puppets (multiplayer guests) ---------------------------------------------------------

## New position / heading / state from the host.
func net_update(pos: Vector3, yaw: float, st: int, is_dead: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if st != state and not dead:
		if st == State.FLEE or st == State.ATTACK:
			_call(1.05)
		if st == State.ATTACK and player and position.distance_to(player.global_position) < 30.0:
			Music.combat_ping(1.0)
		state = st as State
	if is_dead and not dead:
		_die(player.global_position if player else position + Vector3.FORWARD)


func _puppet_step(delta: float) -> void:
	if dead:
		return
	var before := position
	var k := 1.0 - exp(-10.0 * delta)
	position.x = lerpf(position.x, _net_pos.x, k)
	position.z = lerpf(position.z, _net_pos.z, k)
	position.y = lerpf(position.y, Game.world_gen.get_height(position.x, position.z), 1.0 - exp(-14.0 * delta))
	_yaw = lerp_angle(_yaw, _net_yaw, k)
	_desired_yaw = _net_yaw
	rotation = Vector3(0, _yaw, 0)
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	_speed = lerpf(_speed, moved / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_gait += moved / maxf(species.leg_len * 1.6, 0.2) * PI
	var graze := 1.0 if state == State.GRAZE and _speed < 0.3 else 0.0
	var alert := 1.0 if state in [State.ALERT, State.WARN] else 0.0
	_call_cd -= delta
	if _call_cd <= 0.0:
		_call_cd = _rng.randf_range(10.0, 30.0)
		if player and position.distance_to(player.global_position) < 60.0:
			_call()
	_animate(delta, graze, alert)


## A flinch when someone hit it (the host already applied the damage).
func puppet_hit() -> void:
	if dead or not _body:
		return
	_call(1.15)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.06, 0.94, 1.06), 0.06)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
