class_name Caves
extends RefCounted
## Caves cut into the rock under the island. Entrances are openings in the hillsides; from each one
## tunnels wind inward and downward, with chambers, branches, dead ends and loops, and close
## entrances are joined by long corridors. The plan is made from the BASE terrain (before any building)
## so every machine plans the same caves. VoxelTerrain subtracts the planned voids from the ground.
##
## A plan is a Dictionary: {entrances, roots, nodes, rooms, chests, glow, segs, buckets}.
## segs are [a: Vector3, b: Vector3, ra: float, rb: float, walk_a, walk_b, floor_a, floor_b, ceiling, theme_a,
## theme_b] tunnel pieces (a capsule cut flat at its floor, and at its ceiling for lake basins); buckets map a 16 m grid
## cell to the segs that reach it, for quick lookups. A plan is read-only once made, so worker
## threads can use it safely.

const MIN_SPACING := 120.0   ## entrances are kept apart
const MAX_ENTRANCES := 12
const MAX_NODES := 900
const LINK_DISTANCE := 260.0
const MAX_DEPTH := 24.0      ## tunnels never go deeper than this under the ground above
const CLEARANCE := 1.5       ## metres of rock left over the top of a tunnel
const BUCKET := 16.0

## What a cave's rock is like, from the land above it (and a few deep chambers of crystal).
enum Rock { STONE, ICE, MOSS, SAND, FUNGAL, CRYSTAL }
const NO_FLOOR := -1.0e9
const NO_CEILING := 1.0e9
const MAX_LAKES := 5
const MAX_CRYSTAL_ROOMS := 4
const MOUTH_R := 2.8          ## a cave mouth's radius


static func theme_for_biome(b: int) -> int:
	match b:
		WorldGen.Biome.SNOW, WorldGen.Biome.TUNDRA, WorldGen.Biome.TAIGA:
			return Rock.ICE
		WorldGen.Biome.FOREST, WorldGen.Biome.JUNGLE, WorldGen.Biome.MARSH, WorldGen.Biome.AUTUMN:
			return Rock.MOSS
		WorldGen.Biome.DESERT, WorldGen.Biome.BADLANDS, WorldGen.Biome.DRYLANDS, WorldGen.Biome.BEACH:
			return Rock.SAND
		WorldGen.Biome.FUNGAL:
			return Rock.FUNGAL
	return Rock.STONE


## The cave rock's colour for a theme (sRGB), on a wall or (up-facing) a floor.
static func theme_rock(theme: int, floor_up: float, y: float) -> Color:
	var stone: Color = Game.palette.rock.darkened(0.3)
	# Layers in the walls: soft bands of lighter and darker rock running level round the caves (wavering a little),
	# strongest on the walls, gone on the floors.
	var strata := (sin(y * 1.9 + sin(y * 0.55) * 1.7) * 0.6 + sin(y * 4.7 + 1.3) * 0.4) * 0.07 * (1.0 - floor_up)
	stone = stone.lightened(maxf(strata, 0.0)).darkened(maxf(-strata, 0.0))
	match theme:
		Rock.ICE:
			return Color(0.5, 0.6, 0.68).lerp(Color(0.8, 0.86, 0.9), floor_up).lightened(maxf(strata, 0.0) * 0.6).darkened(maxf(-strata, 0.0) * 0.6)
		Rock.MOSS:
			return stone.lerp(Color(0.24, 0.3, 0.17), 0.35 + 0.5 * floor_up)
		Rock.SAND:
			var band := 0.5 + 0.5 * sin(y * 2.3 + sin(y * 0.7) * 1.5)
			return Color(0.56, 0.38, 0.25).lerp(Color(0.7, 0.53, 0.36), band).lerp(Color(0.66, 0.52, 0.38), floor_up * 0.5)
		Rock.FUNGAL:
			return Color(0.3, 0.24, 0.33).lerp(Color(0.38, 0.28, 0.42), floor_up).lightened(maxf(strata, 0.0)).darkened(maxf(-strata, 0.0))
		Rock.CRYSTAL:
			return Color(0.2, 0.2, 0.28).lerp(Color(0.28, 0.27, 0.36), floor_up)
	return stone


## The theme of the cave nearest p (the nearer end of the nearest piece), or -1 out of the caves.
static func theme_at(plan: Dictionary, p: Vector3) -> int:
	var hit := _nearest_piece(plan, p)
	if hit.is_empty():
		return -1
	var sg: Array = hit.s
	return int(sg[9]) if float(hit.t) < 0.5 else int(sg[10])


## The cave wall's colour at p (blended along the nearest piece between its two ends' themes), sRGB.
static func rock_color(plan: Dictionary, p: Vector3, up: float) -> Color:
	var hit := _nearest_piece(plan, p)
	var f := clampf((up - 0.45) / 0.4, 0.0, 1.0)
	if hit.is_empty():
		return theme_rock(Rock.STONE, f, p.y)
	var sg: Array = hit.s
	var ta := int(sg[9])
	var tb := int(sg[10])
	var c := theme_rock(ta, f, p.y)
	if tb != ta:
		c = c.lerp(theme_rock(tb, f, p.y), smoothstep(0.2, 0.8, float(hit.t)))
	# Wet round an underground lake: darker and cooler on the shore and the walls just over the water.
	for lk: Array in plan.get("lakes", []):
		var at: Vector3 = lk[0]
		var reach := float(lk[1]) + 2.5
		var dx := Vector2(p.x - at.x, p.z - at.z).length()
		if dx < reach and p.y < at.y + 2.0 and p.y > at.y - 1.5:
			var wet := (1.0 - smoothstep(float(lk[1]), reach, dx)) * (1.0 - smoothstep(at.y + 0.6, at.y + 2.0, p.y))
			c = c.lerp(c.darkened(0.35).lerp(Color(0.16, 0.22, 0.26), 0.25), wet)
	return c


static func _nearest_piece(plan: Dictionary, p: Vector3) -> Dictionary:
	if plan.is_empty():
		return {}
	var key := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
	if not plan.buckets.has(key):
		return {}
	var best := 99.0
	var out := {}
	var bounds: PackedVector4Array = plan.bounds
	for si: int in plan.buckets[key]:
		var bb := bounds[si]
		if Vector3(bb.x - p.x, bb.y - p.y, bb.z - p.z).length() - bb.w >= best:
			continue
		var sg: Array = plan.segs[si]
		var a: Vector3 = sg[0]
		var ab: Vector3 = sg[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := _piece_distance(sg, p)
		if d < best:
			best = d
			out = {"s": sg, "t": t}
	return out


## Hillside spots where an entrance can open: steep faces between the lowlands and the peaks.
static func entrances(gen: WorldGen) -> Array:
	var cand: Array = []
	var size := Game.WORLD_SIZE
	var z := 60.0
	while z < size - 60.0:
		var x := 60.0
		while x < size - 60.0:
			var h := gen.get_base_height(x, z)
			if h > 10.0 and h < 55.0 and _base_slope_y(gen, x, z) < 0.8:
				cand.append(Vector3(x, h, z))
			x += 24.0
		z += 24.0
	# Shuffle deterministically by seed, then take the first spread-out ones.
	cand.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return hash([Game.world_seed, a.x, a.z]) < hash([Game.world_seed, b.x, b.z]))
	var out: Array = []
	for c: Vector3 in cand:
		if out.size() >= MAX_ENTRANCES:
			break
		var ok := true
		for o: Vector3 in out:
			if Vector2(o.x - c.x, o.z - c.z).length() < MIN_SPACING:
				ok = false
				break
		if ok:
			out.append(c)
	return out


