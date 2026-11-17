class_name ItemModels
extends RefCounted
## 3D models for items, built vertex by vertex (lofted handles, bevelled blades cut from outlines,
## faceted stone and crystal) rather than stretched primitives. Used in first person and for items
## lying in the world.
##
## Orientation: the grip is at the origin, the handle runs up +Y, and blades face forward (-Z).
## Tiers read at a glance:
##  1 Stone      - knapped, chipped heads lashed with cord to crooked branches
##  2 1st metal  - simple cast shapes, leather-wrapped grips
##  3 2nd metal  - forged, bevelled shapes with bright edges, collars and pommels
##  4 Gem        - faceted crystal heads with gold fittings on dark wood
##  5 Duskforged - dark, barbed shapes with glowing violet edges and inlay

const WOOD := Color(0.55, 0.4, 0.26)
const BARK := Color(0.42, 0.3, 0.2)
const DARK_WOOD := Color(0.24, 0.17, 0.13)
const LEATHER := Color(0.36, 0.22, 0.14)
const CORD := Color(0.74, 0.64, 0.42)
const GOLD := Color(0.86, 0.7, 0.34)
const DUSK := Color(0.2, 0.15, 0.26)
const DUSK_GLOW := Color(0.78, 0.52, 1.0)
const STONE := Color(0.5, 0.5, 0.54)

## Basis for blades/heads whose outline is drawn with x = forward (-Z) and y = up.
const FORWARD_PLANE := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()


static func mesh_for(id: String, material: Material) -> ArrayMesh:
	var key := id + str(material.get_instance_id())
	if _cache.has(key):
		return _cache[key]
	var info := ItemDB.info(id)
	var k := MeshKit.new(hash(id))
	if info.kind == "tool":
		var t: Dictionary = info.tool
		if t.type == "rock":
			_flint_rock(k, 0.045)
		else:
			var tier := int(t.tier)
			var col: Color = info.get("color", STONE)
			match String(t.type):
				"hatchet": _hatchet(k, tier, col)
				"pickaxe": _pickaxe(k, tier, col)
				"spear": _spear(k, tier, col)
				"knife": _knife(k, tier, col)
	else:
		_material_item(k, id, info)
	var mesh := k.commit(material)
	_cache[key] = mesh
	return mesh


# --- Shared parts ---------------------------------------------------------------------

## Handle from y = -0.1 (butt) to `length`. Tier changes wood, shape and grip.
static func _handle(k: MeshKit, length: float, tier: int, radius := 0.016) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 31 + int(length * 1000)
	var path: Array = []
	var radii: Array = []
	var steps := 10
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(-0.1, length, t)
		var bend := Vector3.ZERO
		if tier == 1:   # crooked branch
			bend = Vector3(sin(t * 5.0 + rng.randf()) * 0.006, 0, sin(t * 3.0) * 0.008)
		else:           # gentle ergonomic curve
			bend = Vector3(0, 0, sin(t * PI) * 0.008)
		path.append(Vector3(0, y, 0) + bend)
		var r := radius * (1.12 - t * 0.18)
		if tier >= 3 and t < 0.08:
			r *= 1.25   # flared butt
		radii.append(r)
	var wood := BARK if tier == 1 else (DARK_WOOD if tier >= 4 else WOOD.lightened(0.05 * tier))
	var grip_to := 0.13
	var wrap := LEATHER if tier < 5 else Color(0.32, 0.18, 0.42)
	var col_fn := func(t: float, ang: float) -> Color:
		var y := lerpf(-0.1, length, t)
		if tier >= 2 and y > -0.07 and y < grip_to:
			# Spiral leather wrap with dark seams.
			return wrap.darkened(0.25) if fposmod(y * 90.0 + ang / TAU, 1.0) < 0.18 else wrap
		if tier == 1:
			return wood.darkened(0.12) if fposmod(ang * 1.7 + y * 40.0, 1.0) < 0.3 else wood   # bark ridges
		return wood.darkened(0.06) if fposmod(y * 25.0 + sin(ang) * 0.3, 1.0) < 0.15 else wood   # grain
	k.loft(path, radii, 9, wood, col_fn, Callable(), true, true, 0.0015 if tier == 1 else 0.0)
	if tier >= 3:   # pommel
		var pc := GOLD if tier == 4 else (DUSK_GLOW if tier == 5 else Color(0.62, 0.6, 0.58))
		k.loft([Vector3(0, -0.118, 0), Vector3(0, -0.1, 0), Vector3(0, -0.085, 0)], [0.012, radius * 1.5, radius * 1.1], 10, pc)


