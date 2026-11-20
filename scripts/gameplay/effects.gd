class_name Effects
extends RefCounted
## Particles and one-shot effects: chips, splinters and shards off things you hit, dust, leaves, sparks, steam,
## splashes, blood, little twinkles; fires' embers and smoke; trees falling over, rocks crumbling.
##
## Everything is a CPUParticles3D sharing a handful of meshes and materials made once. One-shot bursts free
## themselves when done, and there's a cap on how many may be alive at once (the least important are skipped
## when it's reached), so a busy moment can't pile up.

const MAX_BURSTS := 48
## The colour of the dust and bits knocked off each building material.
const MAT_DUST := {"wood": Color(0.72, 0.56, 0.38), "stone": Color(0.62, 0.62, 0.64), "brick": Color(0.74, 0.46, 0.36)}

static var _active := 0
static var _slow := 0.0   ## while > 0, new bursts start in slow motion and speed up over this many seconds
static var _soft_tex: Texture2D        ## a soft round blob (puffs, smoke, glows)
static var _leaf_tex: Texture2D        ## a leaf shape
static var _lit_mat: StandardMaterial3D       ## lit solid bits: chips, shards, splinters
static var _puff_mat: StandardMaterial3D      ## soft lit puffs: dust, smoke, steam
static var _glow_mat: StandardMaterial3D      ## additive glows: embers, sparks, fireflies, twinkles
static var _leaf_mat: StandardMaterial3D      ## two-sided leaves
static var _box: BoxMesh
static var _shard: BoxMesh
static var _splinter: BoxMesh
static var _quad: QuadMesh
static var _glow_quad: QuadMesh
static var _streak: QuadMesh
static var _leaf: QuadMesh
static var _drop: SphereMesh


static func _setup() -> void:
	if _box:
		return
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	_soft_tex = soft
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var u := (x - 15.5) / 15.5
			var v := (y - 15.5) / 15.5
			var w := 0.55 * (1.0 - v * v)   # a leaf: wide in the middle, pointed at both ends
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if absf(u) < w else 0.0))
	_leaf_tex = ImageTexture.create_from_image(img)

	_lit_mat = StandardMaterial3D.new()
	_lit_mat.vertex_color_use_as_albedo = true
	_lit_mat.roughness = 1.0
	_puff_mat = StandardMaterial3D.new()
	_puff_mat.vertex_color_use_as_albedo = true
	_puff_mat.albedo_texture = _soft_tex
	_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puff_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_puff_mat.billboard_keep_scale = true   # (or every particle is drawn a metre across, whatever its scale)
	# Lit (per vertex: cheap), so smoke and dust are dark at night and catch a fire's light.
	_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_puff_mat.roughness = 1.0
	_puff_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_puff_mat.proximity_fade_enabled = true
	_puff_mat.proximity_fade_distance = 0.4
	_glow_mat = _puff_mat.duplicate()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.proximity_fade_enabled = false
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.albedo_texture = _leaf_tex
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.roughness = 1.0

	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_box.material = _lit_mat
	_shard = BoxMesh.new()
	_shard.size = Vector3(1.0, 0.35, 0.65)
	_shard.material = _lit_mat
	_splinter = BoxMesh.new()
	_splinter.size = Vector3(0.22, 0.22, 1.0)
	_splinter.material = _lit_mat
	_quad = QuadMesh.new()
	_quad.material = _puff_mat
	_glow_quad = QuadMesh.new()
	_glow_quad.material = _glow_mat
	_streak = QuadMesh.new()
	_streak.size = Vector2(0.35, 1.0)
	_streak.material = _glow_mat
	_leaf = QuadMesh.new()
	_leaf.size = Vector2(0.6, 1.0)
	_leaf.material = _leaf_mat
	_drop = SphereMesh.new()
	_drop.radius = 0.5
	_drop.height = 1.0
	_drop.radial_segments = 6
	_drop.rings = 3
	_drop.material = _lit_mat


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	return c


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


## A one-shot burst: made, placed, started and freed when done. Skipped (null) when too many are alive, unless
## `must` (the thing you just did should always show something).
static func _burst(parent: Node, pos: Vector3, mesh: Mesh, count: int, lifetime: float, must := false) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree() or count <= 0:
		return null
	if _active >= MAX_BURSTS and not must:
		return null
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = count
	p.lifetime = lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	_active += 1
	var extra := 0.0
	if _slow > 0.0:
		p.speed_scale = 0.2
		p.create_tween().tween_property(p, "speed_scale", 1.0, _slow).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		extra = _slow * 0.8
	parent.get_tree().create_timer(lifetime + 0.2 + extra, false).timeout.connect(func() -> void:
		_active -= 1
		if is_instance_valid(p):
			p.queue_free())
	return p


