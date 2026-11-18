class_name StructureModels
extends RefCounted
## Models for placed stations (campfire, workbench, forge), built like the item models from
## lofts, bevelled boards and lumpy faceted stones. Each has a body mesh plus an optional "glow"
## mesh (embers, coals) drawn with an emissive material, and a point for the light.

const WOOD := Color(0.56, 0.41, 0.27)
const WOOD_DARK := Color(0.4, 0.28, 0.18)
const BARK := Color(0.4, 0.29, 0.2)
const ROPE := Color(0.74, 0.64, 0.42)
const IRON := Color(0.32, 0.32, 0.36)
const ASH := Color(0.28, 0.26, 0.25)

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()
	_extents.clear()


# --- Wall joints ----------------------------------------------------------------------------
# Wall pieces stand on cell edges and reach the cell's corners. Where walls at right angles meet, the
# taller one (or the east-west one, if they're the same height) runs through the corner and the other
# stops flush against its face: a butt joint, so no two walls fill the same corner.

static var _extents := {}   # material -> Vector2(min, max) of a wall's thickness along its own z


## Every wall piece's corners: Vector3i(level, x, z) (in decimetres) -> the pieces that end there.
static func corner_index(structures: Dictionary) -> Dictionary:
	var out := {}
	for id: String in structures:
		var st: Dictionary = structures[id]
		if not st.kind in GameActions.EDGE_KINDS:
			continue
		for corner: Vector3 in _wall_corners(st):
			var key := _corner_key(st, corner)
			if not out.has(key):
				out[key] = []
			out[key].append(st)
	return out


## How far a wall piece's left and right ends reach past (+) or stop short of (-) its corners; see get_model.
static func wall_ends(st: Dictionary, index: Dictionary) -> Vector2:
	var out := Vector2.ZERO
	var axis := _axis(st)
	var corners := _wall_corners(st)
	for e in 2:
		var at: Array = index.get(_corner_key(st, corners[e]), [])
		var same: Array = []    # walls in line with this one, ending here
		var cross: Array = []   # walls at right angles, ending here
		for o: Dictionary in at:
			if o.id == st.id:
				continue
			if absf(_axis(o).dot(axis)) > 0.5:
				same.append(o)
			else:
				cross.append(o)
		if cross.is_empty():
			continue
		var mine := _height(st.kind)
		for o: Dictionary in same:
			mine = maxf(mine, _height(o.kind))
		var theirs := 0.0
		for o: Dictionary in cross:
			theirs = maxf(theirs, _height(o.kind))
		var runs_through := mine > theirs + 0.01 or (absf(mine - theirs) <= 0.01 and absf(axis.x) > 0.5)
		# The band the crossing walls fill, as distances along this wall from the corner.
		var lo := INF
		var hi := -INF
		for o: Dictionary in cross:
			var ext := _extent(o.kind)
			var s := (Basis(Vector3.UP, float(o.get("yaw", 0.0))) * Vector3.BACK).dot(axis)
			lo = minf(lo, minf(s * ext.x, s * ext.y))
			hi = maxf(hi, maxf(s * ext.x, s * ext.y))
		var right := e == 1
		if runs_through:
			if same.is_empty():   # walls in line through the corner already fill it between them
				out[e] = hi if right else lo
		else:
			out[e] = lo if right else hi
	return out


## The piece's two corners in world space: left (its -x end), then right.
static func _wall_corners(st: Dictionary) -> Array:
	var p: Array = st.pos
	var pos := Vector3(p[0], p[1], p[2])
	var half := _axis(st) * GameActions.CELL * 0.5
	return [pos - half, pos + half]


## The direction a wall piece runs along (its own +x), in world space.
static func _axis(st: Dictionary) -> Vector3:
	return Basis(Vector3.UP, float(st.get("yaw", 0.0))) * Vector3.RIGHT


static func _corner_key(st: Dictionary, corner: Vector3) -> Vector3i:
	return Vector3i(int(st.get("level", 0)), roundi(corner.x * 10.0), roundi(corner.z * 10.0))


static func _height(kind: String) -> float:
	return 1.0 if kind in GameActions.HALF_KINDS else GameActions.WALL_H


## A wall's solid face, as a range along its own z, measured once per material from a plain wall. A plank wall's
## rails stand proud of its boards and are left out: walls meet board to board, and the rails cross at the corner.
static func _extent(kind: String) -> Vector2:
	var mat: String = GameActions.PIECES[kind].mat
	if not _extents.has(mat):
		var k := MeshKit.new(1)
		_edge(k, mat, 1.0, [], RandomNumberGenerator.new(), -0.5, 0.5, false)
		var aabb := k.commit(StandardMaterial3D.new()).get_aabb()
		_extents[mat] = Vector2(aabb.position.z, aabb.end.z)
	return _extents[mat]


