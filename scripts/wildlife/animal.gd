class_name Animal
extends Node3D
## A four-legged creature: grazers wander and flee, territorial beasts fight back when hit.
## Moves along the terrain height (no physics) to stay cheap; legs are animated in code.

signal removed(animal: Animal)

enum State { IDLE, GRAZE, WANDER, FLEE, ATTACK, DEAD }

var species: FaunaLibrary.Species
var hp := 10.0
var dead := false
var carcass_hp := 0.0
var state := State.IDLE
var player: Node3D

var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _target := Vector3.ZERO
var _timer := 0.0
var _speed := 0.0
var _yaw := 0.0
var _gait := 0.0
var _attack_cd := 0.0
var _call_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _collider: StaticBody3D


func setup(sp: FaunaLibrary.Species, pos: Vector3, p: Node3D) -> void:
	species = sp
	player = p
	hp = sp.hp
	_rng.randomize()
	_yaw = _rng.randf() * TAU
	position = pos

	_body = Node3D.new()
	_body.position.y = sp.leg_len + sp.body_h * 0.2
	add_child(_body)
	_body.add_child(_mesh(sp.body_mesh))
	_head = Node3D.new()
	_head.position = sp.head_pivot
	_head.add_child(_mesh(sp.head_mesh))
	_body.add_child(_head)
	for off in sp.leg_offsets:
		var leg := Node3D.new()
		leg.position = off
		leg.add_child(_mesh(sp.leg_mesh))
		_body.add_child(leg)
		_legs.append(leg)

	# Hit box on the "interact" layer: the crosshair and tools can hit it, the player walks through.
	_collider = StaticBody3D.new()
	_collider.collision_layer = TerrainChunk.LAYER_INTERACT
	_collider.collision_mask = 0
	_collider.set_meta("animal", self)
	var shape := BoxShape3D.new()
	# Covers the body plus the upper legs (the box hangs below the body, which sits atop the legs).
	shape.size = Vector3(maxf(sp.body_w * 1.2, 0.4), sp.body_h * 1.2 + sp.leg_len * 0.6, maxf(sp.body_len * 1.3, 0.5))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, sp.body_h * 0.6 - shape.size.y * 0.5, -sp.body_len * 0.1)
	_collider.add_child(cs)
	_body.add_child(_collider)
	_enter(State.GRAZE)


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


func _enter(s: State) -> void:
	state = s
	match s:
		State.IDLE:
			_timer = _rng.randf_range(2.0, 5.0)
		State.GRAZE:
			_timer = _rng.randf_range(4.0, 10.0)
		State.WANDER:
			_timer = 20.0
			_pick_wander_target()
		State.FLEE:
			_timer = _rng.randf_range(5.0, 8.0)
		State.ATTACK:
			_timer = 15.0


func _pick_wander_target() -> void:
	for i in 8:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(6.0, 18.0)
		var t := position + Vector3(cos(a) * d, 0, sin(a) * d)
		var h: float = Game.world_gen.get_height(t.x, t.z)
		if h > 2.0 and h < 55.0:
			_target = t
			return
	_target = position


