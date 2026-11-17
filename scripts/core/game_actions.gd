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
	_give(inv, ItemDB.YIELDS.get(key, []), mult * ItemDB.GATHER_RATE, rng, result.items)
	if r.hp <= 0.0:
		_give(inv, ItemDB.BONUS.get(key, []), 1.0, rng, result.items)
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
static func stations_near(pos: Vector3) -> Array:
	var out := []
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
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


## Building pieces snap to a 2 m grid: foundations fill cells, walls sit on cell edges.
const CELL := 2.0
const BUILD_KINDS := ["foundation", "wall", "wood_wall"]
const WALL_LIFT := 0.25   ## walls stand on top of a foundation's slab


static func is_building(kind: String) -> bool:
	return kind in BUILD_KINDS


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


## The foundation in a grid cell, or {} if there isn't one.
static func foundation_at(cell: Vector2i) -> Dictionary:
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind == "foundation":
			var p: Array = st.pos
			if cell_of(Vector3(p[0], p[1], p[2])) == cell:
				return st
	return {}


## Where a building piece would go if the player aims at `aim` (ground point).
## Returns {pos, yaw}. Foundations: the cell under the aim. Walls: the nearest cell edge.
static func snap_piece(kind: String, aim: Vector3) -> Dictionary:
	var cell := cell_of(aim)
	var c := Vector3(cell.x * CELL + CELL * 0.5, 0.0, cell.y * CELL + CELL * 0.5)
	if kind == "foundation":
		c.y = Game.world_gen.get_height(c.x, c.z)
		return {"pos": c, "yaw": 0.0}
	var dx := aim.x - c.x
	var dz := aim.z - c.z
	var pos: Vector3
	var yaw := 0.0
	if absf(dx) > absf(dz):   # the wall runs north-south, on an east or west edge
		pos = Vector3(c.x + signf(dx) * CELL * 0.5, 0.0, c.z)
		yaw = PI * 0.5
	else:                     # runs east-west, on a north or south edge
		pos = Vector3(c.x, 0.0, c.z + signf(dz) * CELL * 0.5)
	# Stand on the foundation that the wall borders (either side), if there is one.
	var sides := _wall_sides(pos, yaw)
	for s: Vector2i in sides:
		var f := foundation_at(s)
		if not f.is_empty():
			pos.y = float(f.pos[1]) + WALL_LIFT
			return {"pos": pos, "yaw": yaw}
	pos.y = Game.world_gen.get_height(pos.x, pos.z)
	return {"pos": pos, "yaw": yaw}


## The two grid cells a wall at `pos` with `yaw` separates.
static func _wall_sides(pos: Vector3, yaw: float) -> Array:
	if absf(yaw) < 0.01:   # along x, on a z boundary
		return [cell_of(Vector3(pos.x, 0, pos.z - 0.5)), cell_of(Vector3(pos.x, 0, pos.z + 0.5))]
	return [cell_of(Vector3(pos.x - 0.5, 0, pos.z)), cell_of(Vector3(pos.x + 0.5, 0, pos.z))]


## Can a structure go here? Returns "" if fine, else the reason.
static func placement_problem(pos: Vector3, kind := "", yaw := 0.0) -> String:
	if pos.y < Game.SEA_LEVEL + 0.15:
		return "Can't build in water"
	if is_building(kind):
		var steep_limit := 0.6 if kind == "foundation" else 0.8
		if kind == "foundation" and Game.world_gen.get_normal(pos.x, pos.z).y < steep_limit:
			return "Too steep here (the ground would need too much levelling)"
		if kind == "foundation":
			if not foundation_at(cell_of(pos)).is_empty():
				return "There's already a foundation here"
			return ""
		var sides := _wall_sides(pos, yaw)
		var supported := false
		for s: Vector2i in sides:
			if not foundation_at(s).is_empty():
				supported = true
		if not supported:
			return "Walls need a foundation along that edge"
		for id: String in Game.structures:
			var o: Dictionary = Game.structures[id]
			var p: Array = o.pos
			if o.kind in BUILD_KINDS and o.kind != "foundation" and Vector3(p[0], p[1], p[2]).distance_to(pos) < 0.5:
				return "There's already a wall here"
		return ""
	if Game.world_gen.get_normal(pos.x, pos.z).y < 0.8:
		return "Too steep here"
	for id: String in Game.structures:
		var p: Array = Game.structures[id].pos
		if Vector3(p[0], p[1], p[2]).distance_to(pos) < 1.8:
			return "Too close to another structure"
	return ""


## Place the held placeable. Result: {ok, reason, id}
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
	var hp := 8 if is_building(kind) else 3
	Game.structures[id] = {"id": id, "kind": kind, "pos": [pos.x, pos.y, pos.z], "yaw": yaw, "hp": hp}
	Game.structures_changed.emit()
	return {"ok": true, "id": id, "kind": kind}


## Knock a structure down a bit; after a few hits it's packed back up into an item.
static func hit_structure(player_id: int, structure_id: String) -> Dictionary:
	if not Game.structures.has(structure_id):
		return {"ok": false}
	var st: Dictionary = Game.structures[structure_id]
	st.hp = int(st.hp) - 1
	if st.hp > 0:
		return {"ok": true, "packed": false}
	Game.structures.erase(structure_id)
	Game.structures_changed.emit()
	var p: Array = st.pos
	var got := Game.inventory_of(player_id).add(st.kind, 1)
	if got < 1:
		spawn_pickup(st.kind, 1, -1, Vector3(p[0], p[1] + 0.3, p[2]))
	return {"ok": true, "packed": true, "kind": st.kind}


# --- Items in the world -----------------------------------------------------------------

## Drop items from a slot onto the ground in front of the player.
static func drop(player_id: int, slot: int, amount: int, pos: Vector3) -> String:
	var inv := Game.inventory_of(player_id)
	var stack := inv.take_from_slot(slot, amount)
	if stack.is_empty():
		return ""
	return spawn_pickup(stack.id, stack.count, int(stack.dur), pos)


static func spawn_pickup(item: String, count: int, dur: int, pos: Vector3) -> String:
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
	# One or two tools, usually stone or the world's first metal, rarely better.
	for i in rng.randi_range(1, 2):
		var roll := rng.randf()
		var tier := 1 if roll < 0.6 else (2 if roll < 0.9 else 3)
		var id := "%s_t%d" % [tools[rng.randi() % tools.size()], tier]
		var dur := int(ItemDB.tool_stats(id).durability * rng.randf_range(0.4, 0.9))   # well used
		var got := inv.add(id, 1, false, dur)
		if got > 0:
			out[id] = out.get(id, 0) + 1
	var supplies := [["wood", 10, 30], ["stone", 10, 25], ["fiber", 5, 15], ["ore_t2", 3, 8], ["flint", 1, 4], ["berries", 3, 8], ["resin", 1, 3]]
	for i in rng.randi_range(2, 4):
		var e: Array = supplies[rng.randi() % supplies.size()]
		_add(inv, e[0], rng.randi_range(e[1], e[2]), out)
