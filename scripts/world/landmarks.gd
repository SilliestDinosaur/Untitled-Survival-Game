class_name Landmarks
extends RefCounted
## The places worth finding on an island, worked out once from its seed (the same on every machine):
##   giant_tree: a lone, huge old tree standing in a clearing of its own
##   meadow:     an open glade thick with flowers, inside a forest
##   stones:     a ring of old standing stones on a hilltop
##   arch:       a natural rock arch standing over open ground
##   stack:      tall rock pillars standing in the sea off the coast
## Each is {kind, pos: Vector3 (on the ground), r: the ground it claims (no trees grow there), yaw}.
## The chunks keep trees out of a landmark's ground and add its tree or flowers; LandmarkModels builds the rest.

const MAX := {"giant_tree": 5, "meadow": 6, "stones": 3, "arch": 3, "stack": 4}


static func plan(gen: WorldGen) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "landmarks"])
	var out: Array = []
	var size := Game.WORLD_SIZE
	var counts := {}
	var tries := 0
	while tries < 2600:
		tries += 1
		var x := rng.randf_range(80.0, size - 80.0)
		var z := rng.randf_range(80.0, size - 80.0)
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var h := gen.get_height(x, z)
		var kind := ""
		var r := 0.0
		if h < -3.0 and h > -12.0:
			# Sea stacks: off the coast, in water a few metres deep, with land close by.
			if _land_within(gen, x, z, 70.0):
				kind = "stack"
				r = 6.0
		elif h > 4.0 and not gen.near_river(x, z, 12.0) and Caves.void_distance(gen.caves, Vector3(x, h, z)) > 12.0:
			var n := gen.get_normal(x, z)
			var biome := gen.get_biome(x, z)
			var forest := gen.get_forest_clump(x, z)
			if roll < 0.3 and n.y > 0.95 and h < 40.0 and biome in [WorldGen.Biome.MEADOW, WorldGen.Biome.FOREST, WorldGen.Biome.AUTUMN, WorldGen.Biome.DRYLANDS, WorldGen.Biome.JUNGLE]:
				kind = "giant_tree"
				r = 20.0
			elif roll < 0.55 and n.y > 0.94 and forest > 0.5 and h < 40.0 and biome in [WorldGen.Biome.FOREST, WorldGen.Biome.AUTUMN, WorldGen.Biome.MEADOW, WorldGen.Biome.TAIGA]:
				kind = "meadow"
				r = rng.randf_range(14.0, 22.0)
			elif roll < 0.78 and n.y > 0.9 and _hilltop(gen, x, z, h) and h < 55.0:
				kind = "stones"
				r = 9.0
			elif roll >= 0.78 and n.y > 0.9 and h < 45.0 and biome in [WorldGen.Biome.DRYLANDS, WorldGen.Biome.DESERT, WorldGen.Biome.BADLANDS, WorldGen.Biome.MEADOW, WorldGen.Biome.HIGHLANDS]:
				kind = "arch"
				r = 10.0
		if kind == "" or int(counts.get(kind, 0)) >= int(MAX[kind]):
			continue
		# Apart from each other (and the spawn's area stays plain).
		var p := Vector3(x, h, z)
		var ok := true
		for o: Dictionary in out:
			if Vector2(o.pos.x - x, o.pos.z - z).length() < 140.0:
				ok = false
				break
		if not ok:
			continue
		counts[kind] = int(counts.get(kind, 0)) + 1
		out.append({"kind": kind, "pos": p, "r": r, "yaw": yaw, "seed": rng.randi()})
	return out


static func _land_within(gen: WorldGen, x: float, z: float, d: float) -> bool:
	for k in 8:
		var a := TAU * k / 8.0
		if gen.get_height(x + cos(a) * d, z + sin(a) * d) > 1.5:
			return true
	return false


## Higher than the ground round it on every side.
static func _hilltop(gen: WorldGen, x: float, z: float, h: float) -> bool:
	for k in 8:
		var a := TAU * k / 8.0
		if gen.get_height(x + cos(a) * 30.0, z + sin(a) * 30.0) > h - 2.5:
			return false
	return true


## The landmark whose ground (x, z) is in, or {}.
static func at(list: Array, x: float, z: float) -> Dictionary:
	for lm: Dictionary in list:
		var p: Vector3 = lm.pos
		if Vector2(p.x - x, p.z - z).length() < float(lm.r):
			return lm
	return {}
