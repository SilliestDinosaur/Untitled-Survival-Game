class_name WorldPalette
extends RefCounted
## Every color in the world, generated from the seed.
## Most worlds look natural with a twist; about 1 in 5 is "exotic" (strange hues).

var exotic := false

# Ground colors per biome (sRGB).
var sand: Color
var meadow_grass: Color
var forest_grass: Color
var autumn_grass: Color
var dry_grass: Color
var rock: Color
var rock_light: Color
var snow: Color
var taiga_grass: Color
var marsh_grass: Color
var desert_sand: Color
## Biome -> ground color (used for smooth blending).
var ground := {}

# Foliage.
var pine_leaves: Color
var oak_leaves: Color
var autumn_leaves: Array[Color] = []
var birch_leaves: Color
var bark: Color
var birch_bark: Color
var bush_leaves: Color
var berry: Color
var flowers: Array[Color] = []
var ore_crystal: Color
var fir_leaves: Color
var willow_leaves: Color
var acacia_leaves: Color
var cactus: Color
var dead_wood: Color
var reed: Color
var fern: Color
var moss: Color
var mushroom_caps: Array[Color] = []
var pebble: Color

# Sky / water.
var sky_top: Color
var sky_horizon: Color
var cloud: Color
var sun: Color
var water_shallow: Color
var water_deep: Color


func _init(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	exotic = rng.randf() < 0.2
	# One global hue shift for plants keeps the world coherent.
	var plant_shift := rng.randf_range(-0.5, 0.5) if exotic else rng.randf_range(-0.035, 0.035)
	var sky_shift := rng.randf_range(-0.35, 0.35) if exotic and rng.randf() < 0.6 else rng.randf_range(-0.03, 0.03)
	var sat := rng.randf_range(0.85, 1.1)

	var p := func(h: float, s: float, v: float) -> Color:
		return Color.from_hsv(fposmod(h + plant_shift + rng.randf_range(-0.015, 0.015), 1.0), clampf(s * sat, 0, 1), v)
	var k := func(h: float, s: float, v: float) -> Color:
		return Color.from_hsv(fposmod(h + sky_shift, 1.0), clampf(s, 0, 1), v)

	sand = Color.from_hsv(rng.randf_range(0.10, 0.14), rng.randf_range(0.25, 0.4), 0.86)
	meadow_grass = p.call(0.25, 0.55, 0.62)
	forest_grass = p.call(0.30, 0.55, 0.45)
	autumn_grass = p.call(0.17, 0.55, 0.58)
	dry_grass = p.call(0.14, 0.45, 0.66)
	rock = Color.from_hsv(rng.randf_range(0.0, 1.0), rng.randf_range(0.03, 0.10), rng.randf_range(0.44, 0.54))
	rock_light = rock.lightened(0.12)
	snow = Color(0.93, 0.95, 0.98)
	taiga_grass = p.call(0.36, 0.35, 0.42)
	marsh_grass = p.call(0.2, 0.5, 0.42)
	desert_sand = Color.from_hsv(rng.randf_range(0.06, 0.1), rng.randf_range(0.35, 0.5), 0.82)

	pine_leaves = p.call(0.38, 0.55, 0.38)
	oak_leaves = p.call(0.29, 0.6, 0.48)
	birch_leaves = p.call(0.21, 0.6, 0.62)
	autumn_leaves = [p.call(0.07, 0.75, 0.80), p.call(0.03, 0.7, 0.65), p.call(0.11, 0.75, 0.85)]
	bark = Color.from_hsv(rng.randf_range(0.05, 0.09), 0.45, rng.randf_range(0.30, 0.38))
	birch_bark = Color(0.90, 0.89, 0.85)
	bush_leaves = p.call(0.31, 0.55, 0.42)
	berry = Color.from_hsv(rng.randf_range(0.9, 1.05), 0.8, 0.75)
	flowers = []
	for i in 3:
		flowers.append(Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.8), rng.randf_range(0.85, 1.0)))
	ore_crystal = Color.from_hsv(rng.randf(), 0.65, 0.95)
	fir_leaves = p.call(0.42, 0.45, 0.32)
	willow_leaves = p.call(0.24, 0.5, 0.55)
	acacia_leaves = p.call(0.22, 0.55, 0.5)
	cactus = p.call(0.33, 0.45, 0.5)
	dead_wood = Color.from_hsv(rng.randf_range(0.06, 0.1), 0.2, rng.randf_range(0.5, 0.62))
	reed = p.call(0.17, 0.45, 0.62)
	fern = p.call(0.31, 0.6, 0.45)
	moss = p.call(0.27, 0.55, 0.45)
	pebble = rock.lightened(0.05)
	mushroom_caps = [Color.from_hsv(rng.randf_range(0.98, 1.03), 0.75, 0.75), Color.from_hsv(0.08, 0.45, 0.62), Color.from_hsv(rng.randf(), 0.5, 0.8)]

	ground = {
		WorldGen.Biome.MEADOW: meadow_grass,
		WorldGen.Biome.FOREST: forest_grass,
		WorldGen.Biome.AUTUMN: autumn_grass,
		WorldGen.Biome.DRYLANDS: dry_grass,
		WorldGen.Biome.TAIGA: taiga_grass,
		WorldGen.Biome.MARSH: marsh_grass,
		WorldGen.Biome.DESERT: desert_sand,
	}

	sky_top = k.call(0.60, 0.55, 0.88)
	sky_horizon = k.call(0.58, 0.22, 0.95)
	cloud = Color(1.0, 0.98, 0.96)
	sun = Color.from_hsv(rng.randf_range(0.08, 0.13), rng.randf_range(0.08, 0.2), 1.0)
	water_shallow = k.call(0.48, 0.55, 0.75)
	water_deep = k.call(0.58, 0.8, 0.35)
