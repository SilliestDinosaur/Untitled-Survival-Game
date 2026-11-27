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
## The placed pieces' own materials (set by Structures): the build ghost and the wheel's preview use the very same
## (prebuilt) meshes with a material of their own laid over them, instead of building every model a second time.
static var shared_material: Material
static var shared_glow: Material


## A piece's model for showing with a material of its own over it (the ghost, the preview): the shared one.
static func shared_model(kind: String, fallback: Material) -> Dictionary:
	if shared_material:
		return get_model(kind, shared_material, shared_glow)
	return get_model(kind, fallback, fallback)


static func clear_cache() -> void:
	_cache.clear()
	_roof_cache.clear()
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


## {body: ArrayMesh, glow: ArrayMesh or null, light: Vector3 (local), radius: float (collision)}; building pieces also
## have door and glass (ArrayMesh or null: a door's swinging panel, a window's see-through pane).
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
		var glass_kit: MeshKit = parts.glass
		var glow_kit: MeshKit = parts.get("glow")
		var d: Dictionary = GameActions.DECOR.get(kind, {})
		var piece := {"body": (parts.body as MeshKit).commit(material),
			"glow": glow_kit.commit(glow_material) if glow_kit != null and not glow_kit.is_empty() else null,
			"light": d.get("light_at", Vector3(0, float(d.get("light_y", 1.0)), 0)), "radius": 1.0,
			"door": door_kit.commit(material) if door_kit != null else null,
			"glass": glass_kit.commit(glass_material()) if glass_kit != null else null}
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
			light = Vector3(0, FORGE_HEARTH.y + 0.18, -0.05)   # over the coals
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


## {body: MeshKit, door: MeshKit or null, glass: MeshKit or null}. A door's panel is its own mesh, hinged at its left
## edge; a window's pane is its own mesh too, drawn see-through.
static func _build_piece(kind: String, ends := Vector2.ZERO) -> Dictionary:
	var spec: Dictionary = GameActions.PIECES[kind]
	var shape: String = spec.shape
	var mat: String = spec.mat
	var k := MeshKit.new(hash(kind))
	var door: MeshKit = null
	var glass: MeshKit = null
	var glow: MeshKit = null
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
			glass = MeshKit.new(hash(kind) + 5)
			_window_fittings(k, glass)
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
			# On its own (the ghost, the building wheel): a one-cell roof, open all round.
			var lone := PackedByteArray()
			lone.resize(25)
			lone[12] = 1
			_roof_into(k, kind, lone)
		"fence":
			_fence(k, mat, rng, x0, x1)
		"arch":
			_edge(k, mat, GameActions.WALL_H, _arch_openings(), rng, x0, x1)
			_arch_ring(k, mat, rng)
		"shutters":
			_edge(k, mat, GameActions.WALL_H, [Rect2(-0.55, 1.0, 1.1, 1.0)], rng, x0, x1)
			glass = MeshKit.new(hash(kind) + 5)
			_window_fittings(k, glass)
			_shutters(k, rng)
		"decor":
			glow = MeshKit.new(hash(kind) + 7)
			DecorModels.build(kind, k, glow, rng)
	return {"body": k, "door": door, "glass": glass, "glow": glow}


## A rail fence: posts at the ends and the middle in the piece's material (timber posts, piers of stacked stones,
## brick piers with a cap), and two timber rails between them.
static func _fence(k: MeshKit, mat: String, rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var col := _mat_colour(mat)
	var posts := [x0 + 0.12, (x0 + x1) * 0.5, x1 - 0.12]
	for px: float in posts:
		match mat:
			"wood":
				_board(k, Vector3(0.14, 1.06, 0.14), Transform3D(Basis(), Vector3(px, 0.53, 0.0)), WOOD_DARK, 0.004)
				k.add_primitive(_box(Vector3(0.18, 0.05, 0.18)), Transform3D(Basis(), Vector3(px, 1.08, 0.0)), WOOD_DARK.darkened(0.1), 0.0, 0.03)
			"stone":
				for i in 4:   # rough stones stacked, a little off true
					var s := col.lightened(rng.randf_range(-0.08, 0.06))
					var w := rng.randf_range(0.26, 0.32)
					k.extrude(_rounded_rect(w * 0.5, 0.12, 0.05, 2), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), Vector3(px + rng.randf_range(-0.02, 0.02), 0.13 + i * 0.26, 0.0)),
						0.28, 0.04, s, s.darkened(0.15))
			_:
				k.add_primitive(_box(Vector3(0.3, 1.0, 0.3)), Transform3D(Basis(), Vector3(px, 0.5, 0.0)), MORTAR, 0.0, 0.02)
				for i in 8:   # brick courses round the pier's faces
					var b := col.lightened(rng.randf_range(-0.07, 0.05))
					for side in [-1.0, 1.0]:
						k.extrude(_rounded_rect(0.15, 0.05, 0.02, 2), Transform3D(Basis(), Vector3(px, 0.07 + i * 0.125, side * 0.13)), 0.06, 0.015, b, b.darkened(0.14))
				k.add_primitive(_box(Vector3(0.38, 0.08, 0.38)), Transform3D(Basis(), Vector3(px, 1.04, 0.0)), col.darkened(0.1), 0.0, 0.03)
	for i in 2:   # the rails, a little bowed and weathered
		var ry := 0.42 + i * 0.4
		for seg in 2:
			var a: float = posts[seg]
			var b: float = posts[seg + 1]
			var rc := WOOD.lightened(rng.randf_range(-0.06, 0.04))
			_board(k, Vector3(b - a, 0.11, 0.06), Transform3D(Basis(), Vector3((a + b) * 0.5, ry, 0.0)), rc, 0.006)