## {body: ArrayMesh, glow: ArrayMesh or null, light: Vector3 (local), radius: float (collision)}
## `ends` (wall pieces only): how far the left and right ends reach past (+) or stop short of (-) the cell's corners,
## for butt joints with the walls they meet (see wall_ends).
static func get_model(kind: String, material: Material, glow_material: Material, ends := Vector2.ZERO) -> Dictionary:
	var key := kind + str(material.get_instance_id())
	if ends != Vector2.ZERO:
		key += "|%d|%d" % [roundi(ends.x * 1000.0), roundi(ends.y * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	if GameActions.is_building(kind):
		var parts := _build_piece(kind, ends)
		var door_kit: MeshKit = parts.door
		var piece := {"body": (parts.body as MeshKit).commit(material), "glow": null, "light": Vector3(0, 1, 0), "radius": 1.0,
			"door": door_kit.commit(material) if door_kit != null else null}
		_cache[key] = piece
		return piece
	var k := MeshKit.new(hash(kind))
	var g := MeshKit.new(hash(kind) + 1)
	var light := Vector3(0, 0.5, 0)
	var radius := 0.6
	var stone: Color = Game.palette.rock
	match kind:
		"campfire":
			_campfire(k, g, stone)
			light = Vector3(0, 0.45, 0)
			radius = 0.55
		"workbench":
			_workbench(k)
			light = Vector3.ZERO
			radius = 0.8
		"forge":
			_forge(k, g, stone)
			light = Vector3(0, 0.55, -0.45)
			radius = 0.85
	var out := {"body": k.commit(material), "glow": g.commit(glow_material) if not g.is_empty() else null,
		"light": light, "radius": radius}
	_cache[key] = out
	return out


## A board with bevelled edges: size x (length), y (width), z (thickness), centered on xf.
static func _board(k: MeshKit, size: Vector3, xf: Transform3D, col: Color, wobble := 0.0) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var outline := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy + wobble), Vector2(hx, hy), Vector2(-hx, hy - wobble)])
	k.extrude(outline, xf, size.z, minf(size.z, size.y) * 0.25, col, col.lightened(0.12), 0.55)


## ---- Building pieces --------------------------------------------------------------------
## A piece is a shape (floor, wall, half wall, window, doorway, door, stairs, roof) in a material
## (brick, wood or stone); GameActions.PIECES says which. Every one is built from the same parts: a
## mortar core, courses of bricks or stones (or boards), and timber or iron fittings.

const MORTAR := Color(0.7, 0.67, 0.61)
const STONE_MORTAR := Color(0.36, 0.36, 0.38)
const GLASS := Color(0.7, 0.82, 0.86)
const DOOR_W := 0.7     ## half the width of a doorway
const DOOR_H := 2.3     ## height of a doorway's opening


## {body: MeshKit, door: MeshKit or null}. A door's panel is its own mesh, hinged at its left edge.
static func _build_piece(kind: String, ends := Vector2.ZERO) -> Dictionary:
	var spec: Dictionary = GameActions.PIECES[kind]
	var shape: String = spec.shape
	var mat: String = spec.mat
	var k := MeshKit.new(hash(kind))
	var door: MeshKit = null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var opening := Rect2(-DOOR_W, 0.0, DOOR_W * 2.0, DOOR_H)
	var x0 := -GameActions.CELL * 0.5 + ends.x
	var x1 := GameActions.CELL * 0.5 + ends.y
	match shape:
		"floor":
			_floor(k, mat, rng)
		"wall":
			_edge(k, mat, GameActions.WALL_H, [], rng, x0, x1)
		"half":
			_edge(k, mat, 1.0, [], rng, x0, x1)
		"window":
			_edge(k, mat, GameActions.WALL_H, [Rect2(-0.55, 1.0, 1.1, 1.0)], rng, x0, x1)
			_window_fittings(k)
		"doorway":
			_edge(k, mat, GameActions.WALL_H, [opening], rng, x0, x1)
			_door_fittings(k)
		"door":
			_edge(k, mat, GameActions.WALL_H, [opening], rng, x0, x1)
			_door_fittings(k)
			door = MeshKit.new(hash(kind) + 3)
			_door_panel(door, mat, rng)
		"stairs":
			_stairs(k, mat)
		"roof":
			_roof(k, mat, rng)
	return {"body": k, "door": door}


static func _mat_colour(mat: String) -> Color:
	match mat:
		"brick":
			return ItemDB.info("brick").color
		"wood":
			return WOOD
	return Game.palette.rock


