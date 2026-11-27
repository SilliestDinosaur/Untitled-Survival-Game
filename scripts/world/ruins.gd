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
		var dims := dims_of(kind, seed_value)
		var reach := reach_of(kind, dims)
		if not _clear(out, gen.landmarks, x, z):
			continue
		if Caves.void_distance(gen.caves, Vector3(x, h, z)) < 14.0:
			continue
		var biome := gen.get_biome(x, z)
		if kind == "temple":
			if biome in [WorldGen.Biome.TUNDRA, WorldGen.Biome.MARSH] or h > 45.0 or gen.get_normal(x, z).y < 0.9:
				continue
			if _rise(gen, x, z, yaw, dims.x * 0.5 + 1.0, dims.y * 0.5 + 1.0) > 3.2:
				continue   # too steep for a plinth
		else:
			if h < 12.0 or gen.get_normal(x, z).y < 0.8 or biome == WorldGen.Biome.MARSH:
				continue
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
		out.append({"kind": kind, "pos": Vector3(x, h, z), "yaw": yaw, "seed": seed_value, "r": reach, "size": dims})
	return out


## A temple's plinth (width, depth) or a tower's (radius, height), from its seed: the planner and the models
## agree on it without passing anything else around.
static func dims_of(kind: String, seed_value: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if kind == "temple":
		return Vector2(snappedf(rng.randf_range(9.0, 15.0), 0.5), snappedf(rng.randf_range(10.0, 18.0), 0.5))
	return Vector2(rng.randf_range(2.2, 3.2), rng.randf_range(9.0, 15.0))


## How far round a ruin its ground reaches (no trees or rocks on it).
static func reach_of(kind: String, dims: Vector2) -> float:
	if kind == "temple":
		return dims.length() * 0.5 + 5.0
	return dims.x + 6.0


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
