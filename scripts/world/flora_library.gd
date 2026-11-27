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
	Biome.JUNGLE: [["jungle_tree", 0.72], ["kapok", 0.13], ["willow", 0.15]],   # no palms: they grow only on beaches (see ChunkGenerator)
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
	Biome.MEADOW: [["bush", 0.3], ["berry", 0.25], ["flower_bush", 0.2], ["bramble", 0.25]],
	Biome.FOREST: [["bush", 0.45], ["berry", 0.2], ["rhododendron", 0.2], ["bramble", 0.15]],
	Biome.AUTUMN: [["bush", 0.3], ["berry", 0.25], ["flower_bush", 0.15], ["bramble", 0.15], ["rhododendron", 0.15]],
	Biome.DRYLANDS: [["bush", 0.2], ["dead_bush", 0.25], ["agave", 0.2], ["sagebrush", 0.2], ["juniper", 0.15]],
	Biome.TAIGA: [["berry", 0.3], ["bush", 0.25], ["juniper", 0.25], ["heather", 0.2]],
	Biome.MARSH: [["reeds", 0.6], ["bush", 0.15], ["hibiscus", 0.25]],
	Biome.DESERT: [["dead_bush", 0.3], ["agave", 0.25], ["small_cactus", 0.15], ["ocotillo", 0.15], ["sagebrush", 0.15]],
	Biome.JUNGLE: [["jungle_plant", 0.45], ["flower_bush", 0.15], ["berry", 0.15], ["hibiscus", 0.25]],
	Biome.TUNDRA: [["dead_bush", 0.3], ["berry", 0.2], ["bush", 0.1], ["heather", 0.25], ["juniper", 0.15]],
	Biome.BADLANDS: [["dead_bush", 0.3], ["agave", 0.2], ["small_cactus", 0.15], ["ocotillo", 0.2], ["sagebrush", 0.15]],
	Biome.FUNGAL: [["glowcap", 0.55], ["jungle_plant", 0.1], ["bush", 0.1], ["spore_bush", 0.25]],
	Biome.HIGHLANDS: [["heather", 0.55], ["juniper", 0.45]],   # (bushes above the tree line: see ChunkGenerator)
}
const BIOME_BUSH_DENSITY := {
	Biome.MEADOW: 0.25, Biome.FOREST: 0.35, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.4,
	Biome.TAIGA: 0.3, Biome.MARSH: 0.75, Biome.DESERT: 0.3,
	Biome.JUNGLE: 0.75, Biome.TUNDRA: 0.2, Biome.BADLANDS: 0.25, Biome.FUNGAL: 0.55,
	Biome.HIGHLANDS: 0.2,
}
## Small things on the ground that make places feel lived-in.
const BIOME_CLUTTER := {
	Biome.MEADOW: [["pebbles", 0.45], ["stump", 0.15], ["mushroom", 0.15], ["herb", 0.12], ["branch", 0.15], ["sapling", 0.12], ["cache", 0.015], ["wild_garlic", 0.1]],
	Biome.FOREST: [["log", 0.25], ["stump", 0.2], ["mushroom", 0.25], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.25], ["sapling", 0.15], ["cache", 0.015], ["wild_garlic", 0.12]],
	Biome.AUTUMN: [["log", 0.25], ["mushroom", 0.3], ["stump", 0.15], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.25], ["cache", 0.015], ["wild_garlic", 0.08]],
	Biome.DRYLANDS: [["pebbles", 0.35], ["boulder", 0.2], ["scree", 0.2], ["tumbleweed", 0.15], ["branch", 0.1], ["cache", 0.02], ["aloe", 0.08]],
	Biome.TAIGA: [["log", 0.3], ["stump", 0.2], ["mushroom", 0.15], ["pebbles", 0.1], ["herb", 0.1], ["branch", 0.2], ["sapling", 0.12], ["scree", 0.08], ["cache", 0.015], ["lingonberry", 0.18]],
	Biome.MARSH: [["log", 0.4], ["mushroom", 0.45], ["stump", 0.15], ["herb", 0.15], ["cache", 0.015], ["cattail", 0.3]],
	Biome.DESERT: [["pebbles", 0.3], ["boulder", 0.3], ["scree", 0.15], ["tumbleweed", 0.2], ["small_cactus", 0.2], ["cache", 0.03], ["aloe", 0.15]],
	Biome.JUNGLE: [["mossy_log", 0.4], ["log", 0.15], ["mushroom", 0.2], ["herb", 0.2], ["stump", 0.1], ["branch", 0.15], ["sapling", 0.15], ["cache", 0.015]],
	Biome.TUNDRA: [["ice_rock", 0.35], ["pebbles", 0.25], ["scree", 0.2], ["boulder", 0.15], ["branch", 0.05], ["cache", 0.02], ["lingonberry", 0.2]],
	Biome.BADLANDS: [["boulder", 0.3], ["scree", 0.3], ["pebbles", 0.2], ["tumbleweed", 0.15], ["cache", 0.025], ["aloe", 0.1]],
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
## Each land's own ground plants (wildflowers, sedges, lichens...), grown in patches among the grass: [kind, weight].
## They share the ground cover's count with the grass and the old flowers (see ChunkGenerator), so the ground is as
## thick as before, only more varied.
const BIOME_GROUND := {
	Biome.MEADOW: [["lupin", 0.5], ["daisy", 0.5]],
	Biome.FOREST: [["foxglove", 0.6], ["daisy", 0.4]],
	Biome.AUTUMN: [["foxglove", 0.5], ["lupin", 0.5]],
	Biome.DRYLANDS: [["desert_bloom", 1.0]],
	Biome.TAIGA: [["cotton_grass", 0.4], ["sedge", 0.3], ["lichen", 0.3]],
	Biome.MARSH: [["sedge", 0.7], ["cotton_grass", 0.3]],
	Biome.DESERT: [["desert_bloom", 1.0]],
	Biome.JUNGLE: [["bromeliad", 1.0]],
	Biome.TUNDRA: [["lichen", 0.55], ["cotton_grass", 0.45]],
	Biome.BADLANDS: [["lichen", 0.4], ["desert_bloom", 0.6]],
	Biome.FUNGAL: [["puffball", 1.0]],
	Biome.BEACH: [["dune_grass", 0.65], ["sea_thrift", 0.35]],
	Biome.HIGHLANDS: [["alpine_cushion", 0.45], ["lichen", 0.35], ["edelweiss", 0.2]],
	Biome.SNOW: [["lichen", 1.0]],
}
const BIOME_GROUND_DENSITY := {
	Biome.MEADOW: 0.8, Biome.FOREST: 0.5, Biome.AUTUMN: 0.5, Biome.DRYLANDS: 0.4,
	Biome.TAIGA: 0.5, Biome.MARSH: 0.8, Biome.DESERT: 0.3,
	Biome.JUNGLE: 0.6, Biome.TUNDRA: 0.8, Biome.BADLANDS: 0.35, Biome.FUNGAL: 0.7,
	Biome.BEACH: 0.6, Biome.HIGHLANDS: 0.55, Biome.SNOW: 0.12,
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
	# Added with the cave dressing (last again).
	"stalagmite": {"category": "rock", "label": "Stalagmite", "variants": 3, "solid": true, "hp": 120, "target": "rock", "yield": "rock", "shape": "rock"},
	# Jungle undergrowth and the vines on rock faces (last again).
	"bamboo": {"category": "bush", "label": "Bamboo", "variants": 3, "solid": false, "hp": 50, "target": "tree", "yield": "bamboo", "shape": "bush"},
	"heliconia": {"category": "bush", "label": "Heliconia", "variants": 3, "solid": false, "hp": 30, "target": "bush", "yield": "bush", "shape": "bush"},
	"fern_palm": {"category": "bush", "label": "Fern palm", "variants": 3, "solid": false, "hp": 40, "target": "bush", "yield": "bush", "shape": "bush"},
	"cliff_vine": {"category": "bush", "label": "Vines", "variants": 3, "solid": false, "hp": 25, "target": "bush", "yield": "reeds", "shape": "small"},
	# The jungle's emergent giants, standing over its canopy (last again).
	"kapok": {"category": "tree", "label": "Giant tree", "variants": 3, "solid": true, "hp": 260, "target": "tree", "yield": "tree", "shape": "tree"},
	# The jungle floor: a fallen giant gone green with moss and ferns, and patches of wet mud (last again).
	"mossy_log": {"category": "clutter", "label": "Mossy log", "variants": 3, "solid": true, "hp": 90, "target": "tree", "yield": "log", "shape": "log"},
	"mud": {"category": "grass", "label": "", "variants": 3, "solid": false, "hp": 0},
	# More plants for every land (last again): shrubs, small plants worth gathering ("named": shown by their own
	# name, not a made-up species name), and each land's own ground plants.
	"heather": {"category": "bush", "label": "Heather", "variants": 3, "solid": false, "hp": 25, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"juniper": {"category": "bush", "label": "Juniper", "variants": 2, "solid": false, "hp": 40, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"sagebrush": {"category": "bush", "label": "Sagebrush", "variants": 2, "solid": false, "hp": 30, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"bramble": {"category": "bush", "label": "Bramble", "variants": 2, "solid": false, "hp": 30, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"rhododendron": {"category": "bush", "label": "Rhododendron", "variants": 3, "solid": false, "hp": 40, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"ocotillo": {"category": "bush", "label": "Ocotillo", "variants": 2, "solid": false, "hp": 30, "target": "bush", "yield": "dead_bush", "shape": "bush", "named": true},
	"hibiscus": {"category": "bush", "label": "Hibiscus", "variants": 3, "solid": false, "hp": 30, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"spore_bush": {"category": "bush", "label": "Sporebush", "variants": 3, "solid": false, "hp": 25, "target": "bush", "yield": "bush", "shape": "bush", "named": true},
	"cattail": {"category": "clutter", "label": "Cattails", "variants": 2, "solid": false, "hp": 10, "target": "bush", "yield": "reeds", "shape": "small", "named": true},
	"aloe": {"category": "clutter", "label": "Aloe", "variants": 2, "solid": false, "hp": 10, "target": "bush", "yield": "bush", "shape": "small", "named": true},
	"wild_garlic": {"category": "clutter", "label": "Wild Garlic", "variants": 2, "solid": false, "hp": 10, "target": "bush", "yield": "bush", "shape": "small", "named": true},
	"lingonberry": {"category": "clutter", "label": "Lingonberry", "variants": 2, "solid": false, "hp": 15, "target": "bush", "yield": "bush", "shape": "small", "named": true},
	"lupin": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
	"daisy": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"foxglove": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"sedge": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"desert_bloom": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
	"bromeliad": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"cotton_grass": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"lichen": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
	"puffball": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"dune_grass": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"sea_thrift": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
	"alpine_cushion": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
	"edelweiss": {"category": "flower", "label": "", "variants": 2, "solid": false, "hp": 0},
}

## The jungle's own layer of undergrowth, on top of its bushes (see ChunkGenerator): [kind, weight].
const JUNGLE_UNDERGROWTH := [["jungle_plant", 0.32], ["heliconia", 0.28], ["fern_palm", 0.24], ["bamboo", 0.16]]
## How green a place has to be for vines on its rock faces, per biome.
const VINE_BIOMES := {Biome.JUNGLE: 1.0, Biome.FOREST: 0.45, Biome.MARSH: 0.5, Biome.AUTUMN: 0.3, Biome.MEADOW: 0.2, Biome.TAIGA: 0.15}
## A vine curtain's model is this long; each one is stretched to the rock face it hangs on.
const VINE_LENGTH := 4.0

## Fade-out distance per category (0 = always visible; trees are handled by chunk detail levels).
const VIS_RANGE := {"tree": 0.0, "bush": 150.0, "rock": 260.0, "clutter": 110.0, "grass": 60.0, "flower": 55.0, "fern": 75.0}
## Collider height offsets per shape.
const SHAPE_LIFT := {"tree": 2.0, "rock": 0.25, "bush": 0.6, "log": 0.35, "stump": 0.35, "small": 0.2}

var meshes := {}         # built so far: "pine_0" -> ArrayMesh, "pine_0_lod" -> simpler ArrayMesh (see mesh())
var variants := {}       # "pine" -> ["pine_0", "pine_1", ...]
var species_names := {}  # "pine" -> "Ember Spire"
var shapes := {}         # shape name -> Shape3D
## Mesh key -> a couple of dozen points round the foot of the model (its lowest few cm, round the outline and
## halfway in), local to it. The chunks fit each thing to the ground by these (see ChunkGenerator._settle).
var feet := {}
## Mud key -> [verts, normals, colors] of its upward faces and rims (the underside never shows), for draping each
## patch over the ground it lies on (see ChunkGenerator._drape).
var drape_src := {}

var foliage_material: ShaderMaterial
var grass_material: ShaderMaterial
var rock_material: ShaderMaterial
var mud_material: ShaderMaterial   ## the grass look, held still (mud is draped over the ground, see drape_src)
var terrain_material: ShaderMaterial

var _pal: WorldPalette
var _specs := {}          # mesh key -> {kind, index, seed, bare, detail}: what mesh() builds
var _base_detail := 1.0
var _bare := false   ## building the "already harvested" look
var _lod := false    ## building a far-away twin (models with many small parts use fewer, bigger ones)

## Kinds that look different after being hand-harvested (the fruiting tree is added per world).
## Trees are built at this share of the model detail setting, whatever it is: they are the costliest flora to draw.
const TREE_DETAIL := 0.5
const BARE_KINDS := ["berry", "reeds", "agave", "glowcap", "giant_mushroom", "juniper", "bramble", "lingonberry"]


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
	# More shapes for the trees, so a forest doesn't repeat itself (drawn from their own seed after all the
	# others, so the shapes older worlds already have stay as they were).
	var more := RandomNumberGenerator.new()
	more.seed = seed_value * 53 + 11
	for kind: String in KINDS:
		var want := int(MORE_TREE_SHAPES.get(kind, 0))
		for i in range(KINDS[kind].variants, want):
			var key := "%s_%d" % [kind, i]
			var variant_seed := more.randi()
			var detail := _base_detail * TREE_DETAIL
			_specs[key] = {"kind": kind, "index": i, "seed": variant_seed, "bare": false, "detail": detail}
			if kind in BARE_KINDS or kind == ItemDB.fruit_tree:
				_specs[key + "_bare"] = {"kind": kind, "index": i, "seed": variant_seed, "bare": true, "detail": detail}
			_specs[key + "_lod"] = {"kind": kind, "index": i, "seed": variant_seed, "bare": false, "detail": _base_detail * TREE_DETAIL * 0.6}
			variants[kind].append(key)


## How many canopy shapes each tree has in all (the common forest trees most).
const MORE_TREE_SHAPES := {"pine": 8, "oak": 8, "birch": 7, "fir": 8, "autumn_oak": 7, "willow": 5, "acacia": 6, "palm": 5,
	"jungle_tree": 6, "dead_tree": 5}


## The mesh for a key ("pine_0", "pine_0_bare", "pine_0_lod"), built the first time it's asked for.
func mesh(key: String) -> ArrayMesh:
	if not meshes.has(key):
		var spec: Dictionary = _specs[key]
		var kept_detail := MeshKit.detail
		var kept_bare := _bare
		MeshKit.detail = spec.detail
		_bare = spec.bare
		_lod = key.ends_with("_lod")
		meshes[key] = _build_mesh(spec.kind, spec.index, spec.seed)
		if not spec.bare and not key.ends_with("_lod"):
			feet[key] = _feet_of(meshes[key], spec.kind)
		if spec.kind == "mud":
			drape_src[key] = _drape_source(meshes[key])
		MeshKit.detail = kept_detail
		_bare = kept_bare
		_lod = false
	return meshes[key]


## Build every mesh now, while the world loads. A single flora mesh can take ~100 ms, so building them on first
## use stalled play; loading is the one moment a stall is expected.
func prebuild() -> void:
	for key: String in _specs:
		mesh(key)


## How far out from a tree's axis its foot reaches (the rest of its lowest band is drooping leaves): buttressed
## trunks spread wide, the rest are a trunk and its root flare.
const FOOT_REACH := {"kapok": 5.0, "jungle_tree": 4.0, "giant_mushroom": 2.0}


## The foot of a model: its lowest few centimetres, thinned to the farthest point in each of 12 directions round
## its middle and the point nearest halfway out (so a wide flat thing like mud is held at its middle too).
func _feet_of(m: ArrayMesh, kind: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if m == null or m.get_surface_count() == 0:
		return out
	var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return out
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var band := clampf((hi - lo) * 0.1, 0.02, 0.15)
	var reach := float(FOOT_REACH.get(kind, 1.5)) if KINDS[kind].category == "tree" else INF
	var far: Array = []
	far.resize(12)
	var far_d := PackedFloat32Array()
	far_d.resize(12)
	far_d.fill(-1.0)
	var pts: Array = []
	for v in verts:
		if v.y > lo + band:
			continue
		var d := Vector2(v.x, v.z).length()
		if d > reach:
			continue
		var s := int(fposmod(atan2(v.z, v.x), TAU) / TAU * 12.0) % 12
		pts.append([v, d, s])
		if d > far_d[s]:
			far_d[s] = d
			far[s] = v
	var half: Array = []
	half.resize(12)
	var half_e := PackedFloat32Array()
	half_e.resize(12)
	half_e.fill(INF)
	for p: Array in pts:
		var s: int = p[2]
		var e := absf(float(p[1]) - far_d[s] * 0.5)
		if e < half_e[s]:
			half_e[s] = e
			half[s] = p[0]
	for s in 12:
		if far_d[s] >= 0.0:
			out.append(far[s])
			if half_e[s] < INF and half[s] != far[s]:
				out.append(half[s])
	return out


func _drape_source(m: ArrayMesh) -> Array:
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	for t in range(0, v.size() - 2, 3):
		if (n[t] + n[t + 1] + n[t + 2]).y < -1.5:
			continue   # an underside
		for k in 3:
			ov.append(v[t + k])
			on.append(n[t + k])
			oc.append(c[t + k])
	return [ov, on, oc]


## Whether a mesh key exists (it may not be built yet).
func has_mesh(key: String) -> bool:
	return _specs.has(key)


func mesh_keys() -> Array:
	return _specs.keys()


static func category_of(kind: String) -> String:
	return KINDS[kind].category


## "pine_1" / "pine_1_lod" / "pine_1_shadow" (a mesh key or the node drawn from it) -> "pine".
static func kind_of_key(key: String) -> String:
	var k := key.trim_suffix("_shadow").trim_suffix("_lod")
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
	if KINDS.get(kind, {}).get("named", false):
		return String(KINDS[kind].label)
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
	mud_material = ArtStyle.material(preload("res://shaders/grass.gdshader"), {"brush_strength": 0.15, "sway_strength": 0.0})
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
		"stalagmite": _stalagmite(kit, rng)
		"bamboo": _bamboo(kit, rng)
		"heliconia": _heliconia(kit, rng)
		"fern_palm": _fern_palm(kit, rng)
		"cliff_vine": _cliff_vine(kit, rng)
		"mossy_log": _mossy_log(kit, rng)
		"mud": _mud(kit, rng)
		"heather": _heather(kit, rng, index)
		"juniper": _juniper(kit, rng)
		"sagebrush": _sagebrush(kit, rng)
		"bramble": _bramble(kit, rng)
		"rhododendron": _rhododendron(kit, rng, index)
		"ocotillo": _ocotillo(kit, rng)
		"hibiscus": _hibiscus(kit, rng, index)
		"spore_bush": _spore_bush(kit, rng, index)
		"cattail": _cattail(kit, rng)
		"aloe": _aloe(kit, rng, index)
		"wild_garlic": _wild_garlic(kit, rng)
		"lingonberry": _lingonberry(kit, rng)
		"lupin": _lupin(kit, rng, index)
		"daisy": _daisy(kit, rng)
		"foxglove": _foxglove(kit, rng, index)
		"sedge": _sedge(kit, rng)
		"desert_bloom": _desert_bloom(kit, rng, index)
		"bromeliad": _bromeliad(kit, rng, index)
		"cotton_grass": _cotton_grass(kit, rng)
		"lichen": _lichen(kit, rng, index)
		"puffball": _puffball(kit, rng)
		"dune_grass": _dune_grass(kit, rng)
		"sea_thrift": _sea_thrift(kit, rng)
		"alpine_cushion": _alpine_cushion(kit, rng, index)
		"edelweiss": _edelweiss(kit, rng)
		"kapok": TreeModels.emergent(kit, rng, _vary(_pal.bark, rng).lightened(0.3), _vary(_pal.jungle_leaves, rng).darkened(0.05), rng.randf_range(22.0, 27.0), rng.randf_range(0.6, 0.75))
	if kind == ItemDB.fruit_tree and not _bare:
		_add_fruit(kit, rng)
	var cat: String = KINDS[kind].category
	var mat: Material = foliage_material
	if cat == "rock" or kind in ["pebbles", "scree"]:
		mat = rock_material
	elif kind == "mud":
		mat = mud_material
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

## Weeping willow: a stout, leaning, gnarled trunk; limbs arching up and out; and from them long curtains of leafy
## strands falling nearly to the ground, under a soft dome of leaves.
func _willow(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.weeping_willow(kit, rng, _vary(_pal.bark, rng).darkened(0.12), _vary(_pal.willow_leaves, rng), rng.randf_range(4.6, 5.8), rng.randf_range(0.34, 0.44), _lod)


## Savanna tree: leaning trunk splitting into branches with flat, wide canopy layers.
func _acacia(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.umbrella(kit, rng, _vary(_pal.bark, rng).lightened(0.05), _vary(_pal.acacia_leaves, rng), rng.randf_range(3.5, 5.0), rng.randf_range(0.22, 0.3))

## Bare, weathered tree.
func _dead_tree(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	TreeModels.dead(kit, rng, _vary(_pal.dead_wood, rng), rng.randf_range(3.5, 6.0), rng.randf_range(0.2, 0.3))

func _cactus(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.cactus, rng)
	if rng.randf() < 0.35:
		_prickly_pear(kit, rng, col)
		return
	# A saguaro: a ribbed column with arms that elbow out and curve up, spines along the ribs, flowers on the tips.
	var h := rng.randf_range(2.2, 3.8)
	var r := rng.randf_range(0.26, 0.36)
	var ribs := 12
	var rib_col := func(_t: float, a: float) -> Color:
		var c := sin(a * ribs)
		if c > 0.82:
			return col.lightened(0.18) if fposmod(_t * 26.0, 1.0) < 0.3 else col.lightened(0.06)   # spine dots on the ridge
		return col.darkened(0.16) if c < -0.4 else col
	var rib_shape := func(_t: float, a: float) -> Vector2:
		return Vector2.ONE * (1.0 + sin(a * ribs) * 0.07)
	var trunk: Array = []
	var trunk_r: Array = []
	for i in 9:
		var t := i / 8.0
		trunk.append(Vector3(sin(t * 2.0) * 0.04, t * h, 0))
		trunk_r.append(r * (1.0 - pow(t, 6.0) * 0.6) * (1.04 if i == 0 else 1.0))
	kit.loft(trunk, trunk_r, 24, col, rib_col, rib_shape, true, true)
	var arms := 2 if rng.randf() < 0.65 else (1 if rng.randf() < 0.6 else 3)
	var spin := rng.randf() * TAU
	var tips: Array = [trunk[8]]
	for k in arms:
		var dir := Vector3(cos(spin + TAU * k / arms + rng.randf_range(-0.3, 0.3)), 0, sin(spin + TAU * k / arms))
		var y := rng.randf_range(h * 0.3, h * 0.6)
		var out := r + rng.randf_range(0.45, 0.75)
		var up := rng.randf_range(0.8, 1.4)
		var ar := r * rng.randf_range(0.6, 0.72)
		var base := Vector3(0, y, 0)
		var elbow := base + dir * out + Vector3(0, ar * 0.4, 0)
		var path: Array = [base, base + dir * out * 0.55 + Vector3(0, ar * 0.05, 0), elbow, elbow + Vector3(0, up * 0.45, 0) + dir * 0.03, elbow + Vector3(0, up, 0) + dir * 0.05]
		kit.loft(path, [ar * 0.95, ar, ar, ar * 0.97, ar * 0.65], 18, col, rib_col, rib_shape, false, true)
		tips.append(path[4])
	# Flowers crowning the tips.
	var flower: Color = _pal.flowers[rng.randi() % _pal.flowers.size()].lerp(Color(0.98, 0.95, 0.85), 0.4)
	for tip: Vector3 in tips:
		if rng.randf() < 0.55:
			for i in rng.randi_range(2, 4):
				var a := rng.randf() * TAU
				kit.add_primitive(MeshKit.sphere(0.07, 7, 4), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), tip + Vector3(cos(a) * 0.08, 0.06, sin(a) * 0.08)), flower, 0.0, 0.04)


## A prickly pear: flat oval pads growing from each other's edges, spine tufts dotted over them, red fruit on top.
func _prickly_pear(kit: MeshKit, rng: RandomNumberGenerator, col: Color) -> void:
	# Pads: [base, basis, size]. Each grows two or three more from its rim, tilting outward, so they fan into a clump.
	var fruit := Color(0.75, 0.18, 0.3).lerp(Color(0.85, 0.35, 0.2), rng.randf())
	var first := Basis(Vector3.UP, rng.randf() * TAU)
	var pads: Array = [[Vector3.ZERO, first, 0.46]]
	var want := rng.randi_range(8, 13)
	var i := 0
	while i < pads.size() and pads.size() < want:
		var p: Array = pads[i]
		var pb: Basis = p[1]
		var psz: float = p[2]
		for k in rng.randi_range(2, 3):
			var sz := psz * rng.randf_range(0.72, 0.9)
			if sz < 0.17 or pads.size() >= want:
				continue
			var u := rng.randf_range(-0.55, 0.55)
			var at: Vector3 = (p[0] as Vector3) + pb * Vector3(u * psz * 0.6, psz * 1.72, 0)
			var lean := u * 1.1 + rng.randf_range(-0.35, 0.35)
			var b := pb * Basis(Vector3.FORWARD, -lean) * Basis(Vector3.UP, rng.randf_range(-0.7, 0.7))
			pads.append([at, b, sz])
		i += 1
	for pd: Array in pads:
		var base: Vector3 = pd[0]
		var b: Basis = pd[1]
		var sz: float = pd[2]
		var outline := PackedVector2Array()
		for j in 16:
			var a := TAU * j / 16.0
			outline.append(Vector2(cos(a) * sz * 0.62, (sin(a) + 1.0) * sz * 0.9))
		var shade := col.lightened(rng.randf_range(-0.06, 0.08))
		kit.extrude(outline, Transform3D(b, base), sz * 0.16, sz * 0.06, shade, shade.darkened(0.15), 0.5)
		# Spine tufts: pale dots on both faces.
		for j in 7:
			var u := rng.randf_range(-0.45, 0.45) * sz
			var v := rng.randf_range(0.25, 1.55) * sz
			for side in [-1.0, 1.0]:
				kit.add_primitive(MeshKit.sphere(sz * 0.035, 4, 3), Transform3D(Basis(), base + b * Vector3(u, v, side * sz * 0.085)), Color(0.92, 0.88, 0.7), 0.0, 0.0)
		if rng.randf() < 0.5 and sz < 0.36:
			for j in rng.randi_range(1, 3):
				var u := rng.randf_range(-0.4, 0.4) * sz
				kit.add_primitive(MeshKit.sphere(sz * 0.12, 7, 5), Transform3D(Basis.from_scale(Vector3(1, 1.3, 1)), base + b * Vector3(u, sz * 1.78, 0)), fruit, 0.0, 0.05)


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


## A stalagmite: a lumpy cone of dripstone rising from a flared foot, banded where the mineral built up, wet and
## pale at the tip. About 1.6 m tall at scale 1.
func _stalagmite(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.rock.lerp(Color(0.72, 0.66, 0.56), 0.35), rng, 0.05)
	var h := rng.randf_range(1.4, 1.8)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var path: Array = []
	var radii: Array = []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(0, t * h, 0) + lean * t * t)
		radii.append(lerpf(0.42, 0.03, pow(t, 0.8)) * (1.0 + 0.08 * sin(t * 17.0)))
	var bands := func(t: float, _a: float) -> Color:
		return col.lightened(0.2 * t) if fmod(t * 9.0, 1.0) > 0.25 else col.darkened(0.08)
	kit.loft(path, radii, 9, col, bands, Callable(), true, true, 0.03)
	# A flared foot of flowstone round it, and sometimes a small twin.
	kit.add_primitive(MeshKit.sphere(0.55, 9, 4), Transform3D(Basis().scaled(Vector3(1.0, 0.3, 1.0)), Vector3(0, 0.03, 0)), col.darkened(0.05), 0.15, 0.05)
	if rng.randf() < 0.6:
		var off := Vector3(rng.randf_range(0.35, 0.5), 0, rng.randf_range(-0.3, 0.3))
		var small: Array = []
		var sr: Array = []
		for i in 4:
			var t := i / 3.0
			small.append(off + Vector3(0, t * h * 0.45, 0))
			sr.append(lerpf(0.2, 0.02, t))
		kit.loft(small, sr, 7, col.darkened(0.04), bands, Callable(), true, true, 0.02)


## Tier-4 gem: big crystal spikes bursting from a small rock.
func _gem(kit: MeshKit, rng: RandomNumberGenerator, col: Color) -> void:
	# A rough rock it grows from, then a cluster of six-sided crystals with faceted points, splaying outward, dark at
	# the root and clear at the tip, and a scatter of small ones round them.
	var rock := _vary(_pal.rock, rng).darkened(0.15)
	kit.flat_shading = true
	kit.add_primitive(MeshKit.sphere(0.8, 9, 6), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.25, 0.55, 1.0)), Vector3(0, 0.12, 0)), rock, 0.3, 0.08)
	var crystal := func(base: Vector3, dir: Vector3, length: float, r: float) -> void:
		var b := Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, rng.randf() * TAU)
		var shade := _vary(col, rng, 0.04)
		var body := length * 0.78
		kit.add_primitive(MeshKit.cylinder(r, r * 1.04, body, 6), Transform3D(b, base + dir * body * 0.5), shade.darkened(0.12), 0.0, 0.0,
			null, func(p: Vector3) -> Color: return shade.darkened(0.2).lerp(shade.lightened(0.1), clampf((p - base).dot(dir) / body, 0.0, 1.0)))
		kit.add_primitive(MeshKit.cylinder(0.0, r, length - body, 6), Transform3D(b, base + dir * (body + (length - body) * 0.5)), shade.lightened(0.28), 0.0, 0.0)
	for i in rng.randi_range(5, 8):
		var dir := Vector3(rng.randf_range(-0.75, 0.75), rng.randf_range(0.55, 1.0), rng.randf_range(-0.75, 0.75)).normalized()
		var length := rng.randf_range(0.8, 1.8) * (1.25 if i == 0 else 1.0)
		var r := rng.randf_range(0.13, 0.24) * (1.25 if i == 0 else 1.0)
		crystal.call(Vector3(dir.x * 0.2, 0.15, dir.z * 0.2), dir if i > 0 else Vector3(0.1, 1, 0.05).normalized(), length, r)
	for i in rng.randi_range(5, 9):   # little ones round the foot
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.55, 1.0)
		var dir := Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6).normalized()
		crystal.call(Vector3(cos(a) * d, 0.05, sin(a) * d * 0.85), dir, rng.randf_range(0.2, 0.45), rng.randf_range(0.05, 0.09))
	kit.flat_shading = false


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
## A patch of wet mud: a flat dark sheen on the ground with a few puddles in it.
func _mud(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	# Warm wet earth, not black: dark enough to read as mud against the grass, light enough not to read as a hole.
	# Each patch sits on a wider, fainter rim of churned earth halfway to the ground colour, so it fades in at its edge.
	var ground: Color = _pal.ground[WorldGen.Biome.JUNGLE]
	var mud := Color(0.4, 0.3, 0.2).lerp(ground, 0.2)
	for i in rng.randi_range(3, 5):
		var at := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
		var r := rng.randf_range(0.6, 1.1)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0)))
		kit.add_primitive(MeshKit.cylinder(r * 1.25, r * 1.3, 0.03, 12), Transform3D(b, at + Vector3(0, 0.015, 0)), mud.lerp(ground, 0.5), 0.0, 0.03)
		kit.add_primitive(MeshKit.cylinder(r, r * 1.05, 0.04, 12), Transform3D(b, at + Vector3(0, 0.03, 0)), mud.darkened(rng.randf_range(0.0, 0.12)), 0.0, 0.03)
	for i in rng.randi_range(2, 3):   # puddles: brown water catching the sky a little
		var at := Vector3(rng.randf_range(-0.6, 0.6), 0.055, rng.randf_range(-0.6, 0.6))
		kit.add_primitive(MeshKit.cylinder(rng.randf_range(0.2, 0.4), rng.randf_range(0.22, 0.42), 0.02, 10), Transform3D(Basis(), at), Color(0.3, 0.27, 0.22).lerp(Color(0.55, 0.62, 0.66), 0.25), 0.0, 0.0)


