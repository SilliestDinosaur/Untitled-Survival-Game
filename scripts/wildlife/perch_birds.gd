class_name PerchBirds
extends Node3D
## A few birds that land: on tree crowns, fallen logs and rocks. They sit and look about, hop and peck, flit from
## perch to perch, and all burst up and away to somewhere further off when you come close. Scenery (each game has
## its own, like the circling flocks).

var species: FaunaLibrary.Species
var player: Node3D
var _birds: Array[Dictionary] = []   ## {node, wings, at, from, to, t, flying, wait, flap}
var _perches: Array[Vector3] = []
var _rescan := 0.0
var _chirp := 2.0
var _rng := RandomNumberGenerator.new()
const SCARE := 7.0
const TREE_TOPS := {"kapok": 20.0, "jungle_tree": 8.5, "oak": 5.0, "autumn_oak": 5.0, "birch": 6.0, "willow": 4.5, "acacia": 4.5, "palm": 6.5, "pine": 6.0, "fir": 7.0}


func setup(sp: FaunaLibrary.Species, centre: Vector3, p: Node3D) -> bool:
	species = sp
	player = p
	_rng.randomize()
	position = centre
	_scan()
	if _perches.size() < 3:
		return false
	for i in _rng.randi_range(3, 7):
		var b := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = sp.body_mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(body)
		var wings: Array[Node3D] = []
		for side in [-1.0, 1.0]:
			var w := Node3D.new()
			var wm := MeshInstance3D.new()
			wm.mesh = sp.wing_mesh
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if side < 0.0:
				wm.rotation.y = PI
			w.add_child(wm)
			b.add_child(w)
			wings.append(w)
		b.top_level = true
		add_child(b)
		var at := _perch_spot(_perches[_rng.randi() % _perches.size()])
		b.global_position = at
		_birds.append({"node": b, "wings": wings, "at": at, "from": at, "to": at, "t": 1.0, "flying": false,
			"wait": _rng.randf_range(1.0, 6.0), "flap": _rng.randf() * TAU, "yaw": _rng.randf() * TAU})
	return true


## Places to land near here: the crowns of trees, fallen logs, rocks.
func _scan() -> void:
	_perches.clear()
	var world: Node = get_node_or_null("/root/Main/World")
	if not world:
		return
	var here: Vector2i = world.world_to_chunk(position)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk = world.get_chunk(here + Vector2i(dx, dz))
			if not chunk:
				continue
			for pr: Array in perches_in(chunk):
				var top: Vector3 = pr[0]
				if not (pr[1] as Dictionary).get("removed", false) and top.distance_to(position) < 45.0:   # not a felled tree
					_perches.append(top)
	# Anyone sitting where there's no perch any more (the tree was felled) flies off.
	if _perches.is_empty():
		return
	for b in _birds:
		if b.flying:
			continue
		var held := false
		for p: Vector3 in _perches:
			if p.distance_to(b.at) < 1.6:
				held = true
				break
		if not held:
			_take_off(b, _perches[_rng.randi() % _perches.size()], 0.0)


## Every place to land in a chunk ([spot, its resource]): the crowns of its trees (out on the lower edge, where a bird on a branch can be
## seen from below), its fallen logs and rocks. Worked out once per chunk (a chunk that's rebuilt is a new one).
static var _chunk_perches := {}
static func perches_in(chunk: Node) -> Array:
	var id := chunk.get_instance_id()
	if _chunk_perches.has(id):
		return _chunk_perches[id]
	if _chunk_perches.size() > 300:
		_chunk_perches.clear()
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	for r: Dictionary in chunk.resources:
		var xf: Transform3D = r.transform
		if TREE_TOPS.has(r.kind) and Game.flora.has_mesh(r.key):
			var bb := _crown(String(r.key))
			var a := rng.randf() * TAU
			out.append([xf * Vector3(cos(a) * bb.x * 0.4, bb.y * (0.42 if r.kind == "jungle_tree" else 0.7), sin(a) * bb.x * 0.4), r])
		elif r.kind == "log":
			out.append([xf.origin + xf.basis.y.normalized() * 0.5 * xf.basis.y.length(), r])
		elif r.kind in ["rock", "boulder"]:
			out.append([xf.origin + Vector3(0, 0.85 * xf.basis.y.length(), 0), r])
	_chunk_perches[id] = out
	return out


