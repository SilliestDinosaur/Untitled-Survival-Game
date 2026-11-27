class_name RuinModels
extends Node3D
## Builds the island's ruins (see Ruins): overgrown temples and watchtowers, each laid out and worn down its own way
## from its seed, so no two are alike. Real stone blocks in courses (not painted-on lines), moss on what faces the
## sky in damp country, rubble round about. One painted mesh each, box colliders for what you can stand on or bump
## into, and a chest (Interact: see GameActions.open_cache).
##
## Built in each ruin's own frame: x across, z back to front (the stair is at -z), y up from the ground at its middle.

const SEEN := 460.0

var _mat: Material
var _box := BoxMesh.new()   ## one unit box, scaled for every block (its arrays are made once)
var _stone := Color(0.66, 0.64, 0.58)
var _moss := Color(0.36, 0.48, 0.24)
var _mossy := 0.0           ## how much moss grows here (damp country) 0..1
var _frame := Transform3D()
var _ground := {}
var _shapes: StaticBody3D
# How this ruin was built (see _look): its material's courses and block lengths, rough or dressed, arched or
# lintelled doorways, round or square columns.
var _course := 0.5
var _blen := Vector2(0.6, 1.15)
var _rough := false
var _arch := false
var _round_cols := true


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
			# Mostly a walk-in complex of rooms and corridors; now and then an open temple on its plinth.
			chest = _temple(kit, ru.size, rng) if rng.randf() < 0.22 else _complex(kit, ru, rng)
		elif ru.get("fort", false):
			chest = _fort(kit, ru, rng)
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
	# What it was built of, and how.
	var dry := b in [WorldGen.Biome.DESERT, WorldGen.Biome.DRYLANDS, WorldGen.Biome.BADLANDS]
	var kinds := ["big", "big", "brick", "ashlar", "rubble"] if dry else ["ashlar", "ashlar", "rubble", "rubble", "big", "brick"]
	var kind: String = kinds[rng.randi() % kinds.size()]
	_rough = false
	match kind:
		"ashlar":   # dressed blocks
			_course = 0.5
			_blen = Vector2(0.6, 1.15)
		"rubble":   # rough stones, roughly coursed
			_course = 0.4
			_blen = Vector2(0.35, 0.75)
			_rough = true
			_stone = _stone.darkened(0.06)
		"big":      # great blocks
			_course = 0.62
			_blen = Vector2(0.95, 1.6)
		"brick":    # brick (mud brick in dry country)
			_course = 0.3
			_blen = Vector2(0.48, 0.62)
			_stone = Color(0.78, 0.62, 0.44) if dry else Color(0.62, 0.36, 0.27)
	_arch = rng.randf() < (0.7 if kind == "brick" else 0.45)
	_round_cols = rng.randf() < 0.6


# --- Helpers ------------------------------------------------------------------------------------

## The drawn ground's height at a point of the ruin's frame, in that frame.
func _gy(x: float, z: float) -> float:
	var w := _frame * Vector3(x, 0, z)
	return ChunkGenerator.surface_height(Game.world_gen, w.x, w.z, _ground) - _frame.origin.y


## Lowest and highest ground over a rectangle (half w by half d) of the frame.
func _ground_span(hw: float, hd: float, c := Vector2.ZERO) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for i in 7:
		for j in 7:
			var h := _gy(c.x + lerpf(-hw, hw, i / 6.0), c.y + lerpf(-hd, hd, j / 6.0))
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
		if _round_cols:
			kit.add_primitive(MeshKit.cylinder(r1 * 0.97, r0 * 0.97, h - 0.02, 12), Transform3D(Basis(), at + Vector3(0, h * 0.5, 0)),
				col.lightened(rng.randf_range(-0.04, 0.04)), 0.0, 0.05, null,
				func(p: Vector3) -> Color: return col.lerp(_moss, _mossy * 0.5) if p.y > h * 0.3 and d == drums - 1 and left < 1.0 else col)
		else:   # a square pier of stacked blocks
			_block(kit, Vector3(r0 * 1.85, h - 0.02, r0 * 1.85), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), at + Vector3(0, h * 0.5, 0)),
				col.lightened(rng.randf_range(-0.04, 0.04)), _mossy * 0.5 if d == drums - 1 and left < 1.0 else 0.0)
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
			var lie := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5), Vector3(p.x, py + radius * 0.8, p.z))
			if _round_cols:
				kit.add_primitive(MeshKit.cylinder(radius * 0.95, radius * 0.95, 0.85, 12), lie, col.darkened(0.04), 0.0, 0.05)
			else:
				_block(kit, Vector3(radius * 1.8, 0.85, radius * 1.8), lie, col.darkened(0.04))
	_solid(Vector3(radius * 1.8, y - foot.y + (0.3 if whole else 0.0), radius * 1.8), Transform3D(Basis(), foot + Vector3(0, (y - foot.y) * 0.5, 0)))
	return whole


