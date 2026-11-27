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
const GRASS_ATTEMPTS := 600
const FLOWER_ATTEMPTS := 55
const GROUND_PLANT_ATTEMPTS := 80   ## each land's own ground plants (see FloraLibrary.BIOME_GROUND)
const FERN_ATTEMPTS := 90
const PALM_ATTEMPTS := 10
const TALL_GRASS_ATTEMPTS := 160
const CLOVER_ATTEMPTS := 120
const UNDERGROWTH_ATTEMPTS := 40   ## the jungle's extra layer of plants
const VINE_ATTEMPTS := 110        ## vines on rock faces


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
	var covered: Array = job.get("covered", [])
	var resources := _place_resources(coord, origin, gen, flora, job.removed, covered, tier == 0)
	result.resources = resources
	result.multimesh = _resource_buffers(resources, origin, tier)
	if tier == 0 and job.grass_density > 0.0:
		var drape := [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		_place_ground_cover(coord, origin, gen, flora, job.grass_density, result.multimesh, drape, covered)
		if not (drape[0] as PackedVector3Array).is_empty():
			result.drape = drape
		if not covered.is_empty():
			_clear_covered(result.multimesh, origin, covered)
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

## The ground as it is drawn close up, at (x, z) in the world: the full-detail terrain mesh is flat between its
## samples (FINE metres apart), so on a rounded rise it sits a little under the true height and in a dip a little
## over it. Things that lie on the ground are fitted to this, not to the smooth height, so they meet the ground
## the player sees. (Cut the same way as _terrain_arrays: each cell fans from its first corner off the chunk's border.)
## `cache`: fine sample (world fine grid coordinates) -> height, kept by the caller across many calls.
static func surface_height(gen: WorldGen, x: float, z: float, cache := {}) -> float:
	var gx := floori(x / FINE)
	var gz := floori(z / FINE)
	var fx := x / FINE - gx
	var fz := z / FINE - gz
	var cx := posmod(gx, FINE_SEGS)   # the cell within its chunk
	var cz := posmod(gz, FINE_SEGS)
	var h0 := _grid_h(gen, cache, gx, gz)
	var h1 := _grid_h(gen, cache, gx + 1, gz)
	var h2 := _grid_h(gen, cache, gx + 1, gz + 1)
	var h3 := _grid_h(gen, cache, gx, gz + 1)
	# The fan's first corner: the first of the four (in outline order) not on the chunk's border.
	var last := FINE_SEGS - 1
	var first := 0
	if cx == 0 or cz == 0:
		first = 1 if cz != 0 and cx != last else (2 if cx != last and cz != last else 3)
	if first % 2 == 0:   # cut corner 0 to corner 2
		if fx >= fz:
			return h0 + (h1 - h0) * fx + (h2 - h1) * fz
		return h0 + (h2 - h3) * fx + (h3 - h0) * fz
	if fx + fz >= 1.0:   # cut corner 1 to corner 3
		return h3 + (h2 - h3) * fx + (h2 - h1) * (fz - 1.0)
	return h0 + (h1 - h0) * fx + (h3 - h0) * fz


## The lowest drawn ground under an oval footprint (radii rx, rz, turned by yaw) round (x, z): where a stone or
## boulder set on a slope has to reach down to, so its downhill side doesn't float.
static func lowest_ground(gen: WorldGen, x: float, z: float, rx: float, rz: float, yaw := 0.0, cache := {}) -> float:
	var lo := surface_height(gen, x, z, cache)
	var c := cos(yaw)
	var s := sin(yaw)
	for k in 8:
		var a := TAU * k / 8.0
		var ox := cos(a) * rx
		var oz := sin(a) * rz
		lo = minf(lo, surface_height(gen, x + ox * c - oz * s, z + ox * s + oz * c, cache))
	return lo


static func _grid_h(gen: WorldGen, cache: Dictionary, gx: int, gz: int) -> float:
	var key := Vector2i(gx, gz)
	var h: Variant = cache.get(key)
	if h == null:
		h = gen.get_height(gx * FINE, gz * FINE)
		cache[key] = h
	return h


## Things that lie on the ground rather than stand on it: tipped to fit the slope under them and bedded in this
## deep (metres) at their highest point, so no edge floats and none digs in more than it must.
const LIE_SINK := {"log": 0.04, "mossy_log": 0.07, "branch": 0.02, "pebbles": 0.02, "scree": 0.03, "mud": 0.004}
## Tipped to the slope too, but left as deep as they were placed (rocks sit well into the ground), only lowered
## where an edge would float.
const TIP := ["rock", "ore_t2", "ore_t3", "boulder", "ice_rock", "cache", "tumbleweed"]
## How far (metres) a standing thing may be lowered to bring its downhill foot down to the ground, by category.
const STAND_DROP := {"tree": 1.2, "bush": 0.45, "clutter": 0.5, "rock": 0.6, "fern": 0.2, "flower": 0.15}
const MAX_TIP := 0.55   ## radians: no steeper than this, whatever the ground does


## Fit a thing to the ground drawn under it, by the points round its foot (FloraLibrary.feet): one that lies is tipped
## to the slope across its own length and width and lowered (or raised) until its highest foot point is just bedded
## in; one that stands stays upright and is lowered until no foot point floats (within its category's limit).
static func _settle(gen: WorldGen, ground: Dictionary, kind: String, feet: PackedVector3Array, xf: Transform3D) -> Transform3D:
	if feet.is_empty():
		return xf
	var lie := LIE_SINK.has(kind)
	if lie or kind in TIP:
		# The slope along the thing's own two axes, measured across its foot's full reach each way.
		var ax := Vector3(xf.basis.x.x, 0, xf.basis.x.z).normalized()
		var az := Vector3(-ax.z, 0, ax.x)
		var ex := 0.3
		var ez := 0.3
		for v in feet:
			var d := xf.basis * v
			ex = maxf(ex, absf(d.dot(ax)))
			ez = maxf(ez, absf(d.dot(az)))
		var o := xf.origin
		var sx := (surface_height(gen, o.x + ax.x * ex, o.z + ax.z * ex, ground) - surface_height(gen, o.x - ax.x * ex, o.z - ax.z * ex, ground)) / (2.0 * ex)
		var sz := (surface_height(gen, o.x + az.x * ez, o.z + az.z * ez, ground) - surface_height(gen, o.x - az.x * ez, o.z - az.z * ez, ground)) / (2.0 * ez)
		var n := (Vector3.UP - ax * sx - az * sz).normalized()
		var tip := Vector3.UP.angle_to(n)
		if tip > MAX_TIP:
			n = Vector3.UP.slerp(n, MAX_TIP / tip)
		if tip > 0.001:
			xf.basis = Basis(Quaternion(Vector3.UP, n)) * xf.basis
	var top := -INF
	for v in feet:
		var w := xf * v
		top = maxf(top, w.y - surface_height(gen, w.x, w.z, ground))
	if lie:
		xf.origin.y -= top + float(LIE_SINK[kind])
	else:
		var cat := FloraLibrary.category_of(kind)
		# (A tree a little deeper: its foot is a few points round a wide spread of roots and buttresses.)
		xf.origin.y -= clampf(top + (0.08 if cat == "tree" else 0.03), 0.0, float(STAND_DROP.get(cat, 0.3)))
	return xf


## The lowest ground under a trunk of radius r at (x, z), so its downhill side sits on the ground instead of floating.
static func _ground_under(gen: WorldGen, x: float, z: float, r: float) -> float:
	var lowest := gen.get_height(x, z)
	for k in 6:
		var a := TAU * k / 6.0
		lowest = minf(lowest, gen.get_height(x + cos(a) * r, z + sin(a) * r))
	return lowest


## A biome for one plant from the blend of biomes at its spot. Faint traces of biomes far off (a jungle's last 0.1%
## out in the tundra) are left out, so borders still mix but no kapok turns up alone on the snow.
const MIN_BIOME_SHARE := 0.05

static func _pick_biome(weights: Dictionary, roll: float) -> int:
	var total := 0.0
	var best := Biome.MEADOW
	var best_w := -1.0
	for b: int in weights:
		var w: float = weights[b]
		if w >= MIN_BIOME_SHARE:
			total += w
		if w > best_w:
			best_w = w
			best = b
	if total <= 0.0:
		return best
	var acc := 0.0
	roll *= total
	for b: int in weights:
		var w: float = weights[b]
		if w < MIN_BIOME_SHARE:
			continue
		acc += w
		if roll <= acc:
			return b
	return best


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


## Whether a spot is under a floor at ground level (covered: the floors' footprints, world xz).
static func _is_covered(covered: Array, x: float, z: float) -> bool:
	for r: Rect2 in covered:
		if r.has_point(Vector2(x, z)):
			return true
	return false


## Take out the grass, flowers and the like that came up under a floor (they'd poke through it).
static func _clear_covered(buffers: Dictionary, origin: Vector3, covered: Array) -> void:
	for key: String in buffers:
		var b: PackedFloat32Array = buffers[key]
		var kept := PackedFloat32Array()
		for i in range(0, b.size(), 16):
			if not _is_covered(covered, origin.x + b[i + 3], origin.z + b[i + 11]):
				kept.append_array(b.slice(i, i + 16))
		if kept.size() != b.size():
			buffers[key] = kept


static func _place_resources(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, removed: Dictionary, covered := [], contour_vines := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, coord.x, coord.y, "res"])
	var size := Game.CHUNK_SIZE
	var counter := [0]
	var ground := {}   # drawn-ground samples, shared by everything fitted to the ground in this chunk

	var add := func(kind: String, variant: int, pos: Vector3, yaw: float, scl: Vector3) -> void:
		var id := "%d_%d_%d" % [coord.x, coord.y, counter[0]]
		counter[0] += 1
		# Nothing grows over a cave opening or inside a tunnel (the draws above still happen).
		if removed.has(id) or Caves.void_distance(gen.caves, pos) < 1.0 or (not covered.is_empty() and _is_covered(covered, pos.x, pos.z)):
			return
		var basis := Basis(Vector3.UP, yaw).scaled(scl)
		if FloraLibrary.KINDS[kind].category == "tree":
			# Every tree its own: stretched a little differently each way and leaning a touch (from its id, so it's
			# the same on every machine and draws nothing from the placement's random numbers).
			var h := hash(id)
			var sx := 0.86 + float(h % 29) / 100.0
			var sy := 0.88 + float((h >> 5) % 31) / 100.0
			var sz := 0.86 + float((h >> 10) % 29) / 100.0
			var lean_axis := Vector3(cos(float((h >> 15) % 628) / 100.0), 0, sin(float((h >> 15) % 628) / 100.0))
			var lean := deg_to_rad(float((h >> 20) % 50) / 10.0)   # up to 5 degrees
			basis = Basis(lean_axis, lean) * Basis(Vector3.UP, yaw) * Basis.from_scale(scl * Vector3(sx, sy, sz))
		var key: String = flora.variants[kind][variant % flora.variants[kind].size()]
		out.append({
			"id": id,
			"kind": kind,
			"key": key,
			"transform": _settle(gen, ground, kind, flora.feet.get(key, PackedVector3Array()), Transform3D(basis, pos)),
			"hp": FloraLibrary.KINDS[kind].hp,
		})

	# The landmarks reaching into this chunk: no trees on their ground (a giant tree's clearing, a meadow, the stones).
	var marks: Array = []
	for lm: Dictionary in gen.landmarks:
		var lp: Vector3 = lm.pos
		if lp.x > origin.x - 30.0 and lp.x < origin.x + size + 30.0 and lp.z > origin.z - 30.0 and lp.z < origin.z + size + 30.0:
			marks.append(lm)

	# Every attempt draws the same number of random values, whether it succeeds or not,
	# so placement is identical on every machine. (Ids are numbered in a fixed order too.)
	for i in TREE_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		if h < 2.6 or gen.near_river(a.x, a.z) or h > 60.0 or (not marks.is_empty() and not Landmarks.at(marks, a.x, a.z).is_empty()):
			counter[0] += 1
			continue
		var nrm := gen.get_normal(a.x, a.z)
		var biome := _pick_biome(gen.biome_weights_at(a.x, a.z, h), a.r_biome)
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
		if h < 1.4 or gen.near_river(a.x, a.z) or h > 6.0 or gen.get_normal(a.x, a.z).y < 0.85 or gen.get_climate(a.x, a.z, h).x < 0.45 or a.r_place > 0.35:
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
		if h < 0.8 or gen.near_river(a.x, a.z) or gen.get_normal(a.x, a.z).y < 0.55 or a.r_place >= chance:
			counter[0] += 1
			continue
		# Ore tiers by altitude: the world's first metal in the hills, the second in the
		# mountains, crystals near the peaks.
		var kind := "rock"
		var roll: float = a.r_kind
		# Crystals on the upper mountains, likelier the higher up (only a handful of spots reach the very peaks, so
		# they once came out at about one an island). They take the top of the roll, so the second metal, which
		# takes the bottom, is as common as it was.
		if h > 44.0 and roll > 1.0 - (0.08 + (h - 44.0) / 100.0):
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
		if h < 2.2 or gen.near_river(a.x, a.z) or h > 66.0 or gen.get_normal(a.x, a.z).y < 0.8:
			counter[0] += 1
			continue
		var biome := _pick_biome(gen.biome_weights_at(a.x, a.z, h), a.r_biome)
		if h > 50.0:
			biome = Biome.HIGHLANDS   # up on the mountains: heather and mountain juniper
		if a.r_place >= FloraLibrary.BIOME_BUSH_DENSITY[biome]:
			counter[0] += 1
			continue
		add.call(_pick_weighted(FloraLibrary.BIOME_BUSHES[biome], a.r_kind), a.variant, Vector3(a.x, h - 0.1, a.z), a.yaw, Vector3.ONE * a.scl)

	for i in CLUTTER_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		var nrm := gen.get_normal(a.x, a.z)
		if h < 2.0 or gen.near_river(a.x, a.z) or nrm.y < 0.82:
			counter[0] += 1
			continue
		var biome := _pick_biome(gen.biome_weights_at(a.x, a.z, h), a.r_biome)
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
		# (Logs, branches and the like are then tipped to the slope under them: see _settle.)
		add.call(kind, a.variant, Vector3(a.x, h - sink, a.z), a.yaw, scl)

	# The jungle floor: a thick layer of broadleaves, heliconias, fern palms and bamboo between the trees.
	for i in UNDERGROWTH_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		if h < 2.2 or gen.near_river(a.x, a.z) or h > 48.0 or gen.get_normal(a.x, a.z).y < 0.8:
			counter[0] += 1
			continue
		var jungle: float = gen.biome_weights_at(a.x, a.z, h).get(Biome.JUNGLE, 0.0)
		if a.r_place >= jungle * 0.85:
			counter[0] += 1
			continue
		add.call(_pick_weighted(FloraLibrary.JUNGLE_UNDERGROWTH, a.r_kind), a.variant, Vector3(a.x, h - 0.08, a.z), a.yaw, Vector3.ONE * a.scl)

	# Vines down the rock faces where the land is green: each hangs from the top of the face to its foot.
	for i in VINE_ATTEMPTS:
		var a := _attempt(rng, origin, size)
		var h := gen.get_height(a.x, a.z)
		var nrm := gen.get_normal(a.x, a.z)
		if h < 2.5 or nrm.y > 0.75 or nrm.y < 0.1 or gen.near_river(a.x, a.z, 2.0):
			counter[0] += 1
			continue
		var w := gen.biome_weights_at(a.x, a.z, h)
		var green := 0.0
		for b: int in FloraLibrary.VINE_BIOMES:
			green += float(w.get(b, 0.0)) * float(FloraLibrary.VINE_BIOMES[b])
		var face: Variant = _rock_face(gen, a.x, a.z) if a.r_place < green * 0.9 else null
		if face == null:
			counter[0] += 1
			continue
		var before := out.size()
		add.call("cliff_vine", a.variant, face.top, 0.0, Vector3.ONE)
		if out.size() > before:
			out[-1].transform = Transform3D(face.basis, face.top)
			# Close by, each vine is built to the rock it hangs on: its strands follow the face's bulges and hollows.
			if contour_vines:
				out[-1].vine_arrays = _contour_vine(gen, flora, out[-1].transform, hash(out[-1].id))
	_place_cave_resources(coord, origin, gen, flora, removed, out)
	# A landmark's giant tree: an old tree of the country round it, two and a half times the size, in its clearing.
	for lm: Dictionary in marks:
		var lp: Vector3 = lm.pos
		if lm.kind != "giant_tree" or lp.x < origin.x or lp.x >= origin.x + size or lp.z < origin.z or lp.z >= origin.z + size:
			continue
		var gb := gen.get_biome(lp.x, lp.z)
		var gk: String = {Biome.JUNGLE: "jungle_tree", Biome.DRYLANDS: "acacia", Biome.AUTUMN: "autumn_oak"}.get(gb, "oak")
		var gs := 2.8 + float(absi(int(lm.seed)) % 5) * 0.12
		add.call(gk, int(lm.seed), Vector3(lp.x, _ground_under(gen, lp.x, lp.z, 1.6) - 0.3, lp.z), float(lm.yaw), Vector3.ONE * gs)

	return out


