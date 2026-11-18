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
	if info.kind == "placeable":
		var m: ArrayMesh = StructureModels.get_model(info.station, material, material).body
		_cache[key] = m
		return m
	var k := MeshKit.new(hash(id))
	if info.kind == "tool":
		var t: Dictionary = info.tool
		if t.type == "rock":
			_flint_rock(k, 0.045)
		elif t.type == "torch":
			_torch(k)
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

## Cheap smooth-ish noise for hammered metal and wood grain (deterministic, no textures).
static func _n2(p: Vector2, f: float) -> float:
	return sin(p.x * f * 1.7 + sin(p.y * f * 1.3) * 1.5) * cos(p.y * f * 1.1 + sin(p.x * f * 0.9))


## Materials per tier: {base, edge (honed / polished), dark (recesses), fitting (bands, collars)}
static func _metal(tier: int, col: Color) -> Dictionary:
	match tier:
		1: return {"base": Color(0.36, 0.38, 0.44), "edge": Color(0.62, 0.64, 0.7), "dark": Color(0.26, 0.27, 0.32), "fitting": CORD}
		2: return {"base": col, "edge": col.lightened(0.42), "dark": col.darkened(0.35), "fitting": col.darkened(0.25)}
		3: return {"base": col.darkened(0.08), "edge": col.lightened(0.55), "dark": col.darkened(0.45), "fitting": Color(0.34, 0.33, 0.36)}
		4: return {"base": col, "edge": col.lightened(0.6), "dark": col.darkened(0.3), "fitting": GOLD}
		_: return {"base": DUSK, "edge": DUSK_GLOW, "dark": Color(0.1, 0.07, 0.13), "fitting": DUSK_GLOW.darkened(0.35)}


## Surface color for a sculpted head: honed edge band, hammered or knapped body, by tier.
static func _head_color(tier: int, m: Dictionary, edge: PackedVector2Array, band := 0.012) -> Callable:
	return func(p: Vector2, th: float) -> Color:
		var c: Color = m.base
		match tier:
			1:   # knapped flint: patchy facets
				var cell := Vector2(floorf(p.x * 70.0 + sin(p.y * 90.0) * 0.8), floorf(p.y * 70.0 + sin(p.x * 80.0) * 0.8))
				var h := fposmod(sin(cell.x * 12.99 + cell.y * 78.23) * 437.5, 1.0)
				c = c.lightened(h * 0.18).darkened((1.0 - h) * 0.08)
			2:   # cast and hammered: soft mottling
				c = c.lightened(_n2(p, 140.0) * 0.07)
			3:   # forged: faint fold lines along the head
				c = c.darkened(0.06 if fposmod(p.y * 160.0 + _n2(p, 40.0) * 0.6, 1.0) < 0.12 else 0.0)
			4:   # crystal: facets catch the light differently
				var cell := Vector2i(floori(p.x * 45.0 + p.y * 20.0), floori(p.y * 45.0 - p.x * 15.0))
				c = c.lightened(fposmod(sin(cell.x * 3.7 + cell.y * 5.1) * 91.3, 1.0) * 0.25)
			_:   # dusk: dark metal with faint veins
				c = c.lerp(DUSK_GLOW, 0.25 if absf(_n2(p, 70.0)) < 0.06 else 0.0)
		if not edge.is_empty():
			var d := MeshKit.dist_to_polyline(p, edge)
			# Grind line: a slightly darker bevel band, then the bright honed edge.
			if tier != 1 and d > band and d < band * 2.4:
				c = c.darkened(0.08)
			c = c.lerp(m.edge, 1.0 - smoothstep(band * 0.3, band, d))
		return c


## Thickness for a head: thin at the cutting edge, `body` thick inside, swelling to `eye`
## around the handle (x within eye_r of 0) so the head visibly wraps it.
static func _head_thickness(edge: PackedVector2Array, body: float, falloff: float, eye: float, eye_r: float, edge_min := 0.0012) -> Callable:
	return func(p: Vector2) -> float:
		var along_edge := smoothstep(0.0, falloff, MeshKit.dist_to_polyline(p, edge))
		var t := lerpf(edge_min, body, along_edge)
		if eye > 0.0:
			# The eye's bulge fades out toward the edge too, or it would stand up as a cliff where the haft meets the rim.
			t = maxf(t, eye * (1.0 - smoothstep(eye_r, eye_r + 0.016, absf(p.x))) * along_edge)
		return t


