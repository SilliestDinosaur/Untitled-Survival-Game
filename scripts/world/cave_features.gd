class_name CaveFeatures
extends Node3D
## The things inside caves that aren't ground: supply chests, glowing fungus, dripstone (hanging stalactites,
## pillars), rubble, still pools, glowing moss and glow-worms, old miners' camps, the glow of crystal deposits and
## water dripping from the ceilings, placed where the cave plan put them. The rock itself comes from VoxelTerrain,
## so these simply stand in the real caves. Built once per world; the many small pieces are merged into a few meshes
## per area (with how much sky each piece sees baked into its colour's alpha, see painted.gdshader).
## (Ore, crystals and stalagmites are chunk resources: see ChunkGenerator._place_cave_resources.)

## Cave things are only seen from inside the caves: past this they aren't drawn (from the surface they were drawn
## through the ground).
const SEEN_WITHIN := 50.0

var _lights: Array = []
var _time := 0.0


func build(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "features"])
	_build_chests(plan.chests)
	_build_glowcaps(plan.glow, rng)
	if plan.has("stalactites"):
		_build_dressing(plan, rng)
		var bats := CaveBats.new()
		add_child(bats)
		bats.setup(plan.roosts)


func _build_chests(chests: Array) -> void:
	var wood := Color(0.36, 0.25, 0.17)
	for k in chests.size():
		var c: Vector3 = chests[k]
		var body := StaticBody3D.new()
		body.collision_layer = TerrainChunk.LAYER_INTERACT | TerrainChunk.LAYER_SOLID
		body.collision_mask = 0
		body.position = c
		body.set_meta("cave_chest", k)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.1, 0.7, 0.7)
		cs.shape = box
		cs.position.y = 0.35
		body.add_child(cs)
		var kit := MeshKit.new(11 + k)
		kit.add_primitive(_cube(Vector3(1.1, 0.5, 0.7)), Transform3D(Basis(), Vector3(0, 0.25, 0)), wood, 0.0, 0.04)
		kit.add_primitive(_cube(Vector3(1.14, 0.2, 0.74)), Transform3D(Basis(), Vector3(0, 0.6, 0)), wood.lightened(0.08), 0.0, 0.04)
		kit.add_primitive(_cube(Vector3(0.12, 0.2, 0.06)), Transform3D(Basis(), Vector3(0, 0.45, 0.37)), Color(0.8, 0.66, 0.3), 0.0, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.3}))
		mi.visibility_range_end = SEEN_WITHIN
		body.add_child(mi)
		add_child(body)
		CaveShade.apply(body, CaveShade.at(c))


