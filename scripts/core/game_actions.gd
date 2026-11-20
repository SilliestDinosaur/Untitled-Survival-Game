class_name GameActions
extends RefCounted
## Every action that changes the shared world goes through here, identified by the acting
## player's id. In single-player these run directly. For peer-to-peer multiplayer, a client will
## send the same request to the host (RPC), the host runs it here (validating reach, tool, etc.)
## and broadcasts the result; visuals and sounds stay on the client side (Player / Effects).
##
## Results are plain dictionaries so they can be sent over the network as-is.

const REACH := 3.6


## Swing at a tree / rock / bush / clutter with the player's held tool.
## Result: {ok, target, kind, blocked, need_tier, destroyed, items, broke}
static func hit_resource(player_id: int, chunk: TerrainChunk, index: int, rng: RandomNumberGenerator) -> Dictionary:
	return hit_resource_r(player_id, chunk.resources[index], rng)


## Same, on a resource record ({id, kind, key, hp, removed}). The host uses this for guests'
## swings, whether or not it has that part of the world loaded itself.
static func hit_resource_r(player_id: int, r: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var tool_id := inv.selected_item()
	var tool := ItemDB.tool_stats(tool_id)
	var result := {"ok": false, "target": ItemDB.target_type(r.kind), "kind": r.kind, "blocked": false,
		"need_tier": -1, "destroyed": false, "items": {}, "broke": false}
	if r.get("removed", false):
		return result
	var info: Dictionary = FloraLibrary.KINDS[r.kind]
	if r.kind == "cache":
		result.blocked = true   # caches are opened with Interact, not smashed
		result.use_interact = true
		return result
	var mult: float = tool.get(result.target, 0.0)
	# Better ore needs a good enough pickaxe (or any tool of that tier for the rock tier).
	var need: int = info.get("min_tier", -1)
	if need >= 0 and (tool.type != "pickaxe" or int(tool.tier) < need):
		result.blocked = true
		result.need_tier = need
		return result
	if mult <= 0.0:
		result.blocked = true
		return result
	var key := ItemDB.yield_key(r.kind)
	r.hp = float(r.hp) - ItemDB.HIT_DAMAGE * mult
	_give(inv, ItemDB.YIELDS.get(key, []), mult * ItemDB.GATHER_RATE * float(Difficulty.preset(Game.difficulty).yield), rng, result.items)
	if r.hp <= 0.0:
		# Ore and crystals come out when the deposit breaks, in a share set by the difficulty.
		var bonus_mult := float(Difficulty.preset(Game.difficulty).ore) if key in ["ore_t2", "ore_t3", "gem_t4"] else 1.0
		_give(inv, ItemDB.BONUS.get(key, []), bonus_mult, rng, result.items)
		# A felled tree may give up some resin: conifers, the sappy ones, more often.
		if key == "tree" and FloraLibrary.category_of(r.kind) == "tree":
			var chance := 0.6 if r.kind in ["pine", "fir"] else 0.25
			if rng.randf() < chance:
				_add(inv, "resin", rng.randi_range(1, 2), result.items)
		if r.kind == "cache":
			Game.looted[r.id] = true
		Game.mark_removed(r.id)
		r.removed = true
		result.destroyed = true
	else:
		Game.resource_hp[r.id] = r.hp
	result.hp = r.hp
	result.broke = inv.damage_selected(1)
	result.ok = true
	return result


## Gather by hand (Interact): berries, fiber, sticks, fruit, picking up small things, caches.
## Result: {ok, kind, items, picked_up (node removed), empty (nothing to take right now)}
static func harvest_resource(player_id: int, chunk: TerrainChunk, index: int, rng: RandomNumberGenerator) -> Dictionary:
	return harvest_resource_r(player_id, chunk.resources[index], rng)


static func harvest_resource_r(player_id: int, r: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var result := {"ok": false, "kind": r.kind, "items": {}, "picked_up": false, "empty": false}
	if r.get("removed", false):
		return result
	if r.kind == "cache":
		if Game.looted.has(r.id):
			result.empty = true
			return result
		_loot_cache(inv, r.id, rng, result.items)
		Game.looted[r.id] = true
		Game.mark_removed(r.id)
		r.removed = true
		result.picked_up = true
		result.ok = true
		return result
	var key := ItemDB.harvest_key(r.kind)
	if key == "":
		return result
	var pick_up: bool = key in ItemDB.PICKUP_KEYS
	if not pick_up and Game.is_harvested(r.id):
		result.empty = true
		return result
	var variant := int(String(r.key).get_slice("_", String(r.key).get_slice_count("_") - 1))
	var table: Array = []
	for e: Array in ItemDB.HARVEST[key]:
		var id: String = e[0] % variant if "%d" in e[0] else e[0]
		table.append([id, e[1], e[2], e[3]])
	_give_chance(inv, table, rng, result.items)
	if pick_up:
		Game.mark_removed(r.id)
		r.removed = true
		result.picked_up = true
	else:
		Game.harvested[r.id] = Game.play_time
	result.ok = true
	return result


## Skin / butcher a carcass by hand (a knife helps).
static func harvest_carcass(player_id: int, animal: Node, rng: RandomNumberGenerator) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var result := {"ok": false, "kind": "carcass", "items": {}, "destroyed": false, "broke": false}
	if not is_instance_valid(animal) or not animal.dead:
		return result
	var tool := ItemDB.tool_stats(inv.selected_item())
	# Bigger animals and better blades give more; every cut gives at least something.
	var mult: float = clampf(tool.carcass, 0.6, 2.5) * (0.5 + 0.5 * animal.species.yield_scale)
	_give_chance(inv, ItemDB.HARVEST.carcass, rng, result.items, mult)
	if result.items.is_empty():
		_add(inv, "raw_meat", 1, result.items)
	animal.carcass_hp -= ItemDB.HIT_DAMAGE * clampf(tool.carcass, 0.6, 2.5)
	if animal.carcass_hp <= 0.0:
		result.destroyed = true
	if tool.type == "knife":
		result.broke = inv.damage_selected(1)
	result.ok = true
	return result


## Hit a living animal. Result: {ok, damage, killed, broke}
static func hit_animal(player_id: int, animal: Node, from: Vector3) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var tool := ItemDB.tool_stats(inv.selected_item())
	if not is_instance_valid(animal) or animal.dead:
		return {"ok": false}
	var damage: float = tool.damage
	animal.take_hit(damage, from)
	return {"ok": true, "damage": damage, "killed": animal.dead, "broke": inv.damage_selected(1)}


## Eat the selected food. Result: {ok, id, effect, first_time}
static func eat(player_id: int, stats: PlayerStats) -> Dictionary:
	var res := consume(player_id)
	return apply_food(stats, res.id) if res.ok else res


## The host's half of eating: take one of the held food from the inventory.
static func consume(player_id: int) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var id := inv.selected_item()
	var info := ItemDB.info(id)
	if id == "" or info.kind != "food" or not inv.remove(id, 1):
		return {"ok": false}
	return {"ok": true, "id": id}


## The eater's half: apply the food to their own stats. Returns {ok, id, effect, first_time}.
static func apply_food(stats: PlayerStats, id: String) -> Dictionary:
	var info := ItemDB.info(id)
	stats.eat(info.get("food", 0.0))
	var hp: float = info.get("health", 0.0)
	if hp > 0.0:
		stats.health = minf(stats.max_health, stats.health + hp)
	elif hp < 0.0:
		stats.take_damage(-hp)
	var first := not Game.known_items.has(id)
	Game.known_items[id] = true
	if info.has("effect"):
		stats.add_effect(info.effect, ItemDB.EFFECTS[info.effect].time)
	return {"ok": true, "id": id, "effect": info.get("effect", ""), "first_time": first and info.has("effect")}


# --- Crafting & structures ---------------------------------------------------------------

## Which station kinds are within reach of a position.
## The kinds of crafting station (campfire, workbench, forge) within reach of pos. Building pieces don't count.
static func stations_near(pos: Vector3) -> Array:
	var out := []
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if not Recipes.STATION_NAMES.has(st.kind) or st.kind == "":
			continue
		var p: Array = st.pos
		if Vector3(p[0], p[1], p[2]).distance_to(pos) <= Recipes.STATION_RANGE and not out.has(st.kind):
			out.append(st.kind)
	return out


## How many times the player could craft a recipe right now (ignores stations).
static func craftable_count(inv: Inventory, recipe: Dictionary) -> int:
	var n := 999
	for item: String in recipe.needs:
		n = mini(n, inv.count(item) / int(recipe.needs[item]))
	return n


## Craft a recipe `times` times. Result: {ok, reason, out, made}
static func craft(player_id: int, recipe_id: String, pos: Vector3, times := 1) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var r := Recipes.get_recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "Unknown recipe"}
	if r.at != "" and not stations_near(pos).has(r.at):
		return {"ok": false, "reason": "Needs a %s nearby" % Recipes.STATION_NAMES[r.at]}
	var made := 0
	for i in times:
		if craftable_count(inv, r) < 1:
			break
		for item: String in r.needs:
			inv.remove(item, int(r.needs[item]))
		var got := inv.add(r.out, int(r.count))
		if got < int(r.count):
			spawn_pickup(r.out, int(r.count) - got, -1, pos + Vector3(0, 0.3, 0))
		made += 1
	if made == 0:
		return {"ok": false, "reason": "Missing ingredients"}
	return {"ok": true, "out": r.out, "made": made}


## Building pieces live on a grid: foundations fill 2 m cells and can stack in levels. Walls,
## doorways and roofs sit on the levels. Heights: each level is STACK_H apart and its walls are that tall, so the
## walls of one level stand right on those of the level below (the slab above sits inside their tops).
const CELL := 3.0
const STACK_H := 3.5
const SLAB_T := 0.5
const WALL_LIFT := 0.25      ## walls stand on the top of a level's slab
const WALL_H := 3.5         ## a full storey: one level's walls meet the next's, and a staircase ends at their top
const ROOF_T := 0.3
const MAX_LEVEL := 3
const FLOOR_TOP := 0.34      ## a floor's walking surface, above its origin
const STAIR_STEPS := 12      ## a staircase climbs one storey (STACK_H) in this many steps

## Building pieces: each kind is a shape in a material. The shape decides how it's placed (floors
## and covers by cell, everything else on a floor's edge, stairs in a cell) and how it's built.
const PIECES := {
	"foundation": {"shape": "floor", "mat": "stone"},
	"wood_floor": {"shape": "floor", "mat": "wood"},
	"brick_floor": {"shape": "floor", "mat": "brick"},
	"wall": {"shape": "wall", "mat": "brick"},
	"wood_wall": {"shape": "wall", "mat": "wood"},
	"stone_wall": {"shape": "wall", "mat": "stone"},
	"brick_half": {"shape": "half", "mat": "brick"},
	"wood_half": {"shape": "half", "mat": "wood"},
	"stone_half": {"shape": "half", "mat": "stone"},
	"window_wall": {"shape": "window", "mat": "brick"},
	"wood_window": {"shape": "window", "mat": "wood"},
	"stone_window": {"shape": "window", "mat": "stone"},
	"doorway": {"shape": "doorway", "mat": "brick"},
	"wood_doorway": {"shape": "doorway", "mat": "wood"},
	"stone_doorway": {"shape": "doorway", "mat": "stone"},
	"brick_door": {"shape": "door", "mat": "brick"},
	"wood_door": {"shape": "door", "mat": "wood"},
	"stone_door": {"shape": "door", "mat": "stone"},
	"brick_stairs": {"shape": "stairs", "mat": "brick"},
	"wood_stairs": {"shape": "stairs", "mat": "wood"},
	"stone_stairs": {"shape": "stairs", "mat": "stone"},
	"roof": {"shape": "roof", "mat": "brick"},
	"wood_roof": {"shape": "roof", "mat": "wood"},
	"stone_roof": {"shape": "roof", "mat": "stone"},
	"wood_fence": {"shape": "fence", "mat": "wood"},
	"stone_fence": {"shape": "fence", "mat": "stone"},
	"brick_fence": {"shape": "fence", "mat": "brick"},
	"wood_arch": {"shape": "arch", "mat": "wood"},
	"stone_arch": {"shape": "arch", "mat": "stone"},
	"brick_arch": {"shape": "arch", "mat": "brick"},
	"wood_shutters": {"shape": "shutters", "mat": "wood"},
	"stone_shutters": {"shape": "shutters", "mat": "stone"},
	"brick_shutters": {"shape": "shutters", "mat": "brick"},
	# Furniture, decor, lights and storage: built from a blueprint like the rest, but placed freely (see DECOR).
	"table": {"shape": "decor", "mat": "wood"},
	"chair": {"shape": "decor", "mat": "wood"},
	"bench": {"shape": "decor", "mat": "wood"},
	"bed": {"shape": "decor", "mat": "wood"},
	"shelf": {"shape": "decor", "mat": "wood"},
	"rug": {"shape": "decor", "mat": "wood"},
	"barrel": {"shape": "decor", "mat": "wood"},
	"crate": {"shape": "decor", "mat": "wood"},
	"flower_pot": {"shape": "decor", "mat": "stone"},
	"banner": {"shape": "decor", "mat": "wood"},
	"brazier": {"shape": "decor", "mat": "stone"},
	"lantern_post": {"shape": "decor", "mat": "wood"},
	"standing_torch": {"shape": "decor", "mat": "wood"},
	"chest": {"shape": "decor", "mat": "wood"},
	"large_chest": {"shape": "decor", "mat": "wood"},
}

## Free-standing pieces (shape "decor"): where they go on the build wheel, their footprint (radius: how close other
## things may stand; 0 lets you put things on top, like a rug), their collision box (size; ZERO for none), and for
## lights the colour and height of their flame, for storage how many slots they hold.
const DECOR := {
	"table": {"name": "Table", "page": "furniture", "r": 0.7, "box": Vector3(1.3, 0.8, 0.8), "desc": "A sturdy plank table."},
	"chair": {"name": "Chair", "page": "furniture", "r": 0.3, "box": Vector3(0.5, 0.95, 0.5), "desc": "A plank chair with a slatted back."},
	"bench": {"name": "Bench", "page": "furniture", "r": 0.5, "box": Vector3(1.4, 0.48, 0.38), "desc": "A long bench for two."},
	"bed": {"name": "Bed", "page": "furniture", "r": 0.9, "box": Vector3(1.1, 0.6, 2.1), "desc": "A timber bed with a straw mattress and a warm blanket."},
	"shelf": {"name": "Shelf", "page": "furniture", "r": 0.55, "box": Vector3(1.2, 1.8, 0.4), "desc": "Shelves of jars, pots and bundles."},
	"rug": {"name": "Rug", "page": "furniture", "r": 0.0, "box": Vector3.ZERO, "desc": "A woven rug. Things can stand on it."},
	"barrel": {"name": "Barrel", "page": "furniture", "r": 0.33, "box": Vector3(0.62, 0.9, 0.62), "desc": "An iron-hooped barrel."},
	"crate": {"name": "Crate", "page": "furniture", "r": 0.38, "box": Vector3(0.7, 0.62, 0.7), "desc": "A braced plank crate."},
	"flower_pot": {"name": "Flower Pot", "page": "furniture", "r": 0.22, "box": Vector3(0.4, 0.55, 0.4), "desc": "A clay pot of wildflowers."},
	"banner": {"name": "Banner", "page": "furniture", "r": 0.25, "box": Vector3(0.25, 2.3, 0.25), "desc": "A painted banner on a pole."},
	"brazier": {"name": "Brazier", "page": "lights", "r": 0.42, "box": Vector3(0.8, 0.9, 0.8), "light": Color(1.0, 0.6, 0.28), "light_y": 1.05, "range": 8.0,
		"desc": "A stone fire bowl. Lights the night."},
	"lantern_post": {"name": "Lantern Post", "page": "lights", "r": 0.25, "box": Vector3(0.25, 2.2, 0.25), "light": Color(1.0, 0.78, 0.46), "light_at": Vector3(0, 1.78, 0.34), "range": 7.0,
		"desc": "A lantern hung from a timber post."},
	"standing_torch": {"name": "Standing Torch", "page": "lights", "r": 0.18, "box": Vector3(0.18, 1.5, 0.18), "light": Color(1.0, 0.62, 0.3), "light_y": 1.6, "range": 6.5,
		"desc": "A torch on a stake, burning bright."},
	"chest": {"name": "Chest", "page": "storage", "r": 0.48, "box": Vector3(0.95, 0.7, 0.6), "slots": 16, "desc": "Holds 16 stacks. Interact to open it."},
	"large_chest": {"name": "Iron-Bound Chest", "page": "storage", "r": 0.6, "box": Vector3(1.2, 0.8, 0.7), "slots": 32, "desc": "Holds 32 stacks, bound in iron. Interact to open it."},
}
const FLOOR_KINDS := ["foundation", "wood_floor", "brick_floor"]
## Full-height walls, windows, doorways and doors. Roofs need two of these under them.
const WALL_KINDS := ["wall", "wood_wall", "stone_wall", "window_wall", "wood_window", "stone_window",
	"doorway", "wood_doorway", "stone_doorway", "brick_door", "wood_door", "stone_door",
	"wood_arch", "stone_arch", "brick_arch", "wood_shutters", "stone_shutters", "brick_shutters"]
## Knee-high edge pieces: they fence a floor's edge but don't hold a roof up.
const HALF_KINDS := ["brick_half", "wood_half", "stone_half", "wood_fence", "stone_fence", "brick_fence"]
## Everything that stands on a floor's edge.
const EDGE_KINDS := ["wall", "wood_wall", "stone_wall", "window_wall", "wood_window", "stone_window",
	"doorway", "wood_doorway", "stone_doorway", "brick_door", "wood_door", "stone_door",
	"brick_half", "wood_half", "stone_half", "wood_fence", "stone_fence", "brick_fence",
	"wood_arch", "stone_arch", "brick_arch", "wood_shutters", "stone_shutters", "brick_shutters"]
const DOOR_KINDS := ["brick_door", "wood_door", "stone_door"]
const STAIR_KINDS := ["brick_stairs", "wood_stairs", "stone_stairs"]
const COVER_KINDS := ["roof", "wood_roof", "stone_roof"]

## Building pieces aren't items. The Building Plan lays a free blueprint of any shape in any material; the hammer
## builds it a share at a time, taking that share of its cost with each hit, and repairs it the same way.
const MATERIALS := ["wood", "stone", "brick"]
const SHAPES := ["floor", "wall", "half", "window", "doorway", "door", "stairs", "roof", "fence", "arch", "shutters"]
## Health of a finished piece, by material.
const MAT_HP := {"wood": 200.0, "stone": 400.0, "brick": 320.0}
## Hammer hits to finish a blueprint; a repair hit restores the same share of health.
const BUILD_HITS := {"wood": 4, "stone": 6, "brick": 5}
## The tool that knocks a finished piece down, by material, and the damage a hit does (times the tool's power).
const BREAK_TOOL := {"wood": "hatchet", "stone": "pickaxe", "brick": "pickaxe"}
const BREAK_HIT := 25.0
## What each piece takes to finish. Knocking a finished piece down gives back half.
const PIECE_COSTS := {
	"foundation": {"stone": 6}, "wood_floor": {"plank": 4}, "brick_floor": {"brick": 5},
	"wall": {"brick": 3}, "wood_wall": {"plank": 3}, "stone_wall": {"stone": 6},
	"brick_half": {"brick": 2}, "wood_half": {"plank": 2}, "stone_half": {"stone": 3},
	"window_wall": {"brick": 3, "plank": 2}, "wood_window": {"plank": 5}, "stone_window": {"stone": 6, "plank": 2},
	"doorway": {"brick": 3}, "wood_doorway": {"plank": 3}, "stone_doorway": {"stone": 6},
	"brick_door": {"brick": 3, "plank": 3}, "wood_door": {"plank": 6, "rope": 1}, "stone_door": {"stone": 6, "plank": 2},
	"brick_stairs": {"brick": 8}, "wood_stairs": {"plank": 8}, "stone_stairs": {"stone": 12},
	"roof": {"plank": 6}, "wood_roof": {"plank": 8}, "stone_roof": {"stone": 10, "plank": 2},
	"wood_fence": {"plank": 2}, "stone_fence": {"stone": 3, "plank": 1}, "brick_fence": {"brick": 2, "plank": 1},
	"wood_arch": {"plank": 4}, "stone_arch": {"stone": 7}, "brick_arch": {"brick": 4},
	"wood_shutters": {"plank": 6}, "stone_shutters": {"stone": 6, "plank": 3}, "brick_shutters": {"brick": 3, "plank": 3},
	"table": {"plank": 4}, "chair": {"plank": 2}, "bench": {"plank": 3}, "bed": {"plank": 4, "hide": 2}, "shelf": {"plank": 4},
	"rug": {"fiber": 12, "hide": 1}, "barrel": {"plank": 4, "rope": 1}, "crate": {"plank": 3}, "flower_pot": {"stone": 2, "fiber": 2},
	"banner": {"sticks": 2, "fiber": 6}, "brazier": {"stone": 6, "charcoal": 2}, "lantern_post": {"plank": 2, "resin": 2},
	"standing_torch": {"sticks": 3, "resin": 2, "fiber": 2}, "chest": {"plank": 6, "rope": 1}, "large_chest": {"plank": 8, "ingot_t2": 2},
}


## The piece kind for a shape in a material (both from the building wheel).
static func piece_kind(shape: String, mat: String) -> String:
	for kind: String in PIECES:
		if PIECES[kind].shape == shape and PIECES[kind].mat == mat:
			return kind
	return ""


static func piece_mat(kind: String) -> String:
	return String(PIECES[kind].mat) if PIECES.has(kind) else ""


## Still a blueprint (not yet finished with the hammer)?
static func is_blueprint(st: Dictionary) -> bool:
	return is_building(st.kind) and float(st.get("built", 1.0)) < 1.0


## A piece's health: Vector2(now, most). Pieces from older saves (before blueprints) count as finished and whole.
static func piece_health(st: Dictionary) -> Vector2:
	var most: float = MAT_HP.get(piece_mat(st.kind), 1.0)
	if not st.has("max_hp"):
		return Vector2(most, most)
	return Vector2(float(st.hp), float(st.max_hp))


## Bring a piece from an older save up to date before changing it.
static func _upgrade_piece(st: Dictionary) -> void:
	if st.has("max_hp"):
		return
	var most: float = MAT_HP.get(piece_mat(st.kind), 1.0)
	st["built"] = 1.0
	st["max_hp"] = most
	st["hp"] = most
	st["spent"] = PIECE_COSTS.get(st.kind, {}).duplicate()


static func is_building(kind: String) -> bool:
	return PIECES.has(kind)


## A free-standing piece: furniture, decor, a light or storage (see DECOR).
static func is_decor(kind: String) -> bool:
	return DECOR.has(kind)


## How close other things may stand to a free-standing piece or a station.
static func footprint(kind: String) -> float:
	return float(DECOR[kind].r) if DECOR.has(kind) else STATION_GAP * 0.5


static func shape_of(kind: String) -> String:
	return String(PIECES.get(kind, {}).get("shape", ""))


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)