## Bursts made inside `body` start in slow motion and catch up over `seconds` (a perfect strike, a finished piece).
static func slow_motion(seconds: float, body: Callable) -> void:
	_slow = seconds
	body.call()
	_slow = 0.0


## A quick flash of light (a strike on hot metal, a finished piece), fading out by itself.
static func flash(parent: Node, pos: Vector3, color := Color(1.0, 0.7, 0.35), energy := 2.0, radius := 3.0, time := 0.25) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


## A ring of glowing motes bursting outwards (a finishing flourish).
static func ring(parent: Node, pos: Vector3, color := Color(1.0, 0.9, 0.55), count := 18, size := 1.0) -> void:
	_setup()
	var p := _burst(parent, pos, _glow_quad, count, 0.8, true)
	if p:
		p.explosiveness = 1.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 0.05 * size
		p.emission_ring_inner_radius = 0.0
		p.emission_ring_height = 0.0
		p.direction = Vector3(1, 0.15, 0)
		p.spread = 180.0
		p.flatness = 0.85
		p.initial_velocity_min = 0.8 * size
		p.initial_velocity_max = 1.2 * size
		p.damping_min = 1.5 * size
		p.damping_max = 2.0 * size
		p.gravity = Vector3(0, 0.3 * size, 0)
		p.scale_amount_min = 0.035 * size
		p.scale_amount_max = 0.06 * size
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
		p.color_ramp = _ramp(Color(color.r * 1.5, color.g * 1.5, color.b * 1.5), Color(color, 0.0))
		_start(p)


## Bubbles popping up at a liquid's surface (a pot on the boil): a continuous emitter, `radius` across.
static func bubbles(radius := 0.1, color := Color(0.75, 0.55, 0.35)) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = _drop
	p.amount = 14
	p.lifetime = 0.6
	p.randomness = 0.6
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.0
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.08
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.008
	p.scale_amount_max = 0.018
	p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.85, 1.0), Vector2(1, 1.4)])
	p.color = color.lightened(0.25)
	return p


## Fine dust hanging and drifting in the air round a workplace (sawdust at the bench).
static func motes(box: Vector3, color := Color(0.85, 0.72, 0.5), amount := 24) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = _glow_quad
	p.amount = amount
	p.lifetime = 5.0
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3(1, 0.3, 0.2)
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.07
	p.gravity = Vector3(0.0, -0.01, 0.0)
	p.scale_amount_min = 0.006
	p.scale_amount_max = 0.012
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.add_point(0.3, Color(color, 0.5))
	g.add_point(0.7, Color(color, 0.5))
	g.set_color(g.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = g
	return p


## A card of heat haze to hang over something hot; set its strength with set_shimmer.
static func shimmer(size := Vector2(0.3, 0.5)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, size.y * 0.5, 0)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/heat_shimmer.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


static func set_shimmer(mi: MeshInstance3D, strength: float) -> void:
	if mi == null:
		return
	mi.visible = strength > 0.02
	if mi.visible:
		(mi.material_override as ShaderMaterial).set_shader_parameter("strength", strength)


static func _start(p: CPUParticles3D) -> void:
	if p:
		p.emitting = true


## What colour a plant's leaves are, and its wood (for what flies off it).
static func leaf_color(kind: String) -> Color:
	var pal: WorldPalette = Game.palette
	match kind:
		"pine": return pal.pine_leaves
		"fir": return pal.fir_leaves
		"birch": return pal.birch_leaves
		"willow": return pal.willow_leaves
		"acacia": return pal.acacia_leaves
		"jungle_tree", "palm": return pal.jungle_leaves
		"autumn_oak": return pal.autumn_leaves[0] if not pal.autumn_leaves.is_empty() else pal.oak_leaves
		"oak": return pal.oak_leaves
		"cactus": return pal.cactus
		"giant_mushroom": return pal.mushroom_caps[0] if not pal.mushroom_caps.is_empty() else pal.bush_leaves
		"dead_tree", "log", "stump", "sapling": return pal.dead_wood
	return pal.bush_leaves


static func bark_color(kind: String) -> Color:
	var pal: WorldPalette = Game.palette
	match kind:
		"birch": return pal.birch_bark
		"dead_tree", "log", "stump": return pal.dead_wood
		"cactus": return pal.cactus
	return pal.bark


## True for kinds that have leaves to shake loose.
static func has_leaves(kind: String) -> bool:
	return not kind in ["dead_tree", "log", "stump", "cactus", "giant_mushroom"]


# --- Bursts ---------------------------------------------------------------------------------

## Small coloured chips flying off whatever you hit (and a little dust where they came from).
static func chips(parent: Node, pos: Vector3, color: Color, count := 10, size := 0.08, spread := 3.5) -> void:
	var p := _burst(parent, pos, _box, count, 0.9, true)
	if p:
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = spread * 0.5
		p.initial_velocity_max = spread
		p.gravity = Vector3(0, -12, 0)
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.scale_amount_min = size * 0.6
		p.scale_amount_max = size * 1.3
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.7, 1), Vector2(1, 0)])
		p.color_initial_ramp = _ramp(color.lightened(0.15), color.darkened(0.2))
		_start(p)