## An archway's opening: the doorway's width, its top rounded by stepped bands (the arch ring over it hides the
## steps' corners).
static func _arch_openings() -> Array:
	var out: Array = [Rect2(-ARCH_R, 0.0, ARCH_R * 2.0, ARCH_SPRING)]
	var bands := 5
	for i in bands:
		var y0 := ARCH_SPRING + i * ARCH_R / bands
		var y1 := ARCH_SPRING + (i + 1) * ARCH_R / bands
		var half := sqrt(maxf(ARCH_R * ARCH_R - pow(y1 - ARCH_SPRING, 2.0), 0.0))
		half = maxf(half, 0.08)
		out.append(Rect2(-half, y0 - 0.001, half * 2.0, y1 - y0 + 0.002))
	return out


const ARCH_R := 0.72        ## an arch's inner radius (half the opening's width)
const ARCH_SPRING := 1.9    ## where the arch springs from its sides


## The ring of an arch: wedge-shaped voussoirs of stone or brick with a keystone, or for timber a curved frame,
## through the wall's whole depth.
static func _arch_ring(k: MeshKit, mat: String, rng: RandomNumberGenerator) -> void:
	var col := _mat_colour(mat) if mat != "wood" else WOOD_DARK
	var n := 9 if mat != "wood" else 6
	var outer := ARCH_R + (0.24 if mat != "wood" else 0.14)
	for i in n:
		var a0 := PI * float(i) / n
		var a1 := PI * float(i + 1) / n
		var gap := 0.012 if mat != "wood" else 0.004   # (a hairline even in timber: no two segments share an edge)
		var pts := PackedVector2Array()
		for a in [a0 + gap, a1 - gap]:
			pts.append(Vector2(cos(a) * ARCH_R, ARCH_SPRING + sin(a) * ARCH_R))
		for a in [a1 - gap, a0 + gap]:
			pts.append(Vector2(cos(a) * outer, ARCH_SPRING + sin(a) * outer))
		var keystone := mat != "wood" and i == n / 2
		var c: Color = col.lightened(0.08 if keystone else rng.randf_range(-0.06, 0.05))
		var thick := 0.36 if keystone else 0.32
		k.extrude(pts, Transform3D(Basis(), Vector3(0.0, 0.0, 0.06)), thick, 0.02, c, c.darkened(0.15))
	# The jambs below the spring, framing the sides of the opening.
	for side in [-1.0, 1.0]:
		var jc := col.lightened(rng.randf_range(-0.04, 0.04))
		k.add_primitive(_box(Vector3(0.14, ARCH_SPRING, 0.32)), Transform3D(Basis(), Vector3(side * (ARCH_R + 0.07), ARCH_SPRING * 0.5, 0.06)), jc, 0.0, 0.03)


## A shuttered window's shutters: two painted plank shutters folded open against the wall's outer face, each
## with a Z brace and iron hinges, standing a little proud of the wall.
static func _shutters(k: MeshKit, rng: RandomNumberGenerator) -> void:
	var paint := SHUTTER_PAINT
	var lo := 1.0
	var hi := 2.0
	var w := 0.56
	for side in [-1.0, 1.0]:
		var hinge := Vector3(side * 0.62, 0.0, 0.25)
		var b := Basis(Vector3.UP, side * 0.22)   # opened out a touch past flat
		for i in 4:
			var bx: float = side * (w * (i + 0.5) / 4.0)
			var pc := paint.lightened(rng.randf_range(-0.05, 0.05))
			_board(k, Vector3(hi - lo + 0.04, w / 4.0 - 0.012, 0.035), Transform3D(b * Basis(Vector3.BACK, PI * 0.5), hinge + b * Vector3(bx, (lo + hi) * 0.5, 0.0)), pc, 0.004)
		for y in [lo + 0.14, hi - 0.14]:   # ledges and the brace between them
			_board(k, Vector3(w - 0.06, 0.08, 0.03), Transform3D(b, hinge + b * Vector3(side * w * 0.5, y, 0.03)), paint.darkened(0.2), 0.0)
			k.add_primitive(_box(Vector3(0.16, 0.035, 0.02)), Transform3D(b, hinge + b * Vector3(side * 0.08, y, 0.05)), IRON, 0.0, 0.02)
		var brace := Basis(Vector3.BACK, side * atan2(hi - lo - 0.28, w - 0.1))
		_board(k, Vector3(sqrt(pow(w - 0.1, 2.0) + pow(hi - lo - 0.28, 2.0)), 0.07, 0.03), Transform3D(b * brace, hinge + b * Vector3(side * w * 0.5, (lo + hi) * 0.5, 0.03)), paint.darkened(0.2), 0.0)
	# A little window box of flowers on the sill, for colour.
	k.add_primitive(_box(Vector3(1.0, 0.12, 0.16)), Transform3D(Basis(), Vector3(0.0, lo - 0.1, 0.3)), WOOD_DARK, 0.0, 0.03)
	for i in 7:
		var fx := -0.42 + i * 0.14 + rng.randf_range(-0.02, 0.02)
		var fc: Color = [Color(0.86, 0.36, 0.34), Color(0.93, 0.78, 0.36), Color(0.82, 0.55, 0.78)][i % 3]
		k.add_primitive(MeshKit.sphere(0.045, 6, 4), Transform3D(Basis(), Vector3(fx, lo - 0.0, 0.3 + rng.randf_range(-0.03, 0.03))), fc, 0.01, 0.1)
		k.add_primitive(MeshKit.sphere(0.04, 6, 4), Transform3D(Basis.from_scale(Vector3(1.2, 0.6, 1.2)), Vector3(fx + 0.05, lo - 0.03, 0.3)), Color(0.36, 0.55, 0.3), 0.01, 0.1)


