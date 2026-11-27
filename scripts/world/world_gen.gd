class_name WorldGen
extends RefCounted
## Pure math that describes the island: height, biomes, colors.
## No nodes and no hidden randomness, so it gives identical results on every machine
## and is safe to call from worker threads.

enum Biome { MEADOW, FOREST, AUTUMN, DRYLANDS, BEACH, HIGHLANDS, SNOW, TAIGA, MARSH, DESERT, JUNGLE, TUNDRA, BADLANDS, FUNGAL }
const BIOME_NAMES := ["Meadow", "Forest", "Autumn Grove", "Savanna", "Beach", "Highlands", "Snowfields", "Taiga", "Marsh", "Desert",
	"Jungle", "Tundra", "Badlands", "Fungal Grove"]
## Some biomes claim less of their climate space (the fungal grove is a rare find).
const BIOME_RARITY := {Biome.FUNGAL: 0.12, Biome.JUNGLE: 0.7}
## Biomes where nights bite harder (and snowfields/highlands by altitude).
const COLD_BIOMES := [Biome.TUNDRA, Biome.TAIGA, Biome.SNOW, Biome.HIGHLANDS]

## Climate biomes: their "centers" in (temperature, moisture) space. Ground colors and plant
## choice blend between neighbours smoothly.
const CLIMATE_BIOMES := {
	Biome.MEADOW: Vector2(0.55, 0.4),
	Biome.FOREST: Vector2(0.48, 0.72),
	Biome.AUTUMN: Vector2(0.28, 0.5),
	Biome.DRYLANDS: Vector2(0.8, 0.25),
	Biome.TAIGA: Vector2(0.08, 0.62),
	Biome.MARSH: Vector2(0.62, 0.96),
	Biome.DESERT: Vector2(0.98, 0.02),
	Biome.JUNGLE: Vector2(0.9, 0.8),
	Biome.TUNDRA: Vector2(0.0, 0.18),
	Biome.BADLANDS: Vector2(0.66, 0.06),
	Biome.FUNGAL: Vector2(0.3, 0.94),
}

var palette: WorldPalette
var mountain_scale: float
var hill_scale: float
var lake_amount: float                 ## 0..1: how lake-rich this world is

var _continent := FastNoiseLite.new()  # big rolling lowlands
var _ranges := FastNoiseLite.new()     # where mountain ranges run
var _ridge := FastNoiseLite.new()      # warped, weighted ridges (range crests + spurs)
var _detail := FastNoiseLite.new()     # small bumps + coastline wobble
var _coast := FastNoiseLite.new()      # bays and headlands along the coast
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _forest := FastNoiseLite.new()     # clumping of trees inside a biome
var _lake := FastNoiseLite.new()       # lake basins in the lowlands
var _hills := FastNoiseLite.new()      # rolling hills between the plains and the ranges
var _hilly := FastNoiseLite.new()      # where the land is hilly and where it lies in broad plains
var _plateau := FastNoiseLite.new()    # raised tablelands with escarpment edges
var _warp := FastNoiseLite.new()       # bends the island's outline into bays and peninsulas
## The island's outline: a few overlapping lobes (Vector3: centre x, centre z, radius, all as shares of the map's
## half width), merged softly into one coast with peninsulas and bays; and some small islets offshore.
var _lobes: Array[Vector3] = []
var _islets: Array[Vector3] = []
var plateau_amount: float              ## 0..1: how much tableland this world has


## This world's size (metres a side), kept here: the map is painted on a worker thread, which mustn't reach into
## the Game autoload (it may be gone by then, quitting).
var size := 2048.0