## Every floor in one cell, lowest first.
static func foundations_in(cell: Vector2i) -> Array:
	var out := []
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in FLOOR_KINDS and cell_of(_pos(st)) == cell:
			out.append(st)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.level) < int(b.level))
	return out


## The floor of one level in a cell, or {}.
static func foundation_at(cell: Vector2i, level := 0) -> Dictionary:
	for f: Dictionary in foundations_in(cell):
		if int(f.level) == level:
			return f
	return {}


## The roof covering a cell's level, or {}.
static func cover_in(cell: Vector2i, level: int) -> Dictionary:
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in COVER_KINDS and int(st.get("level", 0)) == level and cell_of(_pos(st)) == cell:
			return st
	return {}


static func _pos(st: Dictionary) -> Vector3:
	var p: Array = st.pos
	return Vector3(p[0], p[1], p[2])


## Ground height the cell is built on: its level-0 slab if there is one, else the terrain.
static func base_y(cell: Vector2i) -> float:
	var f := foundation_at(cell, 0)
	if not f.is_empty():
		return _pos(f).y
	var c := _cell_center(cell)
	return Game.world_gen.get_height(c.x, c.z)


## The two grid cells a wall at `pos` with `yaw` separates.
static func wall_sides(pos: Vector3, yaw: float) -> Array:
	if absf(sin(yaw)) < 0.5:   # along x, on a z boundary (yaw 0 or a half turn)
		return [cell_of(Vector3(pos.x, 0, pos.z - 0.5)), cell_of(Vector3(pos.x, 0, pos.z + 0.5))]
	return [cell_of(Vector3(pos.x - 0.5, 0, pos.z)), cell_of(Vector3(pos.x + 0.5, 0, pos.z))]


