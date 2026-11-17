class_name Critter
extends Node3D
## Small ambient animal: hops about in the grass and scatters when you get close.

var species: FaunaLibrary.Species
var player: Node3D

var _body: Node3D
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_t := 1.0
var _hop_len := 0.3
var _wait := 0.0
var _scared := 0.0
var _rng := RandomNumberGenerator.new()


func setup(sp: FaunaLibrary.Species, pos: Vector3, p: Node3D) -> void:
	species = sp
	player = p
	position = pos
	_rng.randomize()
	_body = Node3D.new()
	_body.position.y = sp.leg_len + sp.body_h * 0.2
	add_child(_body)
	for m in [sp.body_mesh]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(mi)
	var head := MeshInstance3D.new()
	head.mesh = sp.head_mesh
	head.position = sp.head_pivot
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(head)
	for off in sp.leg_offsets:
		var leg := MeshInstance3D.new()
		leg.mesh = sp.leg_mesh
		leg.position = off
		leg.rotation.x = 0.5 if off.z > 0.0 else -0.3   # crouched, rabbit-like
		_body.add_child(leg)
	rotation.y = _rng.randf() * TAU
	_wait = _rng.randf_range(0.5, 3.0)


func _physics_process(delta: float) -> void:
	_scared = maxf(_scared - delta, 0.0)
	if player:
		var d := player.global_position - position
		d.y = 0.0
		if d.length() < species.flee_radius and _scared <= 0.0:
			_scared = 2.5
			_wait = 0.0
			_hop_t = 1.0
			Audio.play_3d(species.call_sound, global_position, -8.0)
	if _hop_t < 1.0:
		_hop_t = minf(_hop_t + delta / _hop_len, 1.0)
		var p := _hop_from.lerp(_hop_to, _hop_t)
		var arc := sin(_hop_t * PI) * (0.35 if _scared > 0.0 else 0.2)
		position = p + Vector3.UP * arc
		_body.rotation.x = lerpf(-0.35, 0.35, _hop_t)
		return
	_body.rotation.x = 0.0
	_wait -= delta
	if _wait > 0.0:
		return
	# Next hop: away from the player when scared, otherwise a random nibble-and-hop.
	var dir := Vector3(cos(_rng.randf() * TAU), 0, sin(_rng.randf() * TAU))
	if _scared > 0.0 and player:
		dir = (position - player.global_position)
		dir.y = 0.0
		dir = (dir.normalized() + Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4))).normalized()
	var length := _rng.randf_range(1.2, 2.0) if _scared > 0.0 else _rng.randf_range(0.4, 0.9)
	var to := position + dir * length
	var h: float = Game.world_gen.get_height(to.x, to.z)
	if h < 1.5:
		_wait = 0.3
		return
	_hop_from = position
	_hop_to = Vector3(to.x, h, to.z)
	_hop_t = 0.0
	_hop_len = 0.22 if _scared > 0.0 else 0.3
	rotation.y = atan2(-dir.x, -dir.z)
	_wait = _rng.randf_range(0.0, 0.15) if _scared > 0.0 else _rng.randf_range(0.6, 3.5)