func _physics_process(delta: float) -> void:
	if dead:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_call_cd -= delta
	_timer -= delta
	var to_player := player.global_position - position if player else Vector3(1e6, 0, 0)
	to_player.y = 0.0
	var dist := to_player.length()

	# Senses: grazers bolt when you get close (sprinting is louder).
	if species.flee_radius > 0.0 and state != State.FLEE:
		var radius := species.flee_radius * (1.6 if player and player.get("is_sprinting") else 1.0)
		if dist < radius:
			_enter(State.FLEE)
			_call()

	var move_dir := Vector3.ZERO
	var want_speed := 0.0
	var graze := 0.0
	match state:
		State.IDLE, State.GRAZE:
			graze = 1.0 if state == State.GRAZE else 0.0
			if _timer <= 0.0:
				_enter(State.WANDER if _rng.randf() < 0.7 else (State.GRAZE if state == State.IDLE else State.IDLE))
		State.WANDER:
			var d := _target - position
			d.y = 0.0
			if d.length() < 1.0 or _timer <= 0.0:
				_enter(State.GRAZE if _rng.randf() < 0.6 else State.IDLE)
			else:
				move_dir = d.normalized()
				want_speed = species.walk_speed
		State.FLEE:
			move_dir = -to_player.normalized() if dist > 0.01 else Vector3.FORWARD
			want_speed = species.run_speed
			if _timer <= 0.0 and dist > species.flee_radius * 1.5:
				_enter(State.IDLE)
		State.ATTACK:
			if _timer <= 0.0 or dist > 35.0:
				_enter(State.IDLE)
			elif dist > 1.4 + species.size * 0.6:
				move_dir = to_player.normalized()
				want_speed = species.run_speed
			else:
				move_dir = to_player.normalized() * 0.01
				if _attack_cd <= 0.0:
					_attack_cd = 1.3
					_bite()

	_speed = lerpf(_speed, want_speed, 1.0 - exp(-4.0 * delta))
	if move_dir.length_squared() > 0.0:
		_yaw = lerp_angle(_yaw, atan2(-move_dir.x, -move_dir.z), 1.0 - exp(-6.0 * delta))
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var next := position + forward * _speed * delta
	var h: float = Game.world_gen.get_height(next.x, next.z)
	if h < 1.2 or h > 60.0:
		# Don't walk into the sea or up cliffs: turn around.
		_yaw += PI * 0.5
		_speed *= 0.3
		if state == State.WANDER:
			_pick_wander_target()
	else:
		position = Vector3(next.x, h, next.z)

	# Lean with the slope.
	var front: float = Game.world_gen.get_height(position.x + forward.x * species.body_len * 0.5, position.z + forward.z * species.body_len * 0.5)
	var back: float = Game.world_gen.get_height(position.x - forward.x * species.body_len * 0.5, position.z - forward.z * species.body_len * 0.5)
	var pitch := atan2(front - back, species.body_len)
	rotation = Vector3(0, _yaw, 0)
	_body.rotation.x = lerpf(_body.rotation.x, pitch, 1.0 - exp(-8.0 * delta))
	_animate(delta, graze)

	if _call_cd <= 0.0:
		_call_cd = _rng.randf_range(8.0, 25.0)
		if dist < 60.0:
			_call()


func _animate(delta: float, graze: float) -> void:
	var stride := clampf(_speed / maxf(species.run_speed, 0.1), 0.0, 1.0)
	_gait += delta * (2.0 + _speed * 2.2 / maxf(species.size, 0.3))
	var swing := (0.25 + stride * 0.45) * minf(_speed / 0.3, 1.0)
	# Diagonal legs move together (trot).
	var phases := [0.0, PI, PI, 0.0] if _legs.size() == 4 else [0.0, PI]
	for i in _legs.size():
		_legs[i].rotation.x = sin(_gait + phases[i]) * swing
	_body.position.y = species.leg_len + species.body_h * 0.2 + absf(sin(_gait)) * 0.04 * species.size * stride
	# Head: down to graze (with a little nibble), up when moving or alert.
	var target_head := graze * deg_to_rad(55.0) + graze * sin(_gait * 2.0) * 0.05
	if state == State.FLEE or state == State.ATTACK:
		target_head = -0.15
	_head.rotation.x = lerpf(_head.rotation.x, target_head, 1.0 - exp(-4.0 * delta))


func _call(pitch := 1.0) -> void:
	if species.call_sound:
		Audio.play_3d(species.call_sound, global_position + Vector3.UP, -2.0, pitch)


func _bite() -> void:
	if not player or not player.has_method("respawn"):
		return
	player.stats.take_damage(species.damage)
	_call(0.8)
	# Shove the player back a bit.
	var push := (player.global_position - global_position)
	push.y = 0.0
	player.velocity += push.normalized() * 5.0 + Vector3.UP * 2.0


## Hit by the player.
func take_hit(damage: float, from: Vector3) -> void:
	if dead:
		return
	hp -= damage
	if hp <= 0.0:
		_die(from)
		return
	_call(1.15)
	# Brief flinch.
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.08, 0.92, 1.08), 0.06)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
	if species.role == "defensive":
		_enter(State.ATTACK)
	else:
		_enter(State.FLEE)


func _die(from: Vector3) -> void:
	dead = true
	state = State.DEAD
	carcass_hp = 60.0 * species.yield_scale
	_call(0.7)
	var side := 1.0 if (from - global_position).dot(global_transform.basis.x) < 0.0 else -1.0
	var tw := create_tween()
	tw.tween_property(_body, "rotation:z", side * PI * 0.5, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_body, "position:y", species.body_w * 0.5, 0.45)
	tw.parallel().tween_property(_head, "rotation:x", deg_to_rad(20), 0.45)
	for leg in _legs:
		tw.parallel().tween_property(leg, "rotation:x", 0.1, 0.3)


## The carcass has been fully harvested.
func consume_carcass() -> void:
	_collider.queue_free()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		removed.emit(self)
		queue_free())