## The base height a piece on an edge stands from: the bordering cell that has a floor.
static func wall_base(pos: Vector3, yaw: float) -> float:
	var sides := wall_sides(pos, yaw)
	return base_y(sides[0]) if not foundations_in(sides[0]).is_empty() else base_y(sides[1])


## Which level a height belongs to, measured from the cell's base.
static func level_of(kind: String, y: float, base: float) -> int:
	var lift := 0.0
	if kind in EDGE_KINDS:
		lift = WALL_LIFT
	elif kind in COVER_KINDS:
		lift = WALL_LIFT + WALL_H + ROOF_T * 0.5
	return roundi((y - base - lift) / STACK_H)


## The height a new ground-level floor in `cell` sits at. Every floor touching this one (edge or
## corner) shares its height, so a base lines up flush; a lone floor takes the ground height rounded
## to half a metre. The ground under the slab is levelled to this height.
static func ground_slab_y(cell: Vector2i) -> float:
	var best: Dictionary = {}
	var best_d := 99
	for dj in [-1, 0, 1]:
		for di in [-1, 0, 1]:
			if di == 0 and dj == 0:
				continue
			var f := foundation_at(Vector2i(cell.x + di, cell.y + dj), 0)
			var d := absi(di) + absi(dj)
			if not f.is_empty() and d < best_d:
				best_d = d
				best = f
	if not best.is_empty():
		return _pos(best).y
	var c := _cell_center(cell)
	return snappedf(Game.world_gen.get_height(c.x, c.z), 0.5)


