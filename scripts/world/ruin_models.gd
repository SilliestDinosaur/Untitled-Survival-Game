class_name RuinModels
extends Node3D
## Builds the island's ruins (see Ruins): overgrown temples and watchtowers, each laid out and worn down its own way
## from its seed, so no two are alike. Real stone blocks in courses (not painted-on lines), moss on what faces the
## sky in damp country, rubble round about. One painted mesh each, box colliders for what you can stand on or bump
## into, and a chest (Interact: see GameActions.open_cache).
##
## Built in each ruin's own frame: x across, z back to front (the stair is at -z), y up from the ground at its middle.

const SEEN := 460.0
const COURSE := 0.5   ## a course of stone

var _mat: Material
var _box := BoxMesh.new()   ## one unit box, scaled for every block (its arrays are made once)
var _stone := Color(0.66, 0.64, 0.58)
var _moss := Color(0.36, 0.48, 0.24)
var _mossy := 0.0           ## how much moss grows here (damp country) 0..1
var _frame := Transform3D()
var _ground := {}
var _shapes: StaticBody3D


func build(list: Array) -> void:
	_mat = ArtStyle.painted({"brush_strength": 0.3, "rim_amount": 0.2})
	for i in list.size():
		var ru: Dictionary = list[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(ru.seed) + 7   # (Ruins.dims_of draws from the seed itself)
		var pos: Vector3 = ru.pos
		_frame = Transform3D(Basis(Vector3.UP, float(ru.yaw)), pos)
		_ground = {}
		_look(pos, rng)
		_shapes = StaticBody3D.new()
		_shapes.collision_layer = TerrainChunk.LAYER_SOLID
		_shapes.collision_mask = 0
		_shapes.transform = _frame
		add_child(_shapes)
		var kit := MeshKit.new(int(ru.seed))
		var chest: Transform3D
		if ru.kind == "temple":
			chest = _temple(kit, ru.size, rng)
		else:
			chest = _tower(kit, ru.size, rng)
		_chest(kit, chest, i)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(_mat)
		mi.transform = _frame
		mi.visibility_range_end = SEEN
		add_child(mi)


## The stone and the moss of the country it stands in.
func _look(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var gen: WorldGen = Game.world_gen
	var pal: WorldPalette = Game.palette
	var b := gen.get_biome(pos.x, pos.z)
	match b:
		WorldGen.Biome.DESERT:
			_stone = Color(0.84, 0.7, 0.52)
		WorldGen.Biome.DRYLANDS:
			_stone = Color(0.78, 0.69, 0.56)
		WorldGen.Biome.BADLANDS:
			_stone = pal.badlands_ochre.lerp(Color(0.82, 0.62, 0.5), 0.45)
		WorldGen.Biome.JUNGLE:
			_stone = Color(0.58, 0.6, 0.52)
		WorldGen.Biome.TAIGA, WorldGen.Biome.TUNDRA, WorldGen.Biome.HIGHLANDS:
			_stone = Color(0.6, 0.61, 0.64)
		_:
			_stone = Color(0.68, 0.65, 0.58)
	_stone = _stone.lerp(pal.rock, 0.2).lightened(rng.randf_range(-0.05, 0.05))
	_mossy = {WorldGen.Biome.JUNGLE: 0.9, WorldGen.Biome.FOREST: 0.65, WorldGen.Biome.AUTUMN: 0.5, WorldGen.Biome.TAIGA: 0.5,
		WorldGen.Biome.MEADOW: 0.35, WorldGen.Biome.FUNGAL: 0.6}.get(b, 0.05)
	_moss = Color(0.34, 0.47, 0.22) if b != WorldGen.Biome.FUNGAL else Color(0.42, 0.34, 0.5)


# --- Helpers ------------------------------------------------------------------------------------

## The drawn ground's height at a point of the ruin's frame, in that frame.
func _gy(x: float, z: float) -> float:
	var w := _frame * Vector3(x, 0, z)
	return ChunkGenerator.surface_height(Game.world_gen, w.x, w.z, _ground) - _frame.origin.y


## Lowest and highest ground over a rectangle (half w by half d) of the frame.
func _ground_span(hw: float, hd: float) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for i in 7:
		for j in 7:
			var h := _gy(lerpf(-hw, hw, i / 6.0), lerpf(-hd, hd, j / 6.0))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## A stone block: size, placed by xf (in the frame), its top mossy by `moss` (fading down its sides).
func _block(kit: MeshKit, size: Vector3, xf: Transform3D, col: Color, moss := 0.0) -> void:
	var c := col
	var top := col.lerp(_moss, clampf(moss, 0.0, 0.85))
	kit.add_primitive(_box, Transform3D(xf.basis.scaled_local(size), xf.origin), c, 0.0, 0.05, null,
		func(p: Vector3) -> Color: return top if p.y > 0.0 else c)


## A stone's colour: the stone, a little lighter or darker block by block.
func _shade(rng: RandomNumberGenerator) -> Color:
	return _stone.lightened(rng.randf_range(-0.09, 0.07))


func _solid(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_shapes.add_child(cs)


## Fallen blocks lying about: on the ground (or a deck at `on_y`), half sunk and tipped.
func _rubble(kit: MeshKit, rng: RandomNumberGenerator, center: Vector2, spread: float, count: int, on_y := NAN) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, 1.0) * spread
		var p := center + Vector2(cos(a), sin(a)) * d
		var s := Vector3(rng.randf_range(0.35, 0.8), rng.randf_range(0.25, 0.45), rng.randf_range(0.3, 0.6))
		var y: float = on_y if not is_nan(on_y) else _gy(p.x, p.y)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.05, 0.35))
		_block(kit, s, Transform3D(b, Vector3(p.x, y + s.y * 0.3, p.y)), _shade(rng).darkened(0.05), _mossy * 0.6)