## Splinters of wood spinning off a chopped tree or a hammered plank, with bark flakes.
static func splinters(parent: Node, pos: Vector3, wood: Color, bark: Color, count := 8, size := 1.0) -> void:
	var p := _burst(parent, pos, _splinter, count, 1.0, true)
	if p:
		p.direction = Vector3.UP
		p.spread = 75.0
		p.initial_velocity_min = 2.0 * sqrt(size)
		p.initial_velocity_max = 4.2 * sqrt(size)
		p.gravity = Vector3(0, -11, 0)
		p.angular_velocity_min = -600
		p.angular_velocity_max = 600
		p.particle_flag_rotate_y = true
		p.scale_amount_min = 0.05 * size
		p.scale_amount_max = 0.12 * size
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.75, 1), Vector2(1, 0)])
		p.color_initial_ramp = _ramp(wood.lightened(0.2), wood)
		_start(p)
	chips(parent, pos, bark, maxi(count / 2, 2), 0.05 * size, 2.5 * sqrt(size))


## Shards of stone (or ore, or crystal) and a puff of grit.
static func shards(parent: Node, pos: Vector3, color: Color, count := 9) -> void:
	var p := _burst(parent, pos, _shard, count, 0.9, true)
	if p:
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -13, 0)
		p.angular_velocity_min = -500
		p.angular_velocity_max = 500
		p.scale_amount_min = 0.04
		p.scale_amount_max = 0.1
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.75, 1), Vector2(1, 0)])
		p.color_initial_ramp = _ramp(color.lightened(0.2), color.darkened(0.15))
		_start(p)
	dust(parent, pos, color.lightened(0.25), 4, 0.35)


## Soft dust: puffs that swell, drift up a little and fade.
static func dust(parent: Node, pos: Vector3, color: Color, count := 6, size := 0.4, rise := 0.5) -> void:
	var p := _burst(parent, pos, _quad, count, 1.2)
	if p:
		p.explosiveness = 0.85
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = size * 0.4
		p.direction = Vector3.UP
		p.spread = 90.0
		p.initial_velocity_min = rise * 0.4
		p.initial_velocity_max = rise
		p.gravity = Vector3(0, 0.2, 0)
		p.damping_min = 1.5
		p.damping_max = 2.5
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.scale_amount_min = size * 0.7
		p.scale_amount_max = size * 1.3
		p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.4, 1.0), Vector2(1, 1.3)])
		p.color_ramp = _ramp(Color(color, 0.55), Color(color, 0.0))
		_start(p)


## Leaves shaken loose: they flutter and spin down slowly, drifting with the air.
static func leaves(parent: Node, pos: Vector3, color: Color, count := 6, spread := 1.2) -> void:
	var p := _burst(parent, pos, _leaf, count, 2.6)
	if p:
		p.explosiveness = 0.7
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = spread
		p.direction = Vector3(0.3, -1, 0.2)
		p.spread = 60.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.8
		p.gravity = Vector3(0.25, -1.3, 0.15)
		p.damping_min = 0.6
		p.damping_max = 1.2
		p.angular_velocity_min = -220
		p.angular_velocity_max = 220
		p.particle_flag_rotate_y = true
		p.scale_amount_min = 0.07
		p.scale_amount_max = 0.12
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.85, 1), Vector2(1, 0)])
		p.color_initial_ramp = _ramp(color.lightened(0.12), color.darkened(0.12))
		_start(p)