## Where a building piece goes when the player aims at `aim` (a world point, from the ray when it hits
## something, or the ground). Returns {pos, yaw, level}.
## `prefer_yaw` (edge pieces): the edge the preview was already on. Near a cell corner both edges are
## about equally close, and keeping the current one stops the ghost flickering between them.
## `facing` (stairs): the way the player faces; the steps climb away from them, snapped to a quarter turn.
static func snap_piece(kind: String, aim: Vector3, prefer_yaw := -1.0, facing := 0.0) -> Dictionary:
	var cell := cell_of(aim)
	var c := _cell_center(cell)
	if kind in FLOOR_KINDS:
		var stack := foundations_in(cell)
		var level := 0
		var y := ground_slab_y(cell)
		if not stack.is_empty():
			level = int(stack[-1].level) + 1
			y = _pos(stack[-1]).y + STACK_H
		return {"pos": Vector3(c.x, y, c.z), "yaw": 0.0, "level": level}
	if kind in COVER_KINDS:
		var base := base_y(cell)
		var level := clampi(floori((aim.y - base) / STACK_H), 0, MAX_LEVEL)
		var y := base + level * STACK_H + WALL_LIFT + WALL_H + ROOF_T * 0.5
		return {"pos": Vector3(c.x, y, c.z), "yaw": 0.0, "level": level}
	if kind in STAIR_KINDS:
		# The floor it climbs from: the highest one under the aim (-1 if the cell has none).
		var level := -1
		var y := aim.y
		for f: Dictionary in foundations_in(cell):
			if _pos(f).y <= aim.y + 0.5:
				level = int(f.level)
				y = _pos(f).y
		return {"pos": Vector3(c.x, y, c.z), "yaw": snappedf(facing, PI * 0.5), "level": level}
	# Edge pieces: the nearest cell edge, at the level the aim is on.
	var dx := aim.x - c.x
	var dz := aim.z - c.z
	var pos: Vector3
	var yaw := 0.0
	var east_west := absf(dx) > absf(dz)
	if prefer_yaw >= 0.0 and absf(absf(dx) - absf(dz)) < CELL * 0.1:
		east_west = absf(sin(prefer_yaw)) > 0.5   # too close to call: stay on the same edge
	if east_west:             # runs north-south, on an east or west edge
		pos = Vector3(c.x + signf(dx) * CELL * 0.5, 0.0, c.z)
		yaw = PI * 0.5
	else:                     # runs east-west, on a north or south edge
		pos = Vector3(c.x, 0.0, c.z + signf(dz) * CELL * 0.5)
	var base := wall_base(pos, yaw)
	var level := clampi(floori((aim.y - base) / STACK_H), 0, MAX_LEVEL)
	pos.y = base + level * STACK_H + WALL_LIFT
	return {"pos": pos, "yaw": yaw, "level": level}


