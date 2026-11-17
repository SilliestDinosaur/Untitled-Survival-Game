class_name Caves
extends RefCounted
## Caves: hillside entrances on the island lead down into a separate underground area (far below
## the surface, so it never overlaps the world). Each entrance has its own cave, planned from the
## world seed: a winding tunnel with a few rooms, glowing fungus, bats, and a supply chest.

const CAVE_Y := -400.0      ## where the underground lives
const MIN_SPACING := 120.0  ## entrances are kept apart
const MAX_ENTRANCES := 12


## Hillside spots where an entrance can open: steep faces, between the lowlands and the peaks.
static func entrances(gen: WorldGen) -> Array:
	var cand: Array = []
	var size := Game.WORLD_SIZE
	var z := 60.0
	while z < size - 60.0:
		var x := 60.0
		while x < size - 60.0:
			var h := gen.get_height(x, z)
			if h > 10.0 and h < 55.0:
				var n := gen.get_normal(x, z)
				if n.y < 0.8:
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


## The underground network, planned from the world seed. Every entrance drops into it at its own
## spot; tunnels grow from there with branches, dead ends, chambers of varying size, and loops.
## Entrances that are close together are joined by long winding corridors, so caves link up.
## Nodes are in world coordinates (y around CAVE_Y). Cached per world seed.
static var _net_cache := {}
const MAX_NODES := 900
const LINK_DISTANCE := 260.0


static func network(entrance_points: Array) -> Dictionary:
	var key := "%d_%d" % [Game.world_seed, entrance_points.size()]
	if _net_cache.has(key):
		return _net_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "network"])
	var nodes: Array = []   # {p: Vector3, r: float, tree: int}
	var edges: Array = []   # [a, b]
	var rooms: Array = []   # node indices of chambers
	var roots: Array = []   # node index at each entrance
	# Each entrance starts a tree of tunnels.
	for e in entrance_points.size():
		var s: Vector3 = entrance_points[e]
		var root := _add_node(nodes, Vector3(s.x, Caves.CAVE_Y, s.z), 2.4, e)
		roots.append(root)
		# Frontier items: [node index, direction, radius, steps left, tree]
		var frontier: Array = [[root, Vector3(rng.randf_range(-1, 1), -0.25, rng.randf_range(-1, 1)).normalized(), 2.4, 14 + rng.randi() % 10, e]]
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
				dir.y = clampf(dir.y + rng.randf_range(-0.12, 0.12) - (nodes[cur].p.y - Caves.CAVE_Y) * 0.04, -0.4, 0.3)
				dir = dir.normalized()
				var length := rng.randf_range(3.2, 5.0)
				# Mostly tunnels, now and then a chamber (bigger, and a point to put chests and bats).
				var is_room := rng.randf() < 0.1
				var nr := clampf(rad + rng.randf_range(-0.5, 0.5), 1.2, 3.6)
				if is_room:
					nr = rng.randf_range(4.5, 7.5)
				var p: Vector3 = nodes[cur].p + dir * length
				p.y = clampf(p.y, Caves.CAVE_Y - 26.0, Caves.CAVE_Y + 10.0)
				var nxt := _add_node(nodes, p, nr, tree)
				edges.append([cur, nxt])
				if is_room:
					rooms.append(nxt)
				cur = nxt
				rad = nr
				# Branches: side tunnels that are narrower and shorter.
				if rng.randf() < 0.16 and steps > 3:
					var bd := dir.rotated(Vector3.UP, (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.6, 1.3))
					frontier.append([cur, bd.normalized(), maxf(rad * 0.7, 1.1), rng.randi_range(3, 8), tree])
			# A tunnel can end in a dead end (fine), or carry on as its own branch.
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
			_corridor(nodes, edges, rng, roots[a], roots[best])
	# Loops: a few nodes of different tunnels that happen to be close are joined.
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
	# Chests in some chambers, glowing fungus on the floors, bats up in the chambers.
	var chests: Array = []
	var glow: Array = []
	var bats: Array = []
	for r: int in rooms:
		if chests.size() < 6 and rng.randf() < 0.45:
			chests.append(nodes[r].p + Vector3(float(nodes[r].r) * 0.4, -float(nodes[r].r) + 1.0, 0.0))
		if bats.size() < 16:
			for k in 2:
				var ang := rng.randf() * TAU
				bats.append(nodes[r].p + Vector3(cos(ang) * 2.5, float(nodes[r].r) * 0.4, sin(ang) * 2.5))
	for i in nodes.size():
		if glow.size() >= 90:
			break
		if rng.randf() < 0.1:
			var n: Dictionary = nodes[i]
			var ang := rng.randf() * TAU
			glow.append(n.p + Vector3(cos(ang) * float(n.r) * 0.5, -float(n.r) * 0.8, sin(ang) * float(n.r) * 0.5))
	var result := {"nodes": nodes, "edges": edges, "rooms": rooms, "roots": roots, "chests": chests, "glow": glow, "bats": bats}
	_net_cache[key] = result
	return result


