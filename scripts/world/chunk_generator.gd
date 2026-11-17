class_name ChunkGenerator
extends RefCounted
## Builds all the *data* for one chunk (mesh arrays, collision heights, plant placements).
## Runs on a worker thread, so it must not touch the scene tree. The main thread turns
## the result into nodes (see TerrainChunk.apply).

const Biome := WorldGen.Biome

## Detail tiers: 0 = right around the player, 2 = far away.
const TIER_RES := [32, 16, 8]          ## terrain quads per side
const TIER_SKIRT := [3.0, 6.0, 10.0]   ## depth of the edge "skirt" that hides gaps between tiers

const TREE_ATTEMPTS := 110
const ROCK_ATTEMPTS := 10
const BUSH_ATTEMPTS := 26
const GRASS_ATTEMPTS := 650
const FLOWER_ATTEMPTS := 70


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

	var n := res + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for z in n:
		for x in n:
			heights[z * n + x] = gen.get_height(origin.x + x * step, origin.z + z * step)

	var result := {
		"mesh": _terrain_arrays(heights, n, res, step, origin, gen, TIER_SKIRT[tier]),
		"collision": _collision_data(heights, step) if tier <= 1 else PackedFloat32Array(),
		"collision_width": n,
		"step": step,
	}
	var resources := _place_resources(coord, origin, gen, flora, job.removed)
	result.resources = resources
	result.multimesh = _resource_buffers(resources, origin, tier)
	if tier == 0 and job.grass_density > 0.0:
		_place_ground_cover(coord, origin, gen, flora, job.grass_density, result.multimesh)
	job.result = result


# --- Terrain ------------------------------------------------------------------

static func _terrain_arrays(heights: PackedFloat32Array, n: int, res: int, step: float, origin: Vector3, gen: WorldGen, skirt: float) -> Array:
	# Smooth, shared vertices (painterly look). Normals come from a grid padded by one
	# sample on every side, so lighting matches seamlessly across chunk borders.
	var pn := n + 2
	var pad := PackedFloat32Array()
	pad.resize(pn * pn)
	for z in pn:
		for x in pn:
			var gx := x - 1
			var gz := z - 1
			if gx >= 0 and gx < n and gz >= 0 and gz < n:
				pad[z * pn + x] = heights[gz * n + gx]
			else:
				pad[z * pn + x] = gen.get_height(origin.x + gx * step, origin.z + gz * step)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for z in n:
		for x in n:
			var i := z * n + x
			var hl := pad[(z + 1) * pn + x]
			var hr := pad[(z + 1) * pn + x + 2]
			var hd := pad[z * pn + x + 1]
			var hu := pad[(z + 2) * pn + x + 1]
			var nrm := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var h := heights[i]
			verts[i] = Vector3(x * step, h, z * step)
			normals[i] = nrm
			colors[i] = gen.get_terrain_color(h, nrm.y, origin.x + x * step, origin.z + z * step).srgb_to_linear()
	for z in res:
		for x in res:
			var i00 := z * n + x
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			if (x + z) % 2 == 0:
				indices.append_array([i00, i10, i01, i10, i11, i01])
			else:
				indices.append_array([i00, i10, i11, i00, i11, i01])

	# Skirts: short walls hanging down from each edge. Neighbouring chunks at different
	# detail levels don't line up exactly; the skirts hide the tiny gaps.
	var edges := []
	for k in res:
		edges.append([Vector2i(k, 0), Vector2i(k + 1, 0)])
		edges.append([Vector2i(res, k), Vector2i(res, k + 1)])
		edges.append([Vector2i(k + 1, res), Vector2i(k, res)])
		edges.append([Vector2i(0, k + 1), Vector2i(0, k)])
	for e: Array in edges:
		var a: int = e[0].y * n + e[0].x
		var b: int = e[1].y * n + e[1].x
		var base := verts.size()
		verts.append(verts[a] - Vector3(0, skirt, 0))
		verts.append(verts[b] - Vector3(0, skirt, 0))
		normals.append(normals[a])
		normals.append(normals[b])
		colors.append(colors[a])
		colors.append(colors[b])
		indices.append_array([a, b, base, b, base + 1, base])
	return [verts, normals, colors, indices]


static func _collision_data(heights: PackedFloat32Array, step: float) -> PackedFloat32Array:
	# HeightMapShape3D samples are 1 unit apart; the shape gets scaled by `step`,
	# so heights are divided by `step` to compensate.
	var data := PackedFloat32Array()
	data.resize(heights.size())
	for k in heights.size():
		data[k] = heights[k] / step
	return data


