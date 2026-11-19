class_name TreeModels
extends RefCounted
## Tree models built from real polygons. Wood is lofted along curved paths (root flare, bark ridges,
## recursive forks); canopies are noise-displaced icospheres with smooth normals, lit from above;
## leaves are two-sided cards scattered over the canopy surface; conifers are rings of triangles
## with ragged skirts. Everything goes into a MeshKit, so the same code gives the far LOD twin.


static var _ico_cache := {}
const FAR_MIN_BRANCH := 0.09   ## far versions skip branch tubes thinner than this (m)


# --- Triangles ----------------------------------------------------------------------------------

## One triangle with smooth per-vertex normals. Wound so its front faces along the normals (Godot
## front faces are clockwise: (c - a) x (b - a) points out of the front).
static func _tri(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-12:
		return
	if fn.dot(na + nb + nc) < 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
		var tc := cb
		cb = cc
		cc = tc
	kit.verts.append_array([a, b, c])
	kit.normals.append_array([na.normalized(), nb.normalized(), nc.normalized()])
	kit.colors.append_array([ca.srgb_to_linear(), cb.srgb_to_linear(), cc.srgb_to_linear()])


# --- Icosphere ----------------------------------------------------------------------------------

## Unit icosphere, subdivided `level` times. Cached: the same mesh is reused by every tree.
static func _icosphere(level: int) -> Dictionary:
	if _ico_cache.has(level):
		return _ico_cache[level]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10],
		[8, 6, 7], [9, 8, 1]]
	for _l in level:
		var cache := {}
		var next: Array = []
		for f: Array in faces:
			var m0 := _midpoint(v, cache, f[0], f[1])
			var m1 := _midpoint(v, cache, f[1], f[2])
			var m2 := _midpoint(v, cache, f[2], f[0])
			next.append([f[0], m0, m2])
			next.append([f[1], m1, m0])
			next.append([f[2], m2, m1])
			next.append([m0, m1, m2])
		faces = next
	var out := {"verts": PackedVector3Array(v), "faces": faces}
	_ico_cache[level] = out
	return out