## The normal's height component on the base terrain (1 = flat, lower = steeper).
static func _base_slope_y(gen: WorldGen, x: float, z: float) -> float:
	var gx := (gen.get_base_height(x + 1.0, z) - gen.get_base_height(x - 1.0, z)) * 0.5
	var gz := (gen.get_base_height(x, z + 1.0) - gen.get_base_height(x, z - 1.0)) * 0.5
	return 1.0 / sqrt(1.0 + gx * gx + gz * gz)


## Plan every cave for this world. Call once per world, on the main thread.
static var timing := {}   ## how long the last plan's stages took (ms), for profiling
static func plan(gen: WorldGen) -> Dictionary:
	var _t := Time.get_ticks_usec()
	var spots := entrances(gen)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "network"])
	var nodes: Array = []   # {p: Vector3, r: float, tree: int}
	var edges: Array = []   # [a, b]
	var rooms: Array = []   # node indices of chambers
	var roots: Array = []   # node index at each entrance
	_node_grid = {}
	for e in spots.size():
		var s: Vector3 = spots[e]
		# The mouth: just under the slope, so the void breaks the surface and makes an opening.
		# (Wide enough to read as a cave from down the slope, not a dimple in it.)
		var root := _add_node(nodes, Vector3(s.x, gen.get_base_height(s.x, s.z) - 1.0, s.z), MOUTH_R, e, 0.6)
		roots.append(root)
		# Start heading into the hill (uphill, and down a little).
		var g := _base_grad(gen, s.x, s.z)   # points uphill
		var uphill := Vector3(g.x, 0.0, g.y)
		if uphill.length() < 0.01:
			uphill = Vector3(1, 0, 0)
		var start_dir := (uphill.normalized() + Vector3(0, -0.4, 0)).normalized()
		# Frontier items: [node index, direction, radius, steps left, tree]
		var frontier: Array = [[root, start_dir, MOUTH_R, 17 + rng.randi() % 11, e]]
		var stretch := 0       # steps left of a hall or a crawl
		var stretch_r := 0.0
		var stretch_k := 0.8
		while not frontier.is_empty() and nodes.size() < MAX_NODES:
			var pick: int = rng.randi() % frontier.size()
			var item: Array = frontier[pick]
			frontier.remove_at(pick)
			var cur: int = item[0]
			var dir: Vector3 = item[1]
			var rad: float = item[2]
			var steps: int = item[3]
			var tree: int = item[4]
			var chain: Array = [cur]   # this run of tunnel's own nodes, newest last (the last few are kept)
			for _step in steps:
				if nodes.size() >= MAX_NODES:
					break
				dir = dir.rotated(Vector3.UP, rng.randf_range(-0.55, 0.55)).normalized()
				dir.y = clampf(dir.y + rng.randf_range(-0.12, 0.12) - 0.05, -0.5, 0.3)
				dir = dir.normalized()
				var length := rng.randf_range(3.2, 5.0)
				# Mostly tunnels, now and then a chamber (bigger, and a point for chests).
				var is_room := rng.randf() < 0.1
				var nr := clampf(rad + rng.randf_range(-0.5, 0.5), 1.2, 3.6)
				var nk := 0.8
				# Now and then a stretch of a different shape: a wide low hall, or a tight crawl.
				if stretch <= 0 and rng.randf() < 0.08:
					stretch = rng.randi_range(3, 6)
					if rng.randf() < 0.55:
						stretch_r = rng.randf_range(3.2, 4.0)   # hall
						stretch_k = 0.62
					else:
						stretch_r = rng.randf_range(1.4, 1.55)  # narrow squeeze
						stretch_k = 0.7
				if stretch > 0:
					stretch -= 1
					nr = stretch_r
					nk = stretch_k
					is_room = false
				if is_room:
					nr = rng.randf_range(4.5, 7.5)
					nk = 0.55   # chambers have wide floors
					length += nr * 0.75   # and open out at the end of the tunnel, rather than swallowing its last stretch
				var fit: Variant = null
				# A few headings: one that would cut through another tunnel at a different height (a hole in that one's
				# floor) or drop away too steeply is swapped for a turn.
				for attempt in 8:
					var d := dir if attempt == 0 else dir.rotated(Vector3.UP, (0.45 + 0.3 * ((attempt + 1) / 2)) * (1.0 if attempt % 2 == 1 else -1.0))
					fit = _follow(gen, nodes[cur], nodes[cur].p + d * length, nr, nk)
					# (A chamber's wide floor would reach back under the tunnel it comes from: only the node it grows
					# from is let off, so it opens where that tunnel's floor runs level into it.)
					if fit != null and _breaks_floor(nodes, fit, nr, nk, [cur] if is_room else chain):
						fit = null
					if fit != null:
						dir = d
						break
				if fit == null:
					break   # the rock ends here (or it would have to drop away too steeply): this branch stops
				var nxt := _add_node(nodes, fit, nr, tree, nk)
				edges.append([cur, nxt])
				if is_room:
					rooms.append(nxt)
				cur = nxt
				chain.append(nxt)
				if chain.size() > 4:
					chain.pop_front()
				rad = nr
				# Branches: side tunnels that are narrower and shorter.
				if rng.randf() < 0.2 and steps > 3:
					var bd := dir.rotated(Vector3.UP, (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.6, 1.3))
					frontier.append([cur, bd.normalized(), maxf(rad * 0.7, 1.1), rng.randi_range(3, 8), tree])
	timing['tunnels'] = (Time.get_ticks_usec() - _t) / 1000.0
	_t = Time.get_ticks_usec()
	# Corridors between entrances that are close: they make the caves connect.
	for a in roots.size():
		var best := -1
		var best_d := LINK_DISTANCE
		for b in roots.size():
			if b == a:
				continue
			var d: float = nodes[roots[a]].p.distance_to(nodes[roots[b]].p)
			if d < best_d:
				best_d = d
				best = b
		if best >= 0 and rng.randf() < 0.8:
			_corridor(gen, nodes, edges, rng, roots[a], roots[best])
	# Loops: nodes of different tunnels that happen to be close are joined.
	var loops := 0
	for i in nodes.size():
		if loops >= 20 or nodes.size() >= MAX_NODES:
			break
		for j in range(i + 1, nodes.size()):
			if nodes[i].tree == nodes[j].tree:
				continue
			if nodes[i].p.distance_to(nodes[j].p) < 16.0 and rng.randf() < 0.3 and _walkable_link(nodes[i], nodes[j]):
				edges.append([i, j])
				loops += 1
				break
	timing['links'] = (Time.get_ticks_usec() - _t) / 1000.0
	_t = Time.get_ticks_usec()
	# Chests in some chambers, glowing fungus on the floors.
	var chests: Array = []
	var glow: Array = []
	for r: int in rooms:
		var n: Dictionary = nodes[r]
		if chests.size() < 6 and rng.randf() < 0.45:
			chests.append(Vector3(n.p.x + float(n.r) * 0.4, _floor_of(n) + 1.0, n.p.z))
	for i in nodes.size():
		if glow.size() >= 90:
			break
		if rng.randf() < 0.1:
			var n: Dictionary = nodes[i]
			var ang := rng.randf() * TAU
			glow.append(Vector3(n.p.x + cos(ang) * float(n.r) * 0.5, _floor_of(n), n.p.z + sin(ang) * float(n.r) * 0.5))
	timing['chests'] = (Time.get_ticks_usec() - _t) / 1000.0
	_t = Time.get_ticks_usec()
	# How far each node is from daylight: the walk along the tunnels from the nearest mouth.
	var walk := _walk_from(nodes, edges, roots)
	# The rock takes after the land above: icy under the cold, mossy and rooty under the woods, sandstone under the
	# dry lands, purple under the fungal grove.
	for n: Dictionary in nodes:
		var q: Vector3 = n.p
		var weights: Dictionary = gen.biome_weights_at(q.x, q.z, gen.get_base_height(q.x, q.z))
		var lead := WorldGen.Biome.MEADOW
		var lw := -1.0
		for b: int in weights:
			if float(weights[b]) > lw:
				lw = float(weights[b])
				lead = b
		n.theme = theme_for_biome(lead)
	# Crystal caverns deep in, and underground lakes in other chambers.
	var crystal_rooms: Array = []
	var lakes: Array = []      # [water centre, water radius, room node]
	var extra: Array = []      # extra pieces: lake basins and rifts
	for r: int in rooms:
		var n: Dictionary = nodes[r]
		if crystal_rooms.size() < MAX_CRYSTAL_ROOMS and walk[r] > 35.0 and rng.randf() < 0.35:
			n.theme = Rock.CRYSTAL
			crystal_rooms.append(r)
		elif lakes.size() < MAX_LAKES and walk[r] > 12.0 and rng.randf() < 0.3:
			# A shallow bowl in the chamber's floor: under a metre deep at the middle, its sides a gentle slope you
			# can walk out up (a sphere's cap, cut flat at the floor so it doesn't touch the chamber above).
			var f := _floor_of(n)
			# A lake's chamber is a big low hall: wider, its floor kept where it was (so the tunnels still meet it),
			# where the rock above has room for it.
			var big_r := minf(float(n.r) * 1.4, 9.5)
			var big_k := 0.45
			if f + big_k * big_r + big_r + CLEARANCE <= gen.get_base_height(n.p.x, n.p.z):
				n.r = big_r
				n.k = big_k
				n.p = Vector3(n.p.x, f + big_k * big_r, n.p.z)
			var rr := float(n.r) * sqrt(1.0 - float(n.k) * float(n.k)) * 0.8
			var dep := 0.95
			var big := (rr * rr + dep * dep) / (2.0 * dep)
			var cen := Vector3(n.p.x, f - dep + big, n.p.z)
			var water_y := f - 0.12
			var h := cen.y - water_y
			lakes.append([Vector3(n.p.x, water_y, n.p.z), sqrt(maxf(big * big - h * h, 0.0)) + 0.12, r])
			extra.append([cen, cen + Vector3(0, 0.01, 0), big, big, walk[r], walk[r], NO_FLOOR, NO_FLOOR, f + 0.05, n.theme, n.theme])
	# Rifts: tall cracks rising over some tunnels.
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if walk[i] < 8.0 or float(n.r) > 3.0 or rng.randf() > 0.05:
			continue
		var top := gen.get_base_height(n.p.x, n.p.z) - CLEARANCE - 1.0
		var rise := minf(rng.randf_range(3.0, 7.0), top - n.p.y)
		if rise < 2.0:
			continue
		var rr := minf(float(n.r) * 0.55, 1.1)
		var f := _floor_of(n)
		extra.append([n.p, n.p + Vector3(rng.randf_range(-0.8, 0.8), rise, rng.randf_range(-0.8, 0.8)), rr, rr * 0.5, walk[i], walk[i], f, f, NO_CEILING, n.theme, n.theme])
	# Tunnel pieces: each edge is two straight pieces with a slight bend, so they read as dug rock. Each piece also
	# carries the walk from daylight at its two ends.
	var segs: Array = []
	for edge: Array in edges:
		var a: Dictionary = nodes[edge[0]]
		var b: Dictionary = nodes[edge[1]]
		var mid: Vector3 = (a.p + b.p) * 0.5
		mid += Vector3(sin(a.p.x * 0.13 + b.p.z * 0.07), 0.0, cos(a.p.z * 0.11 + b.p.x * 0.05)) * minf(a.p.distance_to(b.p) * 0.12, 1.2)
		var mid_r := (float(a.r) + float(b.r)) * 0.5 * 0.92
		var wa: float = walk[edge[0]]
		var wb: float = walk[edge[1]]
		var wm := minf(wa + a.p.distance_to(mid), wb + b.p.distance_to(mid))
		# Each piece carries its floor at both ends: the tunnel is cut flat there (see _piece_distance), so the floor
		# runs straight from node to node instead of dipping into the bottom of each round chamber.
		var fa := _floor_of(a)
		var fb := _floor_of(b)
		var fm := (fa + fb) * 0.5
		segs.append([a.p, mid, float(a.r), mid_r, wa, wm, fa, fm, NO_CEILING, a.theme, b.theme])
		segs.append([mid, b.p, mid_r, float(b.r), wm, wb, fm, fb, NO_CEILING, a.theme, b.theme])
	segs.append_array(extra)
	timing['themes_lakes_segs'] = (Time.get_ticks_usec() - _t) / 1000.0
	_t = Time.get_ticks_usec()
	var buckets := {}
	for si in segs.size():
		var s: Array = segs[si]
		var reach: float = maxf(float(s[2]), float(s[3])) + 1.0
		var lo: Vector3 = Vector3(minf(s[0].x, s[1].x), 0, minf(s[0].z, s[1].z)) - Vector3(reach, 0, reach)
		var hi: Vector3 = Vector3(maxf(s[0].x, s[1].x), 0, maxf(s[0].z, s[1].z)) + Vector3(reach, 0, reach)
		for bz in range(floori(lo.z / BUCKET), floori(hi.z / BUCKET) + 1):
			for bx in range(floori(lo.x / BUCKET), floori(hi.x / BUCKET) + 1):
				var key := Vector2i(bx, bz)
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(si)
	var out := {"entrances": spots, "roots": roots, "nodes": nodes, "rooms": rooms, "chests": chests,
		"glow": glow, "segs": segs, "buckets": buckets, "lakes": lakes, "crystal_rooms": crystal_rooms}
	# Each piece's bounding ball (centre, radius), for skipping far pieces in the distance lookups.
	var bounds := PackedVector4Array()
	for sg: Array in segs:
		var c: Vector3 = ((sg[0] as Vector3) + (sg[1] as Vector3)) * 0.5
		var rad: float = (sg[0] as Vector3).distance_to(sg[1]) * 0.5 + maxf(float(sg[2]), float(sg[3]))
		bounds.append(Vector4(c.x, c.y, c.z, rad))
	out.bounds = bounds
	timing["buckets"] = (Time.get_ticks_usec() - _t) / 1000.0
	_t = Time.get_ticks_usec()
	_dress(out, gen, walk)
	timing["dress"] = (Time.get_ticks_usec() - _t) / 1000.0
	return out


