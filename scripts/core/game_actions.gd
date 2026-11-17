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
	var inv := Game.inventory_of(player_id)
	var r := chunk.resources[index]
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
	_give(inv, ItemDB.YIELDS.get(key, []), mult, rng, result.items)
	if r.hp <= 0.0:
		_give(inv, ItemDB.BONUS.get(key, []), 1.0, rng, result.items)
		if r.kind == "cache":
			Game.looted[r.id] = true
		Game.mark_removed(r.id)
		result.destroyed = true
	else:
		Game.resource_hp[r.id] = r.hp
	result.broke = inv.damage_selected(1)
	result.ok = true
	return result


## Gather by hand (Interact): berries, fiber, sticks, fruit, picking up small things, caches.
## Result: {ok, kind, items, picked_up (node removed), empty (nothing to take right now)}
static func harvest_resource(player_id: int, chunk: TerrainChunk, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var inv := Game.inventory_of(player_id)
	var r := chunk.resources[index]
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
	var inv := Game.inventory_of(player_id)
	var id := inv.selected_item()
	var info := ItemDB.info(id)
	if id == "" or info.kind != "food" or not inv.remove(id, 1):
		return {"ok": false}
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
