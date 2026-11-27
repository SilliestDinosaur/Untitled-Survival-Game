class_name Ruins
extends RefCounted
## Where the island's ruins are: old overgrown temples on level ground and watchtowers on rises, each one laid out
## and weathered differently (see RuinModels), with a cache of supplies to find in it. (Cave vaults are planned
## with the caves: see Caves._plan_vaults.)
##
## A ruin is a Dictionary: {kind: "temple"|"tower", pos (on the ground), yaw, seed, r (its ground: no trees or
## rocks on it), size: Vector2 (a temple's plinth; a tower's radius and height)}.
## Only worlds made since ruins came (Game.world_v >= 2) have them: an older save's island stays as it was.

const MAX := {"temple": 4, "tower": 5}   ## per 2 km of island (more on a bigger one, the same share of its ground)
const APART := 260.0                      ## between ruins
const CLEAR_OF_LANDMARKS := 120.0


static func plan(gen: WorldGen) -> Array:
	if Game.world_v < 2:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "ruins"])
	var size := gen.size
	var area := pow(size / 2048.0, 2.0)
	var most := {}
	var wanted := 0
	for k: String in MAX:
		most[k] = roundi(float(MAX[k]) * area)
		wanted += int(most[k])
	var counts := {}
	var out: Array = []
	var tries := 0
	while tries < roundi(9000 * area) and out.size() < wanted:
		tries += 1
		var x := rng.randf_range(100.0, size - 100.0)
		var z := rng.randf_range(100.0, size - 100.0)
		var kind := "temple" if rng.randf() < 0.45 else "tower"
		var yaw := rng.randf() * TAU
		var seed_value := rng.randi()
		if int(counts.get(kind, 0)) >= int(most[kind]):
			continue
		var h := gen.get_height(x, z)
		if h < 4.0 or h > 70.0 or gen.near_river(x, z, 16.0):
			continue
		var des := design(kind, seed_value)
		var dims: Vector2 = des.dims
		var reach: float = des.reach
		if not _clear(out, gen.landmarks, x, z):
			continue
		if Caves.void_distance(gen.caves, Vector3(x, h, z)) < 14.0:
			continue
		var biome := gen.get_biome(x, z)
		if kind == "temple":
			if biome in [WorldGen.Biome.TUNDRA, WorldGen.Biome.MARSH] or h > 45.0 or gen.get_normal(x, z).y < 0.9:
				continue
			if _rise(gen, x, z, yaw, dims.x * 0.5 + 1.0, dims.y * 0.5 + 1.0) > 3.6:
				continue   # too steep for a plinth
		else:
			if h < 12.0 or gen.get_normal(x, z).y < 0.8 or biome == WorldGen.Biome.MARSH:
				continue
			if des.fort:
				# A fort wants a broad, level-ish top for its walls.
				if _rise(gen, x, z, yaw, float(des.span) + 2.0, float(des.span) + 2.0) > 3.8:
					continue
			else:
				if _rise(gen, x, z, 0.0, dims.x + 1.6, dims.x + 1.6) > 3.0:
					continue
				# On a rise: the land falls away round it (a view, and seen from afar).
				var ring := 0.0
				for k in 8:
					var a := TAU * k / 8.0
					ring += gen.get_height(x + cos(a) * 30.0, z + sin(a) * 30.0)
				if ring / 8.0 > h - 2.0:
					continue
		counts[kind] = int(counts.get(kind, 0)) + 1
		out.append({"kind": kind, "pos": Vector3(x, h, z), "yaw": yaw, "seed": seed_value, "r": reach, "size": dims, "fort": bool(des.get("fort", false))})
	return out