func _build_glowcaps(glow: Array, rng: RandomNumberGenerator) -> void:
	var kinds := ["glowcap_0", "glowcap_1", "glowcap_2"]
	var k := 0
	for g: Vector3 in glow:
		var key: String = kinds[rng.randi() % kinds.size()]
		if not Game.flora.has_mesh(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Game.flora.mesh(key)
		mi.position = g
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		mi.visibility_range_end = SEEN_WITHIN
		add_child(mi)
		CaveShade.apply(mi, CaveShade.at(g))
		if k % 10 == 0 and _lights.size() < 12:   # a few of them light the place up
			var light := OmniLight3D.new()
			light.light_color = Game.palette.glow
			light.light_energy = 0.9
			light.omni_range = 7.0
			light.omni_attenuation = 1.5
			light.position = g + Vector3(0, 0.5, 0)
			light.distance_fade_enabled = true   # off the lighting work when you're nowhere near
			light.distance_fade_begin = SEEN_WITHIN - 10.0
			light.distance_fade_length = 10.0
			add_child(light)
			_lights.append(light)
		k += 1


func _cube(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _process(delta: float) -> void:
	_time += delta
	for light: OmniLight3D in _lights:
		light.light_energy = 0.8 + sin(_time * 1.3 + light.position.x) * 0.12
	for l: OmniLight3D in _lanterns:
		l.light_energy = 1.1 + 0.15 * sin(_time * 9.0 + l.position.z) * sin(_time * 4.3)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_wake_nearby()


# --- Dressing -------------------------------------------------------------------------------------

const AREA := 32.0           ## pieces are merged per area this many metres square
const DRIP_NEAR := 22.0      ## drips only run within this of the camera
const GLOW_COLOURS := [Color(0.35, 1.0, 0.82), Color(0.72, 0.5, 1.0), Color(1.0, 0.72, 0.3)]

var _areas := {}             ## Vector2i -> {"rock": MeshKit, "glow": MeshKit, "water": MeshKit, "centre": Vector3}
var _lanterns: Array = []
var _drips: Array = []       ## [CPUParticles3D, ceiling pos]
var _crystals: Array = []    ## [OmniLight3D, resource id]
var _check := 0.0
var k_lights := 0
static var _glow_mat: ShaderMaterial
static var _water_mat: StandardMaterial3D


func _area(p: Vector3) -> Dictionary:
	var key := Vector2i(floori(p.x / AREA), floori(p.z / AREA))
	if not _areas.has(key):
		_areas[key] = {"rock": MeshKit.new(hash(key)), "glow": MeshKit.new(hash(key) + 1), "water": MeshKit.new(hash(key) + 2),
			"centre": Vector3((key.x + 0.5) * AREA, p.y, (key.y + 0.5) * AREA), "n": {"rock": 0, "glow": 0, "water": 0}}
	return _areas[key]


## A colour carrying how much sky this spot sees (the painted shader darkens by it).
static func _lit(c: Color, p: Vector3) -> Color:
	return Color(c, Caves.sky_seen(Game.world_gen.caves, p))


func _build_dressing(plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var pal: WorldPalette = Game.palette
	var drip_col := pal.rock.lerp(Color(0.72, 0.66, 0.56), 0.35)
	# Stalactites: lumpy cones hanging from the ceiling, banded, pale and wet at the tip.
	for st: Array in plan.stalactites:
		var top: Vector3 = st[0]
		var length: float = st[1]
		var a := _area(top)
		var c := _lit(drip_col.lerp(pal.rock, rng.randf() * 0.4), top - Vector3(0, length * 0.5, 0))
		var path: Array = []
		var radii: Array = []
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06)) * length
		for i in 6:
			var t := i / 5.0
			path.append(top + Vector3(0, 0.15 - t * (length + 0.15), 0) + lean * t * t)
			radii.append(lerpf(0.16 + length * 0.12, 0.015, pow(t, 0.75)))
		(a.rock as MeshKit).loft(path, radii, 7, c, Callable(), Callable(), true, true, 0.02)
		a.n.rock += 1
	# Pillars: where a stalactite met a stalagmite long ago, floor to ceiling, waisted in the middle.
	for pl: Array in plan.pillars:
		var foot: Vector3 = pl[0]
		var ceil_y: float = pl[1]
		var r: float = pl[2]
		var a := _area(foot)
		var c := _lit(drip_col, foot + Vector3(0, 1.0, 0))
		var hgt := ceil_y - foot.y + 0.3
		var path: Array = []
		var radii: Array = []
		for i in 7:
			var t := i / 6.0
			path.append(foot + Vector3(0, -0.15 + t * hgt, 0))
			radii.append(r * (1.0 + 0.7 * pow(absf(t - 0.5) * 2.0, 2.0)) * (1.0 + 0.06 * sin(t * 23.0)))
		(a.rock as MeshKit).loft(path, radii, 10, c, func(t: float, _ang: float) -> Color:
			return c.lightened(0.12) if fmod(t * 11.0, 1.0) > 0.7 else c, Callable(), true, true, 0.05)
		a.n.rock += 1
		var body := StaticBody3D.new()
		body.collision_layer = TerrainChunk.LAYER_SOLID
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 1.05
		cyl.height = hgt
		cs.shape = cyl
		body.position = foot + Vector3(0, hgt * 0.5 - 0.15, 0)
		body.add_child(cs)
		add_child(body)
	# Rubble: fallen stones heaped at the foot of the walls.
	for rb: Array in plan.rubble:
		var at: Vector3 = rb[0]
		var rad: float = rb[1]
		var a := _area(at)
		for k in rng.randi_range(4, 8):
			var ang := rng.randf() * TAU
			var d := rng.randf() * rad
			var sz := rng.randf_range(0.12, 0.3) * (1.2 - d / rad * 0.5)
			var p := at + Vector3(cos(ang) * d, sz * 0.25 - 0.04, sin(ang) * d)
			(a.rock as MeshKit).add_primitive(MeshKit.sphere(sz, 6, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, 0.7, 1.0)), p),
				_lit(pal.rock.darkened(rng.randf_range(0.0, 0.15)), p), 0.25, 0.04)
		a.n.rock += 1
	# Still pools: dark water in a shallow basin, a rim of wet stones.
	for pool: Array in plan.pools:
		var at: Vector3 = pool[0]
		var pr: float = pool[1]
		var a := _area(at)
		(a.water as MeshKit).add_primitive(MeshKit.cylinder(pr, pr * 0.9, 0.06, 20), Transform3D(Basis(), at - Vector3(0, 0.03, 0)), Color(0.08, 0.17, 0.2), 0.0, 0.0)
		a.n.water += 1
		for k in 14:
			var ang := TAU * k / 14.0 + rng.randf_range(-0.1, 0.1)
			var p := at + Vector3(cos(ang) * pr, -0.04, sin(ang) * pr)
			(a.rock as MeshKit).add_primitive(MeshKit.sphere(rng.randf_range(0.12, 0.22), 6, 4), Transform3D(Basis().scaled(Vector3(1.3, 0.55, 1.0)), p),
				_lit(pal.rock.darkened(0.25), p), 0.2, 0.03)
		a.n.rock += 1
	# Glowing moss: soft clumps spread on the wall.
	for m: Array in plan.moss:
		var at: Vector3 = m[0]
		var nrm: Vector3 = m[1]
		var col: Color = GLOW_COLOURS[int(m[2])]
		var a := _area(at)
		var side := nrm.cross(Vector3.UP).normalized()
		for k in rng.randi_range(7, 13):
			var p := at + side * rng.randf_range(-0.7, 0.7) + Vector3(0, rng.randf_range(-0.5, 0.5), 0)
			var sz := rng.randf_range(0.06, 0.16)
			(a.glow as MeshKit).add_primitive(MeshKit.sphere(sz, 6, 3), Transform3D(Basis(Quaternion(Vector3.UP, nrm)).scaled(Vector3(1.0, 0.35, 1.0)), p),
				col.darkened(rng.randf_range(0.0, 0.35)), 0.2, 0.0)
		a.n.glow += 1
		if k_lights < 14 and rng.randf() < 0.3:
			_glow_light(at + nrm * 0.4, col, 0.5, 4.5)
	# Glow-worms: silk threads hanging from the ceiling, a glowing bead at the end of each.
	for w: Array in plan.worms:
		var top: Vector3 = w[0]
		var col: Color = GLOW_COLOURS[int(w[1])]
		var a := _area(top)
		for k in rng.randi_range(8, 16):
			var p := top + Vector3(rng.randf_range(-0.9, 0.9), 0.05, rng.randf_range(-0.9, 0.9))
			var len := rng.randf_range(0.25, 1.3)
			(a.rock as MeshKit).loft([p, p - Vector3(0, len, 0)], [0.006, 0.004], 3, _lit(Color(0.75, 0.78, 0.72), p), Callable(), Callable(), false, false)
			(a.glow as MeshKit).add_primitive(MeshKit.sphere(rng.randf_range(0.014, 0.024), 5, 3), Transform3D(Basis(), p - Vector3(0, len, 0)), col, 0.0, 0.0)
		a.n.rock += 1
		a.n.glow += 1
		if k_lights < 14 and rng.randf() < 0.35:
			_glow_light(top - Vector3(0, 0.8, 0), col, 0.45, 5.0)
	# Old miners' camps.
	for camp: Array in plan.camps:
		_build_camp(camp[0], float(camp[1]), rng)
	# Crystal deposits glow (their light goes when they're mined).
	for i in plan.ores.size():
		var o: Array = plan.ores[i]
		if o[1] != "gem_t4" or _crystals.size() >= 16:
			continue
		var p: Vector3 = o[0]
		var cc := Vector2i(floori(p.x / Game.CHUNK_SIZE), floori(p.z / Game.CHUNK_SIZE))
		var l := OmniLight3D.new()
		l.light_color = ItemDB.tier_info(4).color.lightened(0.3)
		l.light_energy = 0.8
		l.omni_range = 5.5
		l.omni_attenuation = 1.6
		l.position = p + Vector3(0, 0.7, 0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = SEEN_WITHIN - 10.0
		l.distance_fade_length = 10.0
		add_child(l)
		_crystals.append([l, "%d_%d_c%d" % [cc.x, cc.y, i]])
	# Water drips: one falling drop at a time from each, run only near the camera.
	for d: Vector3 in plan.drips:
		var fl: Variant = Caves.floor_at(Game.world_gen.caves, d - Vector3(0, 0.3, 0))
		if fl == null:
			continue
		var fall := maxf(d.y - (fl as Vector3).y, 0.3)
		var e := Effects.drip(fall)
		e.position = d
		e.emitting = false
		add_child(e)
		_drips.append([e, d])
	_commit_areas()




func _glow_light(at: Vector3, col: Color, energy: float, rng_m: float) -> void:
	k_lights += 1
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.8
	l.position = at
	l.distance_fade_enabled = true
	l.distance_fade_begin = SEEN_WITHIN - 10.0
	l.distance_fade_length = 10.0
	add_child(l)


func _commit_areas() -> void:
	if not _water_mat:
		if not _glow_mat:
			_glow_mat = ShaderMaterial.new()
			_glow_mat.shader = preload("res://shaders/glow_vertex.gdshader")
		_water_mat = StandardMaterial3D.new()
		_water_mat.vertex_color_use_as_albedo = true
		_water_mat.roughness = 0.06
		_water_mat.metallic = 0.0
		_water_mat.disable_ambient_light = true   # no sky to reflect down here: only lamps and torches glint on it
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.albedo_color = Color(1, 1, 1, 0.88)
	var rock_mat := ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.2})
	for key: Vector2i in _areas:
		var a: Dictionary = _areas[key]
		for part: String in ["rock", "glow", "water"]:
			if int(a.n[part]) == 0:
				continue
			var mi := MeshInstance3D.new()
			var centre: Vector3 = a.centre
			mi.mesh = _recentred((a[part] as MeshKit).commit(rock_mat if part == "rock" else (_glow_mat if part == "glow" else _water_mat)), centre)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part != "rock" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.position = centre
			# Seen only from inside the caves near it (the area's middle plus its reach).
			mi.visibility_range_end = SEEN_WITHIN + AREA * 0.75
			add_child(mi)
	_areas.clear()