## Ore, crystals and stalagmites the cave plan put in this chunk (ids "x_z_c<n>" / "x_z_s<n>", from their place in the
## plan, so every machine agrees). They're in the dark, so they carry how much sky they see (drawn darker).
static func _place_cave_resources(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, removed: Dictionary, out: Array[Dictionary]) -> void:
	var plan: Dictionary = gen.caves
	if plan.is_empty() or not plan.has("ores"):
		return
	var size := float(Game.CHUNK_SIZE)
	var inside := func(p: Vector3) -> bool:
		return p.x >= origin.x and p.x < origin.x + size and p.z >= origin.z and p.z < origin.z + size
	var lists := [["c", plan.ores], ["s", plan.stalagmites]]
	for l: Array in lists:
		var tag: String = l[0]
		var items: Array = l[1]
		for i in items.size():
			var it: Array = items[i]
			var p: Vector3 = it[0]
			if not inside.call(p):
				continue
			var id := "%d_%d_%s%d" % [coord.x, coord.y, tag, i]
			if removed.has(id):
				continue
			var kind: String = it[1] if tag == "c" else "stalagmite"
			var vs: Array = flora.variants[kind]
			var h := hash([id, "look"])
			var yaw := float(h % 628) / 100.0
			var scl := (0.55 + float(h % 23) / 100.0) if tag == "c" else float(it[1])
			var sink := 0.12 if tag == "c" else 0.08
			out.append({
				"id": id,
				"kind": kind,
				"key": vs[h % vs.size()],
				"transform": Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), p - Vector3(0, sink, 0)),
				"hp": FloraLibrary.KINDS[kind].hp,
				"sky": Caves.sky_seen(plan, p + Vector3(0, 0.5, 0)),
			})