static func _midpoint(v: Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if not cache.has(key):
		v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
		cache[key] = v.size() - 1
	return cache[key]


## Subdivision level for blobs: finer when the detail is high. The far twins are built at low detail, which gets
## the plain 20-face icosahedron; full trees get one subdivision.
## Far versions (the low-poly twins drawn past the nearest chunks and used for shadows): round sections need few
## sides at that distance, and leaf cards are too small to see.
static func _far() -> bool:
	return MeshKit.detail < 0.4


static func _sides(n: int) -> int:
	return maxi(4, roundi(n * 0.6)) if _far() else n


static func _level() -> int:
	if MeshKit.detail >= 0.7:
		return 2
	if MeshKit.detail >= 0.4:
		return 1
	return 0


# --- Canopy blobs and leaves --------------------------------------------------------------------

## A puffy canopy volume: a displaced icosphere. Its surface gets smooth normals, sunlit tops and cool
## undersides, and a scatter of leaf cards. Returns the blob's surface (for more leaves).
static func blob(kit: MeshKit, rng: RandomNumberGenerator, center: Vector3, radius: float, squash: float,
		color: Color, leaf_density := 0.5) -> void:
	var ico := _icosphere(_level())
	var unit: PackedVector3Array = ico.verts
	var faces: Array = ico.faces
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	var p := PackedVector3Array()
	p.resize(unit.size())
	for i in unit.size():
		var u := unit[i]
		var d := 1.0 + noise.get_noise_3dv(u * 1.9 + center * 0.2) * 0.2
		p[i] = center + Vector3(u.x * radius * d, u.y * radius * d * squash, u.z * radius * d)
	# Smooth normals: each vertex averages the outward normals of the faces around it.
	var nrm := PackedVector3Array()
	nrm.resize(p.size())
	for f: Array in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var centroid := (a + b + c) / 3.0
		var fn := (c - a).cross(b - a).normalized()
		if fn.dot(centroid - center) < 0.0:
			fn = -fn
		for vi: int in f:
			nrm[vi] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()
	var top_col := color.lightened(0.06)
	var low_col := color.darkened(0.32).lerp(Color(0.18, 0.3, 0.2), 0.3)
	var cols := PackedColorArray()
	cols.resize(p.size())
	for i in p.size():
		var up := smoothstep(-0.7, 0.7, nrm[i].y)
		cols[i] = low_col.lerp(top_col, up)
	for f: Array in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var centroid := (a + b + c) / 3.0
		var outward := centroid - center
		_tri(kit, a, b, c, nrm[f[0]], nrm[f[1]], nrm[f[2]], cols[f[0]], cols[f[1]], cols[f[2]])
		# Leaves on some faces, pointing out of the surface. Fewer at lower detail (leaf cards are most of a crown's triangles).
		if rng.randf() < leaf_density * MeshKit.detail and not _far():
			var fn := (c - a).cross(b - a).normalized()
			if fn.dot(outward) < 0.0:
				fn = -fn
			leaf(kit, rng, centroid + fn * 0.06, fn, radius * rng.randf_range(0.22, 0.34), color)


## A leaf card: a pointed quad, double-sided so it reads from above and below.
static func leaf(kit: MeshKit, rng: RandomNumberGenerator, at: Vector3, n: Vector3, size: float, color: Color) -> void:
	if not MeshKit.leaves or _far():
		return
	var helper := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var t := n.cross(helper).normalized().rotated(n, rng.randf() * TAU)
	var s := n.cross(t).normalized()
	var tip := at + t * size * rng.randf_range(0.9, 1.25)
	var left := at + t * size * 0.45 + s * size * 0.34
	var right := at + t * size * 0.45 - s * size * 0.34
	var base_col := color.darkened(0.15).lightened(rng.randf_range(-0.04, 0.08))
	var tip_col := color.lightened(rng.randf_range(0.0, 0.12))
	_tri(kit, at, left, tip, n, n, n, base_col, base_col, tip_col)
	_tri(kit, at, tip, right, n, n, n, base_col, tip_col, base_col)
	_tri(kit, at, tip, left, -n, -n, -n, base_col, tip_col, base_col)
	_tri(kit, at, right, tip, -n, -n, -n, base_col, base_col, tip_col)


# --- Wood ---------------------------------------------------------------------------------------

## Bark ridges and knots: a colour pattern around a loft.
static func bark_fn(bark: Color, phase: float) -> Callable:
	return func(t: float, a: float) -> Color:
		var ridge := sin(a * 7.0 + phase + sin(t * 9.0 + phase) * 0.8)
		return bark.darkened(0.1).lerp(bark.lightened(0.08), smoothstep(-0.3, 0.6, ridge))


## A branch from `start` along `dir`: lofted with bark, then forking into smaller branches until
## depth runs out. The branch tips are collected in `tips` (where the canopy goes).
static func branch(kit: MeshKit, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float,
		radius: float, depth: int, bark: Color, tips: Array, sides := 7) -> void:
	var seg := 3
	var bend := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)) * length
	var path: Array = []
	var radii: Array = []
	for i in seg + 1:
		var t := float(i) / seg
		path.append(start + dir * length * t + bend * t * t)
		radii.append(radius * lerpf(1.0, 0.3, t))
	var phase := rng.randf() * 10.0
	# Far away the thin twigs are a pixel wide or inside the canopy: skip their tubes, but still grow the tree the
	# same way, so the canopy blobs sit where they do up close.
	if not (_far() and radius < FAR_MIN_BRANCH):
		kit.loft(path, radii, _sides(sides), bark, bark_fn(bark, phase), Callable(), true, true, 0.035)
	var end: Vector3 = path[seg]
	if depth <= 0 or radius < 0.035:
		tips.append(end)
		return
	var kids := rng.randi_range(2, 3)
	for k in kids:
		var yaw := rng.randf() * TAU + float(k) * TAU / kids
		var tilt := rng.randf_range(0.5, 0.95)
		var nd := (dir + Vector3(cos(yaw), 0.0, sin(yaw)) * tilt).normalized()
		branch(kit, rng, end, nd, length * rng.randf_range(0.55, 0.75), radius * 0.62, depth - 1, bark, tips, maxi(4, sides - 1))


## A trunk: a loft with a root flare at the base, tapering up to `top`.
static func trunk(kit: MeshKit, rng: RandomNumberGenerator, base: Vector3, height: float, radius: float,
		bark: Color, lean := Vector3.ZERO, sides := 8, flare := 0.7) -> Vector3:
	var seg := 5
	var path: Array = []
	var radii: Array = []
	for i in seg + 1:
		var t := float(i) / seg
		path.append(base + Vector3(0, height * t, 0) + lean * t * t)
		var foot := 1.0 + flare * maxf(0.0, 1.0 - t * 4.0)   # buttressed foot
		radii.append(radius * (1.0 - 0.28 * t) * foot)
	kit.loft(path, radii, _sides(sides), bark, bark_fn(bark, rng.randf() * 10.0), Callable(), true, false, 0.05)
	return path[seg]


# --- Species ------------------------------------------------------------------------------------

