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
var _river := FastNoiseLite.new()      # rivers follow this noise's zero line (meandering via warp)
var _river_gate := FastNoiseLite.new() # breaks the zero lines into separate rivers and creeks
var _lake := FastNoiseLite.new()       # lake basins in the lowlands


func _init(seed_value: int, pal: WorldPalette) -> void:
	palette = pal
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Each world has its own "personality": flatter or more mountainous.
	mountain_scale = rng.randf_range(38.0, 72.0)
	hill_scale = rng.randf_range(16.0, 30.0)

	_continent.seed = seed_value
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = rng.randf_range(0.0014, 0.0022)
	_continent.fractal_octaves = 4

	_ranges.seed = seed_value + 6
	_ranges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ranges.frequency = rng.randf_range(0.0011, 0.0016)
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
	_coast.frequency = rng.randf_range(0.0012, 0.0018)
	_coast.fractal_octaves = 3
	_detail.seed = seed_value + 2
	_detail.frequency = 0.02
	_detail.fractal_octaves = 2

	_temperature.seed = seed_value + 3
	_temperature.frequency = 0.0015
	_temperature.fractal_octaves = 2

	_moisture.seed = seed_value + 4
	_moisture.frequency = 0.002
	_moisture.fractal_octaves = 3

	_forest.seed = seed_value + 5
	_hydro_ready = false
	_forest.frequency = 0.012
	_forest.fractal_octaves = 2

	_river.seed = seed_value + 7
	_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_river.frequency = rng.randf_range(0.0013, 0.0019)
	_river.fractal_octaves = 1
	_river.domain_warp_enabled = true
	_river.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_river.domain_warp_amplitude = 40.0
	_river.domain_warp_frequency = 0.006
	_river_gate.seed = seed_value + 8
	_river_gate.frequency = 0.0012
	_river_gate.fractal_octaves = 1
	_lake.seed = seed_value + 9
	_lake.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lake.frequency = rng.randf_range(0.0035, 0.005)
	_lake.fractal_octaves = 2
	lake_amount = rng.randf_range(0.0, 1.0)

	hydro = Hydrology.compute(self)
	_hydro_ready = true
	caves = Caves.plan(self)   # planned from the base ground, so it's the same on every machine


## Terrain height in meters at world position (x, z). Sea level is 0.
## Drainage: river depths and water levels on a coarse grid (see Hydrology). Built once per world.
var hydro := {}
var caves: Dictionary = {}   ## the cave plan (see Caves.plan)
var _hydro_ready := false

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


## The procedural ground, before any digging or building.
func get_base_height(x: float, z: float) -> float:
	var half := Game.WORLD_SIZE * 0.5
	var dx := (x - half) / half
	var dz := (z - half) / half
	# Island mask: 1 in the middle, fades to 0 near the map edge, with a wobbly coastline.
	# Bays and headlands: a broad wobble for the big shape, a finer one for the rocky edge.
	var coast_raw := sqrt(dx * dx + dz * dz) + _coast.get_noise_2d(x, z) * 0.13 + _detail.get_noise_2d(x * 0.12, z * 0.12) * 0.035
	var coast := coast_raw + _detail.get_noise_2d(x * 0.12, z * 0.12) * 0.09
	var mask := 1.0 - smoothstep(0.55, 0.92, coast)

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

	var land := 3.0 + lowlands + foothills + mountains + bumps
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
	# Rivers: cut where the drainage model says water runs (see Hydrology). Done last, on the ground the
	# coast has already shaped, and never below just above the sea, so plains don't turn into lagoons.
	if _hydro_ready and ground > 0.0:
		# The cut is the drainage model's (see Hydrology.compute): river beds, with the banks beside them held above
		# the water. Never below just above the sea (Hydrology.BED_FLOOR), so plains don't turn into lagoons.
		var cut := Hydrology.sample(hydro.depth, hydro.n, x, z)
		ground = maxf(ground - cut, minf(ground, Game.SEA_LEVEL + Hydrology.BED_FLOOR))
	return ground


## How strongly the badlands climate holds here (ignores altitude so terraces stay put).
func badlands_amount(x: float, z: float) -> float:
	var t := clampf(_temperature.get_noise_2d(x, z) * 0.8 + 0.5, 0.0, 1.0)
	var c := Vector2(t, get_moisture(x, z))
	return 1.0 - smoothstep(0.08, 0.2, c.distance_to(CLIMATE_BIOMES[Biome.BADLANDS]))


## Rivers and lakes: channels and basins cut below sea level so the sea plane fills them.
## They only form in the lowlands; in hills and mountains they taper out (springs, gorges' ends).
func _carve_water(x: float, z: float, land: float, range_t: float, mask: float, bumps: float) -> float:
	var lowland := (1.0 - range_t) * (1.0 - smoothstep(6.0, 12.0, land)) * smoothstep(0.25, 0.5, mask)
	if lowland <= 0.001:
		return land
	# Lakes
	var lk := _lake.get_noise_2d(x, z)
	var lake_th := lerpf(0.56, 0.4, lake_amount)
	var lake_t := smoothstep(lake_th - 0.06, lake_th + 0.08, lk) * lowland
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


func get_moisture(x: float, z: float) -> float:
	return clampf(_moisture.get_noise_2d(x, z) * 0.8 + 0.5, 0.0, 1.0)


## Temperature and moisture (both 0..1). Higher ground is colder.
func get_climate(x: float, z: float, height: float) -> Vector2:
	var t := clampf(_temperature.get_noise_2d(x, z) * 0.8 + 0.5 - maxf(height - 20.0, 0.0) * 0.007, 0.0, 1.0)
	return Vector2(t, get_moisture(x, z))


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
	var w := get_biome_weights(get_climate(x, z, h))
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
	var w := get_biome_weights(get_climate(x, z, h))
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
func get_terrain_color(height: float, normal_y: float, x: float, z: float) -> Color:
	var jitter := (fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5) * 0.02
	var pal := palette
	var w := get_biome_weights(get_climate(x, z, height))
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
	return Color(col.r + jitter, col.g + jitter, col.b + jitter)


## A nice dry, flat-ish spot near the middle of the island to start on.
func find_spawn_point() -> Vector3:
	var center := Game.WORLD_SIZE * 0.5
	for ring in range(0, 80):
		var r := ring * 12.0
		var steps := maxi(1, ring * 6)
		for i in steps:
			var a := TAU * i / steps
			var x := center + cos(a) * r
			var z := center + sin(a) * r
			var h := get_height(x, z)
			if h > 3.0 and h < 22.0 and get_normal(x, z).y > 0.93:
				return Vector3(x, h, z)
	return Vector3(center, get_height(center, center), center)
