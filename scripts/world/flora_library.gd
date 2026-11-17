class_name FloraLibrary
extends RefCounted
## Generates this world's plant, rock and clutter species from the seed: their meshes, names
## and rules. Built once per world on the main thread; worker threads only read from it.

const Biome := WorldGen.Biome

## Which trees grow in which biome: [kind, weight].
const BIOME_TREES := {
	Biome.MEADOW: [["oak", 0.7], ["birch", 0.2], ["pine", 0.1]],
	Biome.FOREST: [["pine", 0.45], ["oak", 0.45], ["birch", 0.1]],
	Biome.AUTUMN: [["autumn_oak", 0.6], ["birch", 0.4]],
	Biome.DRYLANDS: [["acacia", 0.75], ["dead_tree", 0.25]],
	Biome.TAIGA: [["fir", 0.8], ["pine", 0.2]],
	Biome.MARSH: [["willow", 0.65], ["birch", 0.2], ["dead_tree", 0.15]],
	Biome.DESERT: [["cactus", 0.8], ["dead_tree", 0.2]],
}
## Base tree density per biome (0..1 chance per placement attempt).
const BIOME_TREE_DENSITY := {
	Biome.MEADOW: 0.07, Biome.FOREST: 0.6, Biome.AUTUMN: 0.38, Biome.DRYLANDS: 0.06,
	Biome.TAIGA: 0.55, Biome.MARSH: 0.22, Biome.DESERT: 0.06,
}
const BIOME_BUSHES := {
	Biome.MEADOW: [["bush", 0.6], ["berry", 0.4]],
	Biome.FOREST: [["bush", 0.7], ["berry", 0.3]],
	Biome.AUTUMN: [["bush", 0.6], ["berry", 0.4]],
	Biome.DRYLANDS: [["bush", 0.5], ["dead_bush", 0.5]],
	Biome.TAIGA: [["berry", 0.5], ["bush", 0.5]],
	Biome.MARSH: [["reeds", 0.75], ["bush", 0.25]],
	Biome.DESERT: [["dead_bush", 1.0]],
}
const BIOME_BUSH_DENSITY := {
	Biome.MEADOW: 0.25, Biome.FOREST: 0.35, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.4,
	Biome.TAIGA: 0.3, Biome.MARSH: 0.75, Biome.DESERT: 0.3,
}
## Small things on the ground that make places feel lived-in.
const BIOME_CLUTTER := {
	Biome.MEADOW: [["pebbles", 0.6], ["stump", 0.2], ["mushroom", 0.2], ["herb", 0.12], ["cache", 0.015]],
	Biome.FOREST: [["log", 0.3], ["stump", 0.25], ["mushroom", 0.3], ["pebbles", 0.15], ["herb", 0.1], ["cache", 0.015]],
	Biome.AUTUMN: [["log", 0.3], ["mushroom", 0.35], ["stump", 0.2], ["pebbles", 0.15], ["herb", 0.1], ["cache", 0.015]],
	Biome.DRYLANDS: [["pebbles", 0.6], ["boulder", 0.25], ["log", 0.15], ["cache", 0.02]],
	Biome.TAIGA: [["log", 0.35], ["stump", 0.25], ["mushroom", 0.2], ["pebbles", 0.2], ["herb", 0.1], ["cache", 0.015]],
	Biome.MARSH: [["log", 0.4], ["mushroom", 0.45], ["stump", 0.15], ["herb", 0.15], ["cache", 0.015]],
	Biome.DESERT: [["pebbles", 0.5], ["boulder", 0.5], ["cache", 0.03]],
}
const BIOME_CLUTTER_DENSITY := {
	Biome.MEADOW: 0.2, Biome.FOREST: 0.55, Biome.AUTUMN: 0.45, Biome.DRYLANDS: 0.3,
	Biome.TAIGA: 0.5, Biome.MARSH: 0.45, Biome.DESERT: 0.3,
}
## How much grass / ferns grow per biome (0..1).
const BIOME_GRASS := {
	Biome.MEADOW: 1.0, Biome.FOREST: 0.7, Biome.AUTUMN: 0.85, Biome.DRYLANDS: 0.8,
	Biome.TAIGA: 0.45, Biome.MARSH: 0.55, Biome.DESERT: 0.0,
}
const BIOME_FERNS := {
	Biome.MEADOW: 0.0, Biome.FOREST: 0.8, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.0,
	Biome.TAIGA: 0.6, Biome.MARSH: 0.7, Biome.DESERT: 0.0,
}