func _log(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	_fallen_log(kit, rng, false)


func _mossy_log(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	_fallen_log(kit, rng, true)


## A fallen tree trunk lying on the ground (along X, settled a little into it). Ridged, fissured bark, thick and
## gently bent, tapering from the end it stood on to the end where it snapped off. That end is a break of pale
## wood; the other is old weathered wood showing its rings (or, for a fallen jungle
## giant, the flare of its foot with roots reaching out into the ground). A few broken branch stubs, bracket fungi
## and lichen; the jungle giant is half grown over with moss, ferns arching up out of it.
func _fallen_log(kit: MeshKit, rng: RandomNumberGenerator, giant: bool) -> void:
	var length := rng.randf_range(5.2, 6.4) if giant else rng.randf_range(3.0, 3.6)
	var r := rng.randf_range(0.56, 0.66) if giant else rng.randf_range(0.31, 0.37)
	var bark := _vary(_pal.bark, rng).darkened(0.12 if giant else 0.0)
	var deep := bark.darkened(0.55)            # down in the fissures
	var weathered := bark.lerp(Color(0.62, 0.58, 0.52), 0.35)   # sun-bleached on top
	var wood := Color(0.78, 0.64, 0.46)
	var moss := _vary(_pal.moss, rng).lerp(_pal.jungle_leaves, 0.25).darkened(0.22)
	var mn := FastNoiseLite.new()
	mn.seed = rng.randi()
	mn.frequency = 2.2
	mn.fractal_octaves = 3
	var steps := 16
	var bend := Vector3(0, rng.randf_range(-0.04, 0.06), rng.randf_range(-0.25, 0.25)) * length / 3.0
	var path: Array = []
	var radii: Array = []
	for i in steps + 1:
		var t := float(i) / steps
		var x := lerpf(-length * 0.5, length * 0.5, t)
		var rr := r * lerpf(1.06, 0.82, t)
		if giant:
			rr *= 1.0 + 0.12 * pow(1.0 - smoothstep(0.0, 0.14, t), 2.0)   # a touch wider at the foot
		path.append(Vector3(x, 0.0, 0.0) + bend * sin(t * PI) + Vector3(0, rr * 0.78, 0))   # settled a fifth into the ground
		radii.append(rr)
	# Bark: deep fissures running along the trunk, wandering a little, and broad plates between them.
	var fissure := func(t: float, ang: float) -> float:
		return pow(maxf(sin(ang * 11.0 + sin(t * 9.0 + ang * 2.0) * 0.9), 0.0), 5.0)
	var shape := func(t: float, ang: float) -> Vector2:
		var k: float = 1.0 - 0.13 * float(fissure.call(t, ang)) + 0.03 * sin(ang * 3.0 + t * 4.0)
		return Vector2(k, k * 0.96)
	var colour := func(t: float, ang: float) -> Color:
		var up := cos(ang)   # (ang 0 is straight up along the log)
		# Long streaks of lighter and darker bark down the length, bleached grey on top where the sun gets it.
		var streak := sin(ang * 5.0 + t * 2.0) * 0.5 + sin(ang * 13.0 - t * 5.0) * 0.5
		var c: Color = bark.lightened(0.07 * streak).lerp(weathered, smoothstep(0.3, 0.95, up) * (0.35 if giant else 0.55))
		c = c.lerp(deep, float(fissure.call(t, ang)))
		if giant:
			# Moss in ragged patches, most of them over the top, a few creeping down the sides; bark between.
			var p3 := Vector3(t * length, cos(ang) * r, sin(ang) * r)
			var cover := mn.get_noise_3dv(p3) * 0.9 + up * 0.45 - 0.05
			var m := smoothstep(0.05, 0.3, cover)
			c = c.lerp(moss.lightened(0.1 * mn.get_noise_3dv(p3 * 4.0)), m)
			c = c.lerp(moss.darkened(0.35), smoothstep(0.0, 0.1, cover) * (1.0 - m) * 0.5)   # a dark damp rim round each patch
		return c
	kit.loft(path, radii, 26, bark, colour, shape, false, false, r * 0.06)

	if giant:
		# An old jungle trunk, rotted hollow: both ends open on a dark hollow inside a crumbly rim (see _hollow_end).
		var rot := Color(0.36, 0.25, 0.16)
		_hollow_end(kit, rng, path[steps], ((path[steps] as Vector3) - (path[steps - 1] as Vector3)).normalized(), radii[steps], rot, moss)
		_hollow_end(kit, rng, path[0], ((path[0] as Vector3) - (path[1] as Vector3)).normalized(), radii[0], rot, moss)
	else:
		# The snapped end: the broken face of pale wood.
		var tip: Vector3 = path[steps]
		var tr: float = radii[steps]
		var ax := ((path[steps] as Vector3) - (path[steps - 1] as Vector3)).normalized()
		kit.loft([tip - ax * 0.02, tip + ax * tr * 0.25], [tr * 0.98, tr * 0.35], 14, wood.darkened(0.15), func(t: float, _a: float) -> Color:
			return wood.darkened(0.25).lerp(wood, t), Callable(), false, true, tr * 0.08)
		# The other end: old weathered wood, grey, with rings.
		var foot: Vector3 = path[0]
		var fr: float = radii[0]
		var rings := func(t: float, _a: float) -> Color:
			return wood.lerp(Color(0.6, 0.57, 0.52), 0.55).darkened(0.12 * float(int(t * 6.0) % 2))
		kit.loft([foot + Vector3(0.01, 0, 0), foot - Vector3(fr * 0.05, 0, 0)], [fr * 0.99, 0.0], 16, wood, rings, Callable(), false, false, 0.008)

	# Broken branch stubs.
	for i in rng.randi_range(2, 3):
		var k := rng.randi_range(4, steps - 3)
		var at: Vector3 = path[k]
		var a := rng.randf_range(-1.6, 1.6)   # anywhere but underneath
		var out := (Vector3.UP * cos(a) + Vector3.BACK * sin(a)).normalized()
		var dir := (out + Vector3(rng.randf_range(0.1, 0.5), 0, 0)).normalized()
		var bl := rng.randf_range(0.1, 0.28) * (1.8 if giant else 1.0)
		var br := float(radii[k]) * rng.randf_range(0.18, 0.26)
		var base := at + out * float(radii[k]) * 0.8
		kit.loft([base, base + dir * bl * 0.6, base + dir * bl], [br * 1.3, br, br * 0.8], 7, bark, func(_t: float, ang: float) -> Color:
			return bark.lerp(deep, 0.3 * absf(sin(ang * 3.0))), Callable(), false, true, 0.006)
		kit.add_primitive(MeshKit.sphere(br * 0.85, 7, 4), Transform3D(Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1, 0.35, 1)), base + dir * bl), wood.lightened(0.05), 0.15, 0.03)

	# Bracket fungi in a little stepped run up one side.
	var fside := 1.0 if rng.randf() < 0.5 else -1.0
	var fx := rng.randf_range(0.25, 0.6)
	var fcol := Color(0.86, 0.78, 0.62) if rng.randf() < 0.6 else Color(0.72, 0.48, 0.3)
	for i in rng.randi_range(2, 4):
		var k := clampi(int((fx + i * 0.05) * steps), 1, steps - 1)
		var at: Vector3 = path[k]
		var a := fside * rng.randf_range(1.1, 1.6) - 0.15 * i * fside
		var out := (Vector3.UP * cos(a) + Vector3.BACK * sin(a)).normalized()
		var fr2 := rng.randf_range(0.07, 0.13) * (1.4 if giant else 1.0)
		kit.add_primitive(MeshKit.cylinder(fr2 * 0.85, fr2, fr2 * 0.3, 10), Transform3D(Basis(), at + out * (float(radii[k]) + fr2 * 0.5) + Vector3(0, 0.0, 0)), fcol.darkened(0.05 * i), 0.1, 0.04)

	if not giant:
		# Lichen: small pale grey-green crusts on the upper side.
		for i in rng.randi_range(4, 7):
			var k := rng.randi_range(1, steps - 1)
			var a := rng.randf_range(-0.9, 0.9)
			var out := (Vector3.UP * cos(a) + Vector3.BACK * sin(a)).normalized()
			var at: Vector3 = (path[k] as Vector3) + out * float(radii[k]) * 0.97
			kit.add_primitive(MeshKit.sphere(rng.randf_range(0.035, 0.06), 6, 3), Transform3D(Basis(Quaternion(Vector3.UP, out)).scaled(Vector3(1.3, 0.1, 1.0)), at), Color(0.55, 0.6, 0.45).lerp(weathered, rng.randf_range(0.2, 0.5)), 0.2, 0.05)
		return

	# The jungle giant: soft low cushions of moss along the top, and ferns arching up out of it.
	for i in rng.randi_range(8, 12):
		var k := rng.randi_range(1, steps - 1)
		var a := rng.randf_range(-0.8, 0.8)
		var out := (Vector3.UP * cos(a) + Vector3.BACK * sin(a)).normalized()
		var at: Vector3 = (path[k] as Vector3) + out * float(radii[k]) * 0.9
		var cr := rng.randf_range(0.14, 0.28)
		kit.add_primitive(MeshKit.sphere(cr, 8, 4), Transform3D(Basis(Quaternion(Vector3.UP, out)).scaled(Vector3(1.6, 0.32, 1.2)), at), moss.lightened(rng.randf_range(-0.05, 0.1)), 0.15, 0.06)
	var fern := _vary(_pal.fern, rng)
	for i in rng.randi_range(3, 4):
		var k := rng.randi_range(3, steps - 3)
		var root: Vector3 = (path[k] as Vector3) + Vector3.UP * float(radii[k]) * 0.92
		var turn := rng.randf() * TAU
		for j in rng.randi_range(6, 9):
			var a := turn + TAU * j / 7.0 + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(a), 0, sin(a))
			var fl := rng.randf_range(0.45, 0.8)
			var rise := rng.randf_range(0.35, 0.6)
			var fpath: Array = []
			var fw: Array = []
			for q in 6:
				var t := q / 5.0
				# Up and out, then arching over and down at the tip.
				fpath.append(root + out * fl * t + Vector3.UP * fl * (rise * sin(t * PI * 0.8) - 0.15 * t * t))
				fw.append(fl * 0.09 * sin(PI * (0.15 + t * 0.85)) + 0.005)
			var fc := fern.lightened(rng.randf_range(-0.06, 0.08))
			kit.loft(fpath, fw, 4, fc, func(t: float, _ang: float) -> Color: return fc.darkened(0.25 * (1.0 - t)),
				func(_t: float, _ang: float) -> Vector2: return Vector2(0.18, 1.0), true, true)


