class_name ChunkGenerator
extends RefCounted
## Builds all the *data* for one chunk (mesh arrays, collision heights, plant placements).
## Runs on a worker thread, so it must not touch the scene tree. The main thread turns
## the result into nodes (see TerrainChunk.apply).

const Biome := WorldGen.Biome

## Detail tiers: 0 = right around the player, 2 = far away.
const TIER_RES := [32, 16, 8]          ## terrain quads per side
## Every heightfield chunk's border is sampled at FINE metres between points, whatever its own detail level, so
## neighbours at different levels share their border points exactly (no cracks, no skirts). Interiors use TIER_RES.
const FINE := 2.0
const FINE_SEGS := 32                   ## fine segments per side of a chunk (64 m / FINE)
const VOXEL_STEP := [1.0, 2.0, 4.0]    ## grid size of the solid ground near caves, per tier

const TREE_ATTEMPTS := 110
const ROCK_ATTEMPTS := 10
const BUSH_ATTEMPTS := 26
const CLUTTER_ATTEMPTS := 22
const GRASS_ATTEMPTS := 650
const FLOWER_ATTEMPTS := 70
const FERN_ATTEMPTS := 90
const PALM_ATTEMPTS := 10
const TALL_GRASS_ATTEMPTS := 160
const CLOVER_ATTEMPTS := 120


## job: {coord, tier, gen, flora, removed (Dictionary of ids), grass_density}
static func generate(job: Dictionary) -> void:
	var coord: Vector2i = job.coord
	var tier: int = job.tier
	var gen: WorldGen = job.gen
	var flora: FloraLibrary = job.flora
	var size := Game.CHUNK_SIZE
	var origin := Vector3(coord.x * size, 0.0, coord.y * size)
	var res: int = TIER_RES[tier]
	var step := size / res

	# Chunks with caves under them get a solid 3D ground (see VoxelTerrain); the rest use the heightfield.
	var cave_segs: Array = Caves.segments_near(gen.caves, origin, size) if tier <= 1 else []
	var result: Dictionary
	if not cave_segs.is_empty():
		var vox := VoxelTerrain.build(gen, origin, size, VOXEL_STEP[tier], cave_segs)
		# The collider is built here too: on the main thread its triangle tree cost a 20-50 ms hitch per chunk.
		# (A shape not yet in the world is safe to build off the main thread: the physics server keeps its shapes
		# in a thread-safe table, and filling one touches nothing else.)
		var tri := ConcavePolygonShape3D.new()
		tri.backface_collision = true   # solid from both sides: a steep face can't be walked through from behind
		tri.set_faces(vox.faces)
		result = {
			"mesh": [vox.verts, vox.normals, vox.colors, vox.indices],
			"collision": PackedFloat32Array(),
			"collision_width": 0,
			"collision_faces": vox.faces,
			"collision_shape": tri,
			"step": step,
		}
	else:
		var cache := {}   # fine sample key -> height, shared by the mesh and the collision of this chunk
		result = {
			"mesh": _terrain_arrays(origin, gen, res, cache),
			"collision": _collision_data(origin, gen, cache) if tier <= 1 else PackedFloat32Array(),
			"collision_width": FINE_SEGS + 1,
			"step": FINE,
		}
	var resources := _place_resources(coord, origin, gen, flora, job.removed)
	result.resources = resources
	result.multimesh = _resource_buffers(resources, origin, tier)
	if tier == 0 and job.grass_density > 0.0:
		_place_ground_cover(coord, origin, gen, flora, job.grass_density, result.multimesh)
	job.result = result


# --- Terrain ------------------------------------------------------------------

## The height at a fine sample (key = fine grid coordinates), cached for the chunk being built.
static func _fine_h(cache: Dictionary, gen: WorldGen, origin: Vector3, key: Vector2i) -> float:
	if not cache.has(key):
		cache[key] = gen.get_height(origin.x + key.x * FINE, origin.z + key.y * FINE)
	return cache[key]


static func _on_border(p: Vector2i) -> bool:
	return p.x == 0 or p.y == 0 or p.x == FINE_SEGS or p.y == FINE_SEGS