# --- What's in the caves -------------------------------------------------------------------------
# Worked out after the tunnels, with their own random numbers, so adding things never moves the tunnels, chests or
# glowcaps of a world that already exists.

const MAX_ORES := 110
const MAX_STALAGMITES := 140

## Fill in the plan's contents:
##   ores:        [pos, kind] ore and crystal deposits on the floors, better the deeper (chunk resources: mineable)
##   stalagmites: [pos, scale] (chunk resources: mineable for stone)
##   stalactites: [pos (ceiling), length]
##   pillars:     [floor pos, ceiling y, radius]
##   rubble:      [pos, radius]
##   pools:       [pos (water surface), radius]
##   drips:       ceiling points water drips from (over pools, and here and there)
##   moss:        [pos, normal, colour index] glowing moss patches on walls
##   worms:       [ceiling pos, colour index] glow-worm threads
##   camps:       [floor pos, facing] abandoned miners' camps (each has a loot crate, added to chests)
##   lairs:       floor points in deep chambers where a cave beast lives
##   roosts:      ceiling points where bats hang
static func _dress(plan: Dictionary, gen: WorldGen, walk: PackedFloat32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "cave dressing"])
	var nodes: Array = plan.nodes
	var ores: Array = []
	var stalagmites: Array = []
	var stalactites: Array = []
	var pillars: Array = []
	var rubble: Array = []
	var pools: Array = []
	var drips: Array = []
	var moss: Array = []
	var worms: Array = []
	var camps: Array = []
	var lairs: Array = []
	var roosts: Array = []
	var crystals: Array = []   # [foot, direction it grows, length, colour index]
	var hanging: Array = []    # [ceiling spot, length, kind: 0 leafy vine, 1 pale roots]
	var shrooms: Array = []    # [foot, height, colour index]
	var lake_at := {}
	for lk: Array in plan.lakes:
		lake_at[int(lk[2])] = lk
	var crystal_room := {}
	for r: int in plan.crystal_rooms:
		crystal_room[r] = true
	var is_room := {}
	for r: int in plan.rooms:
		is_room[r] = true
	# Visited in a shuffled order, so the limits on how many there are don't fill up in the first caves.
	var order: Array = range(nodes.size())
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: int = order[k]
		order[k] = order[j]
		order[j] = tmp
	for i: int in order:
		var n: Dictionary = nodes[i]
		var c: Vector3 = n.p
		var r := float(n.r)
		var w: float = walk[i]
		var theme := int(n.theme)
		# Vines hang over the mouths (thickest where the land above is green), and roots and vines from the ceilings
		# of the green caves further in.
		var vine_chance := 0.0
		if w < 6.0:
			vine_chance = 0.9 if theme == Rock.MOSS else (0.45 if theme == Rock.STONE else 0.0)
		elif theme == Rock.MOSS:
			vine_chance = 0.55 if is_room.has(i) else 0.3
		if rng.randf() < vine_chance:
			for k in (4 if w < 6.0 else 2):
				var ce: Variant = ceiling_at(plan, c + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * r)
				if ce != null:
					var under: Variant = floor_at(plan, (ce as Vector3) - Vector3(0, 0.3, 0))
					var room_h: float = (ce as Vector3).y - (under as Vector3).y if under != null else 2.0
					hanging.append([ce, minf(rng.randf_range(0.8, 2.8), room_h * 0.7), 0 if w < 30.0 else 1])
		if w < 6.0:
			continue   # leave the mouths clear
		var depth := gen.get_base_height(c.x, c.z) - c.y
		var room: bool = is_room.has(i)
		# Ore and crystals, hugging the walls on the floor. Deeper rock holds better: the second metal near the
		# top, the third further down, crystals deepest.
		var crystal: bool = crystal_room.has(i)
		var lake: bool = lake_at.has(i)
		var tries := (6 if crystal else 3) if room else 1
		if lake:
			tries = 0
		for t in tries:
			var ang := rng.randf() * TAU
			var roll := rng.randf()
			var kind_roll := rng.randf()
			if ores.size() >= MAX_ORES or roll > (0.55 if room else 0.16):
				continue
			var at: Variant = settle(plan, c + Vector3(cos(ang), 0, sin(ang)) * r * 0.62, 0.4)
			if at == null:
				continue
			var kind := "ore_t2"
			if crystal and kind_roll < 0.6:
				kind = "gem_t4"
			elif depth > 13.0 and kind_roll < 0.12 + clampf((w - 40.0) / 250.0, 0.0, 0.14):
				kind = "gem_t4"
			elif depth > 7.0 and kind_roll < 0.7:
				kind = "ore_t3"
			ores.append([at, kind])
		# Stalagmites and stalactites: clusters in chambers, a few in the tunnels.
		var spikes := rng.randi_range(3, 7) if room else (rng.randi_range(0, 2) if rng.randf() < 0.4 else 0)
		if theme == Rock.ICE:
			spikes += 2 if room else (1 if rng.randf() < 0.5 else 0)   # icicles
		elif theme == Rock.SAND or crystal:
			spikes /= 2
		for t in spikes:
			var ang := rng.randf() * TAU
			var off := Vector3(cos(ang), 0, sin(ang)) * r * rng.randf_range(0.25, 0.8)
			var up := rng.randf() < 0.5
			var len := rng.randf_range(0.5, 1.0) * minf(r * 0.45, 2.6)
			if up and not lake:
				var f: Variant = settle(plan, c + off, 0.35)
				if f != null and stalagmites.size() < MAX_STALAGMITES and rng.randf() < 0.75:
					stalagmites.append([f, len / 1.6])
			else:
				var ce: Variant = ceiling_at(plan, c + off)
				# Not under thin rock (by the mouths): there it couldn't be rooted in the ceiling without poking out
				# of the ground above, and would hang in the air under it.
				if ce != null and gen.get_base_height((ce as Vector3).x, (ce as Vector3).z) - (ce as Vector3).y > 1.3:
					stalactites.append([ce, len])
					if rng.randf() < 0.35:
						drips.append(ce - Vector3(0, len, 0))
		# Pillars where a chamber is tall enough: floor to ceiling, thick in the middle.
		if room and not lake and not crystal and rng.randf() < 0.45:
			var ang := rng.randf() * TAU
			var at := c + Vector3(cos(ang), 0, sin(ang)) * r * 0.45
			var f: Variant = floor_at(plan, at)
			var ce: Variant = ceiling_at(plan, at)
			if f != null and ce != null and (ce as Vector3).y - (f as Vector3).y > 2.5:
				pillars.append([f, (ce as Vector3).y, rng.randf_range(0.45, 0.8)])
		# Rubble along the tunnels (heaps of it in the crumbling sandstone).
		if not lake and rng.randf() < (0.45 if theme == Rock.SAND else 0.22):
			var ang := rng.randf() * TAU
			var f: Variant = floor_at(plan, c + Vector3(cos(ang), 0, sin(ang)) * r * 0.5)
			if f != null:
				rubble.append([f, rng.randf_range(0.5, 1.1)])
		# A still pool in some chambers, with water dripping into it.
		if lake:
			# Water drips into the lake from the ceiling.
			var ce: Variant = ceiling_at(plan, c)
			if ce != null:
				for k in 5:
					drips.append((ce as Vector3) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * float(lake_at[i][1]) * 0.6)
		elif room and not crystal and rng.randf() < 0.3:
			var f: Variant = floor_at(plan, c + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) * r)
			if f != null:
				var pr := r * rng.randf_range(0.26, 0.36)   # inside the dip of the floor, so its edge meets the rock
				pools.append([(f as Vector3) + Vector3(0, 0.07, 0), pr])
				var ce: Variant = ceiling_at(plan, f)
				if ce != null:
					for k in 3:
						drips.append((ce as Vector3) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * pr * 0.5)
		# A crystal cavern: great glowing crystals growing from the floor by the walls, out of the walls, and down from
		# the ceiling, each room its own colour.
		if crystal:
			var hue := rng.randi() % 3
			for k in rng.randi_range(9, 14):
				var ang := rng.randf() * TAU
				var out := Vector3(cos(ang), 0, sin(ang))
				var where := rng.randf()
				if where < 0.45:
					var f: Variant = settle(plan, c + out * r * rng.randf_range(0.45, 0.7), 0.3)
					if f != null:
						crystals.append([f, (Vector3.UP * 1.4 + out * rng.randf_range(0.2, 0.9)).normalized(), rng.randf_range(0.6, 2.2), hue])
				elif where < 0.8:
					var wall: Variant = wall_at(plan, c + Vector3(0, rng.randf_range(-0.2, 0.5) * r, 0), out)
					if wall != null:
						crystals.append([wall, (-out + Vector3(0, rng.randf_range(-0.3, 0.6), 0)).normalized(), rng.randf_range(0.5, 1.5), hue])
				else:
					var ce: Variant = ceiling_at(plan, c + out * r * rng.randf_range(0.0, 0.5))
					if ce != null:
						crystals.append([ce, (Vector3.DOWN * 1.5 + out * rng.randf_range(0.0, 0.6)).normalized(), rng.randf_range(0.5, 1.4), hue])
		# Giant glowing mushrooms in the fungal caves.
		if theme == Rock.FUNGAL and not lake and rng.randf() < (0.8 if room else 0.25):
			for k in (rng.randi_range(2, 4) if room else 1):
				var ang := rng.randf() * TAU
				var f: Variant = settle(plan, c + Vector3(cos(ang), 0, sin(ang)) * r * rng.randf_range(0.3, 0.6), 0.5)
				if f != null:
					var ce: Variant = ceiling_at(plan, f as Vector3 + Vector3(0, 0.3, 0))
					var headroom: float = (ce as Vector3).y - (f as Vector3).y if ce != null else 2.5
					if headroom > 1.6:
						shrooms.append([f, minf(rng.randf_range(1.0, 2.6), headroom - 0.5), rng.randi() % 3])
		# Glowing moss on the walls and glow-worms on the ceilings, more of them the further from daylight.
		var dark := clampf((w - 15.0) / 40.0, 0.0, 1.0)
		if rng.randf() < 0.25 * dark:
			var ang := rng.randf() * TAU
			var wall: Variant = wall_at(plan, c + Vector3(0, rng.randf_range(-0.3, 0.4) * r, 0), Vector3(cos(ang), 0, sin(ang)))
			if wall != null:
				moss.append([wall, -Vector3(cos(ang), 0, sin(ang)), rng.randi() % 3])
		if rng.randf() < (0.4 if room else 0.12) * dark:
			var ce: Variant = ceiling_at(plan, c + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) * r)
			if ce != null:
				worms.append([ce, rng.randi() % 3])
		# Bats roost in the high places of chambers not too far in.
		if room and w < 70.0 and rng.randf() < 0.5:
			var ce: Variant = ceiling_at(plan, c)
			if ce != null:
				roosts.append(ce)
		# A cave beast's lair in deep chambers; an old miners' camp in others.
		if lake or crystal:
			pass
		elif room and w > 45.0 and lairs.size() < 4 and rng.randf() < 0.4:
			var f: Variant = floor_at(plan, c)
			if f != null:
				lairs.append(f)
		elif room and w > 20.0 and camps.size() < 4 and rng.randf() < 0.35:
			var f: Variant = settle(plan, c, 1.2)
			if f != null:
				var turn := rng.randf() * TAU
				var facing: Variant = _camp_facing(plan, f, turn)
				if facing != null:
					camps.append([f, float(facing)])
					var crate: Variant = settle(plan, (f as Vector3) + Basis(Vector3.UP, float(facing)) * CAMP_CHEST, 0.6)
					if crate != null:
						plan.chests.append(crate)   # the camp's crate of supplies
	# The chests and glowcaps placed with the tunnels: down onto the floor, and clear of the walls (they were put
	# by the room's size, and stood in the air or in the rock).
	for i in plan.chests.size():
		var s: Variant = null
		for clear in [0.6, 0.4, 0.2]:
			s = settle(plan, plan.chests[i], clear)
			if s != null:
				break
		if s != null:
			plan.chests[i] = s
	var glow: Array = []
	for g: Vector3 in plan.glow:
		var s: Variant = settle(plan, g + Vector3(0, 0.5, 0), 0.25)
		if s != null:
			glow.append(s)
	plan.glow = glow
	# A camp's ground is clear: no stalagmite, pillar, pool, rubble or deposit among its things.
	var away := func(list: Array, reach: float) -> Array:
		return list.filter(func(it: Variant) -> bool:
			var p: Vector3 = it[0] if it is Array else it
			for camp: Array in camps:
				if Vector2(p.x - camp[0].x, p.z - camp[0].z).length() < reach and absf(p.y - camp[0].y) < 3.0:
					return false
			return true)
	ores = away.call(ores, 3.2)
	stalagmites = away.call(stalagmites, 3.2)
	pillars = away.call(pillars, 3.6)
	rubble = away.call(rubble, 3.2)
	pools = away.call(pools, 4.0)
	shrooms = away.call(shrooms, 3.2)
	# Nothing stands in a lake (the chests and glowcaps placed with the tunnels included).
	var dry := func(list: Array) -> Array:
		return list.filter(func(it: Variant) -> bool:
			var p: Vector3 = it[0] if it is Array else it
			for lk: Array in plan.lakes:
				var wp: Vector3 = lk[0]
				if Vector2(p.x - wp.x, p.z - wp.z).length() < float(lk[1]) + 0.5 and absf(p.y - wp.y) < 2.5:
					return false
			return true)
	ores = dry.call(ores)
	stalagmites = dry.call(stalagmites)
	rubble = dry.call(rubble)
	shrooms = dry.call(shrooms)
	plan.chests = dry.call(plan.chests)
	plan.glow = dry.call(plan.glow)
	plan.ores = ores
	plan.stalagmites = stalagmites
	plan.stalactites = stalactites
	plan.pillars = pillars
	plan.rubble = rubble
	plan.pools = pools
	plan.drips = drips
	plan.moss = moss
	plan.worms = worms
	plan.camps = camps
	plan.lairs = lairs
	plan.roosts = roosts
	plan.crystals = crystals
	plan.hanging = hanging
	plan.shrooms = shrooms