## A handle from y = -0.1 (butt) to `length`: oval section, swelling knob at the butt, a gentle
## curve (`curve` > 0 bows it forward like an axe haft), wood grain, and per-tier grip work.
static func _handle(k: MeshKit, length: float, tier: int, radius := 0.016, curve := 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tier * 31 + int(length * 1000)
	var path: Array = []
	var radii: Array = []
	var steps := 22
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(-0.1, length, t)
		var bend := Vector3(0, 0, -sin(t * PI) * curve + sin(t * PI * 2.0) * curve * 0.25)
		if tier == 1:   # a crooked branch
			bend += Vector3(sin(t * 7.0 + rng.randf()) * 0.004, 0, sin(t * 4.0) * 0.006)
		path.append(Vector3(0, y, 0) + bend)
		var r := radius * 1.3 * (1.06 - t * 0.12)   # a sturdier haft than the first cut
		r *= 1.0 + 0.32 * exp(-pow(t / 0.05, 2.0))   # knob at the butt
		radii.append(r)
	var wood := BARK if tier == 1 else (DARK_WOOD if tier >= 4 else WOOD.lightened(0.04 * tier))
	var col_fn := func(t: float, ang: float) -> Color:
		var y := lerpf(-0.1, length, t)
		if tier == 1:
			return wood.darkened(0.14) if fposmod(ang * 1.9 + y * 35.0 + sin(y * 60.0), 1.0) < 0.28 else wood   # bark ridges
		var grain := sin(ang * 3.0 + y * 8.0 + sin(y * 30.0 + ang) * 1.2)
		var c := wood.darkened(0.08 * (grain * 0.5 + 0.5))
		if t < 0.03:
			c = wood.lightened(0.12)   # end grain at the butt
		return c
	k.loft(path, radii, 14, wood, col_fn, func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.82), true, true, 0.0018 if tier == 1 else 0.0)
	if tier == 1:
		# Knots where twigs were trimmed off.
		for i in 3:   # one knot per third of the haft, turned round the haft, so they never overlap
			var t := lerpf(0.25, 0.75, (i + rng.randf_range(0.2, 0.8)) / 3.0)
			var at: Vector3 = path[int(t * steps)]
			var a := (i + rng.randf_range(0.0, 0.8)) * TAU / 3.0
			var d := Vector3(cos(a), 0.2, sin(a)).normalized()
			k.loft([at, at + d * radius * 1.35], [radius * 0.55, radius * 0.4], 6, BARK.darkened(0.15), Callable(), Callable(), true, true)
		return
	# Plain haft; metal ferrules at the grip ends.
	var y0 := -0.075
	var y1 := 0.09
	var band: Color = _metal(tier, Color.WHITE).fitting if tier != 2 else Color(0.5, 0.42, 0.34)
	for y in [y1 + 0.004, y0 - 0.006]:
		var base: Vector3 = path[int(clampf((y + 0.1) / (length + 0.1), 0.0, 1.0) * steps)]
		k.loft([Vector3(base.x, y - 0.005, base.z), Vector3(base.x, y + 0.005, base.z)], [radius * 1.3 * 1.22, radius * 1.3 * 1.22], 14, band,
			Callable(), func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.84), true, true)
	if tier >= 3:   # pommel cap
		var pc: Color = GOLD if tier == 4 else (DUSK_GLOW if tier == 5 else Color(0.5, 0.49, 0.52))
		k.loft([Vector3(0, -0.122, 0), Vector3(0, -0.112, 0), Vector3(0, -0.098, 0)], [0.008, radius * 1.45, radius * 1.3], 16, pc)


## A metal ring around the handle (collars on forged heads).
static func _collar(k: MeshKit, y: float, radius: float, h: float, col: Color) -> void:
	k.loft([Vector3(0, y - h * 0.5, 0), Vector3(0, y - h * 0.4, 0), Vector3(0, y + h * 0.4, 0), Vector3(0, y + h * 0.5, 0)],
		[radius * 0.9, radius, radius, radius * 0.9], 16, col, Callable(), func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.84))


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
	var m := _metal(tier, col)
	return [m.base, m.edge]


## Flint heads are set into the haft with a lump of resin at the joint, not wrapped.
static func _resin_joint(k: MeshKit, y: float, radius: float) -> void:
	var resin := Color(0.66, 0.42, 0.18)
	k.add_primitive(MeshKit.sphere(radius * 2.1, 10, 7), Transform3D(Basis.from_scale(Vector3(1.0, 0.9, 1.0)), Vector3(0, y, 0)), resin, 0.0, 0.03)


# --- Hatchets ---------------------------------------------------------------------------
# Head outlines are drawn with x = forward (the blade side) and y = up; the handle passes
# through x = 0. FORWARD_PLANE turns that into the model's -Z forward.

static func _hatchet(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.34
	var m := _metal(tier, col)
	var hr := 0.016
	_handle(k, top + 0.045, tier, hr, 0.012 if tier > 1 else 0.0)
	# An axe blade: a thick poll behind the eye, a convex face that thins to a honed bit.
	# The eye (where the haft goes through) is the thick middle of the head.
	# Squared poll, a straight top edge rising to the toe, and a convex bit sweeping down to the lower corner.
	var outline := PackedVector2Array([Vector2(-0.09, 0.028), Vector2(-0.098, 0.006), Vector2(-0.098, -0.014), Vector2(-0.088, -0.03),
		Vector2(-0.04, -0.032), Vector2(0.0, -0.034), Vector2(0.05, -0.044), Vector2(0.1, -0.06), Vector2(0.14, -0.068),
		Vector2(0.172, -0.042), Vector2(0.182, -0.004), Vector2(0.17, 0.034), Vector2(0.136, 0.054),
		Vector2(0.08, 0.044), Vector2(0.0, 0.036), Vector2(-0.05, 0.036)])
	var size := 1.0 + 0.04 * tier
	for i in outline.size():
		outline[i] *= size
	if tier == 1:
		outline = _knap(outline, 11, 0.002)   # knapped flint: a little irregular, but crisp
	var ridge := PackedVector2Array(outline)
	ridge.append(outline[0])
	var xf := Transform3D(FORWARD_PLANE, Vector3(0, top, 0))
	k.sculpt(outline, xf, _head_thickness(ridge, 0.022 + 0.002 * tier, 0.014, 0.034, 0.022, 0.001),
		_head_color(tier, m, ridge, 0.014), 3, 0.005)
	# The haft's end: a wedge driven into the top of it, standing proud of the head.
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.03, 0.012, 0.014)
	k.add_primitive(wedge, Transform3D(Basis(), Vector3(0, top + 0.046, 0)), WOOD.darkened(0.15) if tier == 1 else m.fitting, 0.0, 0.04)
	if tier == 1:
		# Rawhide lashing crossing the eye, the way a knapped head was bound on.
		_resin_joint(k, top, hr)
	else:
		# A metal socket around the eye, with a ring band where it meets the head.
		var fit: Color = m.fitting if tier != 2 else m.base.darkened(0.2)
		k.loft([Vector3(0, top - 0.042, 0), Vector3(0, top - 0.02, 0), Vector3(0, top + 0.02, 0), Vector3(0, top + 0.042, 0)],
			[hr * 1.3, hr * 1.55, hr * 1.55, hr * 1.3], 12, fit,
			func(t: float, _a: float) -> Color: return fit.lightened(0.15) if fposmod(t * 3.0, 1.0) < 0.12 else fit)


# --- Pickaxes ---------------------------------------------------------------------------