static func _add_node(nodes: Array, p: Vector3, r: float, tree: int) -> int:
	nodes.append({"p": p, "r": r, "tree": tree})
	return nodes.size() - 1


## A long winding corridor from node a to node b, with a few bends so it reads as dug rock.
static func _corridor(nodes: Array, edges: Array, rng: RandomNumberGenerator, a: int, b: int) -> void:
	var pa: Vector3 = nodes[a].p
	var pb: Vector3 = nodes[b].p
	var n := maxi(3, int(pa.distance_to(pb) / 4.5))
	var prev := a
	for i in range(1, n):
		if nodes.size() >= MAX_NODES:
			break
		var t := float(i) / n
		var p := pa.lerp(pb, t)
		p += Vector3(rng.randf_range(-3, 3), rng.randf_range(-1.5, 1.5), rng.randf_range(-3, 3))
		p.y = clampf(p.y, Caves.CAVE_Y - 26.0, Caves.CAVE_Y + 10.0)
		var nxt := _add_node(nodes, p, rng.randf_range(1.5, 2.6), nodes[a].tree)
		edges.append([prev, nxt])
		prev = nxt
	edges.append([prev, b])


## The visible entrance on the hillside: a rock arch around a dark opening, facing downhill.
static func build_mouth(index: int, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "CaveMouth%d" % index
	root.position = at
	var gen: WorldGen = Game.world_gen
	var g := Vector2(gen.get_height(at.x + 1.0, at.z) - gen.get_height(at.x - 1.0, at.z), gen.get_height(at.x, at.z + 1.0) - gen.get_height(at.x, at.z - 1.0))
	var down := Vector3(-g.x, 0.0, -g.y)
	if down.length() < 0.01:
		down = Vector3(1, 0, 0)
	root.basis = Basis.looking_at(down.normalized(), Vector3.UP)   # works before the node is in the tree
	var rock := Game.palette.rock.darkened(0.1)
	var kit := MeshKit.new(hash([Game.world_seed, index, "mouth"]))
	# The arch: a thick rock ring, flattened so it sits into the slope.
	var ring := PackedVector2Array()
	for i in 24:
		var a := PI * i / 23.0
		ring.append(Vector2(cos(a) * 2.2, sin(a) * 2.6))
	ring.append(Vector2(-2.2, -0.6))   # down the left side, then across the base (a simple outline)
	ring.append(Vector2(2.2, -0.6))
	var inner := PackedVector2Array()
	for i in 24:
		var a := PI * (23 - i) / 23.0
		inner.append(Vector2(cos(a) * 1.25, sin(a) * 1.6 - 0.1))
	kit.sculpt(ring, Transform3D(), func(_p: Vector2) -> float: return 1.2, func(p: Vector2, _t: float) -> Color: return rock.lightened(sin(p.x * 4.0) * 0.04), 2, 0.1)
	var mi := MeshInstance3D.new()
	mi.name = "Arch"
	mi.mesh = kit.commit(ArtStyle.painted({"brush_strength": 0.3, "rim_amount": 0.2}))
	root.add_child(mi)
	# The dark opening, set just inside the arch.
	var hole := MeshKit.new(3)
	hole.sculpt(inner, Transform3D(Basis(), Vector3(0, 0, 0.5)), func(_p: Vector2) -> float: return 0.05, func(_p: Vector2, _t: float) -> Color: return Color(0.05, 0.04, 0.05), 0, 0.1)
	var hi := MeshInstance3D.new()
	hi.name = "Opening"
	hi.mesh = hole.commit(ArtStyle.painted({"brush_strength": 0.05, "rim_amount": 0.0}))
	root.add_child(hi)
	# A collider for the crosshair (you walk up to the opening and press interact).
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta("cave_mouth", index)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.4, 4.0, 2.0)
	cs.shape = box
	cs.position = Vector3(0, 1.4, 0)
	body.add_child(cs)
	root.add_child(body)
	return root