## Everything that can be placed. Fields:
##  category: visual group (draw distance, shadows, which material)
##  target:   what tools treat it as when hit (tree / rock / bush)
##  yield:    key into ItemDB.YIELDS
##  shape:    collider (tree / rock / bush / log / stump / small / none), lift: collider height
##  solid:    blocks the player
const KINDS := {
	"pine": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 100, "target": "tree", "yield": "tree", "shape": "tree"},
	"oak": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 100, "target": "tree", "yield": "tree", "shape": "tree"},
	"autumn_oak": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 100, "target": "tree", "yield": "tree", "shape": "tree"},
	"birch": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 80, "target": "tree", "yield": "tree", "shape": "tree"},
	"fir": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 110, "target": "tree", "yield": "tree", "shape": "tree"},
	"willow": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 100, "target": "tree", "yield": "tree", "shape": "tree"},
	"acacia": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 90, "target": "tree", "yield": "tree", "shape": "tree"},
	"dead_tree": {"category": "tree", "label": "Dead tree", "variants": 2, "solid": true, "hp": 60, "target": "tree", "yield": "tree", "shape": "tree"},
	"cactus": {"category": "tree", "label": "Cactus", "variants": 3, "solid": true, "hp": 60, "target": "bush", "yield": "cactus", "shape": "tree"},
	"bush": {"category": "bush", "label": "Shrub", "variants": 2, "solid": false, "hp": 40, "target": "bush", "yield": "bush", "shape": "bush"},
	"berry": {"category": "bush", "label": "Berry bush", "variants": 2, "solid": false, "hp": 40, "target": "bush", "yield": "berry", "shape": "bush"},
	"reeds": {"category": "bush", "label": "Reeds", "variants": 2, "solid": false, "hp": 20, "target": "bush", "yield": "reeds", "shape": "bush"},
	"dead_bush": {"category": "bush", "label": "Dry brush", "variants": 2, "solid": false, "hp": 20, "target": "bush", "yield": "dead_bush", "shape": "bush"},
	"rock": {"category": "rock", "label": "Stone", "variants": 4, "solid": true, "hp": 150, "target": "rock", "yield": "rock", "shape": "rock"},
	"ore_t2": {"category": "rock", "label": "Ore deposit", "variants": 2, "solid": true, "hp": 160, "target": "rock", "yield": "ore_t2", "shape": "rock", "min_tier": 1},
	"ore_t3": {"category": "rock", "label": "Ore deposit", "variants": 2, "solid": true, "hp": 200, "target": "rock", "yield": "ore_t3", "shape": "rock", "min_tier": 2},
	"gem_t4": {"category": "rock", "label": "Crystal cluster", "variants": 2, "solid": true, "hp": 220, "target": "rock", "yield": "gem_t4", "shape": "rock", "min_tier": 3},
	"boulder": {"category": "rock", "label": "Boulder", "variants": 2, "solid": true, "hp": 320, "target": "rock", "yield": "boulder", "shape": "rock"},
	"log": {"category": "clutter", "label": "Fallen log", "variants": 2, "solid": true, "hp": 60, "target": "tree", "yield": "log", "shape": "log"},
	"stump": {"category": "clutter", "label": "Stump", "variants": 2, "solid": true, "hp": 50, "target": "tree", "yield": "log", "shape": "stump"},
	"mushroom": {"category": "clutter", "label": "Mushrooms", "variants": 3, "solid": false, "hp": 10, "target": "bush", "yield": "mushroom", "shape": "small"},
	"pebbles": {"category": "clutter", "label": "Loose stones", "variants": 3, "solid": false, "hp": 10, "target": "bush", "yield": "pebbles", "shape": "small"},
	"herb": {"category": "clutter", "label": "Herb", "variants": 3, "solid": false, "hp": 10, "target": "bush", "yield": "herb", "shape": "small"},
	"cache": {"category": "clutter", "label": "Supply cache", "variants": 2, "solid": true, "hp": 40, "target": "bush", "yield": "cache", "shape": "stump"},
	"grass": {"category": "grass", "label": "", "variants": 3, "solid": false, "hp": 0},
	"flower": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
	"fern": {"category": "fern", "label": "", "variants": 3, "solid": false, "hp": 0},
}

## Fade-out distance per category (0 = always visible; trees are handled by chunk detail levels).
const VIS_RANGE := {"tree": 0.0, "bush": 150.0, "rock": 260.0, "clutter": 110.0, "grass": 60.0, "flower": 55.0, "fern": 70.0}
## Collider height offsets per shape.
const SHAPE_LIFT := {"tree": 2.0, "rock": 0.25, "bush": 0.6, "log": 0.35, "stump": 0.35, "small": 0.2}

var meshes := {}         # "pine_0" -> ArrayMesh, "pine_0_lod" -> simpler ArrayMesh
var variants := {}       # "pine" -> ["pine_0", "pine_1", ...]
var species_names := {}  # "pine" -> "Ember Spire"
var shapes := {}         # shape name -> Shape3D

var foliage_material: ShaderMaterial
var grass_material: ShaderMaterial
var rock_material: ShaderMaterial
var terrain_material: ShaderMaterial

var _pal: WorldPalette


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	_build_materials()
	_build_shapes()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	var base_detail := MeshKit.detail
	for kind: String in KINDS:
		var root: String = kind.trim_prefix("autumn_").trim_prefix("dead_")
		species_names[kind] = NameGen.species_name(rng, root)
		variants[kind] = []
		for i in KINDS[kind].variants:
			var key := "%s_%d" % [kind, i]
			var variant_seed := rng.randi()
			meshes[key] = _build_mesh(kind, i, variant_seed)
			# Far-away twin: same shape (same seed), far fewer polygons.
			if KINDS[kind].category == "tree":
				MeshKit.detail = base_detail * 0.45
				meshes[key + "_lod"] = _build_mesh(kind, i, variant_seed)
				MeshKit.detail = base_detail
			variants[kind].append(key)