## A wall of coursed blocks from a to b (frame xz), standing on `base_y`, up to `height` but ruined along its top
## (some stretches lower, a few gaps; `wear` 0 keeps it whole), with `openings` ([from, to] metres along it, up to
## `open_h`, or [from, to, height] of their own) left open: a lintel over them, or an arch (see _arch). Returns how
## high it still stands at its lowest (above base_y), for roofs.
func _wall(kit: MeshKit, rng: RandomNumberGenerator, a: Vector2, b: Vector2, base_y: float, height: float, thick: float,
		openings: Array, open_h := 2.2, wear := 1.0) -> float:
	var length := a.distance_to(b)
	if length < 0.2:
		return 0.0
	var dir := (b - a) / length
	var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x))
	var course := _course
	var courses := maxi(1, roundi(height / course))
	# The ruined top: how many courses still stand at each metre along it (smooth dips, the odd deep gap).
	var ph := rng.randf() * TAU
	var keep := func(s: float) -> int:
		var v := lerpf(1.0, 0.72 + 0.28 * sin(s * 0.9 + ph) + 0.15 * sin(s * 2.3 - ph * 1.7), wear)
		return clampi(roundi(courses * clampf(v, 0.15, 1.0)), 1, courses)
	var oh := func(o: Array) -> float: return float(o[2]) if o.size() > 2 else open_h
	for row in courses:
		var y0 := base_y + row * course
		var s := -rng.randf_range(_blen.x * 0.2, _blen.x * 0.7) if row % 2 == 1 else 0.0
		while s < length - 0.05:
			var s0 := maxf(s, 0.0)
			var s1 := minf(s0 + rng.randf_range(_blen.x, _blen.y), length)
			if length - s1 < _blen.x * 0.5:
				s1 = length
			s = s1
			var mid := (s0 + s1) * 0.5
			if row >= keep.call(mid):
				continue
			var open := false
			for o: Array in openings:
				var h_o: float = oh.call(o)
				if s1 > float(o[0]) and s0 < float(o[1]) and y0 < base_y + h_o:
					open = true
				elif _arch and h_o < 50.0:
					# Under the arch's curve: left out too (its voussoirs go there).
					var rr := (float(o[1]) - float(o[0])) * 0.5 + 0.05
					var dx := absf(mid - (float(o[0]) + float(o[1])) * 0.5)
					if dx < rr and y0 < base_y + h_o + sqrt(rr * rr - dx * dx) + 0.2:
						open = true
			if open:
				continue
			var top_row: bool = row == keep.call(mid) - 1
			var lift := rng.randf_range(-0.03, 0.03) if top_row else 0.0   # top stones a touch askew
			var p := a + dir * mid
			var turn := lift * 2.0 + (rng.randf_range(-0.05, 0.05) if _rough else 0.0)
			var depth := thick + (rng.randf_range(-0.06, 0.08) if _rough else 0.0)
			var xf := Transform3D(basis * Basis(Vector3.UP, turn), Vector3(p.x, y0 + course * 0.5 + lift, p.y))
			_block(kit, Vector3(s1 - s0 - 0.03, course - 0.02, depth), xf, _shade(rng), _mossy if top_row else 0.0)
	# Over the openings, if the wall still stands that high there: a lintel, or an arch of wedge stones.
	for o: Array in openings:
		var h_o: float = oh.call(o)
		if h_o > 50.0:
			continue   # a breach: open to the top
		var mid := (float(o[0]) + float(o[1])) * 0.5
		var p := a + dir * mid
		if _arch:
			var rr := (float(o[1]) - float(o[0])) * 0.5 + 0.05
			if keep.call(mid) * course > h_o + rr + 0.3:
				var n := 7
				for k in n:
					var th := PI * (k + 0.5) / n
					var at := p + dir * cos(th) * (rr + 0.17)
					var xf := Transform3D(basis * Basis(Vector3.BACK, th + PI * 0.5), Vector3(at.x, base_y + h_o + sin(th) * (rr + 0.17), at.y))
					_block(kit, Vector3(PI * rr / n * 1.12, 0.34, thick + 0.05), xf, _shade(rng).darkened(0.04), _mossy * 0.3)
		elif keep.call(mid) * course > h_o + course * 0.5:
			_block(kit, Vector3(float(o[1]) - float(o[0]) + 0.6, course * 0.8, thick + 0.04), Transform3D(basis, Vector3(p.x, base_y + h_o + course * 0.4, p.y)), _shade(rng).darkened(0.05), _mossy * 0.4)
	# Colliders: one box a metre along, as high as the wall stands there (none in the openings).
	var s2 := 0.0
	while s2 < length - 0.01:
		var e := minf(s2 + 1.0, length)
		var mid := (s2 + e) * 0.5
		var inside := -1.0
		for o: Array in openings:
			if mid > float(o[0]) and mid < float(o[1]):
				inside = oh.call(o)
		var h: float = keep.call(mid) * course
		var p := a + dir * mid
		if inside >= 0.0:
			if h > inside + course:
				_solid(Vector3(e - s2, h - inside, thick), Transform3D(basis, Vector3(p.x, base_y + inside + (h - inside) * 0.5, p.y)))
		else:
			_solid(Vector3(e - s2, h, thick), Transform3D(basis, Vector3(p.x, base_y + h * 0.5, p.y)))
		s2 = e
	var lowest := float(courses)
	var t := 0.0
	while t <= length:
		lowest = minf(lowest, keep.call(t))
		t += 0.5
	return lowest * course


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