const SHUTTER_PAINT := Color(0.36, 0.5, 0.52)   ## a weathered blue-green


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
	k.extrude(bed, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.42, 0.0, mortar, mortar)
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
			var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), Vector3(bx, 0.12 if mat == "stone" else 0.24, bz))
			var thick := (0.44 if mat == "stone" else 0.2) + rng.randf_range(-0.01, 0.01)
			k.extrude(outline, xf, thick, 0.03 if mat == "stone" else 0.015, block, block.darkened(0.12))


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
		k.extrude(_rect_outline(r), Transform3D(), core_thick, 0.0, core, core)
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
			var outline := _rounded_rect((bx1 - bx0) * 0.5, bh * 0.5 - 0.015, 0.025, 2)
			k.extrude(outline, Transform3D(Basis(), Vector3((bx0 + bx1) * 0.5, y0 + bh * 0.5, 0.07)), 0.22, 0.02, b, b.darkened(0.14))


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
			k.extrude(_rounded_rect((sx1 - sx0) * 0.5 - 0.012, rh * 0.5 - 0.012, 0.07, 2),
				Transform3D(Basis(), Vector3((sx0 + sx1) * 0.5, y0 + rh * 0.5, 0.09)), 0.26, 0.04, s, s.darkened(0.14))


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
			k.extrude(_rounded_rect(bhw, ln * 0.5, minf(0.02, bhw * 0.5), 1), Transform3D(Basis(), Vector3(bx, (sg[0] + sg[1]) * 0.5 + off, 0.0)),
				0.08, 0.012, board, board.darkened(0.1))


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
static func _window_fittings(k: MeshKit, glass: MeshKit) -> void:
	var lo := 1.0
	var hi := 2.0
	var wx := 0.55
	_board(k, Vector3(wx * 2.0 + 0.3, 0.12, 0.16), Transform3D(Basis(), Vector3(0, lo - 0.02, 0.1)), WOOD_DARK)
	_board(k, Vector3(wx * 2.0 + 0.3, 0.12, 0.16), Transform3D(Basis(), Vector3(0, hi + 0.02, 0.1)), WOOD_DARK)
	for side in [-1.0, 1.0]:
		_board(k, Vector3(0.1, hi - lo, 0.16), Transform3D(Basis(), Vector3(side * (wx + 0.03), (lo + hi) * 0.5, 0.1)), WOOD_DARK)
	_board(k, Vector3(0.06, hi - lo, 0.04), Transform3D(Basis(), Vector3(0, (lo + hi) * 0.5, 0.1)), WOOD_DARK)
	glass.add_primitive(_box(Vector3(wx * 2.0 + 0.04, hi - lo + 0.04, 0.02)), Transform3D(Basis(), Vector3(0, (lo + hi) * 0.5, 0.06)), GLASS, 0.0, 0.0)


static var _glass_mat: StandardMaterial3D