static func category_of(kind: String) -> String:
	return KINDS[kind].category


static func kind_of_key(key: String) -> String:
	var k := key.trim_suffix("_lod")
	return k.substr(0, k.rfind("_"))


func display_name(kind: String) -> String:
	match kind:
		"log", "stump", "pebbles", "boulder", "cache":
			return KINDS[kind].label
		"ore_t2", "ore_t3":
			return "%s Deposit" % ItemDB.tier_info(int(kind.right(1))).name
		"gem_t4":
			return "%s Crystals" % ItemDB.tier_info(4).name
		"berry":
			return ItemDB.display_name("berries").trim_suffix(" Berries") + " Bush"
	return species_names.get(kind, kind.capitalize())


## Name of a specific resource (herbs and mushrooms differ per variant).
func resource_name(r: Dictionary) -> String:
	if r.kind in ["herb", "mushroom"]:
		var v := String(r.key).get_slice("_", 1)
		return ItemDB.display_name("%s_%s" % [r.kind, v])
	return display_name(r.kind)


# --- Materials & collision --------------------------------------------------

func _build_materials() -> void:
	foliage_material = ArtStyle.material(preload("res://shaders/foliage.gdshader"))
	grass_material = ArtStyle.material(preload("res://shaders/grass.gdshader"), {"brush_strength": 0.15})
	rock_material = ArtStyle.painted({"brush_strength": 0.4, "rim_amount": 0.1, "stroke_scale": 0.3})
	terrain_material = ArtStyle.material(preload("res://shaders/terrain.gdshader"), {"stroke_scale": 0.12, "brush_strength": 0.32})


func _build_shapes() -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.4
	trunk.height = 4.0
	shapes.tree = trunk
	var boulder := SphereShape3D.new()
	boulder.radius = 0.95
	shapes.rock = boulder
	var bush := SphereShape3D.new()
	bush.radius = 0.8
	shapes.bush = bush
	var log_shape := BoxShape3D.new()
	log_shape.size = Vector3(3.0, 0.7, 0.7)
	shapes.log = log_shape
	var stump := CylinderShape3D.new()
	stump.radius = 0.45
	stump.height = 0.7
	shapes.stump = stump
	var small := SphereShape3D.new()
	small.radius = 0.35
	shapes.small = small


# --- Mesh generation ---------------------------------------------------------

func _build_mesh(kind: String, index: int, variant_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var kit := MeshKit.new(variant_seed)
	match kind:
		"pine": _pine(kit, rng, _pal.pine_leaves, 3, 4, 7.0, 10.5, 2.0, 2.7)
		"fir": _pine(kit, rng, _pal.fir_leaves, 5, 7, 10.0, 14.0, 1.3, 1.7)
		"oak": _oak(kit, rng, _pal.oak_leaves)
		"autumn_oak": _oak(kit, rng, _pal.autumn_leaves[index % _pal.autumn_leaves.size()])
		"birch": _birch(kit, rng)
		"willow": _willow(kit, rng)
		"acacia": _acacia(kit, rng)
		"dead_tree": _dead_tree(kit, rng)
		"cactus": _cactus(kit, rng)
		"bush": _bush(kit, rng, false)
		"berry": _bush(kit, rng, true)
		"reeds": _reeds(kit, rng)
		"dead_bush": _dead_bush(kit, rng)
		"rock": _rock(kit, rng, false)
		"ore_t2": _rock(kit, rng, true, ItemDB.tier_info(2).color)
		"ore_t3": _rock(kit, rng, true, ItemDB.tier_info(3).color)
		"gem_t4": _gem(kit, rng, ItemDB.tier_info(4).color)
		"herb": _herb(kit, rng, ItemDB.info("herb_%d" % index).get("color", _pal.fern))
		"cache": _cache(kit, rng)
		"boulder": _boulder(kit, rng)
		"log": _log(kit, rng)
		"stump": _stump(kit, rng)
		"mushroom": _mushrooms(kit, rng, index)
		"pebbles": _pebbles(kit, rng)
		"grass": _grass(kit, rng)
		"flower": _flower(kit, rng, _pal.flowers[index % _pal.flowers.size()])
		"fern": _fern(kit, rng)
	var cat: String = KINDS[kind].category
	var mat: Material = foliage_material
	if cat == "rock" or kind == "pebbles":
		mat = rock_material
	elif cat in ["grass", "flower", "fern"]:
		mat = grass_material
	return kit.commit(mat)


func _vary(c: Color, rng: RandomNumberGenerator, amount := 0.06) -> Color:
	return Color.from_hsv(fposmod(c.h + rng.randf_range(-amount, amount) * 0.3, 1.0), c.s, clampf(c.v + rng.randf_range(-amount, amount), 0, 1))


# Painterly trees: each canopy is lit as one soft volume (shared puff_center),
# with small leaf clumps on the surface to break up the silhouette.

func _pine(kit: MeshKit, rng: RandomNumberGenerator, leaf: Color, tiers_min: int, tiers_max: int,
		h_min: float, h_max: float, r_min: float, r_max: float) -> void:
	var h := rng.randf_range(h_min, h_max)
	var trunk_r := rng.randf_range(0.24, 0.32)
	var bark := _vary(_pal.bark, rng)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.5, trunk_r, h * 0.5, 7), Transform3D(Basis(), Vector3(0, h * 0.25, 0)), bark, 0.03)
	var tiers := rng.randi_range(tiers_min, tiers_max)
	var base := h * rng.randf_range(0.18, 0.28)
	var radius := rng.randf_range(r_min, r_max)
	var tier_h := (h - base) / tiers * 1.75
	var leaves := _vary(leaf, rng)
	for t in tiers:
		var f := float(t) / tiers
		var r := lerpf(radius, radius * 0.4, f)
		var y := base + (h - base - tier_h) * (float(t) / (tiers - 1))
		var twist := Basis(Vector3.UP, rng.randf() * TAU)
		# Each tier is lit from its own core, so the layers read as separate soft skirts.
		kit.add_primitive(MeshKit.cylinder(0.0, r, tier_h, 9), Transform3D(twist, Vector3(0, y + tier_h * 0.5, 0)),
			leaves.lightened(f * 0.14), 0.18, 0.06, Vector3(0, y + tier_h * 0.2, 0))