static func _pickaxe(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.35
	var m := _metal(tier, col)
	var hr := 0.017
	_handle(k, top + 0.04, tier, hr)
	if tier == 1:
		# A long flint point lashed across the top of the handle.
		var outline := _knap(PackedVector2Array([Vector2(-0.045, 0.0), Vector2(-0.02, -0.026), Vector2(0.06, -0.024), Vector2(0.17, 0.0), Vector2(0.06, 0.026), Vector2(-0.02, 0.026)]), 41, 0.004)
		var ridge := PackedVector2Array(outline)
		ridge.append(outline[0])
		k.sculpt(outline, Transform3D(FORWARD_PLANE, Vector3(0, top, 0)), _head_thickness(ridge, 0.03, 0.02, 0.0, 0.0, 0.003), _head_color(1, m, ridge, 0.02), 3, 0.006)
		_resin_joint(k, top, hr)
		return
	# The head: a bar in the swing plane that curves down to a point at each end, thinned to a crisp
	# edge. Tier 3's back end is a square chisel instead of a point.
	var front := 0.17
	var back := 0.12 if tier == 3 else 0.15
	var bar := PackedVector2Array([Vector2(-back, -0.05), Vector2(-0.10, -0.014), Vector2(-0.05, 0.012), Vector2(0.0, 0.02),
		Vector2(0.05, 0.014), Vector2(0.11, -0.012), Vector2(front, -0.05),
		Vector2(0.11, -0.03), Vector2(0.05, -0.004), Vector2(0.0, -0.001),
		Vector2(-0.05, -0.004), Vector2(-0.10, -0.03)])
	if tier == 3:
		bar[0] = Vector2(-back, -0.02)
		bar.append(Vector2(-back, -0.055))
	var ridge := PackedVector2Array(bar)
	ridge.append(bar[0])
	if tier == 4:
		k.flat_shading = true
	k.sculpt(bar, Transform3D(FORWARD_PLANE, Vector3(0, top, 0)), _head_thickness(ridge, 0.016 + 0.002 * tier, 0.012, 0.03, 0.02, 0.001),
		_head_color(tier, m, ridge, 0.012), 3, 0.005)
	k.flat_shading = false
	# The eye: a metal sleeve where the haft goes through the head, and a cord binding above it.
	var fit: Color = m.fitting if tier != 2 else m.base.darkened(0.2)
	k.loft([Vector3(0, top - 0.03, 0), Vector3(0, top - 0.012, 0), Vector3(0, top + 0.012, 0), Vector3(0, top + 0.03, 0)],
		[hr * 1.3, hr * 1.55, hr * 1.55, hr * 1.3], 12, fit,
		func(t: float, _a: float) -> Color: return fit.lightened(0.15) if fposmod(t * 3.0, 1.0) < 0.12 else fit)
	# The haft's end: a wedge pinned into the top of it.
	var wedge := BoxMesh.new()
	wedge.size = Vector3(0.012, 0.012, 0.022)
	k.add_primitive(wedge, Transform3D(Basis(), Vector3(0, top + 0.044, 0)), fit, 0.0, 0.04)


# --- Spears -----------------------------------------------------------------------------

static func _spear(k: MeshKit, tier: int, col: Color) -> void:
	var top := 0.85
	var m := _metal(tier, col)
	var hr := 0.015
	_handle(k, top, tier, hr)
	var L := 0.17 + tier * 0.012
	var outline: PackedVector2Array
	match tier:
		1:   # knapped leaf point
			outline = _knap(PackedVector2Array([Vector2(0.0, -0.01), Vector2(0.018, 0.0), Vector2(0.03, 0.05), Vector2(0.024, 0.1), Vector2(0.0, L), Vector2(-0.024, 0.1), Vector2(-0.03, 0.05), Vector2(-0.018, 0.0)]), 21, 0.0035)
		2:   # broad leaf blade
			outline = PackedVector2Array([Vector2(0.0, -0.01), Vector2(0.016, 0.004), Vector2(0.034, 0.05), Vector2(0.03, 0.11), Vector2(0.0, L), Vector2(-0.03, 0.11), Vector2(-0.034, 0.05), Vector2(-0.016, 0.004)])
		3:   # long narrow blade with waisted base
			outline = PackedVector2Array([Vector2(0.0, -0.01), Vector2(0.012, 0.004), Vector2(0.03, 0.04), Vector2(0.022, 0.08), Vector2(0.026, 0.13), Vector2(0.0, L), Vector2(-0.026, 0.13), Vector2(-0.022, 0.08), Vector2(-0.03, 0.04), Vector2(-0.012, 0.004)])
		4:   # crystal shard
			outline = PackedVector2Array([Vector2(0.0, -0.01), Vector2(0.03, 0.06), Vector2(0.014, 0.14), Vector2(0.0, L), Vector2(-0.014, 0.14), Vector2(-0.03, 0.06)])
		_:   # dusk: barbed head
			outline = PackedVector2Array([Vector2(0.0, -0.01), Vector2(0.05, 0.004), Vector2(0.026, 0.04), Vector2(0.034, 0.1), Vector2(0.0, L), Vector2(-0.034, 0.1), Vector2(-0.026, 0.04), Vector2(-0.05, 0.004)])
	var head_y := top + 0.02
	if tier == 4:
		k.flat_shading = true
	var big := PackedVector2Array()
	for p in outline:
		big.append(Vector2(p.x * 1.45, p.y * 1.35))
	outline = big
	var rim := PackedVector2Array(outline)
	rim.append(outline[0])
	# A blade is a lens with a midrib: thin at the honed edges, a raised ridge down the middle.
	var edge_t := _head_thickness(rim, 0.022 if tier != 1 else 0.028, 0.02, 0.0, 0.0, 0.0012)
	var thick := func(p: Vector2) -> float:
		var t: float = edge_t.call(p)
		return t + (0.007 if tier != 1 else 0.004) * exp(-absf(p.x) * 60.0) * smoothstep(0.0, 0.05, p.y)
	k.sculpt(outline, Transform3D(Basis(), Vector3(0, head_y, 0)), thick, _head_color(tier, m, rim, 0.01), 3, 0.005)
	k.flat_shading = false
	if tier == 1:
		# Rawhide binding just below the knapped point.
		_resin_joint(k, head_y - 0.01, hr)
		return
	# Socket: a tapered metal sleeve over the shaft, with rings, and a cord binding below it.
	var sock: Color = m.fitting if tier != 2 else m.base.darkened(0.12)
	k.loft([Vector3(0, top - 0.06, 0), Vector3(0, top - 0.02, 0), Vector3(0, head_y + 0.004, 0)], [hr * 1.32, hr * 1.18, hr * 0.85], 14, sock,
		func(t: float, _a: float) -> Color: return sock.lightened(0.18) if fposmod(t * 4.0, 1.0) < 0.14 else sock)


# --- Knives -----------------------------------------------------------------------------

static func _knife(k: MeshKit, tier: int, col: Color) -> void:
	var m := _metal(tier, col)
	# Grip from y = -0.05 to 0.055: oval, slightly swollen in the palm.
	var gp := [Vector3(0, -0.05, 0), Vector3(0, -0.02, 0.001), Vector3(0, 0.015, 0.0015), Vector3(0, 0.055, 0)]
	var grip := CORD if tier == 1 else (WOOD.darkened(0.1) if tier <= 3 else (DARK_WOOD if tier == 4 else Color(0.28, 0.16, 0.36)))
	var gfn := func(t: float, a: float) -> Color:
		if tier == 1:
			return grip.darkened(0.22) if fposmod(t * 9.0 + a / TAU, 1.0) < 0.25 else grip   # wound cord
		return grip.darkened(0.08 * (sin(a * 3.0 + t * 12.0) * 0.5 + 0.5))
	k.loft(gp, [0.0125, 0.0145, 0.0145, 0.012], 14, grip, gfn, func(_t: float, _a: float) -> Vector2: return Vector2(0.7, 1.0), true, true)
	if tier >= 2:   # guard
		var gc: Color = m.fitting if tier != 2 else m.base.darkened(0.2)
		var gw := 0.02 + tier * 0.003
		k.loft([Vector3(0, 0.058, gw * 0.4), Vector3(0, 0.061, 0), Vector3(0, 0.058, -gw)], [0.006, 0.0085, 0.005], 12, gc)
	if tier >= 3:   # pommel
		var pc: Color = GOLD if tier == 4 else (DUSK_GLOW if tier == 5 else m.fitting)
		k.loft([Vector3(0, -0.062, 0), Vector3(0, -0.055, 0), Vector3(0, -0.047, 0)], [0.007, 0.014, 0.012], 14, pc)
	var L := 0.13 + tier * 0.01
	var outline: PackedVector2Array
	var edge: PackedVector2Array
	match tier:
		1:
			edge = PackedVector2Array([Vector2(0.022, 0.008), Vector2(0.024, 0.06), Vector2(0.004, L)])
			outline = _knap(PackedVector2Array([Vector2(-0.008, 0.0), Vector2(0.022, 0.008), Vector2(0.024, 0.06), Vector2(0.004, L), Vector2(-0.01, 0.06)]), 31, 0.003)
		2:
			edge = PackedVector2Array([Vector2(0.021, 0.0), Vector2(0.021, 0.085), Vector2(0.0, L)])
			outline = PackedVector2Array([Vector2(-0.007, 0.0), Vector2(0.021, 0.0), Vector2(0.021, 0.085), Vector2(0.0, L), Vector2(-0.007, 0.09)])
		3:   # clip point
			edge = PackedVector2Array([Vector2(0.024, 0.0), Vector2(0.026, 0.07), Vector2(0.014, 0.115), Vector2(0.0, L)])
			outline = PackedVector2Array([Vector2(-0.008, 0.0), Vector2(0.024, 0.0), Vector2(0.026, 0.07), Vector2(0.014, 0.115), Vector2(0.0, L), Vector2(-0.003, 0.12), Vector2(-0.009, 0.1)])
		4:
			edge = PackedVector2Array([Vector2(0.024, 0.0), Vector2(0.018, 0.085), Vector2(0.0, L)])
			outline = PackedVector2Array([Vector2(-0.012, 0.0), Vector2(0.024, 0.0), Vector2(0.018, 0.085), Vector2(0.0, L), Vector2(-0.016, 0.075)])
		_:   # dusk: serrated back, swept tip
			edge = PackedVector2Array([Vector2(0.024, 0.0), Vector2(0.03, 0.05), Vector2(0.026, 0.1), Vector2(0.0, L)])
			outline = PackedVector2Array([Vector2(-0.008, 0.0), Vector2(0.024, 0.0), Vector2(0.03, 0.05), Vector2(0.026, 0.1), Vector2(0.0, L),
				Vector2(-0.008, 0.12), Vector2(-0.004, 0.105), Vector2(-0.012, 0.09), Vector2(-0.006, 0.075), Vector2(-0.014, 0.06), Vector2(-0.008, 0.04)])
	if tier in [1, 4]:
		k.flat_shading = true
	var base_col := _head_color(tier, m, edge, 0.007)
	var fuller := func(p: Vector2, th: float) -> Color:
		var c: Color = base_col.call(p, th)
		if tier in [2, 3, 5] and absf(p.x - 0.002) < 0.0025 and p.y > 0.012 and p.y < L * 0.62:
			c = c.darkened(0.22)   # fuller groove
		return c
	k.sculpt(outline, Transform3D(FORWARD_PLANE, Vector3(0, 0.062, 0)), _head_thickness(edge, 0.008 if tier != 1 else 0.011, 0.026, 0.0, 0.0, 0.0009), fuller, 2, 0.006)
	k.flat_shading = false


# --- Torch ----------------------------------------------------------------------------

## A branch with a resin-soaked fiber wrap at the top (the flame is a separate glowing mesh).
static func _torch(k: MeshKit) -> void:
	_handle(k, 0.3, 1, 0.017)
	# The rag head: a bundle of cloth soaked in pitch, bulging in the middle and charred at the tip.
	var path := []
	var radii := []
	for i in 12:
		var t := i / 11.0
		path.append(Vector3(0, 0.2 + t * 0.14, 0))
		radii.append(0.019 + sin(t * PI) * 0.013 + (0.002 if t > 0.8 else 0.0))
	var rag := Color(0.6, 0.48, 0.3)
	var char := Color(0.18, 0.12, 0.08)
	var rag_col := func(t: float, _a: float) -> Color: return rag.lerp(char, smoothstep(0.7, 1.0, t))
	k.loft(path, radii, 14, rag, rag_col, Callable(), true, true, 0.0)


static var _flame: ArrayMesh

static func torch_flame() -> ArrayMesh:
	if _flame:
		return _flame
	var k := MeshKit.new(4)
	for i in 3:
		var a := TAU * i / 3.0
		var base := Vector3(cos(a) * 0.008, 0.0, sin(a) * 0.008)
		var path := []
		var radii := []
		for s in 8:
			var t := s / 7.0
			path.append(base.lerp(Vector3(0, 0.11 - i * 0.015, 0), t) + Vector3(sin(t * 4.0 + i) * 0.006, 0, 0))
			radii.append(sin(pow(t, 0.6) * PI) * 0.024 * (1.0 - t * 0.5))
		k.loft(path, radii, 10, Color(1, 0.8, 0.3), func(t: float, _a: float) -> Color:
			return Color(1.0, 0.88, 0.45).lerp(Color(0.95, 0.3, 0.06), t))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame = k.commit(m)
	return _flame


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
	var centre := Vector3(0, 0.03, -0.04)
	k.add_primitive(MeshKit.sphere(r, 9, 6), Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.3, 0.85, 1.05)), centre), stone, r * 0.35, 0.05, null, chipped)
	# Flake scars: shallow, pale dishes where knappers struck off a flake, spread over the lumps.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 5:
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.1, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var at := centre + d * r * 0.95
		var scar := MeshKit.sphere(r * rng.randf_range(0.28, 0.4), 6, 4)
		var basis := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT) * Basis.from_scale(Vector3(1.0, 1.0, 0.25))
		k.add_primitive(scar, Transform3D(basis, at), stone.lightened(0.22), 0.0, 0.03)
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
				k.add_primitive(MeshKit.sphere(0.014, 12, 8), Transform3D(Basis(), p), col.lightened(rng.randf_range(-0.1, 0.1)), 0.0, 0.03)
			_leaf(k, at + Vector3(0, 0.03, 0), Vector3(0.6, 0.6, -0.2), 0.04, Game.palette.bush_leaves)
		"fruit":
			# Lofted fruit: plump body with a dimple at the top.
			var path := []
			var radii := []
			for i in 9:
				var t := i / 8.0
				path.append(at + Vector3(0, t * 0.06, 0))
				radii.append(sin(t * PI) * 0.032 + 0.004 * (1.0 - t))
			k.loft(path, radii, 20, col, func(t: float, a: float) -> Color: return col.lightened(0.15) if a > 2.0 and a < 3.4 and t > 0.4 else col)
			k.loft([at + Vector3(0, 0.055, 0), at + Vector3(0.004, 0.075, 0)], [0.003, 0.002], 5, BARK)
			_leaf(k, at + Vector3(0.004, 0.07, 0), Vector3(1, 0.4, 0), 0.035, Game.palette.oak_leaves)
		"mushroom":
			k.loft([at, at + Vector3(0, 0.03, 0), at + Vector3(0.002, 0.05, 0)], [0.011, 0.009, 0.01], 14, Color(0.93, 0.89, 0.8))
			var cap := []
			var cr := []
			for i in 9:
				var t := i / 8.0
				cap.append(at + Vector3(0, 0.04 + sin(t * PI * 0.5) * 0.034, 0))
				cr.append(cos(t * PI * 0.5) * 0.04 + 0.002)
			k.loft(cap, cr, 20, col, func(t: float, a: float) -> Color: return Color(0.97, 0.95, 0.9) if sin(a * 4.0) * cos(t * 7.0) > 0.7 and t > 0.2 else col)
		"herb":
			for i in 5:
				var a := i * 1.25
				_leaf(k, at, Vector3(cos(a), 1.2, sin(a)), 0.05, col.lightened(i * 0.03))
		"meat":
			# A steak cut from an outline, with a bone through it.
			var outline := PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.04, 0.03), Vector2(0.0, 0.04), Vector2(0.045, 0.025), Vector2(0.05, -0.01), Vector2(0.02, -0.035), Vector2(-0.03, -0.03)])
			k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), 0.03, 0.012, Color(0.78, 0.35, 0.36), Color(0.9, 0.62, 0.58), 0.6)
			k.loft([at + Vector3(0.03, 0, 0), at + Vector3(0.09, 0.005, 0)], [0.008, 0.007], 12, Color(0.93, 0.9, 0.84))
			k.add_primitive(MeshKit.sphere(0.011, 10, 7), Transform3D(Basis(), at + Vector3(0.095, 0.005, 0)), Color(0.93, 0.9, 0.84), 0.0, 0.02)
		"logs", "sticks":
			_logs(k, at, info.icon == "logs")
		"rope":
			# A coil of twisted rope: stacked loops with a loose end.
			for i in 4:
				var ring := []
				var rr := []
				var r := 0.045 - i * 0.004
				for s2 in 25:
					var a := TAU * s2 / 24.0
					ring.append(at + Vector3(cos(a) * r, i * 0.011, sin(a) * r))
					rr.append(0.0075)
				k.loft(ring, rr, 8, CORD.darkened(i * 0.04), func(_t: float, a: float) -> Color: return CORD.darkened(0.12) if fposmod(a / TAU * 3.0, 1.0) < 0.3 else CORD, Callable(), false, false, 0.0, true)
			k.loft([at + Vector3(0.04, 0.035, 0), at + Vector3(0.07, 0.02, 0.03), at + Vector3(0.09, 0.0, 0.02)], [0.0075, 0.0075, 0.006], 8, CORD)
		"plank":
			var face := Basis(Vector3.RIGHT, -PI * 0.5)
			var plank := PackedVector2Array([Vector2(-0.08, -0.022), Vector2(0.08, -0.022), Vector2(0.08, 0.022), Vector2(-0.08, 0.022)])
			for z in [-0.024, 0.024]:   # two side by side
				k.extrude(plank, Transform3D(face, at + Vector3(0, 0, z)), 0.014, 0.004, WOOD.lightened(0.04), WOOD.lightened(0.15), 0.5)
			k.extrude(plank, Transform3D(face.rotated(Vector3.UP, PI * 0.5), at + Vector3(0, 0.015, 0)), 0.014, 0.004, WOOD.lightened(0.1), WOOD.lightened(0.2), 0.5)
		"leather":
			var outline := PackedVector2Array([Vector2(-0.05, -0.04), Vector2(-0.02, -0.05), Vector2(0.03, -0.045), Vector2(0.055, -0.01),
				Vector2(0.05, 0.035), Vector2(0.01, 0.05), Vector2(-0.035, 0.045), Vector2(-0.055, 0.01)])
			k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), 0.008, 0.006, LEATHER.lightened(0.1), LEATHER.lightened(0.25), 0.5)
			k.loft([at + Vector3(-0.03, 0.01, 0.0), at + Vector3(0.03, 0.01, 0.0)], [0.009, 0.009], 8, LEATHER)   # rolled edge
		"cooked_meat", "roast_fruit":
			if info.icon == "cooked_meat":
				var outline := PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.04, 0.03), Vector2(0.0, 0.04), Vector2(0.045, 0.025), Vector2(0.05, -0.01), Vector2(0.02, -0.035), Vector2(-0.03, -0.03)])
				k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at), 0.03, 0.012, Color(0.52, 0.28, 0.16), Color(0.36, 0.18, 0.1), 0.6)
				for i in 3:   # grill marks
					k.loft([at + Vector3(-0.03 + i * 0.025, 0.016, -0.025), at + Vector3(-0.015 + i * 0.025, 0.016, 0.025)], [0.004, 0.004], 5, Color(0.2, 0.1, 0.06))
				k.loft([at + Vector3(0.03, 0, 0), at + Vector3(0.09, 0.005, 0)], [0.008, 0.007], 12, Color(0.9, 0.85, 0.75))
			else:
				var fcol: Color = ItemDB.info("fruit").get("color", Color(0.8, 0.3, 0.3))
				for i in 2:
					var o := at + Vector3(i * 0.04 - 0.02, 0, 0)
					var path := []
					var radii := []
					for s2 in 9:
						var t := s2 / 8.0
						path.append(o + Vector3(0, t * 0.05, 0))
						radii.append(sin(t * PI) * 0.026 + 0.003 * (1.0 - t))
					k.loft(path, radii, 16, fcol.darkened(0.25), func(t: float, a: float) -> Color: return Color(0.35, 0.2, 0.1) if fposmod(a * 2.0 + t * 5.0, 1.0) < 0.15 else fcol.darkened(0.25))
				k.loft([at + Vector3(-0.06, 0.025, 0), at + Vector3(0.06, 0.025, 0)], [0.004, 0.004], 6, BARK)   # skewer
		"stew":
			# A carved wooden bowl, filled.
			var path := []
			var radii := []
			for s2 in 9:
				var t := s2 / 8.0
				path.append(at + Vector3(0, t * 0.04, 0))
				radii.append(0.028 + sin(t * PI * 0.5) * 0.03)
			# The bowl is closed across the top: that surface is the stew, coloured as it fills the mouth.
			var stew_col := Color(0.82, 0.46, 0.24)
			k.loft(path, radii, 22, WOOD, func(t: float, _a: float) -> Color: return stew_col if t > 0.97 else (WOOD.darkened(0.1) if t < 0.2 else WOOD), Callable(), true, true)
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			for i in 6:
				var a := rng.randf() * TAU
				var rr := rng.randf_range(0.0, 0.035)
				var c: Color = [Color(0.62, 0.36, 0.3), Game.palette.berry, Color(0.75, 0.6, 0.35)][i % 3]
				k.add_primitive(MeshKit.sphere(0.009, 8, 5), Transform3D(Basis(), at + Vector3(cos(a) * rr, 0.038, sin(a) * rr)), c, 0.002, 0.05)
		"bandage":
			# A roll of pale fiber cloth with a loose tail.
			var path := []
			var radii := []
			for s2 in 7:
				var t := s2 / 6.0
				path.append(at + Vector3(-0.03 + t * 0.06, 0.02, 0))
				radii.append(0.024)
			var cloth := Color(0.9, 0.86, 0.74)
			k.loft(path, radii, 18, cloth, func(t: float, a: float) -> Color: return cloth.darkened(0.08) if fposmod(t * 4.0, 1.0) < 0.15 else cloth)
			var tail := PackedVector2Array([Vector2(0.0, -0.022), Vector2(0.06, -0.026), Vector2(0.07, 0.0), Vector2(0.06, 0.026), Vector2(0.0, 0.022)])
			k.extrude(tail, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at + Vector3(0.0, 0.0, 0.02)), 0.003, 0.002, cloth, cloth.darkened(0.05), 0.5)
		"ingot":
			# A cast bar: trapezoid profile with bevelled bright edges, stacked two high.
			var c: Array = _head_colors(clampi(int(info.get("tier", 2)), 2, 5), col)
			for i in 2:
				var prof := PackedVector2Array([Vector2(-0.065, 0.0), Vector2(0.065, 0.0), Vector2(0.05, 0.026), Vector2(-0.05, 0.026)])
				k.extrude(prof, Transform3D(Basis(Vector3.UP, i * 0.5), at + Vector3(i * 0.01, i * 0.027, i * 0.006)), 0.045, 0.007, c[0], c[1], 0.3)
		"cut_gem":
			k.flat_shading = true
			var top := at + Vector3(0, 0.05, 0)
			var mid := at + Vector3(0, 0.03, 0)
			var bot := at
			var n := 8
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var p0 := mid + Vector3(cos(a0), 0, sin(a0)) * 0.04
				var p1 := mid + Vector3(cos(a1), 0, sin(a1)) * 0.04
				var t0 := top + Vector3(cos(a0), 0, sin(a0)) * 0.022
				var t1 := top + Vector3(cos(a1), 0, sin(a1)) * 0.022
				var shade := col.lightened(0.25 if i % 2 == 0 else 0.0)
				k.add_tri(t0, t1, p1, shade)
				k.add_tri(t0, p1, p0, shade)
				k.add_tri(top, t1, t0, col.lightened(0.4))
				k.add_tri(p0, p1, bot, col.darkened(0.1 if i % 2 == 0 else 0.25))
			k.flat_shading = false
		"ore":
			_ore(k, at, col)
		"gem":
			_crystals(k, at, col)
		"stone":
			_stone_lump(k, at)
		"flint":
			_flake(k, at)
		"fiber":
			_fiber(k, at)
		"resin":
			_resin(k, at)
		"hide":
			_hide(k, at)
		"bone":
			_bone(k, at)
		"cactus":
			_cactus_pad(k, at)
		"essence":
			_essence(k, at)
		"brick":
			_brick(k, at, col)
		_:
			k.flat_shading = true
			k.add_primitive(MeshKit.sphere(0.035, 7, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1)), at), col, 0.01, 0.06)
			k.flat_shading = false


