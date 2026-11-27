class_name LandmarkModels
extends Node3D
## Builds the landmarks that aren't trees or flowers (see Landmarks): rings of standing stones, rock arches and sea
## stacks. Each is one painted mesh with simple box colliders, seen from far off (they're things to steer by).

const SEEN := 420.0


func build(list: Array) -> void:
	var mat := ArtStyle.painted({"brush_strength": 0.3, "rim_amount": 0.15})
	var pal: WorldPalette = Game.palette
	var gen: WorldGen = Game.world_gen
	for lm: Dictionary in list:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(lm.seed)
		var at: Vector3 = lm.pos
		var kit := MeshKit.new(int(lm.seed))
		var n := 0
		match String(lm.kind):
			"stones":
				n = _stones(kit, gen, at, rng, pal)
			"arch":
				n = _arch(kit, gen, at, float(lm.yaw), rng, pal)
			"stack":
				n = _stacks(kit, gen, at, rng, pal)
		if n == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(mat)
		mi.position = Vector3.ZERO
		mi.visibility_range_end = SEEN
		add_child(mi)


## A ring of old standing stones on a hilltop, a few fallen, one big flat one in the middle. Each is fitted to the
## ground it stands on (the drawn ground, see ChunkGenerator.surface_height): a standing stone reaches down past
## the lowest ground round its foot, a fallen one lies along the slope under it, and the slab is tipped to the
## ground and bedded in all round, so none of them shows a gap underneath.
func _stones(kit: MeshKit, gen: WorldGen, at: Vector3, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var count := rng.randi_range(7, 11)
	var ring := rng.randf_range(5.0, 7.0)
	var stone := pal.rock.lerp(Color(0.62, 0.6, 0.55), 0.4)
	var ground := {}
	var surf := func(x: float, z: float) -> float: return ChunkGenerator.surface_height(gen, x, z, ground)
	for k in count:
		var a := TAU * k / count + rng.randf_range(-0.08, 0.08)
		var out := Vector3(cos(a), 0, sin(a))
		var p := at + out * ring
		p.y = surf.call(p.x, p.z)
		var h := rng.randf_range(2.4, 3.8)
		var w := rng.randf_range(0.85, 1.2)
		var c := stone.darkened(rng.randf_range(0.0, 0.2)).lerp(Color(0.42, 0.5, 0.34), rng.randf_range(0.0, 0.25))   # lichen
		if rng.randf() < 0.18:   # fallen over, outward, lying along the slope under it
			var lie_r := w * 0.9
			var a0 := p - out * h * 0.1
			var a1 := p + out * h * 0.9
			a0.y = surf.call(a0.x, a0.z)
			a1.y = surf.call(a1.x, a1.z)
			var axis := (a1 - a0).normalized()
			var mid := (a0 + a1) * 0.5
			mid.y = minf(mid.y, surf.call(mid.x, mid.z))   # (over a rise, it bridges it: bed it at the low side)
			var roll := Basis(axis, rng.randf() * TAU)
			kit.add_primitive(MeshKit.cylinder(w * 0.8, w, h, 6), Transform3D(roll * Basis(Quaternion(Vector3.UP, axis)), mid + Vector3(0, lie_r * 0.5, 0)), c, 0.15, 0.05)
			continue
		# Upright (a touch of lean): from well under the lowest ground round its foot up to its full height.
		var yaw_b := Basis(Vector3.UP, a)
		var low := ChunkGenerator.lowest_ground(gen, p.x, p.z, w * 1.05, w * 1.05, 0.0, ground)
		var bottom := low - 0.35
		var top := p.y + h
		var tall := top - bottom
		var tilt := Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.07))
		kit.add_primitive(MeshKit.cylinder(w * 0.7, w, tall, 6), Transform3D(tilt * yaw_b.scaled(Vector3(1.0, 1.0, 0.55)), Vector3(p.x, bottom + tall * 0.5, p.z)), c, 0.15, 0.05)
		_solid(p + Vector3(0, h * 0.5, 0), Vector3(w * 1.6, h, w * 1.0), a)
	# The slab in the middle: tipped to the ground under it, its whole rim bedded in.
	var mid := at
	mid.y = surf.call(at.x, at.z)
	var e := 1.4
	var sx: float = (surf.call(at.x + e, at.z) - surf.call(at.x - e, at.z)) / (2.0 * e)
	var sz: float = (surf.call(at.x, at.z + e) - surf.call(at.x, at.z - e)) / (2.0 * e)
	var n := Vector3(-sx, 1.0, -sz).normalized()
	var slab := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, rng.randf() * TAU)
	var sunk := 0.0   # how far the tipped slab's foot rim floats at worst
	for k in 10:
		var q := mid + slab * Vector3(cos(TAU * k / 10.0) * 1.5, -0.1, sin(TAU * k / 10.0) * 1.5)
		sunk = maxf(sunk, q.y - surf.call(q.x, q.z))
	mid.y -= sunk + 0.08
	kit.add_primitive(MeshKit.cylinder(1.3, 1.5, 0.75, 7), Transform3D(slab.scaled(Vector3(1.0, 1.0, 0.7)), mid + slab * Vector3(0, 0.27, 0)), stone.darkened(0.1), 0.15, 0.05)
	_solid(mid + Vector3(0, 0.3, 0), Vector3(2.4, 0.55, 1.8), 0.0)
	return count