## Sparks: bright streaks flung out, falling as they cool.
static func sparks(parent: Node, pos: Vector3, color := Color(1.0, 0.62, 0.22), count := 10, speed := 3.5) -> void:
	var p := _burst(parent, pos, _streak, count, 0.6, true)
	if p:
		p.direction = Vector3.UP
		p.spread = 85.0
		p.initial_velocity_min = speed * 0.5
		p.initial_velocity_max = speed
		p.gravity = Vector3(0, -9, 0)
		p.particle_flag_align_y = true
		p.scale_amount_min = 0.02
		p.scale_amount_max = 0.05
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
		p.color_ramp = _ramp(color.lightened(0.4), Color(color.darkened(0.3), 0.0))
		_start(p)


## Steam: white puffs rising and swelling (a quench, a boiling pot).
static func steam(parent: Node, pos: Vector3, count := 8, size := 0.25) -> void:
	var p := _burst(parent, pos, _quad, count, 1.6)
	if p:
		p.explosiveness = 0.6
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = size * 0.4
		p.direction = Vector3.UP
		p.spread = 20.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.2
		p.gravity = Vector3(0, 0.4, 0)
		p.damping_min = 0.8
		p.damping_max = 1.2
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.scale_amount_min = size * 0.6
		p.scale_amount_max = size
		p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.0)])
		p.color_ramp = _ramp(Color(0.95, 0.96, 1.0, 0.55), Color(0.95, 0.96, 1.0, 0.0))
		_start(p)


## A splash: droplets thrown up and a ring of spray (going into water, a stone thrown in).
static func splash(parent: Node, pos: Vector3, strength := 1.0) -> void:
	var p := _burst(parent, pos, _drop, roundi(14 * strength), 0.8, true)
	if p:
		p.direction = Vector3.UP
		p.spread = 35.0
		p.initial_velocity_min = 2.0 * strength
		p.initial_velocity_max = 4.0 * strength
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.03
		p.scale_amount_max = 0.06
		p.color_initial_ramp = _ramp(Color(0.82, 0.9, 0.96), Color(0.55, 0.72, 0.85))
		_start(p)
	dust(parent, pos + Vector3(0, 0.05, 0), Color(0.9, 0.95, 1.0), roundi(5 * strength), 0.45 * strength, 0.4)


## Blood from a hit: a spray of drops thrown away from the blow, a red mist, and drops falling after.
static func blood(parent: Node, pos: Vector3, away: Vector3, amount := 1.0) -> void:
	away.y = maxf(away.y, 0.2)
	var dir := away.normalized() if away.length() > 0.01 else Vector3.UP
	var p := _burst(parent, pos, _drop, roundi(16 * amount), 1.0, true)
	if p:
		p.direction = dir
		p.spread = 30.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.025
		p.scale_amount_max = 0.06
		p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0.3)])
		p.color_initial_ramp = _ramp(Color(0.62, 0.06, 0.06), Color(0.35, 0.02, 0.03))
		_start(p)
	var m := _burst(parent, pos, _quad, roundi(5 * amount), 0.7)
	if m:
		m.direction = dir
		m.spread = 40.0
		m.initial_velocity_min = 0.6
		m.initial_velocity_max = 1.4
		m.gravity = Vector3(0, -1.0, 0)
		m.damping_min = 2.0
		m.damping_max = 3.0
		m.scale_amount_min = 0.15
		m.scale_amount_max = 0.3
		m.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.4)])
		m.color_ramp = _ramp(Color(0.55, 0.05, 0.05, 0.55), Color(0.4, 0.02, 0.02, 0.0))
		_start(m)
	var d := _burst(parent, pos, _drop, roundi(6 * amount), 1.4)
	if d:
		d.explosiveness = 0.2
		d.direction = Vector3.DOWN
		d.spread = 10.0
		d.initial_velocity_min = 0.1
		d.initial_velocity_max = 0.4
		d.gravity = Vector3(0, -9, 0)
		d.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		d.emission_sphere_radius = 0.12
		d.scale_amount_min = 0.02
		d.scale_amount_max = 0.035
		d.color = Color(0.45, 0.03, 0.04)
		_start(d)