## A column standing on `foot` (frame), `height` tall if whole: a base, a slightly swelling shaft in drums, a
## capital. Broken (`left` < 1) it stops at that share with a ragged drum; its fallen drums lie beside it.
func _column(kit: MeshKit, rng: RandomNumberGenerator, foot: Vector3, radius: float, height: float, left: float, fall_on_y: float) -> bool:
	var col := _shade(rng)
	_block(kit, Vector3(radius * 2.5, 0.28, radius * 2.5), Transform3D(Basis(), foot + Vector3(0, 0.14, 0)), col.darkened(0.04), _mossy * 0.5)
	if left <= 0.0:
		return false
	var shaft_h := (height - 0.28 - 0.32) * left
	var drums := maxi(1, roundi(shaft_h / 0.9))
	var y := foot.y + 0.28
	var tilt := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04)) * (1.0 - left)
	for d in drums:
		var h := shaft_h / drums
		var t0 := (y - foot.y) / height
		var r0 := radius * (1.0 + 0.06 * sin(t0 * PI))
		var r1 := radius * (1.0 + 0.06 * sin(minf(t0 + h / height, 1.0) * PI))
		var at := foot + Vector3(0, y - foot.y, 0) + tilt * (y - foot.y)
		# (A hair narrower at each drum's ends, so drums read as stacked stones, and no two faces meet flush.)
		kit.add_primitive(MeshKit.cylinder(r1 * 0.97, r0 * 0.97, h - 0.02, 12), Transform3D(Basis(), at + Vector3(0, h * 0.5, 0)),
			col.lightened(rng.randf_range(-0.04, 0.04)), 0.0, 0.05, null,
			func(p: Vector3) -> Color: return col.lerp(_moss, _mossy * 0.5) if p.y > h * 0.3 and d == drums - 1 and left < 1.0 else col)
		y += h
	var whole := left >= 1.0
	if whole:   # the capital: a square slab on a round collar
		_block(kit, Vector3(radius * 2.7, 0.3, radius * 2.7), Transform3D(Basis(), foot + Vector3(0, height - 0.15, 0)), col.lightened(0.03), _mossy)
	else:
		# Its fallen drums, lying where they rolled.
		for k in rng.randi_range(1, 2):
			var a := rng.randf() * TAU
			var p := foot + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.2, 2.6)
			var py: float = fall_on_y if not is_nan(fall_on_y) else _gy(p.x, p.z)
			kit.add_primitive(MeshKit.cylinder(radius * 0.95, radius * 0.95, 0.85, 12),
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5), Vector3(p.x, py + radius * 0.8, p.z)),
				col.darkened(0.04), 0.0, 0.05)
	_solid(Vector3(radius * 1.8, y - foot.y + (0.3 if whole else 0.0), radius * 1.8), Transform3D(Basis(), foot + Vector3(0, (y - foot.y) * 0.5, 0)))
	return whole


## A wall of coursed blocks from a to b (frame xz), standing on `base_y`, up to `height` but ruined along its top
## (some stretches lower, a few gaps), with `openings` ([from, to] metres along it, up to `open_h`) left open.
func _wall(kit: MeshKit, rng: RandomNumberGenerator, a: Vector2, b: Vector2, base_y: float, height: float, thick: float,
		openings: Array, open_h := 2.2, wear := 1.0) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x))
	var courses := maxi(1, roundi(height / COURSE))
	# The ruined top: how many courses still stand at each metre along it (smooth dips, the odd deep gap).
	var ph := rng.randf() * TAU
	var keep := func(s: float) -> int:
		var v := lerpf(1.0, 0.72 + 0.28 * sin(s * 0.9 + ph) + 0.15 * sin(s * 2.3 - ph * 1.7), wear)
		return clampi(roundi(courses * clampf(v, 0.15, 1.0)), 1, courses)
	var tops: Array = []   # [from s, to s, top y] stretches, for the colliders
	for row in courses:
		var y0 := base_y + row * COURSE
		var s := -rng.randf_range(0.1, 0.5) if row % 2 == 1 else 0.0
		while s < length - 0.05:
			var s0 := maxf(s, 0.0)
			var s1 := minf(s0 + rng.randf_range(0.6, 1.15), length)
			if length - s1 < 0.3:
				s1 = length
			s = s1
			var mid := (s0 + s1) * 0.5
			if row >= keep.call(mid):
				continue
			var open := false
			for o: Array in openings:
				if s1 > float(o[0]) and s0 < float(o[1]) and y0 < base_y + open_h:
					open = true
			if open:
				continue
			var lift := rng.randf_range(-0.03, 0.03) if row == keep.call(mid) - 1 else 0.0   # top stones a touch askew
			var p := a + dir * mid
			var xf := Transform3D(basis * Basis(Vector3.UP, lift * 2.0), Vector3(p.x, y0 + COURSE * 0.5 + lift, p.y))
			_block(kit, Vector3(s1 - s0 - 0.03, COURSE - 0.02, thick), xf, _shade(rng), _mossy if row == keep.call(mid) - 1 else 0.0)
	# Lintels over the openings, if the wall still stands that high there.
	for o: Array in openings:
		var mid := (float(o[0]) + float(o[1])) * 0.5
		if keep.call(mid) * COURSE > open_h + COURSE * 0.5:
			var p := a + dir * mid
			_block(kit, Vector3(float(o[1]) - float(o[0]) + 0.6, COURSE * 0.8, thick + 0.04), Transform3D(basis, Vector3(p.x, base_y + open_h + COURSE * 0.4, p.y)), _shade(rng).darkened(0.05), _mossy * 0.4)
	# Colliders: one box a metre along, as high as the wall stands there (none in the openings).
	var s2 := 0.0
	while s2 < length - 0.01:
		var e := minf(s2 + 1.0, length)
		var mid := (s2 + e) * 0.5
		var inside := false
		for o: Array in openings:
			if mid > float(o[0]) and mid < float(o[1]):
				inside = true
		var h: float = keep.call(mid) * COURSE
		var p := a + dir * mid
		if inside:
			if h > open_h + COURSE:
				_solid(Vector3(e - s2, h - open_h, thick), Transform3D(basis, Vector3(p.x, base_y + open_h + (h - open_h) * 0.5, p.y)))
		else:
			_solid(Vector3(e - s2, h, thick), Transform3D(basis, Vector3(p.x, base_y + h * 0.5, p.y)))
		s2 = e