## One placement attempt's random values (always the same count, for determinism).
## The rock face through (x, z): its top (walking uphill until the slope eases) and its foot (downhill likewise),
## and the basis that lays a vine curtain on it from top to foot (model -Y down the face, +Z out of it, stretched to
## the face's length). Null where it's too short or too long to be worth a vine.
static func _rock_face(gen: WorldGen, x: float, z: float) -> Variant:
	var walk := func(sign: float) -> Vector3:
		var p := Vector2(x, z)
		for k in 26:
			var n := gen.get_normal(p.x, p.y)
			if n.y > 0.8:
				break
			var down := Vector2(n.x, n.z).normalized()   # the normal leans downhill
			p += down * sign * 0.7
		return Vector3(p.x, gen.get_height(p.x, p.y), p.y)
	var top: Vector3 = walk.call(-1.0)
	var foot: Vector3 = walk.call(1.0)
	var along := top - foot
	if along.y < 1.5:
		return null
	if along.length() > 9.0:   # a long face: the vine hangs down its top part
		foot = top - along.normalized() * rng_len(x, z)
		along = top - foot
	# A vine is straight, a face is curved: where the face bows in under the straight line the vine would stand off
	# it, so the whole vine is sunk by the widest gap (its ends tuck into the ground a little). Too curved: no vine.
	var gap := 0.0
	for k in range(1, 10):
		var c := foot.lerp(top, k / 10.0)
		gap = maxf(gap, c.y - gen.get_height(c.x, c.z))
	if gap > 1.0:
		return null
	top.y -= gap
	foot.y -= gap
	var up_face := along.normalized()
	var flat := Vector2(along.x, along.z).normalized()
	var across := Vector3(-flat.y, 0, flat.x)
	var out_face := across.cross(up_face).normalized()
	var length := along.length() + 0.3
	return {"top": top + out_face * 0.04, "basis": Basis(across * 1.0, up_face * (length / FloraLibrary.VINE_LENGTH), out_face)}