## Window glass: a faint blue-green tint you can see through, with a little shine.
static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.vertex_color_use_as_albedo = true
		_glass_mat.albedo_color = Color(1, 1, 1, 0.22)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.roughness = 0.08
		_glass_mat.metallic_specular = 0.8
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


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
## Wood: an open stair, two slanted stringers with plank treads between them and gaps where the risers would be.
## Stone and brick: solid stepped blocks with chunky slab treads, between side curbs shaped like the stringers.
static func _stairs(k: MeshKit, mat: String) -> void:
	var col := _mat_colour(mat)
	var rise := GameActions.STACK_H / GameActions.STAIR_STEPS
	var run := GameActions.CELL / GameActions.STAIR_STEPS
	var h := GameActions.CELL * 0.5
	var ft := GameActions.FLOOR_TOP
	var top_y := ft + GameActions.STACK_H
	var wood := mat == "wood"
	# The side beams: their top runs 4 cm over the treads' middles, cut level at the floor and at the floor above,
	# and square at the bottom front and top back (an outline in the stair's side, z flipped so it runs up the slope).
	var depth := 0.34 if wood else 0.42
	var slope := GameActions.STACK_H / GameActions.CELL
	var over := rise * 0.5 + 0.04
	var u_top := -h + (top_y - ft - over) / slope
	var u_foot := -h + (depth - over) / slope
	var side := PackedVector2Array([Vector2(-h, ft), Vector2(u_foot, ft), Vector2(h, top_y - depth + over), Vector2(h, top_y),
		Vector2(u_top, top_y), Vector2(-h, ft + over)])
	var beam_w := 0.12 if wood else 0.16
	var beam_col := WOOD_DARK if wood else col.darkened(0.22)
	for sx in [-1.0, 1.0]:
		k.extrude(side, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * (h - beam_w * 0.5), 0, 0)), beam_w, 0.012, beam_col, beam_col.darkened(0.1), 0.1)
	var inner := GameActions.CELL - beam_w * 2.0
	for i in GameActions.STAIR_STEPS:
		var top := ft + (i + 1) * rise
		var zc := h - (i + 0.5) * run
		var shade := 0.06 * float((i * 7) % 3) - 0.04
		if wood:
			# A plank tread, its ends let into the stringers.
			k.add_primitive(_box(Vector3(inner + 0.06, 0.08, run * 0.9)), Transform3D(Basis(), Vector3(0, top - 0.04, zc)),
				WOOD.darkened(0.08).lightened(shade), 0.0, 0.015)
		else:
			# The block under the step, and a slab on top with a nose over the step below.
			k.add_primitive(_box(Vector3(inner + 0.02, top - 0.06, run + 0.02)), Transform3D(Basis(), Vector3(0, (top - 0.06) * 0.5, zc)),
				col.darkened(0.08).lightened(shade), 0.0, 0.03)
			k.add_primitive(_box(Vector3(inner + 0.02, 0.08, run + 0.05)), Transform3D(Basis(), Vector3(0, top - 0.04, zc + 0.015)),
				col.lightened(0.12 + shade), 0.0, 0.02)


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
			# Tiles are nudged off a regular grid so their edges never line up exactly.
			var jitter := Vector2(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.004, 0.004))
			k.extrude(_rounded_rect(hx, hy, hx * 0.3, 1), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx + jitter.x, 0.03 + row * 0.004, tz + jitter.y)),
				0.06, 0.012, t, t.darkened(0.18))
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
	# On the top: a plank offcut with a hand saw across it, a few curls of shavings, and a coil of rope.
	var y := top_y + 0.035
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)   # outlines drawn in x/y lie flat on the bench (y -> -z)
	var turn := Basis(Vector3.UP, 0.22)
	_board(k, Vector3(0.55, 0.16, 0.035), Transform3D(turn * flat, Vector3(0.36, y + 0.0175, -0.06)), WOOD.lightened(0.14))
	var saw_at := Vector3(0.3, y + 0.04, -0.04)
	var saw_turn := Basis(Vector3.UP, -0.35)
	var steel := Color(0.7, 0.72, 0.76)
	# The blade: a long tapering plate, toothed along its lower edge (a darker rim).
	var blade := PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.42, -0.028), Vector2(0.42, 0.012), Vector2(0.0, 0.045)])
	k.extrude(blade, Transform3D(saw_turn * flat, saw_at), 0.004, 0.0, steel, steel.darkened(0.35))
	# The handle: a closed grip at the heel, with a darker hand-hole.
	var grip := PackedVector2Array([Vector2(-0.13, -0.045), Vector2(0.01, -0.06), Vector2(0.01, 0.06), Vector2(-0.09, 0.07), Vector2(-0.14, 0.03)])
	k.extrude(grip, Transform3D(saw_turn * flat, saw_at + Vector3(0, 0.004, 0)), 0.022, 0.006, WOOD_DARK.lightened(0.18), WOOD_DARK)
	var hole := PackedVector2Array([Vector2(-0.1, -0.022), Vector2(-0.03, -0.028), Vector2(-0.03, 0.026), Vector2(-0.08, 0.034), Vector2(-0.11, 0.012)])
	k.extrude(hole, Transform3D(saw_turn * flat, saw_at + Vector3(0, 0.016, 0)), 0.004, 0.0, WOOD_DARK.darkened(0.45), WOOD_DARK.darkened(0.45))
	# Shavings: little curls of pale wood scattered off the end of the plank.
	var shave := WOOD.lightened(0.2)
	for i in 8:
		var c := Vector3(0.6 + rng.randf_range(-0.09, 0.09), y + 0.012, 0.12 + rng.randf_range(-0.1, 0.08))
		var a0 := rng.randf() * TAU
		var r := rng.randf_range(0.022, 0.034)
		var path: Array = []
		var radii: Array = []
		for t in 8:
			var a2 := a0 + t * 0.75
			path.append(c + Vector3(cos(a2) * r, 0.008 + sin(t * 0.6) * 0.012, sin(a2) * r))
			radii.append(0.007)
		k.loft(path, radii, 4, shave, Callable(), Callable(), true, true)
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
	# A blacksmith's forge: a waist-high hearth of mortared stone with a bed of coals on top, a back wall carrying a
	# brick hood and a short chimney over the fire, leather bellows at its left side, and the anvil on a stump.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var mortar := stone.darkened(0.3)
	var brick := Color(0.6, 0.35, 0.26)
	var hw := FORGE_HEARTH.x * 0.5
	var hd := FORGE_HEARTH.z * 0.5
	var top := FORGE_HEARTH.y
	_stone_box(k, Vector3(hw * 2.0, top, hd * 2.0), Vector3(0, top * 0.5, 0), stone, mortar, rng)
	# A curb of dressed stone round the top, and the fire bed inside it: ash, dark coal and glowing coals.
	var curb := stone.lightened(0.06)
	for side in [-1.0, 1.0]:
		# (Lifted a hair off the hearth, and the short sides a hair shorter, so no faces or edges coincide.)
		k.add_primitive(_box(Vector3(hw * 2.0, 0.08, 0.1)), Transform3D(Basis(), Vector3(0, top + 0.043, side * (hd - 0.05))), curb, 0.0, 0.04)
		k.add_primitive(_box(Vector3(0.1, 0.08, hd * 2.0 - 0.206)), Transform3D(Basis(), Vector3(side * (hw - 0.05), top + 0.043, 0)), curb, 0.0, 0.04)
	k.add_primitive(_box(Vector3(hw * 2.0 - 0.2, 0.03, hd * 2.0 - 0.2)), Transform3D(Basis(), Vector3(0, top + 0.015, 0)), ASH, 0.0, 0.05)
	for i in 22:
		var at := Vector3(rng.randf_range(-0.32, 0.32), top + 0.04 + rng.randf_range(0.0, 0.03), rng.randf_range(-0.2, 0.16))
		var r := rng.randf_range(0.035, 0.06)
		if i % 3 == 0:   # dark coal among the glowing
			k.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), at), Color(0.12, 0.1, 0.09), r * 0.3, 0.1)
		else:
			g.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), at),
				Color(1.0, rng.randf_range(0.3, 0.55), 0.1), r * 0.25, 0.15)
	# The back wall, carrying the hood.
	var back_h := 0.62
	# (Sunk a hair into the hearth so its bottom edges don't sit exactly on the hearth's top edge.)
	_stone_box(k, Vector3(hw * 2.0, back_h + 0.02, 0.2), Vector3(0, top + back_h * 0.5 - 0.01, hd - 0.1), stone, mortar, rng)
	# The hood: brick, narrowing from over the fire up into the chimney.
	var hood_y := top + back_h
	var hood := PackedVector2Array([Vector2(-hw - 0.04, 0.0), Vector2(hw + 0.04, 0.0), Vector2(0.2, 0.45), Vector2(-0.2, 0.45)])
	k.extrude(hood, Transform3D(Basis(), Vector3(0, hood_y, 0.08)), 0.62, 0.02, brick, brick.darkened(0.15))
	k.add_primitive(_box(Vector3(hw * 2.0 + 0.04, 0.08, 0.66)), Transform3D(Basis(), Vector3(0, hood_y - 0.02, 0.08)), brick.darkened(0.2), 0.0, 0.03)
	var chimney_h := 0.85
	for i in 5:   # courses of brick, alternately a shade lighter
		var y := hood_y + 0.42 + i * chimney_h / 5.0
		k.add_primitive(_box(Vector3(0.36, chimney_h / 5.0 - 0.012, 0.36)), Transform3D(Basis(), Vector3(0, y + chimney_h / 10.0, 0.1)),
			brick.lightened(0.05 * float(i % 2)), 0.0, 0.03)
	k.add_primitive(_box(Vector3(0.44, 0.07, 0.44)), Transform3D(Basis(), Vector3(0, hood_y + 0.42 + chimney_h + 0.035, 0.1)), brick.darkened(0.3), 0.0, 0.03)
	# Bellows on the left: two wooden boards with pleated leather between, an iron nozzle into the fire, a handle.
	var bx := -hw - 0.42
	var by := top - 0.18
	var board := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(-0.22, -0.18), Vector2(0.12, -0.12), Vector2(0.22, 0.0), Vector2(0.12, 0.12), Vector2(-0.22, 0.18)])
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for yb in [by - 0.09, by + 0.09]:
		k.extrude(board, Transform3D(flat, Vector3(bx, yb, 0.0)), 0.025, 0.006, WOOD, WOOD_DARK)
	var leather := Color(0.36, 0.22, 0.14)
	var pleats := PackedVector2Array()
	for p in board:
		pleats.append(p * 0.92)
	for j in 3:
		k.extrude(pleats, Transform3D(flat, Vector3(bx, by - 0.05 + j * 0.05, 0.0)), 0.04, 0.012, leather.lightened(0.05 * float(j % 2)), leather.darkened(0.2))
	k.loft([Vector3(bx + 0.2, by, 0.0), Vector3(-hw + 0.02, by + 0.06, 0.0), Vector3(-hw + 0.22, top + 0.06, 0.0)], [0.025, 0.02, 0.018], 8, IRON)
	k.loft([Vector3(bx - 0.28, by + 0.1, 0.0), Vector3(bx - 0.48, by + 0.32, 0.0)], [0.02, 0.018], 7, WOOD_DARK)
	k.add_primitive(_box(Vector3(0.12, by - 0.11, 0.12)), Transform3D(Basis(), Vector3(bx, (by - 0.11) * 0.5, 0.0)), WOOD_DARK, 0.0, 0.03)   # its stand
	# Anvil on a stump beside it.
	var ax := Vector3(0.95, 0, -0.2)
	k.loft([ax, ax + Vector3(0, 0.45, 0)], [0.2, 0.18], 14, BARK, func(t: float, _a: float) -> Color: return BARK if t < 0.98 else WOOD, Callable(), true, true, 0.008)
	var anvil := PackedVector2Array([Vector2(-0.24, 0.0), Vector2(-0.1, 0.02), Vector2(-0.08, 0.14), Vector2(-0.22, 0.17), Vector2(-0.3, 0.2),
		Vector2(0.18, 0.2), Vector2(0.3, 0.17), Vector2(0.12, 0.13), Vector2(0.09, 0.02), Vector2(0.2, 0.0)])
	k.extrude(anvil, Transform3D(Basis(Vector3.UP, 0.3), ax + Vector3(0, 0.45, 0)), 0.13, 0.025, IRON, IRON.lightened(0.35), 0.4)
	# Tongs leaning on the front of the hearth.
	for s in [-1.0, 1.0]:
		k.loft([Vector3(-0.3 + s * 0.02, 0.0, -hd - 0.3), Vector3(-0.25, top + 0.02, -hd - 0.01)], [0.012, 0.01], 6, IRON)