# --- Temples ------------------------------------------------------------------------------------

## An old temple on a stepped plinth. Returns where its chest stands (frame).
func _temple(kit: MeshKit, dims: Vector2, rng: RandomNumberGenerator) -> Transform3D:
	var gen: WorldGen = Game.world_gen
	var w := _frame.origin
	var biome := gen.get_biome(w.x, w.z)
	var styles := ["colonnade", "colonnade", "hall", "tholos"]
	if biome in [WorldGen.Biome.JUNGLE, WorldGen.Biome.DESERT, WorldGen.Biome.DRYLANDS, WorldGen.Biome.BADLANDS]:
		styles += ["stepped", "stepped", "stepped"]
	var style: String = styles[rng.randi() % styles.size()]
	var hw := dims.x * 0.5
	var hd := dims.y * 0.5
	var span := _ground_span(hw, hd)
	var tiers := rng.randi_range(1, 3) if style != "stepped" else rng.randi_range(3, 5)
	var tier_h := rng.randf_range(0.5, 0.75)
	var inset := rng.randf_range(0.7, 1.1) if style != "stepped" else rng.randf_range(1.1, 1.5)
	tiers = mini(tiers, int((minf(hw, hd) - 3.0) / inset) + 1)   # the top keeps room to stand things on
	var foot := span.x - 0.5
	var top0 := span.y + tier_h
	# The plinth: tier on tier, each a core with a kerb of blocks round its edge, a little worn.
	for t in tiers:
		var tw := hw - t * inset
		var td := hd - t * inset
		var top := top0 + t * tier_h
		var bottom := foot if t == 0 else top - tier_h - 0.1
		var core := _stone.darkened(0.16)
		_block(kit, Vector3(tw * 2.0 - 0.3, top - bottom, td * 2.0 - 0.3), Transform3D(Basis(), Vector3(0, (top + bottom) * 0.5, 0)), core, _mossy * 0.3)
		_solid(Vector3(tw * 2.0, top - bottom, td * 2.0), Transform3D(Basis(), Vector3(0, (top + bottom) * 0.5, 0)))
		for side in 4:
			var along := tw if side % 2 == 0 else td
			var across := td if side % 2 == 0 else tw
			var s := -along
			while s < along - 0.05:
				var e := minf(s + rng.randf_range(0.8, 1.4), along)
				if along - e < 0.4:
					e = along
				var mid := (s + e) * 0.5
				s = e
				if rng.randf() < 0.08:
					continue   # a block gone
				var h := minf(tier_h + (0.5 if t == 0 else 0.0), top - bottom)
				var p := Vector3(mid, top - h * 0.5 + 0.03, -across + 0.2) if side % 2 == 0 else Vector3(-across + 0.2, top - h * 0.5 + 0.03, mid)
				if side >= 2:
					p = Vector3(-p.x, p.y, -p.z)
				var size := Vector3(e - (mid * 2.0 - e) - 0.04, h, 0.46) if side % 2 == 0 else Vector3(0.46, h, e - (mid * 2.0 - e) - 0.04)
				var nudge := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
				_block(kit, size, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), p + nudge), _shade(rng), _mossy)
	var deck_t := tiers - 1
	var dw := hw - deck_t * inset
	var dd := hd - deck_t * inset
	var deck_y := top0 + deck_t * tier_h
	# Paving on the deck, some slabs lifted or gone (the core shows dark between).
	for i in int((dw * 2.0 - 0.8) / 1.1):
		for j in int((dd * 2.0 - 0.8) / 1.1):
			if rng.randf() < 0.15:
				continue
			var p := Vector3(-dw + 0.4 + 0.55 + i * 1.1, deck_y + 0.04, -dd + 0.4 + 0.55 + j * 1.1)
			var heave := rng.randf_range(0.0, 0.06) if rng.randf() < 0.2 else 0.0
			_block(kit, Vector3(1.04, 0.08 + heave, 1.04), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), p + Vector3(0, heave * 0.5, 0)), _stone.lightened(rng.randf_range(-0.05, 0.08)), _mossy * rng.randf_range(0.2, 0.8))
	# The stair up the front (-z), from the ground to the deck, in steps you walk up.
	var sw := clampf(dw * 0.7, 2.2, 4.5)
	var front := -hd
	var ground_y := _gy(0.0, front - 1.0)
	var rise := 0.27
	var steps := ceili((deck_y - ground_y) / rise)
	var run := 0.42
	for k in steps:
		# The last step meets the deck's front edge; the ones before it run out over the lower tiers and down onto
		# the ground in front (where they're buried in a tier, they're hidden in it).
		var top_y := minf(ground_y + (k + 1) * rise, deck_y)
		var z := -dd - (steps - 1 - k + 0.5) * run
		var bottom := minf(_gy(-sw * 0.5, z), _gy(sw * 0.5, z)) - 0.3
		var xf := Transform3D(Basis(), Vector3(0, (top_y + bottom) * 0.5, z))
		_block(kit, Vector3(sw - (0.06 if k % 2 == 0 else 0.0), top_y - bottom, run + 0.01), xf, _shade(rng), _mossy * 0.7)
		_solid(Vector3(sw, top_y - bottom, run + 0.01), xf)
	# What stands on the deck.
	var chest := Transform3D(Basis(), Vector3(0, deck_y + 0.08, dd - 3.0))
	match style:
		"colonnade":
			_colonnade(kit, rng, dw - 0.9, dd - 0.9, deck_y + 0.08)
			if rng.randf() < 0.55:   # a shrine within: walls round the back half, a doorway in its front
				var cw := dw * 0.5
				var z0 := -dd * 0.05
				var z1 := dd - 2.4
				var h := rng.randf_range(2.6, 3.6)
				_wall(kit, rng, Vector2(-cw, z0), Vector2(-cw, z1), deck_y + 0.08, h, 0.6, [])
				_wall(kit, rng, Vector2(cw, z1), Vector2(cw, z0), deck_y + 0.08, h, 0.6, [])
				_wall(kit, rng, Vector2(-cw, z1), Vector2(cw, z1), deck_y + 0.08, h, 0.6, [])
				var door := rng.randf_range(1.2, 1.8)
				_wall(kit, rng, Vector2(-cw, z0), Vector2(cw, z0), deck_y + 0.08, h, 0.6, [[cw - door * 0.5, cw + door * 0.5]])
				chest = Transform3D(Basis(), Vector3(0, deck_y + 0.08, (z0 + z1) * 0.5 + 0.6))
		"hall":
			var h := rng.randf_range(3.0, 4.2)
			var wx := dw - 0.6
			# Long walls with windows, a back wall; the front open between two columns.
			var win: Array = []
			var n := int((dd * 2.0 - 2.0) / 3.0)
			for k in n:
				var c := 1.5 + k * 3.0 + 1.0
				win.append([c - 0.4, c + 0.4])
			_wall(kit, rng, Vector2(-wx, -dd + 0.6), Vector2(-wx, dd - 0.6), deck_y + 0.08, h, 0.6, win, 2.0)
			_wall(kit, rng, Vector2(wx, dd - 0.6), Vector2(wx, -dd + 0.6), deck_y + 0.08, h, 0.6, win, 2.0)
			_wall(kit, rng, Vector2(-wx, dd - 0.6), Vector2(wx, dd - 0.6), deck_y + 0.08, h, 0.6, [])
			for sx in [-1.0, 1.0]:
				_column(kit, rng, Vector3(sx * wx * 0.45, deck_y + 0.08, -dd + 1.0), 0.36, h + 0.4, 1.0 if rng.randf() < 0.6 else rng.randf_range(0.3, 0.8), deck_y + 0.08)
			# A row of columns down the middle, most fallen.
			for k in int(dd * 2.0 / 3.5):
				var z := -dd + 2.5 + k * 3.5
				if z > dd - 3.0:
					break
				_column(kit, rng, Vector3(0, deck_y + 0.08, z), 0.3, h + 0.2, rng.randf_range(0.0, 0.7), deck_y + 0.08)
			chest = Transform3D(Basis(), Vector3(wx * 0.5, deck_y + 0.08, dd - 3.0))   # (off the middle row)
		"tholos":
			var ring := minf(dw, dd) - 1.0
			var n := rng.randi_range(8, 12)
			var whole: Array = []
			for k in n:
				var a := TAU * k / n
				var left := 1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 0.8)
				whole.append(_column(kit, rng, Vector3(cos(a) * ring, deck_y + 0.08, sin(a) * ring), 0.32, 4.2, left, deck_y + 0.08))
			for k in n:   # a curved lintel between two whole neighbours
				if whole[k] and whole[(k + 1) % n] and rng.randf() < 0.7:
					var a := TAU * (k + 0.5) / n
					var len := 2.0 * ring * sin(PI / n) + 0.7
					_block(kit, Vector3(len, 0.45, 0.6), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * ring * cos(PI / n), deck_y + 0.08 + 4.2 + 0.22, sin(a) * ring * cos(PI / n))), _shade(rng), _mossy)
			chest = Transform3D(Basis(), Vector3(0, deck_y + 0.08, 0.6))
		"stepped":
			# A small shrine on top: four short piers and the remains of a roof slab.
			var sh := minf(dw, dd) * 0.45
			var ph := rng.randf_range(1.8, 2.4)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var left := 1.0 if rng.randf() < 0.65 else rng.randf_range(0.3, 0.8)
					_block(kit, Vector3(0.7, ph * left, 0.7), Transform3D(Basis(), Vector3(sx * sh, deck_y + 0.08 + ph * left * 0.5, sz * sh)), _shade(rng), _mossy)
					_solid(Vector3(0.7, ph * left, 0.7), Transform3D(Basis(), Vector3(sx * sh, deck_y + 0.08 + ph * left * 0.5, sz * sh)))
			if rng.randf() < 0.6:
				_block(kit, Vector3(sh * 2.0 + 1.0, 0.4, sh * 1.2), Transform3D(Basis(Vector3.RIGHT, rng.randf_range(0.0, 0.12)), Vector3(0, deck_y + 0.08 + ph + 0.2, sh * 0.4)), _shade(rng), _mossy)
			chest = Transform3D(Basis(), Vector3(0, deck_y + 0.08, 0.0))
	# The altar the chest stands before, and the rubble that's come off it all.
	var altar := chest.origin + Vector3(0, 0, 1.0)
	_block(kit, Vector3(1.8, 0.9, 0.9), Transform3D(Basis(), altar + Vector3(0, 0.45, 0)), _stone.lightened(0.05), _mossy * 0.8)
	_solid(Vector3(1.8, 0.9, 0.9), Transform3D(Basis(), altar + Vector3(0, 0.45, 0)))
	_rubble(kit, rng, Vector2.ZERO, maxf(hw, hd) + 3.0, rng.randi_range(10, 18))
	_rubble(kit, rng, Vector2.ZERO, minf(dw, dd) - 0.5, rng.randi_range(3, 7), deck_y + 0.08)
	return chest