# --- Ores, stones and raw materials ------------------------------------------------------

## A chunk of ore: grey rock with nuggets of the metal studding its faces.
static func _ore(k: MeshKit, at: Vector3, col: Color) -> void:
	k.flat_shading = true
	k.add_primitive(MeshKit.sphere(0.042, 9, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.85, 1.0)), at), Game.palette.rock, 0.008, 0.05)
	k.flat_shading = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 8:
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var r := rng.randf_range(0.009, 0.016)
		d.y = absf(d.y) * 0.6 + d.y * 0.4   # spread over the sides, not just the top
		var p := at + d.normalized() * Vector3(0.05, 0.036, 0.046)   # on the rock's surface, half sunk in
		k.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.15)), p),
			col.lightened(rng.randf_range(-0.06, 0.14)), 0.0, 0.04)


## An uncut crystal cluster: a rock base with faceted crystals standing out of it.
static func _crystals(k: MeshKit, at: Vector3, col: Color) -> void:
	k.add_primitive(MeshKit.sphere(0.03, 8, 5), Transform3D(Basis.from_scale(Vector3(1.3, 0.7, 1.1)), at + Vector3(0, -0.004, 0)), Game.palette.rock, 0.003, 0.05)
	k.flat_shading = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a) * rng.randf_range(0.2, 0.5), 1.0, sin(a) * rng.randf_range(0.2, 0.5)).normalized()
		var base := at + Vector3(cos(a) * 0.018, 0.0, sin(a) * 0.018)
		var length := rng.randf_range(0.05, 0.08) if i % 2 == 0 else rng.randf_range(0.065, 0.1)
		var shade := col.lightened(rng.randf_range(-0.1, 0.12))
		k.loft([base, base + lean * length * 0.6, base + lean * length], [0.0145, 0.0125, 0.0008], 6, shade, Callable(), Callable(), true, true)
	k.flat_shading = false