## Full-height walls (and doors) standing on a level along one cell's edges. Roofs need two of them.
static func walls_around(cell: Vector2i, level: int) -> int:
	var n := 0
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in WALL_KINDS and int(st.get("level", 0)) == level:
			for s: Vector2i in wall_sides(_pos(st), float(st.get("yaw", 0.0))):
				if s == cell:
					n += 1
	return n


## Can a structure go here? Returns "" if fine, else the reason.
static func placement_problem(pos: Vector3, kind := "", yaw := 0.0) -> String:
	if pos.y < Game.SEA_LEVEL + 0.15:
		return "Can't build in water"
	if is_building(kind) and not is_decor(kind):
		if kind in FLOOR_KINDS:
			var sn := snap_piece(kind, pos)
			pos = sn.pos
			var cell_f := cell_of(pos)
			var lvl_f: int = sn.level
			if lvl_f > MAX_LEVEL:
				return "Too high to build"
			if lvl_f > 0 and not cover_in(cell_f, lvl_f - 1).is_empty():
				return "A roof covers this spot"
			if lvl_f == 0 and Game.world_gen.get_normal(pos.x, pos.z).y < 0.6:
				return "Too steep here (the ground would need too much levelling)"
			if TerrainEdit.tree_near(pos, 3.0) != null:
				return "A tree is in the way. Chop it down first."
			return ""
		if kind in STAIR_KINDS:
			return _stairs_problem(pos, kind, yaw)
		var cell := cell_of(pos)
		if TerrainEdit.tree_near(pos, 2.0) != null:
			return "A tree is in the way. Chop it down first."
		var base := wall_base(pos, yaw) if kind in EDGE_KINDS else base_y(cell)
		var level := level_of(kind, pos.y, base)
		if kind in COVER_KINDS:
			if foundation_at(cell, level).is_empty():
				return "A roof needs a foundation under it"
			if not cover_in(cell, level).is_empty():
				return "There's already a roof here"
			if not _stairs_at(cell, level).is_empty():
				return "Stairs go up through this spot"
			if walls_around(cell, level) < 2:
				return "A roof needs at least two walls under it"
			return ""
		# Edge pieces: walls, half walls, windows, doorways and doors.
		var sides := wall_sides(pos, yaw)
		var supported := false
		for s: Vector2i in sides:
			if not foundation_at(s, level).is_empty():
				supported = true
		if not supported:
			return "Walls need a foundation along that edge"
		for id: String in Game.structures:
			var o: Dictionary = Game.structures[id]
			if o.kind in EDGE_KINDS and _pos(o).distance_to(pos) < 0.5:
				return "There's already a wall here"
		return ""
	# Stations, furniture, lights and storage: on the ground, or on top of a finished floor.
	var on_floor := not floor_under(pos).is_empty()
	if not on_floor and Game.world_gen.get_normal(pos.x, pos.z).y < 0.8:
		return "Too steep here"
	var mine := footprint(kind)
	for id: String in Game.structures:
		var o: Dictionary = Game.structures[id]
		var op := _pos(o)
		if not is_building(o.kind) or is_decor(o.kind):
			var gap := mine + footprint(o.kind)
			if mine > 0.0 and footprint(o.kind) > 0.0 and op.distance_to(pos) < gap:
				return "Too close to the %s" % ItemDB.display_name(o.kind).to_lower()
		elif o.kind in EDGE_KINDS:
			# Clear of walls: its footprint mustn't reach into one.
			var clear := minf(mine, STATION_RADIUS) if is_decor(kind) else STATION_RADIUS
			if pos.y < op.y + WALL_H and pos.y + 1.2 > op.y and _to_wall(pos, op, float(o.get("yaw", 0.0))) < clear:
				return "A wall is in the way"
		elif o.kind in FLOOR_KINDS and not on_floor:
			if cell_of(op) == cell_of(pos) and absf(op.y - pos.y) < 1.0:
				if is_blueprint(o) and absf(op.y + FLOOR_TOP - pos.y) < 0.3:
					return "Build the floor with the hammer first"
				return "Put it on top of the floor"
		elif o.kind in STAIR_KINDS:
			if cell_of(op) == cell_of(pos) and absf(op.y - pos.y) < STACK_H:
				return "Stairs are in the way"
	return ""


const STATION_GAP := 1.6      ## stations keep this far apart (centre to centre)
const STATION_RADIUS := 0.7   ## and this far from a wall


## Something set down on a floor stands exactly on its top (a hand's breadth either way is taken as meant).
static func on_floor_top(pos: Vector3) -> Vector3:
	var under := floor_under(pos)
	if not under.is_empty():
		pos.y = _pos(under).y + FLOOR_TOP
	return pos


## The finished floor a station at `pos` would stand on (its top within a hand's breadth of pos), or {}.
static func floor_under(pos: Vector3) -> Dictionary:
	var cell := cell_of(pos)
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in FLOOR_KINDS and not is_blueprint(st) and cell_of(_pos(st)) == cell and absf(_pos(st).y + FLOOR_TOP - pos.y) < 0.3:
			return st
	return {}


## Distance across the ground from p to a wall standing on an edge at `wall` (a 3 m segment along the edge).
static func _to_wall(p: Vector3, wall: Vector3, yaw: float) -> float:
	var along_x := absf(sin(yaw)) < 0.5
	var a := absf(p.x - wall.x) if along_x else absf(p.z - wall.z)   # along the wall
	var b := absf(p.z - wall.z) if along_x else absf(p.x - wall.x)   # out from it
	return Vector2(maxf(a - CELL * 0.5, 0.0), b).length()


## The staircase starting from a cell's level, or {}.
static func _stairs_at(cell: Vector2i, level: int) -> Dictionary:
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in STAIR_KINDS and int(st.get("level", 0)) == level and cell_of(_pos(st)) == cell:
			return st
	return {}


## A staircase needs a floor to climb from, and nothing overhead in its cell: no floor, roof or
## another staircase at the level it climbs to.
static func _stairs_problem(pos: Vector3, kind: String, yaw: float) -> String:
	var sn := snap_piece(kind, pos, -1.0, yaw)
	var cell := cell_of(sn.pos)
	var level: int = sn.level
	if level < 0:
		return "Stairs need a floor to climb from"
	if level + 1 > MAX_LEVEL:
		return "Too high to build"
	if not foundation_at(cell, level + 1).is_empty():
		return "A floor above blocks the stairs"
	if not cover_in(cell, level).is_empty():
		return "A roof covers the stairs"
	for id: String in Game.structures:
		var o: Dictionary = Game.structures[id]
		if o.kind in STAIR_KINDS and cell_of(_pos(o)) == cell and int(o.get("level", 0)) == level:
			return "There's already a staircase here"
	if TerrainEdit.tree_near(sn.pos, 2.0) != null:
		return "A tree is in the way. Chop it down first."
	return ""


## Place the held placeable. Result: {ok, reason, id, kind, level}
## Place a station (campfire, workbench, forge) from the selected slot.
static func place_structure(player_id: int, slot: int, pos: Vector3, yaw: float) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var s: Dictionary = inv.slots[slot]
	if s.is_empty() or ItemDB.info(s.id).kind != "placeable":
		return {"ok": false, "reason": ""}
	var kind: String = ItemDB.info(s.id).station
	var problem := placement_problem(pos, kind, yaw)
	if problem != "":
		return {"ok": false, "reason": problem}
	inv.take_from_slot(slot, 1)
	var id := Game.new_entity_id("s")
	pos = on_floor_top(pos)
	Game.structures[id] = {"id": id, "kind": kind, "pos": [pos.x, pos.y, pos.z], "yaw": yaw, "hp": 3, "level": 0}
	Game.structures_changed.emit()
	return {"ok": true, "id": id, "kind": kind, "level": 0, "pos": pos, "yaw": yaw}