## Columns round the deck's edge (half widths cw, cd), most broken; lintels left where two still stand side by side.
func _colonnade(kit: MeshKit, rng: RandomNumberGenerator, cw: float, cd: float, y: float) -> void:
	var spacing := rng.randf_range(2.3, 3.0)
	var height := rng.randf_range(3.6, 5.2)
	var radius := rng.randf_range(0.28, 0.4)
	var nx := maxi(2, roundi(cw * 2.0 / spacing) + 1)
	var nz := maxi(2, roundi(cd * 2.0 / spacing) + 1)
	var spots: Array = []   # round the rectangle, in order
	for i in nx:
		spots.append(Vector3(lerpf(-cw, cw, float(i) / (nx - 1)), y, -cd))
	for j in range(1, nz):
		spots.append(Vector3(cw, y, lerpf(-cd, cd, float(j) / (nz - 1))))
	for i in range(nx - 2, -1, -1):
		spots.append(Vector3(lerpf(-cw, cw, float(i) / (nx - 1)), y, cd))
	for j in range(nz - 2, 0, -1):
		spots.append(Vector3(-cw, y, lerpf(-cd, cd, float(j) / (nz - 1))))
	var whole: Array = []
	for p: Vector3 in spots:
		var roll := rng.randf()
		var left := 1.0 if roll < 0.45 else (rng.randf_range(0.2, 0.85) if roll < 0.85 else (0.08 if roll < 0.93 else 0.0))
		if absf(p.x) < 1.6 and p.z < 0.0 and left > 0.0 and left < 1.0:
			left = 1.0 if rng.randf() < 0.5 else left   # the entrance tends to stand
		whole.append(_column(kit, rng, p, radius, height, left, y))
	for k in spots.size():
		var k2 := (k + 1) % spots.size()
		if whole[k] and whole[k2] and rng.randf() < 0.65:
			var a: Vector3 = spots[k]
			var b: Vector3 = spots[k2]
			var mid := (a + b) * 0.5
			var d := b - a
			_block(kit, Vector3(d.length() + radius * 2.4, 0.5, radius * 2.4), Transform3D(Basis(Vector3.UP, -atan2(d.z, d.x)), mid + Vector3(0, height + 0.25, 0)), _shade(rng), _mossy)


