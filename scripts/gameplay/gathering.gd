class_name Gathering
extends RefCounted
## The rules for hitting things and getting resources. All game-state changes for
## gathering go through here (one place to make network-authoritative later).

## Result: {target, kind, blocked, destroyed, items: {id: amount}}
static func hit_resource(chunk: TerrainChunk, index: int, tool_id: String, inv: Inventory, rng: RandomNumberGenerator) -> Dictionary:
	var r := chunk.resources[index]
	var result := {"target": ItemDB.target_type(r.kind), "kind": r.kind, "blocked": false, "destroyed": false, "items": {}}
	if r.get("removed", false):
		return result
	var mult: float = ItemDB.tool_stats(tool_id).get(result.target, 0.0)
	if mult <= 0.0:
		result.blocked = true     # e.g. punching a boulder
		return result
	var key := ItemDB.yield_key(r.kind)
	r.hp = float(r.hp) - ItemDB.HIT_DAMAGE * mult
	_give(inv, ItemDB.YIELDS[key], mult, rng, result.items)
	if r.hp <= 0.0:
		_give(inv, ItemDB.BONUS.get(key, []), 1.0, rng, result.items)
		Game.mark_removed(r.id)
		result.destroyed = true
	else:
		Game.resource_hp[r.id] = r.hp
	return result


## Harvest a dead animal. Bigger animals give more.
static func hit_carcass(animal: Node, tool_id: String, inv: Inventory, rng: RandomNumberGenerator) -> Dictionary:
	var result := {"target": "carcass", "kind": "carcass", "blocked": false, "destroyed": false, "items": {}}
	var mult: float = ItemDB.tool_stats(tool_id).get("carcass", 0.0)
	if mult <= 0.0:
		result.blocked = true
		return result
	var size: float = animal.species.yield_scale
	animal.carcass_hp -= ItemDB.HIT_DAMAGE * mult
	_give(inv, ItemDB.YIELDS.carcass, mult * size, rng, result.items)
	if animal.carcass_hp <= 0.0:
		_give(inv, ItemDB.BONUS.carcass, size, rng, result.items)
		result.destroyed = true
	return result


static func _give(inv: Inventory, table: Array, mult: float, rng: RandomNumberGenerator, out: Dictionary) -> void:
	for e: Array in table:
		var n := int(round(rng.randi_range(e[1], e[2]) * mult))
		if e[2] > 0 and mult > 0.0 and n == 0 and rng.randf() < mult:
			n = 1   # small tools/animals still give something now and then
		n = inv.add(e[0], n)
		if n > 0:
			out[e[0]] = out.get(e[0], 0) + n