func _oak(kit: MeshKit, rng: RandomNumberGenerator, leaf: Color) -> void:
	var h := rng.randf_range(2.6, 3.8)
	var trunk_r := rng.randf_range(0.3, 0.42)
	var bark := _vary(_pal.bark, rng)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.6, trunk_r, h + 0.8, 8), Transform3D(Basis(), Vector3(0, (h + 0.8) * 0.5, 0)), bark, 0.06)
	_branches(kit, rng, bark, trunk_r, h, rng.randi_range(2, 3), 30, 50)
	var center := Vector3(0, h + 1.3, 0)
	var base_leaf := _vary(leaf, rng)
	var blobs: Array = [[center, rng.randf_range(1.9, 2.3)]]
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.1, 1.7)
		blobs.append([center + Vector3(cos(a) * d, rng.randf_range(-0.7, 0.8), sin(a) * d), rng.randf_range(1.1, 1.6)])
	for bl: Array in blobs:
		kit.add_primitive(MeshKit.sphere(bl[1], 9, 5), Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), bl[0]),
			base_leaf.lightened(rng.randf_range(-0.05, 0.06)), bl[1] * 0.2, 0.07, center)
	_leaf_clumps(kit, rng, blobs, center, base_leaf, rng.randi_range(7, 10), 0.4)


func _branches(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, trunk_r: float, h: float, count: int, tilt_min: float, tilt_max: float) -> Array:
	var tips := []
	for b in count:
		var yaw := rng.randf() * TAU
		var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(tilt_min, tilt_max)))
		var length := rng.randf_range(1.2, 1.8)
		var start := Vector3(0, h * rng.randf_range(0.6, 0.9), 0)
		kit.add_primitive(MeshKit.cylinder(trunk_r * 0.22, trunk_r * 0.42, length, 6), Transform3D(tilt, start + tilt.y * length * 0.5), bark)
		tips.append(start + tilt.y * length)
	return tips


func _birch(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(6.0, 8.5)
	var trunk_r := rng.randf_range(0.15, 0.2)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.6, trunk_r, h, 7), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), _pal.birch_bark, 0.0, 0.03)
	for i in rng.randi_range(4, 7):
		var y := rng.randf_range(0.4, h * 0.7)
		var r := lerpf(trunk_r, trunk_r * 0.6, y / h) * 1.06
		kit.add_primitive(MeshKit.cylinder(r, r, rng.randf_range(0.05, 0.12), 7), Transform3D(Basis(), Vector3(0, y, 0)), Color(0.2, 0.18, 0.17), 0.0, 0.0)
	var leaf := _vary(_pal.birch_leaves, rng)
	var center := Vector3(0, h * 0.78, 0)
	var blobs: Array = []
	var clumps := rng.randi_range(4, 6)
	for i in clumps:
		var f := float(i) / (clumps - 1)
		var r := lerpf(1.05, 0.6, f) * rng.randf_range(0.85, 1.15)
		var a := rng.randf() * TAU
		var spread := lerpf(0.75, 0.2, f)
		var pos := Vector3(cos(a) * spread, lerpf(h * 0.55, h * 0.98, f), sin(a) * spread)
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis().scaled(Vector3(1, 1.25, 1)), pos),
			leaf.lightened(rng.randf_range(-0.06, 0.08)), r * 0.22, 0.07, center)
	_leaf_clumps(kit, rng, blobs, center, leaf, 5, 0.3)