## A ruin's design, from its seed alone (so the planner and the models agree without passing anything round):
##   temple: {dims (its footprint, metres), reach, plan (see _floor_plan)}
##   tower:  {dims (radius, height), reach, fort: false}, or a fort: {fort: true, span (its half width), towers:
##           [[centre Vector2, radius, height, round?]] (the first the keep), dims, reach}
static func design(kind: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if kind == "temple":
		var plan := _floor_plan(rng)
		var dims := Vector2(plan.nx * plan.cell + 2.0, plan.nz * plan.cell + 2.0)
		return {"dims": dims, "reach": dims.length() * 0.5 + 7.0, "plan": plan}
	if rng.randf() < 0.45:
		# A fort: towers round a courtyard, curtain walls between them.
		var n := rng.randi_range(3, 5)
		var span := rng.randf_range(8.0, 13.0)
		var towers: Array = []
		var turn := rng.randf() * TAU
		for k in n:
			var a := turn + TAU * k / n + rng.randf_range(-0.25, 0.25) / n * TAU
			var d := span * rng.randf_range(0.85, 1.05)
			var keep := k == 0
			towers.append([Vector2(cos(a), sin(a)) * d, rng.randf_range(2.5, 3.2) if keep else rng.randf_range(1.6, 2.3),
				rng.randf_range(11.0, 16.0) if keep else rng.randf_range(6.0, 9.5), rng.randf() < 0.65])
		return {"fort": true, "span": span, "towers": towers, "dims": Vector2(span, 6.0), "reach": span + 9.0}
	var dims := Vector2(rng.randf_range(2.0, 3.4), rng.randf_range(7.0, 18.0))
	return {"fort": false, "dims": dims, "reach": dims.x + 6.0}


## A walk-in temple's floor plan on a grid of cells: rooms of different sizes, a tree of corridors joining them (a
## loop or two, a dead end or two), sometimes a courtyard open to the sky, sometimes a room with a stair up to a
## roof terrace. The way in is at the front (the -z edge).
##   {cell (metres), nx, nz, grid: cell -> 0 nothing, 1 corridor, 2+ room (index + 2), rooms: [Rect2i],
##    open: {Vector3i(x, z, axis): true} (a way through that edge: axis 0 the +x side, 1 the +z side),
##    entrance: Vector2i (a front-row cell, entered through its -z side), court, deep, stair (room indices or -1)}
static func _floor_plan(rng: RandomNumberGenerator) -> Dictionary:
	var cell := snappedf(rng.randf_range(2.8, 3.8), 0.1)
	var nx := rng.randi_range(3, 7)
	var nz := rng.randi_range(3, 7)
	var grid: Array = []   # (an Array, not a packed one: the carving below changes it from inside a lambda)
	grid.resize(nx * nz)
	grid.fill(0)
	var rooms: Array = []
	var want := 1 + (nx * nz) / 7
	for t in 60:
		if rooms.size() >= want:
			break
		var w := rng.randi_range(1, mini(3, nx))
		var d := rng.randi_range(1, mini(3, nz))
		var r := Rect2i(rng.randi_range(0, nx - w), rng.randi_range(0, nz - d), w, d)
		var ok := true
		for o: Rect2i in rooms:   # a cell apart at least, for corridors between
			if r.position.x < o.end.x + 1 and r.end.x + 1 > o.position.x and r.position.y < o.end.y + 1 and r.end.y + 1 > o.position.y:
				ok = false
				break
		if not ok:
			continue
		rooms.append(r)
		for x in range(r.position.x, r.end.x):
			for z in range(r.position.y, r.end.y):
				grid[z * nx + x] = rooms.size() + 1
	if rooms.is_empty():
		rooms.append(Rect2i(0, 0, nx, nz))
		grid.fill(2)
	var open := {}
	var carve := func(a: Vector2i, b: Vector2i) -> void:
		var c := a
		var x_first := rng.randf() < 0.5
		while c != b:
			var step := Vector2i(signi(b.x - c.x), 0) if (x_first and c.x != b.x) or c.y == b.y else Vector2i(0, signi(b.y - c.y))
			var n := c + step
			if grid[n.y * nx + n.x] == 0:
				grid[n.y * nx + n.x] = 1
			open[_edge(c, n)] = true
			c = n
	var centre := func(r: Rect2i) -> Vector2i: return r.position + Vector2i(r.size.x / 2, r.size.y / 2)
	# Join the rooms: a tree (each new room to the nearest already joined), then a loop or two.
	var joined := [0]
	while joined.size() < rooms.size():
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for i in rooms.size():
			if joined.has(i):
				continue
			for j: int in joined:
				var dd := float((centre.call(rooms[i]) - centre.call(rooms[j])).length_squared())
				if dd < best_d:
					best_d = dd
					best = Vector2i(i, j)
		carve.call(centre.call(rooms[best.x]), centre.call(rooms[best.y]))
		joined.append(best.x)
	if rooms.size() >= 3:
		for k in rng.randi_range(0, 2):
			carve.call(centre.call(rooms[rng.randi() % rooms.size()]), centre.call(rooms[rng.randi() % rooms.size()]))
	# The way in: from the front edge, straight back to the first room it meets (or the nearest room).
	var front: Rect2i = rooms[0]
	for r: Rect2i in rooms:
		if r.position.y < front.position.y:
			front = r
	var ex := clampi(front.position.x + rng.randi_range(0, front.size.x - 1), 0, nx - 1)
	var entrance := Vector2i(ex, 0)
	if grid[ex] == 0:
		grid[ex] = 1
	carve.call(entrance, Vector2i(ex, front.position.y))
	# A dead end or two off the corridors.
	for k in rng.randi_range(0, 2):
		var halls: Array = []
		for i in grid.size():
			if grid[i] == 1:
				halls.append(Vector2i(i % nx, i / nx))
		if halls.is_empty():
			break
		var c: Vector2i = halls[rng.randi() % halls.size()]
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for step in rng.randi_range(1, 2):
			var dir: Vector2i = dirs[rng.randi() % 4]
			var n := c + dir
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or grid[n.y * nx + n.x] != 0:
				break
			grid[n.y * nx + n.x] = 1
			open[_edge(c, n)] = true
			c = n
	# The deepest room from the way in (where the chest is), a courtyard, a room with a stair up.
	var dist := {entrance: 0}
	var queue := [entrance]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + dir
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or dist.has(n) or grid[n.y * nx + n.x] == 0:
				continue
			var gc: int = grid[c.y * nx + c.x]
			var gn: int = grid[n.y * nx + n.x]
			if (gc >= 2 and gc == gn) or open.has(_edge(c, n)):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	var deep := 0
	var far := -1
	for i in rooms.size():
		var c: Vector2i = centre.call(rooms[i])
		if int(dist.get(c, -1)) > far:
			far = int(dist.get(c, -1))
			deep = i
	var court := -1
	var stair := -1
	var order: Array = range(rooms.size())
	for i: int in order:
		var r: Rect2i = rooms[i]
		if court < 0 and i != deep and r.size.x * r.size.y >= 4 and rng.randf() < 0.5:
			court = i
		elif stair < 0 and i != court and maxi(r.size.x, r.size.y) >= 2 and rng.randf() < 0.45:
			stair = i
	return {"cell": cell, "nx": nx, "nz": nz, "grid": grid, "rooms": rooms, "open": open, "entrance": entrance,
		"court": court, "deep": deep, "stair": stair}


## The key of the edge between two neighbouring cells.
static func _edge(a: Vector2i, b: Vector2i) -> Vector3i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	return Vector3i(lo.x, lo.y, 0 if a.x != b.x else 1)


## The ruin whose ground (x, z) is on, or {}.
static func at(list: Array, x: float, z: float) -> Dictionary:
	for ru: Dictionary in list:
		var p: Vector3 = ru.pos
		if Vector2(p.x - x, p.z - z).length() < float(ru.r):
			return ru
	return {}


## The ground's rise (highest - lowest) over a rectangle half w by half d, turned by yaw.
static func _rise(gen: WorldGen, x: float, z: float, yaw: float, hw: float, hd: float) -> float:
	var lo := 1e9
	var hi := -1e9
	var b := Basis(Vector3.UP, yaw)
	for i in 5:
		for j in 5:
			var p := b * Vector3(lerpf(-hw, hw, i / 4.0), 0, lerpf(-hd, hd, j / 4.0))
			var h := gen.get_height(x + p.x, z + p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


static func _clear(out: Array, landmarks: Array, x: float, z: float) -> bool:
	for o: Dictionary in out:
		if Vector2(o.pos.x - x, o.pos.z - z).length() < APART:
			return false
	for lm: Dictionary in landmarks:
		if Vector2(lm.pos.x - x, lm.pos.z - z).length() < CLEAR_OF_LANDMARKS:
			return false
	return true