## One end of a log rotted hollow, at `e`, opening along `d` (out of the log), the shell's radius `r` there: a soft,
## crumbly rim of rotten wood a sixth of the radius thick (wavering, but no sharp points), and inside it a hollow going
## back into the log, darkening the deeper it goes; moss creeping over the top of the rim, crumbs of rot spilled on the
## ground at the mouth.
func _hollow_end(kit: MeshKit, rng: RandomNumberGenerator, e: Vector3, d: Vector3, r: float, rot: Color, moss: Color) -> void:
	var u := d.cross(Vector3.UP).normalized()
	var v := u.cross(d).normalized()   # (up, across the end)
	var sides := 22
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var wall := r * 0.17
	var depth := r * rng.randf_range(1.3, 1.9)
	var jag := func(a: float) -> float:
		return 1.0 - 0.07 * absf(sin(a * 3.0 + ph)) - 0.05 * absf(sin(a * 7.0 + ph2))
	var ring := func(rad: float, along: float, ragged: bool) -> PackedVector3Array:
		var out := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			var m: float = float(jag.call(a)) if ragged else 1.0
			out.append(e + d * along + (u * cos(a) + v * sin(a)) * rad * m)
		return out
	# A quad as two triangles, wound to face `want`.
	var quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c: Color, want: Vector3) -> void:
		for t: Array in [[p0, p1, p2], [p0, p2, p3]]:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c2: Vector3 = t[2]
			if (c2 - a).cross(b - a).dot(want) < 0.0:
				kit.add_tri(a, c2, b, c)
			else:
				kit.add_tri(a, b, c2, c)
	# The rim: from just outside the shell's edge (hiding it) in to the hollow, sloping down into it a little.
	var outer: PackedVector3Array = ring.call(r * 1.05, 0.015, false)
	var lip: PackedVector3Array = ring.call((r - wall * 0.5) * 1.0, 0.03, true)
	var inner: PackedVector3Array = ring.call(r - wall, -0.03, true)
	for k in sides:
		var k2 := (k + 1) % sides
		var crumb := rot.lightened(0.12 + 0.1 * absf(sin(k * 1.7 + ph)))
		quad.call(outer[k], outer[k2], lip[k2], lip[k], crumb.darkened(0.08), d)
		quad.call(lip[k], lip[k2], inner[k2], inner[k], crumb, d)
	# The hollow: its wall, facing in, going back and narrowing, darker deeper in; a dark back to it.
	var rings: Array = [inner]
	var rows := 4
	for q in range(1, rows + 1):
		var t := float(q) / rows
		rings.append(ring.call((r - wall) * lerpf(1.0, 0.72, t), -0.03 - depth * t, true))
	for q in rows:
		var col := rot.darkened(lerpf(0.25, 0.8, float(q) / rows))
		var ra: PackedVector3Array = rings[q]
		var rb: PackedVector3Array = rings[q + 1]
		for k in sides:
			var k2 := (k + 1) % sides
			var mid := (ra[k] + rb[k2]) * 0.5
			var axis_pt := e + d * d.dot(mid - e)
			quad.call(ra[k], ra[k2], rb[k2], rb[k], col, (axis_pt - mid).normalized())
	var back: PackedVector3Array = rings[rows]
	var bc := e - d * (0.03 + depth)
	for k in sides:
		var k2 := (k + 1) % sides
		var a := bc
		var b2: Vector3 = back[k]
		var c3: Vector3 = back[k2]
		if (c3 - a).cross(b2 - a).dot(d) < 0.0:
			kit.add_tri(a, c3, b2, rot.darkened(0.88))
		else:
			kit.add_tri(a, b2, c3, rot.darkened(0.88))
	# Moss creeping over the top of the rim.
	for k in rng.randi_range(2, 3):
		var a := PI * 0.5 + rng.randf_range(-0.7, 0.7)
		var at := e + d * rng.randf_range(-0.05, 0.03) + (u * cos(a) + v * sin(a)) * r * 0.97
		var cr := r * rng.randf_range(0.16, 0.24)
		kit.add_primitive(MeshKit.sphere(cr, 8, 4), Transform3D(Basis.looking_at(d, (u * cos(a) + v * sin(a))).scaled(Vector3(1.5, 0.45, 1.1)), at), moss.lightened(rng.randf_range(-0.05, 0.08)), 0.15, 0.06)
	# Crumbs of rotten wood spilled out on the ground at the mouth.
	for k in rng.randi_range(3, 5):
		var at := e + d * rng.randf_range(0.08, r * 0.8) + u * rng.randf_range(-r * 0.8, r * 0.8)
		at.y = 0.03
		var cr := r * rng.randf_range(0.06, 0.12)
		kit.add_primitive(MeshKit.sphere(cr, 6, 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.5, 1.0)), at), rot.lightened(rng.randf_range(0.0, 0.15)), 0.2, 0.05)


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
	var ribs := 14
	var path: Array = []
	var radii: Array = []
	for i in 8:
		var t := i / 7.0
		path.append(Vector3(0, t * h, 0))
		radii.append(r * (0.75 + sin(t * PI * 0.85) * 0.3) * (1.0 if t < 0.95 else 0.4))
	kit.loft(path, radii, 28, col, func(t: float, a: float) -> Color:
		var c := sin(a * ribs)
		if c > 0.85:
			return Color(0.95, 0.85, 0.55) if fposmod(t * 14.0, 1.0) < 0.35 else col.lightened(0.08)   # golden spines on the ridges
		return col.darkened(0.2) if c < -0.3 else col,
		func(t: float, a: float) -> Vector2: return Vector2.ONE * (1.0 + sin(a * ribs) * 0.1), false, true)
	var flower: Color = _pal.flowers[1].lerp(Color(1.0, 0.8, 0.3), 0.3)
	for i in 6:
		var a := TAU * i / 6.0
		kit.add_primitive(MeshKit.sphere(0.045, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), Vector3(cos(a) * r * 0.28, h * 0.98, sin(a) * r * 0.28)), flower, 0.0, 0.04)


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
			var c := base + Vector3(cos(a), 0.002 * l, sin(a)) * 0.035 + Vector3(0, 0.0015 * l, 0)   # each leaf a hair above the last (they overlap)
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
	TreeModels.rainforest(kit, rng, _vary(_pal.bark, rng).lightened(0.18), _vary(_pal.jungle_leaves, rng), _vary(_pal.jungle_leaves_2, rng), rng.randf_range(12.0, 17.0), rng.randf_range(0.34, 0.44), _lod)

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