# --- Watchtowers --------------------------------------------------------------------------------

## A watchtower on a rise, round or square, a stair winding up its outside to a crenellated top. Returns where its
## chest stands (on the top).
func _tower(kit: MeshKit, dims: Vector2, rng: RandomNumberGenerator) -> Transform3D:
	var radius := dims.x
	var height := dims.y
	var round_body := rng.randf() < 0.6
	var span := _ground_span(radius + 1.6, radius + 1.6)
	var foot := span.x - 0.6
	var base := span.y + 0.5          # the top of the batter (the sloping skirt round its foot)
	var top := base + height          # the walk on top
	var core_col := Color(0.1, 0.09, 0.08).lerp(_stone, 0.25)   # what shows dark through a gap: the inside
	# The skirt: a wider, battered course from below the ground up to the base.
	if round_body:
		kit.add_primitive(MeshKit.cylinder(radius + 0.12, radius + 0.45, base - foot, 20), Transform3D(Basis(), Vector3(0, (base + foot) * 0.5, 0)), _stone.darkened(0.08), 0.0, 0.06)
	else:
		_block(kit, Vector3(radius * 2.0 + 0.6, base - foot, radius * 2.0 + 0.6), Transform3D(Basis(), Vector3(0, (base + foot) * 0.5, 0)), _stone.darkened(0.08), _mossy * 0.4)
	# The core (dark: it's what you see through a gap), with the facing stones round it.
	var core_r := radius - 0.32
	if round_body:
		kit.add_primitive(MeshKit.cylinder(core_r, core_r, top - base + 0.02, 16), Transform3D(Basis(), Vector3(0, (top + base) * 0.5, 0)), core_col, 0.0, 0.0)
	else:
		_block(kit, Vector3(core_r * 2.0, top - base + 0.02, core_r * 2.0), Transform3D(Basis(), Vector3(0, (top + base) * 0.5, 0)), core_col)
	var courses := int(height / COURSE)
	var door_a := rng.randf() * TAU                  # which way the door faces
	var bite_a := rng.randf() * TAU                  # where the top has crumbled away
	var bite_w := rng.randf_range(0.5, 1.2)
	var slits: Array = []
	for k in rng.randi_range(3, 6):
		slits.append([rng.randf() * TAU, rng.randi_range(4, courses - 4)])
	for row in courses:
		var y0 := base + row * COURSE
		var bite_depth := clampi(courses - row, 0, 99)
		if round_body:
			var n := maxi(8, roundi(TAU * radius / 0.85))
			var off := (0.5 if row % 2 == 1 else 0.0) * TAU / n
			for i in n:
				var a := off + TAU * i / n
				if _gap(a, row, courses, door_a, bite_a, bite_w, bite_depth, slits, rng):
					continue
				var arc := TAU * radius / n
				var p := Vector3(cos(a), 0, sin(a)) * (radius - 0.16)
				_block(kit, Vector3(0.36, COURSE - 0.02, arc * 1.04), Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, y0 + COURSE * 0.5, 0)), _shade(rng), _mossy * 0.35 if row == courses - 1 else 0.0)
		else:
			for side in 4:
				var s := -radius + (0.45 if row % 2 == 1 else 0.0)
				while s < radius - 0.05:
					var e := minf(s + rng.randf_range(0.6, 1.0), radius)
					if radius - e < 0.3:
						e = radius
					var mid := (s + e) * 0.5
					s = e
					var n2 := Vector2(0, -1).rotated(side * PI * 0.5)
					var t2 := Vector2(1, 0).rotated(side * PI * 0.5)
					var p2 := n2 * (radius - 0.16) + t2 * mid
					var a := atan2(p2.y, p2.x)
					if _gap(a, row, courses, door_a, bite_a, bite_w, bite_depth, slits, rng):
						continue
					_block(kit, Vector3(e - (mid * 2.0 - e) - 0.03, COURSE - 0.02, 0.36), Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(p2.x, y0 + COURSE * 0.5, p2.y)), _shade(rng), _mossy * 0.35 if row == courses - 1 else 0.0)
	# The body you bump into (and the top you stand on).
	if round_body:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = top - foot
		cs.shape = cyl
		cs.position = Vector3(0, (top + foot) * 0.5, 0)
		_shapes.add_child(cs)
	else:
		_solid(Vector3(radius * 2.0, top - foot, radius * 2.0), Transform3D(Basis(), Vector3(0, (top + foot) * 0.5, 0)))
	# The stair: stone treads stuck out of the wall, winding up from the foot to the top.
	var turn := 1.0 if rng.randf() < 0.5 else -1.0
	var rise := 0.28
	var tread_r := radius + 0.55
	# Along the outside, measured in metres (round the circle, or round the square's sides).
	var s0 := (door_a + turn * 0.9) * tread_r if round_body else _square_s(door_a + turn * 0.9, tread_r)
	var p0 := _tread_at(round_body, s0, tread_r)
	var ground0 := _gy(p0[0].x, p0[0].y)
	var steps := ceili((top - ground0) / rise)
	var end_a := 0.0
	for k in steps:
		var at: Array = _tread_at(round_body, s0 + turn * k * 0.44, tread_r)
		var p2: Vector2 = at[0]
		var out: Vector2 = at[1]
		end_a = atan2(p2.y, p2.x)
		var y := minf(ground0 + (k + 1) * rise, top)
		var g := _gy(p2.x, p2.y)
		var bottom := y - 0.3 if y - 0.3 > g + 0.6 else g - 0.3   # low ones are solid to the ground
		var xf := Transform3D(Basis(Vector3.UP, -atan2(out.y, out.x)), Vector3(p2.x, (y + bottom) * 0.5, p2.y))
		_block(kit, Vector3(1.1, y - bottom, 0.5), xf, _shade(rng), _mossy * 0.5)
		_solid(Vector3(1.1, y - bottom, 0.5), xf)
	var step_a := 0.44 / tread_r
	# Battlements round the top, open where the stair comes up (and fallen in places).
	var n3 := maxi(8, roundi(TAU * radius / 1.1))
	for i in n3:
		var a := TAU * i / n3
		if absf(angle_difference(a, end_a + turn * step_a)) < 0.55:
			continue   # the way in from the stair
		if absf(angle_difference(a, bite_a)) < bite_w * 0.6 or i % 2 == 1 or rng.randf() < 0.2:
			continue
		var p: Vector3
		if round_body:
			p = Vector3(cos(a), 0, sin(a)) * (radius - 0.2)
		else:
			var d := Vector2(cos(a), sin(a))
			d /= maxf(absf(d.x), absf(d.y))
			p = Vector3(d.x, 0, d.y) * (radius - 0.2)
		var h := rng.randf_range(0.6, 0.85)
		var xf := Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, top + h * 0.5, 0))
		_block(kit, Vector3(0.4, h, 0.75), xf, _shade(rng), _mossy)
		_solid(Vector3(0.4, h, 0.75), xf)
	# A cap of slabs on the walk (the core's top shows between), and what's fallen off it below.
	_block(kit, Vector3(core_r * (1.6 if round_body else 2.0), 0.08, core_r * (1.6 if round_body else 2.0)), Transform3D(Basis(Vector3.UP, rng.randf() * 0.3), Vector3(0, top + 0.04, 0)), _stone.lightened(0.04), _mossy * 0.7)
	_rubble(kit, rng, Vector2(cos(bite_a), sin(bite_a)) * (radius + 1.5), 2.5, rng.randi_range(6, 10))
	_rubble(kit, rng, Vector2.ZERO, radius + 3.5, rng.randi_range(4, 8))
	var chest_a := end_a + PI
	return Transform3D(Basis(Vector3.UP, -chest_a + PI * 0.5), Vector3(cos(chest_a), 0, sin(chest_a)) * radius * 0.35 + Vector3(0, top + 0.08, 0))