## Floors: a bed of mortar, then blocks, pavers or planks laid on it.
static func _floor(k: MeshKit, mat: String, rng: RandomNumberGenerator) -> void:
	var h := GameActions.CELL * 0.5
	if mat == "wood":
		# Planks laid across three beams on a dark sill; the top is level with a stone floor's top.
		for z in [-1.0, 0.0, 1.0]:
			_board(k, Vector3(GameActions.CELL, 0.26, 0.2), Transform3D(Basis(), Vector3(0, -0.07, z)), WOOD_DARK)
		var pw := GameActions.CELL / 12.0
		for i in 12:
			var z := -h + pw * (i + 0.5)
			_board(k, Vector3(GameActions.CELL, pw - 0.03, 0.14), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.27, z)),
				WOOD.lightened(rng.randf_range(-0.05, 0.06)), rng.randf_range(-0.005, 0.005))
		return
	var bed := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var mortar := MORTAR.darkened(0.12) if mat == "brick" else STONE_MORTAR
	k.sculpt(bed, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), func(_p: Vector2) -> float: return 0.42,
		func(_p: Vector2, _t: float) -> Color: return mortar, 0, 0.05)
	var n := 3 if mat == "stone" else 6
	var step := GameActions.CELL / n
	var base := _mat_colour(mat)
	for iz in n:
		for ix in n:
			var bx := -h + step * (ix + 0.5) + rng.randf_range(-0.02, 0.02)
			var bz := -h + step * (iz + 0.5) + rng.randf_range(-0.02, 0.02)
			var hw := step * 0.5 - (0.035 if mat == "stone" else 0.03) + rng.randf_range(-0.01, 0.01)
			var outline := _rounded_rect(hw, hw, 0.07 if mat == "stone" else 0.03, 3)
			var block := base.lightened(rng.randf_range(-0.07, 0.05))
			var face := func(p: Vector2, _t: float) -> Color:
				return block.darkened(0.1) if fposmod(p.x * 5.0 + p.y * 3.0, 1.0) < 0.04 else block
			var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(bx, 0.12 if mat == "stone" else 0.24, bz))
			var thick := 0.44 if mat == "stone" else 0.2
			k.sculpt(outline, xf, func(_p: Vector2) -> float: return thick + rng.randf_range(-0.01, 0.01), face, 1, 0.04 if mat == "stone" else 0.02)


## Walls, half walls and the wall around an opening: a mortar core split round the openings, then the
## courses of bricks, stones or boards on its face.
## The wall runs from x0 to x1 along its own x (the cell's corners are at -CELL/2 and CELL/2).
static func _edge(k: MeshKit, mat: String, height: float, openings: Array, rng: RandomNumberGenerator, x0: float, x1: float,
		rails := true) -> void:
	var core := MORTAR
	if mat == "stone":
		core = STONE_MORTAR
	elif mat == "wood":
		core = WOOD_DARK.darkened(0.2)
	# Boards are thin, so their core is too: a thick core would hide them behind its face.
	var core_thick := 0.06 if mat == "wood" else 0.2
	for r: Rect2 in _core_rects(height, openings, x0, x1):
		k.sculpt(_rect_outline(r), Transform3D(), func(_p: Vector2) -> float: return core_thick,
			func(_p: Vector2, _t: float) -> Color: return core, 0, 0.06)
	match mat:
		"brick":
			_brick_courses(k, height, openings, rng, x0, x1)
		"stone":
			_stone_courses(k, height, openings, rng, x0, x1)
		_:
			_wood_boards(k, height, openings, rng, x0, x1, rails)


## The mortar core as rectangles covering the wall except the openings. Each band of the wall is cut
## by the openings that cross it; bands overlap a little so no two pieces share an edge.
static func _core_rects(height: float, openings: Array, x0: float, x1: float) -> Array:
	var ys: Array = [0.0, height]
	for o: Rect2 in openings:
		ys.append(o.position.y)
		ys.append(o.end.y)
	ys.sort()
	var out: Array = []
	for i in ys.size() - 1:
		var ya: float = ys[i]
		var yb: float = ys[i + 1]
		if yb - ya < 0.001:
			continue
		var gaps: Array = []
		for o: Rect2 in openings:
			if o.position.y <= ya + 0.001 and o.end.y >= yb - 0.001:
				gaps.append(Vector2(o.position.x, o.end.x))
		gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var x := x0
		for g: Vector2 in gaps:
			if g.x > x:
				out.append(Rect2(x, ya, g.x - x, yb - ya))
			x = maxf(x, g.y)
		if x < x1:
			out.append(Rect2(x, ya, x1 - x, yb - ya))
	for i in out.size():
		var r: Rect2 = out[i]
		var grow := 0.02 if r.end.y < height - 0.001 else 0.0
		out[i] = Rect2(r.position, r.size + Vector2(0.0, grow))
	return out