## Round broadleaf: a trunk, a fork of branches, and a crown of blobs at the branch tips.
static func round_tree(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, leaf: Color, height: float,
		radius: float, crown_radius: float) -> void:
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
	var top := trunk(kit, rng, Vector3.ZERO, height, radius, bark, lean)
	var tips: Array = []
	var forks := rng.randi_range(3, 4)
	for i in forks:
		var yaw := rng.randf() * TAU
		var start := top - lean * 0.5 + Vector3(0, -height * rng.randf_range(0.12, 0.25), 0)
		var dir := (Vector3(cos(yaw), rng.randf_range(0.35, 0.8), sin(yaw))).normalized()
		branch(kit, rng, start, dir, height * rng.randf_range(0.42, 0.55), radius * 0.7, 2, bark, tips)
	tips.append(top)
	for tip: Vector3 in tips:
		var r := crown_radius * rng.randf_range(0.7, 1.1)
		blob(kit, rng, tip + Vector3(0, r * 0.25, 0), r, rng.randf_range(0.78, 0.92), leaf.lightened(rng.randf_range(-0.06, 0.06)), 0.55)


## Conifer: tiers of ragged rings stacked up a trunk, each with a drooping skirt of needles.
static func conifer(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, leaf: Color, tiers: int,
		height: float, radius: float) -> void:
	var base_y := height * rng.randf_range(0.16, 0.24)
	# The trunk stops just inside the lowest tier. Running it up through the crown let it poke out through the tiers
	# near their narrow tops, as bark-coloured triangles on the needles.
	trunk(kit, rng, Vector3.ZERO, base_y + radius * 0.35, radius * 0.5, bark, Vector3.ZERO, 6, 0.12)
	for t in tiers:
		var f := float(t) / maxf(tiers - 1, 1)
		var r := lerpf(radius, radius * 0.32, f) * rng.randf_range(0.92, 1.08)
		var y0 := lerpf(base_y, height * 0.72, f)
		var tier_h := (height - y0) / float(tiers) * 1.9
		_tier(kit, rng, Vector3(0, y0, 0), r, tier_h, leaf.lightened(0.1 * f - 0.02 * (t % 2)))
	# Leader: the top spike.
	_tier(kit, rng, Vector3(0, height * 0.7, 0), radius * 0.22, height * 0.22, leaf.lightened(0.14))


## One conifer tier: a ring of jagged points around `base`, meeting at a tip above it. Alternate points
## droop, so the edge reads as needles.
static func _tier(kit: MeshKit, rng: RandomNumberGenerator, base: Vector3, r: float, h: float, color: Color) -> void:
	var sides := maxi(8, roundi(10.0 * MeshKit.detail))   # cheap, and fewer sides read as a pyramid
	var spin := rng.randf() * TAU
	var tip := base + Vector3(0, h, 0)
	var ring: Array = []
	for i in sides:
		var a := TAU * float(i) / sides + spin
		var rr := r * (0.82 + 0.18 * sin(float(i) * 2.7 + spin) * 0.5 + 0.09 * float(i % 2))
		var droop := (0.12 * r) if i % 2 == 1 else 0.0
		ring.append(base + Vector3(cos(a) * rr, -droop, sin(a) * rr))
	var dark := color.darkened(0.3)
	for i in sides:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % sides]
		var mid := (a + b) * 0.5
		var n := ((mid - base) + Vector3(0, r * 0.5, 0)).normalized()
		_tri(kit, a, b, tip, n, n, Vector3.UP, color.darkened(0.12), color.darkened(0.12), color.lightened(0.2))
		# Underside of the skirt, a little darker.
		_tri(kit, base, b, a, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, dark, dark, dark)
		if rng.randf() < 0.55:
			leaf(kit, rng, mid, (mid - base + Vector3(0, -0.2 * r, 0)).normalized(), r * 0.32, color)
	# A few loose needle cards along the skirt.
	for i in sides:
		var a: Vector3 = ring[i]
		var outward := (a - base).normalized()
		leaf(kit, rng, a, outward.lerp(Vector3.DOWN, 0.5).normalized(), r * 0.26, color)