## A cliff vine built to the face it hangs on (worker thread): strands hang from the top of the face and run down
## over it, each point pressed onto the rock along the face's outward direction, with leaves along them. Built in the
## world and handed back in the vine's own frame (its resource transform), so it's drawn, shaken and hidden like any
## other plant. Returns [verts, normals, colors].
static func _contour_vine(gen: WorldGen, flora: FloraLibrary, xf: Transform3D, seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var kit := MeshKit.new(seed_v)
	var pal: WorldPalette = flora._pal
	var stem := pal.vine.darkened(0.2 + rng.randf_range(-0.05, 0.05))
	var leaf := pal.vine.lightened(rng.randf_range(-0.06, 0.06))
	var across := xf.basis.x.normalized()
	var down := -xf.basis.y.normalized()
	var out := xf.basis.z.normalized()
	var length := xf.basis.y.length() * FloraLibrary.VINE_LENGTH
	# A point on the rock: from p, along the outward direction, to where it meets the ground (a few halvings).
	var on_rock := func(p: Vector3) -> Vector3:
		var lo := -1.4
		var hi := 1.4
		for k in 8:
			var mid := (lo + hi) * 0.5
			var q := p + out * mid
			if q.y > gen.get_height(q.x, q.z):
				hi = mid   # in the air: come in
			else:
				lo = mid
		return p + out * hi
	for i in rng.randi_range(9, 13):
		var x := rng.randf_range(-1.2, 1.2)
		var l := length * rng.randf_range(0.55, 1.0)
		var path: Array = []
		var radii: Array = []
		var rows := clampi(int(l / 0.35), 6, 18)
		var lean := rng.randf_range(-0.12, 0.12)
		for k in rows + 1:
			var t := float(k) / rows
			var p: Vector3 = xf.origin + across * (x + sin(t * 5.0 + x * 3.0) * 0.1 + lean * t) + down * l * t
			var g: Vector3 = on_rock.call(p)
			path.append(g + out * (0.05 + 0.025 * sin(t * 7.0 + x)))
			radii.append(lerpf(0.024, 0.011, t))
		kit.loft(path, radii, 4, stem, Callable(), Callable(), false, true)
		# Leaves along it, lying against the rock: thickest near the top, where the vine has grown longest.
		for k in rng.randi_range(18, 28):
			var t := pow(rng.randf(), 1.4)
			var seg := mini(int(t * rows), rows - 1)
			var c: Vector3 = (path[seg] as Vector3).lerp(path[seg + 1], t * rows - seg)
			var d: Vector3 = ((path[seg + 1] as Vector3) - (path[seg] as Vector3)).normalized()
			var side := d.cross(out).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
			var sz := rng.randf_range(0.09, 0.16) * lerpf(1.15, 0.8, t)
			var tip := c + (side * 0.8 + d * 0.5).normalized() * sz * 1.6 + out * 0.03
			var w := d * sz * 0.55
			var col := leaf.lightened(rng.randf_range(-0.12, 0.1))
			var lift := out * 0.025
			kit.add_tri(c, c + w + side * sz * 0.6 + lift, tip, col.darkened(0.15), col, col.lightened(0.1))
			kit.add_tri(c, tip, c - w + side * sz * 0.6 + lift, col.darkened(0.15), col.lightened(0.1), col)
	# Into the vine's own frame (normals by the transpose of its basis: the inverse-transpose of the frame's inverse).
	var inv := xf.affine_inverse()
	var bt := xf.basis.transposed()
	var verts := kit.verts
	var normals := kit.normals
	for k in verts.size():
		verts[k] = inv * verts[k]
		normals[k] = (bt * normals[k]).normalized()
	return [verts, normals, kit.colors]


## A vine's length on a long face (from its place, so it's the same on every machine).
static func rng_len(x: float, z: float) -> float:
	return 5.0 + float(absi(hash(Vector2i(int(x * 10.0), int(z * 10.0)))) % 400) / 100.0


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
		if r.has("vine_arrays"):
			continue   # drawn from its own mesh (see TerrainChunk)
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
		var warm := 0.0
		if cat == "tree":   # a touch warmer or cooler, tree to tree
			warm = fposmod(t.origin.x * 1.91 + t.origin.z * 2.73, 0.1) - 0.05
		# Remember which instance this is, so it can be shaken / hidden when gathered.
		r.mm_key = key
		r.mm_index = buffers[key].size() / 16 if buffers.has(key) else 0
		_append_instance(buffers, key, t, Color(shade * (1.0 + warm), shade, shade * (1.0 - warm), float(r.get("sky", 1.0))))
	return buffers


## Lay a patch (mud) over the ground: each of its points is set on the drawn ground under it, at its own height
## above its base, so the patch follows every rise and dip instead of lying flat across them. Upward faces take
## the ground's slope for their light. Appended (in chunk space) to drape = [verts, normals, colors].
static func _drape(gen: WorldGen, ground: Dictionary, src: Array, xf: Transform3D, origin: Vector3, drape: Array) -> void:
	var sv: PackedVector3Array = src[0]
	var sn: PackedVector3Array = src[1]
	var sc: PackedColorArray = src[2]
	var lift := xf.basis.y.length()
	var up := gen.get_normal(origin.x + xf.origin.x, origin.z + xf.origin.z)
	var tilt := Basis(Quaternion(Vector3.UP, up))
	var dv: PackedVector3Array = drape[0]
	var dn: PackedVector3Array = drape[1]
	var dc: PackedColorArray = drape[2]
	var base := dv.size()
	dv.resize(base + sv.size())
	dn.resize(base + sv.size())
	dc.resize(base + sv.size())
	for i in sv.size():
		var p := xf * sv[i]
		p.y = surface_height(gen, origin.x + p.x, origin.z + p.z, ground) - origin.y + 0.004 + sv[i].y * lift
		dv[base + i] = p
		dn[base + i] = (tilt * (xf.basis * sn[i])).normalized()
		dc[base + i] = sc[i]
	drape[0] = dv
	drape[1] = dn
	drape[2] = dc


static func _append_instance(buffers: Dictionary, key: String, t: Transform3D, col: Color) -> void:
	if not buffers.has(key):
		buffers[key] = PackedFloat32Array()
	var b := t.basis
	var o := t.origin
	buffers[key].append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, col.r, col.g, col.b, col.a])