## A light leaf: a flat diamond from `base` along `dir`, `width` across (its flat facing `normal`), seen from both
## sides (four triangles: the foliage material only draws a face's front).
func _leaf_diamond(kit: MeshKit, base: Vector3, dir: Vector3, normal: Vector3, length: float, width: float, col: Color) -> void:
	var across := dir.cross(normal).normalized() * width * 0.5
	var mid := base + dir * length * 0.4
	var tip := base + dir * length
	var a := mid + across
	var b := mid - across
	var dark := col.darkened(0.12)
	kit.add_tri(base, a, tip, dark, col, col.lightened(0.1))
	kit.add_tri(base, tip, b, dark, col.lightened(0.1), col)
	kit.add_tri(base, tip, a, dark, col.lightened(0.1), col)
	kit.add_tri(base, b, tip, dark, col, col.lightened(0.1))


## A clump of bamboo: tall jointed canes, pale bands at the nodes, sprays of narrow leaves up top.
func _bamboo(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var cane := _vary(Color(0.5, 0.62, 0.28), rng, 0.05)
	var leaf := _vary(_pal.jungle_leaves, rng)
	for i in rng.randi_range(7, 12):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.5)
		var base := Vector3(cos(a) * d, -0.1, sin(a) * d)
		var h := rng.randf_range(3.2, 5.8)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.7) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var path: Array = []
		var radii: Array = []
		var r := rng.randf_range(0.035, 0.055)
		for k in 5:
			var t := k / 4.0
			path.append(base + Vector3(0, h * t, 0) + lean * t * t)
			radii.append(r * (1.0 - t * 0.35))
		var nodes := rng.randi_range(7, 10)
		var c := cane.lightened(rng.randf_range(-0.05, 0.08))
		kit.loft(path, radii, 5, c, func(t: float, _ang: float) -> Color:
			return c.lightened(0.25) if fposmod(t * nodes, 1.0) < 0.06 else c, Callable(), true, true)
		# Leaf sprays from the upper nodes.
		for k in rng.randi_range(2, 4):
			var t := rng.randf_range(0.55, 0.98)
			var at: Vector3 = base + Vector3(0, h * t, 0) + lean * t * t
			for j in rng.randi_range(3, 4):
				var la := rng.randf() * TAU
				var dir := Vector3(cos(la), rng.randf_range(-0.6, 0.1), sin(la)).normalized()
				_leaf_diamond(kit, at, dir, Vector3.UP.cross(dir).cross(dir).normalized(), rng.randf_range(0.24, 0.4), 0.06, leaf.lightened(rng.randf_range(-0.06, 0.1)))