## Umbrella tree (acacia): a leaning trunk, then a flat, wide canopy with a ragged rim.
static func umbrella(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, leaf: Color, height: float, radius: float) -> void:
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var top := trunk(kit, rng, Vector3.ZERO, height, radius, bark, lean, 7)
	var tips: Array = []
	branch(kit, rng, top - Vector3(0, height * 0.2, 0), Vector3(rng.randf_range(-0.7, 0.7), 0.6, rng.randf_range(-0.7, 0.7)).normalized(), height * 0.4, radius * 0.6, 1, bark, tips, 5)
	var canopy := top + Vector3(0, 0.3, 0)
	# The flat-topped crown: a ring of wide, squashed leaf clumps round a middle one, overlapping into one broad
	# layer, with a few smaller puffs on top. Each clump is shaded like any canopy (sunlit top, darker underside).
	# (It used to be a cone with one straight-up normal, which lit as a flat pale plate.)
	var rim_r := rng.randf_range(2.6, 3.4)
	var clumps := 6
	var turn := rng.randf() * TAU
	blob(kit, rng, canopy + Vector3(0, 0.25, 0), rim_r * 0.5, 0.45, leaf.darkened(0.03), 0.3)
	for i in clumps:
		var a := turn + TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / clumps
		var d := rim_r * rng.randf_range(0.5, 0.62)
		blob(kit, rng, canopy + Vector3(cos(a) * d, rng.randf_range(0.0, 0.15), sin(a) * d), rim_r * rng.randf_range(0.36, 0.44), 0.42,
			leaf.darkened(rng.randf_range(0.0, 0.06)), 0.3)
	for i in 3:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, rim_r * 0.45)
		blob(kit, rng, canopy + Vector3(cos(a) * d, 0.75, sin(a) * d), rng.randf_range(0.7, 0.95), 0.55, leaf.lightened(0.03), 0.4)
	for tip: Vector3 in tips:
		blob(kit, rng, tip, 0.9, 0.7, leaf, 0.4)


## Jungle giant: a tall trunk with buttresses, a dense dome of foliage and hanging vines.
static func jungle(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, leaf: Color, height: float, radius: float) -> void:
	var top := trunk(kit, rng, Vector3.ZERO, height, radius, bark, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), 9)
	var tips: Array = []
	for i in rng.randi_range(4, 6):
		var yaw := rng.randf() * TAU
		var dir := Vector3(cos(yaw), rng.randf_range(0.3, 0.7), sin(yaw)).normalized()
		branch(kit, rng, top - Vector3(0, height * 0.22, 0), dir, height * rng.randf_range(0.3, 0.4), radius * 0.55, 2, bark, tips, 6)
	tips.append(top)
	for tip: Vector3 in tips:
		var r := rng.randf_range(1.5, 2.1)
		blob(kit, rng, tip + Vector3(0, r * 0.3, 0), r, rng.randf_range(0.7, 0.85), leaf.lightened(rng.randf_range(-0.05, 0.05)), 0.5)
	# Vines: thin tapered wood hanging from the canopy.
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var start := top + Vector3(cos(a) * 2.2, rng.randf_range(-0.8, 0.2), sin(a) * 2.2)
		var length := rng.randf_range(2.0, 4.0)
		var path: Array = []
		var radii: Array = []
		for k in 4:
			var t := float(k) / 3.0
			path.append(start + Vector3(sin(t * 2.0 + a) * 0.25, -length * t, cos(t * 2.0 + a) * 0.25))
			radii.append(lerpf(0.035, 0.012, t))
		kit.loft(path, radii, 4, leaf.darkened(0.2), Callable(), Callable(), true, true)


## Dead tree: bare gnarled branches, no canopy.
static func dead(kit: MeshKit, rng: RandomNumberGenerator, wood: Color, height: float, radius: float) -> void:
	var top := trunk(kit, rng, Vector3.ZERO, height, radius, wood, Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)), 6)
	var tips: Array = []
	for i in rng.randi_range(3, 5):
		var yaw := rng.randf() * TAU
		var start := top - Vector3(0, height * rng.randf_range(0.05, 0.4), 0)
		var dir := Vector3(cos(yaw), rng.randf_range(0.3, 0.9), sin(yaw)).normalized()
		branch(kit, rng, start, dir, height * rng.randf_range(0.3, 0.45), radius * 0.6, 2, wood, tips, 5)
	tips.append(top)
	for tip: Vector3 in tips:
		if rng.randf() < 0.4:
			branch(kit, rng, tip, Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), 0.4, radius * 0.25, 0, wood, [], 4)


## Birch: a slim pale trunk with dark marks, a loose airy crown of small blobs.
static func birch(kit: MeshKit, rng: RandomNumberGenerator, bark: Color, leaf: Color, height: float, radius: float) -> void:
	var top := trunk(kit, rng, Vector3.ZERO, height, radius, bark, Vector3(rng.randf_range(-0.12, 0.12), 0, 0), 7, 0.15)
	var tips: Array = []
	for i in rng.randi_range(3, 5):
		var yaw := rng.randf() * TAU
		var start := top - Vector3(0, height * rng.randf_range(0.18, 0.4), 0)
		var dir := Vector3(cos(yaw), rng.randf_range(0.5, 0.9), sin(yaw)).normalized()
		branch(kit, rng, start, dir, height * rng.randf_range(0.2, 0.3), radius * 0.6, 1, bark, tips, 5)
	tips.append(top)
	for tip: Vector3 in tips:
		var r := rng.randf_range(0.8, 1.2)
		blob(kit, rng, tip, r, rng.randf_range(1.1, 1.3), leaf.lightened(rng.randf_range(-0.05, 0.1)), 0.45)
