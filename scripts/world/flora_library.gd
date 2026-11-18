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
	Biome.JUNGLE: [["jungle_tree", 0.7], ["palm", 0.2], ["willow", 0.1]],
	Biome.TUNDRA: [["fir", 0.4], ["dead_tree", 0.6]],
	Biome.BADLANDS: [["dead_tree", 0.5], ["cactus", 0.3], ["acacia", 0.2]],
	Biome.FUNGAL: [["giant_mushroom", 0.85], ["dead_tree", 0.15]],
}
## Base tree density per biome (0..1 chance per placement attempt).
const BIOME_TREE_DENSITY := {
	Biome.MEADOW: 0.07, Biome.FOREST: 0.6, Biome.AUTUMN: 0.38, Biome.DRYLANDS: 0.06,
	Biome.TAIGA: 0.55, Biome.MARSH: 0.22, Biome.DESERT: 0.06,
	Biome.JUNGLE: 0.75, Biome.TUNDRA: 0.04, Biome.BADLANDS: 0.04, Biome.FUNGAL: 0.4,
}
const BIOME_BUSHES := {
	Biome.MEADOW: [["bush", 0.4], ["berry", 0.35], ["flower_bush", 0.25]],
	Biome.FOREST: [["bush", 0.7], ["berry", 0.3]],
	Biome.AUTUMN: [["bush", 0.45], ["berry", 0.35], ["flower_bush", 0.2]],
	Biome.DRYLANDS: [["bush", 0.35], ["dead_bush", 0.35], ["agave", 0.3]],
	Biome.TAIGA: [["berry", 0.5], ["bush", 0.5]],
	Biome.MARSH: [["reeds", 0.75], ["bush", 0.25]],
	Biome.DESERT: [["dead_bush", 0.4], ["agave", 0.35], ["small_cactus", 0.25]],
	Biome.JUNGLE: [["jungle_plant", 0.55], ["flower_bush", 0.25], ["berry", 0.2]],
	Biome.TUNDRA: [["dead_bush", 0.5], ["berry", 0.3], ["bush", 0.2]],
	Biome.BADLANDS: [["dead_bush", 0.5], ["agave", 0.3], ["small_cactus", 0.2]],
	Biome.FUNGAL: [["glowcap", 0.7], ["jungle_plant", 0.15], ["bush", 0.15]],
}
const BIOME_BUSH_DENSITY := {
	Biome.MEADOW: 0.25, Biome.FOREST: 0.35, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.4,
	Biome.TAIGA: 0.3, Biome.MARSH: 0.75, Biome.DESERT: 0.3,
	Biome.JUNGLE: 0.75, Biome.TUNDRA: 0.2, Biome.BADLANDS: 0.25, Biome.FUNGAL: 0.55,
}
## Small things on the ground that make places feel lived-in.
const BIOME_CLUTTER := {
	Biome.MEADOW: [["pebbles", 0.45], ["stump", 0.15], ["mushroom", 0.15], ["herb", 0.12], ["branch", 0.15], ["sapling", 0.12], ["cache", 0.015]],
	Biome.FOREST: [["log", 0.25], ["stump", 0.2], ["mushroom", 0.25], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.25], ["sapling", 0.15], ["cache", 0.015]],
	Biome.AUTUMN: [["log", 0.25], ["mushroom", 0.3], ["stump", 0.15], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.25], ["cache", 0.015]],
	Biome.DRYLANDS: [["pebbles", 0.35], ["boulder", 0.2], ["scree", 0.2], ["tumbleweed", 0.15], ["branch", 0.1], ["cache", 0.02]],
	Biome.TAIGA: [["log", 0.3], ["stump", 0.2], ["mushroom", 0.15], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.2], ["sapling", 0.12], ["scree", 0.08], ["cache", 0.015]],
	Biome.MARSH: [["log", 0.4], ["mushroom", 0.45], ["stump", 0.15], ["herb", 0.15], ["cache", 0.015]],
	Biome.DESERT: [["pebbles", 0.3], ["boulder", 0.3], ["scree", 0.15], ["tumbleweed", 0.2], ["small_cactus", 0.2], ["cache", 0.03]],
	Biome.JUNGLE: [["log", 0.35], ["mushroom", 0.2], ["herb", 0.2], ["stump", 0.1], ["branch", 0.2], ["sapling", 0.15], ["cache", 0.015]],
	Biome.TUNDRA: [["ice_rock", 0.35], ["pebbles", 0.25], ["scree", 0.2], ["boulder", 0.15], ["branch", 0.05], ["cache", 0.02]],
	Biome.BADLANDS: [["boulder", 0.3], ["scree", 0.3], ["pebbles", 0.2], ["tumbleweed", 0.15], ["cache", 0.025]],
	Biome.FUNGAL: [["mushroom", 0.55], ["log", 0.2], ["herb", 0.1], ["stump", 0.1], ["cache", 0.02]],
}
const BIOME_CLUTTER_DENSITY := {
	Biome.MEADOW: 0.2, Biome.FOREST: 0.55, Biome.AUTUMN: 0.45, Biome.DRYLANDS: 0.3,
	Biome.TAIGA: 0.5, Biome.MARSH: 0.45, Biome.DESERT: 0.3,
	Biome.JUNGLE: 0.55, Biome.TUNDRA: 0.35, Biome.BADLANDS: 0.3, Biome.FUNGAL: 0.6,
}
## How much grass / ferns grow per biome (0..1).
const BIOME_GRASS := {
	Biome.MEADOW: 1.0, Biome.FOREST: 0.7, Biome.AUTUMN: 0.85, Biome.DRYLANDS: 0.8,
	Biome.TAIGA: 0.45, Biome.MARSH: 0.55, Biome.DESERT: 0.0,
	Biome.JUNGLE: 0.9, Biome.TUNDRA: 0.25, Biome.BADLANDS: 0.1, Biome.FUNGAL: 0.3,
}
const BIOME_TALL_GRASS := {
	Biome.MEADOW: 0.35, Biome.FOREST: 0.05, Biome.AUTUMN: 0.25, Biome.DRYLANDS: 1.0,
	Biome.TAIGA: 0.1, Biome.MARSH: 0.3, Biome.DESERT: 0.08,
	Biome.JUNGLE: 0.4, Biome.TUNDRA: 0.35, Biome.BADLANDS: 0.2, Biome.FUNGAL: 0.0,
}
const BIOME_CLOVER := {
	Biome.MEADOW: 0.8, Biome.FOREST: 0.6, Biome.AUTUMN: 0.5, Biome.DRYLANDS: 0.0,
	Biome.TAIGA: 0.3, Biome.MARSH: 0.4, Biome.DESERT: 0.0,
	Biome.JUNGLE: 0.3, Biome.TUNDRA: 0.0, Biome.BADLANDS: 0.0, Biome.FUNGAL: 0.5,
}
const BIOME_FERNS := {
	Biome.MEADOW: 0.0, Biome.FOREST: 0.8, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.0,
	Biome.TAIGA: 0.6, Biome.MARSH: 0.7, Biome.DESERT: 0.0,
	Biome.JUNGLE: 1.0, Biome.TUNDRA: 0.0, Biome.BADLANDS: 0.0, Biome.FUNGAL: 0.4,
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
	"tall_grass": {"category": "fern", "label": "", "variants": 3, "solid": false, "hp": 0},
	"clover": {"category": "grass", "label": "", "variants": 2, "solid": false, "hp": 0},
	"palm": {"category": "tree", "label": "Palm", "variants": 3, "solid": true, "hp": 90, "target": "tree", "yield": "tree", "shape": "tree"},
	"sapling": {"category": "clutter", "label": "Sapling", "variants": 3, "solid": false, "hp": 20, "target": "tree", "yield": "dead_bush", "shape": "small"},
	"flower_bush": {"category": "bush", "label": "Flowering shrub", "variants": 3, "solid": false, "hp": 40, "target": "bush", "yield": "bush", "shape": "bush"},
	"agave": {"category": "bush", "label": "Agave", "variants": 2, "solid": false, "hp": 30, "target": "bush", "yield": "reeds", "shape": "bush"},
	"small_cactus": {"category": "clutter", "label": "Barrel cactus", "variants": 2, "solid": true, "hp": 30, "target": "bush", "yield": "cactus", "shape": "small"},
	"tumbleweed": {"category": "clutter", "label": "Tumbleweed", "variants": 2, "solid": false, "hp": 10, "target": "bush", "yield": "dead_bush", "shape": "small"},
	"branch": {"category": "clutter", "label": "Fallen branch", "variants": 3, "solid": false, "hp": 10, "target": "bush", "yield": "dead_bush", "shape": "small"},
	"scree": {"category": "clutter", "label": "Scree", "variants": 2, "solid": false, "hp": 20, "target": "rock", "yield": "pebbles", "shape": "small"},
	# Added with the jungle, tundra, badlands and fungal grove (kept last so older worlds don't change).
	"jungle_tree": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 140, "target": "tree", "yield": "tree", "shape": "tree"},
	"giant_mushroom": {"category": "tree", "label": "Giant mushroom", "variants": 3, "solid": true, "hp": 70, "target": "tree", "yield": "giant_mushroom", "shape": "tree"},
	"jungle_plant": {"category": "bush", "label": "Broadleaf", "variants": 2, "solid": false, "hp": 30, "target": "bush", "yield": "bush", "shape": "bush"},
	"glowcap": {"category": "bush", "label": "Glowcaps", "variants": 3, "solid": false, "hp": 20, "target": "bush", "yield": "mushroom", "shape": "bush"},
	"ice_rock": {"category": "rock", "label": "Ice-crusted stone", "variants": 2, "solid": true, "hp": 170, "target": "rock", "yield": "rock", "shape": "rock"},
}