static func _edge_on_border(a: Vector2i, b: Vector2i) -> bool:
	return (a.x == b.x and (a.x == 0 or a.x == FINE_SEGS)) or (a.y == b.y and (a.y == 0 or a.y == FINE_SEGS))


## The outline of one coarse cell: its four corners, with the fine samples inserted on any edge that lies on the
## chunk's border. Starts at a corner that is not on the border, so the cell fans out from there.
static func _cell_outline(corners: Array, k: int) -> Array:
	var start := 0
	for i in 4:
		if not _on_border(corners[i]):
			start = i
			break
	var out: Array = []
	for step in 4:
		var a: Vector2i = corners[(start + step) % 4]
		var b: Vector2i = corners[(start + step + 1) % 4]
		out.append(a)
		if _edge_on_border(a, b):
			var d: Vector2i = (b - a) / k
			for t in range(1, k):
				out.append(a + d * t)
	return out


static func _terrain_arrays(origin: Vector3, gen: WorldGen, res: int, cache: Dictionary) -> Array:
	var k := FINE_SEGS / res   # fine steps per coarse cell: 1 for the finest tier
	# Every vertex, by fine key, and every cell's outline (which names the vertices it needs).
	var keys: Array[Vector2i] = []
	var index := {}
	var outlines: Array = []
	for cz in res:
		for cx in res:
			var corners := [Vector2i(cx * k, cz * k), Vector2i((cx + 1) * k, cz * k),
				Vector2i((cx + 1) * k, (cz + 1) * k), Vector2i(cx * k, (cz + 1) * k)]
			var outline := _cell_outline(corners, k)
			for key: Vector2i in outline:
				if not index.has(key):
					index[key] = keys.size()
					keys.append(key)
			outlines.append(outline)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(keys.size())
	normals.resize(keys.size())
	colors.resize(keys.size())
	for i in keys.size():
		var key: Vector2i = keys[i]
		var h := _fine_h(cache, gen, origin, key)
		var hl := _fine_h(cache, gen, origin, key + Vector2i(-1, 0))
		var hr := _fine_h(cache, gen, origin, key + Vector2i(1, 0))
		var hd := _fine_h(cache, gen, origin, key + Vector2i(0, -1))
		var hu := _fine_h(cache, gen, origin, key + Vector2i(0, 1))
		var nrm := Vector3(hl - hr, 2.0 * FINE, hd - hu).normalized()
		var wx := origin.x + key.x * FINE
		var wz := origin.z + key.y * FINE
		verts[i] = Vector3(key.x * FINE, h, key.y * FINE)
		normals[i] = nrm
		colors[i] = gen.get_terrain_color(h, nrm.y, wx, wz).srgb_to_linear()
	var indices := PackedInt32Array()
	for outline: Array in outlines:
		for t in range(1, outline.size() - 1):
			indices.append_array([index[outline[0]], index[outline[t]], index[outline[t + 1]]])
	return [verts, normals, colors, indices]


## Heights on the fine grid for the collision shape (HeightMapShape3D samples are 1 unit apart, scaled by FINE,
## so heights are divided by FINE to compensate).
static func _collision_data(origin: Vector3, gen: WorldGen, cache: Dictionary) -> PackedFloat32Array:
	var n := FINE_SEGS + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for z in n:
		for x in n:
			data[z * n + x] = _fine_h(cache, gen, origin, Vector2i(x, z)) / FINE
	return data


# --- Trees, rocks, bushes ---------------------------------------------------

## The lowest ground under a trunk of radius r at (x, z), so its downhill side sits on the ground instead of floating.
static func _ground_under(gen: WorldGen, x: float, z: float, r: float) -> float:
	var lowest := gen.get_height(x, z)
	for k in 6:
		var a := TAU * k / 6.0
		lowest = minf(lowest, gen.get_height(x + cos(a) * r, z + sin(a) * r))
	return lowest


static func _pick_biome(weights: Dictionary, roll: float) -> int:
	var acc := 0.0
	for b: int in weights:
		acc += weights[b]
		if roll <= acc:
			return b
	return Biome.MEADOW


static func _pick_weighted(table: Array, roll: float) -> String:
	var total := 0.0
	for e: Array in table:
		total += e[1]
	var acc := 0.0
	for e: Array in table:
		acc += e[1] / total
		if roll <= acc:
			return e[0]
	return table[-1][0]