func _init(seed_value: int, pal: WorldPalette) -> void:
	palette = pal
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Each world has its own "personality": flatter or more mountainous.
	mountain_scale = rng.randf_range(38.0, 72.0)
	hill_scale = rng.randf_range(16.0, 30.0)
	# A bigger island has bigger regions, not more of them: the region-sized noise (the land's broad shape, where
	# the ranges run, the coast, climate, hilly-or-plain, tablelands, the outline's bends) stretches with the map.
	# Lakes, hills, ridges and surface detail keep their size, so there are more of those. (A 2 km world, from an
	# older save, comes out exactly as before.)
	size = Game.WORLD_SIZE
	var big := 2048.0 / size
	FUNGAL_N = int(size / FUNGAL_CELL)

	_continent.seed = seed_value
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = rng.randf_range(0.0014, 0.0022) * big
	_continent.fractal_octaves = 4

	_ranges.seed = seed_value + 6
	_ranges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ranges.frequency = rng.randf_range(0.0011, 0.0016) * big
	_ranges.fractal_octaves = 2

	# Ridged multifractal with domain warping: long, bending crests with branching spurs
	# and broad shoulders, instead of isolated spikes.
	_ridge.seed = seed_value + 1
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = rng.randf_range(0.0026, 0.0036)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_ridge.fractal_weighted_strength = 0.7
	_ridge.domain_warp_enabled = true
	_ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_ridge.domain_warp_amplitude = 55.0
	_ridge.domain_warp_frequency = 0.004
	_ridge.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	_ridge.domain_warp_fractal_octaves = 2

	_coast.seed = seed_value + 10
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast.frequency = rng.randf_range(0.0012, 0.0018) * big
	_coast.fractal_octaves = 3
	_detail.seed = seed_value + 2
	_detail.frequency = 0.02
	_detail.fractal_octaves = 2

	_temperature.seed = seed_value + 3
	_temperature.frequency = 0.0015 * big
	_temperature.fractal_octaves = 2

	_moisture.seed = seed_value + 4
	_moisture.frequency = 0.002 * big
	_moisture.fractal_octaves = 3

	_forest.seed = seed_value + 5
	_forest.frequency = 0.012
	_forest.fractal_octaves = 2

	_lake.seed = seed_value + 9
	_lake.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lake.frequency = rng.randf_range(0.0035, 0.005)
	_lake.fractal_octaves = 2
	lake_amount = rng.randf_range(0.0, 1.0)

	_hills.seed = seed_value + 11
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = rng.randf_range(0.005, 0.0075)
	_hills.fractal_octaves = 3
	_hills.fractal_gain = 0.45
	_hilly.seed = seed_value + 12
	_hilly.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hilly.frequency = 0.0018 * big
	_plateau.seed = seed_value + 13
	_plateau.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_plateau.frequency = rng.randf_range(0.0022, 0.0032) * big
	_plateau.fractal_octaves = 2
	plateau_amount = rng.randf_range(0.2, 1.0)
	_warp.seed = seed_value + 14
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 0.0009 * big
	_warp.fractal_octaves = 2
	# The outline: one lobe in the middle (so there's always land there), and three to five more around it of
	# different sizes, reaching out as peninsulas or swelling the island to one side.
	_lobes.append(Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08), rng.randf_range(0.58, 0.68)))
	var ang := rng.randf() * TAU
	for k in rng.randi_range(3, 6):
		ang += rng.randf_range(0.8, 1.8)
		var reach := rng.randf_range(0.36, 0.6)
		var r := rng.randf_range(0.2, 0.38)
		r = minf(r, 0.9 - reach)   # never out to the map's edge
		_lobes.append(Vector3(cos(ang) * reach, sin(ang) * reach, r))
	# Islets offshore: small, apart from the main island.
	for k in rng.randi_range(2, 5):
		var a := rng.randf() * TAU
		_islets.append(Vector3(cos(a), sin(a), 0.0) * rng.randf_range(0.7, 0.82) + Vector3(0, 0, rng.randf_range(0.035, 0.07)))

	if not pal.exotic:
		_pick_fungal_home()
		_fungal_limit = true
	rivers = Rivers.plan(self)   # before the caves, so they run under the river beds
	caves = Caves.plan(self)   # planned from the base ground, so it's the same on every machine
	landmarks = Landmarks.plan(self)
	ruins = Ruins.plan(self)   # (after the landmarks, to keep clear of them)


## Terrain height in meters at world position (x, z). Sea level is 0.
var caves: Dictionary = {}   ## the cave plan (see Caves.plan)
var rivers: Dictionary = {}  ## the river plan (see Rivers.plan)
var landmarks: Array = []    ## the island's places worth finding (see Landmarks.plan)
var ruins: Array = []        ## old temples and watchtowers (see Ruins.plan)