## A ring around the handle where the head sits: cord lashing, metal collar or gold band.
static func _binding(k: MeshKit, y: float, tier: int, radius := 0.02, height := 0.04) -> void:
	if tier == 1:
		# Fiber cord wound in a criss-cross: several tilted rings.
		for i in 5:
			var yy := y - height * 0.5 + height * i / 4.0
			var tilt := 0.35 if i % 2 == 0 else -0.35
			var ring: Array = []
			var radii: Array = []
			for j in 13:
				var a := TAU * j / 12.0
				ring.append(Vector3(cos(a) * radius, yy + sin(a) * radius * tilt, sin(a) * radius))
				radii.append(0.0035)
			k.loft(ring, radii, 5, CORD.darkened(0.05 * (i % 2)), Callable(), Callable(), false, false)
		return
	var c := Color(0.55, 0.5, 0.45) if tier <= 3 else (GOLD if tier == 4 else DUSK)
	k.loft([Vector3(0, y - height * 0.5, 0), Vector3(0, y - height * 0.45, 0), Vector3(0, y + height * 0.45, 0), Vector3(0, y + height * 0.5, 0)],
		[radius * 0.85, radius, radius, radius * 0.85], 12, c)


static func _knap(outline: PackedVector2Array, seed_value: int, amount: float) -> PackedVector2Array:
	# Irregular chipped edge for stone tools.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedVector2Array()
	for p in outline:
		out.append(p + Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount)))
	return out


static func _arc(center: Vector2, radius: float, from_deg: float, to_deg: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


static func _head_colors(tier: int, col: Color) -> Array:
	# [face color, edge color]
	match tier:
		1: return [STONE, STONE.lightened(0.28)]
		2: return [col, col.lightened(0.22)]
		3: return [col.darkened(0.05), col.lightened(0.45)]
		4: return [col, col.lightened(0.5)]
		_: return [DUSK, DUSK_GLOW]


# --- Hatchets ---------------------------------------------------------------------------

static func _hatchet(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.32
	_handle(k, top + 0.045, tier, 0.017)
	var c := _head_colors(tier, col)
	var outline: PackedVector2Array
	var thick := 0.026
	var bevel := 0.014
	match tier:
		1:
			outline = _knap(PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.05, 0.045), Vector2(0.105, 0.035), Vector2(0.12, -0.005), Vector2(0.1, -0.04), Vector2(0.05, -0.04), Vector2(0.0, -0.028)]), 11, 0.006)
			thick = 0.032
			k.flat_shading = true
		2:
			outline = PackedVector2Array([Vector2(-0.02, 0.022), Vector2(0.05, 0.026), Vector2(0.09, 0.05), Vector2(0.105, 0.02), Vector2(0.108, -0.02), Vector2(0.09, -0.055), Vector2(0.055, -0.03), Vector2(-0.02, -0.022)])
		3:
			outline = PackedVector2Array([Vector2(-0.03, 0.02), Vector2(0.045, 0.022)])
			outline.append_array(_arc(Vector2(0.055, -0.005), 0.07, 70, -80, 8))
			outline.append_array(PackedVector2Array([Vector2(0.05, -0.035), Vector2(-0.03, -0.02)]))
			thick = 0.022
			bevel = 0.02
		4:
			outline = PackedVector2Array([Vector2(-0.015, 0.024), Vector2(0.05, 0.065), Vector2(0.125, 0.045), Vector2(0.14, -0.01), Vector2(0.11, -0.07), Vector2(0.04, -0.035), Vector2(-0.015, -0.024)])
			k.flat_shading = true
			bevel = 0.022
		_:
			outline = PackedVector2Array([Vector2(-0.065, 0.0), Vector2(-0.03, 0.02), Vector2(0.03, 0.025)])
			outline.append_array(_arc(Vector2(0.06, 0.0), 0.08, 85, -95, 9))
			outline.append_array(PackedVector2Array([Vector2(0.075, -0.045), Vector2(0.03, -0.025), Vector2(-0.03, -0.02)]))
			thick = 0.024
			bevel = 0.022
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(p * 1.4)
	k.extrude(scaled, Transform3D(FORWARD_PLANE, Vector3(0, top, 0)), thick * 1.25, bevel * 1.3, c[0], c[1])
	k.flat_shading = false
	_binding(k, top, tier, 0.022, 0.055 if tier == 1 else 0.04)
	if tier == 5:   # glowing inlay line along the blade
		k.loft([Vector3(0, top + 0.01, -0.03), Vector3(0, top + 0.015, -0.08), Vector3(0, top - 0.01, -0.11)], [0.004, 0.004, 0.003], 5, DUSK_GLOW, Callable(), Callable(), true, true)