## Shadow essence: a dark core with rings of light round it.
static func _essence(k: MeshKit, at: Vector3) -> void:
	var c := at + Vector3(0, 0.02, 0)
	k.add_primitive(MeshKit.sphere(0.024, 10, 7), Transform3D(Basis(), c), DUSK, 0.002, 0.05)
	for i in 3:
		var tilt := Basis(Vector3.RIGHT, PI * i / 3.0) * Basis(Vector3.UP, PI * 0.25 * i)
		var ring: Array = []
		var rr: Array = []
		for s in 14:
			var a := TAU * s / 13.0
			ring.append(c + tilt * Vector3(cos(a) * 0.036, 0.0, sin(a) * 0.036))
			rr.append(0.0022)
		k.loft(ring, rr, 4, DUSK_GLOW, Callable(), Callable(), false, false, 0.0, true)


## A flake of flint: a knapped sliver, flat, with a pale glassy edge.
static func _flake(k: MeshKit, at: Vector3) -> void:
	k.flat_shading = true
	var outline := _knap(PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.025, 0.028), Vector2(0.02, 0.036),
		Vector2(0.056, 0.01), Vector2(0.024, -0.026), Vector2(-0.03, -0.02)]), 17, 0.003)
	k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), 0.012, 0.004, Color(0.4, 0.42, 0.47), Color(0.66, 0.68, 0.72), 0.3)
	k.flat_shading = false