## The height of the water's surface at (x, z): a river's or pond's where there is one, otherwise the sea's
## (which also fills the lakes). Ground below it is under water.
func water_level(x: float, z: float) -> float:
	return maxf(Game.SEA_LEVEL, Rivers.surface_at(rivers, x, z))


## Whether (x, z) is in a river or pond, or within `margin` metres of one (for keeping trees and rocks out).
func near_river(x: float, z: float, margin := 0.6) -> bool:
	return Rivers.near(rivers, x, z, margin)

## Metres added to the procedural ground by digging / piling / flattening. Keys are whole-metre
## cells (Vector2i). Copy-on-write: edits are replaced by a new dictionary, so worker threads that
## hold the old one keep reading a consistent copy.
var edits: Dictionary = {}


## Ground height including player edits. Everything that places things uses this.
func get_height(x: float, z: float) -> float:
	var base := get_base_height(x, z)
	if edits.is_empty():
		return base
	return base + edit_at(x, z)


## Bilinear blend of the edit grid, so sculpted ground has smooth slopes between metres.
func edit_at(x: float, z: float) -> float:
	var x0 := floori(x)
	var z0 := floori(z)
	var fx := x - x0
	var fz := z - z0
	var a: float = edits.get(Vector2i(x0, z0), 0.0)
	var b: float = edits.get(Vector2i(x0 + 1, z0), 0.0)
	var c: float = edits.get(Vector2i(x0, z0 + 1), 0.0)
	var d: float = edits.get(Vector2i(x0 + 1, z0 + 1), 0.0)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## How far out a point is, as a share of the way from the island's middle to the map edge, with the coastline's
## bays and headlands: x is the broad outline, y adds the rocky edge's finer wobble.
func _coast_at(x: float, z: float) -> Vector2:
	var half := size * 0.5
	# Bent a little first, so the lobes' round edges become irregular bays and headlands.
	var dx := (x - half) / half + _warp.get_noise_2d(x, z) * 0.15
	var dz := (z - half) / half + _warp.get_noise_2d(z + 917.0, x) * 0.15
	# How far out a point is: 0.75 on a lobe's edge (where the beaches start to fall to the sea), merged softly
	# between lobes so they join with smooth necks and bays, never past the map's edge.
	var k := 0.0
	for lb: Vector3 in _lobes:
		k += exp(-11.0 * Vector2(dx - lb.x, dz - lb.y).length() / lb.z)
	var shape := -0.75 * log(maxf(k, 1e-12)) / 11.0
	shape = maxf(shape, sqrt(dx * dx + dz * dz) * 0.97)
	for il: Vector3 in _islets:
		shape = minf(shape, 0.75 * Vector2(dx - il.x, dz - il.y).length() / il.z + 0.12)
	var coast_raw := shape + _coast.get_noise_2d(x, z) * 0.12 + _detail.get_noise_2d(x * 0.12, z * 0.12) * 0.045
	return Vector2(coast_raw, coast_raw + _detail.get_noise_2d(x * 0.12, z * 0.12) * 0.09)


## The island's outline: 1 inland, falling to 0 out at sea. Lakes lie inland, where it is 1; the sea's beaches are
## where it falls away.
func island_mask(x: float, z: float) -> float:
	return 1.0 - smoothstep(0.55, 0.92, _coast_at(x, z).y)


