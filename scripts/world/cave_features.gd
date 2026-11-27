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
	_build_mouths(plan, rng)
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
		# Many of them cast a pool of their glow on the floor and walls round them (each light is only drawn near the
		# camera: see distance_fade).
		if k % 3 == 0 and _lights.size() < 45:
			var light := OmniLight3D.new()
			light.light_color = Game.palette.glow
			light.light_energy = 1.0
			light.omni_range = 7.5
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
		if _shaft_mat:
			var day := Game.daylight()
			_shaft_mat.set_shader_parameter("day", day)
			var cam := get_viewport().get_camera_3d()
			if cam:
				for sh: Array in _shafts:
					var p := sh[0] as CPUParticles3D
					var on := day > 0.2 and cam.global_position.distance_squared_to(sh[1]) < 35.0 * 35.0
					if p.emitting != on:
						p.emitting = on


# --- Cave mouths ---------------------------------------------------------------------------------

## Each mouth framed so it reads as a cave from down the slope: an arch of half-buried stones over the opening, a
## boulder to each side at its foot. Seen from much further off than the dressing inside (one mesh per mouth).
func _build_mouths(plan: Dictionary, rng: RandomNumberGenerator) -> void:
	var gen: WorldGen = Game.world_gen
	var mat := ArtStyle.painted({"brush_strength": 0.25, "rim_amount": 0.15})
	for e in plan.roots.size():
		var root: Dictionary = plan.nodes[plan.roots[e]]
		var mouth: Vector3 = root.p
		var inward := Vector3.ZERO
		for sg: Array in plan.segs:
			if (sg[0] as Vector3).distance_to(mouth) < 0.3:
				inward = (sg[1] as Vector3) - mouth
				break
		inward.y = 0.0
		if inward.length() < 0.1:
			continue
		inward = inward.normalized()
		var side := inward.cross(Vector3.UP).normalized()
		var stone: Color = Caves.rock_color(plan, mouth, 0.0).lerp(Game.palette.rock, 0.5)
		var kit := MeshKit.new(e + 77)
		var r := float(root.r)
		var placed := 0
		# The arch: stones round the top and sides of the opening, pushed out of the void and bedded in the ground.
		for k in 11:
			var a := lerpf(0.08, 0.92, k / 10.0) * PI + rng.randf_range(-0.05, 0.05)
			var size := rng.randf_range(0.55, 0.85) * (1.0 + 0.45 * sin(a))   # bigger over the top (the lintel)
			var p := mouth + side * cos(a) * r * 1.05 + Vector3.UP * sin(a) * r * 0.95 - inward * 0.6
			var ground := gen.get_height(p.x, p.z)
			if p.y > ground + size * 0.25:
				p.y = ground + size * 0.25   # on the slope, not hanging in the air
			if p.y < ground - size * 0.8:
				continue   # buried: nothing would show
			# Then out of the opening (the slope over it has been cut away): the stones sit in the rim, never in the
			# way in. Outward from the mouth's middle and up the slope.
			var clear := true
			for it in 10:
				var vd := Caves.void_distance(plan, p)
				if vd >= size * 0.4:
					break
				var away := p - mouth
				away.y = maxf(away.y, 0.0) + 0.5
				p += away.normalized() * (size * 0.4 - vd + 0.05)
				clear = it < 9
			if not clear or p.y > gen.get_height(p.x, p.z) + size * 0.4:
				continue   # nowhere it could sit on the rim
			var b := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU)
			kit.add_primitive(MeshKit.sphere(1.0, 8, 5), Transform3D(b.scaled(Vector3(size * 1.3, size * 0.8, size)), p),
				Color(stone.darkened(rng.randf_range(0.0, 0.25)), 1.0), 0.3, 0.06)
			placed += 1
		# A boulder to each side at the foot of the mouth (solid: you walk round them).
		for sgn: float in [-1.0, 1.0]:
			var size := rng.randf_range(0.7, 1.15)
			var p := mouth + side * sgn * (r + size * 0.9) - inward * rng.randf_range(0.8, 1.8)
			if Caves.void_distance(plan, p) < size:
				continue
			p.y = ChunkGenerator.lowest_ground(gen, p.x, p.z, size * 1.1, size * 1.1) + size * 0.25   # (its downhill side too)
			kit.add_primitive(MeshKit.sphere(1.0, 9, 6), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 1.2, size * 0.85, size)), p),
				Color(stone.darkened(rng.randf_range(0.05, 0.2)), 1.0), 0.3, 0.06)
			_solid(self, p + Vector3(0, size * 0.2, 0), Vector3(size * 1.6, size * 1.2, size * 1.4))
			placed += 1
		_shaft(mouth, inward, r)
		if placed == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _recentred(kit.commit(mat), mouth)
		mi.position = mouth
		mi.visibility_range_end = 220.0
		add_child(mi)


