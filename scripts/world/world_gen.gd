class_name WorldGen
extends RefCounted
## Pure math that describes the island: height, biomes, colors.
## No nodes and no hidden randomness, so it gives identical results on every machine
## and is safe to call from worker threads.

enum Biome { MEADOW, FOREST, AUTUMN, DRYLANDS, BEACH, HIGHLANDS, SNOW }
const BIOME_NAMES := ["Meadow", "Forest", "Autumn Grove", "Drylands", "Beach", "Highlands", "Snowfields"]

## Biome "centers" in (temperature, moisture) space. Ground colors blend between them smoothly.
const _BIOME_CLIMATE := {
	Biome.MEADOW: Vector2(0.55, 0.35),
	Biome.FOREST: Vector2(0.55, 0.75),
	Biome.AUTUMN: Vector2(0.2, 0.55),
	Biome.DRYLANDS: Vector2(0.9, 0.15),
}

var palette: WorldPalette
var mountain_scale: float
var hill_scale: float

var _continent := FastNoiseLite.new()  # big rolling hills
var _ridge := FastNoiseLite.new()      # mountain ridges
var _detail := FastNoiseLite.new()     # small bumps + coastline wobble
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _forest := FastNoiseLite.new()     # clumping of trees inside a biome


func _init(seed_value: int, pal: WorldPalette) -> void:
	palette = pal
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Each world has its own "personality": flatter or more mountainous.
	mountain_scale = rng.randf_range(70.0, 140.0)
	hill_scale = rng.randf_range(18.0, 34.0)

	_continent.seed = seed_value
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = rng.randf_range(0.0014, 0.0022)
	_continent.fractal_octaves = 4

	_ridge.seed = seed_value + 1
	_ridge.frequency = rng.randf_range(0.0035, 0.005)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4

	_detail.seed = seed_value + 2
	_detail.frequency = 0.02
	_detail.fractal_octaves = 2

	_temperature.seed = seed_value + 3
	_temperature.frequency = 0.0016
	_temperature.fractal_octaves = 2

	_moisture.seed = seed_value + 4
	_moisture.frequency = 0.0022
	_moisture.fractal_octaves = 3

	_forest.seed = seed_value + 5
	_forest.frequency = 0.012
	_forest.fractal_octaves = 2


## Terrain height in meters at world position (x, z). Sea level is 0.
func get_height(x: float, z: float) -> float:
	var half := Game.WORLD_SIZE * 0.5
	var dx := (x - half) / half
	var dz := (z - half) / half
	# Island mask: 1 in the middle, fades to 0 near the map edge, with a wobbly coastline.
	var coast := sqrt(dx * dx + dz * dz) + _detail.get_noise_2d(x * 0.12, z * 0.12) * 0.12
	var mask := 1.0 - smoothstep(0.55, 0.92, coast)

	var c := _continent.get_noise_2d(x, z) * 0.5 + 0.5          # 0..1
	var hills := c * hill_scale
	var ridge := maxf(0.0, _ridge.get_noise_2d(x, z) * 0.5 + 0.5 - 0.45) * 1.8
	var mountains := ridge * ridge * smoothstep(0.5, 0.8, c) * mountain_scale * 1.6
	var bumps := _detail.get_noise_2d(x, z) * 1.0

	var land := 3.0 + hills + mountains + bumps
	# Flatten a little right at the shore so beaches are walkable.
	return lerpf(-25.0, land, mask)


## Approximate surface normal, from neighbouring heights.
func get_normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := get_height(x - e, z)
	var hr := get_height(x + e, z)
	var hd := get_height(x, z - e)
	var hu := get_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Temperature and moisture (both 0..1). Higher ground is colder.
func get_climate(x: float, z: float, height: float) -> Vector2:
	var t := clampf(_temperature.get_noise_2d(x, z) * 0.75 + 0.5 - maxf(height - 20.0, 0.0) * 0.006, 0.0, 1.0)
	var m := clampf(_moisture.get_noise_2d(x, z) * 0.75 + 0.5, 0.0, 1.0)
	return Vector2(t, m)


## Soft weights for the 4 climate biomes (sum to 1). Used for color blending + flora choice.
func get_biome_weights(climate: Vector2) -> Dictionary:
	var weights := {}
	var total := 0.0
	for b: int in _BIOME_CLIMATE:
		var d: float = climate.distance_squared_to(_BIOME_CLIMATE[b])
		var w := 1.0 / pow(d + 0.002, 2.0)
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
	if h > 50.0:
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
	if h > 50.0 or get_normal(x, z).y < 0.72:
		return "rock"
	return "grass"


## 0..1 clumping factor for trees.
func get_forest_clump(x: float, z: float) -> float:
	return clampf(_forest.get_noise_2d(x, z) * 0.8 + 0.55, 0.0, 1.0)


## Stylized flat colors (sRGB) from height, steepness and biome.
func get_terrain_color(height: float, normal_y: float, x: float, z: float) -> Color:
	var jitter := (fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5) * 0.045
	var pal := palette
	var col: Color
	var w := get_biome_weights(get_climate(x, z, height))
	var grass: Color = pal.meadow_grass * w[Biome.MEADOW] + pal.forest_grass * w[Biome.FOREST] \
		+ pal.autumn_grass * w[Biome.AUTUMN] + pal.dry_grass * w[Biome.DRYLANDS]
	# Darker patches under dense forest clumps.
	grass = grass.darkened(get_forest_clump(x, z) * 0.08)

	var sand_t := 1.0 - smoothstep(1.0, 2.6, height)
	var steep_t := smoothstep(0.80, 0.68, normal_y)
	var high_t := smoothstep(44.0, 56.0, height)
	col = grass.lerp(pal.sand, sand_t)
	col = col.lerp(pal.rock, maxf(steep_t, high_t))
	if height > 72.0 and normal_y > 0.62:
		col = col.lerp(pal.snow, smoothstep(72.0, 82.0, height))
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
