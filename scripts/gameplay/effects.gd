class_name Effects
extends RefCounted
## One-shot visual effects: chips flying off things you hit, trees falling over, rocks crumbling.

static var _chip_material: StandardMaterial3D
static var _chip_mesh: BoxMesh


## A burst of small colored chips (wood, stone shards, leaves, blood...).
static func chips(parent: Node, pos: Vector3, color: Color, count := 10, size := 0.08, spread := 3.5) -> void:
	if not _chip_mesh:
		_chip_material = StandardMaterial3D.new()
		_chip_material.vertex_color_use_as_albedo = true
		_chip_material.roughness = 1.0
		_chip_mesh = BoxMesh.new()
		_chip_mesh.size = Vector3.ONE
		_chip_mesh.material = _chip_material
	var p := CPUParticles3D.new()
	p.mesh = _chip_mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = count
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = spread * 0.5
	p.initial_velocity_max = spread
	p.gravity = Vector3(0, -12, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(0.7, 1))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	p.color = color
	var grad := Gradient.new()
	grad.set_color(0, color.lightened(0.15))
	grad.set_color(1, color.darkened(0.2))
	p.color_initial_ramp = grad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.2, false).timeout.connect(p.queue_free)


## Topple a chopped tree away from the player, then fade it out.
static func fall_tree(parent: Node, mesh: Mesh, xf: Transform3D, away: Vector3, color: Color) -> void:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.global_transform = Transform3D(Basis(), xf.origin)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(xf.basis, Vector3.ZERO)
	pivot.add_child(mi)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var axis := Vector3.UP.cross(away).normalized()
	# It comes to rest along the ground it falls onto: further than flat down a slope, short of flat up one
	# (the crown props it a little off the ground, hence a few degrees short of the slope itself).
	var height := mesh.get_aabb().size.y * xf.basis.get_scale().y
	var reach := maxf(height * 0.6, 1.0)
	var land := xf.origin + away * reach
	var rise := Game.world_gen.get_height(land.x, land.z) - Game.world_gen.get_height(xf.origin.x, xf.origin.z)
	var rest := clampf(deg_to_rad(84.0) - atan2(rise, reach), deg_to_rad(40.0), deg_to_rad(130.0))
	var tw := pivot.create_tween()
	tw.tween_method(func(a: float) -> void: pivot.basis = Basis(axis, a), 0.0, rest, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		var hit := Vector3(land.x, Game.world_gen.get_height(land.x, land.z) + 0.3, land.z)
		chips(parent, hit, color, 18, 0.14, 4.0)
		Audio.play_3d(Audio.sfx.tree_fall, hit, 2.0))
	tw.tween_interval(1.6)
	tw.tween_property(mi, "scale", Vector3(1, 0.001, 1), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(pivot.queue_free)


## Rocks and bushes: shrink away with a burst.
static func crumble(parent: Node, mesh: Mesh, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	mi.global_transform = xf
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", mi.scale * 0.05, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