static var _shaft_mat: ShaderMaterial
var _shafts: Array = []   ## [dust particles, mouth] (the dust only drifts while you're near)

## Daylight slanting in through a mouth (crossed quads of glowing air, see light_shaft.gdshader) with dust drifting in
## it: from the opening, in and down to the floor a few metres inside.
func _shaft(mouth: Vector3, inward: Vector3, r: float) -> void:
	if not _shaft_mat:
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = preload("res://shaders/light_shaft.gdshader")
	var top := mouth + Vector3(0, r * 0.55, 0) - inward * 0.4
	var dir := (inward + Vector3(0, -0.55, 0)).normalized()
	var length := r * 3.2
	var width := r * 1.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := inward.cross(Vector3.UP).normalized()
	for across: Vector3 in [side, dir.cross(side).normalized()]:
		var corners := [top - across * width * 0.5, top + across * width * 0.5,
			top + dir * length + across * width * 0.75, top + dir * length - across * width * 0.75]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[k])
			st.add_vertex((corners[k] as Vector3) - mouth)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _shaft_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = mouth
	mi.visibility_range_end = 90.0
	add_child(mi)
	var dust := Effects.dust_drift()
	dust.amount = 26
	dust.emission_box_extents = Vector3(width * 0.4, r * 0.5, length * 0.35)
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.2
	dust.direction = Vector3(0, -0.2, 0)
	dust.gravity = Vector3(0, -0.01, 0)
	dust.scale_amount_min = 0.015
	dust.scale_amount_max = 0.035
	dust.color = Color(1.0, 0.95, 0.85, 0.5)
	add_child(dust)
	dust.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), top + dir * length * 0.45)
	_shafts.append([dust, mouth])


# --- Dressing -------------------------------------------------------------------------------------

const AREA := 32.0           ## pieces are merged per area this many metres square
const DRIP_NEAR := 22.0      ## drips only run within this of the camera
const GLOW_COLOURS := [Color(0.35, 1.0, 0.82), Color(0.72, 0.5, 1.0), Color(1.0, 0.72, 0.3)]
const CRYSTAL_COLOURS := [Color(0.45, 0.85, 1.0), Color(0.75, 0.5, 1.0), Color(1.0, 0.5, 0.75)]
const SHROOM_COLOURS := [Color(0.55, 0.4, 1.0), Color(0.3, 0.85, 0.95), Color(1.0, 0.45, 0.7)]
const MAX_GLOW_LIGHTS := 40


## How far above a planned ceiling spot a hanging thing starts, so it's rooted in the rock: the built ceiling can sit
## a little higher than the planned one (the ground mesh only follows it to within its grid), and a thing hung from
## exactly the planned spot would float under it. Up to a metre, but never out through the ground above.
static func _root_lift(top: Vector3) -> float:
	var ground: float = Game.world_gen.get_height(top.x, top.z)
	return clampf(ground - top.y - 0.25, 0.0, 1.0)


static func _drip_colour(theme: int, stone: Color) -> Color:
	match theme:
		Caves.Rock.ICE:
			return Color(0.7, 0.84, 0.94)
		Caves.Rock.SAND:
			return Color(0.72, 0.55, 0.38)
		Caves.Rock.FUNGAL:
			return Color(0.5, 0.42, 0.52)
		Caves.Rock.CRYSTAL:
			return Color(0.42, 0.42, 0.52)
		Caves.Rock.MOSS:
			return stone.lerp(Color(0.4, 0.46, 0.32), 0.4)
	return stone