## Fade-out distance per category (0 = always visible; trees are handled by chunk detail levels).
const VIS_RANGE := {"tree": 0.0, "bush": 150.0, "rock": 260.0, "clutter": 110.0, "grass": 60.0, "flower": 55.0, "fern": 75.0}
## Collider height offsets per shape.
const SHAPE_LIFT := {"tree": 2.0, "rock": 0.25, "bush": 0.6, "log": 0.35, "stump": 0.35, "small": 0.2}

var meshes := {}         # built so far: "pine_0" -> ArrayMesh, "pine_0_lod" -> simpler ArrayMesh (see mesh())
var variants := {}       # "pine" -> ["pine_0", "pine_1", ...]
var species_names := {}  # "pine" -> "Ember Spire"
var shapes := {}         # shape name -> Shape3D

var foliage_material: ShaderMaterial
var grass_material: ShaderMaterial
var rock_material: ShaderMaterial
var terrain_material: ShaderMaterial

var _pal: WorldPalette
var _specs := {}          # mesh key -> {kind, index, seed, bare, detail}: what mesh() builds
var _base_detail := 1.0
var _bare := false   ## building the "already harvested" look

## Kinds that look different after being hand-harvested (the fruiting tree is added per world).
## Trees are built at this share of the model detail setting, whatever it is: they are the costliest flora to draw.
const TREE_DETAIL := 0.5
const BARE_KINDS := ["berry", "reeds", "agave", "glowcap", "giant_mushroom"]


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	_build_materials()
	_build_shapes()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	_base_detail = MeshKit.detail
	# Only the specs are made here; each mesh is built the first time something asks for it (see mesh()), so a
	# world doesn't pay for every flora mesh up front. The seeds are drawn in the same order as always.
	for kind: String in KINDS:
		var root: String = kind.trim_prefix("autumn_").trim_prefix("dead_")
		species_names[kind] = NameGen.species_name(rng, root)
		variants[kind] = []
		for i in KINDS[kind].variants:
			var key := "%s_%d" % [kind, i]
			var variant_seed := rng.randi()
			var detail := _base_detail * (TREE_DETAIL if KINDS[kind].category == "tree" else 1.0)
			_specs[key] = {"kind": kind, "index": i, "seed": variant_seed, "bare": false, "detail": detail}
			# Harvested look (same shape, same seed): bare bushes, fruitless trees, cut reeds.
			if kind in BARE_KINDS or kind == ItemDB.fruit_tree:
				_specs[key + "_bare"] = {"kind": kind, "index": i, "seed": variant_seed, "bare": true, "detail": detail}
			# Far-away twin: same shape (same seed), far fewer polygons.
			if KINDS[kind].category == "tree":
				_specs[key + "_lod"] = {"kind": kind, "index": i, "seed": variant_seed, "bare": false, "detail": _base_detail * TREE_DETAIL * 0.6}
			variants[kind].append(key)


