class_name BirdFlock
extends Node3D
## A flock of birds circling and drifting over the land, flapping and chirping.

var species: FaunaLibrary.Species
var _birds: Array[Dictionary] = []
var _heading := 0.0
var _altitude := 30.0
var _t := 0.0
var _chirp := 3.0
var _rng := RandomNumberGenerator.new()
var _soar := false


func setup(sp: FaunaLibrary.Species, pos: Vector3) -> void:
	species = sp
	_rng.randomize()
	position = pos
	_heading = _rng.randf() * TAU
	_altitude = _rng.randf_range(22.0, 40.0)
	_soar = sp.bird_kind == "soar"
	if _soar:   # vultures: a few, high, in wide slow circles
		_altitude = _rng.randf_range(45.0, 70.0)
	for i in (_rng.randi_range(2, 4) if _soar else _rng.randi_range(5, 10)):
		var b := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = sp.body_mesh
		b.add_child(body)
		var wings: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var w := Node3D.new()
			var wm := MeshInstance3D.new()
			wm.mesh = sp.wing_mesh
			if side < 0.0:
				wm.rotation.y = PI   # mirror by rotating (negative scale would flip the faces)
			w.add_child(wm)
			b.add_child(w)
			wings.append(w)
		add_child(b)
		_birds.append({
			"node": b, "wings": wings,
			"radius": _rng.randf_range(14.0, 30.0) if _soar else _rng.randf_range(3.0, 9.0), "phase": _rng.randf() * TAU,
			"speed": _rng.randf_range(0.12, 0.2) if _soar else _rng.randf_range(0.6, 0.9), "height": _rng.randf_range(-2.5, 2.5),
			"flap": _rng.randf() * TAU,
		})


func _physics_process(delta: float) -> void:
	_t += delta
	# The whole flock drifts slowly, keeping a height above the ground.
	_heading += sin(_t * 0.1) * 0.15 * delta
	position += Vector3(cos(_heading), 0, sin(_heading)) * 4.0 * delta
	var ground: float = maxf(Game.world_gen.get_height(position.x, position.z), 0.0)
	position.y = lerpf(position.y, ground + _altitude, 1.0 - exp(-0.5 * delta))
	for b in _birds:
		var a: float = b.phase + _t * b.speed
		var r: float = b.radius
		var p := Vector3(cos(a) * r, b.height + sin(_t * 0.7 + b.phase) * 0.8, sin(a) * r)
		var node: Node3D = b.node
		var vel := Vector3(-sin(a), 0, cos(a))
		node.position = p
		node.rotation = Vector3(0, atan2(-vel.x, -vel.z), -0.2 if _soar else -0.35)
		# Flap in bursts, then glide.
		var flapping := sin(_t * 0.8 + b.phase) > (0.97 if _soar else -0.2)   # soarers barely flap
		b.flap += delta * (16.0 if flapping else 0.0)
		var wing_angle := sin(b.flap) * 0.7 if flapping else 0.1
		node.get_child(1).rotation.z = wing_angle
		node.get_child(2).rotation.z = -wing_angle
	_chirp -= delta
	if _chirp <= 0.0:
		_chirp = _rng.randf_range(3.0, 9.0)
		Audio.play_3d(species.call_sound, global_position, -4.0, _rng.randf_range(0.9, 1.15))
