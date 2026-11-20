class_name Caves
extends RefCounted
## Caves cut into the rock under the island. Entrances are openings in the hillsides; from each one
## tunnels wind inward and downward, with chambers, branches, dead ends and loops, and close
## entrances are joined by long corridors. The plan is made from the BASE terrain (before any building)
## so every machine plans the same caves. VoxelTerrain subtracts the planned voids from the ground.
##
## A plan is a Dictionary: {entrances, roots, nodes, rooms, chests, glow, segs, buckets}.
## segs are [a: Vector3, b: Vector3, ra: float, rb: float] tunnel pieces; buckets map a 16 m grid
## cell to the segs that reach it, for quick lookups. A plan is read-only once made, so worker
## threads can use it safely.

const MIN_SPACING := 120.0   ## entrances are kept apart
const MAX_ENTRANCES := 12
const MAX_NODES := 900
const LINK_DISTANCE := 260.0
const MAX_DEPTH := 24.0      ## tunnels never go deeper than this under the ground above
const CLEARANCE := 1.5       ## metres of rock left over the top of a tunnel
const BUCKET := 16.0


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
static func plan(gen: WorldGen) -> Dictionary:
	var spots := entrances(gen)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "network"])
	var nodes: Array = []   # {p: Vector3, r: float, tree: int}
	var edges: Array = []   # [a, b]
	var rooms: Array = []   # node indices of chambers
	var roots: Array = []   # node index at each entrance
	for e in spots.size():
		var s: Vector3 = spots[e]
		# The mouth: just under the slope, so the void breaks the surface and makes an opening.
		var root := _add_node(nodes, Vector3(s.x, gen.get_base_height(s.x, s.z) - 0.8, s.z), 2.4, e)
		roots.append(root)
		# Start heading into the hill (uphill, and down a little).
		var g := _base_grad(gen, s.x, s.z)   # points uphill
		var uphill := Vector3(g.x, 0.0, g.y)
		if uphill.length() < 0.01:
			uphill = Vector3(1, 0, 0)
		var start_dir := (uphill.normalized() + Vector3(0, -0.4, 0)).normalized()
		# Frontier items: [node index, direction, radius, steps left, tree]
		var frontier: Array = [[root, start_dir, 2.4, 14 + rng.randi() % 10, e]]
		while not frontier.is_empty() and nodes.size() < MAX_NODES:
			var pick: int = rng.randi() % frontier.size()
			var item: Array = frontier[pick]
			frontier.remove_at(pick)
			var cur: int = item[0]
			var dir: Vector3 = item[1]
			var rad: float = item[2]
			var steps: int = item[3]
			var tree: int = item[4]
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
				if is_room:
					nr = rng.randf_range(4.5, 7.5)
				var fit: Variant = _fit(gen, nodes[cur].p + dir * length, nr)
				if fit == null:
					break   # the rock ends here: this branch stops
				var nxt := _add_node(nodes, fit, nr, tree)
				edges.append([cur, nxt])
				if is_room:
					rooms.append(nxt)
				cur = nxt
				rad = nr
				# Branches: side tunnels that are narrower and shorter.
				if rng.randf() < 0.16 and steps > 3:
					var bd := dir.rotated(Vector3.UP, (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.6, 1.3))
					frontier.append([cur, bd.normalized(), maxf(rad * 0.7, 1.1), rng.randi_range(3, 8), tree])
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
			if nodes[i].p.distance_to(nodes[j].p) < 16.0 and rng.randf() < 0.3:
				edges.append([i, j])
				loops += 1
				break
	# Chests in some chambers, glowing fungus on the floors.
	var chests: Array = []
	var glow: Array = []
	for r: int in rooms:
		var n: Dictionary = nodes[r]
		if chests.size() < 6 and rng.randf() < 0.45:
			chests.append(n.p + Vector3(float(n.r) * 0.4, -float(n.r) + 1.0, 0.0))
	for i in nodes.size():
		if glow.size() >= 90:
			break
		if rng.randf() < 0.1:
			var n: Dictionary = nodes[i]
			var ang := rng.randf() * TAU
			glow.append(n.p + Vector3(cos(ang) * float(n.r) * 0.5, -float(n.r) * 0.8, sin(ang) * float(n.r) * 0.5))
	# How far each node is from daylight: the walk along the tunnels from the nearest mouth.
	var walk := _walk_from(nodes, edges, roots)
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
		segs.append([a.p, mid, float(a.r), mid_r, wa, wm])
		segs.append([mid, b.p, mid_r, float(b.r), wm, wb])
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
		"glow": glow, "segs": segs, "buckets": buckets}
	_dress(out, gen, walk)
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
		if w < 6.0:
			continue   # leave the mouths clear
		var depth := gen.get_base_height(c.x, c.z) - c.y
		var room: bool = is_room.has(i)
		# Ore and crystals, hugging the walls on the floor. Deeper rock holds better: the second metal near the
		# top, the third further down, crystals deepest.
		var tries := 3 if room else 1
		for t in tries:
			var ang := rng.randf() * TAU
			var roll := rng.randf()
			var kind_roll := rng.randf()
			if ores.size() >= MAX_ORES or roll > (0.55 if room else 0.16):
				continue
			var at: Variant = floor_at(plan, c + Vector3(cos(ang), 0, sin(ang)) * r * 0.62)
			if at == null:
				continue
			var kind := "ore_t2"
			if depth > 13.0 and kind_roll < 0.12 + clampf((w - 40.0) / 250.0, 0.0, 0.14):
				kind = "gem_t4"
			elif depth > 7.0 and kind_roll < 0.7:
				kind = "ore_t3"
			ores.append([at, kind])
		# Stalagmites and stalactites: clusters in chambers, a few in the tunnels.
		var spikes := rng.randi_range(3, 7) if room else (rng.randi_range(0, 2) if rng.randf() < 0.4 else 0)
		for t in spikes:
			var ang := rng.randf() * TAU
			var off := Vector3(cos(ang), 0, sin(ang)) * r * rng.randf_range(0.25, 0.8)
			var up := rng.randf() < 0.5
			var len := rng.randf_range(0.5, 1.0) * minf(r * 0.45, 2.6)
			if up:
				var f: Variant = floor_at(plan, c + off)
				if f != null and stalagmites.size() < MAX_STALAGMITES and rng.randf() < 0.75:
					stalagmites.append([f, len / 1.6])
			else:
				var ce: Variant = ceiling_at(plan, c + off)
				if ce != null:
					stalactites.append([ce, len])
					if rng.randf() < 0.35:
						drips.append(ce - Vector3(0, len, 0))
		# Pillars where a chamber is tall enough: floor to ceiling, thick in the middle.
		if room and rng.randf() < 0.45:
			var ang := rng.randf() * TAU
			var at := c + Vector3(cos(ang), 0, sin(ang)) * r * 0.45
			var f: Variant = floor_at(plan, at)
			var ce: Variant = ceiling_at(plan, at)
			if f != null and ce != null and (ce as Vector3).y - (f as Vector3).y > 2.5:
				pillars.append([f, (ce as Vector3).y, rng.randf_range(0.45, 0.8)])
		# Rubble along the tunnels.
		if rng.randf() < 0.22:
			var ang := rng.randf() * TAU
			var f: Variant = floor_at(plan, c + Vector3(cos(ang), 0, sin(ang)) * r * 0.5)
			if f != null:
				rubble.append([f, rng.randf_range(0.5, 1.1)])
		# A still pool in some chambers, with water dripping into it.
		if room and rng.randf() < 0.3:
			var f: Variant = floor_at(plan, c + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) * r)
			if f != null:
				var pr := r * rng.randf_range(0.26, 0.36)   # inside the dip of the floor, so its edge meets the rock
				pools.append([(f as Vector3) + Vector3(0, 0.07, 0), pr])
				var ce: Variant = ceiling_at(plan, f)
				if ce != null:
					for k in 3:
						drips.append((ce as Vector3) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * pr * 0.5)
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
		if room and w > 45.0 and lairs.size() < 4 and rng.randf() < 0.4:
			var f: Variant = floor_at(plan, c)
			if f != null:
				lairs.append(f)
		elif room and w > 20.0 and camps.size() < 4 and rng.randf() < 0.35:
			var f: Variant = floor_at(plan, c + Vector3(r * 0.2, 0, -r * 0.15))
			if f != null:
				camps.append([f, rng.randf() * TAU])
				plan.chests.append((f as Vector3) + Vector3(cos(0.6), 0, sin(0.6)) * 1.6)   # the camp's crate of supplies
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