## The procedural ground, before any digging or building.
func get_base_height(x: float, z: float) -> float:
	var cv := _coast_at(x, z)
	var coast_raw := cv.x
	var coast := cv.y
	var mask := 1.0 - smoothstep(0.55, 0.92, coast)   # island mask (see island_mask)

	var c := _continent.get_noise_2d(x, z) * 0.5 + 0.5          # 0..1
	var lowlands := c * hill_scale
	# Mountains only where a range runs, rising through foothills to the crest.
	var range_t := smoothstep(0.42, 0.72, _ranges.get_noise_2d(x, z) * 0.5 + 0.5) * smoothstep(0.35, 0.8, mask)
	var ridge := clampf(_ridge.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var crest := pow(ridge, 2.4)                                   # sharp crest, wide shoulders
	var mountains := (crest * 0.85 + ridge * 0.15) * range_t * mountain_scale
	var foothills := range_t * hill_scale * 0.6 * ridge
	# Soften the very tops so peaks are rounded-sharp rather than needles.
	var peak_cap := mountain_scale * 0.9
	if mountains > peak_cap * 0.7:
		var over := mountains - peak_cap * 0.7
		mountains = peak_cap * 0.7 + over / (1.0 + over / (peak_cap * 0.5))
	var bumps := _detail.get_noise_2d(x, z) * 0.9
	# Rolling hills: some country is broad open plain, some rolls in hills (and nothing pokes up out of the beaches).
	var hilly := smoothstep(-0.25, 0.35, _hilly.get_noise_2d(x, z)) * smoothstep(0.4, 0.75, mask)
	var hn := _hills.get_noise_2d(x, z)
	var hills := (hn * 0.5 + 0.5) * hilly * hill_scale * 0.55 * (1.0 - range_t * 0.5)

	var land := 3.0 + lowlands + hills + foothills + mountains + bumps
	# Tablelands: here and there the ground stands up as a broad flat-topped plateau, its edge an escarpment (steep
	# where the noise climbs quickly, a walkable ramp where it climbs slowly), kept off the ranges and the coast.
	var pl := _plateau.get_noise_2d(x, z)
	var pl_th := lerpf(0.42, 0.22, plateau_amount)
	var plateau := smoothstep(pl_th, pl_th + 0.05, pl) * (1.0 - range_t) * smoothstep(0.55, 0.85, mask)
	if plateau > 0.0:
		land += plateau * (7.0 + 5.0 * smoothstep(pl_th + 0.05, pl_th + 0.3, pl))
	# Beaches: the lowest ground by the sea is a gentle, nearly flat strip.
	var beach := (1.0 - smoothstep(1.2, 5.0, land)) * smoothstep(0.5, 0.8, coast)
	land = lerpf(land, 1.4 + bumps * 0.18, beach * 0.7)
	# Marshes sit low and flat.
	var wet := smoothstep(0.82, 0.95, get_moisture(x, z))
	land = lerpf(land, 2.4 + bumps * 0.5, wet * (1.0 - range_t) * 0.85)
	# Badlands: stepped mesas with flat tops and steep striped cliffs.
	var bad := badlands_amount(x, z) * (1.0 - range_t * 0.6) * smoothstep(0.35, 0.55, mask)
	if bad > 0.01 and land > 3.0:
		# Two tiers of flat-topped mesas with steep sides, then gentle ledges on the slopes.
		var n := _forest.get_noise_2d(x * 0.7 + 311.0, z * 0.7) + _detail.get_noise_2d(x * 0.5, z * 0.5) * 0.06
		var raised := land + 11.0 * smoothstep(-0.14, 0.0, n) + 8.0 * smoothstep(0.16, 0.32, n)
		var step := 3.0
		var f := raised / step
		var stepped := (floorf(f) + smoothstep(0.15, 1.0, f - floorf(f))) * step
		land = lerpf(land, lerpf(raised, stepped, 0.6), smoothstep(0.0, 0.5, bad))
	land = _carve_water(x, z, land, range_t, mask, bumps)
	# The seabed: a shallow shelf that drops away gradually offshore.
	var offshore := smoothstep(0.5, 0.95, coast_raw)
	var seabed := lerpf(-2.5, -24.0, offshore) + bumps * 0.6 * offshore
	var ground := lerpf(seabed, land, mask)
	# The rivers last, so the coast's slope down to the seabed can't pull their banks under their water.
	return Rivers.carve(rivers, x, z, ground)


## How strongly the badlands climate holds here (ignores altitude so terraces stay put).
func badlands_amount(x: float, z: float) -> float:
	var c := Vector2(_warmth(x, z), get_moisture(x, z))
	return 1.0 - smoothstep(0.08, 0.2, c.distance_to(CLIMATE_BIOMES[Biome.BADLANDS]))


## Lakes: basins cut below sea level so the sea plane fills them.
## They only form in the lowlands; in hills and mountains they taper out (springs, gorges' ends).
func _carve_water(x: float, z: float, land: float, range_t: float, mask: float, bumps: float) -> float:
	# Fading out over a wide band of height, so a lake meeting a hill's foot doesn't cut a cliff into it.
	var lowland := (1.0 - range_t) * (1.0 - smoothstep(3.0, 16.0, land)) * smoothstep(0.25, 0.5, mask)
	if lowland <= 0.001:
		return land
	# Lakes
	var lk := _lake.get_noise_2d(x, z)
	var lake_th := lerpf(0.56, 0.4, lake_amount)
	# The higher the land around a lake, the further out its shore starts to slope down, so the shores stay gentle
	# enough to walk out up (a lake cut into a hillside would otherwise have a steep bank).
	var ramp := 0.06 + 0.016 * maxf(land - 2.0, 0.0)
	var lake_t := smoothstep(lake_th - ramp, lake_th + 0.08, lk) * lowland
	if lake_t > 0.0:
		var depth := -1.5 - smoothstep(lake_th, lake_th + 0.25, lk) * 3.5
		land = lerpf(land, minf(land, depth + bumps * 0.4), lake_t)
	return land


## Approximate surface normal, from neighbouring heights.
func get_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := get_height(x - e, z)
	var hr := get_height(x + e, z)
	var hd := get_height(x, z - e)
	var hu := get_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## How wet a place is: the noise's patches, wetter along the coasts (sea air) and drier deep inland.
func get_moisture(x: float, z: float) -> float:
	var c := _coast_at(x, z).x
	var coastal := smoothstep(0.45, 0.72, c) * 0.12 - (1.0 - smoothstep(0.15, 0.45, c)) * 0.06
	return clampf(_moisture.get_noise_2d(x, z) * 0.75 + 0.5 + coastal, 0.0, 1.0)


## How warm a place is before altitude: the north of the island cooler and the south warmer, with the noise's
## patches on top (so the biomes fall in a believable order across the island, not scattered at random).
func _warmth(x: float, z: float) -> float:
	var south := z / size - 0.5   # -0.5 north .. 0.5 south
	return clampf(_temperature.get_noise_2d(x, z) * 0.62 + 0.5 + south * 0.55, 0.0, 1.0)


## Temperature and moisture (both 0..1). Higher ground is colder.
func get_climate(x: float, z: float, height: float) -> Vector2:
	var t := clampf(_warmth(x, z) - maxf(height - 20.0, 0.0) * 0.007, 0.0, 1.0)
	return Vector2(t, get_moisture(x, z))


## The weights at a place: the climate's, except that the fungal grove only grows in one region of the island (the
## patch of its climate found by _pick_fungal_home); elsewhere its climate goes to its neighbours. Exotic worlds
## keep every grove their climate makes.
func biome_weights_at(x: float, z: float, h: float) -> Dictionary:
	var w := get_biome_weights(get_climate(x, z, h))
	if _fungal_limit and w.has(Biome.FUNGAL):
		var keep := _fungal_keep(x, z)
		if keep < 1.0:
			w[Biome.FUNGAL] = float(w[Biome.FUNGAL]) * keep
			var total := 0.0
			for b: int in w:
				total += float(w[b])
			for b: int in w:
				w[b] = float(w[b]) / total
	return w


const FUNGAL_CELL := 32.0
var FUNGAL_N := 64                ## cells a side: the world's size / FUNGAL_CELL (set in _init)
var fungal_home := Vector2(-1e9, -1e9)   ## the middle of the island's one fungal grove (none if it has none)
var _fungal_cells := PackedFloat32Array()   ## 1 in the grove's cells (its one connected patch), else 0
var _fungal_limit := false


## How much of the fungal grove's claim holds here (0 outside its region, 1 inside; soft at the edge).
func _fungal_keep(x: float, z: float) -> float:
	if _fungal_cells.is_empty():
		return 0.0
	var fx := clampf(x / FUNGAL_CELL - 0.5, 0.0, FUNGAL_N - 1.001)
	var fz := clampf(z / FUNGAL_CELL - 0.5, 0.0, FUNGAL_N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_fungal_cells[j * FUNGAL_N + i], _fungal_cells[j * FUNGAL_N + i + 1], tx)
	var b := lerpf(_fungal_cells[(j + 1) * FUNGAL_N + i], _fungal_cells[(j + 1) * FUNGAL_N + i + 1], tx)
	return lerpf(a, b, tz)


## The one fungal grove: where its climate is strongest on the island's land, and the patch of cells around that
## where it's the leading biome, joined to it (flood fill), with a cell's margin round it.
func _pick_fungal_home() -> void:
	var lead := PackedByteArray()
	lead.resize(FUNGAL_N * FUNGAL_N)
	var best := 0.5
	var start := -1
	for j in FUNGAL_N:
		for i in FUNGAL_N:
			var x := (i + 0.5) * FUNGAL_CELL
			var z := (j + 0.5) * FUNGAL_CELL
			if island_mask(x, z) < 0.5:
				continue
			var h := get_base_height(x, z)
			if h < 2.0 or h > 55.0:
				continue
			var w := get_biome_weights(get_climate(x, z, h))
			var f: float = w.get(Biome.FUNGAL, 0.0)
			var top := true
			for b: int in w:
				if float(w[b]) > f:
					top = false
					break
			if top:
				lead[j * FUNGAL_N + i] = 1
				if f > best:
					best = f
					start = j * FUNGAL_N + i
	_fungal_cells.resize(FUNGAL_N * FUNGAL_N)
	_fungal_cells.fill(0.0)
	if start < 0:
		return
	fungal_home = Vector2((start % FUNGAL_N + 0.5) * FUNGAL_CELL, (start / FUNGAL_N + 0.5) * FUNGAL_CELL)
	var stack := [start]
	while not stack.is_empty():
		var c: int = stack.pop_back()
		if _fungal_cells[c] > 0.0 or lead[c] == 0:
			continue
		_fungal_cells[c] = 1.0
		var ci := c % FUNGAL_N
		var cj := c / FUNGAL_N
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := ci + d.x
			var nj := cj + d.y
			if ni >= 0 and nj >= 0 and ni < FUNGAL_N and nj < FUNGAL_N:
				stack.append(nj * FUNGAL_N + ni)
	# A margin of one cell, so its edge blends rather than being cut at the cell line.
	var grown := _fungal_cells.duplicate()
	for c in FUNGAL_N * FUNGAL_N:
		if _fungal_cells[c] > 0.0:
			var ci := c % FUNGAL_N
			var cj := c / FUNGAL_N
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := ci + d.x
				var nj := cj + d.y
				if ni >= 0 and nj >= 0 and ni < FUNGAL_N and nj < FUNGAL_N:
					grown[nj * FUNGAL_N + ni] = maxf(grown[nj * FUNGAL_N + ni], 1.0)
	_fungal_cells = grown


## Soft weights for the climate biomes (sum to 1). Used for color blending + plant choice.
func get_biome_weights(climate: Vector2) -> Dictionary:
	var weights := {}
	var total := 0.0
	for b: int in CLIMATE_BIOMES:
		var d: float = climate.distance_squared_to(CLIMATE_BIOMES[b])
		var w := 1.0 / pow(d + 0.002, 2.0) * float(BIOME_RARITY.get(b, 1.0))
		weights[b] = w
		total += w
	for b: int in weights:
		weights[b] /= total
	return weights


## The single dominant biome at a point (what the HUD shows).
func get_biome(x: float, z: float) -> int:
	var h := get_height(x, z)
	if h < 1.8:
		return Biome.BEACH
	if h > 78.0:
		return Biome.SNOW
	if h > 52.0:
		return Biome.HIGHLANDS
	var w := biome_weights_at(x, z, h)
	var best := Biome.MEADOW
	for b: int in w:
		if w[b] > w[best]:
			best = b
	return best


## What the ground is made of here (used for footstep sounds).
func get_surface(x: float, z: float) -> String:
	var h := get_height(x, z)
	if h < 1.9:
		return "sand"
	if h > 74.0:
		return "snow"
	if h > 52.0 or get_normal(x, z).y < 0.72:
		return "rock"
	var w := biome_weights_at(x, z, h)
	if w[Biome.DESERT] > 0.5:
		return "sand"
	if w[Biome.BADLANDS] > 0.5:
		return "rock"
	if w[Biome.TUNDRA] > 0.5 or (w[Biome.TAIGA] > 0.6 and h > 30.0):
		return "snow"
	return "grass"


## 0..1 clumping factor for trees.
func get_forest_clump(x: float, z: float) -> float:
	return clampf(_forest.get_noise_2d(x, z) * 0.8 + 0.55, 0.0, 1.0)


## Stylized ground colors (sRGB) from height, steepness and biome.
func get_terrain_color(height: float, normal_y: float, x: float, z: float, weights: Dictionary = {}) -> Color:
	var jitter := (fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5) * 0.02
	var pal := palette
	# The biome mix can be handed in (the cave ground works it out once per column of its grid: it's the dear part).
	var w := weights if not weights.is_empty() else biome_weights_at(x, z, height)
	var ground := Color(0, 0, 0)
	for b: int in w:
		ground += pal.ground[b] * w[b]
	# Darker patches under dense forest clumps.
	ground = ground.darkened(get_forest_clump(x, z) * 0.08 * (1.0 - w[Biome.DESERT]))

	var sand_t := 1.0 - smoothstep(1.0, 2.6, height)
	var steep_t := smoothstep(0.80, 0.66, normal_y)
	var high_t := smoothstep(46.0, 60.0, height)
	# Alpine meadows: grass on gentle high slopes, rock on steep ones.
	var rock_t := maxf(steep_t, high_t * smoothstep(0.95, 0.8, normal_y))
	var col := ground.lerp(pal.sand, sand_t)
	col = col.lerp(pal.rock.lerp(pal.rock_light, smoothstep(0.6, 0.9, normal_y)), rock_t)
	# Badlands: rust, ochre and cream bands by height, strongest on the cliffs.
	var bad_w: float = w[Biome.BADLANDS]
	if bad_w > 0.05:
		var band := sin(height * 1.25 + sin(x * 0.02) * 1.5) * 0.5 + 0.5
		var band2 := sin(height * 0.45 + 1.7) * 0.5 + 0.5
		var stripe := pal.badlands_red.lerp(pal.badlands_ochre, band).lerp(pal.badlands_cream, smoothstep(0.75, 0.95, band2))
		col = col.lerp(stripe, bad_w * lerpf(0.55, 1.0, steep_t))
	# Tundra: patchy old snow on the flats.
	var tun_w: float = w[Biome.TUNDRA]
	if tun_w > 0.05:
		var patch := smoothstep(0.1, 0.35, _forest.get_noise_2d(x * 2.0, z * 2.0))
		col = col.lerp(pal.snow, tun_w * patch * smoothstep(0.75, 0.9, normal_y) * 0.85)
	if height > 70.0 and normal_y > 0.6:
		col = col.lerp(pal.snow, smoothstep(70.0, 82.0, height) * smoothstep(0.6, 0.75, normal_y))
	if height < -0.5:
		col = pal.sand.darkened(0.25)   # seabed
	# River beds and the wet banks: sand and gravel.
	var wet := Rivers.wet(rivers, x, z)
	if wet > 0.0:
		col = col.lerp(pal.sand.lerp(pal.rock, 0.3).darkened(0.18), wet)
		# The wet line where the water laps the bank: darker, so the river's edge reads like a beach's.
		col = col.darkened(0.28 * Rivers.waterline(rivers, x, z))
	return Color(col.r + jitter, col.g + jitter, col.b + jitter)


## A nice dry, flat-ish spot near the middle of the island to start on.
func find_spawn_point() -> Vector3:
	var center := size * 0.5
	for ring in range(0, 80):
		var r := ring * 12.0
		var steps := maxi(1, ring * 6)
		for i in steps:
			var a := TAU * i / steps
			var x := center + cos(a) * r
			var z := center + sin(a) * r
			var h := get_height(x, z)
			if h > 3.0 and h < 22.0 and get_normal(x, z).y > 0.93 and not near_river(x, z, 4.0):
				return Vector3(x, h, z)
	return Vector3(center, get_height(center, center), center)