## Where the miners' camp keeps its things, in the camp's own frame (x right, z back): the stacked crates, the
## mine cart, the bedroll, the bones, and its supply chest. (Matches CaveFeatures._build_camp.)
const CAMP_SPOTS := [Vector3(1.6, 0, -0.7), Vector3(1.9, 0, -0.5), Vector3(-1.6, 0, 0.6), Vector3(0.2, 0, 1.3), Vector3(-0.8, 0, 1.5)]
const CAMP_CHEST := Vector3(1.3, 0, 1.0)


## A facing for a camp at `at` where all its things stand on floor near its height and clear of the walls
## (tries eight turns from `turn`), or null if the chamber's too cramped.
static func _camp_facing(plan: Dictionary, at: Vector3, turn: float) -> Variant:
	for k in 8:
		var yaw := turn + TAU * k / 8.0
		var ok := true
		for spot: Vector3 in CAMP_SPOTS + [CAMP_CHEST]:
			var p: Vector3 = at + Basis(Vector3.UP, yaw) * spot
			if void_distance(plan, p + Vector3(0, 0.6, 0)) > -0.2:
				ok = false
				break
			var room := 1.0
			for kk in 4:
				room = minf(room, side_room(plan, p + Vector3(0, 0.6, 0), Vector3(cos(TAU * kk / 4.0), 0, sin(TAU * kk / 4.0)), 0.5))
			if room < 0.5:
				ok = false
				break
			var f: Variant = floor_at(plan, p + Vector3(0, 0.6, 0))
			if f == null or absf((f as Vector3).y - at.y) > 0.4:
				ok = false
				break
		if ok:
			return yaw
	return null