## The mesh for a key ("pine_0", "pine_0_bare", "pine_0_lod"), built the first time it's asked for.
func mesh(key: String) -> ArrayMesh:
	if not meshes.has(key):
		var spec: Dictionary = _specs[key]
		var kept_detail := MeshKit.detail
		var kept_bare := _bare
		MeshKit.detail = spec.detail
		_bare = spec.bare
		meshes[key] = _build_mesh(spec.kind, spec.index, spec.seed)
		MeshKit.detail = kept_detail
		_bare = kept_bare
	return meshes[key]


## Build every mesh now, while the world loads. A single flora mesh can take ~100 ms, so building them on first
## use stalled play; loading is the one moment a stall is expected.
func prebuild() -> void:
	for key: String in _specs:
		mesh(key)


## Whether a mesh key exists (it may not be built yet).
func has_mesh(key: String) -> bool:
	return _specs.has(key)


func mesh_keys() -> Array:
	return _specs.keys()


static func category_of(kind: String) -> String:
	return KINDS[kind].category


static func kind_of_key(key: String) -> String:
	var k := key.trim_suffix("_lod")
	return k.substr(0, k.rfind("_"))


func display_name(kind: String) -> String:
	match kind:
		"log", "stump", "pebbles", "boulder", "cache", "branch", "scree", "tumbleweed":
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
		"tall_grass": _tall_grass(kit, rng)
		"clover": _clover(kit, rng)
		"palm": _palm(kit, rng)
		"sapling": _sapling(kit, rng)
		"flower_bush": _flower_bush(kit, rng, _pal.flowers[index % _pal.flowers.size()])
		"agave": _agave(kit, rng)
		"small_cactus": _barrel_cactus(kit, rng)
		"tumbleweed": _tumbleweed(kit, rng)
		"branch": _branch(kit, rng)
		"scree": _scree(kit, rng)
		"jungle_tree": _jungle_tree(kit, rng)
		"giant_mushroom": _giant_mushroom(kit, rng, index)
		"jungle_plant": _jungle_plant(kit, rng)
		"glowcap": _glowcap(kit, rng, index)
		"ice_rock": _ice_rock(kit, rng)
	if kind == ItemDB.fruit_tree and not _bare:
		_add_fruit(kit, rng)
	var cat: String = KINDS[kind].category
	var mat: Material = foliage_material
	if cat == "rock" or kind in ["pebbles", "scree"]:
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
	TreeModels.conifer(kit, rng, _vary(_pal.bark, rng), _vary(leaf, rng), rng.randi_range(tiers_min, tiers_max), rng.randf_range(h_min, h_max), rng.randf_range(r_min, r_max))

func _oak(kit: MeshKit, rng: RandomNumberGenerator, leaf: Color) -> void:
	TreeModels.round_tree(kit, rng, _vary(_pal.bark, rng), _vary(leaf, rng), rng.randf_range(2.8, 3.8), rng.randf_range(0.3, 0.42), rng.randf_range(1.5, 1.9))

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
	TreeModels.birch(kit, rng, _pal.birch_bark, _vary(_pal.birch_leaves, rng), rng.randf_range(6.0, 8.5), rng.randf_range(0.15, 0.2))

## Weeping willow: a dome with long curtains of leaves hanging around it.
func _willow(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	# A willow: a slim, leaning trunk with forks under a low crown of leafy lumps.
	var h := rng.randf_range(3.6, 4.6)
	var trunk_r := rng.randf_range(0.26, 0.34)
	var bark := _vary(_pal.bark, rng).darkened(0.1)
	var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1))
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.55, trunk_r, h, 8), Transform3D(lean, Vector3(0, h * 0.5, 0)), bark, 0.08)
	# Two forks near the top, so the crown spreads from a few branches.
	for side in [-1.0, 1.0]:
		var fork_dir := Vector3(side * 0.55, 0.8, rng.randf_range(-0.2, 0.2)).normalized()
		var fork_basis := Basis(Vector3.UP.cross(fork_dir).normalized(), Vector3.UP.angle_to(fork_dir))   # turns the cylinder's up onto the fork
		kit.add_primitive(MeshKit.cylinder(trunk_r * 0.35, trunk_r * 0.6, 1.4, 6), Transform3D(fork_basis, Vector3(0, h * 0.82, 0) + fork_dir * 0.6), bark, 0.08)
	var leaf := _vary(_pal.willow_leaves, rng)
	var crown := Vector3(0, h + 0.2, 0)
	# Crown: a few lumps, not one blob.
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var d := rng.randf_range(0.4, 1.2)
		var at := crown + Vector3(cos(a) * d, rng.randf_range(-0.2, 0.5), sin(a) * d)
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.9, 1.25), 9, 6), Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), at), leaf.lightened(rng.randf_range(-0.04, 0.06)), 0.3, 0.07, crown)