## A stair tread's place `s` metres round the outside of the tower (round: a circle of radius r; square: a square
## of half-size r), and the way out from the wall there: [Vector2 position, Vector2 outward].
func _tread_at(round_body: bool, s: float, r: float) -> Array:
	if round_body:
		var a := s / r
		return [Vector2(cos(a), sin(a)) * r, Vector2(cos(a), sin(a))]
	var side := 2.0 * r
	var u := fposmod(s, side * 4.0)
	var k := int(u / side)
	var t := u - k * side - r   # -r..r along the side
	# Sides in turn: +x, +z, -x, -z (going round counter-clockwise seen from above, like the angle).
	var outs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var o: Vector2 = outs[k]
	var along := Vector2(-o.y, o.x)
	return [o * r + along * t, o]


## How far round the square (see _tread_at) the point at angle `a` is.
func _square_s(a: float, r: float) -> float:
	var d := Vector2(cos(a), sin(a))
	d /= maxf(absf(d.x), absf(d.y))
	var k := 0
	if absf(d.x) >= absf(d.y):
		k = 0 if d.x > 0.0 else 2
	else:
		k = 1 if d.y > 0.0 else 3
	var outs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var o: Vector2 = outs[k]
	var along := Vector2(-o.y, o.x)
	return k * 2.0 * r + (d * r).dot(along) + r


