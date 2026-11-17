class_name ItemDB
extends RefCounted
## Every item in the game. Plain data so new items are one entry each.
##
## kind:  resource | food | tool
## tool:  gather multipliers per target ("tree", "rock", "bush", "carcass") + "damage" vs creatures.
##        A multiplier of 0 means the tool can't gather that at all.

const ITEMS := {
	"wood": {"name": "Wood", "kind": "resource", "stack": 1000},
	"stone": {"name": "Stone", "kind": "resource", "stack": 1000},
	"metal_ore": {"name": "Metal Ore", "kind": "resource", "stack": 1000},
	"fiber": {"name": "Plant Fiber", "kind": "resource", "stack": 1000},
	"hide": {"name": "Hide", "kind": "resource", "stack": 500},
	"bone": {"name": "Bone", "kind": "resource", "stack": 500},
	"berries": {"name": "Berries", "kind": "food", "stack": 100, "food": 9.0, "health": 2.0},
	"mushroom": {"name": "Mushroom", "kind": "food", "stack": 100, "food": 6.0, "health": 1.0},
	"raw_meat": {"name": "Raw Meat", "kind": "food", "stack": 100, "food": 16.0, "health": -4.0},
	"rock": {"name": "Rock", "kind": "tool", "stack": 1,
		"tool": {"tree": 1.0, "rock": 1.0, "bush": 1.0, "carcass": 1.0, "damage": 14.0, "cooldown": 0.7}},
}

## Bare hands: slow on wood, useless on stone, fine for bushes.
const HANDS := {"tree": 0.3, "rock": 0.0, "bush": 1.0, "carcass": 0.4, "damage": 5.0, "cooldown": 0.55}

## What hitting each kind of thing gives, per hit at multiplier 1.0: [item, min, max].
const YIELDS := {
	"tree": [["wood", 4, 6]],
	"rock": [["stone", 3, 5]],
	"ore": [["metal_ore", 2, 3], ["stone", 1, 2]],
	"bush": [["fiber", 2, 3]],
	"berry": [["fiber", 1, 2], ["berries", 2, 4]],
	"carcass": [["raw_meat", 1, 2], ["hide", 0, 1], ["bone", 0, 1]],
	"boulder": [["stone", 4, 6]],
	"cactus": [["fiber", 2, 3]],
	"reeds": [["fiber", 2, 4]],
	"dead_bush": [["fiber", 1, 2], ["wood", 1, 1]],
	"log": [["wood", 3, 5]],
	"mushroom": [["mushroom", 1, 2]],
	"pebbles": [["stone", 1, 2]],
}
## Extra reward for finishing a node off.
const BONUS := {
	"tree": [["wood", 8, 12]],
	"rock": [["stone", 6, 9]],
	"ore": [["metal_ore", 4, 6]],
	"carcass": [["raw_meat", 1, 3], ["hide", 1, 1]],
	"boulder": [["stone", 10, 14], ["metal_ore", 0, 2]],
	"cactus": [["fiber", 3, 5]],
	"log": [["wood", 6, 9]],
	"mushroom": [["mushroom", 1, 2]],
	"pebbles": [["stone", 1, 3]],
}
## HP damage per hit at multiplier 1.0 (trees have 100 HP -> 5 hits with a rock).
const HIT_DAMAGE := 20.0


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id.capitalize(), "kind": "resource", "stack": 1000})


static func display_name(id: String) -> String:
	return info(id).name


static func tool_stats(id: String) -> Dictionary:
	var i := info(id)
	return i.tool if i.has("tool") else HANDS


## Map a resource kind (pine, oak, rock, ore, bush, berry...) to its gather target type.
static func target_type(kind: String) -> String:
	return FloraLibrary.KINDS[kind].get("target", "bush")


static func yield_key(kind: String) -> String:
	return FloraLibrary.KINDS[kind].get("yield", "bush")