## Savanna tree: leaning trunk splitting into branches with flat, wide canopy layers.
func _acacia(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.umbrella(kit, rng, _vary(_pal.bark, rng).lightened(0.05), _vary(_pal.acacia_leaves, rng), rng.randf_range(3.5, 5.0), rng.randf_range(0.22, 0.3))

## Bare, weathered tree.
func _dead_tree(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.dead(kit, rng, _vary(_pal.dead_wood, rng), rng.randf_range(3.5, 6.0), rng.randf_range(0.2, 0.3))

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


## Hang fruit on the outside of a canopy: pick points from the upper part of the mesh built so far.
func _add_fruit(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var top := -1e9
	var bottom := 1e9
	for v in kit.verts:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	var col: Color = ItemDB.info("fruit").get("color", Color(0.9, 0.3, 0.2))
	var placed := 0
	var tries := 0
	while placed < 10 and tries < 400:
		tries += 1
		var v: Vector3 = kit.verts[rng.randi() % kit.verts.size()]
		var t := (v.y - bottom) / maxf(top - bottom, 0.01)
		if t < 0.45 or t > 0.85 or Vector2(v.x, v.z).length() < 0.6:
			continue
		var out := Vector3(v.x, 0, v.z).normalized() * 0.06
		kit.add_primitive(MeshKit.sphere(0.12, 7, 5), Transform3D(Basis.from_scale(Vector3(1, 1.1, 1)), v + out - Vector3(0, 0.06, 0)), col.lightened(rng.randf_range(-0.08, 0.08)), 0.0, 0.04)
		placed += 1


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
	# A few woody stems at the base, so it reads as a shrub and not a mossy rock.
	var stem := _vary(_pal.bark, rng).lightened(0.05)
	for i in 4:
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.35, rng.randf_range(0.45, 0.7), sin(a) * 0.35)
		kit.loft([Vector3(cos(a) * 0.05, -0.05, sin(a) * 0.05), tip * 0.5 + Vector3(0, 0.05, 0), tip], [0.035, 0.025, 0.012], 5, stem)
	# Several smaller leaf masses of different sizes make a lumpier, more natural silhouette.
	var blobs := []
	for i in rng.randi_range(5, 7):
		var r := rng.randf_range(0.32, 0.55)
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.5)
		var pos := Vector3(cos(a) * d, r * 0.75 + rng.randf_range(0.0, 0.3), sin(a) * d)
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(-0.06, 0.07)), r * 0.3, 0.08, center)
	_leaf_clumps(kit, rng, blobs, center, leaf, rng.randi_range(8, 11), 0.15)
	if berries and not _bare:
		for i in rng.randi_range(12, 16):
			var blob: Array = blobs[rng.randi() % blobs.size()]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			kit.add_primitive(MeshKit.sphere(0.075, 6, 4), Transform3D(Basis(), blob[0] + dir * blob[1] * 0.97), _pal.berry.lightened(rng.randf_range(-0.08, 0.1)), 0.0, 0.04)


func _reeds(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(_pal.reed, rng)
	for i in rng.randi_range(14, 22):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.6)
		var base := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var tip := base + lean + Vector3.UP * rng.randf_range(0.9, 1.7) * (0.3 if _bare else 1.0)   # cut: stubble
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
		# Chunky ore nuggets sitting in the rock's top and shoulders, each a little faceted lump.
		for i in rng.randi_range(5, 7):
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.0), rng.randf_range(-1, 1)).normalized()
			var size := rng.randf_range(0.3, 0.42)
			var pos := Vector3(dir.x * squash.x, dir.y * squash.y, dir.z * squash.z) * 0.95 + Vector3(0, 0.25, 0)
			var tilt := Basis(Quaternion(Vector3.UP, dir))
			kit.add_primitive(MeshKit.sphere(size, 6, 4), Transform3D(tilt.scaled(Vector3(1.0, 0.7, 1.0)), pos),
				_vary(ore_color, rng, 0.05).lightened(rng.randf_range(0.0, 0.12)), 0.0, 0.05)


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


## Fallen log: a gnarled lofted trunk with bark ridges, a broken end, moss and shelf fungi.
func _log(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(2.6, 3.6)
	var r := rng.randf_range(0.26, 0.36)
	var bark := _vary(_pal.bark, rng)
	var path: Array = []
	var radii: Array = []
	var steps := 9
	for i in steps + 1:
		var t := float(i) / steps
		path.append(Vector3(lerpf(-length * 0.5, length * 0.5, t), r * 0.85 + sin(t * 3.0) * 0.03, sin(t * 2.3 + 1.0) * 0.08))
		radii.append(r * lerpf(1.05, 0.85, t))
	var ridges := func(t: float, a: float) -> Color:
		return bark.darkened(0.15) if fposmod(a * 2.2 + t * 1.5, 1.0) < 0.28 else bark
	kit.loft(path, radii, 12, bark, ridges, Callable(), true, true)
	# Clean cut at one end (pale rings), jagged break at the other.
	var rings := func(t: float, a: float) -> Color:
		return Color(0.8, 0.66, 0.46).darkened(0.1 * (int(t * 4.0) % 2))
	kit.loft([path[0] - Vector3(0.02, 0, 0), path[0]], [r * 0.9, r * 1.05], 10, Color(0.8, 0.66, 0.46), rings, Callable(), true, false)
	var tip: Vector3 = path[steps]
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf()
		var off: Vector3 = Vector3(0, cos(a), sin(a)) * float(radii[steps]) * 0.6
		kit.loft([tip + off, tip + off + Vector3(rng.randf_range(0.08, 0.2), 0, 0)], [radii[steps] * 0.35, 0.01], 5, Color(0.72, 0.58, 0.4))
	# Moss on top.
	var moss := _vary(_pal.moss, rng)
	kit.loft([path[2] + Vector3(0, r * 0.8, 0), path[5] + Vector3(0, r * 0.82, 0)], [r * 0.45, r * 0.5], 8, moss, Callable(),
		func(t: float, a: float) -> Vector2: return Vector2(1.0, 0.35), true, true, 0.02)
	# Shelf fungi on the side.
	for i in rng.randi_range(2, 4):
		var at: Vector3 = path[rng.randi_range(2, steps - 2)]
		var shelf := PackedVector2Array()
		for j in 9:
			var a := PI * j / 8.0
			shelf.append(Vector2(cos(a) * 0.11, sin(a) * 0.08))
		kit.extrude(shelf, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, 0.0), at + Vector3(0, -r * 0.1 + i * 0.05, r * 0.95)), 0.03, 0.012, Color(0.85, 0.72, 0.5), Color(0.95, 0.88, 0.7), 0.4)