static func _rect_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Whether a unit of the wall would sit in an opening (a little margin so none pokes into one).
static func _hits(r: Rect2, openings: Array) -> bool:
	for o: Rect2 in openings:
		if o.grow(0.03).intersects(r):
			return true
	return false


static func _brick_courses(k: MeshKit, height: float, openings: Array, rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var h := GameActions.CELL * 0.5
	var bw := 0.5
	var bh := 0.25
	var base := _mat_colour("brick")
	for row in int(round(height / bh)):
		var y0 := row * bh
		# The bond is laid from the cell's corner, so it carries on unbroken where a wall runs past a corner.
		var x := -h - (bw * 0.5 if row % 2 == 1 else 0.0)
		while x > x0:
			x -= bw
		while x < x1:
			# Bricks stop a joint short of the wall's ends, so their end faces never share a plane with the core's.
			var bx0 := maxf(x + 0.015, x0 + 0.015)
			var bx1 := minf(x + bw - 0.015, x1 - 0.015)
			x += bw
			if bx1 - bx0 < 0.15:
				continue
			if _hits(Rect2(bx0, y0, bx1 - bx0, bh), openings):
				continue
			var b := base.lightened(rng.randf_range(-0.07, 0.05))
			var face := func(p: Vector2, _t: float) -> Color:
				return b.darkened(0.12) if p.y < -bh * 0.5 + 0.045 or p.y > bh * 0.5 - 0.045 else b
			var outline := _rounded_rect((bx1 - bx0) * 0.5, bh * 0.5 - 0.015, 0.025, 2)
			k.sculpt(outline, Transform3D(Basis(), Vector3((bx0 + bx1) * 0.5, y0 + bh * 0.5, 0.07)),
				func(_p: Vector2) -> float: return 0.22, face, 1, 0.03)


static func _stone_courses(k: MeshKit, height: float, openings: Array, rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var rh := 0.5
	var base := _mat_colour("stone")
	for row in maxi(1, int(round(height / rh))):
		var y0 := row * rh
		var x := x0 - (rng.randf_range(0.1, 0.35) if row % 2 == 1 else 0.0)
		while x < x1 - 0.05:
			var sx0 := maxf(x, x0)
			var sx1 := minf(sx0 + rng.randf_range(0.5, 0.85), x1)
			if x1 - sx1 < 0.35:
				sx1 = x1
			x = sx1
			if sx1 - sx0 < 0.15 or _hits(Rect2(sx0, y0, sx1 - sx0, rh), openings):
				continue
			var s := base.lightened(rng.randf_range(-0.08, 0.06))
			var face := func(p: Vector2, _t: float) -> Color:
				return s.darkened(0.12) if absf(p.x) > (sx1 - sx0) * 0.5 - 0.06 or absf(p.y) > rh * 0.5 - 0.06 else s
			k.sculpt(_rounded_rect((sx1 - sx0) * 0.5 - 0.012, rh * 0.5 - 0.012, 0.07, 2),
				Transform3D(Basis(), Vector3((sx0 + sx1) * 0.5, y0 + rh * 0.5, 0.09)),
				func(_p: Vector2) -> float: return 0.26, face, 1, 0.025)


## Boards standing between a bottom and a top rail. Rails and boards stop short where an opening crosses them.
static func _wood_boards(k: MeshKit, height: float, openings: Array, rng: RandomNumberGenerator, x0: float, x1: float,
		rails := true) -> void:
	var lo := 0.1
	var hi := height - 0.1
	for ry in ([lo, hi] if rails else []):
		var segs: Array = [[x0 + 0.01, x1 - 0.01]]   # rails stop just short of the ends, clear of the core's end faces
		for o: Rect2 in openings:
			if o.position.y < ry + 0.1 and o.end.y > ry - 0.1:
				segs = _subtract(segs, o.position.x, o.end.x)
		for sg: Array in segs:
			var len: float = sg[1] - sg[0]
			if len < 0.05:
				continue
			k.add_primitive(_box(Vector3(len, 0.2, 0.26)), Transform3D(Basis(), Vector3((sg[0] + sg[1]) * 0.5, ry, 0.0)), WOOD_DARK, 0.0, 0.03)
	# Boards on a 0.2 m grid from the cell's corner; narrower boards fill any end that runs past the grid.
	var cols: Array = []
	for i in range(ceili((x0 + 1.4 + 0.082) / 0.2), floori((x1 + 1.4 - 0.082) / 0.2) + 1):
		cols.append([-1.4 + i * 0.2, 0.092])
	if not cols.is_empty():
		var left: float = cols[0][0] - 0.1 - x0
		var right: float = x1 - (cols[-1][0] + 0.1)
		if left > 0.03:
			cols.push_front([x0 + left * 0.5, left * 0.5 - 0.008])
		if right > 0.03:
			cols.append([x1 - right * 0.5, right * 0.5 - 0.008])
	for col: Array in cols:
		var bx: float = col[0]
		var bhw: float = col[1]
		var off := rng.randf_range(-0.01, 0.01)
		var segs: Array = [[lo, hi]]
		for o: Rect2 in openings:
			if bx + bhw > o.position.x and bx - bhw < o.end.x:
				segs = _subtract(segs, o.position.y, o.end.y)
		for sg: Array in segs:
			var ln: float = sg[1] - sg[0]
			if ln < 0.1:
				continue
			var board := WOOD.lightened(rng.randf_range(-0.05, 0.06))
			var grain := func(p: Vector2, _t: float) -> Color:
				return board.darkened(0.08) if fposmod(p.y * 6.0 + sin(p.x * 30.0), 1.0) < 0.08 else board
			k.sculpt(_rounded_rect(bhw, ln * 0.5, minf(0.02, bhw * 0.5), 1), Transform3D(Basis(), Vector3(bx, (sg[0] + sg[1]) * 0.5 + off, 0.0)),
				func(_p: Vector2) -> float: return 0.08, grain, 1, 0.02)


## What is left of [a, b] segments once the cut (c, d) is taken out of them.
static func _subtract(segs: Array, c: float, d: float) -> Array:
	var out: Array = []
	for sg: Array in segs:
		var s0: float = sg[0]
		var s1: float = sg[1]
		if d <= s0 or c >= s1:
			out.append([s0, s1])
			continue
		if c > s0:
			out.append([s0, c])
		if d < s1:
			out.append([d, s1])
	return out


## The frame round a doorway: two posts and a lintel.
static func _door_fittings(k: MeshKit) -> void:
	for side in [-1.0, 1.0]:
		k.add_primitive(_box(Vector3(0.12, DOOR_H, 0.26)), Transform3D(Basis(), Vector3(side * DOOR_W, DOOR_H * 0.5, 0.0)), WOOD_DARK, 0.0, 0.03)
	k.add_primitive(_box(Vector3(DOOR_W * 2.0 + 0.24, 0.12, 0.26)), Transform3D(Basis(), Vector3(0.0, DOOR_H, 0.0)), WOOD_DARK, 0.0, 0.03)


## A window's timber frame, its mullion and the pane.
static func _window_fittings(k: MeshKit) -> void:
	var lo := 1.0
	var hi := 2.0
	var wx := 0.55
	_board(k, Vector3(wx * 2.0 + 0.3, 0.12, 0.16), Transform3D(Basis(), Vector3(0, lo - 0.02, 0.1)), WOOD_DARK)
	_board(k, Vector3(wx * 2.0 + 0.3, 0.12, 0.16), Transform3D(Basis(), Vector3(0, hi + 0.02, 0.1)), WOOD_DARK)
	for side in [-1.0, 1.0]:
		_board(k, Vector3(0.1, hi - lo, 0.16), Transform3D(Basis(), Vector3(side * (wx + 0.03), (lo + hi) * 0.5, 0.1)), WOOD_DARK)
	_board(k, Vector3(0.06, hi - lo, 0.04), Transform3D(Basis(), Vector3(0, (lo + hi) * 0.5, 0.1)), WOOD_DARK)
	_board(k, Vector3(wx * 2.0 + 0.04, hi - lo + 0.04, 0.03), Transform3D(Basis(), Vector3(0, (lo + hi) * 0.5, 0.06)), GLASS)


## A plank door, hinged at x = 0 (the hinge side), with iron straps and a latch.
static func _door_panel(door: MeshKit, mat: String, rng: RandomNumberGenerator) -> void:
	var planks := WOOD_DARK.lightened(0.05) if mat == "stone" else WOOD.lightened(0.02)
	var w := DOOR_W * 2.0 - 0.04
	var hgt := DOOR_H - 0.06
	for i in 6:
		var pw := w / 6.0
		door.add_primitive(_box(Vector3(pw - 0.02, hgt, 0.06)), Transform3D(Basis(), Vector3(pw * (i + 0.5), 0.03 + hgt * 0.5, 0.0)),
			planks.lightened(rng.randf_range(-0.04, 0.04)), 0.0, 0.03)
	for yb in [0.35, 1.85]:
		door.add_primitive(_box(Vector3(w, 0.12, 0.08)), Transform3D(Basis(), Vector3(w * 0.5, yb, 0.0)), WOOD_DARK, 0.0, 0.03)
		door.add_primitive(_box(Vector3(0.5, 0.05, 0.1)), Transform3D(Basis(), Vector3(0.25, yb, 0.0)), IRON, 0.0, 0.03)
	door.add_primitive(_box(Vector3(0.05, 0.14, 0.06)), Transform3D(Basis(), Vector3(w - 0.12, 1.1, 0.07)), IRON, 0.0, 0.03)


## Twelve steps climbing one storey, from the floor's top to the next floor's top, running out along -Z.
static func _stairs(k: MeshKit, mat: String) -> void:
	var col := _mat_colour(mat)
	var rise := GameActions.STACK_H / GameActions.STAIR_STEPS
	var run := GameActions.CELL / GameActions.STAIR_STEPS
	for i in GameActions.STAIR_STEPS:
		var top := GameActions.FLOOR_TOP + (i + 1) * rise
		var zc := GameActions.CELL * 0.5 - (i + 0.5) * run
		# Each tread overlaps the next by a hair, so no two faces lie exactly on each other.
		k.add_primitive(_box(Vector3(GameActions.CELL - 0.04, top, run + 0.02)), Transform3D(Basis(), Vector3(0, top * 0.5, zc)),
			col.lightened(0.05 * float(i % 2)), 0.0, 0.04)
		k.add_primitive(_box(Vector3(GameActions.CELL - 0.04, 0.025, run * 0.7)), Transform3D(Basis(), Vector3(0, top + 0.012, zc)),
			col.lightened(0.16), 0.0, 0.02)


## A roof of overlapping tiles over a 3 m square, with a beam round the edge. Brick is clay, wood
## shingles, stone slates.
static func _roof(k: MeshKit, mat: String, rng: RandomNumberGenerator) -> void:
	var h := GameActions.CELL * 0.5
	var tile: Color
	var hx: float
	var hy: float
	var pz: float
	var px: float
	match mat:
		"wood":
			tile = Color(0.46, 0.32, 0.22); hx = 0.18; hy = 0.12; pz = 0.22; px = 0.36
		"stone":
			tile = Color(0.4, 0.42, 0.47); hx = 0.22; hy = 0.14; pz = 0.28; px = 0.44
		_:
			tile = Color(0.62, 0.34, 0.26); hx = 0.24; hy = 0.16; pz = 0.3; px = 0.5
	var frame := tile.darkened(0.3) if mat == "stone" else WOOD_DARK
	# A solid deck under the tiles: tiles have rounded corners, so on their own they leave holes to the sky.
	k.add_primitive(_box(Vector3(GameActions.CELL - 0.004, 0.05, GameActions.CELL - 0.004)), Transform3D(), frame.darkened(0.1), 0.0, 0.03)
	# Rows and columns run right to the cell's edges (the last ones pulled in to fit), so neighbouring roofs meet.
	var rows := ceili((GameActions.CELL - 2.0 * hy) / pz) + 1
	for row in rows:
		var tz := minf(-h + hy + row * pz, h - hy)
		for col in int(GameActions.CELL / px) + 2:
			var tx := -h + hx + col * px + (px * 0.5 if row % 2 == 1 else 0.0)
			if tx - hx > h - 0.01:
				continue
			tx = minf(tx, h - hx)
			var t := tile.lightened(rng.randf_range(-0.06, 0.06))
			var face := func(p: Vector2, _t: float) -> Color: return t.darkened(0.15) if p.y < -hy * 0.6 else t
			# Tiles are nudged off a regular grid so their edges never line up exactly.
			var jitter := Vector2(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.004, 0.004))
			k.sculpt(_rounded_rect(hx, hy, hx * 0.3, 1), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx + jitter.x, 0.03 + row * 0.004, tz + jitter.y)),
				func(_p: Vector2) -> float: return 0.06, face, 1, 0.045)
	# Edge beams inside the cell (a neighbouring roof's beams sit beside them, not in the same place), the short pair
	# fitted between the long pair so no two beams overlap.
	for side in [-1.0, 1.0]:
		k.add_primitive(_box(Vector3(GameActions.CELL - 0.004, 0.16, 0.14)), Transform3D(Basis(), Vector3(0, -0.04, side * (h - 0.072))), frame, 0.0, 0.03)
		k.add_primitive(_box(Vector3(0.14, 0.16, GameActions.CELL - 0.29)), Transform3D(Basis(), Vector3(side * (h - 0.072), -0.04, 0)), frame, 0.0, 0.03)