# --- Walk-in complexes ---------------------------------------------------------------------------

## A ruined complex you walk into (its floor plan: see Ruins._floor_plan): on a low platform, rooms of different
## sizes behind walls with doorways, corridors (some still roofed, dark inside), sometimes a courtyard ringed with
## columns, sometimes a stair up to a roof terrace; columns in the big rooms, rubble everywhere. Returns where its
## chest stands: in the room furthest from the way in, or up on the terrace.
func _complex(kit: MeshKit, ru: Dictionary, rng: RandomNumberGenerator) -> Transform3D:
	var plan: Dictionary = Ruins.design("temple", int(ru.seed)).plan
	var cell: float = plan.cell
	var nx: int = plan.nx
	var nz: int = plan.nz
	var grid: Array = plan.grid
	var rooms: Array = plan.rooms
	var open: Dictionary = plan.open
	var entrance: Vector2i = plan.entrance
	var court: int = plan.court
	var stair_room: int = plan.stair
	var wide := nx * cell
	var deep := nz * cell
	var hw := wide * 0.5 + 1.0
	var hd := deep * 0.5 + 1.0
	var span := _ground_span(hw, hd)
	var floor_y := span.y + rng.randf_range(0.3, 0.8)
	var wall_h := rng.randf_range(2.8, 4.4)
	var thick := rng.randf_range(0.5, 0.75)
	var door_w := rng.randf_range(1.2, 1.7)
	var door_h := minf(wall_h - 0.7, rng.randf_range(2.1, 2.5))
	var wear := rng.randf_range(0.45, 1.0)
	var occ := func(i: int, j: int) -> int:
		return 0 if i < 0 or j < 0 or i >= nx or j >= nz else int(grid[j * nx + i])
	var at := func(i: float, j: float) -> Vector2: return Vector2(-wide * 0.5 + i * cell, -deep * 0.5 + j * cell)   # grid point (corner) i, j
	# The platform it all stands on, and the steps up to its way in.
	_plinth(kit, rng, hw, hd, floor_y, span.x - 0.5)
	var door_x: float = (at.call(entrance.x + 0.5, 0) as Vector2).x
	_steps(kit, rng, Vector2(door_x, -hd), Vector2(0, -1), door_w + 1.0, floor_y)
	# Floors: flagstones in the rooms and corridors (some gone), sparser in the courtyard and out in the open.
	for j in nz:
		for i in nx:
			var g: int = occ.call(i, j)
			var keep := 0.85 if g >= 1 and g != court + 2 else 0.45
			var c: Vector2 = at.call(i + 0.5, j + 0.5)
			for a in 2:
				for b in 2:
					if rng.randf() > keep:
						continue
					var p := c + Vector2((a - 0.5) * cell * 0.5, (b - 0.5) * cell * 0.5)
					_block(kit, Vector3(cell * 0.5 - 0.06, 0.08, cell * 0.5 - 0.06), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(p.x, floor_y + 0.04, p.y)),
						_stone.lightened(rng.randf_range(-0.04, 0.09)), _mossy * rng.randf_range(0.2, 0.9))
	# The walls, edge by edge of the grid: round the outside of what's built, between rooms and corridors, with
	# doorways where the plan goes through. The stair room's walls stand whole (its terrace rests on them).
	var tops := {}   # edge key -> how high its wall still stands
	var walls_at := {}   # grid point -> walls meeting there (for the piers)
	var stair_rect: Rect2i = rooms[stair_room] if stair_room >= 0 else Rect2i()
	for axis in 2:
		for j in (nz if axis == 0 else nz + 1):
			for i in (nx + 1 if axis == 0 else nx):
				var a := Vector2i(i - 1, j) if axis == 0 else Vector2i(i, j - 1)
				var b := Vector2i(i, j)
				var ga: int = occ.call(a.x, a.y)
				var gb: int = occ.call(b.x, b.y)
				if ga == 0 and gb == 0:
					continue
				if ga == gb and ga >= 2:
					continue   # inside one room
				var key := Vector3i(mini(a.x, b.x), mini(a.y, b.y), axis)
				var court_edge := (ga == court + 2 or gb == court + 2) and (ga == 0 or gb == 0)
				if court_edge:
					continue   # the courtyard's open side: columns instead (below)
				var through := open.has(key)
				if ga == 1 and gb == 1 and through:
					continue   # along a corridor
				var outside := ga == 0 or gb == 0
				var door := through or (axis == 1 and j == 0 and i == entrance.x)
				var p0: Vector2 = at.call(i, j)
				var p1: Vector2 = at.call(i, j + 1) if axis == 0 else at.call(i + 1, j)
				var dir := (p1 - p0).normalized()
				var q0 := p0 + dir * thick * 0.5
				var q1 := p1 - dir * thick * 0.5
				var len := q0.distance_to(q1)
				var ops: Array = [[len * 0.5 - door_w * 0.5, len * 0.5 + door_w * 0.5]] if door else []
				var by_stairs := stair_room >= 0 and (ga == stair_room + 2 or gb == stair_room + 2)
				var h := wall_h if outside or by_stairs else wall_h * rng.randf_range(0.85, 1.0)
				tops[key] = _wall(kit, rng, q0, q1, floor_y + 0.08, h, thick, ops, door_h, 0.0 if by_stairs else wear)
				for v: Vector2i in [Vector2i(i, j), Vector2i(i, j + 1) if axis == 0 else Vector2i(i + 1, j)]:
					walls_at[v] = minf(float(walls_at.get(v, 99.0)), float(tops[key]))
	# Piers where walls meet, hiding the joints.
	for v: Vector2i in walls_at:
		var p: Vector2 = at.call(v.x, v.y)
		var h := minf(float(walls_at[v]) + 0.2, wall_h + 0.2)
		_block(kit, Vector3(thick + 0.16, h, thick + 0.16), Transform3D(Basis(), Vector3(p.x, floor_y + 0.08 + h * 0.5, p.y)), _shade(rng).darkened(0.05), _mossy)
		_solid(Vector3(thick + 0.16, h, thick + 0.16), Transform3D(Basis(), Vector3(p.x, floor_y + 0.08 + h * 0.5, p.y)))
	# Roofs: slabs still lying over some corridor cells, where both walls along them stand high enough.
	for j in nz:
		for i in nx:
			if occ.call(i, j) != 1 or rng.randf() > 0.55:
				continue
			var pair := [Vector3i(i, j, 0), Vector3i(i + 1, j, 0)]
			if not (tops.has(pair[0]) and tops.has(pair[1])):
				pair = [Vector3i(i, j, 1), Vector3i(i, j + 1, 1)]
			if not (tops.has(pair[0]) and tops.has(pair[1])):
				continue
			var top := minf(float(tops[pair[0]]), float(tops[pair[1]]))
			if top < door_h + 0.4:
				continue
			var c: Vector2 = at.call(i + 0.5, j + 0.5)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), Vector3(c.x, floor_y + 0.08 + top + 0.15, c.y))
			_block(kit, Vector3(cell + thick * 0.6, 0.3, cell + thick * 0.6), xf, _shade(rng), _mossy)
			_solid(Vector3(cell + thick * 0.6, 0.3, cell + thick * 0.6), xf)
	# Columns: rows down the big rooms; round the courtyard's open side.
	var col_r := rng.randf_range(0.26, 0.36)
	for ri in rooms.size():
		var r: Rect2i = rooms[ri]
		if ri == court:
			for j in range(r.position.y, r.end.y + 1):
				for i in range(r.position.x, r.end.x + 1):
					if i > r.position.x and i < r.end.x and j > r.position.y and j < r.end.y:
						continue   # (its middle stays open)
					var p: Vector2 = at.call(i, j)
					var inset := (Vector2(r.position + r.end) * 0.5 - Vector2(i, j)).sign() * 0.6
					p += inset
					_column(kit, rng, Vector3(p.x, floor_y + 0.08, p.y), col_r, wall_h + 0.3, 1.0 if rng.randf() < 0.45 else rng.randf_range(0.15, 0.85), floor_y + 0.08)
			if rng.randf() < 0.6:   # a basin in the middle
				var c: Vector2 = at.call((r.position.x + r.end.x) * 0.5, (r.position.y + r.end.y) * 0.5)
				for k in 8:
					var a := TAU * k / 8.0
					_block(kit, Vector3(0.45, 0.55, 0.62), Transform3D(Basis(Vector3.UP, -a), Vector3(c.x + cos(a) * 1.0, floor_y + 0.35, c.y + sin(a) * 1.0)), _shade(rng), _mossy)
				_solid(Vector3(2.4, 0.6, 2.4), Transform3D(Basis(), Vector3(c.x, floor_y + 0.35, c.y)))
		elif ri != stair_room and r.size.x >= 2 and r.size.y >= 2:
			for j in range(r.position.y + 1, r.end.y):
				for i in range(r.position.x + 1, r.end.x):
					var p: Vector2 = at.call(i, j)
					_column(kit, rng, Vector3(p.x, floor_y + 0.08, p.y), col_r, wall_h, 1.0 if rng.randf() < 0.5 else rng.randf_range(0.0, 0.8), floor_y + 0.08)
	# The chest: in the room furthest from the way in, before an altar; or up on the terrace.
	var deep_r: Rect2i = rooms[plan.deep]
	var dc: Vector2 = at.call((deep_r.position.x + deep_r.end.x) * 0.5, (deep_r.position.y + deep_r.end.y) * 0.5)
	var chest := Transform3D(Basis(), Vector3(dc.x, floor_y + 0.08, dc.y - 0.5))
	if stair_room >= 0:
		var up := _terrace(kit, rng, stair_rect, at, cell, thick, floor_y + 0.08, roundi(wall_h / _course) * _course)
		if plan.deep == stair_room or rng.randf() < 0.5:
			chest = up
	if chest.origin.y < floor_y + 1.0:
		var altar := chest.origin + Vector3(0, 0, 1.0)
		_block(kit, Vector3(1.6, 0.85, 0.8), Transform3D(Basis(), altar + Vector3(0, 0.42, 0)), _stone.lightened(0.05), _mossy * 0.8)
		_solid(Vector3(1.6, 0.85, 0.8), Transform3D(Basis(), altar + Vector3(0, 0.42, 0)))
	_rubble(kit, rng, Vector2.ZERO, maxf(hw, hd) + 3.0, rng.randi_range(10, 20))
	_rubble(kit, rng, Vector2.ZERO, minf(hw, hd) - 1.0, rng.randi_range(6, 14), floor_y + 0.08)
	return chest


