class_name Caves
extends RefCounted
## Caves: hillside entrances on the island lead down into a separate underground area (far below
## the surface, so it never overlaps the world). Each entrance has its own cave, planned from the
## world seed: a winding tunnel with a few rooms, glowing fungus, bats, and a supply chest.

const CAVE_Y := -400.0      ## where the underground lives
const MIN_SPACING := 170.0  ## entrances are kept apart
const MAX_ENTRANCES := 4


## Hillside spots where an entrance can open: steep faces, between the lowlands and the peaks.
static func entrances(gen: WorldGen) -> Array:
	var cand: Array = []
	var size := Game.WORLD_SIZE
	var z := 60.0
	while z < size - 60.0:
		var x := 60.0
		while x < size - 60.0:
			var h := gen.get_height(x, z)
			if h > 14.0 and h < 42.0:
				var n := gen.get_normal(x, z)
				if n.y < 0.72:
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


## The plan for cave number `index` (local coordinates: the entrance is at the origin, the tunnel
## runs off into the hill). Deterministic from the seed, so every player sees the same cave.
static func plan(index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "cave", index])
	var pts: Array[Vector3] = []
	var rad: Array = []
	var p := Vector3.ZERO
	var dir := Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var n := 17
	for i in n:
		pts.append(p)
		rad.append(2.1 + rng.randf() * 0.7)
		dir = dir.rotated(Vector3.UP, rng.randf_range(-0.45, 0.45)).normalized()
		dir.y = clampf(-0.12 + sin(float(i) * 0.5) * 0.08, -0.25, 0.05)
		dir = dir.normalized()
		p += dir * rng.randf_range(3.2, 4.4)
	# Three rooms, spaced along the tunnel.
	var rooms := [5, 10, 15]
	for r: int in rooms:
		rad[r] = 5.0 + rng.randf() * 1.0
	var glow: Array[Vector3] = []
	for i in 16:
		var k: int = rooms[rng.randi() % rooms.size()] if rng.randf() < 0.7 else rng.randi_range(1, n - 2)
		var c: Vector3 = pts[k]
		var ang := rng.randf() * TAU
		var spread := float(rad[k]) * rng.randf_range(0.2, 0.7)
		glow.append(c + Vector3(cos(ang) * spread, -float(rad[k]) * 0.8, sin(ang) * spread))
	var bats: Array[Vector3] = []
	for r: int in rooms:
		for j in 2:
			var ang := rng.randf() * TAU
			bats.append(pts[r] + Vector3(cos(ang) * 2.0, float(rad[r]) * 0.45, sin(ang) * 2.0))
	var last: Vector3 = pts[rooms[2]]
	var chest := Vector3(last.x + 2.2, last.y - float(rad[rooms[2]]) + 1.0, last.z - 1.2)
	return {"id": index, "pts": pts, "rad": rad, "rooms": rooms, "glow": glow, "bats": bats, "chest": chest}


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