static func _place_resources(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, removed: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, coord.x, coord.y, "res"])
	var size := Game.CHUNK_SIZE
	var counter := [0]

	var add := func(kind: String, variant: int, pos: Vector3, yaw: float, scl: Vector3) -> void:
		var id := "%d_%d_%d" % [coord.x, coord.y, counter[0]]
		counter[0] += 1
		# Nothing grows over a cave opening or inside a tunnel (the draws above still happen).
		if removed.has(id) or Caves.void_distance(gen.caves, pos) < 1.0:
			return
		out.append({
			"id": id,
			"kind": kind,
			"key": flora.variants[kind][variant % flora.variants[kind].size()],
			"transform": Transform3D(Basis(Vector3.UP, yaw).scaled(scl), pos),
			"hp": FloraLibrary.KINDS[kind].hp,
		})

	# Every attempt draws the same number of random values, whether it succeeds or not,
	# so placement is identical on every machine. (Ids are numbered in a fixed order too.)
	for i in TREE_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		if h < 2.6 or h > 60.0:
			counter[0] += 1
			continue
		var nrm := gen.get_normal(a.x, a.z)
		var biome := _pick_biome(gen.get_biome_weights(gen.get_climate(a.x, a.z, h)), a.r_biome)
		var density: float = FloraLibrary.BIOME_TREE_DENSITY[biome] * gen.get_forest_clump(a.x, a.z) * 1.6
		if h > 46.0:
			density *= 0.35   # sparse up in the highlands
		if nrm.y < 0.82 or a.r_place >= density:
			counter[0] += 1
			continue
		# Conifers climb the high ground only in the cold and forested biomes.
		var high_conifer := h > 46.0 and biome in [Biome.TAIGA, Biome.TUNDRA, Biome.FOREST]
		var kind := "fir" if high_conifer else _pick_weighted(FloraLibrary.BIOME_TREES[biome], a.r_kind)
		add.call(kind, a.variant, Vector3(a.x, _ground_under(gen, a.x, a.z, 0.6 * a.scl) - 0.12, a.z), a.yaw, Vector3.ONE * a.scl)

	# Palms along warm coasts (just above the beach).
	for i in PALM_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		if h < 1.4 or h > 6.0 or gen.get_normal(a.x, a.z).y < 0.85 or gen.get_climate(a.x, a.z, h).x < 0.45 or a.r_place > 0.35:
			counter[0] += 1
			continue
		# Palms belong on beaches: warm shoreline on the island's edge (not a lake shore inland), with the sea within a
		# few metres.
		if gen.island_mask(a.x, a.z) > 0.98:
			counter[0] += 1
			continue
		var near_sea := false
		for k in 4:
			var ang := TAU * k / 4.0
			if gen.get_height(a.x + cos(ang) * 9.0, a.z + sin(ang) * 9.0) < 0.0:
				near_sea = true
				break
		if not near_sea:
			counter[0] += 1
			continue
		add.call("palm", a.variant, Vector3(a.x, _ground_under(gen, a.x, a.z, 0.4 * a.scl) - 0.1, a.z), a.yaw, Vector3.ONE * a.scl)

	for i in ROCK_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		var chance := 0.35 + clampf(h / 60.0, 0.0, 0.5)   # more rocks (and ore) up high
		if h < 0.8 or gen.get_normal(a.x, a.z).y < 0.55 or a.r_place >= chance:
			counter[0] += 1
			continue
		# Ore tiers by altitude: the world's first metal in the hills, the second in the
		# mountains, crystals near the peaks.
		var kind := "rock"
		var roll: float = a.r_kind
		if h > 58.0 and roll < 0.07:
			kind = "gem_t4"
		elif h > 34.0 and roll < 0.16:
			kind = "ore_t3"
		elif roll < 0.03 + clampf((h - 10.0) / 90.0, 0.0, 0.13):   # scarce on the low hills, commoner higher up
			kind = "ore_t2"
		var s := lerpf(0.5, 1.6, a.scl - 0.8)
		if kind != "rock":
			s = maxf(s, 0.9)
		add.call(kind, a.variant, Vector3(a.x, h - 0.2 * s, a.z), a.yaw, Vector3.ONE * s)

	for i in BUSH_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		if h < 2.2 or h > 50.0 or gen.get_normal(a.x, a.z).y < 0.8:
			counter[0] += 1
			continue
		var biome := _pick_biome(gen.get_biome_weights(gen.get_climate(a.x, a.z, h)), a.r_biome)
		if a.r_place >= FloraLibrary.BIOME_BUSH_DENSITY[biome]:
			counter[0] += 1
			continue
		add.call(_pick_weighted(FloraLibrary.BIOME_BUSHES[biome], a.r_kind), a.variant, Vector3(a.x, h - 0.1, a.z), a.yaw, Vector3.ONE * a.scl)

	for i in CLUTTER_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		var nrm := gen.get_normal(a.x, a.z)
		if h < 2.0 or nrm.y < 0.82:
			counter[0] += 1
			continue
		var biome := _pick_biome(gen.get_biome_weights(gen.get_climate(a.x, a.z, h)), a.r_biome)
		if h > 50.0:
			biome = Biome.DESERT if a.r_biome < 0.5 else Biome.DRYLANDS   # rocky highlands: stones & boulders
		if a.r_place >= FloraLibrary.BIOME_CLUTTER_DENSITY[biome]:
			counter[0] += 1
			continue
		var kind := _pick_weighted(FloraLibrary.BIOME_CLUTTER[biome], a.r_kind)
		var sink := 0.05
		var scl: Vector3 = Vector3.ONE * a.scl
		if kind == "boulder":
			scl = Vector3.ONE * (a.scl * 1.3)
			sink = 0.5
		var before := out.size()
		add.call(kind, a.variant, Vector3(a.x, h - sink, a.z), a.yaw, scl)
		# A log lies on the ground: tipped to the slope under it, so neither end digs in or floats.
		if kind == "log" and out.size() > before:
			var xf: Transform3D = out[-1].transform
			out[-1].transform = Transform3D(Basis(Quaternion(Vector3.UP, nrm)) * xf.basis, xf.origin)
	return out