## Weeping willow: a dome with long curtains of leaves hanging around it.
func _willow(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(3.2, 4.2)
	var trunk_r := rng.randf_range(0.38, 0.5)
	var bark := _vary(_pal.bark, rng).darkened(0.1)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.7, trunk_r, h + 0.6, 8), Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12)), Vector3(0, (h + 0.6) * 0.5, 0)), bark, 0.08)
	var leaf := _vary(_pal.willow_leaves, rng)
	var center := Vector3(0, h + 1.0, 0)
	kit.add_primitive(MeshKit.sphere(2.3, 10, 6), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), center), leaf, 0.35, 0.07, center)
	var curtains := rng.randi_range(9, 13)
	for i in curtains:
		var a := TAU * i / curtains + rng.randf_range(-0.2, 0.2)
		var d := rng.randf_range(1.6, 2.2)
		var length := rng.randf_range(2.0, 3.2)
		var pos := Vector3(cos(a) * d, center.y - length * 0.42, sin(a) * d)
		kit.add_primitive(MeshKit.sphere(0.5, 7, 5), Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.45, length, 0.9)), pos),
			leaf.lightened(rng.randf_range(-0.03, 0.1)), 0.06, 0.05, center + Vector3(0, -1.0, 0))


## Savanna tree: leaning trunk splitting into branches with flat, wide canopy layers.
func _acacia(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(3.5, 5.0)
	var trunk_r := rng.randf_range(0.22, 0.3)
	var bark := _vary(_pal.bark, rng).lightened(0.05)
	var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.18, 0.18))
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.7, trunk_r, h, 7), Transform3D(lean, lean.y * h * 0.5), bark, 0.04)
	var top := lean.y * h
	var leaf := _vary(_pal.acacia_leaves, rng)
	var center := top + Vector3(0, 1.4, 0)
	for b in rng.randi_range(2, 3):
		var dir := (Vector3(rng.randf_range(-1, 1), rng.randf_range(0.7, 1.1), rng.randf_range(-1, 1))).normalized()
		var length := rng.randf_range(1.3, 2.0)
		kit.add_primitive(MeshKit.cylinder(trunk_r * 0.3, trunk_r * 0.6, length, 6), Transform3D(Basis(Quaternion(Vector3.UP, dir)), top + dir * length * 0.5), bark)
		var tip := top + dir * length
		var r := rng.randf_range(1.6, 2.3)
		kit.add_primitive(MeshKit.sphere(r, 10, 5), Transform3D(Basis().scaled(Vector3(1, 0.28, 1)), tip + Vector3(0, 0.2, 0)), leaf.lightened(rng.randf_range(-0.04, 0.08)), 0.25, 0.07, center)
	kit.add_primitive(MeshKit.sphere(2.4, 11, 5), Transform3D(Basis().scaled(Vector3(1, 0.24, 1)), center), leaf, 0.3, 0.07, center)


## Bare, weathered tree.
func _dead_tree(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(3.5, 6.0)
	var trunk_r := rng.randf_range(0.2, 0.3)
	var wood := _vary(_pal.dead_wood, rng)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.35, trunk_r, h, 7), Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), Vector3(0, h * 0.5, 0)), wood, 0.05)
	for b in rng.randi_range(3, 5):
		var yaw := rng.randf() * TAU
		var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(25, 60)))
		var length := rng.randf_range(0.9, 1.8)
		var start := Vector3(0, h * rng.randf_range(0.45, 0.9), 0)
		kit.add_primitive(MeshKit.cylinder(trunk_r * 0.08, trunk_r * 0.35, length, 5), Transform3D(tilt, start + tilt.y * length * 0.5), wood.darkened(0.05))
		# A twig off each branch.
		var twig := tilt * Basis(Vector3.RIGHT, deg_to_rad(-40))
		kit.add_primitive(MeshKit.cylinder(0.01, trunk_r * 0.12, length * 0.5, 4), Transform3D(twig, start + tilt.y * length * 0.6 + twig.y * length * 0.25), wood)


func _cactus(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(2.0, 3.6)
	var r := rng.randf_range(0.28, 0.38)
	var col := _vary(_pal.cactus, rng)
	var ribs := func(p: Vector3) -> Color:
		return col.darkened(0.12) if sin(atan2(p.z, p.x) * 8.0) > 0.4 else col
	kit.add_primitive(MeshKit.cylinder(r, r * 1.05, h, 12), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), col, 0.0, 0.04, null, ribs)
	kit.add_primitive(MeshKit.sphere(r, 12, 6), Transform3D(Basis(), Vector3(0, h, 0)), col, 0.0, 0.04, null, ribs)
	for side in ([-1.0, 1.0] if rng.randf() < 0.7 else [1.0]):
		var y := rng.randf_range(h * 0.35, h * 0.6)
		var out := rng.randf_range(0.5, 0.75)
		var up := rng.randf_range(0.6, 1.1)
		var ar := r * 0.7
		var dir := Vector3(side, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
		kit.add_primitive(MeshKit.cylinder(ar, ar, out, 10), Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(0, y, 0) + dir * out * 0.5), col, 0.0, 0.04)
		kit.add_primitive(MeshKit.cylinder(ar, ar, up, 10), Transform3D(Basis(), Vector3(0, y + up * 0.5, 0) + dir * out), col, 0.0, 0.04, null, ribs)
		kit.add_primitive(MeshKit.sphere(ar, 10, 5), Transform3D(Basis(), Vector3(0, y + up, 0) + dir * out), col, 0.0, 0.04)
	if rng.randf() < 0.5:
		kit.add_primitive(MeshKit.sphere(r * 0.35, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0, h + r * 0.85, 0)), _pal.flowers[0], 0.0, 0.03)