## A rounded rectangle outline (half sizes hx, hy; corner radius r; segments per corner).
static func _rounded_rect(hx: float, hy: float, r: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [Vector2(hx - r, hy - r), Vector2(-hx + r, hy - r), Vector2(-hx + r, -hy + r), Vector2(hx - r, -hy + r)]
	for ci in 4:
		var c: Vector2 = corners[ci]
		var a0 := ci * PI * 0.5
		for s in seg + 1:
			var a := a0 + (PI * 0.5) * s / float(seg)
			out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _stone(k: MeshKit, at: Vector3, r: float, col: Color, rng: RandomNumberGenerator) -> void:
	var sc := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.6, 0.85), rng.randf_range(0.9, 1.2))
	k.add_primitive(MeshKit.sphere(r, 9, 6), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(sc), at),
		col.lightened(rng.randf_range(-0.1, 0.12)), r * 0.3, 0.06)


static func _campfire(k: MeshKit, g: MeshKit, stone: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	k.flat_shading = true
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.1, 0.1)
		_stone(k, Vector3(cos(a) * 0.48, 0.05, sin(a) * 0.48), rng.randf_range(0.09, 0.12), stone, rng)
	k.flat_shading = false
	# Ash bed
	k.add_primitive(MeshKit.cylinder(0.38, 0.42, 0.04, 20), Transform3D(Basis(), Vector3(0, 0.0, 0)), ASH, 0.0, 0.08)
	# Teepee of split logs leaning together, charred toward the middle.
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var foot := Vector3(cos(a) * 0.34, 0.02, sin(a) * 0.34)
		var top := Vector3(cos(a) * 0.04, 0.5, sin(a) * 0.04)
		var path := []
		var radii := []
		for s in 6:
			var t := s / 5.0
			path.append(foot.lerp(top, t))
			radii.append(lerpf(0.042, 0.03, t))
		k.loft(path, radii, 9, BARK, func(t: float, _a: float) -> Color: return BARK.lerp(Color(0.12, 0.1, 0.09), smoothstep(0.35, 0.9, t)),
			Callable(), true, true, 0.006)
	# Glowing embers among the logs.
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.18)
		g.add_primitive(MeshKit.sphere(rng.randf_range(0.035, 0.06), 7, 5),
			Transform3D(Basis.from_scale(Vector3(1.2, 0.6, 1.0)), Vector3(cos(a) * r, 0.04, sin(a) * r)),
			Color(1.0, rng.randf_range(0.35, 0.55), 0.15), 0.01, 0.15)