## A rough stone: a lump with a broken face.
static func _stone_lump(k: MeshKit, at: Vector3) -> void:
	k.flat_shading = true
	k.add_primitive(MeshKit.sphere(0.04, 8, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.85, 1.0)), at), Game.palette.rock, 0.005, 0.05)
	k.add_primitive(MeshKit.sphere(0.018, 6, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 1.0)), at + Vector3(0.02, 0.022, 0.018)),
		Game.palette.rock.lightened(0.25), 0.0, 0.03)
	k.flat_shading = false


## Resin: a lump of amber sap with a drip running down one side.
static func _resin(k: MeshKit, at: Vector3) -> void:
	var amber := Color(0.86, 0.56, 0.2)
	k.add_primitive(MeshKit.sphere(0.034, 10, 7), Transform3D(Basis.from_scale(Vector3(1.15, 0.8, 1.0)), at), amber, 0.0, 0.03)
	k.loft([at + Vector3(0.025, -0.012, 0.012), at + Vector3(0.03, -0.034, 0.016)], [0.008, 0.004], 8, amber.darkened(0.08))


## Hide: a skin pegged out flat, with a fringe of hair along the rim.
static func _hide(k: MeshKit, at: Vector3) -> void:
	var hide := Color(0.64, 0.5, 0.36)
	var outline := PackedVector2Array([Vector2(-0.05, 0.02), Vector2(-0.03, 0.045), Vector2(0.02, 0.05), Vector2(0.05, 0.025),
		Vector2(0.055, -0.01), Vector2(0.03, -0.042), Vector2(-0.01, -0.046), Vector2(-0.045, -0.025)])
	k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), 0.008, 0.004, hide, hide.darkened(0.25), 0.5)
	for p in outline:
		var w := at + Vector3(p.x, 0.0, -p.y)
		var lean := Vector3(p.x, 0.0, -p.y).normalized() * 0.004 + Vector3(0, 0.004, 0)
		k.loft([w, w + lean], [0.0012, 0.0004], 4, hide.darkened(0.2), Callable(), Callable(), true, true)