## A little twinkle: a few soft stars that pop and fade (picking something up, finishing a craft).
static func twinkle(parent: Node, pos: Vector3, color := Color(1.0, 0.92, 0.6), count := 6, size := 1.0) -> void:
	_setup()
	var p := _burst(parent, pos, _glow_quad, count, 0.7)
	if p:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.2 * size
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 0.3 * size
		p.initial_velocity_max = 0.9 * size
		p.gravity = Vector3(0, 0.6 * size, 0)
		p.scale_amount_min = 0.08 * size
		p.scale_amount_max = 0.16 * size
		p.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.25, 1), Vector2(1, 0)])
		p.color = color
		_start(p)


# --- Continuous emitters ----------------------------------------------------------------------

## Embers rising off a fire, flickering out as they climb. `size` scales it (a torch is small, a forge big).
static func embers(size := 1.0, color := Color(1.0, 0.58, 0.2)) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = _glow_quad
	p.amount = maxi(4, roundi(10 * size))
	p.lifetime = 1.6
	p.randomness = 0.6
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * size
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5 * size
	p.initial_velocity_max = 1.3 * size
	p.gravity = Vector3(0.15, 0.6, 0.0)
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.tangential_accel_min = -0.6
	p.tangential_accel_max = 0.6
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.045
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.6, 0.8), Vector2(1, 0)])
	var eg := Gradient.new()   # bright as it leaves the fire, flickering darker as it climbs
	eg.set_color(0, Color(1.5, 0.95, 0.4))
	eg.add_point(0.4, Color(color.r * 1.4, color.g * 1.2, color.b, 1.0))
	eg.set_color(eg.get_point_count() - 1, Color(color.darkened(0.5), 0.0))
	p.color_ramp = eg
	p.visibility_range_end = 60.0
	return p


## Wisps of smoke curling up and spreading out.
static func smoke(size := 1.0, color := Color(0.36, 0.35, 0.35)) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = _quad
	p.amount = maxi(4, roundi(8 * size))
	p.lifetime = 3.2
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1 * size
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.4 * size
	p.initial_velocity_max = 0.8 * size
	p.gravity = Vector3(0.12, 0.25, 0.05)
	p.damping_min = 0.2
	p.damping_max = 0.4
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -25
	p.angular_velocity_max = 25
	p.scale_amount_min = 0.3 * size
	p.scale_amount_max = 0.45 * size
	p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.4)])
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.add_point(0.2, Color(color, 0.3))
	g.set_color(g.get_point_count() - 1, Color(color.lightened(0.2), 0.0))
	p.color_ramp = g
	p.visibility_range_end = 90.0
	return p


## A fire's particles together (embers and smoke) under one node, to hang on a campfire, brazier or torch.
static func fire(size := 1.0, smoke_at := Vector3(0, 0.3, 0)) -> Node3D:
	var n := Node3D.new()
	n.name = "FireFx"
	n.add_child(embers(size))
	var s := smoke(size)
	s.position = smoke_at
	n.add_child(s)
	return n


## Switch a fire's particles on or off (they cost nothing while off: used to skip far-away fires).
static func set_fire_on(n: Node, on: bool) -> void:
	if n == null:
		return
	for c in n.get_children():
		if c is CPUParticles3D and (c as CPUParticles3D).emitting != on:
			(c as CPUParticles3D).emitting = on


# --- Ambient (see AmbientFx) ------------------------------------------------------------------

static func _ambient(mesh: Mesh, amount: int, lifetime: float, box: Vector3) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.emitting = false
	return p


## Fireflies: little lights drifting about low over the grass, blinking on and off.
static func fireflies() -> CPUParticles3D:
	var p := _ambient(_glow_quad, 40, 7.0, Vector3(14, 1.2, 14))
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, 0.02, 0)
	p.tangential_accel_min = -0.15
	p.tangential_accel_max = 0.15
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.12
	var g := Gradient.new()   # blinks: dark, glow, dark, glow, dark
	g.set_color(0, Color(0.75, 1.0, 0.35, 0.0))
	g.add_point(0.18, Color(0.85, 1.0, 0.45, 1.0))
	g.add_point(0.32, Color(0.75, 1.0, 0.35, 0.0))
	g.add_point(0.55, Color(0.75, 1.0, 0.35, 0.0))
	g.add_point(0.7, Color(0.9, 1.0, 0.5, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.75, 1.0, 0.35, 0.0))
	p.color_ramp = g
	return p