## Heliconia: tall paddle leaves on long stalks, and a spike of red and yellow claws zig-zagging up.
func _heliconia(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := _vary(_pal.jungle_leaves_2, rng)
	for i in rng.randi_range(4, 7):
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * rng.randf_range(0.25, 0.5), rng.randf_range(1.0, 1.6), sin(a) * rng.randf_range(0.25, 0.5))
		kit.loft([Vector3(cos(a) * 0.05, 0, sin(a) * 0.05), tip * 0.6, tip], [0.03, 0.025, 0.02], 5, leaf.darkened(0.2))
		var length := rng.randf_range(0.8, 1.2)
		var w := length * 0.2
		var outline := PackedVector2Array([Vector2(0, 0), Vector2(w * 0.8, length * 0.15), Vector2(w, length * 0.5), Vector2(w * 0.7, length * 0.85),
			Vector2(0, length), Vector2(-w * 0.7, length * 0.85), Vector2(-w, length * 0.5), Vector2(-w * 0.8, length * 0.15)])
		var dir := Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45).normalized()
		var b := Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, a + PI * 0.5)
		kit.extrude(outline, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), tip - dir * 0.05), 0.02, 0.01, leaf.lightened(rng.randf_range(-0.04, 0.08)), leaf.lightened(0.15), 0.4)
	var red := Color(0.86, 0.2, 0.18).lerp(Color(0.95, 0.45, 0.15), rng.randf() * 0.5)
	for s in rng.randi_range(1, 2):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a) * 0.15, 0, sin(a) * 0.15)
		var h := rng.randf_range(1.0, 1.5)
		var top := base + Vector3(cos(a) * 0.15, h, sin(a) * 0.15)
		kit.loft([base, top], [0.022, 0.016], 5, Color(0.42, 0.5, 0.22))
		var claws := rng.randi_range(5, 8)
		for k in claws:
			var t := 0.55 + 0.42 * float(k) / float(claws)
			var at := base.lerp(top, t)
			var side := 1.0 if k % 2 == 0 else -1.0
			var out := Vector3(-sin(a), 0, cos(a)) * side
			var dir := (out + Vector3(0, 0.55, 0)).normalized()
			var cl := 0.16 * (1.0 - t * 0.4)
			kit.add_primitive(MeshKit.cylinder(0.0, cl * 0.32, cl, 5), Transform3D(Basis(Quaternion(Vector3.UP, dir)), at + dir * cl * 0.45), red, 0.0, 0.05)
			kit.add_primitive(MeshKit.sphere(cl * 0.12, 5, 3), Transform3D(Basis(), at + dir * cl * 0.95), Color(0.98, 0.85, 0.25), 0.0, 0.03)


