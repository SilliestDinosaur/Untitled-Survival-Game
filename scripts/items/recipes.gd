class_name Recipes
extends RefCounted
## Crafting recipes. Each: {id, out, count, needs {item: n}, at ("" = by hand | campfire |
## workbench | forge), group}. Tool recipes are generated for every tier from the world's materials.

const STATION_RANGE := 4.5
const GROUPS := ["Basics", "Stations", "Tools", "Materials", "Food"]
const STATION_NAMES := {"": "By hand", "campfire": "Campfire", "workbench": "Workbench", "forge": "Forge"}

static var _list: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _list.is_empty():
		_build()
	return _list


static func get_recipe(id: String) -> Dictionary:
	for r in all():
		if r.id == id:
			return r
	return {}


static func _add(out: String, count: int, needs: Dictionary, at: String, group: String) -> void:
	_list.append({"id": "%s_%d" % [out, _list.size()], "out": out, "count": count, "needs": needs, "at": at, "group": group})


static func _build() -> void:
	_list.clear()
	# By hand
	_add("rope", 1, {"fiber": 6}, "", "Basics")
	_add("torch", 1, {"sticks": 2, "fiber": 2, "resin": 1}, "", "Basics")
	_add("bandage", 2, {"fiber": 4, "resin": 1}, "", "Basics")
	_add("campfire", 1, {"stone": 8, "sticks": 6, "wood": 4}, "", "Stations")
	_add("workbench", 1, {"wood": 30, "stone": 10, "rope": 2}, "", "Stations")
	_add("forge", 1, {"stone": 45, "wood": 15, "rope": 2}, "workbench", "Stations")
	# Stone tools are knapped by hand.
	_add("hatchet_t1", 1, {"sticks": 2, "stone": 6, "fiber": 3}, "", "Tools")
	_add("pickaxe_t1", 1, {"sticks": 2, "stone": 8, "fiber": 3}, "", "Tools")
	_add("spear_t1", 1, {"sticks": 4, "flint": 1, "fiber": 2}, "", "Tools")
	_add("knife_t1", 1, {"sticks": 1, "flint": 2, "fiber": 1}, "", "Tools")
	# Materials
	_add("plank", 2, {"wood": 4}, "workbench", "Materials")
	_add("brick", 2, {"stone": 4}, "workbench", "Materials")
	_add("foundation", 1, {"brick": 4}, "workbench", "Stations")
	_add("wall", 1, {"brick": 3}, "workbench", "Stations")
	_add("wood_wall", 1, {"plank": 3}, "workbench", "Stations")
	_add("doorway", 1, {"brick": 3}, "workbench", "Stations")
	_add("roof", 1, {"plank": 6}, "workbench", "Stations")
	_add("wood_floor", 1, {"plank": 4}, "workbench", "Stations")
	_add("window_wall", 1, {"brick": 3, "plank": 2}, "workbench", "Stations")
	_add("wood_doorway", 1, {"plank": 3}, "workbench", "Stations")
	_add("ceiling", 1, {"plank": 5}, "workbench", "Stations")
	_add("leather", 1, {"hide": 2, "resin": 1}, "workbench", "Materials")
	_add("ingot_t2", 1, {"ore_t2": 3, "wood": 2}, "forge", "Materials")
	_add("ingot_t3", 1, {"ore_t3": 3, "wood": 3}, "forge", "Materials")
	_add("cut_gem", 1, {"gem_t4": 2}, "workbench", "Materials")
	_add("dusk_ingot", 1, {"essence": 4, "ingot_t3": 1}, "forge", "Materials")
	# Metal, gem and dusk tools
	var heads := {"hatchet": 3, "pickaxe": 4, "spear": 2, "knife": 2}
	for type: String in heads:
		var n: int = heads[type]
		_add("%s_t2" % type, 1, {"ingot_t2": n, "plank": 2, "rope": 1}, "workbench", "Tools")
		_add("%s_t3" % type, 1, {"ingot_t3": n, "plank": 2, "leather": 1}, "forge", "Tools")
		_add("%s_t4" % type, 1, {"cut_gem": maxi(n - 1, 1), "ingot_t3": 1, "leather": 1, "plank": 1}, "workbench", "Tools")
		_add("%s_t5" % type, 1, {"dusk_ingot": n, "cut_gem": 1, "leather": 1}, "forge", "Tools")
	# Food
	_add("cooked_meat", 1, {"raw_meat": 1}, "campfire", "Food")
	_add("roast_fruit", 1, {"fruit": 2}, "campfire", "Food")
	_add("stew", 1, {"raw_meat": 2, "berries": 4, "wood": 1}, "campfire", "Food")