## Where the forge's fire is: the hearth's size (x width, y height of its top, z depth). The crafting minigame
## puts its crucible and bars on the coals there.
const FORGE_HEARTH := Vector3(1.1, 0.78, 0.8)


## A block of mortar faced on its four sides with courses of rough stones.
static func _stone_box(k: MeshKit, size: Vector3, center: Vector3, stone: Color, mortar: Color, rng: RandomNumberGenerator) -> void:
	k.add_primitive(_box(size - Vector3(0.02, 0.0, 0.02)), Transform3D(Basis(), center), mortar, 0.0, 0.03)
	var rows := maxi(1, roundi(size.y / 0.2))
	var rh := size.y / rows
	var y0 := center.y - size.y * 0.5
	for face in 4:
		var along := size.x if face < 2 else size.z
		var out := (size.z if face < 2 else size.x) * 0.5
		var sgn := 1.0 if face % 2 == 0 else -1.0
		var basis := Basis(Vector3.UP, 0.0 if face < 2 else PI * 0.5)
		for row in rows:
			var x := -along * 0.5 - (rng.randf_range(0.05, 0.15) if row % 2 == 1 else 0.0)
			while x < along * 0.5 - 0.04:
				var x0 := maxf(x, -along * 0.5)
				var x1 := minf(x0 + rng.randf_range(0.22, 0.38), along * 0.5)
				if along * 0.5 - x1 < 0.12:
					x1 = along * 0.5
				x = x1
				if x1 - x0 < 0.08:
					continue
				var c := stone.lightened(rng.randf_range(-0.08, 0.08))
				var local := Vector3((x0 + x1) * 0.5, y0 + rh * (row + 0.5), sgn * out)
				k.extrude(_rounded_rect((x1 - x0) * 0.5 - 0.012, rh * 0.5 - 0.012, 0.04, 2), Transform3D(basis, Vector3(center.x, 0, center.z) + basis * local),
					0.05, 0.015, c, c.darkened(0.14))