# --- Trees, rocks, bushes ---------------------------------------------------

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

	var add := func(kind: String, variant: int, pos: Vector3, yaw: float, scl: float) -> void:
		var id := "%d_%d_%d" % [coord.x, coord.y, counter[0]]
		counter[0] += 1
		if removed.has(id):
			return
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl)
		out.append({
			"id": id,
			"kind": kind,
			"key": flora.variants[kind][variant % flora.variants[kind].size()],
			"transform": Transform3D(basis, pos),
			"hp": FloraLibrary.KINDS[kind].hp,
		})

	# Every attempt draws the same number of random values, whether it succeeds or not,
	# so placement is identical on every machine.
	for i in TREE_ATTEMPTS:
		var wx := origin.x + rng.randf() * size
		var wz := origin.z + rng.randf() * size
		var r_biome := rng.randf()
		var r_place := rng.randf()
		var r_kind := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(0.8, 1.3)
		var h := gen.get_height(wx, wz)
		if h < 2.6 or h > 58.0:
			continue
		var nrm := gen.get_normal(wx, wz)
		if nrm.y < 0.82:
			continue
		var biome := _pick_biome(gen.get_biome_weights(gen.get_climate(wx, wz, h)), r_biome)
		var density: float = FloraLibrary.BIOME_TREE_DENSITY[biome] * gen.get_forest_clump(wx, wz) * 1.6
		if h > 44.0:
			density *= 0.35   # sparse up in the highlands
		if r_place < density:
			var kind := "pine" if h > 44.0 else _pick_weighted(FloraLibrary.BIOME_TREES[biome], r_kind)
			add.call(kind, variant, Vector3(wx, h - 0.15, wz), yaw, scl)

	for i in ROCK_ATTEMPTS:
		var wx := origin.x + rng.randf() * size
		var wz := origin.z + rng.randf() * size
		var r_place := rng.randf()
		var r_ore := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(0.5, 1.6)
		var h := gen.get_height(wx, wz)
		if h < 0.8 or gen.get_normal(wx, wz).y < 0.55:
			continue
		# More rocks (and more ore) up high.
		var chance := 0.35 + clampf(h / 60.0, 0.0, 0.5)
		if r_place < chance:
			var ore_chance := 0.06 + clampf((h - 30.0) / 80.0, 0.0, 0.25)
			add.call("ore" if r_ore < ore_chance else "rock", variant, Vector3(wx, h - 0.2 * scl, wz), yaw, scl)

	for i in BUSH_ATTEMPTS:
		var wx := origin.x + rng.randf() * size
		var wz := origin.z + rng.randf() * size
		var r_biome := rng.randf()
		var r_place := rng.randf()
		var r_berry := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var scl := rng.randf_range(0.7, 1.25)
		var h := gen.get_height(wx, wz)
		if h < 2.2 or h > 46.0 or gen.get_normal(wx, wz).y < 0.8:
			continue
		var biome := _pick_biome(gen.get_biome_weights(gen.get_climate(wx, wz, h)), r_biome)
		if r_place < FloraLibrary.BIOME_BUSH_DENSITY[biome]:
			add.call("berry" if r_berry < 0.25 else "bush", variant, Vector3(wx, h - 0.1, wz), yaw, scl)
	return out


## MultiMesh buffers: 12 floats of transform + 4 floats of color per instance.
static func _resource_buffers(resources: Array[Dictionary], origin: Vector3, tier: int) -> Dictionary:
	var buffers := {}
	for r in resources:
		var cat := FloraLibrary.category_of(r.kind)
		if tier == 2 and cat != "tree":
			continue
		var t: Transform3D = r.transform
		t.origin -= origin
		var shade := 0.92 + fposmod(t.origin.x * 3.17 + t.origin.z * 1.31, 0.16)
		# Remember which instance this is, so it can be shaken / hidden when gathered.
		r.mm_index = buffers[r.key].size() / 16 if buffers.has(r.key) else 0
		_append_instance(buffers, r.key, t, Color(shade, shade, shade))
	return buffers


static func _append_instance(buffers: Dictionary, key: String, t: Transform3D, col: Color) -> void:
	if not buffers.has(key):
		buffers[key] = PackedFloat32Array()
	var b := t.basis
	var o := t.origin
	buffers[key].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, col.a])


# --- Grass and flowers (near the player only) ---------------------------------

static func _place_ground_cover(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, density: float, buffers: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, coord.x, coord.y, "grass"])
	var size := Game.CHUNK_SIZE
	var grass_keys: Array = flora.variants["grass"]
	var flower_keys: Array = flora.variants["flower"]

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
		if h < 1.9 or h > 48.0:
			continue
		var nrm := gen.get_normal(wx, wz)
		if nrm.y < 0.8 or keep > 0.85:
			continue
		var col := gen.get_terrain_color(h, nrm.y, wx, wz).srgb_to_linear()
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz))
		_append_instance(buffers, grass_keys[variant % grass_keys.size()], t, col)

	for i in int(FLOWER_ATTEMPTS * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 2.2 or h > 40.0:
			continue
		var w := gen.get_biome_weights(gen.get_climate(wx, wz, h))
		if keep > w[Biome.MEADOW] * 0.7 + w[Biome.AUTUMN] * 0.2 or gen.get_normal(wx, wz).y < 0.85:
			continue
		# Flowers of one color grow in patches.
		var patch := int(floor(wx / 9.0) * 7.0 + floor(wz / 9.0) * 13.0)
		var pick := patch + (1 if variant % 4 == 0 else 0)
		var key: String = flower_keys[absi(pick) % flower_keys.size()]
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, h, lz))
		_append_instance(buffers, key, t, Color(1, 1, 1))