## Lay a blueprint of a building piece (free). Needs a Building Plan in the pack. The hammer then builds it.
static func place_blueprint(player_id: int, kind: String, pos: Vector3, yaw: float) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	if not is_building(kind) or inv.count("building_plan") < 1:
		return {"ok": false, "reason": ""}
	var problem := placement_problem(pos, kind, yaw)
	if problem != "":
		return {"ok": false, "reason": problem}
	var level := 0
	if kind in FLOOR_KINDS:
		# placement_problem has snapped pos to the shared slab height; take that snap as the truth.
		var sn := snap_piece(kind, pos)
		pos = sn.pos
		level = int(sn.level)
		yaw = snappedf(yaw, PI * 0.5)
	elif kind in STAIR_KINDS:
		var sn_s := snap_piece(kind, pos, -1.0, yaw)
		pos = sn_s.pos
		yaw = sn_s.yaw
		level = int(sn_s.level)
	elif is_decor(kind):
		level = 0
		pos = on_floor_top(pos)
	else:
		level = level_of(kind, pos.y, wall_base(pos, yaw) if kind in EDGE_KINDS else base_y(cell_of(pos)))
	var id := Game.new_entity_id("s")
	var st := {"id": id, "kind": kind, "pos": [pos.x, pos.y, pos.z], "yaw": yaw, "level": level,
		"built": 0.0, "hp": 0.0, "max_hp": float(MAT_HP[piece_mat(kind)]), "spent": {}}
	if kind in DOOR_KINDS:
		st["open"] = false
	Game.structures[id] = st
	Game.structures_changed.emit()
	return {"ok": true, "id": id, "kind": kind, "level": level, "pos": pos, "yaw": yaw}


## Swing a door open or shut. Anyone can use a door.
static func toggle_door(_player_id: int, structure_id: String) -> Dictionary:
	if not Game.structures.has(structure_id):
		return {"ok": false}
	var st: Dictionary = Game.structures[structure_id]
	if not st.kind in DOOR_KINDS or is_blueprint(st):
		return {"ok": false}
	st["open"] = not bool(st.get("open", false))
	Game.structures_changed.emit()
	return {"ok": true, "open": st.open}


## Why a building piece can't be taken down yet ("" if it can).
static func removal_problem(st: Dictionary) -> String:
	if st.kind in FLOOR_KINDS:
		var cell := cell_of(_pos(st))
		var lvl := int(st.level)
		if not foundation_at(cell, lvl + 1).is_empty() or not cover_in(cell, lvl).is_empty() or not cover_in(cell, lvl + 1).is_empty():
			return "Take down what's on top of it first"
		if walls_around(cell, lvl) > 0 or _edges_on_floor(cell, lvl) > 0:
			return "Take down the walls standing on it first"
		for id: String in Game.structures:   # a station standing on it
			var o: Dictionary = Game.structures[id]
			if (not is_building(o.kind) or is_decor(o.kind)) and floor_under(_pos(o)) == st:
				return "Pack up the %s on it first" % ItemDB.display_name(o.kind).to_lower()
	elif DECOR.get(st.kind, {}).has("slots") and not chest_is_empty(st):
		return "Take everything out of it first"
	elif st.kind in WALL_KINDS:
		# A roof needs two walls under it; don't let it fall.
		var lvl := int(st.get("level", 0))
		for s: Vector2i in wall_sides(_pos(st), float(st.get("yaw", 0.0))):
			var cover := cover_in(s, lvl)
			if not cover.is_empty() and walls_around(s, lvl) - 1 < 2:
				return "The roof above it needs this wall"
	return ""


## Edge pieces (walls, half walls, windows, doors) standing on a floor's cell at one level.
static func _edges_on_floor(cell: Vector2i, level: int) -> int:
	var n := 0
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in EDGE_KINDS and int(st.get("level", 0)) == level:
			for s: Vector2i in wall_sides(_pos(st), float(st.get("yaw", 0.0))):
				if s == cell:
					n += 1
	return n


## A swing at a structure. Stations pack back up into an item after a few hits. Building pieces: the hammer
## builds or repairs them; an unfinished blueprint comes down to any other hit (giving back what went into it);
## a finished piece takes damage from the right tool for its material (hatchet for wood, pickaxe for stone and
## brick), and drops half its materials when it falls.
static func hit_structure(player_id: int, structure_id: String) -> Dictionary:
	if not Game.structures.has(structure_id):
		return {"ok": false}
	var st: Dictionary = Game.structures[structure_id]
	if is_building(st.kind):
		return _hit_piece(player_id, st)
	st.hp = int(st.hp) - 1
	if st.hp > 0:
		return {"ok": true, "packed": false}
	var blocked := removal_problem(st)
	if blocked != "":
		st.hp = 1
		return {"ok": false, "reason": blocked}
	Game.structures.erase(structure_id)
	Game.structures_changed.emit()
	var p: Array = st.pos
	var got := Game.inventory_of(player_id).add(st.kind, 1)
	if got < 1:
		spawn_pickup(st.kind, 1, -1, Vector3(p[0], p[1] + 0.3, p[2]))
	return {"ok": true, "packed": true, "kind": st.kind}


static func _hit_piece(player_id: int, st: Dictionary) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var tool := ItemDB.tool_stats(inv.selected_item())
	_upgrade_piece(st)
	if tool.get("type", "") == "hammer":
		return _hammer(inv, st)
	var pos := _pos(st)
	if is_blueprint(st):
		var why := removal_problem(st)
		if why != "":
			return {"ok": false, "reason": why}
		_remove_piece(st)
		_refund(inv, st.get("spent", {}), 1.0, pos)
		return {"ok": true, "removed": true, "kind": st.kind}
	var mat := piece_mat(st.kind)
	if tool.get("type", "") != BREAK_TOOL[mat]:
		return {"ok": false, "reason": "%s needs a %s to knock down" % [ItemDB.display_name(st.kind), BREAK_TOOL[mat]]}
	var power: float = tool.tree if mat == "wood" else tool.rock
	st.hp = float(st.hp) - BREAK_HIT * power
	var broke := inv.damage_selected(1)
	if float(st.hp) > 0.0:
		Game.structures_changed.emit()
		return {"ok": true, "hp": st.hp, "max_hp": st.max_hp, "broke": broke}
	var why := removal_problem(st)
	if why != "":
		st.hp = 1.0
		Game.structures_changed.emit()
		return {"ok": false, "reason": why, "broke": broke}
	_remove_piece(st)
	# Furniture and the like come back whole (you'll move them about); walls and floors give back half, unless they
	# were only just finished (a misplaced piece, put right straight away, costs nothing).
	var whole := is_decor(st.kind) or just_finished(st)
	_refund(inv, PIECE_COSTS.get(st.kind, {}), 1.0 if whole else 0.5, pos)
	return {"ok": true, "destroyed": true, "kind": st.kind, "broke": broke}


