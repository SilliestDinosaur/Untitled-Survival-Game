class_name TerrainEdit
extends RefCounted
## Ground changes made by building. The player can't dig or pile the ground; only placed pieces move
## it: a foundation levels the ground under its footprint to its own height (cutting down hills and
## filling hollows, blending out at the rim), and other pieces cut away any ground poking into them.
## The result of each change is a list of cells [x, z, metres_added] relative to the procedural
## ground. Those lists are what get saved and what friends receive, so every machine ends up with
## identical terrain.

const RIM := 2.0   ## metres over which levelled ground blends back into the natural ground


## Trees standing in the ground (the chunk generator places them the same way on every machine,
## so this works even for trees in chunks nobody has loaded here). Cached per chunk.
static var _tree_cache := {}


## A loaded chunk's trees, from what its generator already placed (on a worker thread): placing them again here,
## on the main thread, the first time someone aimed a building into the chunk took tens of milliseconds.
static func remember_trees(c: Vector2i, resources: Array[Dictionary]) -> void:
	var key := "%d_%d_%d" % [Game.world_seed, c.x, c.y]
	if _tree_cache.has(key):
		return
	var out := []
	for r: Dictionary in resources:
		if FloraLibrary.category_of(r.kind) == "tree":
			out.append([r.transform.origin, r.id])
	_tree_cache[key] = out


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
	var best_d := radius
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


## A foundation at `center` (its top at height y, footprint half-sizes hx by hz, turned by yaw).
## The ground inside the footprint is levelled to y, cutting hills and filling hollows; outside it
## the ground blends back over RIM metres. Returns the cell changes (not applied yet).
static func level_ground(center: Vector3, hx: float, hz: float, yaw: float, y: float) -> Array:
	var gen: WorldGen = Game.world_gen
	var rot := absf(sin(yaw)) > 0.5   # a quarter turn (either way) swaps the footprint's sides
	var ex := hz if rot else hx
	var ez := hx if rot else hz
	var reach := ceili(maxf(ex, ez) + RIM) + 1
	var cells: Array = []
	for j in range(floori(center.z) - reach, floori(center.z) + reach + 1):
		for i in range(floori(center.x) - reach, floori(center.x) + reach + 1):
			# Distance outside the footprint (negative inside), on the rectangle.
			var out := maxf(absf(float(i) - center.x) - ex, absf(float(j) - center.z) - ez)
			var w := 1.0 if out <= 0.0 else 1.0 - smoothstep(0.0, RIM, out)
			if w <= 0.0:
				continue
			var cur := gen.get_height(i, j)
			var nh := lerpf(cur, y, w)
			if absf(nh - cur) < 0.001:
				continue
			cells.append([i, j, nh - gen.get_base_height(i, j)])
	return cells


## For a wall, doorway or roof at `center`: cut away ground that rises above its base inside the
## footprint (never fill, the piece just needs clear space). Returns the cell changes.
static func clear_rect(center: Vector3, hx: float, hz: float, yaw: float, y: float) -> Array:
	var gen: WorldGen = Game.world_gen
	var rot := absf(sin(yaw)) > 0.5   # a quarter turn (either way) swaps the footprint's sides
	var ex := (hz if rot else hx) + 0.5   # every 1 m cell the footprint touches, even a thin wall's
	var ez := (hx if rot else hz) + 0.5
	var cells: Array = []
	for j in range(floori(center.z - ez), ceili(center.z + ez) + 1):
		for i in range(floori(center.x - ex), ceili(center.x + ex) + 1):
			if absf(float(i) - center.x) > ex or absf(float(j) - center.z) > ez:
				continue
			var cur := gen.get_height(i, j)
			if cur > y + 0.02:
				cells.append([i, j, y - gen.get_base_height(i, j)])
	return cells


## How placing a piece changes the ground: a ground-floor slab levels the ground under it; an upper storey's floor
## stands on walls and leaves the ground alone; anything else cuts away ground poking into it.
static func cells_for(kind: String, pos: Vector3, yaw: float, level: int) -> Array:
	if kind in GameActions.FLOOR_KINDS:
		return level_ground(pos, 1.5, 1.5, 0.0, pos.y) if level == 0 else []
	var rect := Vector2(1.5, 0.25) if kind in GameActions.EDGE_KINDS else Vector2(1.5, 1.5)
	return clear_rect(pos, rect.x, rect.y, yaw, pos.y)


## Work the ground out again from scratch: every piece standing, in the order it was placed, shaping the ground as
## it does now. (Repairs saves from before upper floors stopped raising hills under themselves.)
static func rebuild(structures: Dictionary) -> void:
	var gen: WorldGen = Game.world_gen
	if not gen:
		return
	gen.edits = {}
	var ids := structures.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return a.trim_prefix("s").to_int() < b.trim_prefix("s").to_int())
	for id: String in ids:
		var st: Dictionary = structures[id]
		var p: Array = st.pos
		var cells := cells_for(String(st.kind), Vector3(p[0], p[1], p[2]), float(st.get("yaw", 0.0)), int(st.get("level", 0)))
		if cells.is_empty():
			continue
		var nd: Dictionary = gen.edits.duplicate()
		for c: Array in cells:
			var k := Vector2i(int(c[0]), int(c[1]))
			if absf(float(c[2])) < 0.001:
				nd.erase(k)
			else:
				nd[k] = float(c[2])
		gen.edits = nd


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