## A natural rock arch: two weathered legs and a span between them, layered in bands.
func _arch(kit: MeshKit, gen: WorldGen, at: Vector3, yaw: float, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var span := rng.randf_range(9.0, 13.0)
	var height := rng.randf_range(6.0, 8.5)
	var thick := rng.randf_range(0.9, 1.25)
	var base_col := pal.rock.lerp(Color(0.72, 0.5, 0.36), 0.45)
	var phase := rng.randf() * TAU
	var path: Array = []
	var radii: Array = []
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var x := (t - 0.5) * span
		var p := at + dir * x
		var g := gen.get_height(p.x, p.z)
		# A rounded arc: the legs rise steeply, the span is near level over the top.
		var arc := sqrt(maxf(sin(t * PI), 0.0))
		var y := lerpf(g - 1.0, at.y + height, arc) if i > 0 and i < steps else g - 1.0
		path.append(Vector3(p.x, y, p.z))
		radii.append(thick * (1.0 + 0.9 * pow(1.0 - sin(t * PI), 2.0)) * (1.0 + rng.randf_range(-0.08, 0.08)))
	kit.loft(path, radii, 9, base_col, func(t: float, _ang: float) -> Color:
		var band := sin(t * 23.0) * 0.5 + 0.5
		return base_col.lightened(0.1 * band).darkened(0.08 * (1.0 - band)),
		func(t: float, ang: float) -> Vector2:
			# Weathered across, not a tube: a lumpy outline that changes along the span.
			var f := 1.0 + 0.18 * sin(ang * 3.0 + phase + t * 5.0) + 0.08 * sin(ang * 5.0 - t * 7.0)
			return Vector2(f * 1.1, f * 0.9), true, true, 0.22)
	for sgn: float in [-1.0, 1.0]:
		var leg := at + dir * sgn * span * 0.45
		leg.y = gen.get_height(leg.x, leg.z)
		# Rubble fallen from it round the foot of each leg.
		for j in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var bp := leg + Vector3(cos(a), 0, sin(a)) * thick * rng.randf_range(1.6, 3.0)
			var bs := thick * rng.randf_range(0.25, 0.55)
			bp.y = ChunkGenerator.lowest_ground(gen, bp.x, bp.z, bs * 1.1, bs * 1.1)
			kit.add_primitive(MeshKit.sphere(1.0, 7, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bs * 1.3, bs * 0.8, bs)), bp + Vector3(0, bs * 0.3, 0)), base_col.darkened(rng.randf_range(0.0, 0.15)), 0.35, 0.06)
		_solid(leg + Vector3(0, height * 0.45, 0), Vector3(thick * 2.2, height * 0.9, thick * 2.2), yaw)
	return 1


