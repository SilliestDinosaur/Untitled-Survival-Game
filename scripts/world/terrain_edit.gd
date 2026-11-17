class_name TerrainEdit
extends RefCounted
## Shovel terrain work: dig, pile, flatten and smooth the ground. The result is a list of changed
## cells [x, z, metres_added] relative to the procedural ground. Those lists are what get saved and
## what friends receive, so every machine ends up with identical terrain.

enum Mode { DIG, PILE, FLATTEN, SMOOTH }
const MODE_NAMES := ["Dig", "Pile", "Flatten", "Smooth"]
const MIN_HEIGHT := -6.0   ## never dig deeper than this below sea level
const MAX_RADIUS := 4.0
const DIRT_PER_M3 := 1.2   ## dirt you get from a cubic metre dug out


## Trees standing in the ground (the chunk generator places them the same way on every machine,
## so this works even for trees in chunks nobody has loaded here). Cached per chunk.
static var _tree_cache := {}
const TREE_CLEARANCE := 1.2   ## a stroke may not come this close to a trunk


## Trunk positions in one chunk, gathered trees excluded at query time.
static func _trees_in_chunk(c: Vector2i) -> Array:
	var key := "%d_%d_%d" % [Game.world_seed, c.x, c.y]
	if not _tree_cache.has(key):
		var origin := Vector3(c.x * Game.CHUNK_SIZE, 0.0, c.y * Game.CHUNK_SIZE)
		var out := []
		for r: Dictionary in ChunkGenerator._place_resources(c, origin, Game.world_gen, Game.flora, {}):
			if FloraLibrary.category_of(r.kind) == "tree":
				out.append([r.transform.origin, r.id])
		_tree_cache[key] = out
	return _tree_cache[key]


## The nearest standing tree within `radius` of p (ground distance), or null.
static func tree_near(p: Vector3, radius: float) -> Variant:
	var size := float(Game.CHUNK_SIZE)
	var lo := Vector2i(floori((p.x - radius - 8.0) / size), floori((p.z - radius - 8.0) / size))
	var hi := Vector2i(floori((p.x + radius + 8.0) / size), floori((p.z + radius + 8.0) / size))
	var best: Variant = null
	var best_d := radius + TREE_CLEARANCE
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for t: Array in _trees_in_chunk(Vector2i(x, z)):
				if Game.is_removed(t[1]):
					continue
				var d := Vector2(t[0].x - p.x, t[0].z - p.z).length()
				if d < best_d:
					best_d = d
					best = t[0]
	return best