## A spot on the cave floor near p with at least `clear` metres of room to the walls all round (measured level, half
## a metre up, so the floor's own curve doesn't count): pushed away from whichever walls are too close, then
## dropped onto the floor. Null if there's no room.
static func settle(plan: Dictionary, p: Vector3, clear: float) -> Variant:
	var q := p
	for i in 8:
		var probe := q + Vector3(0, 0.5, 0)
		var f: Variant = floor_at(plan, probe if void_distance(plan, probe) < -0.3 else q + Vector3(0, 1.0, 0))
		if f == null:
			return null
		q = f
		var push := Vector3.ZERO
		for k in 8:
			var dir := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
			var dist := side_room(plan, q + Vector3(0, 0.5, 0), dir, clear)
			if dist < clear:
				push -= dir * (clear - dist)
		if push.length() < 0.01:
			return q
		q += push * 0.6
	return null


## How far level from p along dir to a wall, up to `reach` (reach if it's further).
static func side_room(plan: Dictionary, p: Vector3, dir: Vector3, reach: float) -> float:
	var hit: Variant = _march(plan, p, dir, reach + 0.05)
	return reach + 0.05 if hit == null else p.distance_to(hit)


## The cave floor straight below p (p inside a tunnel), or null if p isn't in one.
static func floor_at(plan: Dictionary, p: Vector3) -> Variant:
	var hit: Variant = _march(plan, p, Vector3.DOWN, 12.0)
	return null if hit == null else (hit as Vector3) + Vector3(0, 0.05, 0)