## A stair room's roof terrace: a stair up along one long wall inside it, and slabs over the rest (an opening above
## the stair). Returns where a chest stands on top.
func _terrace(kit: MeshKit, rng: RandomNumberGenerator, r: Rect2i, at: Callable, cell: float, thick: float, floor_y: float, wall_h: float) -> Transform3D:
	var lo: Vector2 = at.call(r.position.x, r.position.y) + Vector2(thick * 0.5, thick * 0.5)
	var hi: Vector2 = at.call(r.end.x, r.end.y) - Vector2(thick * 0.5, thick * 0.5)
	var along_x := hi.x - lo.x >= hi.y - lo.y
	var length := (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var top := wall_h
	var steps := ceili(top / 0.3)
	var run := minf(0.42, (length - 0.6) / steps)
	var width := 1.1
	# The stair, against the room's low-side wall, climbing from one end.
	for k in steps:
		var y := minf((k + 1) * top / steps, top)
		var d := 0.3 + (k + 0.5) * run
		var p := Vector2(lo.x + d, lo.y + width * 0.5) if along_x else Vector2(lo.x + width * 0.5, lo.y + d)
		var size := Vector3(run + 0.01, y, width) if along_x else Vector3(width, y, run + 0.01)
		var xf := Transform3D(Basis(), Vector3(p.x, floor_y + y * 0.5, p.y))
		_block(kit, size, xf, _shade(rng), _mossy * 0.4)
		_solid(size, xf)
	# The terrace: everything but the strip over the stair (its first part, where you come up through).
	var well := 0.3 + steps * run   # how far along the opening reaches
	var y_top := floor_y + top
	var pieces: Array = []   # [centre, size] in the frame's xz
	if along_x:
		pieces.append([Vector2((lo.x + hi.x) * 0.5, (lo.y + width + hi.y) * 0.5), Vector2(hi.x - lo.x, hi.y - lo.y - width)])
		pieces.append([Vector2((lo.x + well + hi.x) * 0.5, lo.y + width * 0.5), Vector2(hi.x - lo.x - well, width)])
	else:
		pieces.append([Vector2((lo.x + width + hi.x) * 0.5, (lo.y + hi.y) * 0.5), Vector2(hi.x - lo.x - width, hi.y - lo.y)])
		pieces.append([Vector2(lo.x + width * 0.5, (lo.y + well + hi.y) * 0.5), Vector2(width, hi.y - lo.y - well)])
	for pc: Array in pieces:
		var sz: Vector2 = pc[1]
		if sz.x < 0.3 or sz.y < 0.3:
			continue
		var c: Vector2 = pc[0]
		var xf := Transform3D(Basis(), Vector3(c.x, y_top + 0.15, c.y))
		_block(kit, Vector3(sz.x + thick * 0.5, 0.3, sz.y + thick * 0.5), xf, _stone.lightened(0.03), _mossy)
		_solid(Vector3(sz.x + thick * 0.5, 0.3, sz.y + thick * 0.5), xf)
	var far := Vector2(hi.x - 1.2, (lo.y + hi.y) * 0.5 + 0.4) if along_x else Vector2((lo.x + hi.x) * 0.5 + 0.4, hi.y - 1.2)
	return Transform3D(Basis(), Vector3(far.x, y_top + 0.3, far.y))


## A low platform (half wide hw, half deep hd), its top at `top`, reaching down to `bottom`: a core with a kerb of
## blocks round its edge.
func _plinth(kit: MeshKit, rng: RandomNumberGenerator, hw: float, hd: float, top: float, bottom: float) -> void:
	_block(kit, Vector3(hw * 2.0 - 0.3, top - bottom, hd * 2.0 - 0.3), Transform3D(Basis(), Vector3(0, (top + bottom) * 0.5, 0)), _stone.darkened(0.16), _mossy * 0.3)
	_solid(Vector3(hw * 2.0, top - bottom, hd * 2.0), Transform3D(Basis(), Vector3(0, (top + bottom) * 0.5, 0)))
	for side in 4:
		var along := hw if side % 2 == 0 else hd
		var across := hd if side % 2 == 0 else hw
		var s := -along
		while s < along - 0.05:
			var e := minf(s + rng.randf_range(_blen.x, _blen.y) * 1.2, along)
			if along - e < 0.4:
				e = along
			var mid := (s + e) * 0.5
			var len := e - s
			s = e
			if rng.randf() < 0.08:
				continue   # a block gone
			var h := minf(_course * 2.0, top - bottom)
			var p := Vector3(mid, top - h * 0.5 + 0.03, -across + 0.2) if side % 2 == 0 else Vector3(-across + 0.2, top - h * 0.5 + 0.03, mid)
			if side >= 2:
				p = Vector3(-p.x, p.y, -p.z)
			var size := Vector3(len - 0.04, h, 0.46) if side % 2 == 0 else Vector3(0.46, h, len - 0.04)
			_block(kit, size, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), p), _shade(rng), _mossy)