## A fern palm: a short rough trunk and a crown of long arching feathery fronds.
func _fern_palm(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := _vary(_pal.fern.lerp(_pal.jungle_leaves, 0.4), rng)
	var trunk_h := rng.randf_range(0.3, 1.1)
	var bark := _vary(_pal.bark, rng).lerp(Color(0.4, 0.33, 0.24), 0.4)
	kit.loft([Vector3(0, -0.1, 0), Vector3(0, trunk_h * 0.5, 0), Vector3(0, trunk_h, 0)], [0.22, 0.2, 0.17], 8, bark, func(t: float, ang: float) -> Color:
		return bark.darkened(0.15) if fposmod(t * 9.0 + ang * 0.3, 1.0) < 0.35 else bark, Callable(), true, true, 0.03)
	var top := Vector3(0, trunk_h, 0)
	for i in rng.randi_range(9, 11):
		var a := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(1.1, 1.7)
		var rise := rng.randf_range(0.5, 0.9)
		# The midrib arches up and over; leaflets in pairs all along it.
		var pts: Array = []
		for k in 6:
			var t := k / 5.0
			pts.append(top + out * length * t + Vector3(0, rise * sin(t * PI * 0.8) - t * t * 0.4, 0))
		kit.loft(pts, [0.02, 0.018, 0.015, 0.012, 0.008, 0.004], 3, leaf.darkened(0.2), Callable(), Callable(), false, false)
		for k in range(1, 8):
			var t := k / 8.0
			var seg := int(t * 5.0)
			var p: Vector3 = (pts[seg] as Vector3).lerp(pts[mini(seg + 1, 5)], t * 5.0 - seg)
			var along: Vector3 = ((pts[mini(seg + 1, 5)] as Vector3) - (pts[seg] as Vector3)).normalized()
			var side := along.cross(Vector3.UP).normalized()
			var ll := 0.3 * (1.0 - t * 0.55)
			for sgn in [-1.0, 1.0]:
				var d: Vector3 = (side * sgn + along * 0.5 + Vector3(0, -0.25, 0)).normalized()
				_leaf_diamond(kit, p, d, Vector3.UP, ll, 0.05, leaf.lightened(rng.randf_range(-0.05, 0.08)))


## A curtain of vines hanging from the top of a rock face: strands in the model's -Y (the length VINE_LENGTH), lying
## in its XY plane (the face) with leaves along them. Placed, it is turned to lie along the face and stretched to it.
func _cliff_vine(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var stem := _vary(_pal.vine, rng).darkened(0.2)
	var leaf := _vary(_pal.vine, rng)
	for i in rng.randi_range(6, 10):
		var x := rng.randf_range(-1.1, 1.1)
		var l := VINE_LENGTH * rng.randf_range(0.55, 1.0)
		var path: Array = []
		var radii: Array = []
		for k in 8:
			var t := k / 7.0
			path.append(Vector3(x + sin(t * 5.0 + x * 3.0) * 0.12, -l * t, 0.04 + 0.03 * sin(t * 7.0 + x)))
			radii.append(lerpf(0.022, 0.01, t))
		kit.loft(path, radii, 4, stem, Callable(), Callable(), false, true)
		for k in rng.randi_range(6, 11):
			var t := rng.randf_range(0.0, 1.0)
			var seg := mini(int(t * 7.0), 6)
			var p: Vector3 = (path[seg] as Vector3).lerp(path[seg + 1], t * 7.0 - seg)
			var s := rng.randf_range(0.07, 0.12)
			kit.add_primitive(MeshKit.sphere(s, 5, 3), Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.6, 0.6)).scaled(Vector3(1.3, 1.0, 0.35)), p + Vector3(rng.randf_range(-0.06, 0.06), 0, 0.05)),
				leaf.lightened(rng.randf_range(-0.12, 0.1)), 0.05, 0.05)


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


# --- More plants for every land ------------------------------------------------------------

## A rosette of leaves round a point (used by several of the small plants): `n` leaves of a length, rising at `rise`.
func _rosette(kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, n: int, length: float, width: float, rise: float, col: Color) -> void:
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), rise * rng.randf_range(0.8, 1.2), sin(a)).normalized()
		# (Each leaf from a point a hair apart and turned a touch: whorls that cross never share a plane.)
		var from := at + Vector3(rng.randf_range(-0.004, 0.004), rng.randf_range(0.0, 0.006), rng.randf_range(-0.004, 0.004))
		var twist := Vector3(-sin(a), rng.randf_range(-0.15, 0.15), cos(a)).normalized()
		_leaf_diamond(kit, from, dir, twist.cross(dir).normalized(), length * rng.randf_range(0.8, 1.15), width, _vary(col, rng, 0.04))


## Heather: a low, springy mound of tiny dark leaves, thick with spikes of little purple, pink or white bells.
func _heather(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var leaf := _vary(Color(0.24, 0.36, 0.22), rng)
	var bloom: Color = [Color(0.62, 0.36, 0.62), Color(0.82, 0.48, 0.62), Color(0.9, 0.86, 0.88)][index % 3]
	var center := Vector3(0, 0.15, 0)
	var blobs := []
	for i in rng.randi_range(7, 9):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.6)
		var r := rng.randf_range(0.2, 0.32)
		var pos := Vector3(cos(a) * d, r * 0.55, sin(a) * d)
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 7, 4), Transform3D(Basis.from_scale(Vector3(1, 0.75, 1)), pos), leaf.lightened(rng.randf_range(-0.05, 0.06)), r * 0.35, 0.08, center)
	for i in rng.randi_range(24, 30):
		var bl: Array = blobs[rng.randi() % blobs.size()]
		var dir := Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
		var at: Vector3 = bl[0] + dir * float(bl[1]) * 0.7
		kit.add_primitive(MeshKit.sphere(0.03, 5, 3), Transform3D(Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1, 3.2, 1)), at + dir * 0.06), _vary(bloom, rng, 0.05), 0.0, 0.05)


## Juniper: a low, spreading conifer shrub: a dense middle, and sprays of spiky blue-green needles fanning out and up
## over it, dusted with frosty blue berries.
func _juniper(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(Color(0.25, 0.42, 0.38), rng)
	var stem := _vary(_pal.bark, rng).darkened(0.1)
	var center := Vector3(0, 0.35, 0)
	var spots := []
	for i in 3:   # the dense middle
		var p := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.25, 0.45), rng.randf_range(-0.2, 0.2))
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.3, 0.4), 7, 5), Transform3D(Basis.from_scale(Vector3(1, 0.8, 1)), p), col.darkened(0.08), 0.12, 0.08, center)
		spots.append(p)
	for i in rng.randi_range(7, 9):
		var a := TAU * i / 8.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(0.6, 0.95)
		var tip := out * length + Vector3.UP * rng.randf_range(0.35, 0.7)
		kit.loft([Vector3(0, -0.04, 0), out * length * 0.35 + Vector3.UP * 0.22, tip], [0.045, 0.03, 0.012], 5, stem)
		# Sprays along the branch, each a tapering cone pointing out (its tip at the branch's end).
		for j in 3:
			var t := 0.45 + j * 0.25
			var at := out * length * t + Vector3.UP * lerpf(0.25, tip.y, t)
			var d := (out + Vector3.UP * rng.randf_range(0.1, 0.5) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))).normalized()
			var lc := rng.randf_range(0.28, 0.4)
			kit.add_primitive(MeshKit.cylinder(0.0, rng.randf_range(0.2, 0.27), lc, 7), Transform3D(Basis(Quaternion(Vector3.UP, d)), at + d * lc * 0.3), col.lightened(rng.randf_range(-0.05, 0.08)), 0.06, 0.08)
			spots.append(at)
	if not _bare:
		for i in rng.randi_range(16, 22):
			var t: Vector3 = spots[rng.randi() % spots.size()]
			kit.add_primitive(MeshKit.sphere(0.035, 5, 3), Transform3D(Basis(), t + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.08, 0.2), rng.randf_range(-0.15, 0.15))), Color(0.42, 0.5, 0.7).lightened(rng.randf_range(0.0, 0.15)), 0.0, 0.03)


## Sagebrush: a silvery grey-green shrub of many small, lumpy clumps on gnarled, twisting woody stems.
func _sagebrush(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := _vary(Color(0.4, 0.47, 0.4), rng, 0.04)
	var wood := _vary(_pal.dead_wood, rng).darkened(0.2)
	var center := Vector3(0, 0.4, 0)
	for i in rng.randi_range(6, 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.15, 0.5)
		var top := Vector3(cos(a) * d, rng.randf_range(0.45, 0.75), sin(a) * d)
		var kink := Vector3(cos(a + 1.2) * 0.1, 0.22, sin(a + 1.2) * 0.1)
		kit.loft([Vector3(cos(a) * 0.04, -0.05, sin(a) * 0.04), kink, top], [0.04, 0.03, 0.015], 5, wood)
		# Clumps down the stem as well as at its end, so it's a full, rounded shrub.
		for t: float in [0.45, 1.0]:
			var r := rng.randf_range(0.15, 0.23) * (0.85 if t < 1.0 else 1.0)
			var at := kink.lerp(top, t) if t < 1.0 else top
			var off := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.04, 0.1), rng.randf_range(-0.1, 0.1))
			kit.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3(1.15, 0.8, 1.15)), at + off), leaf.lightened(rng.randf_range(-0.08, 0.06)), r * 0.55, 0.1, center)


## Bramble: a low thicket of leaves, long thorny canes arching out of it and down to the ground, clusters of dark
## berries along them.
func _bramble(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var cane := _vary(Color(0.42, 0.22, 0.22), rng)
	var leaf := _vary(_pal.bush_leaves.darkened(0.12), rng)
	var center := Vector3(0, 0.35, 0)
	var spots := []
	for i in rng.randi_range(4, 5):   # the thicket
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * rng.randf_range(0.0, 0.35), rng.randf_range(0.2, 0.4), sin(a) * rng.randf_range(0.0, 0.35))
		var r := rng.randf_range(0.28, 0.4)
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis.from_scale(Vector3(1.1, 0.75, 1.1)), p), leaf.lightened(rng.randf_range(-0.05, 0.06)), r * 0.35, 0.08, center)
		spots.append(p + Vector3(0, r * 0.5, 0))
	for i in rng.randi_range(6, 8):
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var reach := rng.randf_range(0.85, 1.15)
		var top := rng.randf_range(0.45, 0.65)
		var path := [out * rng.randf_range(0.03, 0.08) + Vector3(0, 0.15 + rng.randf_range(0.0, 0.03), 0), out * reach * 0.3 + Vector3.UP * top, out * reach * 0.65 + Vector3.UP * top * 0.75, out * reach + Vector3.UP * 0.05]
		kit.loft(path, [0.022, 0.018, 0.014, 0.009], 4, cane)
		for k in range(1, 3):
			var p: Vector3 = path[k]
			kit.add_primitive(MeshKit.sphere(rng.randf_range(0.16, 0.22), 6, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.2)), p + Vector3(0, 0.02, 0)), leaf.lightened(rng.randf_range(-0.03, 0.08)), 0.06, 0.08)
			spots.append(p + Vector3(0, 0.05, 0))
	if not _bare:
		for i in rng.randi_range(6, 9):
			var t: Vector3 = spots[rng.randi() % spots.size()] + Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
			for j in 4:
				var ripe := rng.randf() < 0.7
				kit.add_primitive(MeshKit.sphere(0.035, 6, 4), Transform3D(Basis(), t + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.02, 0.04), rng.randf_range(-0.04, 0.04))),
					Color(0.16, 0.08, 0.16) if ripe else Color(0.65, 0.18, 0.2), 0.0, 0.04)


## Rhododendron: a tall evergreen shrub of glossy leaf whorls, crowned with round trusses of pink, purple or white
## flowers.
func _rhododendron(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var leaf := _vary(Color(0.18, 0.32, 0.2), rng)
	var bloom: Color = [Color(0.86, 0.45, 0.62), Color(0.62, 0.42, 0.78), Color(0.95, 0.9, 0.92)][index % 3]
	var stem := _vary(_pal.bark, rng)
	for i in rng.randi_range(8, 11):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.1, 0.6)
		var at := Vector3(cos(a) * d, rng.randf_range(0.45, 1.35), sin(a) * d)
		kit.loft([Vector3(cos(a) * 0.05, -0.05, sin(a) * 0.05), at * Vector3(0.5, 0.6, 0.5), at], [0.035, 0.025, 0.015], 4, stem)
		_rosette(kit, rng, at, 6, 0.3, 0.12, 0.35, leaf)
		kit.add_primitive(MeshKit.sphere(0.2, 7, 5), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), at - Vector3(0, 0.05, 0)), leaf.darkened(0.08), 0.06, 0.08)
		if rng.randf() < 0.8:
			for j in 7:
				var f := at + Vector3(rng.randf_range(-0.09, 0.09), 0.08 + rng.randf_range(0.0, 0.09), rng.randf_range(-0.09, 0.09))
				kit.add_primitive(MeshKit.sphere(0.055, 6, 4), Transform3D(Basis(), f), _vary(bloom, rng, 0.04), 0.0, 0.04)