# --- Pickaxes ---------------------------------------------------------------------------

static func _pickaxe(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.34
	_handle(k, top + 0.035, tier, 0.017)
	var c := _head_colors(tier, col)
	var sides := 7
	if tier in [1, 4]:
		k.flat_shading = true
		sides = 5
	var head_r := 0.028 + tier * 0.003
	# The head is one lofted curve through the handle: tapered spikes on both ends.
	var front_len := 0.15 + tier * 0.012
	var back_len := 0.04 if tier == 1 else (0.13 if tier != 3 else 0.11)
	var droop := 0.05
	var path: Array = []
	var radii: Array = []
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var x := lerpf(back_len, -front_len, t)        # +z back, -z front
		var y := top - droop * pow(x / (front_len if x < 0.0 else maxf(back_len, 0.01)), 2.0)
		path.append(Vector3(0, y, x))
		var to_tip := 1.0 - absf(lerpf(-1.0, 1.0, t))   # 1 at the middle, 0 at tips
		radii.append(lerpf(0.004, head_r, pow(to_tip, 0.4)))
	var shape := func(t: float, a: float) -> Vector2:
		# Diamond-ish cross-section; the back end of tier-3 heads flattens into a chisel.
		if tier == 3 and t < 0.25:
			return Vector2(1.6, 0.45)
		return Vector2(1.0, 0.75)
	var head_col := func(t: float, a: float) -> Color:
		var tip := absf(lerpf(-1.0, 1.0, t))
		return c[0].lerp(c[1], smoothstep(0.65, 1.0, tip))   # brighter worn points
	if tier == 1:
		# A single knapped stone point lashed on, no back spike.
		path = path.slice(steps / 3, steps + 1)
		radii = radii.slice(steps / 3, steps + 1)
	k.loft(path, radii, sides, c[0], head_col, shape, true, true)
	k.flat_shading = false
	if tier == 5:   # barbs along the top of the pick
		for i in 3:
			var p: Vector3 = path[3 + i * 2]
			k.loft([p, p + Vector3(0, 0.03, 0.012)], [0.007, 0.001], 4, DUSK_GLOW.darkened(0.3))
	_binding(k, top, tier, 0.022, 0.045)


# --- Spears -----------------------------------------------------------------------------

static func _spear(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.85
	_handle(k, top, tier, 0.014)
	var c := _head_colors(tier, col)
	var outline: PackedVector2Array
	var thick := 0.018
	var length := 0.13 + tier * 0.012
	match tier:
		1:
			outline = _knap(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.022, 0.03), Vector2(0.026, 0.07), Vector2(0.0, length), Vector2(-0.026, 0.07), Vector2(-0.022, 0.03)]), 21, 0.004)
			thick = 0.022
			k.flat_shading = true
		2:
			outline = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.02, 0.02), Vector2(0.03, 0.06), Vector2(0.0, length), Vector2(-0.03, 0.06), Vector2(-0.02, 0.02)])
		3:
			outline = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.018, 0.015), Vector2(0.028, 0.05), Vector2(0.02, 0.11), Vector2(0.0, length), Vector2(-0.02, 0.11), Vector2(-0.028, 0.05), Vector2(-0.018, 0.015)])
			thick = 0.022
		4:
			outline = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.05), Vector2(0.012, 0.12), Vector2(0.0, length), Vector2(-0.012, 0.12), Vector2(-0.03, 0.05)])
			k.flat_shading = true
			thick = 0.026
		_:
			outline = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.045, 0.01), Vector2(0.02, 0.035), Vector2(0.03, 0.08), Vector2(0.0, length), Vector2(-0.03, 0.08), Vector2(-0.02, 0.035), Vector2(-0.045, 0.01)])
	var big := PackedVector2Array()
	for p in outline:
		big.append(p * 1.45)
	k.extrude(big, Transform3D(Basis(), Vector3(0, top - 0.01, 0)), thick * 1.3, 0.016, c[0], c[1], 0.12)
	k.flat_shading = false
	if tier == 3:   # crossbar lugs below the head
		k.loft([Vector3(-0.04, top - 0.02, 0), Vector3(0, top - 0.015, 0), Vector3(0.04, top - 0.02, 0)], [0.005, 0.008, 0.005], 6, c[0].darkened(0.15))
	_binding(k, top - 0.02, tier, 0.018, 0.05 if tier == 1 else 0.035)


# --- Knives -----------------------------------------------------------------------------