## Stump: flaring base, pale cut top with rings, roots curving into the ground.
func _stump(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.36, 0.48)
	var h := rng.randf_range(0.45, 0.8)
	var bark := _vary(_pal.bark, rng)
	var path: Array = []
	var radii: Array = []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(0, t * h, 0))
		radii.append(r * (1.0 + pow(1.0 - t, 3.0) * 0.45))
	var ridges := func(t: float, a: float) -> Color:
		return bark.darkened(0.15) if fposmod(a * 2.5, 1.0) < 0.25 else bark
	# Closed trunk (no see-through rim), with the cut face sitting flush on top of it.
	kit.loft(path, radii, 14, bark, ridges, Callable(), true, true)
	var top_rings := func(t: float, a: float) -> Color:
		return Color(0.8, 0.66, 0.46) if int(t * 6.0) % 2 == 0 else Color(0.7, 0.55, 0.38)
	var cap: Array = []
	var cap_r: Array = []
	for i in 7:
		var t := i / 6.0
		cap.append(Vector3(0, h + 0.004 + sin(t * PI * 0.5) * 0.012, 0))
		cap_r.append(lerpf(float(radii[radii.size() - 1]) * 0.97, 0.002, t))
	kit.loft(cap, cap_r, 14, Color(0.8, 0.66, 0.46), top_rings, Callable(), true, true)
	for i in rng.randi_range(3, 5):
		var a := TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var root := [d * r * 0.7 + Vector3(0, h * 0.25, 0), d * r * 1.3 + Vector3(0, 0.08, 0), d * r * 1.9 + Vector3(0, -0.05, 0)]
		# Roots flare out from the trunk base and sink into the ground: closed at both ends.
		var root_path: Array = [d * r * 0.5 + Vector3(0, h * 0.12, 0), d * r * 1.2 + Vector3(0, 0.02, 0), d * r * 1.9 + Vector3(0, -0.08, 0)]
		kit.loft(root_path, [r * 0.3, r * 0.17, r * 0.06], 7, bark.darkened(0.05), Callable(), Callable(), true, true, 0.01)


func _mushrooms(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	_mushroom_cluster(kit, rng, Vector3.ZERO, 1.0, _pal.mushroom_caps[index % _pal.mushroom_caps.size()])


## Lofted mushrooms: bulging stems and domed caps with spots.
func _mushroom_cluster(kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, scale: float, cap: Color) -> void:
	for i in rng.randi_range(3, 6):
		var p := at + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * scale
		var h := rng.randf_range(0.09, 0.24) * scale
		var r := rng.randf_range(0.05, 0.11) * scale
		var lean := Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.02, 0.02)) * scale
		kit.loft([p, p + Vector3(0, h * 0.5, 0) + lean * 0.5, p + Vector3(0, h, 0) + lean], [r * 0.45, r * 0.32, r * 0.35], 7, Color(0.93, 0.89, 0.8))
		var top := p + Vector3(0, h, 0) + lean
		var path: Array = []
		var radii: Array = []
		for k in 7:
			var t := k / 6.0
			path.append(top + Vector3(0, -r * 0.15 + sin(t * PI * 0.5) * r * 0.65, 0))
			radii.append(cos(t * PI * 0.5) * r + 0.002)
		var seed_f := rng.randf() * 10.0
		var spots := func(t: float, a: float) -> Color:
			return Color(0.97, 0.95, 0.9) if t > 0.25 and fposmod(a * 2.9 + t * 5.0 + seed_f, 1.0) < 0.13 else cap
		kit.loft(path, radii, 12, cap, spots, Callable(), true, true)


## Angular, half-buried stones of different sizes.
func _pebbles(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.flat_shading = true
	for i in rng.randi_range(4, 7):
		var r := rng.randf_range(0.06, 0.2)
		var p := Vector3(rng.randf_range(-0.45, 0.45), r * 0.15, rng.randf_range(-0.45, 0.45))
		kit.add_primitive(MeshKit.sphere(r, 6, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.55, 1.0)), p), _vary(_pal.pebble, rng, 0.08), r * 0.3, 0.05)
	kit.flat_shading = false