## The hammer: one share of building on a blueprint, or one share of repair on a damaged piece. Either way the
## share of the piece's cost is taken from the pack first; nothing happens if it isn't there.
static func _hammer(inv: Inventory, st: Dictionary) -> Dictionary:
	var hits: int = BUILD_HITS[piece_mat(st.kind)]
	var cost: Dictionary = PIECE_COSTS.get(st.kind, {})
	var spent: Dictionary = st.get("spent", {})
	var take := {}
	if is_blueprint(st):
		var step := mini(roundi(float(st.built) * hits) + 1, hits)
		for item: String in cost:
			var due := roundi(float(cost[item]) * step / hits) - int(spent.get(item, 0))
			if due > 0:
				take[item] = due
		var short := _shortfall(inv, take)
		if short != "":
			return {"ok": false, "reason": "Needs %s" % short}
		for item: String in take:
			inv.remove(item, int(take[item]))
			spent[item] = int(spent.get(item, 0)) + int(take[item])
		st.spent = spent
		st.built = float(step) / hits
		st.hp = float(st.max_hp) * float(st.built)
		if step >= hits:
			st.finished_at = Game.play_time   # (a change of mind soon after gives everything back: see FULL_REFUND)
		Game.structures_changed.emit()
		return {"ok": true, "built": st.built, "finished": step >= hits, "took": take, "hammer": true}
	if float(st.hp) >= float(st.max_hp) - 0.01:
		return {"ok": false, "reason": "%s is in good repair" % ItemDB.display_name(st.kind), "hammer": true}
	# A repair hit restores one build share of health and costs that share of the materials, rounded (but at least
	# one of the main material, so repairs are never free; a small share of a minor one, like a door's rope, rounds
	# away).
	var share := minf(1.0 / hits, (float(st.max_hp) - float(st.hp)) / float(st.max_hp))
	var first := true
	for item: String in cost:
		var due := roundi(float(cost[item]) * share)
		if first:
			due = maxi(due, 1)
			first = false
		if due > 0:
			take[item] = due
	var short := _shortfall(inv, take)
	if short != "":
		return {"ok": false, "reason": "Repairing needs %s" % short, "hammer": true}
	for item: String in take:
		inv.remove(item, int(take[item]))
	st.hp = minf(float(st.max_hp), float(st.hp) + float(st.max_hp) * share)
	Game.structures_changed.emit()
	return {"ok": true, "repaired": true, "hp": st.hp, "max_hp": st.max_hp, "took": take, "hammer": true}


## Seconds after a piece is finished in which knocking it down gives back everything it cost.
const FULL_REFUND := 30.0


static func just_finished(st: Dictionary) -> bool:
	return st.has("finished_at") and Game.play_time - float(st.finished_at) < FULL_REFUND


## The hammer, Shift-clicked: one share of repair on every damaged finished piece near `at`, as far as the pack's
## materials go. Result: {ok, repaired: how many pieces, reason}.
const REPAIR_REACH := 10.0
static func repair_all(player_id: int, at: Vector3) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	if ItemDB.tool_stats(inv.selected_item()).get("type", "") != "hammer":
		return {"ok": false, "reason": "Needs a hammer"}
	var fixed := 0
	var short := ""
	for sid: String in Game.structures.keys():
		var st: Dictionary = Game.structures[sid]
		if not is_building(st.kind) or is_blueprint(st) or _pos(st).distance_to(at) > REPAIR_REACH:
			continue
		var hp := piece_health(st)
		if hp.x >= hp.y - 0.01:
			continue
		var r := _hammer(inv, st)
		if r.get("repaired", false):
			fixed += 1
		elif short == "":
			short = String(r.get("reason", ""))
	if fixed == 0:
		return {"ok": false, "repaired": 0, "reason": short if short != "" else "Nothing nearby needs repair"}
	return {"ok": true, "repaired": fixed}


## "" if the pack holds everything in `need`, else what's missing ("2 Planks, 1 Rope").
static func _shortfall(inv: Inventory, need: Dictionary) -> String:
	var parts: Array[String] = []
	for item: String in need:
		var have := inv.count(item)
		if have < int(need[item]):
			parts.append("%d %s" % [int(need[item]) - have, ItemDB.display_name(item)])
	return ", ".join(parts)


static func _remove_piece(st: Dictionary) -> void:
	Game.structures.erase(st.id)
	Game.structures_changed.emit()


## Give back a share of some materials: into the pack, and onto the ground at `pos` if the pack is full.
static func _refund(inv: Inventory, items: Dictionary, share: float, pos: Vector3) -> void:
	for item: String in items:
		var n := floori(float(items[item]) * share)
		if n <= 0:
			continue
		var got := inv.add(item, n)
		if got < n:
			spawn_pickup(item, n - got, -1, pos + Vector3(0, 0.5, 0))


# --- Items in the world -----------------------------------------------------------------

## Everything in the pack falls to the ground at `pos` (used when you die).
static func drop_all(inv: Inventory, pos: Vector3) -> void:
	for i in Inventory.SIZE:
		var s: Dictionary = inv.slots[i]
		if s.is_empty():
			continue
		spawn_pickup(String(s.id), int(s.count), int(s.get("dur", -1)), pos + Vector3(0, 0.3, 0))


## Drop items from a slot onto the ground in front of the player.
const PICKUP_MERGE_RANGE := 1.5   ## a drop this close to a pile of the same thing joins it


static func drop(player_id: int, slot: int, amount: int, pos: Vector3) -> String:
	var inv := Game.inventory_of(player_id)
	var stack := inv.take_from_slot(slot, amount)
	if stack.is_empty():
		return ""
	return spawn_pickup(stack.id, stack.count, int(stack.dur), pos)


static func spawn_pickup(item: String, count: int, dur: int, pos: Vector3) -> String:
	# Stackable drops join a pile of the same thing close by (up to a full stack) instead of making another: a full
	# satchel while gathering dropped one per swing, and every pickup is drawn, animated and sent to every guest.
	if dur < 0:
		var cap := ItemDB.stack_size(item)
		for pid: String in Game.pickups:
			var o: Dictionary = Game.pickups[pid]
			if o.item != item or int(o.get("dur", -1)) >= 0 or int(o.count) >= cap:
				continue
			var op: Array = o.pos
			if Vector3(op[0], op[1], op[2]).distance_to(pos) > PICKUP_MERGE_RANGE:
				continue
			var put := mini(count, cap - int(o.count))
			o.count = int(o.count) + put
			count -= put
			if count <= 0:
				Game.pickups_changed.emit()
				return pid
	var id := Game.new_entity_id("p")
	Game.pickups[id] = {"id": id, "item": item, "count": count, "dur": dur, "pos": [pos.x, pos.y, pos.z]}
	Game.pickups_changed.emit()
	return id


## Pick up a dropped item (whatever doesn't fit stays on the ground).
static func pick_up(player_id: int, pickup_id: String) -> int:
	if not Game.pickups.has(pickup_id):
		return 0
	var p: Dictionary = Game.pickups[pickup_id]
	var got := Game.inventory_of(player_id).add(p.item, int(p.count), false, int(p.get("dur", -1)))
	p.count = int(p.count) - got
	if p.count <= 0:
		Game.pickups.erase(pickup_id)
	Game.pickups_changed.emit()
	return got


# --- Helpers ------------------------------------------------------------------------