# --- Pitched roofs -------------------------------------------------------------------------------------------------

## How steeply a roof rises (metres up for each metre in from its edge), how high it can get, how far the eaves reach
## out past the walls, and where the tiles start (just above the flat ceiling deck).
const ROOF_PITCH := 0.66
const ROOF_CAP := 4.5        ## metres in from the edge at most (a big hall's roof flattens off on top)
const EAVE := 0.38
const EAVE_Y := 0.07
const ROOF_GRID := 12

static var _roof_cache := {}


## Which of the cells round a roof (5 x 5, this one in the middle) have a roof at the same level: the roof's shape key.
static func roof_window(st: Dictionary, structures: Dictionary) -> PackedByteArray:
	var w := PackedByteArray()
	w.resize(25)
	var p: Array = st.pos
	var c := GameActions.cell_of(Vector3(p[0], 0, p[2]))
	var level := int(st.get("level", 0))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if not GameActions.cover_in(Vector2i(c.x + dx, c.y + dz), level).is_empty():
				w[(dz + 2) * 5 + (dx + 2)] = 1
	return w


## A roof piece as part of the roof it belongs to: a hipped roof, rising from every open edge of the roofed area at
## ROOF_PITCH (so one cell is a little pyramid, a long room has a ridge, an L-shaped one valleys and hips), tiled in
## rows, with eaves overhanging the open edges and a fascia board under them. The flat ceiling deck and its beams stay
## underneath (the room's ceiling). `window`: see roof_window. Returns {body, glow: null, light, radius, top} (top: the
## roof's faces, for its collider).
static func roof_model(kind: String, material: Material, window: PackedByteArray) -> Dictionary:
	var key := kind + str(material.get_instance_id()) + window.hex_encode()
	if _roof_cache.has(key):
		return _roof_cache[key]
	var k := MeshKit.new(hash(key))
	var top := _roof_into(k, kind, window)
	var out_d := {"body": k.commit(material), "glow": null, "light": Vector3.ZERO, "radius": 1.0, "top": top}
	_roof_cache[key] = out_d
	return out_d