## Scree: a heap of broken, angular rock.
func _scree(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.flat_shading = true
	for i in rng.randi_range(8, 12):
		var r := rng.randf_range(0.12, 0.3)
		var d := rng.randf_range(0.0, 0.7)
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * d, r * 0.3 + (0.7 - d) * 0.25, sin(a) * d)
		kit.add_primitive(MeshKit.sphere(r, 5, 3), Transform3D(Basis(Vector3(rng.randf(), 1, rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(1.2, 0.7, 1.0)), p), _vary(_pal.rock, rng, 0.07), r * 0.25, 0.06)
	kit.flat_shading = false


## Fallen branch: a crooked lofted stick with a fork and a few dry leaves.
func _branch(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var wood := _vary(_pal.bark, rng).lightened(0.05)
	var length := rng.randf_range(1.0, 1.6)
	var path: Array = []
	var radii: Array = []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(lerpf(-length * 0.5, length * 0.5, t), 0.05 + sin(t * 4.0) * 0.02, sin(t * 5.0 + rng.randf()) * 0.08))
		radii.append(lerpf(0.05, 0.018, t))
	kit.loft(path, radii, 6, wood, Callable(), Callable(), true, true, 0.006)
	var fork_at: Vector3 = path[3]
	var fork_dir := Vector3(0.6, 0.15, rng.randf_range(-0.8, 0.8)).normalized()
	kit.loft([fork_at, fork_at + fork_dir * length * 0.3, fork_at + fork_dir * length * 0.45 + Vector3(0, -0.04, 0)], [0.025, 0.015, 0.006], 5, wood)
	for i in rng.randi_range(2, 4):
		var at: Vector3 = path[rng.randi_range(3, 6)]
		_flat_leaf(kit, at + Vector3(0, 0.02, 0), Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)), 0.09, _pal.autumn_leaves[i % _pal.autumn_leaves.size()].darkened(0.2))


## A young tree: thin bent stem and a few soft leaf clusters.
func _sapling(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(0.8, 1.5)
	var leaf := _vary(_pal.oak_leaves, rng).lightened(0.08)
	kit.loft([Vector3.ZERO, Vector3(0.03, h * 0.5, 0.0), Vector3(-0.02, h, 0.03)], [0.025, 0.018, 0.01], 6, _pal.bark.lightened(0.1))
	var center := Vector3(0, h, 0)
	for i in rng.randi_range(3, 4):
		var p := center + Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.2, 0.1), rng.randf_range(-0.18, 0.18))
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.14, 0.22), 7, 5), Transform3D(Basis(), p), leaf.lightened(rng.randf_range(-0.05, 0.05)), 0.04, 0.06, center)


## Palm: curved, ringed trunk with arching fronds and coconuts.
func _palm(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(5.0, 7.5)
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.8, 1.6)
	var path: Array = []
	var radii: Array = []
	for i in 9:
		var t := i / 8.0
		path.append(Vector3(0, t * h, 0) + lean * t * t)
		radii.append(lerpf(0.26, 0.15, t))
	var trunk := Color(0.62, 0.5, 0.36)
	var bands := func(t: float, a: float) -> Color:
		return trunk.darkened(0.18) if fposmod(t * 22.0, 1.0) < 0.3 else trunk
	kit.loft(path, radii, 9, trunk, bands, Callable(), true, true, 0.01)
	var top: Vector3 = path[8]
	var leaf := _vary(_pal.oak_leaves, rng).lightened(0.05)
	var leaf_dark := leaf.darkened(0.18)
	# Fronds: broad arching blades, each with a comb of leaflets down both sides.
	var fronds := rng.randi_range(10, 13)
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := rng.randf_range(2.6, 3.4)
		var prev := top
		var segs := 9
		for sgm in segs:
			var t := float(sgm + 1) / segs
			var p := top + dir * length * t + Vector3.UP * (sin(t * PI * 0.7) * 0.7 - t * t * 1.5)
			var w := (sin(t * PI * 0.9 + 0.2) * 0.62 + 0.12) * (1.0 - t * 0.3) * (0.85 + 0.2 * sin(sgm * 2.7 + f))
			var c := leaf.darkened(t * 0.12)
			var lo := prev + side * w + dir * 0.1 - Vector3.UP * 0.14
			var ro := prev - side * w + dir * 0.1 - Vector3.UP * 0.14
			kit.add_tri(prev, p, lo, c)
			kit.add_tri(prev, ro, p, c)
			kit.add_tri(prev, lo, p, c)
			kit.add_tri(prev, p, ro, c)
			# Leaflets: little slanted blades off the midrib, hanging down the frond's edge.
			if sgm > 0 and sgm < segs - 1:
				for sd: float in [-1.0, 1.0]:
					var tip: Vector3 = p + side * sd * (0.55 + 0.3 * (1.0 - t)) + Vector3.DOWN * (0.25 + 0.25 * t)
					var base_a := p - dir * 0.05
					var base_b := p + dir * 0.18
					kit.add_tri(base_a, tip, base_b, leaf_dark)
					kit.add_tri(base_a, base_b, tip, leaf_dark)
			prev = p
	# Coconuts clustered under the crown.
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		kit.add_primitive(MeshKit.sphere(0.13, 8, 6), Transform3D(Basis(), top + Vector3(cos(a) * 0.22, -0.25, sin(a) * 0.22)), Color(0.42, 0.3, 0.18), 0.02, 0.05)


## Flowering shrub: soft leafy mound dotted with five-petal flowers.
func _flower_bush(kit: MeshKit, rng: RandomNumberGenerator, petal: Color) -> void:
	_bush(kit, rng, false)
	for i in rng.randi_range(10, 14):
		var a := rng.randf() * TAU
		var up := rng.randf_range(0.2, 1.0)
		var dir := Vector3(cos(a) * (1.0 - up * 0.6), up, sin(a) * (1.0 - up * 0.6)).normalized()
		var at := Vector3(0, 0.45, 0) + dir * rng.randf_range(0.6, 0.8)
		var flower := PackedVector2Array()
		for k in 8:
			var ang := TAU * k / 8.0
			var rr := 0.13 if k % 2 == 0 else 0.05
			flower.append(Vector2(cos(ang), sin(ang)) * rr)
		kit.extrude(flower, Transform3D(Basis(Quaternion(Vector3.FORWARD, dir)), at), 0.012, 0.006, _vary(petal, rng, 0.05), petal.lightened(0.3), 0.5)
		kit.add_primitive(MeshKit.sphere(0.035, 5, 3), Transform3D(Basis(), at + dir * 0.015), Color(0.98, 0.85, 0.35), 0.0, 0.0)