## Steps from the ground up to `top_y`, ending at `edge` (frame xz) and running out along `out`, `width` wide.
func _steps(kit: MeshKit, rng: RandomNumberGenerator, edge: Vector2, out: Vector2, width: float, top_y: float) -> void:
	var ground := _gy(edge.x + out.x * 1.5, edge.y + out.y * 1.5)
	var rise := 0.27
	var steps := ceili((top_y - ground) / rise)
	var side := Vector2(-out.y, out.x)
	for k in steps:
		var y := minf(ground + (k + 1) * rise, top_y)
		var p := edge + out * ((steps - 1 - k + 0.5) * 0.42)
		var a := p + side * width * 0.5
		var b := p - side * width * 0.5
		var bottom := minf(_gy(a.x, a.y), _gy(b.x, b.y)) - 0.3
		var basis := Basis(Vector3.UP, -atan2(side.y, side.x))
		var xf := Transform3D(basis, Vector3(p.x, (y + bottom) * 0.5, p.y))
		_block(kit, Vector3(width, y - bottom, 0.43), xf, _shade(rng), _mossy * 0.7)
		_solid(Vector3(width, y - bottom, 0.43), xf)


# --- Forts --------------------------------------------------------------------------------------

## A ruined fort: towers round a courtyard (the first, the keep, taller, with its stair and the chest on top),
## curtain walls between them, breached here and there, a gate in the front one; a well in the yard, rubble. Its
## layout comes from Ruins.design. Returns where the chest stands.
func _fort(kit: MeshKit, ru: Dictionary, rng: RandomNumberGenerator) -> Transform3D:
	var des := Ruins.design("tower", int(ru.seed))
	var towers: Array = des.towers
	var n := towers.size()
	var wall_h := rng.randf_range(3.5, 5.5)
	var thick := rng.randf_range(0.9, 1.3)
	var chest := Transform3D()
	# The gate goes in whichever wall faces the front (-z) most.
	var gate := 0
	var best := 1e9
	for k in n:
		var m: Vector2 = ((towers[k][0] as Vector2) + (towers[(k + 1) % n][0] as Vector2)) * 0.5
		if m.y < best:
			best = m.y
			gate = k
	for k in n:
		var ta: Array = towers[k]
		var tb: Array = towers[(k + 1) % n]
		var a: Vector2 = ta[0]
		var b: Vector2 = tb[0]
		var dir := (b - a).normalized()
		var p0 := a + dir * (float(ta[1]) - 0.3)
		var p1 := b - dir * (float(tb[1]) - 0.3)
		var lo := 1e9
		var hi := -1e9
		for t in 9:
			var q := p0.lerp(p1, t / 8.0)
			var g := _gy(q.x, q.y)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		var base := lo - 0.4
		var len := p0.distance_to(p1)
		var ops: Array = []
		if k == gate:
			var gm := len * 0.5
			ops.append([gm - 1.3, gm + 1.3, (_gy(p0.lerp(p1, 0.5).x, p0.lerp(p1, 0.5).y) - base) + 3.0])
		elif rng.randf() < 0.5:
			var at := rng.randf_range(1.0, maxf(len - 3.0, 1.2))
			ops.append([at, at + rng.randf_range(1.5, 3.0), 99.0])   # a breach, open to the top
		_wall(kit, rng, p0, p1, base, (hi - base) + wall_h, thick, ops, 2.4, rng.randf_range(0.4, 0.8))
	for k in n:
		var t: Array = towers[k]
		var res := _tower(kit, Vector2(t[1], t[2]), rng, t[0], k == 0 or rng.randf() < 0.3, 1 if t[3] else 0)
		if k == 0:
			_rubble(kit, rng, Vector2.ZERO, float(des.span) * 0.7, rng.randi_range(8, 16))
			if rng.randf() < 0.6:   # a well in the yard
				var w := Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
				var g := _gy(w.x, w.y)
				for kk in 8:
					var a := TAU * kk / 8.0
					_block(kit, Vector3(0.4, 0.8, 0.55), Transform3D(Basis(Vector3.UP, -a), Vector3(w.x + cos(a) * 0.85, g + 0.3, w.y + sin(a) * 0.85)), _shade(rng), _mossy)
				kit.add_primitive(MeshKit.cylinder(0.7, 0.7, 0.1, 12), Transform3D(Basis(), Vector3(w.x, g + 0.15, w.y)), Color(0.05, 0.05, 0.06), 0.0, 0.0)
				_solid(Vector3(2.1, 0.8, 2.1), Transform3D(Basis(), Vector3(w.x, g + 0.3, w.y)))
			chest = res
	return chest