## A tree model's crown: (width, height), from its mesh (looked up once per model).
static var _crowns := {}
static func _crown(key: String) -> Vector2:
	if not _crowns.has(key):
		var bb: AABB = Game.flora.mesh(key).get_aabb()
		_crowns[key] = Vector2(maxf(bb.size.x, bb.size.z), bb.end.y)
	return _crowns[key]


## A spot on a perch, spread a little so birds sharing it don't sit inside each other.
func _perch_spot(p: Vector3) -> Vector3:
	return p + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)) + Vector3(0, species.size * 0.35, 0)


func _physics_process(delta: float) -> void:
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = 4.0
		_scan()
	if _perches.is_empty():
		return
	var scared := false
	if player:
		for b in _birds:
			if not b.flying and (b.node as Node3D).global_position.distance_to(player.global_position) < SCARE:
				scared = true
	if scared:   # the whole group bursts up and away
		Audio.play_3d(species.call_sound, (_birds[0].node as Node3D).global_position, -2.0, 1.1)
		var far := _far_perch()
		for b in _birds:
			_take_off(b, far, 25.0)
	for b in _birds:
		var node: Node3D = b.node
		if b.flying:
			b.t = minf(float(b.t) + delta / maxf(float(b.dur), 0.3), 1.0)
			var t: float = b.t
			var from: Vector3 = b.from
			var to: Vector3 = b.to
			var p := from.lerp(to, t) + Vector3.UP * sin(t * PI) * (2.0 + from.distance_to(to) * 0.15)
			var vel := to - from
			b.yaw = atan2(-vel.x, -vel.z)
			node.global_position = p
			node.rotation = Vector3(-0.15 if t < 0.8 else 0.3, b.yaw, 0)
			b.flap += delta * 22.0
			var wing := sin(b.flap) * 0.8 if t < 0.85 else 0.9   # wings up as it lands
			(b.wings[0] as Node3D).rotation.z = wing
			(b.wings[1] as Node3D).rotation.z = -wing
			if t >= 1.0:
				b.flying = false
				b.at = to
				b.wait = _rng.randf_range(2.0, 8.0)
		else:
			# Sitting: wings folded, a hop and a peck now and then, a glance about.
			(b.wings[0] as Node3D).rotation.z = lerpf((b.wings[0] as Node3D).rotation.z, -0.15, 0.2)
			(b.wings[1] as Node3D).rotation.z = lerpf((b.wings[1] as Node3D).rotation.z, 0.15, 0.2)
			b.wait -= delta
			var at: Vector3 = b.at
			var peck := maxf(sin(Time.get_ticks_msec() * 0.004 + float(b.flap) * 3.0), 0.0)
			node.global_position = at
			node.rotation = Vector3(peck * 0.35, b.yaw, 0)
			if b.wait <= 0.0:
				if _rng.randf() < 0.4:
					_take_off(b, _perches[_rng.randi() % _perches.size()], 0.0)   # off to another perch
				else:
					b.yaw += _rng.randf_range(-1.2, 1.2)   # turn about
					b.wait = _rng.randf_range(1.0, 4.0)
	_chirp -= delta
	if _chirp <= 0.0 and not _birds.is_empty():
		_chirp = _rng.randf_range(2.5, 8.0)
		Audio.play_3d(species.call_sound, (_birds[_rng.randi() % _birds.size()].node as Node3D).global_position, -6.0, _rng.randf_range(0.9, 1.15))


func _take_off(b: Dictionary, perch: Vector3, min_dist: float) -> void:
	if b.flying and min_dist <= 0.0:
		return
	var to := _perch_spot(perch)
	if min_dist > 0.0 and to.distance_to((b.node as Node3D).global_position) < min_dist:
		to += Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 2.0
	b.from = (b.node as Node3D).global_position
	b.to = to
	b.t = 0.0
	b.dur = 0.6 + b.from.distance_to(to) / 9.0
	b.flying = true


## The perch furthest from the player (where a startled group flies off to).
func _far_perch() -> Vector3:
	var best := _perches[0]
	var best_d := -1.0
	for p in _perches:
		var d := p.distance_to(player.global_position) if player else 0.0
		if d > best_d:
			best_d = d
			best = p
	return best