## One placement attempt's random values (always the same count, for determinism).
static func _attempt(rng: RandomNumberGenerator, origin: Vector3, size: float) -> Dictionary:
	return {
		"x": origin.x + rng.randf() * size,
		"z": origin.z + rng.randf() * size,
		"r_biome": rng.randf(),
		"r_place": rng.randf(),
		"r_kind": rng.randf(),
		"variant": rng.randi(),
		"yaw": rng.randf() * TAU,
		"scl": rng.randf_range(0.8, 1.3),
	}


## MultiMesh buffers: 12 floats of transform + 4 floats of color per instance.
## Far chunks (tier 2) only draw trees, using their low-poly twins.
static func _resource_buffers(resources: Array[Dictionary], origin: Vector3, tier: int) -> Dictionary:
	var buffers := {}
	for r in resources:
		var cat := FloraLibrary.category_of(r.kind)
		if tier == 2 and cat != "tree":
			continue
		if tier == 1 and cat == "clutter" and r.kind != "boulder" and r.kind != "log":
			continue
		# Trees beyond the nearest ring draw their species' first low-poly twin: they are most of the triangles in
		# view, and at that range one shape per species is plenty (each extra shape is another draw call per chunk).
		var key: String = r.key
		if cat == "tree" and tier >= 1:
			key = "%s_0_lod" % r.kind
		var t: Transform3D = r.transform
		t.origin -= origin
		var shade := 0.92 + fposmod(t.origin.x * 3.17 + t.origin.z * 1.31, 0.16)
		# Remember which instance this is, so it can be shaken / hidden when gathered.
		r.mm_key = key
		r.mm_index = buffers[key].size() / 16 if buffers.has(key) else 0
		_append_instance(buffers, key, t, Color(shade, shade, shade))
	return buffers


static func _append_instance(buffers: Dictionary, key: String, t: Transform3D, col: Color) -> void:
	if not buffers.has(key):
		buffers[key] = PackedFloat32Array()
	var b := t.basis
	var o := t.origin
	buffers[key].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, col.a])


# --- Grass, flowers and ferns (near the player only) ---------------------------------