## Builds a roof piece into `k` (see roof_model); returns the faces of its top.
static func _roof_into(k: MeshKit, kind: String, window: PackedByteArray) -> PackedVector3Array:
	var mat: String = GameActions.PIECES[kind].mat
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind + window.hex_encode())
	var tile: Color
	match mat:
		"wood": tile = Color(0.46, 0.32, 0.22)
		"stone": tile = Color(0.4, 0.42, 0.47)
		_: tile = Color(0.62, 0.34, 0.26)
	var frame := tile.darkened(0.3) if mat == "stone" else WOOD_DARK
	_roof_frame(k, frame)
	var h := GameActions.CELL * 0.5
	var cell := GameActions.CELL
	# The open edges near this cell (an edge of a roofed cell with no roof beyond it), in this cell's own space.
	var segs: Array = []   # [a: Vector2, b: Vector2, outward: Vector2]
	var has := func(dx: int, dz: int) -> bool:
		if absi(dx) > 2 or absi(dz) > 2:
			return true   # beyond what we know: count it roofed (the edge is far enough off not to matter)
		return window[(dz + 2) * 5 + (dx + 2)] == 1
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if not has.call(dx, dz):
				continue
			var cx := dx * cell
			var cz := dz * cell
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if has.call(dx + d.x, dz + d.y):
					continue
				var mid := Vector2(cx + d.x * h, cz + d.y * h)
				var along := Vector2(-d.y, d.x) * h
				segs.append([mid - along, mid + along, Vector2(d.x, d.y)])
	var depth := func(x: float, z: float) -> float:
		var best := ROOF_CAP
		var q := Vector2(x, z)
		for sg: Array in segs:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var ab := b - a
			var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			best = minf(best, q.distance_to(a + ab * t))
		return best
	var height := func(x: float, z: float) -> float:
		return EAVE_Y + ROOF_PITCH * float(depth.call(x, z))
	var top := PackedVector3Array()
	var band := func(d: float) -> Color:
		var row := floori(d / 0.27)
		var c := tile.lightened(0.07) if row % 2 == 0 else tile.darkened(0.06)
		return c.lightened(rng.randf_range(-0.04, 0.04))
	# The surface: a grid over the cell, each square cut along whichever diagonal follows the roof's fold there.
	var n := ROOF_GRID
	var step := cell / n
	var grid: Array = []
	for j in n + 1:
		var row: Array = []
		for i in n + 1:
			var x := -h + i * step
			var z := -h + j * step
			row.append(Vector3(x, float(height.call(x, z)), z))
		grid.append(row)
	k.flat_shading = true
	for j in n:
		for i in n:
			var p00: Vector3 = grid[j][i]
			var p10: Vector3 = grid[j][i + 1]
			var p01: Vector3 = grid[j + 1][i]
			var p11: Vector3 = grid[j + 1][i + 1]
			var cx := -h + (i + 0.5) * step
			var cz := -h + (j + 0.5) * step
			var true_mid: float = height.call(cx, cz)
			var d1 := absf((p00.y + p11.y) * 0.5 - true_mid)   # cut 00-11
			var d2 := absf((p10.y + p01.y) * 0.5 - true_mid)   # cut 10-01
			var col: Color = band.call(float(depth.call(cx, cz)))
			var tris: Array = [[p00, p10, p11], [p00, p11, p01]] if d1 <= d2 else [[p00, p10, p01], [p10, p11, p01]]
			for t: Array in tris:
				k.add_tri(t[0], t[1], t[2], col)
				top.append_array(PackedVector3Array([t[0], t[1], t[2]]))
	# Eaves: past each open edge of this cell, the roof carries on down and out (from the grid's own edge points, so
	# the two join exactly), with a fascia board along its end.
	var drop := EAVE * ROOF_PITCH
	var fascia := frame.darkened(0.1)
	var open := {}
	var boards: Array = []   # fascia boards, added after the tiles (MeshKit nudges each part apart: the skin is one part)
	var lip := func(p: Vector3, out: Vector3) -> Vector3:
		return p + out * EAVE + Vector3(0, -drop, 0)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if has.call(d.x, d.y):
			continue
		open[d] = true
		var out := Vector3(d.x, 0, d.y)
		var pts: Array = []   # along the edge, in grid order
		for m in n + 1:
			if d.x == 1:
				pts.append(grid[m][n])
			elif d.x == -1:
				pts.append(grid[m][0])
			elif d.y == 1:
				pts.append(grid[n][m])
			else:
				pts.append(grid[0][m])
		var col := tile.darkened(0.08)
		for m in n:
			var t0: Vector3 = pts[m]
			var t1: Vector3 = pts[m + 1]
			var b0: Vector3 = lip.call(t0, out)
			var b1: Vector3 = lip.call(t1, out)
			# Wound so the slope faces up and out.
			if (b0 - t0).cross(t1 - t0).y > 0.0:
				k.add_tri(t0, t1, b0, col)
				k.add_tri(t1, b1, b0, col)
			else:
				k.add_tri(t0, b0, t1, col)
				k.add_tri(t1, b0, b1, col)
			top.append_array(PackedVector3Array([t0, t1, b0, t1, b1, b0]))
		var fl := cell + EAVE * 2.0
		var fy: float = float(height.call(out.x * h, out.z * h)) - drop - 0.08
		boards.append([Vector3(fl, 0.12, 0.05) if absf(out.z) > 0.5 else Vector3(0.05, 0.12, fl), out * (h + EAVE + 0.03) + Vector3(0, fy, 0)])
	# Outer corners: where two open edges meet, the eaves wrap round the corner.
	for cd: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		if not (open.has(Vector2i(cd.x, 0)) and open.has(Vector2i(0, cd.y))):
			continue
		var pa: Vector3 = grid[n if cd.y == 1 else 0][n if cd.x == 1 else 0]
		var pb: Vector3 = lip.call(pa, Vector3(cd.x, 0, 0))
		var pd: Vector3 = lip.call(pa, Vector3(0, 0, cd.y))
		var pc := pa + Vector3(cd.x, 0, cd.y) * EAVE + Vector3(0, -drop * 1.4, 0)
		var col := tile.darkened(0.1)
		for t: Array in [[pa, pb, pc], [pa, pc, pd]]:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			if (c - a).cross(b - a).y > 0.0:
				k.add_tri(a, b, c, col)
			else:
				k.add_tri(a, c, b, col)
			top.append_array(PackedVector3Array([a, b, c]))
	k.flat_shading = false
	_roof_underside(k, top, tile.darkened(0.25))
	for b: Array in boards:
		k.add_primitive(_box(b[0]), Transform3D(Basis(), b[1]), fascia, 0.0, 0.03)
	return top


