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


## A ring of old standing stones on a hilltop, a few fallen, one big flat one in the middle.
func _stones(kit: MeshKit, gen: WorldGen, at: Vector3, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var count := rng.randi_range(7, 11)
	var ring := rng.randf_range(5.0, 7.0)
	var stone := pal.rock.lerp(Color(0.62, 0.6, 0.55), 0.4)
	for k in count:
		var a := TAU * k / count + rng.randf_range(-0.08, 0.08)
		var p := at + Vector3(cos(a) * ring, 0, sin(a) * ring)
		p.y = gen.get_height(p.x, p.z)
		var h := rng.randf_range(2.4, 3.8)
		var w := rng.randf_range(0.85, 1.2)
		var c := stone.darkened(rng.randf_range(0.0, 0.2)).lerp(Color(0.42, 0.5, 0.34), rng.randf_range(0.0, 0.25))   # lichen
		if rng.randf() < 0.18:   # fallen over
			var lie := Basis(Vector3(-sin(a), 0, cos(a)), PI * 0.5 * rng.randf_range(0.85, 1.0)) * Basis(Vector3.UP, a)
			kit.add_primitive(MeshKit.cylinder(w * 0.8, w, h, 6), Transform3D(lie, p + Vector3(0, w * 0.55, 0) + Vector3(cos(a), 0, sin(a)) * h * 0.4), c, 0.15, 0.05)
			continue
		var tilt := Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.1))
		kit.add_primitive(MeshKit.cylinder(w * 0.7, w, h + 0.5, 6), Transform3D(tilt * Basis(Vector3.UP, a).scaled(Vector3(1.0, 1.0, 0.55)), p + Vector3(0, h * 0.5 - 0.25, 0)), c, 0.15, 0.05)
		_solid(p + Vector3(0, h * 0.5, 0), Vector3(w * 1.6, h, w * 1.0), a)
	var mid := at
	mid.y = gen.get_height(at.x, at.z)
	kit.add_primitive(MeshKit.cylinder(1.3, 1.5, 0.6, 7), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 1.0, 0.7)), mid + Vector3(0, 0.2, 0)), stone.darkened(0.1), 0.15, 0.05)
	_solid(mid + Vector3(0, 0.25, 0), Vector3(2.4, 0.5, 1.8), 0.0)
	return count


## A natural rock arch: two weathered legs and a span between them, layered in bands.
func _arch(kit: MeshKit, gen: WorldGen, at: Vector3, yaw: float, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var span := rng.randf_range(9.0, 13.0)
	var height := rng.randf_range(6.0, 8.5)
	var thick := rng.randf_range(0.9, 1.25)
	var base_col := pal.rock.lerp(Color(0.72, 0.5, 0.36), 0.45)
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
		return base_col.lightened(0.1 * band).darkened(0.08 * (1.0 - band)), Callable(), true, true, 0.12)
	for sgn: float in [-1.0, 1.0]:
		var leg := at + dir * sgn * span * 0.45
		leg.y = gen.get_height(leg.x, leg.z)
		_solid(leg + Vector3(0, height * 0.45, 0), Vector3(thick * 2.2, height * 0.9, thick * 2.2), yaw)
	return 1


## Two to four tall rock pillars standing in the sea, grassy on top, the waves' line round their feet.
func _stacks(kit: MeshKit, gen: WorldGen, at: Vector3, rng: RandomNumberGenerator, pal: WorldPalette) -> int:
	var count := rng.randi_range(2, 4)
	for k in count:
		var p := at + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
		var floor_y := gen.get_height(p.x, p.z)
		var top := rng.randf_range(5.0, 12.0) * (1.0 if k == 0 else rng.randf_range(0.4, 0.8))
		var r := rng.randf_range(1.4, 2.6) * (1.0 if k == 0 else 0.7)
		var path: Array = []
		var radii: Array = []
		for i in 6:
			var t := i / 5.0
			path.append(Vector3(p.x, lerpf(floor_y - 0.5, top, t), p.z) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)) * t)
			radii.append(r * lerpf(1.25, 0.8, t) * rng.randf_range(0.9, 1.1))
		var c := pal.rock.darkened(rng.randf_range(0.0, 0.15))
		kit.loft(path, radii, 8, c, func(t: float, _ang: float) -> Color:
			return c.lightened(0.18) if t < 0.18 else (pal.ground[WorldGen.Biome.MEADOW] if t > 0.97 else c), Callable(), true, true, 0.15)
		_solid(Vector3(p.x, (floor_y + top) * 0.5, p.z), Vector3(r * 2.0, top - floor_y, r * 2.0), 0.0)
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