## Small leafy bumps scattered over the canopy surface.
func _leaf_clumps(kit: MeshKit, rng: RandomNumberGenerator, blobs: Array, center: Vector3, leaf: Color, count: int, size: float) -> void:
	for i in count:
		var bl: Array = blobs[rng.randi() % blobs.size()]
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var r := size * rng.randf_range(0.8, 1.3)
		var pos: Vector3 = bl[0] + dir * float(bl[1]) * 0.85
		kit.add_primitive(MeshKit.sphere(r, 6, 4), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(0.02, 0.12)), r * 0.2, 0.05, center)


func _bush(kit: MeshKit, rng: RandomNumberGenerator, berries: bool) -> void:
	var leaf := _vary(_pal.bush_leaves, rng)
	var center := Vector3(0, 0.45, 0)
	var blobs := []
	for i in rng.randi_range(3, 4):
		var r := rng.randf_range(0.5, 0.85)
		var pos := Vector3(rng.randf_range(-0.5, 0.5), r * 0.7, rng.randf_range(-0.5, 0.5))
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(-0.05, 0.07)), r * 0.25, 0.07, center)
	if berries:
		for i in rng.randi_range(10, 16):
			var blob: Array = blobs[rng.randi() % blobs.size()]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			kit.add_primitive(MeshKit.sphere(0.09, 6, 4), Transform3D(Basis(), blob[0] + dir * blob[1] * 0.95), _pal.berry, 0.0, 0.04)


func _reeds(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(_pal.reed, rng)
	for i in rng.randi_range(14, 22):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.6)
		var base := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var tip := base + lean + Vector3.UP * rng.randf_range(0.9, 1.7)
		var side := Vector3(cos(a + 1.5), 0, sin(a + 1.5)) * 0.03
		kit.add_tri(base - side, base + side, tip, col.darkened(0.25), col.darkened(0.25), col.lightened(0.1))
		if rng.randf() < 0.35:   # cattail head
			kit.force_up_normals = false
			kit.add_primitive(MeshKit.sphere(0.05, 6, 4), Transform3D(Basis().scaled(Vector3(1, 3.2, 1)), base + (tip - base) * 0.8), Color(0.42, 0.28, 0.18), 0.0, 0.03)
			kit.force_up_normals = true


func _dead_bush(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.dead_wood, rng).darkened(0.1)
	for i in rng.randi_range(7, 11):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.2), rng.randf_range(-1, 1)).normalized()
		var length := rng.randf_range(0.5, 1.0)
		kit.add_primitive(MeshKit.cylinder(0.008, 0.035, length, 4), Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * length * 0.5), col, 0.0, 0.05)
		var fork := (dir + Vector3(rng.randf_range(-0.6, 0.6), 0.2, rng.randf_range(-0.6, 0.6))).normalized()
		kit.add_primitive(MeshKit.cylinder(0.005, 0.02, length * 0.5, 4), Transform3D(Basis(Quaternion(Vector3.UP, fork)), dir * length * 0.6 + fork * length * 0.25), col, 0.0, 0.05)


func _rock(kit: MeshKit, rng: RandomNumberGenerator, ore: bool, ore_color := Color.WHITE) -> void:
	var col := _vary(_pal.rock, rng, 0.05)
	var squash := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.65, 0.9), rng.randf_range(0.9, 1.2))
	kit.add_primitive(MeshKit.sphere(1.0, 11, 7), Transform3D(Basis().scaled(squash), Vector3(0, 0.25, 0)), col, 0.3, 0.08)
	if rng.randf() < 0.5:
		var off := Vector3(rng.randf_range(0.7, 1.1), 0.0, rng.randf_range(-0.6, 0.6))
		kit.add_primitive(MeshKit.sphere(0.55, 9, 5), Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), off), col.darkened(0.06), 0.2, 0.08)
	if rng.randf() < 0.4:
		kit.add_primitive(MeshKit.sphere(0.6, 8, 4), Transform3D(Basis().scaled(Vector3(1.2, 0.25, 1.0)), Vector3(rng.randf_range(-0.3, 0.3), 0.25 + squash.y * 0.78, 0)), _vary(_pal.moss, rng), 0.15, 0.06)
	if ore:
		for i in rng.randi_range(4, 7):
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-1, 1)).normalized()
			var length := rng.randf_range(0.6, 1.1)
			var b := Basis(Quaternion(Vector3.UP, dir))
			var pos := Vector3(dir.x * squash.x, dir.y * squash.y, dir.z * squash.z) * 0.75 + Vector3(0, 0.25, 0)
			kit.add_primitive(MeshKit.cylinder(0.0, rng.randf_range(0.12, 0.2), length, 5), Transform3D(b, pos + dir * length * 0.4),
				_vary(ore_color, rng, 0.06), 0.0, 0.05)