## The cave ceiling straight above p, or null.
static func ceiling_at(plan: Dictionary, p: Vector3) -> Variant:
	var hit: Variant = _march(plan, p, Vector3.UP, 12.0)
	return null if hit == null else (hit as Vector3) - Vector3(0, 0.05, 0)


## Where a horizontal line from p along dir meets the cave wall, or null.
static func wall_at(plan: Dictionary, p: Vector3, dir: Vector3) -> Variant:
	var hit: Variant = _march(plan, p, dir, 10.0)
	return null if hit == null else (hit as Vector3) - dir * 0.04


## From p (inside a tunnel) along dir to the rock. Sphere tracing: the distance to the nearest wall is never more than
## the true distance inside the caves, so each step can safely jump that far; then halving to pin the wall down.
const SLIVER := 1.05   ## rock thinner than this (the ground mesh's grid) is smoothed away in the built caves

static func _march(plan: Dictionary, p: Vector3, dir: Vector3, reach: float) -> Variant:
	var d := void_distance(plan, p)
	if d > -0.3:
		return null
	var inside := 0.0
	var t := 0.0
	while t < reach:
		t = minf(t + clampf(-d * 0.6, 0.08, 1.5), reach)   # cautious: a tapering piece's distance is only near-exact
		d = void_distance(plan, p + dir * t)
		if d >= 0.0:
			var lo := inside
			var hi := t
			while hi - lo > 0.012:
				var mid := (lo + hi) * 0.5
				if void_distance(plan, p + dir * mid) >= 0.0:
					hi = mid
				else:
					lo = mid
			# A sliver of rock thinner than the ground mesh can show (it's smoothed away there) isn't a wall: go on.
			var beyond := void_distance(plan, p + dir * (hi + SLIVER))
			if beyond < 0.0 and hi + SLIVER < reach:
				t = hi + SLIVER
				d = beyond
				inside = t
				continue
			return p + dir * hi
		inside = t
	return null