## Whether a facing stone is left out: the doorway at the foot, arrow slits, and the crumbled bite out of the top.
func _gap(a: float, row: int, courses: int, door_a: float, bite_a: float, bite_w: float, from_top: int, slits: Array, rng: RandomNumberGenerator) -> bool:
	if row < 5 and absf(angle_difference(a, door_a)) < 0.28:
		return true
	for sl: Array in slits:
		if absf(angle_difference(a, float(sl[0]))) < 0.12 and (row == int(sl[1]) or row == int(sl[1]) + 1):
			return true
	var d := absf(angle_difference(a, bite_a))
	if d < bite_w and from_top <= roundi(4.0 * (1.0 - d / bite_w)) + 1:
		return true
	return row >= courses - 1 and rng.randf() < 0.12


# --- Cave vaults --------------------------------------------------------------------------------

## The cave vaults (planned with the caves: see Caves._dress): a square stone room built into a deep chamber, its
## doorway toward where you come in, piers at its corners, a dais at the back with a stone coffer, and two braziers
## of glowing crystal lighting it.
func build_vaults(vaults: Array) -> void:
	_mat = ArtStyle.painted({"brush_strength": 0.3, "rim_amount": 0.2})
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.55, 0.95, 1.0)
	for i in vaults.size():
		var at: Vector3 = vaults[i][0]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([Game.world_seed, "vault", i])
		_frame = Transform3D(Basis(Vector3.UP, float(vaults[i][1])), at)
		_stone = Color(0.5, 0.52, 0.56).lerp(Game.palette.rock, 0.3)
		_mossy = 0.0
		_shapes = StaticBody3D.new()
		_shapes.collision_layer = TerrainChunk.LAYER_SOLID
		_shapes.collision_mask = 0
		_shapes.transform = _frame
		add_child(_shapes)
		var kit := MeshKit.new(hash([Game.world_seed, "vault", i]))
		var h := Caves.VAULT_HALF
		var floor_y := 0.1
		# A footing under it all (the cave's floor is rough), and the flagstones on it.
		_block(kit, Vector3(h * 2.0 + 0.5, 0.9, h * 2.0 + 0.5), Transform3D(Basis(), Vector3(0, floor_y - 0.45 - 0.02, 0)), _stone.darkened(0.2))
		_solid(Vector3(h * 2.0 + 0.5, 0.9, h * 2.0 + 0.5), Transform3D(Basis(), Vector3(0, floor_y - 0.45, 0)))
		var n := 5
		var slab := (h * 2.0 - 0.6) / n
		for a in n:
			for b in n:
				if rng.randf() < 0.08:
					continue
				var p := Vector3(-h + 0.3 + slab * (a + 0.5), floor_y - 0.03, -h + 0.3 + slab * (b + 0.5))
				_block(kit, Vector3(slab - 0.05, 0.08, slab - 0.05), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), p), _stone.lightened(rng.randf_range(-0.04, 0.08)))
		# Walls round it, the doorway in the front (-z) one.
		var wall_h := 2.6
		_wall(kit, rng, Vector2(-h, h), Vector2(h, h), floor_y, wall_h, 0.5, [], 2.2, 0.35)
		_wall(kit, rng, Vector2(-h, -h), Vector2(-h, h), floor_y, wall_h, 0.5, [], 2.2, 0.35)
		_wall(kit, rng, Vector2(h, h), Vector2(h, -h), floor_y, wall_h, 0.5, [], 2.2, 0.35)
		_wall(kit, rng, Vector2(h, -h), Vector2(-h, -h), floor_y, wall_h, 0.5, [[h - 0.75, h + 0.75]], 2.1, 0.35)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx * (h - 0.6), floor_y + 1.45, sz * (h - 0.6))
				_block(kit, Vector3(0.55, 2.9, 0.55), Transform3D(Basis(), p), _shade(rng).darkened(0.05))
				_solid(Vector3(0.55, 2.9, 0.55), Transform3D(Basis(), p))
		# The dais and the coffer on it.
		var chest_at: Vector3 = Caves.VAULT_CHEST
		var dais := Vector3(0, (floor_y + chest_at.y) * 0.5, chest_at.z)
		_block(kit, Vector3(2.6, chest_at.y - floor_y, 1.5), Transform3D(Basis(), dais), _stone.lightened(0.04))
		_solid(Vector3(2.6, chest_at.y - floor_y, 1.5), Transform3D(Basis(), dais))
		_chest(kit, Transform3D(Basis(), chest_at), i, "vault_chest_%d" % i, true)
		# Braziers either side, heaped with glowing crystal, and the light they give.
		var glow := MeshKit.new(i + 31)
		for sx in [-1.0, 1.0]:
			var bp := Vector3(sx * 1.55, floor_y, chest_at.z - 0.2)
			kit.add_primitive(MeshKit.cylinder(0.16, 0.22, 0.7, 10), Transform3D(Basis(), bp + Vector3(0, 0.35, 0)), _stone.darkened(0.1), 0.0, 0.04)
			kit.add_primitive(MeshKit.cylinder(0.34, 0.2, 0.22, 12), Transform3D(Basis(), bp + Vector3(0, 0.81, 0)), _stone.darkened(0.05), 0.0, 0.04)
			_solid(Vector3(0.6, 0.92, 0.6), Transform3D(Basis(), bp + Vector3(0, 0.46, 0)))
			for k in 4:
				var a := TAU * k / 4.0 + rng.randf() * 0.5
				var tip := Vector3(cos(a) * 0.08, 0.28 + rng.randf() * 0.12, sin(a) * 0.08)
				glow.loft([bp + Vector3(cos(a) * 0.1, 0.88, sin(a) * 0.1), bp + Vector3(0, 0.88, 0) + tip], [0.06, 0.005], 5, Color.WHITE)
		var gm := MeshInstance3D.new()
		gm.mesh = glow.commit(glow_mat)
		gm.transform = _frame
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gm)
		var light := OmniLight3D.new()
		light.light_color = Color(0.55, 0.9, 1.0)
		light.light_energy = 1.3
		light.omni_range = 7.5
		light.shadow_enabled = false
		light.position = _frame * Vector3(0, 1.6, chest_at.z - 0.4)
		light.distance_fade_enabled = true   # (off when you're nowhere near)
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 15.0
		add_child(light)
		_rubble(kit, rng, Vector2(0, -h * 0.2), h * 0.7, rng.randi_range(2, 4), floor_y)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(_mat)
		mi.transform = _frame
		mi.visibility_range_end = 90.0
		add_child(mi)
		CaveShade.apply(mi, CaveShade.at(at + Vector3(0, 1.0, 0)))