## The roof is a skin of tiles some centimetres thick, not a sheet: an underside under every face of `top` (seen
## from below the eaves) and a strip down every open edge, so it's closed all round.
static func _roof_underside(k: MeshKit, top: PackedVector3Array, col: Color) -> void:
	var down := Vector3(0, -0.045, 0)
	var tris: Array = []
	var edges := {}
	var key := func(a: Vector3, b: Vector3) -> String:
		var ka := "%d,%d,%d" % [roundi(a.x * 2000.0), roundi(a.y * 2000.0), roundi(a.z * 2000.0)]
		var kb := "%d,%d,%d" % [roundi(b.x * 2000.0), roundi(b.y * 2000.0), roundi(b.z * 2000.0)]
		return ka + "|" + kb if ka < kb else kb + "|" + ka
	for i in range(0, top.size(), 3):
		var a := top[i]
		var b := top[i + 1]
		var c := top[i + 2]
		if (c - a).cross(b - a).y < 0.0:   # (as add_tri winds an upward face)
			var t := b
			b = c
			c = t
		tris.append([a, b, c])
		for e: Array in [[a, b], [b, c], [c, a]]:
			var kk: String = key.call(e[0], e[1])
			edges[kk] = int(edges.get(kk, 0)) + 1
	for t: Array in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		k.add_tri(a + down, c + down, b + down, col)
		for e: Array in [[a, b], [b, c], [c, a]]:
			if int(edges[key.call(e[0], e[1])]) != 1:
				continue
			var p: Vector3 = e[0]
			var q: Vector3 = e[1]
			k.add_tri(p, q + down, q, col.lightened(0.1))
			k.add_tri(p, p + down, q + down, col.lightened(0.1))


## The flat ceiling deck under a roof and the beams round its edge (seen from inside).
static func _roof_frame(k: MeshKit, frame: Color) -> void:
	var h := GameActions.CELL * 0.5
	k.add_primitive(_box(Vector3(GameActions.CELL - 0.004, 0.05, GameActions.CELL - 0.004)), Transform3D(), frame.darkened(0.1), 0.0, 0.03)
	for side in [-1.0, 1.0]:
		k.add_primitive(_box(Vector3(GameActions.CELL - 0.004, 0.16, 0.14)), Transform3D(Basis(), Vector3(0, -0.04, side * (h - 0.072))), frame, 0.0, 0.03)
		k.add_primitive(_box(Vector3(0.14, 0.16, GameActions.CELL - 0.29)), Transform3D(Basis(), Vector3(side * (h - 0.072), -0.04, 0)), frame, 0.0, 0.03)