var _areas := {}             ## Vector2i -> {"rock": MeshKit, "glow": MeshKit, "water": MeshKit, "centre": Vector3}
var _lanterns: Array = []
var _drips: Array = []       ## [CPUParticles3D, ceiling pos]
var _crystals: Array = []    ## [OmniLight3D, resource id]
var _check := 0.0
var k_lights := 0
static var _glow_mat: ShaderMaterial
static var _water_mat: ShaderMaterial


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
	# Stalactites: lumpy cones hanging from the ceiling, banded, pale and wet at the tip (clear blue icicles in the
	# ice caves, sandy in the sandstone, tinted in the fungal and crystal caves).
	for st: Array in plan.stalactites:
		var top: Vector3 = st[0]
		var length: float = st[1]
		var a := _area(top)
		var c := _lit(_drip_colour(Caves.theme_at(plan, top), drip_col).lerp(pal.rock, rng.randf() * 0.25), top - Vector3(0, length * 0.5, 0))
		var path: Array = []
		var radii: Array = []
		var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06)) * length
		var lift := maxf(_root_lift(top), 0.15)
		path.append(top + Vector3(0, lift, 0))   # the root, up in the rock
		radii.append(0.18 + length * 0.13)
		for i in 6:
			var t := i / 5.0
			path.append(top + Vector3(0, -t * length, 0) + lean * t * t)
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
				_lit(_drip_colour(Caves.theme_at(plan, at), pal.rock).darkened(rng.randf_range(0.1, 0.3)), p), 0.25, 0.04)
		a.n.rock += 1
	# Pebbles: small stones scattered along the tunnel floors (on each piece's own flat floor, near its middle).
	var gen: WorldGen = Game.world_gen
	for sg: Array in plan.segs:
		if float(sg[6]) <= Caves.NO_FLOOR * 0.5:
			continue   # a lake's basin
		var a0: Vector3 = sg[0]
		var b0: Vector3 = sg[1]
		var len := a0.distance_to(b0)
		var flat := Vector3(b0.x - a0.x, 0, b0.z - a0.z)
		if flat.length() < 0.5:
			continue
		var sd := flat.normalized().cross(Vector3.UP)
		for k in int(len / 2.5):
			if rng.randf() < 0.45:
				continue
			var t := rng.randf()
			var mid := a0.lerp(b0, t)
			var fl := lerpf(float(sg[6]), float(sg[7]), t)
			var r := lerpf(float(sg[2]), float(sg[3]), t)
			var dy := mid.y - fl
			if dy >= r:
				continue
			var half := sqrt(r * r - dy * dy) * 0.75   # the flat floor's half width, kept clear of the wall's foot
			var p := Vector3(mid.x, fl, mid.z) + sd * rng.randf_range(-half, half)
			if p.y > gen.get_height(p.x, p.z) - 0.4:
				continue   # out in the mouth: the open ground has its own stones
			var a := _area(p)
			var col := _drip_colour(Caves.theme_at(plan, p), pal.rock)
			for n in rng.randi_range(1, 3):
				var sz := rng.randf_range(0.04, 0.11)
				var q := p + Vector3(rng.randf_range(-0.3, 0.3), sz * 0.2 - 0.02, rng.randf_range(-0.3, 0.3))
				(a.rock as MeshKit).add_primitive(MeshKit.sphere(sz, 5, 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.6, 1.0)), q),
					_lit(col.darkened(rng.randf_range(0.0, 0.3)), q), 0.25, 0.04)
			a.n.rock += 1
	# Underground lakes: still dark water filling the bowl in a chamber's floor, wet stones along the shore.
	for lk: Array in plan.get("lakes", []):
		var at: Vector3 = lk[0]
		var lr: float = lk[1]
		var a := _area(at)
		(a.water as MeshKit).add_primitive(MeshKit.cylinder(lr, lr, 0.04, 40), Transform3D(Basis(), at - Vector3(0, 0.02, 0)), Color(0.1, 0.26, 0.3), 0.0, 0.0)
		a.n.water += 1
		var stones := int(lr * 5.0)
		for k in stones:
			var ang := TAU * k / stones + rng.randf_range(-0.08, 0.08)
			var p := at + Vector3(cos(ang) * (lr - 0.1), 0.0, sin(ang) * (lr - 0.1))
			if rng.randf() < 0.35:
				continue
			(a.rock as MeshKit).add_primitive(MeshKit.sphere(rng.randf_range(0.1, 0.24), 6, 4), Transform3D(Basis().scaled(Vector3(1.3, 0.5, 1.0)), p),
				_lit(pal.rock.darkened(0.3), p), 0.2, 0.03)
		a.n.rock += 1
	# Crystal caverns: six-sided crystals in clusters, glowing.
	for cr: Array in plan.get("crystals", []):
		var foot: Vector3 = cr[0]
		var dir: Vector3 = cr[1]
		var length: float = cr[2]
		var col: Color = CRYSTAL_COLOURS[int(cr[3])]
		var a := _area(foot)
		for k in rng.randi_range(3, 6):
			var d := (dir + Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.45, 0.45))).normalized()
			var l := length * (1.0 if k == 0 else rng.randf_range(0.35, 0.75))
			var w := l * rng.randf_range(0.12, 0.17)
			# Rooted well into the rock (the rock curves away under a cluster's outer crystals).
			var base := foot - dir * 0.35 + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)) * (0.0 if k == 0 else 1.0)
			var b := Basis(Quaternion(Vector3.UP, d)) * Basis(Vector3.UP, rng.randf() * TAU)
			var shade := col.darkened(rng.randf_range(0.0, 0.3)).lerp(Color.WHITE, rng.randf_range(0.0, 0.2))
			(a.glow as MeshKit).add_primitive(MeshKit.cylinder(w, w * 1.08, l + 0.35, 6), Transform3D(b, base + d * ((l + 0.35) * 0.5)), shade, 0.0, 0.0)
			(a.glow as MeshKit).add_primitive(MeshKit.cylinder(0.0, w, w * 1.6, 6, false), Transform3D(b, base + d * (l + 0.35 + w * 0.8)), shade.lightened(0.25), 0.0, 0.0)
		a.n.glow += 1
		if k_lights < MAX_GLOW_LIGHTS + 8 and rng.randf() < 0.55:   # crystal caverns get their own share of lights
			_glow_light(foot + dir * length * 0.6 + Vector3(0, 0.3, 0), col, 1.3, 8.0)
		if dir.y > 0.5 and length > 1.0:
			_solid(self, foot + Vector3(0, length * 0.4, 0), Vector3(length * 0.3, length * 0.8, length * 0.3))
	# Vines over the cave mouths and from the ceilings of the green caves; pale roots deeper in.
	for hg: Array in plan.get("hanging", []):
		var top: Vector3 = hg[0]
		var length: float = hg[1]
		var leafy: bool = int(hg[2]) == 0
		var a := _area(top)
		for k in rng.randi_range(3, 6):
			var p := top + Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
			if Caves.void_distance(Game.world_gen.caves, p - Vector3(0, 0.4, 0)) > -0.05:
				continue
			var l := length * rng.randf_range(0.5, 1.0)
			var path: Array = []
			var radii: Array = []
			var sway := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
			var lift := maxf(_root_lift(p), 0.1)
			if lift < 0.45:   # a thin lip of rock: the vine grows over it from the ground on top
				lift = maxf(Game.world_gen.get_height(p.x, p.z) - p.y - 0.03, 0.1)
			path.append(p + Vector3(0, lift, 0))   # grown from up in the rock, so it never hangs from thin air
			radii.append(0.022 if leafy else 0.03)
			for i in 6:
				var t := i / 5.0
				path.append(p + Vector3(0, -l * t, 0) + sway * sin(t * PI) + Vector3(sin(t * 7.0 + p.x), 0, cos(t * 6.0 + p.z)) * 0.03)
				radii.append(lerpf(0.022 if leafy else 0.03, 0.01, t))
			var vc := Color(0.24, 0.36, 0.16) if leafy else Color(0.62, 0.55, 0.44)
			(a.rock as MeshKit).loft(path, radii, 4, _lit(vc, p), Callable(), Callable(), false, true)
			if leafy:
				for i in range(2, 7):
					if rng.randf() < 0.25:
						continue
					var lp: Vector3 = path[i] + Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
					(a.rock as MeshKit).add_primitive(MeshKit.sphere(rng.randf_range(0.06, 0.1), 5, 3),
						Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.4, 0.35, 0.8)), lp),
						_lit(Color(0.27, 0.45, 0.18).darkened(rng.randf_range(0.0, 0.25)), lp), 0.1, 0.05)
			elif rng.randf() < 0.5:   # roots fork
				var fork: Vector3 = path[3]
				(a.rock as MeshKit).loft([fork, fork + Vector3(rng.randf_range(-0.3, 0.3), -l * 0.35, rng.randf_range(-0.3, 0.3))], [0.014, 0.006], 4, _lit(vc, fork), Callable(), Callable(), false, true)
		a.n.rock += 1
	# Giant mushrooms in the fungal caves: a pale stalk, a broad glowing cap with gills underneath.
	for sh: Array in plan.get("shrooms", []):
		var foot: Vector3 = sh[0]
		var hgt: float = sh[1]
		var col: Color = SHROOM_COLOURS[int(sh[2])]
		var a := _area(foot)
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)) * hgt
		var path: Array = []
		var radii: Array = []
		for i in 5:
			var t := i / 4.0
			path.append(foot + Vector3(0, -0.1 + t * hgt, 0) + lean * t * t)
			radii.append(lerpf(0.16, 0.09, t) * (1.0 + hgt * 0.1))
		(a.rock as MeshKit).loft(path, radii, 8, _lit(Color(0.78, 0.74, 0.66), foot + Vector3(0, 0.5, 0)), Callable(), Callable(), true, false)
		var top: Vector3 = path[4]
		var cap := hgt * 0.42 + 0.25
		(a.glow as MeshKit).add_primitive(MeshKit.sphere(cap, 14, 7), Transform3D(Basis().scaled(Vector3(1.0, 0.42, 1.0)), top + Vector3(0, 0.05, 0)), col, 0.08, 0.04)
		(a.glow as MeshKit).add_primitive(MeshKit.cylinder(cap * 0.95, 0.12, cap * 0.12, 14), Transform3D(Basis(), top - Vector3(0, 0.02, 0)), col.darkened(0.45), 0.0, 0.0)
		a.n.rock += 1
		a.n.glow += 1
		_solid(self, foot + Vector3(0, hgt * 0.5, 0), Vector3(0.36, hgt, 0.36))
		if k_lights < MAX_GLOW_LIGHTS and rng.randf() < 0.4:
			_glow_light(top + Vector3(0, -0.4, 0), col, 0.7, 6.0)
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
		if k_lights < MAX_GLOW_LIGHTS and rng.randf() < 0.3:
			_glow_light(at + nrm * 0.4, col, 0.5, 4.5)
	# Glow-worms: silk threads hanging from the ceiling, a glowing bead at the end of each.
	for w: Array in plan.worms:
		var top: Vector3 = w[0]
		var col: Color = GLOW_COLOURS[int(w[1])]
		var a := _area(top)
		# Threads no longer than a third of the head-room here, each starting in the air just under the ceiling (one
		# that would start in the rock, where the ceiling dips, is left out).
		var under: Variant = Caves.floor_at(Game.world_gen.caves, top - Vector3(0, 0.3, 0))
		var headroom: float = top.y - (under as Vector3).y if under != null else 1.5
		for k in rng.randi_range(8, 16):
			var p := top + Vector3(rng.randf_range(-0.9, 0.9), -0.06, rng.randf_range(-0.9, 0.9))
			var len := minf(rng.randf_range(0.25, 1.3), headroom * 0.33)
			if Caves.void_distance(Game.world_gen.caves, p) > -0.01 or Caves.void_distance(Game.world_gen.caves, p - Vector3(0, len + 0.3, 0)) > -0.01:
				continue
			# Each thread runs up into the rock, so none hangs from the air under the ceiling.
			var anchor := p + Vector3(0, maxf(_root_lift(p), 0.1), 0)
			(a.rock as MeshKit).loft([anchor, p - Vector3(0, len, 0)], [0.006, 0.004], 3, _lit(Color(0.75, 0.78, 0.72), p), Callable(), Callable(), false, false)
			(a.glow as MeshKit).add_primitive(MeshKit.sphere(rng.randf_range(0.014, 0.024), 5, 3), Transform3D(Basis(), p - Vector3(0, len, 0)), col, 0.0, 0.0)
		a.n.rock += 1
		a.n.glow += 1
		if k_lights < MAX_GLOW_LIGHTS and rng.randf() < 0.35:
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
		_water_mat = ShaderMaterial.new()   # an inky mirror: see cave_water.gdshader
		_water_mat.shader = preload("res://shaders/cave_water.gdshader")
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