## Leaves coming down out of the canopy and spinning to the ground.
static func falling_leaves() -> CPUParticles3D:
	var p := _ambient(_leaf, 26, 8.0, Vector3(18, 2.5, 18))
	p.direction = Vector3.DOWN
	p.spread = 30.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.3, -0.9, 0.15)
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.angular_velocity_min = -160
	p.angular_velocity_max = 160
	p.tangential_accel_min = -0.4
	p.tangential_accel_max = 0.4
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.13
	p.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.05, 1), Vector2(0.9, 1), Vector2(1, 0)])
	return p


## Snow drifting down and sideways.
static func snowfall() -> CPUParticles3D:
	var p := _ambient(_quad, 160, 7.0, Vector3(20, 5, 20))
	p.direction = Vector3.DOWN
	p.spread = 15.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0.35, -0.5, 0.15)
	p.damping_min = 0.2
	p.damping_max = 0.4
	p.tangential_accel_min = -0.3
	p.tangential_accel_max = 0.3
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.08
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.1, Color(1, 1, 1, 0.9))
	g.add_point(0.85, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	return p


## Dust motes and grit drifting along on the wind (deserts, badlands, dry plains).
static func dust_drift() -> CPUParticles3D:
	var p := _ambient(_quad, 70, 6.0, Vector3(18, 2.0, 18))
	p.direction = Vector3(1, 0.1, 0.4)
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0.1, 0.02, 0.05)
	p.tangential_accel_min = -0.2
	p.tangential_accel_max = 0.2
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.09
	return p


## Water dripping from a cave ceiling: one drop at a time, falling `fall` metres and gone as it lands.
static func drip(fall: float) -> CPUParticles3D:
	_setup()
	var p := CPUParticles3D.new()
	p.mesh = _drop
	p.amount = 1
	p.lifetime = sqrt(2.0 * fall / 9.8)   # it lands (and is gone) just as the next one falls
	p.randomness = 0.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.DOWN
	p.spread = 0.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.028
	# Swelling off the tip, then falling; it vanishes as it reaches the floor.
	p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.12, 1.0), Vector2(0.96, 1.0), Vector2(1, 0)])
	p.color = Color(0.7, 0.82, 0.88)
	p.visibility_range_end = 30.0
	return p


## Set the colour of an ambient emitter's bits (faded in and out at the ends of their lives).
static func tint_ambient(p: CPUParticles3D, color: Color, alpha := 1.0) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.add_point(0.12, Color(color, alpha))
	g.add_point(0.85, Color(color, alpha))
	g.set_color(g.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = g


# --- Bigger moments ---------------------------------------------------------------------------

## Topple a chopped tree away from the player, then fade it out.
static func fall_tree(parent: Node, mesh: Mesh, xf: Transform3D, away: Vector3, color: Color, leaf := Color(0.35, 0.55, 0.3)) -> void:
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
	leaves(parent, xf.origin + Vector3(0, height * 0.75, 0), leaf, 10, 1.4)   # shaken loose as it goes
	var tw := pivot.create_tween()
	tw.tween_method(func(a: float) -> void: pivot.basis = Basis(axis, a), 0.0, rest, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		var hit := Vector3(land.x, Game.world_gen.get_height(land.x, land.z) + 0.3, land.z)
		splinters(parent, hit, color.lightened(0.3), color, 10)
		dust(parent, hit, Color(0.62, 0.55, 0.42), 10, 0.9, 0.8)
		leaves(parent, hit + Vector3(0, 0.8, 0), leaf, 14, 1.8)
		Audio.play_3d(Audio.sfx.tree_fall, hit, 2.0)
		Game.impact.emit(hit, clampf(height / 8.0, 0.4, 1.2)))
	tw.tween_interval(1.6)
	tw.tween_property(mi, "scale", Vector3(1, 0.001, 1), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(pivot.queue_free)


## Rocks and bushes: shrink away with a burst.
static func crumble(parent: Node, mesh: Mesh, xf: Transform3D, color := Color(0.55, 0.56, 0.6), is_rock := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	mi.global_transform = xf
	var at := xf.origin + Vector3(0, 0.3, 0)
	if is_rock:
		shards(parent, at, color, 12)
		dust(parent, at, color.lightened(0.2), 8, 0.6)
	else:
		leaves(parent, at + Vector3(0, 0.3, 0), color, 8, 0.5)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", mi.scale * 0.05, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
