class_name ItemDB
extends RefCounted
## Every item in the game: a fixed set of base items plus items generated per world
## (tier materials, tools named after them, fruits, mushrooms and herbs with effects).
## Call ItemDB.build(seed, palette) when a world is created; the rest is static lookups.
##
## Item fields:
##  name, kind (resource | food | tool | material), stack, icon (how ItemIcon draws it),
##  color (+ color2), tier, desc
##  tool:   {type, tier, tree, rock, bush, carcass (gather multipliers), damage, cooldown, durability}
##  food:   hunger restored, health: instant health change, effect: status effect id

## Material tiers. 0-1 and 5 are fixed; 2-4 are generated per world (the twist): every island has
## its own metals and gem, with their own names, colors, traits and places they're found.
## The last tier is forged from the essence of the night's shadow creatures.
const TIER_POWER := [0.6, 1.0, 1.45, 1.95, 2.6, 3.4]
const TRAITS := {
	"swift": {"name": "Swift", "desc": "Swings 20% faster."},
	"keen": {"name": "Keen", "desc": "Gathers 30% more."},
	"sturdy": {"name": "Sturdy", "desc": "Lasts 60% longer."},
	"vicious": {"name": "Vicious", "desc": "Hits creatures 35% harder."},
	"luminous": {"name": "Luminous", "desc": "Glows softly; strikes harder at night."},
}

## Tool types: base gather multipliers per target, damage vs creatures, swing time, durability factor.
const TOOL_TYPES := {
	"hatchet": {"name": "Hatchet", "tree": 1.0, "rock": 0.2, "bush": 1.0, "carcass": 0.5, "damage": 12.0, "cooldown": 0.75, "dur": 1.0},
	"pickaxe": {"name": "Pickaxe", "tree": 0.3, "rock": 1.0, "bush": 0.6, "carcass": 0.3, "damage": 11.0, "cooldown": 0.85, "dur": 1.0},
	"spear": {"name": "Spear", "tree": 0.1, "rock": 0.05, "bush": 0.5, "carcass": 0.4, "damage": 22.0, "cooldown": 0.7, "dur": 0.8},
	"knife": {"name": "Knife", "tree": 0.15, "rock": 0.0, "bush": 1.3, "carcass": 1.6, "damage": 9.0, "cooldown": 0.45, "dur": 0.9},
}

## Status effects that food/herbs can give.
const EFFECTS := {
	"mend": {"name": "Mending", "desc": "Heals over time.", "time": 12.0},
	"vigor": {"name": "Vigor", "desc": "Stamina recovers twice as fast.", "time": 60.0},
	"satiate": {"name": "Sated", "desc": "Hunger drains much slower.", "time": 150.0},
	"poison": {"name": "Poisoned", "desc": "Loses health over time.", "time": 10.0},
}