## A bone: a long shaft with a double knob at each end.
static func _bone(k: MeshKit, at: Vector3) -> void:
	var bone := Color(0.93, 0.9, 0.82)
	k.loft([at + Vector3(-0.04, 0.0, 0.0), at + Vector3(0.0, 0.0, 0.0), at + Vector3(0.04, 0.0, 0.0)],
		[0.0075, 0.0055, 0.0075], 10, bone, Callable(), Callable(), true, true)
	for sx in [-1.0, 1.0]:
		for dz in [-0.009, 0.009]:
			k.add_primitive(MeshKit.sphere(0.0105, 8, 5), Transform3D(Basis(), at + Vector3(sx * 0.045, 0.0, dz)), bone, 0.0, 0.03)


## Plant fiber: a bundle of pale strands, tied in the middle.
static func _fiber(k: MeshKit, at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var green := Color(0.7, 0.66, 0.36)
	for i in 9:
		var off := rng.randf_range(-0.01, 0.01)
		var path: Array = []
		var radii: Array = []
		for s in 9:
			var t := s / 8.0
			path.append(at + Vector3(-0.055 + t * 0.11, sin(t * PI) * 0.004 + off * 0.6, off + sin(t * TAU) * 0.003))
			radii.append(0.0018)
		k.loft(path, radii, 4, green.lightened(rng.randf_range(-0.1, 0.12)), Callable(), Callable(), true, true)
	var tie: Array = []
	var tr: Array = []
	for j in 13:
		var a := TAU * j / 12.0
		tie.append(at + Vector3(0.0, cos(a) * 0.011, sin(a) * 0.011))
		tr.append(0.0025)
	k.loft(tie, tr, 5, CORD.darkened(0.05), Callable(), Callable(), false, false, 0.0, true)


## Cactus flesh: a green pad, with spines pricking out of its face.
static func _cactus_pad(k: MeshKit, at: Vector3) -> void:
	var green := Color(0.36, 0.6, 0.34)
	var outline := PackedVector2Array([Vector2(-0.04, 0.0), Vector2(-0.032, 0.03), Vector2(0.0, 0.04), Vector2(0.032, 0.03),
		Vector2(0.04, 0.0), Vector2(0.032, -0.03), Vector2(0.0, -0.04), Vector2(-0.032, -0.03)])
	k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), 0.028, 0.009, green, green.darkened(0.2), 0.5)
	for i in 12:
		var a := TAU * i / 12.0
		var r := 0.012 if i % 2 == 0 else 0.022
		var p := at + Vector3(cos(a) * r, 0.014, sin(a) * r)
		var lean := Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized()
		k.loft([p, p + lean * 0.016], [0.0021, 0.0005], 4, Color(0.95, 0.92, 0.75), Callable(), Callable(), true, true)