## Ocotillo: a fountain of tall, thin, spiny wands from one root, each tipped with a spike of scarlet flowers.
func _ocotillo(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(Color(0.45, 0.42, 0.34), rng)
	var bloom := Color(0.9, 0.3, 0.18)
	for i in rng.randi_range(9, 13):
		var a := rng.randf() * TAU
		var spread := rng.randf_range(0.15, 0.45)
		var h := rng.randf_range(1.8, 3.0)
		var out := Vector3(cos(a), 0, sin(a))
		var path := [out * 0.04, out * spread * 0.3 + Vector3.UP * h * 0.35, out * spread * 0.75 + Vector3.UP * h * 0.75, out * spread + Vector3.UP * h]
		kit.loft(path, [0.035, 0.028, 0.02, 0.012], 5, col, func(t: float, ang: float) -> Color:
			return col.lightened(0.18) if fposmod(t * 22.0 + ang, 1.0) < 0.18 else col)   # little spines in rows
		if rng.randf() < 0.75:
			var tip: Vector3 = path[3]
			kit.add_primitive(MeshKit.cylinder(0.0, 0.035, 0.22, 5), Transform3D(Basis(), tip + Vector3(0, 0.1, 0)), _vary(bloom, rng, 0.04), 0.0, 0.04)


## Hibiscus: a lush, leafy shrub with big open flowers, red, pink or orange, each with a long stamen.
func _hibiscus(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var leaf := _vary(_pal.jungle_leaves.lerp(_pal.bush_leaves, 0.4), rng)
	var petal: Color = [Color(0.86, 0.16, 0.2), Color(0.95, 0.5, 0.65), Color(0.97, 0.55, 0.22)][index % 3]
	var center := Vector3(0, 0.6, 0)
	var blobs := []
	for i in rng.randi_range(5, 7):
		var r := rng.randf_range(0.3, 0.45)
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.4)
		var pos := Vector3(cos(a) * d, r * 0.9 + rng.randf_range(0.1, 0.5), sin(a) * d)
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(-0.05, 0.07)), r * 0.3, 0.08, center)
	_leaf_clumps(kit, rng, blobs, center, leaf, rng.randi_range(8, 10), 0.14)
	for i in rng.randi_range(10, 14):
		var bl: Array = blobs[rng.randi() % blobs.size()]
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 0.9), rng.randf_range(-1, 1)).normalized()
		var at: Vector3 = bl[0] + dir * (float(bl[1]) * 0.95 + 0.06)
		var flower := PackedVector2Array()
		for k in 10:
			var ang := TAU * k / 10.0
			flower.append(Vector2(cos(ang), sin(ang)) * (0.22 if k % 2 == 0 else 0.13))
		kit.extrude(flower, Transform3D(Basis(Quaternion(Vector3.FORWARD, dir)), at), 0.012, 0.006, _vary(petal, rng, 0.04), petal.lightened(0.25), 0.5)
		kit.loft([at, at + dir * 0.12], [0.008, 0.006], 4, Color(0.98, 0.85, 0.4))


## Sporebush: pale stalks of the fungal groves, each topped with a frilled, softly glowing cap.
func _spore_bush(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var stalk := Color(0.82, 0.78, 0.84)
	var cap: Color = [Color(0.35, 0.75, 0.78), Color(0.62, 0.42, 0.82), Color(0.82, 0.5, 0.7)][index % 3]
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.05, 0.4)
		var h := rng.randf_range(0.5, 1.3)
		var top := Vector3(cos(a) * d * 1.4, h, sin(a) * d * 1.4)
		kit.loft([Vector3(cos(a) * d * 0.3, -0.04, sin(a) * d * 0.3), Vector3(cos(a) * d, h * 0.5, sin(a) * d), top], [0.04, 0.03, 0.025], 6, stalk.darkened(rng.randf_range(0.0, 0.1)))
		var r := rng.randf_range(0.12, 0.2)
		kit.add_primitive(MeshKit.sphere(r, 9, 4), Transform3D(Basis.from_scale(Vector3(1, 0.4, 1)), top + Vector3(0, 0.02, 0)), _vary(cap, rng, 0.04), r * 0.2, 0.05)
		# The frill under the cap: a lighter, wider skirt.
		kit.add_primitive(MeshKit.cylinder(r * 0.4, r * 1.15, 0.05, 9), Transform3D(Basis(), top - Vector3(0, 0.03, 0)), cap.lightened(0.3), 0.0, 0.04)


## Cattails: a clump of long blades from the mud, and stiff stems with brown velvet heads.
func _cattail(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(_pal.reed, rng)
	kit.force_up_normals = true
	for i in rng.randi_range(10, 14):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.2) + Vector3(0, -0.05, 0)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.35)
		var tip := base + lean + Vector3.UP * rng.randf_range(0.9, 1.5)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.028
		kit.add_tri(base - side, base + side, tip, col.darkened(0.25), col.darkened(0.25), col.lightened(0.12))
	kit.force_up_normals = false
	if not _bare:
		for i in rng.randi_range(3, 5):
			var a := rng.randf() * TAU
			var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.15)
			var h := rng.randf_range(1.2, 1.6)
			var top := base + Vector3(rng.randf_range(-0.05, 0.05), h, rng.randf_range(-0.05, 0.05))
			kit.loft([base - Vector3(0, 0.05, 0), top], [0.011, 0.008], 4, col.darkened(0.1))
			kit.add_primitive(MeshKit.sphere(0.045, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 3.4, 1)), top - Vector3(0, 0.17, 0)), Color(0.4, 0.26, 0.16), 0.0, 0.03)


## Aloe: a rosette of thick, pale-spotted, toothed leaves; the second kind sends up a spike of coral flowers.
func _aloe(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var col := _vary(Color(0.42, 0.58, 0.46), rng, 0.04)
	var n := rng.randi_range(9, 12)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.1, 0.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var length := rng.randf_range(0.3, 0.45)
		var rise := rng.randf_range(0.35, 0.6)
		var path := [dir * 0.02, dir * length * 0.45 + Vector3.UP * rise * 0.55, dir * length + Vector3.UP * rise * 0.8]
		kit.loft(path, [0.045, 0.035, 0.0], 5, col, func(t: float, aa: float) -> Color:
			return Color(0.75, 0.82, 0.7) if fposmod(t * 9.0 + aa * 0.7, 1.0) < 0.2 else col,   # pale spots
			func(t: float, aa: float) -> Vector2: return Vector2(1.0, 0.45), true, false)
	if index == 1:
		kit.loft([Vector3(0, 0, 0), Vector3(0.02, 0.5, 0), Vector3(0.03, 0.85, 0)], [0.015, 0.012, 0.008], 4, col.darkened(0.15))
		for j in 6:
			kit.add_primitive(MeshKit.cylinder(0.0, 0.022, 0.07, 5), Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0.03, 0.62 + j * 0.045, 0) + Vector3(cos(j * 2.0), 0, sin(j * 2.0)) * 0.025), Color(0.95, 0.5, 0.3), 0.0, 0.03)


## Wild garlic: a carpet of broad, glossy leaves, with stems of starry white flower heads.
func _wild_garlic(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(Color(0.3, 0.52, 0.26), rng)
	for i in rng.randi_range(4, 6):
		var at := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		_rosette(kit, rng, at, 4, 0.26, 0.1, 0.6, col)
	for i in rng.randi_range(2, 4):
		var base := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var top := base + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.28, 0.4), rng.randf_range(-0.04, 0.04))
		kit.loft([base - Vector3(0, 0.03, 0), top], [0.008, 0.006], 4, col.darkened(0.1))
		for j in 7:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1), rng.randf_range(-1, 1)).normalized()
			kit.add_primitive(MeshKit.sphere(0.018, 5, 3), Transform3D(Basis(), top + d * 0.04), Color(0.96, 0.96, 0.92), 0.0, 0.02)


## Lingonberry: a low carpet of tiny glossy leaves on wiry stems, hung with bright red berries.
func _lingonberry(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var col := _vary(Color(0.2, 0.36, 0.2), rng)
	var spots := []
	for i in rng.randi_range(9, 13):
		var at := Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.06, 0.18), rng.randf_range(-0.35, 0.35))
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.08, 0.12), 6, 4), Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), at), col.lightened(rng.randf_range(-0.05, 0.08)), 0.03, 0.07)
		spots.append(at)
	if not _bare:
		for i in rng.randi_range(12, 18):
			var at: Vector3 = spots[rng.randi() % spots.size()]
			kit.add_primitive(MeshKit.sphere(0.025, 5, 3), Transform3D(Basis(), at + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.02, 0.08), rng.randf_range(-0.08, 0.08))),
				Color(0.82, 0.12, 0.14).lightened(rng.randf_range(0.0, 0.12)), 0.0, 0.03)


# Ground plants: small and many, so few triangles each.

## Lupins: spires of blue, purple or pink pea-flowers over a ring of fingered leaves.
func _lupin(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var bloom: Color = [Color(0.42, 0.45, 0.85), Color(0.6, 0.38, 0.75), Color(0.9, 0.55, 0.7)][index % 3]
	var leaf := _pal.meadow_grass.darkened(0.15)
	kit.force_up_normals = true
	for i in rng.randi_range(2, 4):
		var base := Vector3(rng.randf_range(-0.2, 0.2), -0.03, rng.randf_range(-0.2, 0.2))
		var h := rng.randf_range(0.45, 0.75)
		for l in 5:
			var a := TAU * l / 5.0 + rng.randf()
			kit.add_tri(base, base + Vector3(cos(a) * 0.15 - sin(a) * 0.03, 0.12, sin(a) * 0.15 + cos(a) * 0.03), base + Vector3(cos(a) * 0.15 + sin(a) * 0.03, 0.12, sin(a) * 0.15 - cos(a) * 0.03), leaf)
		kit.add_tri(base - Vector3(0.012, 0, 0), base + Vector3(0.012, 0, 0), base + Vector3(0, h * 0.6, 0), leaf.darkened(0.1))
		kit.force_up_normals = false
		kit.add_primitive(MeshKit.cylinder(0.0, 0.055, h * 0.5, 6), Transform3D(Basis(), base + Vector3(0, h * 0.72, 0)), _vary(bloom, rng, 0.05), 0.08, 0.06)
		kit.force_up_normals = true


## Daisies: a little patch of white flowers with golden middles on thin stems.
func _daisy(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var stem := _pal.meadow_grass.darkened(0.2)
	for i in rng.randi_range(4, 7):
		var base := Vector3(rng.randf_range(-0.25, 0.25), -0.03, rng.randf_range(-0.25, 0.25))
		var top := base + Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.15, 0.3), rng.randf_range(-0.04, 0.04))
		kit.add_tri(base - Vector3(0.01, 0, 0.008), base + Vector3(0.01, 0, 0.008), top, stem)
		var white := Color(0.97, 0.96, 0.92)
		for k in 6:
			var a1 := TAU * k / 6.0
			kit.add_tri(top + Vector3(0, 0.004, 0), top + Vector3(cos(a1 - 0.25), 0.0, sin(a1 - 0.25)) * 0.055, top + Vector3(cos(a1 + 0.25), 0.0, sin(a1 + 0.25)) * 0.055, white)
		kit.add_primitive(MeshKit.sphere(0.018, 5, 3), Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), top + Vector3(0, 0.01, 0)), Color(0.96, 0.78, 0.2), 0.0, 0.02)