## From p (inside a tunnel) along dir to the rock: coarse steps, then halving (a handful of distance lookups).
static func _march(plan: Dictionary, p: Vector3, dir: Vector3, reach: float) -> Variant:
	if void_distance(plan, p) > -0.3:
		return null
	var inside := 0.0
	var t := 0.0
	while t < reach:
		t = minf(t + 0.45, reach)
		if void_distance(plan, p + dir * t) >= 0.0:
			var lo := inside
			var hi := t
			for k in 5:
				var mid := (lo + hi) * 0.5
				if void_distance(plan, p + dir * mid) >= 0.0:
					hi = mid
				else:
					lo = mid
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


static func _add_node(nodes: Array, p: Vector3, r: float, tree: int) -> int:
	nodes.append({"p": p, "r": r, "tree": tree})
	return nodes.size() - 1


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
		var fit: Variant = _fit(gen, p, r)
		if fit == null:
			continue
		var nxt := _add_node(nodes, fit, r, nodes[a].tree)
		edges.append([prev, nxt])
		prev = nxt
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
	for si: int in plan.buckets[key]:
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
	for si: int in plan.buckets[key]:
		var s: Array = plan.segs[si]
		var a: Vector3 = s[0]
		var ab: Vector3 = s[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) - lerpf(float(s[2]), float(s[3]), t)
		if d < best:
			best = d
			best_walk = lerpf(float(s[4]), float(s[5]), t)
	# Only the tunnels and what's in them: rock walls are within a step of the void, ground overhead is further.
	var inside := 1.0 - smoothstep(0.6, 1.4, best)
	var lit := lerpf(DEEP_SKY, 1.0, 1.0 - smoothstep(DAYLIGHT_REACH.x, DAYLIGHT_REACH.y, best_walk))
	return lerpf(1.0, lit, inside)


static func _piece_distance(s: Array, p: Vector3) -> float:
	var a: Vector3 = s[0]
	var ab: Vector3 = s[1] - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t) - lerpf(float(s[2]), float(s[3]), t)