static func _knife(k: MeshKit, tier: int, col: Color) -> void:
	var c := _head_colors(tier, col)
	# Short handle, then blade from y = 0.06 upward, edge facing forward.
	var hpath := [Vector3(0, -0.04, 0), Vector3(0, -0.01, 0.002), Vector3(0, 0.03, 0.001), Vector3(0, 0.06, 0)]
	var wrap := CORD if tier == 1 else (LEATHER if tier < 4 else (DARK_WOOD if tier == 4 else Color(0.32, 0.18, 0.42)))
	k.loft(hpath, [0.014, 0.016, 0.015, 0.013], 9, wrap, func(t: float, a: float) -> Color:
		return wrap.darkened(0.25) if fposmod(t * 6.0 + a / TAU, 1.0) < 0.2 else wrap)
	if tier >= 2:   # guard
		var gc: Color = c[0].darkened(0.2) if tier < 4 else (GOLD if tier == 4 else DUSK_GLOW.darkened(0.2))
		var gw := 0.022 + tier * 0.004
		k.loft([Vector3(0, 0.062, gw), Vector3(0, 0.066, 0), Vector3(0, 0.062, -gw)], [0.006, 0.009, 0.006], 7, gc)
	if tier >= 3:   # pommel
		k.loft([Vector3(0, -0.055, 0), Vector3(0, -0.042, 0)], [0.008, 0.017], 9, GOLD if tier == 4 else c[0].darkened(0.1))
	var outline: PackedVector2Array
	var L := 0.12 + tier * 0.01
	match tier:
		1:
			outline = _knap(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.026, 0.01), Vector2(0.022, 0.07), Vector2(0.006, L), Vector2(-0.008, 0.06), Vector2(-0.006, 0.0)]), 31, 0.004)
			k.flat_shading = true
		2:
			outline = PackedVector2Array([Vector2(-0.004, 0.0), Vector2(0.022, 0.0), Vector2(0.02, 0.09), Vector2(0.0, L), Vector2(-0.006, 0.09), Vector2(-0.006, 0.0)])
		3:
			outline = PackedVector2Array([Vector2(-0.006, 0.0), Vector2(0.024, 0.0), Vector2(0.026, 0.07), Vector2(0.012, 0.115), Vector2(0.0, L), Vector2(-0.004, 0.11), Vector2(-0.008, 0.06), Vector2(-0.006, 0.0)])
		4:
			outline = PackedVector2Array([Vector2(-0.01, 0.0), Vector2(0.024, 0.0), Vector2(0.018, 0.08), Vector2(0.0, L), Vector2(-0.016, 0.07)])
			k.flat_shading = true
		_:
			outline = PackedVector2Array([Vector2(-0.006, 0.0), Vector2(0.024, 0.0), Vector2(0.03, 0.04), Vector2(0.018, 0.08), Vector2(0.028, 0.11), Vector2(0.0, L), Vector2(-0.01, 0.1), Vector2(-0.004, 0.05), Vector2(-0.012, 0.03)])
	k.extrude(outline, Transform3D(FORWARD_PLANE, Vector3(0, 0.066, 0)), 0.01 + (0.006 if tier in [1, 4] else 0.0), 0.012, c[0], c[1], 0.1)
	k.flat_shading = false


# --- The starting rock ------------------------------------------------------------------

## A fist-sized chunk of flint: faceted, with lighter freshly-chipped faces.
static func _flint_rock(k: MeshKit, r: float) -> void:
	k.flat_shading = true
	var stone := Color(0.4, 0.42, 0.47)
	var chipped := func(p: Vector3) -> Color:
		var d := (p - Vector3(0, 0.03, -0.04)).normalized()
		if d.dot(Vector3(0.3, 0.6, -0.75).normalized()) > 0.6 or d.dot(Vector3(-0.8, 0.1, -0.5).normalized()) > 0.75:
			return stone.lightened(0.3)
		return stone
	k.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.3, 0.85, 1.05)), Vector3(0, 0.03, -0.04)), stone, r * 0.35, 0.05, null, chipped)
	k.flat_shading = false


# --- Food & materials -------------------------------------------------------------------