## Tier-4 gem: big crystal spikes bursting from a small rock.
func _gem(kit: MeshKit, rng: RandomNumberGenerator, col: Color) -> void:
	kit.add_primitive(MeshKit.sphere(0.8, 10, 6), Transform3D(Basis().scaled(Vector3(1.2, 0.6, 1.0)), Vector3(0, 0.15, 0)), _vary(_pal.rock, rng).darkened(0.1), 0.25, 0.08)
	for i in rng.randi_range(5, 8):
		var dir := Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.6, 1.0), rng.randf_range(-0.7, 0.7)).normalized()
		var length := rng.randf_range(0.8, 1.7)
		var r := rng.randf_range(0.14, 0.26)
		var b := Basis(Quaternion(Vector3.UP, dir))
		kit.add_primitive(MeshKit.cylinder(0.0, r, length, 6), Transform3D(b, dir * (0.3 + length * 0.5)), _vary(col, rng, 0.05).lightened(rng.randf_range(0.0, 0.15)), 0.0, 0.06)


## Low leafy herb with a few flowering tips.
func _herb(kit: MeshKit, rng: RandomNumberGenerator, col: Color) -> void:
	kit.force_up_normals = true
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * rng.randf_range(0.05, 0.08)
		var length := rng.randf_range(0.22, 0.38)
		var tip := dir * length + Vector3.UP * rng.randf_range(0.12, 0.28)
		var mid := dir * length * 0.45 + Vector3.UP * 0.1
		kit.add_tri(Vector3(0, 0.02, 0), mid + side, tip, col.darkened(0.15), col, col.lightened(0.15))
		kit.add_tri(Vector3(0, 0.02, 0), tip, mid - side, col.darkened(0.15), col.lightened(0.15), col)
	kit.force_up_normals = false
	for i in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.25, 0.35), rng.randf_range(-0.1, 0.1))
		kit.add_primitive(MeshKit.sphere(0.035, 6, 4), Transform3D(Basis(), p), col.lightened(0.45), 0.0, 0.03)


## Supply cache: a lashed wooden crate with a cloth bundle on top.
func _cache(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var wood := _vary(_pal.bark, rng).lightened(0.15)
	var w := rng.randf_range(0.8, 1.0)
	kit.add_primitive(BoxMesh.new(), Transform3D(Basis().scaled(Vector3(w, 0.55, 0.6)), Vector3(0, 0.27, 0)), wood, 0.0, 0.05)
	for x in [-0.42, 0.42]:   # slats
		kit.add_primitive(BoxMesh.new(), Transform3D(Basis().scaled(Vector3(0.08, 0.58, 0.64)), Vector3(x * w, 0.27, 0)), wood.darkened(0.2), 0.0, 0.03)
	kit.add_primitive(BoxMesh.new(), Transform3D(Basis().scaled(Vector3(w + 0.04, 0.05, 0.64)), Vector3(0, 0.4, 0)), Color(0.55, 0.45, 0.3), 0.0, 0.0)  # rope
	var cloth := Color.from_hsv(rng.randf_range(0.0, 0.12), 0.45, 0.62)
	kit.add_primitive(MeshKit.sphere(0.32, 10, 6), Transform3D(Basis().scaled(Vector3(1.1, 0.55, 0.9)), Vector3(rng.randf_range(-0.15, 0.15), 0.66, 0)), cloth, 0.08, 0.06)


## A big weathered rock formation (2-4 stacked masses).
func _boulder(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.rock, rng, 0.05)
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(1.0, 1.6) * (1.0 - i * 0.18)
		var pos := Vector3(rng.randf_range(-0.9, 0.9), r * 0.45 + i * 0.35, rng.randf_range(-0.9, 0.9))
		kit.add_primitive(MeshKit.sphere(r, 11, 7), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.0, 1.5), rng.randf_range(0.6, 0.9), 1.0)), pos), col.lightened(i * 0.03), 0.35, 0.09)