static func _workbench(k: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top_y := 0.82
	# Tabletop: four planks side by side with slightly different tones.
	for i in 4:
		var z := -0.36 + i * 0.24
		_board(k, Vector3(1.5, 0.22, 0.06), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, top_y, z)),
			WOOD.lightened(rng.randf_range(-0.06, 0.06)), rng.randf_range(-0.01, 0.01))
	# Legs, splayed slightly, with a stretcher frame lower down.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := Vector3(sx * 0.68, 0.0, sz * 0.4)
			var head := Vector3(sx * 0.6, top_y - 0.03, sz * 0.34)
			k.loft([foot, foot.lerp(head, 0.5), head], [0.05, 0.045, 0.045], 8, WOOD_DARK,
				Callable(), func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.8))
	for sz in [-1.0, 1.0]:
		_board(k, Vector3(1.3, 0.08, 0.05), Transform3D(Basis(), Vector3(0, 0.25, sz * 0.38)), WOOD_DARK)
	_board(k, Vector3(0.75, 0.08, 0.05), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.64, 0.25, 0)), WOOD_DARK)
	_board(k, Vector3(0.75, 0.08, 0.05), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.64, 0.25, 0)), WOOD_DARK)
	# Lower shelf with a couple of logs on it.
	_board(k, Vector3(1.2, 0.7, 0.04), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.29, 0)), WOOD_DARK.lightened(0.05))
	for i in 2:
		var z := -0.12 + i * 0.22
		k.loft([Vector3(-0.45, 0.37, z), Vector3(0.45, 0.37, z)], [0.07, 0.07], 12, BARK, Callable(), Callable(), true, true, 0.006)
	# Tools lying on the top: a mallet and a coil of rope.
	var y := top_y + 0.035
	k.loft([Vector3(0.25, y + 0.02, -0.15), Vector3(0.6, y + 0.02, -0.05)], [0.016, 0.014], 8, WOOD)
	k.loft([Vector3(0.6, y + 0.05, -0.13), Vector3(0.6, y + 0.05, 0.03)], [0.05, 0.05], 12, WOOD_DARK.lightened(0.1))
	for i in 3:
		var r := 0.09 - i * 0.012
		var ring := []
		var rr := []
		for s in 17:
			var a := TAU * s / 16.0
			ring.append(Vector3(-0.45 + cos(a) * r, y + 0.015 + i * 0.012, 0.15 + sin(a) * r))
			rr.append(0.014)
		k.loft(ring, rr, 6, ROPE.darkened(i * 0.06), Callable(), Callable(), false, false, 0.0, true)
	# A vise block on the front edge.
	_board(k, Vector3(0.16, 0.14, 0.1), Transform3D(Basis(), Vector3(-0.55, top_y + 0.05, 0.5)), WOOD_DARK)
	k.loft([Vector3(-0.55, top_y + 0.05, 0.5), Vector3(-0.55, top_y + 0.05, 0.68)], [0.012, 0.012], 8, IRON)