static func _material_item(k: MeshKit, id: String, info: Dictionary) -> void:
	var col: Color = info.get("color", Color(0.8, 0.8, 0.8))
	var at := Vector3(0, 0.03, -0.03)
	match String(info.get("icon", "")):
		"berries":
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 10:
				var p := at + Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.0, 0.035), rng.randf_range(-0.03, 0.03))
				k.add_primitive(MeshKit.sphere(0.014, 8, 6), Transform3D(Basis(), p), col.lightened(rng.randf_range(-0.1, 0.1)), 0.0, 0.03)
			_leaf(k, at + Vector3(0, 0.03, 0), Vector3(0.6, 0.6, -0.2), 0.04, Game.palette.bush_leaves)
		"fruit":
			# Lofted fruit: plump body with a dimple at the top.
			var path := []
			var radii := []
			for i in 9:
				var t := i / 8.0
				path.append(at + Vector3(0, t * 0.06, 0))
				radii.append(sin(t * PI) * 0.032 + 0.004 * (1.0 - t))
			k.loft(path, radii, 12, col, func(t: float, a: float) -> Color: return col.lightened(0.15) if a > 2.0 and a < 3.4 and t > 0.4 else col)
			k.loft([at + Vector3(0, 0.055, 0), at + Vector3(0.004, 0.075, 0)], [0.003, 0.002], 5, BARK)
			_leaf(k, at + Vector3(0.004, 0.07, 0), Vector3(1, 0.4, 0), 0.035, Game.palette.oak_leaves)
		"mushroom":
			k.loft([at, at + Vector3(0, 0.03, 0), at + Vector3(0.002, 0.05, 0)], [0.011, 0.009, 0.01], 9, Color(0.93, 0.89, 0.8))
			var cap := []
			var cr := []
			for i in 7:
				var t := i / 6.0
				cap.append(at + Vector3(0, 0.045 + sin(t * PI * 0.5) * 0.025, 0))
				cr.append(cos(t * PI * 0.5) * 0.04 + 0.002)
			k.loft(cap, cr, 14, col, func(t: float, a: float) -> Color: return Color(0.97, 0.95, 0.9) if fposmod(a * 3.0 + t * 7.0, 1.0) < 0.12 and t > 0.3 else col)
		"herb":
			for i in 5:
				var a := i * 1.25
				_leaf(k, at, Vector3(cos(a), 1.2, sin(a)), 0.05, col.lightened(i * 0.03))
		"meat":
			# A steak cut from an outline, with a bone through it.
			var outline := PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.04, 0.03), Vector2(0.0, 0.04), Vector2(0.045, 0.025), Vector2(0.05, -0.01), Vector2(0.02, -0.035), Vector2(-0.03, -0.03)])
			k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), 0.03, 0.012, Color(0.78, 0.35, 0.36), Color(0.9, 0.62, 0.58), 0.6)
			k.loft([at + Vector3(0.03, 0, 0), at + Vector3(0.09, 0.005, 0)], [0.008, 0.007], 7, Color(0.93, 0.9, 0.84))
			k.add_primitive(MeshKit.sphere(0.011, 7, 5), Transform3D(Basis(), at + Vector3(0.095, 0.005, 0)), Color(0.93, 0.9, 0.84), 0.0, 0.02)
		"logs", "sticks":
			var thick := 0.022 if info.icon == "logs" else 0.008
			for i in (2 if info.icon == "logs" else 4):
				var o := Vector3((i - 1) * thick * 1.8, i * 0.005, 0)
				k.loft([at + o + Vector3(0, 0, 0.07), at + o + Vector3(0, 0.004, 0), at + o + Vector3(0, 0, -0.07)], [thick, thick * 1.05, thick * 0.95], 8, BARK, Callable(), Callable(), true, true, thick * 0.08)
		"ore", "gem", "stone", "flint":
			k.flat_shading = true
			var rock_col := Game.palette.rock if info.icon != "flint" else Color(0.38, 0.4, 0.45)
			k.add_primitive(MeshKit.sphere(0.04, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.85, 1.0)), at), rock_col, 0.014, 0.05)
			if info.icon in ["ore", "gem"]:
				for i in (3 if info.icon == "ore" else 5):
					var dir := Vector3(cos(i * 2.1) * 0.6, 1.0, sin(i * 2.1) * 0.6).normalized()
					k.loft([at + dir * 0.025, at + dir * (0.06 if info.icon == "gem" else 0.045)], [0.012, 0.0], 5, col)
			k.flat_shading = false
		_:
			k.flat_shading = true
			k.add_primitive(MeshKit.sphere(0.035, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1)), at), col, 0.01, 0.06)
			k.flat_shading = false


## A leaf: an outline with a soft fold, pointing along `dir`.
static func _leaf(k: MeshKit, base: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(length * 0.3, length * 0.25), Vector2(length * 0.32, length * 0.6), Vector2(0, length), Vector2(-length * 0.32, length * 0.6), Vector2(-length * 0.3, length * 0.25)])
	var b := Basis(Quaternion(Vector3.UP, dir.normalized()))
	k.extrude(outline, Transform3D(b, base), 0.003, 0.002, col, col.lightened(0.15), 0.5)