## Foxgloves: one or two tall spires hung with drooping pink or purple bells, over a rosette of soft leaves.
func _foxglove(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var bloom: Color = [Color(0.85, 0.45, 0.7), Color(0.66, 0.42, 0.8)][index % 2]
	var leaf := _pal.fern.darkened(0.05)
	_rosette(kit, rng, Vector3(0, 0.0, 0), 6, 0.28, 0.11, 0.25, leaf)
	for s in rng.randi_range(1, 2):
		var base := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
		var h := rng.randf_range(0.8, 1.15)
		kit.loft([base - Vector3(0, 0.04, 0), base + Vector3(0.02, h, 0)], [0.012, 0.007], 4, leaf.darkened(0.1))
		for j in 7:
			var y := h * (0.45 + j * 0.075)
			var a := j * 2.4
			var at := base + Vector3(cos(a) * 0.04 + 0.02 * y / h, y, sin(a) * 0.04)
			kit.add_primitive(MeshKit.cylinder(0.035, 0.012, 0.07, 6), Transform3D(Basis(Vector3(sin(a), 0, -cos(a)), 0.5), at), _vary(bloom, rng, 0.04).lightened(j * 0.02), 0.0, 0.04)


## Sedge: a stiff, arching tuft of dark grassy blades with brown seed spikes.
func _sedge(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(Color(0.32, 0.45, 0.25), rng)
	for i in rng.randi_range(9, 13):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.12) + Vector3(0, -0.04, 0)
		var out := Vector3(cos(a), 0, sin(a))
		var mid := base + out * 0.12 + Vector3.UP * rng.randf_range(0.35, 0.5)
		var tip := base + out * rng.randf_range(0.3, 0.45) + Vector3.UP * rng.randf_range(0.25, 0.4)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.02
		kit.add_tri(base - side, base + side, mid, col.darkened(0.25), col.darkened(0.25), col)
		kit.add_tri(mid - side * 0.6, mid + side * 0.6, tip, col, col, col.lightened(0.15))
	for i in rng.randi_range(2, 3):
		var base := Vector3(rng.randf_range(-0.06, 0.06), -0.04, rng.randf_range(-0.06, 0.06))
		var top := base + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.5, 0.65), rng.randf_range(-0.05, 0.05))
		kit.add_tri(base - Vector3(0.008, 0, 0), base + Vector3(0.008, 0, 0), top, col.darkened(0.15))
		kit.add_tri(top - Vector3(0.02, 0.1, 0), top + Vector3(0.02, -0.1, 0), top + Vector3(0, 0.02, 0), Color(0.45, 0.32, 0.2))


## Desert blooms: a low tuft of grey-green leaves bursting with small bright flowers after the rains.
func _desert_bloom(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var bloom: Color = [Color(0.98, 0.62, 0.18), Color(0.98, 0.85, 0.25), Color(0.9, 0.3, 0.6)][index % 3]
	var leaf := Color(0.52, 0.58, 0.46)
	kit.force_up_normals = true
	for i in rng.randi_range(6, 9):
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.14, 0.1, sin(a) * 0.14)
		kit.add_tri(Vector3(-0.01, -0.02, 0), Vector3(0.01, -0.02, 0), tip, leaf.darkened(0.15), leaf.darkened(0.15), leaf)
	for i in rng.randi_range(4, 7):
		var at := Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.1, 0.2), rng.randf_range(-0.15, 0.15))
		kit.add_tri(Vector3(at.x - 0.006, -0.02, at.z), Vector3(at.x + 0.006, -0.02, at.z), at, leaf.darkened(0.2))
		for k in 5:
			var a1 := TAU * k / 5.0
			kit.add_tri(at + Vector3(0, 0.004, 0), at + Vector3(cos(a1 - 0.3), 0.01, sin(a1 - 0.3)) * 0.045, at + Vector3(cos(a1 + 0.3), 0.01, sin(a1 + 0.3)) * 0.045, _vary(bloom, rng, 0.04))


## Bromeliad: a vase of stiff, arching strap leaves on the forest floor, flushed red, pink or orange at the heart.
func _bromeliad(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var leaf := _vary(_pal.fern.lightened(0.05), rng)
	var heart: Color = [Color(0.86, 0.2, 0.22), Color(0.95, 0.45, 0.2)][index % 2]
	_rosette(kit, rng, Vector3(0, 0.0, 0), 9, 0.38, 0.09, 0.8, leaf)
	_rosette(kit, rng, Vector3(0, 0.04, 0), 5, 0.2, 0.07, 1.6, heart)
	kit.add_primitive(MeshKit.cylinder(0.0, 0.04, 0.14, 6), Transform3D(Basis(), Vector3(0, 0.12, 0)), heart.lightened(0.15), 0.0, 0.03)


## Cotton grass: fine sedge blades with nodding tufts of white cotton on thin stems.
func _cotton_grass(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(Color(0.45, 0.5, 0.32), rng)
	for i in rng.randi_range(6, 9):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.1) + Vector3(0, -0.04, 0)
		var tip := base + Vector3(cos(a), 0, sin(a)) * 0.1 + Vector3.UP * rng.randf_range(0.2, 0.32)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.015
		kit.add_tri(base - side, base + side, tip, col.darkened(0.2), col.darkened(0.2), col.lightened(0.1))
	kit.force_up_normals = false
	for i in rng.randi_range(3, 6):
		var base := Vector3(rng.randf_range(-0.12, 0.12), -0.04, rng.randf_range(-0.12, 0.12))
		var top := base + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.35, 0.5), rng.randf_range(-0.05, 0.05))
		kit.add_tri(base - Vector3(0.006, 0, 0), base + Vector3(0.006, 0, 0), top, col.darkened(0.1))
		kit.add_primitive(MeshKit.sphere(0.045, 6, 4), Transform3D(Basis.from_scale(Vector3(1, 1.25, 1)), top + Vector3(0, 0.02, 0)), Color(0.97, 0.97, 0.94), 0.25, 0.04)


## Lichen: crusty, flat rosettes of grey-green, sulphur yellow or rusty orange spread over the ground.
func _lichen(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var col: Color = [Color(0.6, 0.66, 0.55), Color(0.82, 0.78, 0.35), Color(0.82, 0.5, 0.28)][index % 3]
	for i in rng.randi_range(4, 7):
		var at := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var r := rng.randf_range(0.08, 0.18)
		kit.add_primitive(MeshKit.cylinder(r * 0.8, r, 0.025, 7), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, 1, rng.randf_range(0.6, 1.0))), at + Vector3(0, 0.005, 0)), _vary(col, rng, 0.05), r * 0.3, 0.1)


## Puffballs: a cluster of round, papery white and tan fungi, the biggest split open at the top.
func _puffball(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 6):
		var r := rng.randf_range(0.05, 0.13)
		var at := Vector3(rng.randf_range(-0.2, 0.2), r * 0.7, rng.randf_range(-0.2, 0.2))
		var col := Color(0.93, 0.9, 0.82).lerp(Color(0.72, 0.6, 0.45), rng.randf_range(0.0, 0.6))
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 0.85, 1)), at), col, r * 0.15, 0.05)
		if r > 0.1:
			kit.add_primitive(MeshKit.cylinder(r * 0.25, r * 0.35, 0.02, 7), Transform3D(Basis(), at + Vector3(0, r * 0.8, 0)), col.darkened(0.45), 0.0, 0.03)


## Dune grass: tall, wiry, sun-bleached blades leaning in the sea wind.
func _dune_grass(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	kit.force_up_normals = true
	var col := _vary(Color(0.7, 0.68, 0.46), rng, 0.04)
	var wind := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.15
	for i in rng.randi_range(10, 14):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.15) + Vector3(0, -0.04, 0)
		var h := rng.randf_range(0.55, 0.85)
		var mid := base + Vector3(cos(a), 0, sin(a)) * 0.06 + wind * 0.4 + Vector3.UP * h * 0.55
		var tip := base + Vector3(cos(a), 0, sin(a)) * 0.14 + wind + Vector3.UP * h
		var side := Vector3(-sin(a), 0, cos(a)) * 0.016
		kit.add_tri(base - side, base + side, mid, col.darkened(0.25), col.darkened(0.25), col)
		kit.add_tri(mid - side * 0.6, mid + side * 0.6, tip, col, col, col.lightened(0.15))


## Sea thrift: a tight green cushion on the sand with pink pompom flowers on wiry stems.
func _sea_thrift(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := _vary(Color(0.36, 0.5, 0.34), rng)
	kit.add_primitive(MeshKit.sphere(rng.randf_range(0.12, 0.16), 7, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.55, 1.2)), Vector3(0, 0.03, 0)), leaf, 0.04, 0.08)
	for i in rng.randi_range(4, 7):
		var base := Vector3(rng.randf_range(-0.1, 0.1), 0.04, rng.randf_range(-0.1, 0.1))
		var top := base + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.14, 0.24), rng.randf_range(-0.05, 0.05))
		kit.loft([base, top], [0.005, 0.004], 3, leaf.darkened(0.1))
		kit.add_primitive(MeshKit.sphere(0.035, 6, 4), Transform3D(Basis(), top + Vector3(0, 0.02, 0)), _vary(Color(0.92, 0.55, 0.72), rng, 0.04), 0.15, 0.04)


## Alpine cushion: a dense, bright moss-like cushion hugging the rock, starred with tiny pink, white or purple flowers.
func _alpine_cushion(kit: MeshKit, rng: RandomNumberGenerator, index: int) -> void:
	var leaf := _vary(Color(0.38, 0.55, 0.3), rng)
	var bloom: Color = [Color(0.92, 0.5, 0.68), Color(0.96, 0.95, 0.9), Color(0.66, 0.48, 0.82)][index % 3]
	var spots := []
	for i in rng.randi_range(2, 4):
		var at := Vector3(rng.randf_range(-0.15, 0.15), 0.02, rng.randf_range(-0.15, 0.15))
		var r := rng.randf_range(0.12, 0.2)
		kit.add_primitive(MeshKit.sphere(r, 6, 3), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 1.0)), at), leaf.lightened(rng.randf_range(-0.04, 0.06)), r * 0.25, 0.08)
		spots.append([at, r])
	for i in rng.randi_range(8, 12):
		var sp: Array = spots[rng.randi() % spots.size()]
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.8) * float(sp[1])
		var at: Vector3 = sp[0] + Vector3(cos(a) * d, float(sp[1]) * 0.45 * sqrt(1.0 - (d / float(sp[1])) * (d / float(sp[1]))) + 0.005, sin(a) * d)
		kit.add_primitive(MeshKit.sphere(0.02, 4, 2), Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), at), _vary(bloom, rng, 0.04), 0.0, 0.03)


## Edelweiss: a little silvery rosette with white, felted, star-shaped flowers on short stems.
func _edelweiss(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var leaf := Color(0.62, 0.68, 0.6)
	_rosette(kit, rng, Vector3(0, 0.0, 0), 6, 0.1, 0.04, 0.4, leaf)
	kit.force_up_normals = true
	for i in rng.randi_range(2, 4):
		var base := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var top := base + Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.1, 0.17), rng.randf_range(-0.03, 0.03))
		kit.add_tri(base - Vector3(0.006, 0, 0), base + Vector3(0.006, 0, 0), top, leaf.darkened(0.15))
		for k in 7:
			var a1 := TAU * k / 7.0
			kit.add_tri(top + Vector3(0, 0.004, 0), top + Vector3(cos(a1 - 0.18), 0.0, sin(a1 - 0.18)) * 0.045, top + Vector3(cos(a1 + 0.18), 0.0, sin(a1 + 0.18)) * 0.045, Color(0.95, 0.95, 0.9))
		kit.add_primitive(MeshKit.sphere(0.014, 5, 3), Transform3D(Basis(), top + Vector3(0, 0.008, 0)), Color(0.9, 0.85, 0.55), 0.0, 0.02)