const BASE_ITEMS := {
	"wood": {"name": "Wood", "kind": "resource", "stack": 250, "icon": "logs", "desc": "Chopped from trees."},
	"sticks": {"name": "Sticks", "kind": "resource", "stack": 250, "icon": "sticks", "desc": "Gathered by hand from trees and brush."},
	"stone": {"name": "Stone", "kind": "resource", "stack": 250, "icon": "stone", "desc": "Broken off rocks."},
	"flint": {"name": "Flint", "kind": "resource", "stack": 100, "icon": "flint", "desc": "Sharp stone, found among loose pebbles.", "tier": 1},
	"fiber": {"name": "Plant Fiber", "kind": "resource", "stack": 250, "icon": "fiber", "desc": "Pulled from bushes, reeds and cacti."},
	"resin": {"name": "Resin", "kind": "resource", "stack": 100, "icon": "resin", "desc": "Sticky sap from conifers."},
	"hide": {"name": "Hide", "kind": "resource", "stack": 100, "icon": "hide", "desc": "Skinned from animals."},
	"bone": {"name": "Bone", "kind": "resource", "stack": 100, "icon": "bone", "desc": "From animal carcasses."},
	"raw_meat": {"name": "Raw Meat", "kind": "food", "stack": 40, "icon": "meat", "food": 16.0, "health": -4.0, "desc": "Filling, but it should really be cooked."},
	"cactus_flesh": {"name": "Cactus Flesh", "kind": "food", "stack": 40, "icon": "cactus", "food": 5.0, "health": 3.0, "desc": "Watery and a little sour."},
	"charcoal": {"name": "Charcoal", "kind": "material", "stack": 100, "icon": "charcoal", "desc": "Wood burnt slow in a campfire. Burns hot enough to smelt ore."},
	"essence": {"name": "Shadow Essence", "kind": "material", "stack": 50, "icon": "essence", "tier": 5, "desc": "Left behind by shadow creatures. Forges Duskforged tools."},
	# Crafted materials
	"rope": {"name": "Rope", "kind": "material", "stack": 50, "icon": "rope", "desc": "Twisted plant fiber. Lashes tools and frames together."},
	"plank": {"name": "Planks", "kind": "material", "stack": 100, "icon": "plank", "desc": "Split and smoothed at a workbench."},
	"leather": {"name": "Leather", "kind": "material", "stack": 50, "icon": "leather", "desc": "Cured hide. Wraps grips and makes straps."},
	# Crafted food & medicine
	"cooked_meat": {"name": "Cooked Meat", "kind": "food", "stack": 40, "icon": "cooked_meat", "food": 30.0, "health": 5.0, "desc": "Seared over a campfire. Much better."},
	"roast_fruit": {"name": "Roasted Fruit", "kind": "food", "stack": 40, "icon": "roast_fruit", "food": 24.0, "health": 6.0, "desc": "Soft, caramelised and warm."},
	"stew": {"name": "Hearty Stew", "kind": "food", "stack": 10, "icon": "stew", "food": 55.0, "health": 12.0, "effect": "satiate", "desc": "Meat and berries simmered in a wooden bowl. Keeps you full for a long time."},
	"bandage": {"name": "Bandage", "kind": "food", "stack": 20, "icon": "bandage", "food": 0.0, "health": 15.0, "effect": "mend", "verb": "Apply", "desc": "Fiber wrap sealed with resin. Stops bleeding and heals over time."},
	# Light
	"torch": {"name": "Torch", "kind": "tool", "stack": 1, "icon": "torch", "tier": 0, "desc": "Lights the way at night. Burns down as you swing it.",
		"tool": {"type": "torch", "tier": 0, "tree": 0.1, "rock": 0.0, "bush": 0.6, "carcass": 0.2, "damage": 8.0, "cooldown": 0.6, "durability": 120}},
	# Building: the plan lays blueprints (pick the piece and material on its wheel), the hammer builds and repairs them.
	"building_plan": {"name": "Building Plan", "kind": "tool", "stack": 1, "icon": "plan", "tier": 0,
		"desc": "Hold right mouse to pick a piece and its material, then place its blueprint. Blueprints are free; a hammer builds them.",
		"tool": {"type": "plan", "tier": 0, "tree": 0.0, "rock": 0.0, "bush": 0.0, "carcass": 0.0, "damage": 0.0, "cooldown": 0.4, "durability": -1}},
	"hammer": {"name": "Hammer", "kind": "tool", "stack": 1, "icon": "hammer", "tier": 0,
		"desc": "Builds blueprints a share at a time, taking materials with each hit, and repairs damaged pieces. Shows a piece's health.",
		"tool": {"type": "hammer", "tier": 0, "tree": 0.0, "rock": 0.0, "bush": 0.3, "carcass": 0.0, "damage": 6.0, "cooldown": 0.55, "durability": 600}},
	# Placeable stations
	"campfire": {"name": "Campfire", "kind": "placeable", "stack": 5, "icon": "campfire", "station": "campfire", "desc": "Place it, then cook food and light up the night."},
	"workbench": {"name": "Workbench", "kind": "placeable", "stack": 5, "icon": "workbench", "station": "workbench", "desc": "Place it to craft planks, metal tools and better gear."},
	"forge": {"name": "Forge", "kind": "placeable", "stack": 5, "icon": "forge", "station": "forge", "desc": "Place it to smelt ore into ingots and forge the best tools."},
	"foundation": {"name": "Foundation", "kind": "piece", "stack": 10, "icon": "foundation", "station": "foundation", "desc": "A flat stone slab. Placing it levels the ground under it."},
	"wall": {"name": "Brick Wall", "kind": "piece", "stack": 10, "icon": "wall", "station": "wall", "desc": "A brick wall. Place it on the edge of a foundation."},
	"wood_wall": {"name": "Plank Wall", "kind": "piece", "stack": 10, "icon": "wood_wall", "station": "wood_wall", "desc": "A plank wall. Place it on the edge of a foundation."},
	"doorway": {"name": "Doorway", "kind": "piece", "stack": 10, "icon": "doorway", "station": "doorway", "desc": "A brick wall with an opening to walk through."},
	"roof": {"name": "Roof", "kind": "piece", "stack": 10, "icon": "roof", "station": "roof", "desc": "A tiled roof. Needs a foundation and at least two walls under it."},
	"wood_floor": {"name": "Plank Floor", "kind": "piece", "stack": 10, "icon": "wood_floor", "station": "wood_floor", "desc": "Planks on dark beams. Placed like a foundation: it levels the ground under it, and walls stand on it."},
	"window_wall": {"name": "Window Wall", "kind": "piece", "stack": 10, "icon": "window_wall", "station": "window_wall", "desc": "A brick wall with a glazed window in the middle. Place it on the edge of a foundation."},
	"wood_doorway": {"name": "Plank Doorway", "kind": "piece", "stack": 10, "icon": "wood_doorway", "station": "wood_doorway", "desc": "A plank wall with an opening to walk through."},
	"brick_floor": {"name": "Brick Floor", "kind": "piece", "stack": 10, "icon": "piece", "shape": "floor", "mat": "brick", "station": "brick_floor", "desc": "Brick pavers on a mortar bed. Placed like a foundation: it levels the ground, and walls stand on it."},
	"stone_wall": {"name": "Stone Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "wall", "mat": "stone", "station": "stone_wall", "desc": "A wall of rough stone in courses. Place it on the edge of a floor."},
	"brick_half": {"name": "Brick Half Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "half", "mat": "brick", "station": "brick_half", "desc": "A knee-high brick wall. Fences a floor's edge; it doesn't hold a roof up."},
	"wood_half": {"name": "Plank Half Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "half", "mat": "wood", "station": "wood_half", "desc": "A knee-high plank wall. Fences a floor's edge; it doesn't hold a roof up."},
	"stone_half": {"name": "Stone Half Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "half", "mat": "stone", "station": "stone_half", "desc": "A knee-high wall of stone. Fences a floor's edge; it doesn't hold a roof up."},
	"wood_window": {"name": "Plank Window Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "window", "mat": "wood", "station": "wood_window", "desc": "A plank wall with a glazed window in the middle."},
	"stone_window": {"name": "Stone Window Wall", "kind": "piece", "stack": 10, "icon": "piece", "shape": "window", "mat": "stone", "station": "stone_window", "desc": "A stone wall with a glazed window in the middle."},
	"stone_doorway": {"name": "Stone Doorway", "kind": "piece", "stack": 10, "icon": "piece", "shape": "doorway", "mat": "stone", "station": "stone_doorway", "desc": "A stone wall with an opening to walk through."},
	"brick_door": {"name": "Brick Door", "kind": "piece", "stack": 10, "icon": "piece", "shape": "door", "mat": "brick", "station": "brick_door", "desc": "A brick wall with a hinged plank door. Use it to swing the door open or shut."},
	"wood_door": {"name": "Plank Door", "kind": "piece", "stack": 10, "icon": "piece", "shape": "door", "mat": "wood", "station": "wood_door", "desc": "A plank wall with a hinged door. Use it to swing the door open or shut."},
	"stone_door": {"name": "Stone Door", "kind": "piece", "stack": 10, "icon": "piece", "shape": "door", "mat": "stone", "station": "stone_door", "desc": "A stone wall with a hinged plank door. Use it to swing the door open or shut."},
	"brick_stairs": {"name": "Brick Stairs", "kind": "piece", "stack": 10, "icon": "piece", "shape": "stairs", "mat": "brick", "station": "brick_stairs", "desc": "Twelve steps up one storey. Needs a floor to climb from and nothing overhead."},
	"wood_stairs": {"name": "Plank Stairs", "kind": "piece", "stack": 10, "icon": "piece", "shape": "stairs", "mat": "wood", "station": "wood_stairs", "desc": "Twelve plank steps up one storey. Needs a floor to climb from and nothing overhead."},
	"stone_stairs": {"name": "Stone Stairs", "kind": "piece", "stack": 10, "icon": "piece", "shape": "stairs", "mat": "stone", "station": "stone_stairs", "desc": "Twelve stone steps up one storey. Needs a floor to climb from and nothing overhead."},
	"wood_roof": {"name": "Shingle Roof", "kind": "piece", "stack": 10, "icon": "piece", "shape": "roof", "mat": "wood", "station": "wood_roof", "desc": "A roof of overlapping wooden shingles. Needs a foundation and at least two walls under it."},
	"stone_roof": {"name": "Slate Roof", "kind": "piece", "stack": 10, "icon": "piece", "shape": "roof", "mat": "stone", "station": "stone_roof", "desc": "A roof of grey slates. Needs a foundation and at least two walls under it."},
	"brick": {"name": "Stone Brick", "kind": "material", "stack": 100, "icon": "brick", "color": Color(0.7, 0.5, 0.38), "desc": "Chiseled stone. For brick walls and floors, and for building a forge."},
	"rock": {"name": "Rock", "kind": "tool", "stack": 1, "icon": "tool", "tier": 0, "desc": "A fist-sized flint rock. Better than bare hands.",
		"tool": {"type": "rock", "tier": 0, "tree": 0.6, "rock": 0.6, "bush": 1.0, "carcass": 0.6, "damage": 10.0, "cooldown": 0.7, "durability": 110}},
}

## Bare hands: slow on wood, useless on stone, fine for bushes.
const HANDS := {"type": "hands", "tier": -1, "tree": 0.15, "rock": 0.0, "bush": 0.8, "carcass": 0.3, "damage": 4.0, "cooldown": 0.5, "durability": 0}

## Destroying with a swing: what each hit gives at multiplier 1.0: [item, min, max].
const YIELDS := {
	"tree": [["wood", 4, 6]],
	"rock": [["stone", 3, 5]],
	# Ore deposits chip stone with each swing; the ore itself comes out when the deposit breaks (BONUS).
	"ore_t2": [["stone", 0, 1]],
	"ore_t3": [["stone", 0, 1]],
	"gem_t4": [["gem_t4", 1, 1]],
	"bush": [["fiber", 1, 2]],
	"berry": [["fiber", 1, 2]],
	"boulder": [["stone", 4, 6]],
	"cactus": [["fiber", 1, 2], ["cactus_flesh", 0, 1]],
	"reeds": [["fiber", 2, 3]],
	"dead_bush": [["sticks", 1, 2]],
	"log": [["wood", 3, 5]],
	"mushroom": [],
	"herb": [],
	"pebbles": [["stone", 1, 2]],
	"cache": [],
	"giant_mushroom": [["fiber", 1, 2], ["wood", 1, 2]],
}
## Extra reward for finishing a node off.
const BONUS := {
	"tree": [["wood", 8, 12]],
	"rock": [["stone", 6, 9]],
	"ore_t2": [["ore_t2", 5, 7]],   # about two ingots a deposit (scaled by the difficulty's "ore")
	"ore_t3": [["ore_t3", 5, 7]],
	"gem_t4": [["gem_t4", 1, 2]],
	"boulder": [["stone", 10, 14], ["ore_t2", 0, 2]],
	"cactus": [["fiber", 2, 3]],
	"log": [["wood", 6, 9]],
	"giant_mushroom": [["wood", 4, 7], ["fiber", 3, 5]],
}
## Harvesting by hand (Interact): [item, min, max, chance]. Doesn't destroy the node.
const HARVEST := {
	"berry": [["berries", 2, 4, 1.0], ["fiber", 0, 1, 0.5]],
	"bush": [["fiber", 1, 2, 1.0], ["sticks", 0, 1, 0.5]],
	"reeds": [["fiber", 2, 3, 1.0]],
	"dead_bush": [["sticks", 1, 3, 1.0]],
	"tree": [["sticks", 1, 2, 1.0]],
	"conifer": [["sticks", 1, 2, 1.0], ["resin", 1, 1, 0.35]],
	"fruit_tree": [["sticks", 0, 1, 1.0], ["fruit", 1, 3, 1.0]],
	"cactus": [["cactus_flesh", 1, 2, 1.0], ["fiber", 0, 1, 0.5]],
	"carcass": [["raw_meat", 1, 2, 1.0], ["hide", 1, 1, 0.6], ["bone", 1, 1, 0.35]],
	# These are picked up (the node is removed):
	"mushroom": [["mushroom_%d", 1, 2, 1.0]],
	"herb": [["herb_%d", 1, 2, 1.0]],
	"pebbles": [["stone", 1, 2, 1.0], ["flint", 1, 1, 0.45]],
	"scree": [["stone", 2, 4, 1.0], ["flint", 1, 1, 0.5]],
	"branch": [["sticks", 2, 4, 1.0]],
	"tumbleweed": [["sticks", 1, 2, 1.0], ["fiber", 1, 2, 1.0]],
	"sapling": [["sticks", 1, 3, 1.0], ["fiber", 0, 1, 0.5]],
	"agave": [["fiber", 2, 3, 1.0]],
	"giant_mushroom": [["mushroom_%d", 1, 3, 1.0], ["fiber", 0, 1, 0.5]],
	"glowcap": [["mushroom_%d", 1, 2, 1.0], ["fiber", 0, 1, 0.4]],
}
## Hand-harvesting these picks the whole thing up (the node is removed).
const PICKUP_KEYS := ["mushroom", "herb", "pebbles", "scree", "branch", "tumbleweed", "sapling"]
## HP damage per hit at multiplier 1.0 (trees have 100 HP -> 6 hits with a stone hatchet).
const HIT_DAMAGE := 17.0
## Share of the per-hit yield you actually get (difficulty: resources take some effort).
const GATHER_RATE := 0.8

static var _items := {}
static var _tiers: Array[Dictionary] = []
static var fruit_tree := "oak"   ## which tree kind bears fruit on this world


# --- Building the per-world registry ------------------------------------------------

## Names and descriptions for building pieces that aren't listed above by hand (from GameActions.PIECES).
const PIECE_MAT_NAMES := {"wood": "Plank", "stone": "Stone", "brick": "Brick"}
const PIECE_SHAPES := {
	"fence": ["Fence", "A rail fence between posts. Fences a floor's edge; it doesn't hold a roof up."],
	"arch": ["Archway", "A wall with a tall arched opening to walk through. Holds a roof up."],
	"shutters": ["Shuttered Window", "A wall with a glazed window and painted shutters folded open beside it."],
}


static func _piece_items() -> void:
	for kind: String in GameActions.PIECES:
		if _items.has(kind):
			continue
		var spec: Dictionary = GameActions.PIECES[kind]
		var shape: Array = PIECE_SHAPES.get(spec.shape, [String(spec.shape).capitalize(), ""])
		_items[kind] = {"name": "%s %s" % [PIECE_MAT_NAMES.get(spec.mat, ""), shape[0]], "kind": "piece", "stack": 10, "icon": "piece",
			"shape": spec.shape, "mat": spec.mat, "station": kind, "desc": shape[1]}

static func build(seed_value: int, pal: WorldPalette) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 613 + 29
	_items = BASE_ITEMS.duplicate(true)
	_piece_items()
	_tiers = []

	# Tiers 0 (rock) and 1 (stone) are fixed; 2-4 are this world's own materials.
	_tiers.append({"name": "Rock", "color": pal.rock, "trait": ""})
	_tiers.append({"name": "Stone", "color": pal.rock.lightened(0.1), "trait": ""})
	var traits := TRAITS.keys()
	_shuffle(traits, rng)
	var suffixes := [["ite", "ium", "or", "ane"], ["ium", "yx", "ite", "orn"], ["", "", "", ""]]
	for t in [2, 3, 4]:
		var base := NameGen.word(rng, 2, 2)
		var name: String = (base.substr(0, 7) + suffixes[t - 2][rng.randi() % 4]).capitalize()
		var col: Color
		match t:
			2: col = Color.from_hsv(rng.randf_range(0.02, 0.12), rng.randf_range(0.35, 0.55), rng.randf_range(0.6, 0.75))   # coppery
			3:   # a distinctly different, cooler metal than tier 2
				col = Color.from_hsv(fposmod(_tiers[2].color.h + rng.randf_range(0.35, 0.65), 1.0), rng.randf_range(0.38, 0.55), rng.randf_range(0.68, 0.8))
			_: col = Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.8), rng.randf_range(0.85, 1.0))                     # gem
		_tiers.append({"name": name, "color": col, "trait": traits[t - 2]})
		var raw_id := "gem_t4" if t == 4 else "ore_t%d" % t
		_items[raw_id] = {
			"name": "%s %s" % [name, "Shard" if t == 4 else "Ore"], "kind": "material", "stack": 100,
			"icon": "gem" if t == 4 else "ore", "color": col, "tier": t,
			"desc": "Tier %d material. %s tools are %s." % [t, name, TRAITS[traits[t - 2]].name.to_lower()],
		}
	_tiers.append({"name": "Duskforged", "color": Color(0.36, 0.22, 0.55), "trait": "luminous"})
	for t in [2, 3]:
		_items["ingot_t%d" % t] = {"name": "%s Ingot" % _tiers[t].name, "kind": "material", "stack": 50, "icon": "ingot",
			"color": _tiers[t].color, "tier": t, "desc": "Smelted at a forge. Makes tier %d tools." % t}
	_items["cut_gem"] = {"name": "Cut %s" % _tiers[4].name, "kind": "material", "stack": 50, "icon": "cut_gem",
		"color": _tiers[4].color, "tier": 4, "desc": "Faceted at a workbench. Sets into tier 4 tools."}
	_items["dusk_ingot"] = {"name": "Duskforged Ingot", "kind": "material", "stack": 50, "icon": "ingot",
		"color": _tiers[5].color, "tier": 5, "desc": "Shadow essence bound into metal at a forge. It hums faintly."}

	# Tools for every tier from stone up.
	for t in range(1, 6):
		for type: String in TOOL_TYPES:
			_items["%s_t%d" % [type, t]] = _make_tool(type, t)

	# Food & herbs with per-world names and (hidden until tried) effects.
	var berry_name := NameGen.species_name(rng, "berry").get_slice(" ", 0)
	_items["berries"] = {"name": "%s Berries" % berry_name, "kind": "food", "stack": 40, "icon": "berries", "color": pal.berry,
		"food": 9.0, "health": 2.0, "desc": "Sweet and a little tart. The bush grows more."}
	var fruit_trees := ["oak", "acacia", "willow", "birch"]
	fruit_tree = fruit_trees[rng.randi() % fruit_trees.size()]
	var fruit_col := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.8), rng.randf_range(0.75, 0.95))
	_items["fruit"] = {"name": "%s %s" % [NameGen.word(rng, 2, 2), ["Plum", "Pod", "Apple", "Drupe"][rng.randi() % 4]], "kind": "food", "stack": 40,
		"icon": "fruit", "color": fruit_col, "food": 13.0, "health": 3.0, "desc": "Grows on some trees here. Shake one with your hands."}
	var mush_effects := ["satiate", "mend", "poison"]
	_shuffle(mush_effects, rng)
	for i in 3:
		_items["mushroom_%d" % i] = {"name": "%s Cap" % NameGen.word(rng, 2, 2), "kind": "food", "stack": 40, "icon": "mushroom",
			"color": pal.mushroom_caps[i % pal.mushroom_caps.size()], "food": 5.0, "health": 0.0, "effect": mush_effects[i],
			"unknown": true, "desc": "A wild mushroom. Who knows what it does?"}
	var herb_effects := ["vigor", "mend", "satiate"]
	_shuffle(herb_effects, rng)
	for i in 3:
		var hcol := Color.from_hsv(fposmod(pal.fern.h + rng.randf_range(-0.12, 0.12), 1.0), rng.randf_range(0.45, 0.7), rng.randf_range(0.5, 0.75))
		_items["herb_%d" % i] = {"name": "%s %s" % [NameGen.word(rng, 2, 2), ["Leaf", "Sprig", "Root", "Bloom"][rng.randi() % 4]], "kind": "food",
			"stack": 40, "icon": "herb", "color": hcol, "food": 1.0, "health": 0.0, "effect": herb_effects[i], "unknown": true,
			"desc": "A fragrant wild herb."}


static func _make_tool(type: String, t: int) -> Dictionary:
	var base: Dictionary = TOOL_TYPES[type]
	var mat := _tiers[t]
	var power: float = TIER_POWER[t]
	var stats := {
		"type": type, "tier": t,
		"tree": base.tree * power, "rock": base.rock * power, "bush": base.bush * maxf(power, 1.0), "carcass": base.carcass * power,
		"damage": base.damage * (0.75 + 0.35 * t), "cooldown": base.cooldown, "durability": int(80 * (1.0 + t * 0.55) * base.dur),
	}
	match String(mat.trait):
		"swift": stats.cooldown *= 0.8
		"keen":
			for k in ["tree", "rock", "bush", "carcass"]:
				stats[k] *= 1.3
		"sturdy": stats.durability = int(stats.durability * 1.6)
		"vicious": stats.damage *= 1.35
		"luminous": stats.damage *= 1.15
	var desc := "Tier %d %s." % [t, base.name.to_lower()]
	if mat.trait != "":
		desc += " %s: %s" % [TRAITS[mat.trait].name, TRAITS[mat.trait].desc]
	return {"name": "%s %s" % [mat.name, base.name], "kind": "tool", "stack": 1, "icon": "tool", "tool": stats,
		"color": mat.color, "tier": t, "desc": desc}


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# --- Lookups -------------------------------------------------------------------------

static func info(id: String) -> Dictionary:
	if _items.has(id):
		return _items[id]
	return BASE_ITEMS.get(id, {"name": id.capitalize(), "kind": "resource", "stack": 250, "icon": "stone"})


static func exists(id: String) -> bool:
	return _items.has(id) or BASE_ITEMS.has(id)


static func all_ids() -> Array:
	return _items.keys()


static func display_name(id: String) -> String:
	return info(id).name


static func stack_size(id: String) -> int:
	return int(info(id).get("stack", 250))


static func tool_stats(id: String) -> Dictionary:
	var i := info(id)
	return i.tool if i.has("tool") else HANDS


static func tier_info(t: int) -> Dictionary:
	return _tiers[clampi(t, 0, _tiers.size() - 1)] if not _tiers.is_empty() else {"name": "?", "color": Color.WHITE, "trait": ""}


static func tier_count() -> int:
	return _tiers.size()


## Map a resource kind (pine, oak, rock, ore_t2, bush...) to its gather target type.
static func target_type(kind: String) -> String:
	return FloraLibrary.KINDS[kind].get("target", "bush")


static func yield_key(kind: String) -> String:
	return FloraLibrary.KINDS[kind].get("yield", "bush")


## Which HARVEST table a node uses when gathered by hand (or "" if it can't be).
static func harvest_key(kind: String) -> String:
	match kind:
		"berry", "bush", "reeds", "dead_bush", "cactus", "mushroom", "herb", "pebbles", "scree", "branch", "tumbleweed", "sapling", "agave", "giant_mushroom", "glowcap":
			return kind
		"jungle_plant":
			return "bush"
		"jungle_tree":
			return "tree"
		"flower_bush":
			return "bush"
		"small_cactus":
			return "cactus"
		"palm":
			return "tree"
		"pine", "fir":
			return "conifer"
		"oak", "autumn_oak", "birch", "willow", "acacia", "dead_tree":
			return "fruit_tree" if kind == fruit_tree else "tree"
	return ""


## Tooltip text (several lines).
static func describe(id: String, durability := -1) -> String:
	var i := info(id)
	var lines: Array[String] = []
	if i.has("tier"):
		lines.append("Tier %d  ·  %s" % [i.tier, tier_info(i.tier).name])
	lines.append(String(i.get("desc", "")))
	if i.has("tool"):
		var t: Dictionary = i.tool
		lines.append("Damage %d  ·  Swing %.2fs" % [roundi(t.damage), t.cooldown])
		var best := ""
		for k in ["tree", "rock", "carcass"]:
			if t[k] >= 1.0:
				best += ("" if best == "" else ", ") + {"tree": "wood", "rock": "stone", "carcass": "butchering"}[k]
		if best != "":
			lines.append("Good for: " + best)
		if durability >= 0:
			lines.append("Durability %d / %d" % [durability, t.durability])
	if i.kind == "food":
		var known: bool = not i.get("unknown", false) or Game.known_items.has(id)
		lines.append("Food +%d%s" % [roundi(i.get("food", 0.0)), ("  ·  Health %+d" % roundi(i.health)) if i.get("health", 0.0) != 0.0 else ""])
		if i.has("effect"):
			lines.append(("Effect: %s (%s)" % [EFFECTS[i.effect].name, EFFECTS[i.effect].desc]) if known else "Effect: ??? (try it)")
	return "\n".join(lines)