## An abandoned camp: a burnt-out fire in a ring of stones, crates, a mine cart, a bedroll, bones, a pick leaning on
## a crate, and a lantern still burning low. (Its supply crate is one of the plan's chests.)
## The same mesh with its vertices moved so `centre` is its origin (so it can stand at the centre and be faded by
## distance from there).
static func _recentred(mesh: ArrayMesh, centre: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] -= centre
		arrays[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(si, mesh.surface_get_material(si))
	return out


func _build_camp(at: Vector3, facing: float, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = facing
	add_child(root)
	var k := MeshKit.new(hash(at))
	var lit := func(c: Color) -> Color: return _lit(c, at + Vector3(0, 0.5, 0))
	var wood: Color = lit.call(Color(0.42, 0.3, 0.2))
	var dark: Color = lit.call(Color(0.24, 0.17, 0.12))
	var stone: Color = lit.call(Game.palette.rock.darkened(0.1))
	# The dead fire: stones round a bed of ash and two charred logs.
	for i in 9:
		var ang := TAU * i / 9.0
		k.add_primitive(MeshKit.sphere(0.13, 6, 4), Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1.0)), Vector3(cos(ang) * 0.45, 0.04, sin(ang) * 0.45)), stone, 0.2, 0.04)
	k.add_primitive(MeshKit.cylinder(0.38, 0.4, 0.04, 12), Transform3D(Basis(), Vector3(0, 0.02, 0)), lit.call(Color(0.32, 0.31, 0.3)), 0.0, 0.06)
	for s in [-1.0, 1.0]:
		k.loft([Vector3(-0.3, 0.08, s * 0.08), Vector3(0.3, 0.1, -s * 0.05)], [0.06, 0.05], 6, lit.call(Color(0.1, 0.09, 0.08)))
	# Crates, stacked.
	for c: Array in [[Vector3(1.4, 0.3, -0.9), 0.6], [Vector3(1.9, 0.3, -0.5), 0.6], [Vector3(1.6, 0.9, -0.7), 0.5]]:
		var p: Vector3 = c[0]
		var sz: float = c[1]
		k.add_primitive(_cube(Vector3(sz, sz, sz)), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p), wood.lightened(rng.randf_range(-0.05, 0.05)), 0.0, 0.05)
		for e in [-1.0, 1.0]:
			k.add_primitive(_cube(Vector3(sz + 0.02, 0.06, sz + 0.02)), Transform3D(Basis(), p + Vector3(0, e * sz * 0.4, 0)), dark, 0.0, 0.03)
		_solid(root, p, Vector3(sz, sz, sz))
	# A mine cart, tipped a little, on its wheels.
	var cart := Vector3(-1.6, 0.0, 0.6)
	var iron: Color = lit.call(Color(0.3, 0.29, 0.3))
	var tub := Transform3D(Basis(Vector3.UP, 0.5).rotated(Vector3.FORWARD, 0.06), cart + Vector3(0, 0.55, 0))
	k.add_primitive(MeshKit.cylinder(0.55, 0.42, 0.55, 4), tub * Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.3, 1.0, 0.85)), Vector3.ZERO), wood, 0.0, 0.06)
	k.add_primitive(_cube(Vector3(1.0, 0.06, 0.62)), tub * Transform3D(Basis(), Vector3(0, 0.28, 0)), iron, 0.0, 0.03)
	for wx in [-0.32, 0.32]:
		for wz in [-0.3, 0.3]:
			k.add_primitive(MeshKit.cylinder(0.15, 0.15, 0.06, 10), tub * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, -0.38, wz)), iron, 0.0, 0.02)
	_solid(root, cart + Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 0.8))
	# A bedroll and a scatter of bones.
	k.add_primitive(MeshKit.cylinder(0.16, 0.16, 1.2, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.2, 0.13, 1.3)), lit.call(Color(0.42, 0.22, 0.2)), 0.05, 0.05)
	var bone: Color = lit.call(Color(0.82, 0.78, 0.68))
	k.add_primitive(MeshKit.sphere(0.12, 8, 6), Transform3D(Basis().scaled(Vector3(1.0, 0.85, 1.15)), Vector3(-0.8, 0.1, 1.5)), bone, 0.0, 0.03)
	for i in 4:
		var a0 := Vector3(-0.5 + i * 0.12, 0.03, 1.2 + rng.randf_range(-0.1, 0.1))
		k.loft([a0, a0 + Vector3(rng.randf_range(-0.3, 0.3), 0.0, 0.35)], [0.025, 0.02], 5, bone)
	# A pick leaning on the crates.
	var handle_a := Vector3(1.05, 0.02, -0.4)
	var handle_b := Vector3(1.15, 0.85, -0.65)
	k.loft([handle_a, handle_b], [0.025, 0.022], 6, wood.lightened(0.1))
	k.loft([handle_b + Vector3(-0.25, 0.02, 0.05), handle_b + Vector3(0, 0.06, 0), handle_b + Vector3(0.25, 0.0, -0.05)], [0.02, 0.04, 0.015], 6, iron)
	# The lantern, on the top crate, still glowing.
	var lp := Vector3(1.6, 1.22, -0.7)
	k.add_primitive(MeshKit.cylinder(0.07, 0.09, 0.2, 6), Transform3D(Basis(), lp), iron, 0.0, 0.0)
	var gk := MeshKit.new(5)
	gk.add_primitive(MeshKit.sphere(0.06, 8, 5), Transform3D(Basis(), lp + Vector3(0, 0.02, 0)), Color(1.0, 0.7, 0.35), 0.0, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.25}))
	mi.visibility_range_end = SEEN_WITHIN
	root.add_child(mi)
	var gm := MeshInstance3D.new()
	if not _glow_mat:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = preload("res://shaders/glow_vertex.gdshader")
	gm.mesh = gk.commit(_glow_mat)
	gm.visibility_range_end = SEEN_WITHIN
	root.add_child(gm)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.66, 0.32)
	l.omni_range = 7.0
	l.omni_attenuation = 1.4
	l.position = lp + Vector3(0, 0.1, 0)
	l.distance_fade_enabled = true
	l.distance_fade_begin = SEEN_WITHIN - 10.0
	l.distance_fade_length = 10.0
	root.add_child(l)
	_lanterns.append(l)


func _solid(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_SOLID
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.position = at
	body.add_child(cs)
	parent.add_child(body)


## Every half second: drips run near the camera only, and a mined crystal's glow goes out.
func _wake_nearby() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var near := DRIP_NEAR * DRIP_NEAR
	for d: Array in _drips:
		var on: bool = Game.in_cave and eye.distance_squared_to(d[1]) < near
		if (d[0] as CPUParticles3D).emitting != on:
			(d[0] as CPUParticles3D).emitting = on
	for c: Array in _crystals:
		(c[0] as OmniLight3D).visible = not Game.is_removed(String(c[1]))