## A dressed stone brick: a squared block with a chisel groove across the top.
static func _brick(k: MeshKit, at: Vector3, col: Color) -> void:
	var outline := PackedVector2Array([Vector2(-0.05, -0.028), Vector2(0.05, -0.028), Vector2(0.05, 0.028), Vector2(-0.05, 0.028)])
	k.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), 0.03, 0.006, col, col.darkened(0.2), 0.35)
	k.loft([at + Vector3(-0.03, 0.016, 0.0), at + Vector3(0.03, 0.016, 0.0)], [0.002, 0.002], 4, col.darkened(0.3), Callable(), Callable(), true, true)


## Logs and sticks. A log is a barked piece with its cut face and rings at one end; sticks are thin and knotted.
static func _logs(k: MeshKit, at: Vector3, is_log: bool) -> void:
	var bark_fn := func(t: float, a: float) -> Color: return BARK.darkened(0.14) if fposmod(a * 2.0 + t * 6.0, 1.0) < 0.3 else BARK
	if is_log:
		var path: Array = []
		var radii: Array = []
		for i in 7:
			var t := i / 6.0
			path.append(at + Vector3(-0.07 + t * 0.14, 0.0, 0.0))
			radii.append(0.024 * (1.0 - 0.05 * t))
		var end_fn := func(t: float, a: float) -> Color: return Color(0.84, 0.7, 0.5) if t > 0.99 else bark_fn.call(t, a)
		k.loft(path, radii, 12, BARK, end_fn, Callable(), true, true)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for i in 4:
		var o := Vector3(0.0, (i - 1.5) * 0.0035 + 0.004, (i - 1.5) * 0.012 + rng.randf_range(-0.002, 0.002))
		var stick: Array = []
		var sr: Array = []
		for s in 5:
			var t := s / 4.0
			stick.append(at + o + Vector3(-0.07 + t * 0.14, sin(t * PI * 2.0) * 0.002, 0.0))
			sr.append(0.0075)
		k.loft(stick, sr, 8, BARK.lightened(rng.randf_range(-0.05, 0.05)), bark_fn, Callable(), true, true)


## A leaf: an outline with a soft fold, pointing along `dir`.
static func _leaf(k: MeshKit, base: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(length * 0.3, length * 0.25), Vector2(length * 0.32, length * 0.6), Vector2(0, length), Vector2(-length * 0.32, length * 0.6), Vector2(-length * 0.3, length * 0.25)])
	var b := Basis(Quaternion(Vector3.UP, dir.normalized()))
	k.extrude(outline, Transform3D(b, base), 0.003, 0.002, col, col.lightened(0.15), 0.5)