func _log(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(2.6, 3.4)
	var r := rng.randf_range(0.28, 0.36)
	var bark := _vary(_pal.bark, rng)
	var b := Basis(Vector3.FORWARD, PI * 0.5)
	kit.add_primitive(MeshKit.cylinder(r * 0.9, r, length, 9), Transform3D(b, Vector3(0, r * 0.85, 0)), bark, 0.04)
	for side in [-1.0, 1.0]:   # cut ends showing pale wood
		kit.add_primitive(MeshKit.cylinder(r * 0.82, r * 0.82, 0.04, 9), Transform3D(b, Vector3(side * length * 0.5, r * 0.85, 0)), Color(0.82, 0.68, 0.48), 0.0, 0.03)
	kit.add_primitive(MeshKit.sphere(r * 1.1, 8, 4), Transform3D(Basis().scaled(Vector3(2.2, 0.35, 0.9)), Vector3(rng.randf_range(-0.6, 0.6), r * 1.75, 0)), _vary(_pal.moss, rng), 0.2, 0.06)
	if rng.randf() < 0.6:
		_mushroom_cluster(kit, rng, Vector3(rng.randf_range(-1.0, 1.0), r * 0.4, r * 0.9), 0.6, _pal.mushroom_caps[1])


func _stump(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.38, 0.5)
	var h := rng.randf_range(0.45, 0.8)
	var bark := _vary(_pal.bark, rng)
	kit.add_primitive(MeshKit.cylinder(r, r * 1.15, h, 9), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), bark, 0.05)
	var rings := func(p: Vector3) -> Color:
		return Color(0.8, 0.66, 0.46) if sin(Vector2(p.x, p.z).length() * 55.0) > -0.2 else Color(0.7, 0.55, 0.38)
	kit.add_primitive(MeshKit.cylinder(r * 0.92, r * 0.92, 0.04, 9), Transform3D(Basis(), Vector3(0, h, 0)), Color(0.8, 0.66, 0.46), 0.0, 0.0, null, rings)
	for i in rng.randi_range(3, 4):
		var a := TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), -0.35, sin(a)).normalized()
		kit.add_primitive(MeshKit.cylinder(0.04, r * 0.35, 0.7, 6), Transform3D(Basis(Quaternion(Vector3.UP, -dir)), Vector3(cos(a) * r * 0.9, 0.1, sin(a) * r * 0.9)), bark.darkened(0.05))


func _mushrooms(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	_mushroom_cluster(kit, rng, Vector3.ZERO, 1.0, _pal.mushroom_caps[index % _pal.mushroom_caps.size()])


func _mushroom_cluster(kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, scale: float, cap: Color) -> void:
	for i in rng.randi_range(3, 6):
		var p := at + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * scale
		var h := rng.randf_range(0.08, 0.22) * scale
		var r := rng.randf_range(0.05, 0.11) * scale
		kit.add_primitive(MeshKit.cylinder(r * 0.35, r * 0.45, h, 6), Transform3D(Basis(), p + Vector3(0, h * 0.5, 0)), Color(0.92, 0.88, 0.8), 0.0, 0.02)
		var spots := func(q: Vector3) -> Color:
			return Color(0.97, 0.95, 0.9) if fposmod(q.x * 61.0 + q.z * 37.0, 1.0) > 0.82 and q.y > p.y + h + r * 0.15 else cap
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.55, 1)), p + Vector3(0, h, 0)), cap, 0.0, 0.04, null, spots)


func _pebbles(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 6):
		var r := rng.randf_range(0.06, 0.18)
		var p := Vector3(rng.randf_range(-0.4, 0.4), r * 0.3, rng.randf_range(-0.4, 0.4))
		kit.add_primitive(MeshKit.sphere(r, 7, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.6, 1.0)), p), _vary(_pal.pebble, rng, 0.08), 0.15, 0.05)


func _grass(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	# Grey-ish colors: each tuft is tinted by the ground color under it at placement time.
	kit.force_up_normals = true
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.3)
		var base := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0, sin(yaw)) * rng.randf_range(0.035, 0.06)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.25)
		var tip := base + lean + Vector3.UP * rng.randf_range(0.35, 0.75)
		kit.add_tri(base - side, base + side, tip, Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8), Color(1.1, 1.1, 1.1))


func _flower(kit: MeshKit, rng: RandomNumberGenerator, petal: Color) -> void:
	kit.force_up_normals = true
	var stem := _pal.meadow_grass.darkened(0.25)
	for i in rng.randi_range(2, 4):
		var base := Vector3(rng.randf_range(-0.25, 0.25), -0.05, rng.randf_range(-0.25, 0.25))
		var top := base + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.3, 0.55), rng.randf_range(-0.08, 0.08))
		var side := Vector3(0.025, 0, 0.02)
		kit.add_tri(base - side, base + side, top, stem)
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.06, 0.1), 5, 3), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), top), _vary(petal, rng, 0.05), 0.0, 0.03)


## Arching fern fronds made of little leaflets along a curved spine.
func _fern(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(_pal.fern, rng)
	var fronds := rng.randi_range(5, 8)
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(0.6, 1.0)
		var prev := Vector3(0, 0.02, 0)
		var segs := 7
		for s in segs:
			var t := float(s + 1) / segs
			# Rise then droop.
			var p := dir * length * t + Vector3.UP * (sin(t * PI * 0.8) * length * 0.55)
			var w := (1.0 - t) * 0.16 + 0.03
			var c := col.lightened(t * 0.15)
			kit.add_tri(prev, p, prev + side * w + dir * 0.03, c)
			kit.add_tri(prev, prev - side * w + dir * 0.03, p, c)
			prev = p