## The shortest walk along the tunnels from any mouth to each node (Dijkstra; the network is small).
static func _walk_from(nodes: Array, edges: Array, roots: Array) -> PackedFloat32Array:
	var walk := PackedFloat32Array()
	walk.resize(nodes.size())
	walk.fill(INF)
	var links: Array = []
	links.resize(nodes.size())
	for i in nodes.size():
		links[i] = []
	for e: Array in edges:
		var len: float = nodes[e[0]].p.distance_to(nodes[e[1]].p)
		links[e[0]].append([e[1], len])
		links[e[1]].append([e[0], len])
	var open: Array = []
	for r: int in roots:
		walk[r] = 0.0
		open.append(r)
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if walk[open[i]] < walk[open[bi]]:
				bi = i
		var n: int = open[bi]
		open.remove_at(bi)
		if done.has(n):
			continue
		done[n] = true
		for l: Array in links[n]:
			var d: float = walk[n] + float(l[1])
			if d < walk[l[0]]:
				walk[l[0]] = d
				open.append(l[0])
	for i in walk.size():
		if walk[i] == INF:
			walk[i] = 999.0   # cut off from every mouth: dark
	return walk


static func _base_grad(gen: WorldGen, x: float, z: float) -> Vector2:
	return Vector2((gen.get_base_height(x + 1.0, z) - gen.get_base_height(x - 1.0, z)) * 0.5,
		(gen.get_base_height(x, z + 1.0) - gen.get_base_height(x, z - 1.0)) * 0.5)


## A point for a tunnel of radius r: pushed under the local ground by at least CLEARANCE, and not
## deeper than MAX_DEPTH. Null if there's no rock deep enough here (the tunnel stops).
static func _fit(gen: WorldGen, p: Vector3, r: float) -> Variant:
	var top := gen.get_base_height(p.x, p.z) - r - CLEARANCE
	# Tunnels stay dry: the floor (y - r) is never under the sea, and the rock is never too deep.
	var low := maxf(top - MAX_DEPTH, Game.SEA_LEVEL + r + 1.0)
	if top < low:
		return null
	return Vector3(p.x, clampf(p.y, low, top), p.z)


## How steeply a cave floor may fall or rise from one node to the next (rise over run): gentle enough to walk
## back up. (Floors go from node to node in a straight line, so keeping each step to this keeps the whole floor.)
const FLOOR_K := 0.8      ## a cave's floor is this share of its radius below its middle (cut flat there)
const FLOOR_DOWN := 0.5
const FLOOR_UP := 0.45


## A node placed after `from`, near p, with radius r: its floor (y - r) no steeper from `from`'s floor than the
## cave allows, and fitted under the ground like any node. Null if no such place fits (the branch ends there).
static func _follow(gen: WorldGen, from: Dictionary, p: Vector3, r: float, k := 0.8) -> Variant:
	var fit: Variant = _fit(gen, p, r)
	if fit == null:
		return null
	var q: Vector3 = fit
	var run := Vector2(q.x - from.p.x, q.z - from.p.z).length()
	var prev_floor: float = _floor_of(from)
	var floor_y := clampf(q.y - k * r, prev_floor - FLOOR_DOWN * run, prev_floor + FLOOR_UP * run)
	var top := gen.get_base_height(q.x, q.z) - r - CLEARANCE
	var low := maxf(top - MAX_DEPTH, Game.SEA_LEVEL + r + 1.0)
	var y := floor_y + k * r
	if y > top + 0.01 or y < low - 0.01:
		return null   # the ground won't hold a floor that follows on gently here
	return Vector3(q.x, y, q.z)


## Whether two nodes' floors are close enough in height, for the distance between them, to join with a tunnel
## you can walk both ways.
static func _walkable_link(a: Dictionary, b: Dictionary) -> bool:
	var run := Vector2(a.p.x - b.p.x, a.p.z - b.p.z).length()
	var rise := absf(_floor_of(a) - _floor_of(b))
	return rise <= minf(FLOOR_DOWN, FLOOR_UP) * run


## A node's floor height: its middle less its share k of the radius (see FLOOR_K).
static func _floor_of(n: Dictionary) -> float:
	return float(n.p.y) - float(n.get("k", FLOOR_K)) * float(n.r)


static func _add_node(nodes: Array, p: Vector3, r: float, tree: int, k := FLOOR_K) -> int:
	nodes.append({"p": p, "r": r, "tree": tree, "k": k, "theme": Rock.STONE})
	var key := Vector2i(floori(p.x / NODE_CELL), floori(p.z / NODE_CELL))
	var grid: Dictionary = _node_grid
	if not grid.has(key):
		grid[key] = []
	grid[key].append(nodes.size() - 1)
	return nodes.size() - 1


const NODE_CELL := 16.0
## How much more than a gentle slope's rise two overlapping tunnels' floors may differ by: little more than a step,
## so where tunnels cross or run side by side there's no ledge or pit you'd have to jump (or couldn't climb out of).
const BREAK_SLACK := 0.5
static var _node_grid := {}   ## node indices by 16 m cell, for the plan being made