static func _give(inv: Inventory, table: Array, mult: float, rng: RandomNumberGenerator, out: Dictionary) -> void:
	for e: Array in table:
		var n := int(round(rng.randi_range(e[1], e[2]) * mult))
		if e[2] > 0 and mult > 0.0 and n == 0 and rng.randf() < mult:
			n = 1   # weak tools still give something now and then
		_add(inv, e[0], n, out)


static func _give_chance(inv: Inventory, table: Array, rng: RandomNumberGenerator, out: Dictionary, mult := 1.0) -> void:
	for e: Array in table:
		if rng.randf() > e[3]:
			continue
		_add(inv, e[0], int(round(rng.randi_range(e[1], e[2]) * mult)), out)


## Add to the inventory; anything that doesn't fit is dropped at the player's feet by the caller.
static func _add(inv: Inventory, id: String, n: int, out: Dictionary) -> void:
	if n <= 0:
		return
	var got := inv.add(id, n)
	if got > 0:
		out[id] = out.get(id, 0) + got
	if got < n:
		out["_overflow_" + id] = n - got


## Supply caches hold a deterministic mix (same cache, same loot on every machine).
static func _loot_cache(inv: Inventory, cache_id: String, _rng: RandomNumberGenerator, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, cache_id])
	var tools := ItemDB.TOOL_TYPES.keys()
	# One or two well-used tools: stone, now and then the world's first metal (never better: metal is earned).
	var metal := float(Difficulty.preset(Game.difficulty).cache_metal)
	for i in rng.randi_range(1, 2):
		var roll := rng.randf()
		var tier := 2 if roll < metal else 1
		var id := "%s_t%d" % [tools[rng.randi() % tools.size()], tier]
		var dur := int(ItemDB.tool_stats(id).durability * rng.randf_range(0.4, 0.9))   # well used
		var got := inv.add(id, 1, false, dur)
		if got > 0:
			out[id] = out.get(id, 0) + 1
	var supplies := [["wood", 10, 30], ["stone", 10, 25], ["fiber", 5, 15], ["charcoal", 2, 4], ["flint", 1, 4], ["berries", 3, 8], ["resin", 1, 3]]
	for i in rng.randi_range(2, 4):
		var e: Array = supplies[rng.randi() % supplies.size()]
		_add(inv, e[0], rng.randi_range(e[1], e[2]), out)


# --- Storage -----------------------------------------------------------------------------------

const CHEST_REACH := 6.0   ## how close you must be to move things in or out of a chest


## A chest's slots ({} empty, or {id, count, dur}), kept in the structure itself so saves and guests carry them.
static func chest_slots(st: Dictionary) -> Array:
	var n := int(DECOR.get(st.kind, {}).get("slots", 0))
	if not st.has("items") or (st.items as Array).size() != n:
		var old: Array = st.get("items", [])
		var items: Array = []
		for i in n:
			items.append(old[i] if i < old.size() else {})
		st["items"] = items
	return st.items


static func chest_is_empty(st: Dictionary) -> bool:
	for s: Dictionary in st.get("items", []):
		if not s.is_empty():
			return false
	return true


## Move things between a chest and a satchel (or within either). a: {structure, op: "move" | "quick", from: "bag" |
## "chest", a: slot, to: "bag" | "chest", b: slot, pos: where the player stands}. "move" drops slot a's stack on
## slot b (merging like stacks, else swapping); "quick" sends it to the other side wherever it fits.
static func chest_op(player_id: int, a: Dictionary) -> Dictionary:
	var sid := String(a.get("structure", ""))
	if not Game.structures.has(sid):
		return {"ok": false, "reason": "The chest is gone"}
	var st: Dictionary = Game.structures[sid]
	if not DECOR.get(st.kind, {}).has("slots") or is_blueprint(st):
		return {"ok": false}
	var at: Vector3 = a.get("pos", _pos(st))
	if at.distance_to(_pos(st)) > CHEST_REACH:
		return {"ok": false, "reason": "Too far from the chest"}
	var inv := Game.inventory_of(player_id)
	var chest := chest_slots(st)
	var from := String(a.get("from", "chest"))
	var src: Array = chest if from == "chest" else inv.slots
	var ia := int(a.get("a", -1))
	if ia < 0 or ia >= src.size() or (src[ia] as Dictionary).is_empty():
		return {"ok": false}
	if String(a.get("op", "")) == "quick":
		var dst: Array = inv.slots if from == "chest" else chest
		_stow(src, ia, dst, inv if from == "chest" else null)
	else:
		var to := String(a.get("to", "bag"))
		var dst: Array = chest if to == "chest" else inv.slots
		var ib := int(a.get("b", -1))
		if ib < 0 or ib >= dst.size() or (src == dst and ia == ib):
			return {"ok": false}
		var s: Dictionary = src[ia]
		var d: Dictionary = dst[ib]
		if not d.is_empty() and d.id == s.id and ItemDB.info(s.id).kind != "tool":
			var put := mini(int(s.count), ItemDB.stack_size(s.id) - int(d.count))
			d.count = int(d.count) + put
			s.count = int(s.count) - put
			if int(s.count) <= 0:
				src[ia] = {}
		else:
			src[ia] = d
			dst[ib] = s
	inv.changed.emit()
	Game.structures_changed.emit()
	return {"ok": true}


## Quick-stack: everything in the backpack (not the hotbar) that some nearby chest already holds goes into it.
## Result: {ok, moved: item count put away, chests: how many chests took something}.
const QUICK_STACK_REACH := 8.0
static func quick_stack(player_id: int, at: Vector3) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var moved := 0
	var used := 0
	for sid: String in Game.structures:
		var st: Dictionary = Game.structures[sid]
		if not DECOR.get(st.kind, {}).has("slots") or is_blueprint(st) or _pos(st).distance_to(at) > QUICK_STACK_REACH:
			continue
		var chest := chest_slots(st)
		var holds := {}
		for c: Dictionary in chest:
			if not c.is_empty():
				holds[c.id] = true
		var took := false
		for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
			var s: Dictionary = inv.slots[i]
			if s.is_empty() or not holds.has(s.id):
				continue
			var before := int(s.count)
			_stow(inv.slots, i, chest, null)
			var after := 0 if (inv.slots[i] as Dictionary).is_empty() else int(inv.slots[i].count)
			if after < before:
				moved += before - after
				took = true
		if took:
			used += 1
	if moved > 0:
		inv.changed.emit()
		Game.structures_changed.emit()
	return {"ok": true, "moved": moved, "chests": used}


## Put the stack in src[i] into dst: onto like stacks first, then the first empty slot (into a satchel, its own
## rules for where things go). Whatever doesn't fit stays where it was.
static func _stow(src: Array, i: int, dst: Array, into: Inventory) -> void:
	var s: Dictionary = src[i]
	if into != null:
		var got := into.add(s.id, int(s.count), true, int(s.get("dur", -1)))
		s.count = int(s.count) - got
	else:
		var cap := ItemDB.stack_size(s.id)
		if ItemDB.info(s.id).kind != "tool":
			for d: Dictionary in dst:
				if int(s.count) <= 0:
					break
				if not d.is_empty() and d.id == s.id and int(d.count) < cap:
					var put := mini(int(s.count), cap - int(d.count))
					d.count = int(d.count) + put
					s.count = int(s.count) - put
		for j in dst.size():
			if int(s.count) <= 0:
				break
			if (dst[j] as Dictionary).is_empty():
				dst[j] = s.duplicate()
				s.count = 0
	if int(s.count) <= 0:
		src[i] = {}