## Agave: a rosette of thick, pointed leaves curving outward.
func _agave(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := Color.from_hsv(fposmod(_pal.cactus.h + 0.05, 1.0), 0.32, 0.62)
	var leaves := rng.randi_range(10, 14)
	for i in leaves:
		var a := TAU * i / leaves + rng.randf_range(-0.1, 0.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(0.6, 1.0) * (1.0 if i % 2 == 0 else 0.8) * (0.55 if _bare and i % 2 == 0 else 1.0)
		var rise := rng.randf_range(0.6, 1.1)
		var path := [Vector3.ZERO + dir * 0.05, dir * length * 0.4 + Vector3.UP * rise * 0.5, dir * length * 0.8 + Vector3.UP * rise * 0.75, dir * length + Vector3.UP * rise * 0.7]
		kit.loft(path, [0.07, 0.06, 0.035, 0.0], 6, col.lightened(rng.randf_range(-0.05, 0.08)), func(t: float, aa: float) -> Color:
			return col.lightened(0.25) if absf(sin(aa)) > 0.9 else col,
			func(t: float, aa: float) -> Vector2: return Vector2(1.0, 0.35), true, false)


## Barrel cactus: ribbed squat body with a ring of flowers on top.
func _barrel_cactus(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.cactus, rng)
	var h := rng.randf_range(0.35, 0.6)
	var r := rng.randf_range(0.2, 0.3)
	var path: Array = []
	var radii: Array = []
	for i in 8:
		var t := i / 7.0
		path.append(Vector3(0, t * h, 0))
		radii.append(r * (0.75 + sin(t * PI * 0.85) * 0.3) * (1.0 if t < 0.95 else 0.4))
	kit.loft(path, radii, 16, col, func(t: float, a: float) -> Color:
		return col.darkened(0.18) if sin(a * 10.0) < -0.3 else col,
		func(t: float, a: float) -> Vector2: return Vector2.ONE * (1.0 + sin(a * 10.0) * 0.08), false, true)
	for i in 5:
		var a := TAU * i / 5.0
		kit.add_primitive(MeshKit.sphere(0.04, 6, 4), Transform3D(Basis(), Vector3(cos(a) * r * 0.25, h * 0.98, sin(a) * r * 0.25)), _pal.flowers[1], 0.0, 0.04)


## Tumbleweed: a loose ball of dry, curling twigs.
func _tumbleweed(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.dead_wood, rng).lightened(0.05)
	var r := rng.randf_range(0.35, 0.5)
	var center := Vector3(0, r * 0.85, 0)
	for i in 22:
		var a1 := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var a2 := (a1 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.9).normalized()
		var mid := (a1 + a2).normalized() * 1.05
		kit.loft([center + a1 * r, center + mid * r, center + a2 * r], [0.014, 0.018, 0.008], 4, col.darkened(rng.randf() * 0.15), Callable(), Callable(), false, false)


## Tall grass with seed heads (savanna and meadows).
func _tall_grass(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _pal.dry_grass.lightened(0.05)
	for i in rng.randi_range(9, 14):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.25)
		var base := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.3)
		var h := rng.randf_range(0.8, 1.3)
		var mid := base + lean * 0.4 + Vector3.UP * h * 0.55
		var tip := base + lean + Vector3.UP * h
		var side := Vector3(-sin(a), 0, cos(a)) * 0.025
		kit.add_tri(base - side, base + side, mid, col.darkened(0.3), col.darkened(0.3), col)
		kit.add_tri(mid - side * 0.6, mid + side * 0.6, tip, col, col, col.lightened(0.15))
		if rng.randf() < 0.5:   # seed head
			var seed_col := col.lightened(0.2)
			kit.add_tri(tip - side * 1.4 - Vector3.UP * 0.12, tip + side * 1.4 - Vector3.UP * 0.12, tip + Vector3.UP * 0.03, seed_col)


## Clover: low trefoil leaves.
func _clover(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := Color(0.9, 0.9, 0.9)   # tinted by the ground color under it
	for i in rng.randi_range(5, 8):
		var base := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.03, 0.08), rng.randf_range(-0.2, 0.2))
		for l in 3:
			var a := TAU * l / 3.0 + rng.randf()
			var c := base + Vector3(cos(a), 0, sin(a)) * 0.035
			for k in 6:
				var a1 := TAU * k / 6.0
				var a2 := TAU * (k + 1) / 6.0
				kit.add_tri(c, c + Vector3(cos(a1), 0.0, sin(a1)) * 0.035, c + Vector3(cos(a2), 0.0, sin(a2)) * 0.035, col.lightened(0.05), col, col)


## Flat leaf (used on branches).
func _flat_leaf(kit: MeshKit, base: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(length * 0.3, length * 0.3), Vector2(0, length), Vector2(-length * 0.3, length * 0.3)])
	kit.extrude(outline, Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), base), 0.004, 0.002, col, col.lightened(0.1), 0.5)


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


# --- Jungle, tundra, badlands, fungal grove -------------------------------------------