# --- The chest ----------------------------------------------------------------------------------

## The ruin's chest: an old iron-bound box, at `xf` (frame). Interact opens it (see GameActions.open_cache).
func _chest(kit: MeshKit, xf: Transform3D, index: int, key := "", stone := false) -> void:
	var wood := Color(0.34, 0.24, 0.16) if not stone else _stone.lightened(0.08)
	var iron := Color(0.26, 0.25, 0.27) if not stone else Color(0.78, 0.64, 0.32)
	var b := xf.basis
	var o := xf.origin
	_part(kit, Vector3(1.0, 0.5, 0.62), Transform3D(b, o + b * Vector3(0, 0.25, 0)), wood)
	_part(kit, Vector3(1.04, 0.18, 0.66), Transform3D(b, o + b * Vector3(0, 0.59, 0)), wood.lightened(0.06))
	for x in [-0.36, 0.36]:
		_part(kit, Vector3(0.07, 0.7, 0.7), Transform3D(b, o + b * Vector3(x, 0.34, 0)), iron)
	_part(kit, Vector3(0.14, 0.18, 0.06), Transform3D(b, o + b * Vector3(0, 0.44, -0.34)), Color(0.72, 0.6, 0.3))
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_INTERACT | TerrainChunk.LAYER_SOLID
	body.collision_mask = 0
	body.transform = _frame * xf
	body.set_meta("loot_key", key if key != "" else "ruin_chest_%d" % index)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.04, 0.7, 0.68)
	cs.shape = box
	cs.position.y = 0.35
	body.add_child(cs)
	add_child(body)


func _part(kit: MeshKit, size: Vector3, xf: Transform3D, col: Color) -> void:
	kit.add_primitive(_box, Transform3D(xf.basis.scaled_local(size), xf.origin), col, 0.0, 0.04)