# --- Watchtowers --------------------------------------------------------------------------------

## A watchtower on a rise, round or square, a stair winding up its outside to a crenellated top. Returns where its
## chest stands (on the top).
func _tower(kit: MeshKit, dims: Vector2, rng: RandomNumberGenerator, c := Vector2.ZERO, with_stair := true, shape := -1) -> Transform3D:
	var radius := dims.x
	var height := dims.y
	var round_body := rng.randf() < 0.6 if shape < 0 else shape == 1
	var o3 := Vector3(c.x, 0, c.y)
	var span := _ground_span(radius + 1.6, radius + 1.6, c)
	var foot := span.x - 0.6
	var base := span.y + 0.5          # the top of the batter (the sloping skirt round its foot)
	var top := base + height          # the walk on top
	var core_col := Color(0.1, 0.09, 0.08).lerp(_stone, 0.25)   # what shows dark through a gap: the inside
	# The skirt: a wider, battered course from below the ground up to the base.
	if round_body:
		kit.add_primitive(MeshKit.cylinder(radius + 0.12, radius + 0.45, base - foot, 20), Transform3D(Basis(), o3 + Vector3(0, (base + foot) * 0.5, 0)), _stone.darkened(0.08), 0.0, 0.06)
	else:
		_block(kit, Vector3(radius * 2.0 + 0.6, base - foot, radius * 2.0 + 0.6), Transform3D(Basis(), o3 + Vector3(0, (base + foot) * 0.5, 0)), _stone.darkened(0.08), _mossy * 0.4)
	# The core (dark: it's what you see through a gap), with the facing stones round it.
	var core_r := radius - 0.32
	if round_body:
		kit.add_primitive(MeshKit.cylinder(core_r, core_r, top - base + 0.02, 16), Transform3D(Basis(), o3 + Vector3(0, (top + base) * 0.5, 0)), core_col, 0.0, 0.0)
	else:
		_block(kit, Vector3(core_r * 2.0, top - base + 0.02, core_r * 2.0), Transform3D(Basis(), o3 + Vector3(0, (top + base) * 0.5, 0)), core_col)
	var course := _course
	var courses := int(height / course)
	var door_a := rng.randf() * TAU                  # which way the door faces
	var bite_a := rng.randf() * TAU                  # where the top has crumbled away
	var bite_w := rng.randf_range(0.5, 1.2)
	var slits: Array = []
	for k in rng.randi_range(3, 6):
		slits.append([rng.randf() * TAU, rng.randi_range(4, maxi(courses - 4, 5))])
	for row in courses:
		var y0 := base + row * course
		var bite_depth := clampi(courses - row, 0, 99)
		if round_body:
			var n := maxi(8, roundi(TAU * radius / ((_blen.x + _blen.y) * 0.5)))
			var off := (0.5 if row % 2 == 1 else 0.0) * TAU / n
			for i in n:
				var a := off + TAU * i / n
				if _gap(a, row, courses, door_a, bite_a, bite_w, bite_depth, slits, rng):
					continue
				var arc := TAU * radius / n
				var p := Vector3(cos(a), 0, sin(a)) * (radius - 0.16)
				_block(kit, Vector3(0.36, course - 0.02, arc * 1.04), Transform3D(Basis(Vector3.UP, -a), o3 + p + Vector3(0, y0 + course * 0.5, 0)), _shade(rng), _mossy * 0.35 if row == courses - 1 else 0.0)
		else:
			for side in 4:
				var s := -radius + (_blen.x * 0.6 if row % 2 == 1 else 0.0)
				while s < radius - 0.05:
					var e := minf(s + rng.randf_range(_blen.x, _blen.y), radius)
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
					_block(kit, Vector3(e - (mid * 2.0 - e) - 0.03, course - 0.02, 0.36), Transform3D(Basis(Vector3.UP, -side * PI * 0.5), o3 + Vector3(p2.x, y0 + course * 0.5, p2.y)), _shade(rng), _mossy * 0.35 if row == courses - 1 else 0.0)
	# The body you bump into (and the top you stand on).
	if round_body:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = top - foot
		cs.shape = cyl
		cs.position = o3 + Vector3(0, (top + foot) * 0.5, 0)
		_shapes.add_child(cs)
	else:
		_solid(Vector3(radius * 2.0, top - foot, radius * 2.0), Transform3D(Basis(), o3 + Vector3(0, (top + foot) * 0.5, 0)))
	# The stair: stone treads stuck out of the wall, winding up from the foot to the top.
	var turn := 1.0 if rng.randf() < 0.5 else -1.0
	var rise := 0.28
	var tread_r := radius + 0.55
	# Along the outside, measured in metres (round the circle, or round the square's sides).
	var s0 := (door_a + turn * 0.9) * tread_r if round_body else _square_s(door_a + turn * 0.9, tread_r)
	var p0 := _tread_at(round_body, s0, tread_r)
	var ground0 := _gy(c.x + p0[0].x, c.y + p0[0].y)
	var steps := ceili((top - ground0) / rise) if with_stair else 0
	var end_a := door_a + PI
	for k in steps:
		var at: Array = _tread_at(round_body, s0 + turn * k * 0.44, tread_r)
		var p2: Vector2 = at[0]
		var out: Vector2 = at[1]
		end_a = atan2(p2.y, p2.x)
		var y := minf(ground0 + (k + 1) * rise, top)
		var g := _gy(c.x + p2.x, c.y + p2.y)
		var bottom := y - 0.3 if y - 0.3 > g + 0.6 else g - 0.3   # low ones are solid to the ground
		var xf := Transform3D(Basis(Vector3.UP, -atan2(out.y, out.x)), o3 + Vector3(p2.x, (y + bottom) * 0.5, p2.y))
		_block(kit, Vector3(1.1, y - bottom, 0.5), xf, _shade(rng), _mossy * 0.5)
		_solid(Vector3(1.1, y - bottom, 0.5), xf)
	var step_a := 0.44 / tread_r
	# Battlements round the top, open where the stair comes up (and fallen in places).
	var n3 := maxi(8, roundi(TAU * radius / 1.1))
	for i in n3:
		var a := TAU * i / n3
		if with_stair and absf(angle_difference(a, end_a + turn * step_a)) < 0.55:
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
		var xf := Transform3D(Basis(Vector3.UP, -a), o3 + p + Vector3(0, top + h * 0.5, 0))
		_block(kit, Vector3(0.4, h, 0.75), xf, _shade(rng), _mossy)
		_solid(Vector3(0.4, h, 0.75), xf)
	# A cap of slabs on the walk (the core's top shows between), and what's fallen off it below.
	_block(kit, Vector3(core_r * (1.6 if round_body else 2.0), 0.08, core_r * (1.6 if round_body else 2.0)), Transform3D(Basis(Vector3.UP, rng.randf() * 0.3), o3 + Vector3(0, top + 0.04, 0)), _stone.lightened(0.04), _mossy * 0.7)
	_rubble(kit, rng, c + Vector2(cos(bite_a), sin(bite_a)) * (radius + 1.5), 2.5, rng.randi_range(6, 10))
	_rubble(kit, rng, c, radius + 3.5, rng.randi_range(4, 8))
	var chest_a := end_a + PI
	return Transform3D(Basis(Vector3.UP, -chest_a + PI * 0.5), o3 + Vector3(cos(chest_a), 0, sin(chest_a)) * radius * 0.35 + Vector3(0, top + 0.08, 0))


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