## Tall rainforest tree: buttress roots, a straight pale trunk, a broad layered crown and vines.
func _jungle_tree(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.jungle(kit, rng, _vary(_pal.bark, rng).lightened(0.18), _vary(_pal.jungle_leaves, rng), rng.randf_range(11.0, 16.0), rng.randf_range(0.32, 0.42))

## A mushroom the size of a tree: a pale swollen stem and a broad domed cap with spots and gills.
func _giant_mushroom(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var h := rng.randf_range(4.5, 8.0)
	var stem_r := rng.randf_range(0.35, 0.55)
	var stem := _vary(_pal.fungal_stem, rng)
	var bend := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	var path := []
	var radii := []
	for i in 9:
		var t := i / 8.0
		path.append(Vector3(0, t * h, 0) + bend * sin(t * PI * 0.5))
		radii.append(stem_r * (1.35 - t * 0.5 + 0.25 * exp(-pow((t - 0.05) / 0.08, 2.0))))
	kit.loft(path, radii, 12, stem, func(t: float, _a: float) -> Color: return stem.darkened(0.1 * (1.0 - t)), Callable(), true, true, 0.04)
	var top: Vector3 = path[-1]
	var cap_col: Color = _vary(_pal.fungal_caps[index % _pal.fungal_caps.size()], rng)
	var cap_r := rng.randf_range(2.4, 3.6)
	if _bare:
		cap_r *= 0.7   # harvested: the frilly rim is gone
	# Gill underside
	kit.add_primitive(MeshKit.cylinder(cap_r * 0.95, stem_r * 0.8, cap_r * 0.25, 22), Transform3D(Basis(), top + Vector3(0, -cap_r * 0.08, 0)), cap_col.lerp(stem, 0.6).darkened(0.1), 0.0, 0.05)
	# Cap dome
	var cap_path := []
	var cap_radii := []
	for k in 9:
		var t := k / 8.0
		cap_path.append(top + Vector3(0, sin(t * PI * 0.5) * cap_r * 0.55, 0))
		cap_radii.append(cos(t * PI * 0.5) * cap_r + 0.02)
	var seed_f := rng.randf() * 10.0
	var spot := _pal.glow
	var spots := func(t: float, a: float) -> Color:
		return spot if t > 0.15 and t < 0.9 and fposmod(a * 2.3 + t * 4.0 + seed_f, 1.0) < 0.1 else cap_col
	kit.loft(cap_path, cap_radii, 22, cap_col, spots, Callable(), true, true, 0.06)


## Rainforest undergrowth: big drooping elephant-ear leaves.
func _jungle_plant(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := _vary(_pal.jungle_leaves_2, rng)
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var length := rng.randf_range(0.8, 1.4)
		var stem_top := Vector3(cos(a) * 0.35, rng.randf_range(0.5, 0.95), sin(a) * 0.35)
		kit.loft([Vector3(0, 0, 0), stem_top * 0.6 + Vector3(0, 0.15, 0), stem_top], [0.03, 0.025, 0.02], 5, leaf.darkened(0.15))
		var dir := Vector3(cos(a), rng.randf_range(-0.6, -0.1), sin(a)).normalized()
		var w := length * 0.42
		var outline := PackedVector2Array([Vector2(0, 0), Vector2(w * 0.8, length * 0.25), Vector2(w, length * 0.55), Vector2(w * 0.4, length * 0.9),
			Vector2(0, length), Vector2(-w * 0.4, length * 0.9), Vector2(-w, length * 0.55), Vector2(-w * 0.8, length * 0.25)])
		var b := Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3))
		kit.extrude(outline, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), stem_top), 0.02, 0.01, leaf.lightened(rng.randf_range(-0.04, 0.08)), leaf.lightened(0.18), 0.4)


## A ring of tall thin mushrooms with glowing caps (they light up the fungal grove at night).
func _glowcap(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var stem := _pal.fungal_stem
	var cap: Color = _pal.glow.lerp(_pal.fungal_caps[index % _pal.fungal_caps.size()], 0.25)
	for i in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.05, 0.5)
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := rng.randf_range(0.35, 0.9)
		var lean := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var top := base + Vector3(0, h, 0) + lean
		kit.loft([base, base + Vector3(0, h * 0.5, 0) + lean * 0.4, top], [0.035, 0.028, 0.025], 6, stem)
		if _bare:
			continue
		var r := rng.randf_range(0.08, 0.16)
		kit.add_primitive(MeshKit.sphere(r, 8, 4), Transform3D(Basis().scaled(Vector3(1, 0.55, 1)), top), cap, 0.0, 0.03)
		kit.add_primitive(MeshKit.sphere(r * 0.45, 5, 3), Transform3D(Basis(), top + Vector3(0, r * 0.25, 0)), cap.lightened(0.4), 0.0, 0.0)


## Frost-shattered boulder with a crust of ice and snow.
func _ice_rock(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.flat_shading = true
	var col := _vary(_pal.rock, rng, 0.05).lerp(_pal.ice, 0.25)
	var squash := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.7, 0.95), rng.randf_range(0.9, 1.2))
	var ice := _pal.ice
	var frost := func(p: Vector3) -> Color:
		return ice if p.y > 0.55 else (ice.lerp(col, 0.5) if p.y > 0.35 else col)
	kit.add_primitive(MeshKit.sphere(1.0, 9, 6), Transform3D(Basis().scaled(squash), Vector3(0, 0.25, 0)), col, 0.3, 0.06, null, frost)
	for i in rng.randi_range(2, 4):   # icicle-like shards on top
		var dir := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
		var base := Vector3(dir.x * squash.x * 0.6, 0.25 + squash.y * 0.7, dir.z * squash.z * 0.6)
		var length := rng.randf_range(0.3, 0.6)
		kit.add_primitive(MeshKit.cylinder(0.0, rng.randf_range(0.08, 0.14), length, 5), Transform3D(Basis(Quaternion(Vector3.UP, dir)), base + dir * length * 0.4), ice.lightened(0.1), 0.0, 0.03)
	kit.flat_shading = false