static func _forge(k: MeshKit, g: MeshKit, stone: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var mortar := stone.darkened(0.25)
	# Base: a rounded hearth of mortared stone, built up course by course.
	k.add_primitive(MeshKit.cylinder(0.6, 0.72, 0.85, 18), Transform3D(Basis(), Vector3(0, 0.42, 0)), mortar, 0.03, 0.08)
	k.flat_shading = true
	for course in 4:
		var y := 0.1 + course * 0.22
		var r := 0.72 - course * 0.04
		var count := 11 - course
		for i in count:
			var a := TAU * (i + (course % 2) * 0.5) / count
			if course >= 1 and absf(angle_difference(a, -PI * 0.5)) < 0.45:
				continue   # the mouth of the forge faces forward (-Z)
			_stone(k, Vector3(cos(a) * r, y, sin(a) * r), rng.randf_range(0.12, 0.15), stone, rng)
	k.flat_shading = false
	# Chimney: a tapering stone stack with a darker lip.
	var path := []
	var radii := []
	for i in 7:
		var t := i / 6.0
		path.append(Vector3(0, 0.85 + t * 1.15, 0.08 * t))
		radii.append(lerpf(0.5, 0.22, pow(t, 0.7)))
	var chimney_col := func(t: float, a: float) -> Color:
		var band := fposmod(t * 9.0 + sin(a * 3.0) * 0.2, 1.0) < 0.14
		return mortar.darkened(0.15) if band or t > 0.93 else mortar.lightened(0.08 * sin(a * 5.0 + t * 11.0))
	k.loft(path, radii, 14, mortar.lightened(0.05), chimney_col, Callable(), true, true, 0.02)
	# Mouth: dark recess with glowing coals.
	k.add_primitive(MeshKit.sphere(0.3, 14, 8), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.6)), Vector3(0, 0.55, -0.48)), Color(0.16, 0.08, 0.05), 0.0, 0.02)
	for i in 9:
		g.add_primitive(MeshKit.sphere(rng.randf_range(0.05, 0.08), 7, 5),
			Transform3D(Basis(), Vector3(rng.randf_range(-0.18, 0.18), 0.4 + rng.randf_range(0.0, 0.06), -0.66 + rng.randf_range(-0.05, 0.05))),
			Color(1.0, rng.randf_range(0.3, 0.55), 0.1), 0.012, 0.15)
	# Anvil on a stump beside it.
	var ax := Vector3(0.95, 0, -0.2)
	k.loft([ax, ax + Vector3(0, 0.45, 0)], [0.2, 0.18], 14, BARK, func(t: float, _a: float) -> Color: return BARK if t < 0.98 else WOOD, Callable(), true, true, 0.008)
	var anvil := PackedVector2Array([Vector2(-0.24, 0.0), Vector2(-0.1, 0.02), Vector2(-0.08, 0.14), Vector2(-0.22, 0.17), Vector2(-0.3, 0.2),
		Vector2(0.18, 0.2), Vector2(0.3, 0.17), Vector2(0.12, 0.13), Vector2(0.09, 0.02), Vector2(0.2, 0.0)])
	k.extrude(anvil, Transform3D(Basis(Vector3.UP, 0.3), ax + Vector3(0, 0.45, 0)), 0.13, 0.025, IRON, IRON.lightened(0.35), 0.4)
	# Tongs leaning on the hearth.
	for s in [-1.0, 1.0]:
		k.loft([Vector3(-0.75 + s * 0.02, 0.0, -0.15), Vector3(-0.6, 0.75, -0.25)], [0.012, 0.01], 6, IRON)