## Whether a node at p (radius r) would overlap another tunnel whose floor is at a height you couldn't walk between
## over that distance: one would open a pit or a ledge in the other's floor.
static func _breaks_floor(nodes: Array, p: Vector3, r: float, k := FLOOR_K, chain: Array = []) -> bool:
	var f := p.y - k * r
	var cx := floori(p.x / NODE_CELL)
	var cz := floori(p.z / NODE_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i: int in _node_grid.get(Vector2i(cx + dx, cz + dz), []):
				var n: Dictionary = nodes[i]
				var q: Vector3 = n.p
				var rn := float(n.r)
				var run := Vector2(q.x - p.x, q.z - p.z).length()
				if run > r + rn + 0.5:
					continue
				# One above the other with rock between: fine.
				var fn := _floor_of(n)
				if q.y + rn < f - 0.6 or p.y + r < fn - 0.6:
					continue
				# How far you'd walk between the two floors: from the edge of one's flat floor to the other's (a big
				# chamber's floor reaches out most of its width, so a tunnel at its side is close to it).
				var kn := float(n.get("k", FLOOR_K))
				var walk := maxf(run - rn * sqrt(1.0 - kn * kn) - r * sqrt(1.0 - k * k), 0.0)
				if chain.has(i):
					walk = run   # the tunnel it's growing along: its floors follow on gently from these (see _follow)
				if absf(fn - f) > 0.5 * walk + BREAK_SLACK:
					return true
	return false


## A long winding corridor from node a to node b, with bends so it reads as dug rock.
static func _corridor(gen: WorldGen, nodes: Array, edges: Array, rng: RandomNumberGenerator, a: int, b: int) -> void:
	var pa: Vector3 = nodes[a].p
	var pb: Vector3 = nodes[b].p
	var n := maxi(3, int(pa.distance_to(pb) / 4.5))
	var prev := a
	for i in range(1, n):
		if nodes.size() >= MAX_NODES:
			break
		var t := float(i) / n
		var p := pa.lerp(pb, t) + Vector3(rng.randf_range(-3, 3), rng.randf_range(-1.5, 1.5), rng.randf_range(-3, 3))
		var r := rng.randf_range(1.5, 2.6)
		var fit: Variant = _follow(gen, nodes[prev], p, r)
		if fit == null or _breaks_floor(nodes, fit, r, FLOOR_K, [prev, a]):
			continue
		var nxt := _add_node(nodes, fit, r, nodes[a].tree)
		edges.append([prev, nxt])
		prev = nxt
	if _walkable_link(nodes[prev], nodes[b]):
		edges.append([prev, b])


## The tunnel pieces that could reach the chunk at `origin` (size metres square), with a margin.
static func segments_near(plan: Dictionary, origin: Vector3, size: float) -> Array:
	var out: Array = []
	if plan.is_empty():
		return out
	var seen := {}
	var lo := Vector2i(floori((origin.x - 8.0) / BUCKET), floori((origin.z - 8.0) / BUCKET))
	var hi := Vector2i(floori((origin.x + size + 8.0) / BUCKET), floori((origin.z + size + 8.0) / BUCKET))
	for bz in range(lo.y, hi.y + 1):
		for bx in range(lo.x, hi.x + 1):
			var key := Vector2i(bx, bz)
			if not plan.buckets.has(key):
				continue
			for si: int in plan.buckets[key]:
				if not seen.has(si):
					seen[si] = true
					out.append(plan.segs[si])
	return out


## Signed distance from p to the nearest cave wall: negative inside a tunnel, positive in rock.
## 99 when no cave is anywhere near p.
static func void_distance(plan: Dictionary, p: Vector3) -> float:
	if plan.is_empty():
		return 99.0
	var key := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
	if not plan.buckets.has(key):
		return 99.0
	var best := 99.0
	var bounds: PackedVector4Array = plan.bounds
	for si: int in plan.buckets[key]:
		# A piece whose bounding ball is further than the nearest wall found so far can't be nearer (most pieces in a
		# cell are some way off: this skips their sums).
		var bb := bounds[si]
		if Vector3(bb.x - p.x, bb.y - p.y, bb.z - p.z).length() - bb.w >= best:
			continue
		best = minf(best, _piece_distance(plan.segs[si], p))
	return best


## How much open sky a spot sees: 1 outside, falling off along the tunnels with the walk from the nearest mouth,
## down to a little at the deep end. It darkens the sky's light on cave walls and on things in caves (ambient
## occlusion: torches, fires and glowing fungus aren't touched), so the caves are dark by their own shape and the
## world outside never changes.
const DAYLIGHT_REACH := Vector2(4.0, 26.0)   ## metres walked in from a mouth where the light starts and stops falling
const DEEP_SKY := 0.08                        ## what's left at the far end (the eye adjusts to a little)


static func sky_seen(plan: Dictionary, p: Vector3) -> float:
	if plan.is_empty():
		return 1.0
	var key := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
	if not plan.buckets.has(key):
		return 1.0
	var best := 99.0
	var best_walk := 0.0
	var bounds: PackedVector4Array = plan.bounds
	for si: int in plan.buckets[key]:
		var bb := bounds[si]
		if Vector3(bb.x - p.x, bb.y - p.y, bb.z - p.z).length() - bb.w >= best:
			continue
		var s: Array = plan.segs[si]
		var a: Vector3 = s[0]
		var ab: Vector3 = s[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := _piece_distance(s, p)
		if d < best:
			best = d
			best_walk = lerpf(float(s[4]), float(s[5]), t)
	# Only the tunnels and what's in them: rock walls are within a step of the void, ground overhead is further.
	var inside := 1.0 - smoothstep(0.6, 1.4, best)
	var lit := lerpf(DEEP_SKY, 1.0, 1.0 - smoothstep(DAYLIGHT_REACH.x, DAYLIGHT_REACH.y, best_walk))
	return lerpf(1.0, lit, inside)


## sky_seen and void_distance together, from one pass over the pieces: Vector2(sky seen, distance to the wall).
static func sky_and_distance(plan: Dictionary, p: Vector3) -> Vector2:
	if plan.is_empty():
		return Vector2(1.0, 99.0)
	var key := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
	if not plan.buckets.has(key):
		return Vector2(1.0, 99.0)
	var best := 99.0
	var best_walk := 0.0
	var bounds: PackedVector4Array = plan.bounds
	for si: int in plan.buckets[key]:
		var bb := bounds[si]
		if Vector3(bb.x - p.x, bb.y - p.y, bb.z - p.z).length() - bb.w >= best:
			continue
		var s: Array = plan.segs[si]
		var a: Vector3 = s[0]
		var ab: Vector3 = s[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := _piece_distance(s, p)
		if d < best:
			best = d
			best_walk = lerpf(float(s[4]), float(s[5]), t)
	var inside := 1.0 - smoothstep(0.6, 1.4, best)
	var lit := lerpf(DEEP_SKY, 1.0, 1.0 - smoothstep(DAYLIGHT_REACH.x, DAYLIGHT_REACH.y, best_walk))
	return Vector2(lerpf(1.0, lit, inside), best)


static func _piece_distance(s: Array, p: Vector3) -> float:
	var a: Vector3 = s[0]
	var ab: Vector3 = s[1] - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var d := p.distance_to(a + ab * t) - lerpf(float(s[2]), float(s[3]), t)
	# The flat floor: no void below it (and, for a lake's basin, none above its flat top).
	return maxf(maxf(d, lerpf(float(s[6]), float(s[7]), t) - p.y), p.y - float(s[8]))