static func _place_ground_cover(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, density: float, buffers: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, coord.x, coord.y, "grass"])
	var size := Game.CHUNK_SIZE
	var grass_keys: Array = flora.variants["grass"]
	var flower_keys: Array = flora.variants["flower"]
	var fern_keys: Array = flora.variants["fern"]
	var tall_keys: Array = flora.variants["tall_grass"]
	var clover_keys: Array = flora.variants["clover"]
	# Tall grass and clover: shared pass, weighted by biome.
	for pass_def: Array in [[TALL_GRASS_ATTEMPTS, tall_keys, FloraLibrary.BIOME_TALL_GRASS, false], [CLOVER_ATTEMPTS, clover_keys, FloraLibrary.BIOME_CLOVER, true]]:
		for i in int(int(pass_def[0]) * density):
			var lx := rng.randf() * size
			var lz := rng.randf() * size
			var keep := rng.randf()
			var variant := rng.randi()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.8, 1.3)
			var wx := origin.x + lx
			var wz := origin.z + lz
			var h := gen.get_height(wx, wz)
			if Caves.void_distance(gen.caves, Vector3(wx, h, wz)) < 1.0:
				continue
			if h < 2.0 or h > 55.0:
				continue
			var nrm := gen.get_normal(wx, wz)
			if nrm.y < 0.82:
				continue
			var w := gen.get_biome_weights(gen.get_climate(wx, wz, h))
			var amount := 0.0
			var table: Dictionary = pass_def[2]
			for b: int in w:
				amount += w[b] * table[b]
			if keep > amount * 0.7:
				continue
			var col := Color(1, 1, 1)
			if pass_def[3]:   # clover takes the ground color
				col = gen.get_terrain_color(h, nrm.y, wx, wz).srgb_to_linear()
			var keys: Array = pass_def[1]
			_append_instance(buffers, keys[variant % keys.size()], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz)), col)

	for i in int(GRASS_ATTEMPTS * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(0.75, 1.35)
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 1.9 or h > 62.0:
			continue
		var nrm := gen.get_normal(wx, wz)
		if nrm.y < 0.8:
			continue
		var w := gen.get_biome_weights(gen.get_climate(wx, wz, h))
		var amount := 0.0
		for b: int in w:
			amount += w[b] * FloraLibrary.BIOME_GRASS[b]
		if keep > amount * 0.85:
			continue
		var col := gen.get_terrain_color(h, nrm.y, wx, wz).srgb_to_linear()
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz))
		_append_instance(buffers, grass_keys[variant % grass_keys.size()], t, col)

	for i in int(FERN_ATTEMPTS * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(0.7, 1.4)
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 2.0 or h > 55.0 or gen.get_normal(wx, wz).y < 0.8:
			continue
		var w := gen.get_biome_weights(gen.get_climate(wx, wz, h))
		var amount := 0.0
		for b: int in w:
			amount += w[b] * FloraLibrary.BIOME_FERNS[b]
		# Ferns like shade: more of them where trees clump.
		if keep > amount * gen.get_forest_clump(wx, wz):
			continue
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz))
		var shade := rng.randf_range(0.85, 1.1)
		_append_instance(buffers, fern_keys[variant % fern_keys.size()], t, Color(shade, shade, shade))

	for i in int(FLOWER_ATTEMPTS * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 2.2 or h > 58.0:
			continue
		var w := gen.get_biome_weights(gen.get_climate(wx, wz, h))
		# Flowers in meadows and autumn groves, plus alpine flowers on high gentle slopes.
		var alpine := smoothstep(40.0, 55.0, h) * 0.5
		if keep > w[Biome.MEADOW] * 0.7 + w[Biome.AUTUMN] * 0.2 + alpine or gen.get_normal(wx, wz).y < 0.85:
			continue
		# Flowers of one color grow in patches.
		var patch := int(floor(wx / 9.0) * 7.0 + floor(wz / 9.0) * 13.0)
		var pick := patch + (1 if variant % 4 == 0 else 0)
		var key: String = flower_keys[absi(pick) % flower_keys.size()]
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, h, lz))
		_append_instance(buffers, key, t, Color(1, 1, 1))