## Two to four tall rock pillars standing in the sea: craggy and leaning a little, layered in bands, ledged, dark and
## wet where the waves reach, a grassy cap on top and fallen blocks round their feet.
func _stacks(kit: MeshKit, gen: WorldGen, at: Vector3, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var count := rng.randi_range(2, 4)
	var sea := Game.SEA_LEVEL
	var grass: Color = pal.ground[WorldGen.Biome.MEADOW]
	for k in count:
		var p := at + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
		var floor_y := gen.get_height(p.x, p.z)
		var top := rng.randf_range(6.0, 13.0) * (1.0 if k == 0 else rng.randf_range(0.4, 0.8))
		var r := rng.randf_range(1.6, 2.8) * (1.0 if k == 0 else 0.7)
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.3, 1.2)
		# Where the ledges are: the radius steps in there.
		var ledge_a := rng.randf_range(0.3, 0.5)
		var ledge_b := rng.randf_range(0.6, 0.8)
		var path: Array = []
		var radii: Array = []
		var rings := 11
		for i in rings:
			var t := float(i) / (rings - 1)
			var y := lerpf(floor_y - 0.5, top, t)
			path.append(Vector3(p.x, y, p.z) + lean * t * t + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)) * t)
			var rr := r * lerpf(1.0, 0.72, t)
			rr *= 1.0 + 0.45 * clampf(1.0 - (y - floor_y) / 2.5, 0.0, 1.0)   # the foot flares out under the water
			if t > ledge_a:
				rr *= 0.86
			if t > ledge_b:
				rr *= 0.88
			radii.append(rr * rng.randf_range(0.93, 1.07))
		var c := pal.rock.darkened(rng.randf_range(0.0, 0.12)).lerp(Color(0.6, 0.55, 0.48), 0.2)
		var phase := rng.randf() * TAU
		var phase2 := rng.randf() * TAU
		var wet := c.darkened(0.4).lerp(Color(0.2, 0.3, 0.28), 0.3)
		var span := top - floor_y
		kit.loft(path, radii, 10, c, func(t: float, _ang: float) -> Color:
			var y := floor_y - 0.5 + t * (span + 0.5)
			if y < sea + 0.7:
				return wet   # wet and weedy where the waves reach
			var band := sin(y * 2.3 + phase) * 0.5 + 0.5
			var col := c.lightened(0.14 * band).darkened(0.1 * (1.0 - band))
			return col.lerp(grass.darkened(0.15), 0.45) if t > 0.94 else col,
			func(t: float, ang: float) -> Vector2:
				# Craggy across: a lumpy, flattened outline, different at each height.
				var f := 1.0 + 0.2 * sin(ang * 3.0 + phase + t * 2.0) + 0.1 * sin(ang * 5.0 + phase2 - t * 3.0)
				return Vector2(f, f * 0.85), true, true, 0.3)
		# A grassy cap over the flat top, and a tuft or two hanging over its edge.
		var cap_at: Vector3 = path[rings - 1]
		var cap_r: float = radii[rings - 1]
		kit.add_primitive(MeshKit.sphere(1.0, 10, 5), Transform3D(Basis.from_scale(Vector3(cap_r * 1.08, 0.35, cap_r * 0.95)), cap_at + Vector3(0, -0.05, 0)), grass, 0.15, 0.06)
		for j in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			kit.add_primitive(MeshKit.sphere(1.0, 6, 4), Transform3D(Basis.from_scale(Vector3(0.45, 0.3, 0.45)), cap_at + Vector3(cos(a) * cap_r, -0.2, sin(a) * cap_r)), grass.darkened(0.1), 0.2, 0.06)
		# Blocks fallen from it, half in the water round its foot.
		for j in rng.randi_range(3, 5):
			var a := rng.randf() * TAU
			var d := r * rng.randf_range(1.3, 2.0)
			var bp := Vector3(p.x + cos(a) * d, 0, p.z + sin(a) * d)
			var by := maxf(gen.get_height(bp.x, bp.z), sea - 1.5)
			var bs := rng.randf_range(0.5, 1.1) * r * 0.5
			kit.add_primitive(MeshKit.sphere(1.0, 7, 4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(bs * 1.2, bs * 0.8, bs)), Vector3(bp.x, by + bs * 0.3, bp.z)), wet.lerp(c, 0.4), 0.35, 0.06)
		_solid(Vector3(p.x, (floor_y + top) * 0.5, p.z) + lean * 0.3, Vector3(r * 2.0, top - floor_y, r * 2.0), 0.0)
	return count


func _solid(at: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_SOLID
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.position = at
	body.rotation.y = yaw
	body.add_child(cs)
	add_child(body)