## Work out the change for one shovel stroke. Does not change the world yet (see commit).
## op: {mode, x, z, r (metres), s (strength), target (metres, for flatten)}
## Returns {ok, cells, dirt, reason}. Piling takes dirt from `inv`; digging adds dirt to it.
static func apply(op: Dictionary, inv: Inventory) -> Dictionary:
	var gen: WorldGen = Game.world_gen
	var mode := int(op.mode)
	var r := clampf(float(op.r), 0.5, MAX_RADIUS)
	var s := clampf(float(op.s), 0.05, 1.0)
	var cx := float(op.x)
	var cz := float(op.z)
	var target := float(op.get("target", gen.get_height(cx, cz)))
	if tree_near(Vector3(cx, 0.0, cz), r) != null:
		return {"ok": false, "reason": "A tree is in the way. Chop it down first."}
	var stone := bool(op.get("rock", false))   # the pickaxe: only stone can be carved
	if stone and (mode != Mode.DIG or gen.get_surface(cx, cz) != "rock"):
		return {"ok": false, "reason": "Too soft to carve. Only stone can be broken with a pickaxe."}
	var budget := inv.count("dirt") if mode == Mode.PILE else 0
	var removed := 0.0
	var added := 0.0
	var cells: Array = []
	var ri := ceili(r)
	for j in range(floori(cz) - ri, floori(cz) + ri + 1):
		for i in range(floori(cx) - ri, floori(cx) + ri + 1):
			var dx := float(i) - cx
			var dz := float(j) - cz
			var dist := sqrt(dx * dx + dz * dz) / r
			if dist >= 1.0:
				continue
			var f := smoothstep(1.0, 0.0, dist)   # full strength at the centre, none at the rim
			var cur := gen.get_height(i, j)
			var nh := cur
			match mode:
				Mode.DIG:
					nh = cur - s * f
				Mode.PILE:
					var add := minf(s * f, budget - added)
					if add <= 0.0:
						continue
					nh = cur + add
				Mode.FLATTEN:
					nh = lerpf(cur, target, clampf(f * s * 1.5, 0.0, 1.0))
				Mode.SMOOTH:
					var avg := (gen.get_height(i - 1, j) + gen.get_height(i + 1, j) + gen.get_height(i, j - 1) + gen.get_height(i, j + 1)) * 0.25
					nh = lerpf(cur, avg, clampf(f * s, 0.0, 1.0))
			nh = maxf(nh, MIN_HEIGHT)
			var dv := nh - cur
			if dv < 0.0:
				removed -= dv
			else:
				added += dv
			var base := gen.get_base_height(i, j)
			cells.append([i, j, nh - base])
	if cells.is_empty():
		return {"ok": false, "reason": "Nothing to %s here" % MODE_NAMES[mode].to_lower()}
	var dirt := 0
	if mode == Mode.DIG and stone:
		dirt = roundi(removed * 2.0)   # stone yield (the field is still called dirt in results)
		if dirt > 0:
			inv.add("stone", dirt)
	elif mode == Mode.DIG:
		dirt = roundi(removed * DIRT_PER_M3)
		if dirt > 0:
			inv.add("dirt", dirt)
	elif mode == Mode.PILE:
		dirt = roundi(added)
		if dirt > 0:
			inv.remove("dirt", mini(dirt, inv.count("dirt")))
		if added <= 0.0:
			return {"ok": false, "reason": "You're out of dirt"}
	return {"ok": true, "cells": cells, "dirt": dirt}


## For a piece placed at `center` (its base at height y), the ground inside its footprint is
## cut down to the piece's base wherever it rises above it, like clearing a space for a building.
## With `fill`, holes inside the footprint are filled up to y as well. Returns cell changes.
static func clear_rect(center: Vector3, hx: float, hz: float, yaw: float, y: float, fill: bool) -> Array:
	var gen: WorldGen = Game.world_gen
	var rot := absf(yaw - PI * 0.5) < 0.01
	var ex := hz if rot else hx
	var ez := hx if rot else hz
	var cells: Array = []
	for j in range(floori(center.z - ez), ceili(center.z + ez) + 1):
		for i in range(floori(center.x - ex), ceili(center.x + ex) + 1):
			if absf(float(i) - center.x) > ex or absf(float(j) - center.z) > ez:
				continue
			var cur := gen.get_height(i, j)
			if cur > y + 0.02 or (fill and cur < y - 0.02):
				cells.append([i, j, y - gen.get_base_height(i, j)])
	return cells


## Make a change real on this machine: update the ground and rebuild the chunks it touches.
static func commit(cells: Array) -> void:
	var gen: WorldGen = Game.world_gen
	if not gen:
		return
	var nd: Dictionary = gen.edits.duplicate()
	for c: Array in cells:
		var k := Vector2i(int(c[0]), int(c[1]))
		var d := float(c[2])
		if absf(d) < 0.001:
			nd.erase(k)
		else:
			nd[k] = d
	gen.edits = nd
	Game.terrain_changed.emit(cells)


## Every edit as a flat list, for saves and for sending to a new player.
static func to_list(edits: Dictionary) -> Array:
	var out: Array = []
	for k: Vector2i in edits:
		out.append([k.x, k.y, edits[k]])
	return out


static func from_list(list: Array) -> Dictionary:
	var out := {}
	for c: Array in list:
		out[Vector2i(int(c[0]), int(c[1]))] = float(c[2])
	return out