# --- Grass, flowers and ferns (near the player only) ---------------------------------

static func _place_ground_cover(coord: Vector2i, origin: Vector3, gen: WorldGen, flora: FloraLibrary, density: float, buffers: Dictionary, drape := [], covered := []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, coord.x, coord.y, "grass"])
	var size := Game.CHUNK_SIZE
	var grass_keys: Array = flora.variants["grass"]
	var flower_keys: Array = flora.variants["flower"]
	var fern_keys: Array = flora.variants["fern"]
	var tall_keys: Array = flora.variants["tall_grass"]
	var clover_keys: Array = flora.variants["clover"]
	var ground := {}
	# Fit a patch or plant (placed in chunk space) to the drawn ground (see _settle, which works in the world).
	var fit := func(kind: String, key: String, t: Transform3D) -> Transform3D:
		t.origin += origin
		t = _settle(gen, ground, kind, flora.feet.get(key, PackedVector3Array()), t)
		t.origin -= origin
		return t
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
			if h < 2.0 or gen.near_river(wx, wz) or h > 55.0:
				continue
			var nrm := gen.get_normal(wx, wz)
			if nrm.y < 0.82:
				continue
			var w := gen.biome_weights_at(wx, wz, h)
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
		if h < 1.9 or gen.near_river(wx, wz) or h > 62.0:
			continue
		var nrm := gen.get_normal(wx, wz)
		if nrm.y < 0.8:
			continue
		var w := gen.biome_weights_at(wx, wz, h)
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
		if h < 2.0 or gen.near_river(wx, wz) or h > 55.0 or gen.get_normal(wx, wz).y < 0.8:
			continue
		var w := gen.biome_weights_at(wx, wz, h)
		var amount := 0.0
		for b: int in w:
			amount += w[b] * FloraLibrary.BIOME_FERNS[b]
		# Ferns like shade: more of them where trees clump.
		if keep > amount * gen.get_forest_clump(wx, wz):
			continue
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz))
		var shade := rng.randf_range(0.85, 1.1)
		var fk: String = fern_keys[variant % fern_keys.size()]
		_append_instance(buffers, fk, fit.call("fern", fk, t), Color(shade, shade, shade))

	var meadow_here := false   # a flower glade reaches this chunk: more tries at flowers, most of them in the glade
	for lm: Dictionary in gen.landmarks:
		var lp: Vector3 = lm.pos
		if lm.kind == "meadow" and lp.x > origin.x - 25.0 and lp.x < origin.x + size + 25.0 and lp.z > origin.z - 25.0 and lp.z < origin.z + size + 25.0:
			meadow_here = true
	# Jungle floor: patches of wet mud in the shade, and jungle flowers among the ferns.
	var mud_keys: Array = flora.variants.get("mud", [])
	for i in int(24 * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if mud_keys.is_empty() or h < 2.2 or h > 40.0 or gen.near_river(wx, wz):
			continue
		var w := gen.biome_weights_at(wx, wz, h)
		if keep > float(w.get(Biome.JUNGLE, 0.0)) * 0.6 + float(w.get(Biome.MARSH, 0.0)) * 0.4 or gen.get_normal(wx, wz).y < 0.9:
			continue
		var mk: String = mud_keys[variant % mud_keys.size()]
		var mxf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), Vector3(lx, h, lz))
		if not covered.is_empty() and _is_covered(covered, wx, wz):
			continue   # under a floor
		if flora.drape_src.has(mk) and not drape.is_empty():
			_drape(gen, ground, flora.drape_src[mk], mxf, origin, drape)
		else:
			_append_instance(buffers, mk, fit.call("mud", mk, mxf), Color(1, 1, 1))
	for i in int(FLOWER_ATTEMPTS * density * (4.0 if meadow_here else 1.0)):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 2.2 or gen.near_river(wx, wz) or h > 58.0:
			continue
		var w := gen.biome_weights_at(wx, wz, h)
		# Flowers in meadows and autumn groves, plus alpine flowers on high gentle slopes, and thick in a glade.
		var alpine := smoothstep(40.0, 55.0, h) * 0.5
		var glade := 1.5 if meadow_here and not Landmarks.at(gen.landmarks, wx, wz).is_empty() else 0.0
		if keep > w[Biome.MEADOW] * 0.7 + w[Biome.AUTUMN] * 0.2 + w[Biome.JUNGLE] * 0.35 + alpine + glade or gen.get_normal(wx, wz).y < 0.85:
			continue
		# Flowers of one color grow in patches.
		var patch := int(floor(wx / 9.0) * 7.0 + floor(wz / 9.0) * 13.0)
		var pick := patch + (1 if variant % 4 == 0 else 0)
		var key: String = flower_keys[absi(pick) % flower_keys.size()]
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(lx, h, lz))
		_append_instance(buffers, key, fit.call("flower", key, t), Color(1, 1, 1))
	# Each land's own ground plants: lupins and daisies in the meadows, sedges in the marsh, lichens on the tundra...
	# They grow in patches of one kind (with a few strays), like the flowers.
	for i in int(GROUND_PLANT_ATTEMPTS * density):
		var lx := rng.randf() * size
		var lz := rng.randf() * size
		var keep := rng.randf()
		var variant := rng.randi()
		var yaw := rng.randf() * TAU
		var roll := rng.randf()
		var scl := rng.randf_range(0.8, 1.25)
		var wx := origin.x + lx
		var wz := origin.z + lz
		var h := gen.get_height(wx, wz)
		if h < 0.8 or h > 90.0 or gen.near_river(wx, wz):
			continue
		var biome := _pick_biome(gen.biome_weights_at(wx, wz, h), roll)
		# The shore, the high slopes and the peaks have their own (see WorldGen.get_biome's height bands).
		if h < 2.3:
			biome = Biome.BEACH
		elif h > 76.0:
			biome = Biome.SNOW
		elif h > 52.0:
			biome = Biome.HIGHLANDS
		var table: Array = FloraLibrary.BIOME_GROUND.get(biome, [])
		if table.is_empty() or keep > float(FloraLibrary.BIOME_GROUND_DENSITY.get(biome, 0.0)) or gen.get_normal(wx, wz).y < 0.8:
			continue
		var patch := absi(int(floor(wx / 7.0) * 31.0 + floor(wz / 7.0) * 17.0))
		var pick := fposmod(patch * 0.618034, 1.0) if variant % 5 != 0 else fposmod(variant * 0.37, 1.0)
		var kind := _pick_weighted(table, pick)
		var gkeys: Array = flora.variants.get(kind, [])
		if gkeys.is_empty():
			continue
		var gkey: String = gkeys[(patch + variant % 2) % gkeys.size()]
		var gt := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scl), Vector3(lx, h, lz))
		_append_instance(buffers, gkey, fit.call("flower", gkey, gt), Color(1, 1, 1))
