class_name CaveBats
extends Node3D
## Bats roosting in the high places of cave chambers. Come close and a colony bursts off the ceiling, flutters about
## the chamber squeaking and is gone down the tunnels. Scenery only (each player's game has its own).

const WAKE := 9.0          ## metres from a roost that sets them off
const REST := 90.0         ## seconds before a roost has bats in it again
const FLIGHT := 4.0        ## seconds they're in the air

var _roosts: Array = []    ## [ceiling pos, ready at (time)]
var _flocks: Array = []    ## [{bats: [{node, vel, wing_l, wing_r, phase}], age}]
var _time := 0.0
var _check := 0.0
static var _body_mesh: ArrayMesh
static var _wing_mesh: ArrayMesh


func setup(roosts: Array) -> void:
	for r: Vector3 in roosts:
		_roosts.append([r, 0.0])
	if not _body_mesh:
		var mat := ArtStyle.painted({"brush_strength": 0.1, "rim_amount": 0.3})
		var k := MeshKit.new(3)
		k.add_primitive(MeshKit.sphere(0.05, 7, 5), Transform3D(Basis().scaled(Vector3(0.8, 0.75, 1.3)), Vector3.ZERO), Color(0.16, 0.13, 0.13), 0.0, 0.02)
		k.add_primitive(MeshKit.sphere(0.03, 6, 4), Transform3D(Basis(), Vector3(0, 0.01, -0.07)), Color(0.18, 0.14, 0.13), 0.0, 0.0)
		_body_mesh = k.commit(mat)
		var w := MeshKit.new(4)
		# A wing: a scalloped membrane from the body out to the tip.
		var outline := PackedVector2Array([Vector2(0, 0.04), Vector2(0.16, 0.05), Vector2(0.24, 0.0), Vector2(0.18, -0.02),
			Vector2(0.12, -0.05), Vector2(0.07, -0.03), Vector2(0.0, -0.05)])
		w.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO), 0.006, 0.0, Color(0.2, 0.15, 0.14), Color(0.2, 0.15, 0.14))
		_wing_mesh = w.commit(mat)


func _process(delta: float) -> void:
	_time += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		_wake_roosts()
	for fi in range(_flocks.size() - 1, -1, -1):
		var f: Dictionary = _flocks[fi]
		f.age += delta
		if f.age > FLIGHT:
			for b: Dictionary in f.bats:
				(b.node as Node3D).queue_free()
			_flocks.remove_at(fi)
			continue
		var plan: Dictionary = Game.world_gen.caves
		for b: Dictionary in f.bats:
			var n := b.node as Node3D
			var v: Vector3 = b.vel
			# Jinking about, keeping off the walls.
			v += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * 14.0 * delta
			v = v.limit_length(6.5)
			var next := n.position + v * delta
			if Caves.void_distance(plan, next) > -0.35:
				v = -v * 0.6 + Vector3(0, -0.5, 0)
				next = n.position + v * delta
			b.vel = v
			n.position = next
			if v.length() > 0.1:
				n.basis = Basis.looking_at(v, Vector3.UP)
			var flap := sin(_time * 38.0 + float(b.phase)) * 1.0
			(b.wl as Node3D).rotation.z = flap
			(b.wr as Node3D).rotation.z = -flap
			# Fading out of sight at the end.
			if f.age > FLIGHT - 0.5:
				n.scale = Vector3.ONE * clampf((FLIGHT - f.age) * 2.0, 0.01, 1.0)


func _wake_roosts() -> void:
	if not Game.in_cave or Game.world_gen == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for r: Array in _roosts:
		var p: Vector3 = r[0]
		if _time < float(r[1]) or eye.distance_to(p) > WAKE:
			continue
		r[1] = _time + REST
		_burst(p, eye)


func _burst(at: Vector3, away_from: Vector3) -> void:
	var bats: Array = []
	var away := at - away_from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	for i in randi_range(7, 12):
		var n := Node3D.new()
		n.position = at + Vector3(randf_range(-0.6, 0.6), -0.2, randf_range(-0.6, 0.6))
		add_child(n)
		var body := MeshInstance3D.new()
		body.mesh = _body_mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(body)
		var wl := MeshInstance3D.new()
		wl.mesh = _wing_mesh
		wl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(wl)
		var wr := MeshInstance3D.new()
		wr.mesh = _wing_mesh
		wr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wr.scale = Vector3(-1, 1, 1)
		n.add_child(wr)
		CaveShade.apply(n, CaveShade.at(at))
		var v := (away + Vector3(randf_range(-0.8, 0.8), randf_range(-0.6, 0.1), randf_range(-0.8, 0.8))).normalized() * randf_range(3.0, 5.5)
		bats.append({"node": n, "vel": v, "wl": wl, "wr": wr, "phase": randf() * TAU})
	_flocks.append({"bats": bats, "age": 0.0})
	for k in 4:
		get_tree().create_timer(k * 0.18, false).timeout.connect(func() -> void:
			Audio.play_3d("squeak", at, -6.0, randf_range(0.9, 1.2)))
