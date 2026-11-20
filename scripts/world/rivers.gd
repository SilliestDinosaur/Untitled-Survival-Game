class_name Rivers
extends RefCounted
## Rivers and streams. A few big rivers run from the high ground down to the sea, widening as they go, and smaller
## streams run down to the sea or into a river. Each is planned from the base ground (so every machine plans the
## same ones) as a line of points, each with its water's surface height, the channel's half width and depth.
##
## The water's surface only ever steps down along a river, and always sits below the banks, so the water stays in
## its channel. The ground is cut to fit: a shallow rounded bed under the water, and valley sides that rise gently
## (BANK) from the water's edge until they meet the land, so you can always walk out of a river. Where a river would
## have to cut too deep into rising ground to go on, it ends in a pond instead.
##
## A plan is a Dictionary: {lines, segs, buckets, ponds}. segs are [a: Vector2, b: Vector2, surface_a, surface_b,
## half_width_a, half_width_b, depth_a, depth_b, line] pieces; ponds are [centre: Vector2, radius, surface, depth].
## Read-only once made (worker threads read it).

const BUCKET := 16.0
const STEP := 7.0          ## metres between points while tracing a river downhill
const SEG := 9.0           ## metres between points of the finished line
const BANK := 0.42         ## how steeply the valley sides rise from the water's edge (rise per metre)
const LIP := 0.5           ## the bank's lip: an extra rise of this much over LIP_RUN metres from the water's edge
const LIP_RUN := 1.9       ## (together with BANK, the steepest the bank gets is about 39 degrees: still walkable)
const REACH := 30.0        ## how far past the water's edge a valley may reach before it blends back into the land
const MAX_CUT := 13.0      ## a river ends (in a pond) rather than cut deeper than this below the land it runs into
const FLOW_BIG := 1.3      ## metres per second the big rivers flow (the streams half that)

static var material: ShaderMaterial   ## the rivers' water (Atmosphere keeps its sky and night in step with the sea's)


static func plan(gen: WorldGen) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "rivers"])
	var out := {"lines": [], "segs": [], "buckets": {}, "ponds": []}
	var taken: Array = []   # sources so far, kept apart
	var big := _sources(gen, rng, 24.0, 1e9, 360.0, rng.randi_range(2, 4), taken)
	var small := _sources(gen, rng, 9.0, 34.0, 150.0, rng.randi_range(5, 9), taken)
	for src: Vector2 in big:
		_add_river(gen, rng, out, src, true)
	for src: Vector2 in small:
		_add_river(gen, rng, out, src, false)
	return out


## High spots well inside the island to start rivers from, the highest first, at least `apart` from each other and
## from those already taken.
static func _sources(gen: WorldGen, rng: RandomNumberGenerator, min_h: float, max_h: float, apart: float, count: int, taken: Array) -> Array:
	var cands: Array = []
	for k in 900:
		var p := Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.12, 0.88)) * Game.WORLD_SIZE
		if gen.island_mask(p.x, p.y) < 0.95:
			continue
		var h := gen.get_base_height(p.x, p.y)
		if h < min_h or h > max_h or gen.get_normal(p.x, p.y).y < 0.75:
			continue
		cands.append([h, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array = []
	for c: Array in cands:
		if out.size() >= count:
			break
		var p: Vector2 = c[1]
		var ok := true
		for q: Vector2 in taken:
			if p.distance_to(q) < apart:
				ok = false
				break
		if ok:
			out.append(p)
			taken.append(p)
	return out


static func _add_river(gen: WorldGen, rng: RandomNumberGenerator, out: Dictionary, src: Vector2, big: bool) -> void:
	var traced := _trace(gen, rng, out, src)
	var pts: Array = traced.pts
	if pts.size() < (20 if big else 6):
		return
	# Smooth the bends, then space the points evenly.
	for _k in 2:
		pts = _chaikin(pts)
	pts = _resample(pts, SEG)
	# A stream that runs into a river stops at the river's edge, and comes down to the river's water there (rather
	# than lie over the river as a sheet at its own height).
	var join_surface := INF
	if traced.end == "join":
		while pts.size() > 4 and channel_distance(out, pts[pts.size() - 2]) < 0.0:
			pts.pop_back()
		var at: Vector2 = pts[pts.size() - 1]
		var hit := _nearest(out, at.x, at.y, 6.0)
		if not hit.is_empty():
			join_surface = float(hit.surface)
	var n := pts.size()
	if n < 4:
		return
	var surf := PackedFloat32Array()
	var wid := PackedFloat32Array()
	var dep := PackedFloat32Array()
	surf.resize(n)
	wid.resize(n)
	dep.resize(n)
	var s := INF
	for i in n:
		var t := float(i) / float(n - 1)
		var w := lerpf(2.8, 7.5, pow(t, 0.8)) if big else lerpf(1.7, 2.8, t)
		var d := lerpf(1.1, 2.3, t) if big else lerpf(0.45, 0.8, t)
		var p: Vector2 = pts[i]
		var tan: Vector2 = ((pts[mini(i + 1, n - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var side := Vector2(-tan.y, tan.x) * (w + 1.5)
		# The surface sits under the lowest of the middle and both banks, and never rises downstream.
		var low := minf(gen.get_base_height(p.x, p.y), minf(gen.get_base_height(p.x + side.x, p.y + side.y), gen.get_base_height(p.x - side.x, p.y - side.y)))
		# Well below the land, so the river runs in a bed of its own with banks standing over the water.
		s = minf(s, low - (1.1 if big else 0.75))
		if join_surface < INF and i >= n - 4:
			s = minf(s, lerpf(s, join_surface + 0.02, float(i - (n - 4)) / 3.0))
		surf[i] = s
		wid[i] = w
		dep[i] = d
	var line := (out.lines as Array).size()
	out.lines.append({"pts": pts, "surface": surf, "width": wid, "depth": dep, "big": big, "end": traced.end})
	var segs: Array = out.segs
	for i in n - 1:
		var si := segs.size()
		segs.append([pts[i], pts[i + 1], surf[i], surf[i + 1], wid[i], wid[i + 1], dep[i], dep[i + 1], line])
		var reach := maxf(wid[i], wid[i + 1]) + REACH
		_bucket(out.buckets, pts[i], pts[i + 1], reach, si)
	if traced.end == "pond":
		var c: Vector2 = pts[n - 1]
		var r := wid[n - 1] * 2.2 + 3.0
		var pond := [c, r, surf[n - 1], dep[n - 1] + 0.4]
		out.ponds.append(pond)
		_bucket(out.buckets, c, c, r + REACH, -1 - (out.ponds.size() - 1))


static func _bucket(buckets: Dictionary, a: Vector2, b: Vector2, reach: float, idx: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
	for bz in range(floori(lo.y / BUCKET), floori(hi.y / BUCKET) + 1):
		for bx in range(floori(lo.x / BUCKET), floori(hi.x / BUCKET) + 1):
			var key := Vector2i(bx, bz)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(idx)


## Downhill from `start`: each step takes the lowest of a fan of headings ahead (a little momentum, a little
## wander). Ends at the sea or a lake, on meeting a river already planned, or (in a pond) where it would have to cut
## too deep through rising ground.
static func _trace(gen: WorldGen, rng: RandomNumberGenerator, out: Dictionary, start: Vector2) -> Dictionary:
	var pts: Array = [start]
	var p := start
	var g := _grad(gen, p)
	var dir := -g.normalized() if g.length() > 0.0001 else Vector2.RIGHT.rotated(rng.randf() * TAU)
	var low := gen.get_base_height(p.x, p.y)
	var mid := Vector2.ONE * Game.WORLD_SIZE * 0.5
	for i in 300:
		# On the flats a river feels its way toward the coast (rather than wander about until it gives up).
		var seaward := (p - mid).normalized()
		var best_dir := dir
		var best_h := INF
		for k in 9:
			var a := (k - 4) * 0.2
			var dd := dir.rotated(a)
			var q := p + dd * STEP
			var h := gen.get_base_height(q.x, q.y) + absf(a) * 0.4 + rng.randf() * 0.3 - dd.dot(seaward) * 0.9
			if h < best_h:
				best_h = h
				best_dir = dd
		dir = (dir * 0.35 + best_dir * 0.65).normalized()
		p += dir * STEP
		pts.append(p)
		var h := gen.get_base_height(p.x, p.y)
		if h < 0.0:
			# Into the sea or a lake: a little further, so the river's mouth opens into the water.
			pts.append(p + dir * STEP)
			pts.append(p + dir * STEP * 2.0)
			return {"pts": pts, "end": "water"}
		if gen.island_mask(p.x, p.y) < 0.4:
			return {"pts": pts, "end": "water"}
		low = minf(low, h)
		if h - low > MAX_CUT:
			pts.pop_back()
			return {"pts": pts, "end": "pond"}
		if i > 2 and channel_distance(out, p) < 1.0:
			return {"pts": pts, "end": "join"}
	return {"pts": pts, "end": "pond"}


static func _grad(gen: WorldGen, p: Vector2) -> Vector2:
	var e := 4.0
	return Vector2(gen.get_base_height(p.x + e, p.y) - gen.get_base_height(p.x - e, p.y),
		gen.get_base_height(p.x, p.y + e) - gen.get_base_height(p.x, p.y - e))


static func _chaikin(pts: Array) -> Array:
	var out: Array = [pts[0]]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


static func _resample(pts: Array, spacing: float) -> Array:
	var out: Array = [pts[0]]
	var carry := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var at := spacing - carry
		while at <= len:
			out.append(a.lerp(b, at / len))
			at += spacing
		carry = len - (at - spacing)
	if (out[out.size() - 1] as Vector2).distance_to(pts[pts.size() - 1]) > spacing * 0.3:
		out.append(pts[pts.size() - 1])
	return out


# --- Lookups (any thread) --------------------------------------------------------------------------

## The ground with the rivers cut into it: their beds under the water, and their valley sides up to the land.
static func carve(plan: Dictionary, x: float, z: float, land: float) -> float:
	if plan.is_empty():
		return land
	var list: Variant = plan.buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if list == null:
		return land
	var p := Vector2(x, z)
	var out := land
	for si: int in list:
		var sf: float
		var w: float
		var dep: float
		var d: float
		if si >= 0:
			var s: Array = plan.segs[si]
			var a: Vector2 = s[0]
			var ab: Vector2 = s[1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			d = p.distance_to(a + ab * t)
			w = lerpf(s[4], s[5], t)
			sf = lerpf(s[2], s[3], t)
			dep = lerpf(s[6], s[7], t)
		else:
			var pd: Array = plan.ponds[-1 - si]
			d = p.distance_to(pd[0])
			w = pd[1]
			sf = pd[2]
			dep = pd[3]
		if d > w + REACH:
			continue
		var prof: float
		if d < w:
			var u := d / w
			prof = sf - dep * (1.0 - u * u)
		else:
			prof = sf + LIP * smoothstep(0.0, LIP_RUN, d - w) + BANK * (d - w)
			# Far out the valley blends back into the land, so it never ends in a step.
			prof = lerpf(prof, maxf(prof, land), smoothstep(w + REACH * 0.55, w + REACH, d))
		out = minf(out, prof)
	return out


## The height of the river or pond water at (x, z), or -INF where there's none.
static func surface_at(plan: Dictionary, x: float, z: float) -> float:
	var hit := _nearest(plan, x, z, 0.0)
	return float(hit.surface) if not hit.is_empty() else -INF


## How the water moves at (x, z): downstream, metres per second (zero out of the rivers and in ponds).
static func flow_at(plan: Dictionary, x: float, z: float) -> Vector2:
	var hit := _nearest(plan, x, z, 0.0)
	if hit.is_empty() or not hit.has("dir"):
		return Vector2.ZERO
	return (hit.dir as Vector2) * (FLOW_BIG if hit.big else FLOW_BIG * 0.5) * (1.0 - 0.6 * float(hit.edge))


## Whether (x, z) is in a river's or pond's water, or within `margin` metres of its edge.
static func near(plan: Dictionary, x: float, z: float, margin: float) -> bool:
	return not _nearest(plan, x, z, margin).is_empty()


## 1 in the water, falling to 0 a couple of metres up the bank: for the wet bed and bank colour.
static func wet(plan: Dictionary, x: float, z: float) -> float:
	var hit := _nearest(plan, x, z, 2.5)
	if hit.is_empty():
		return 0.0
	return 1.0 - smoothstep(-0.6, 2.5, float(hit.past))


## 1 along the strip of bank just above a river's water (wet, darker sand), 0 elsewhere.
static func waterline(plan: Dictionary, x: float, z: float) -> float:
	var hit := _nearest(plan, x, z, 1.6)
	if hit.is_empty():
		return 0.0
	var past := float(hit.past)
	return smoothstep(-0.3, 0.2, past) * (1.0 - smoothstep(0.7, 1.6, past))


## The river piece or pond whose water is at (x, z) (or within margin of its edge): {surface, past (metres past
## the edge, negative inside), edge (0 middle .. 1 edge), dir, big}; {} if none.
static func _nearest(plan: Dictionary, x: float, z: float, margin: float) -> Dictionary:
	if plan.is_empty():
		return {}
	var list: Variant = plan.buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if list == null:
		return {}
	var p := Vector2(x, z)
	var best := {}
	var best_past := margin
	for si: int in list:
		if si >= 0:
			var s: Array = plan.segs[si]
			var a: Vector2 = s[0]
			var ab: Vector2 = s[1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var w: float = lerpf(s[4], s[5], t)
			if d - w <= best_past:
				best_past = d - w
				best = {"surface": lerpf(s[2], s[3], t), "past": d - w, "edge": clampf(d / w, 0.0, 1.0), "dir": ab.normalized(),
					"big": bool(plan.lines[int(s[8])].big)}
		else:
			var pd: Array = plan.ponds[-1 - si]
			var d := p.distance_to(pd[0])
			if d - float(pd[1]) <= best_past:
				best_past = d - float(pd[1])
				best = {"surface": pd[2], "past": d - float(pd[1]), "edge": clampf(d / float(pd[1]), 0.0, 1.0), "big": false}
	return best


## Metres from p to the nearest river channel's edge planned so far (negative inside one); INF if none near.
static func channel_distance(plan: Dictionary, p: Vector2) -> float:
	var hit := _nearest(plan, p.x, p.y, 30.0)
	return float(hit.past) if not hit.is_empty() else INF


# --- Water meshes (main thread) --------------------------------------------------------------------

## A ribbon of water along each river (in pieces, each seen from a few hundred metres), and a disc on each pond.
static func build_meshes(plan: Dictionary, parent: Node3D, sea_material: ShaderMaterial) -> void:
	for c in parent.get_children():
		c.queue_free()
	if plan.is_empty():
		return
	material = sea_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("flow", 1.0)
	material.set_shader_parameter("depth_scale", 3.0)
	# The banks rise quickly from a river, so its waterline needs a wider band of foam than the sea's beaches, and
	# murkier shallows, to show where the water ends.
	material.set_shader_parameter("foam_width", 2.6)
	material.set_shader_parameter("clarity", 1.2)
	for line: Dictionary in plan.lines:
		var pts: Array = line.pts
		var n := pts.size()
		var piece_start := 0
		while piece_start < n - 1:
			var piece_end := mini(piece_start + 16, n - 1)
			var mi := _ribbon(line, piece_start, piece_end)
			if mi:
				parent.add_child(mi)
			piece_start = piece_end
	for pd: Array in plan.ponds:
		var c: Vector2 = pd[0]
		var mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(pd[1]) + 0.6
		disc.bottom_radius = float(pd[1]) + 0.6
		disc.height = 0.02
		disc.radial_segments = 28
		disc.rings = 1
		disc.cap_bottom = false
		mi.mesh = disc
		mi.material_override = material
		mi.position = Vector3(c.x, float(pd[2]) - 0.01, c.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 420.0
		parent.add_child(mi)


static func _ribbon(line: Dictionary, i0: int, i1: int) -> MeshInstance3D:
	var pts: Array = line.pts
	var surf: PackedFloat32Array = line.surface
	var wid: PackedFloat32Array = line.width
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3((pts[i0] as Vector2).x, surf[i0], (pts[i0] as Vector2).y)
	var along := 0.0
	for i in range(0, i0):
		along += (pts[i] as Vector2).distance_to(pts[i + 1])
	var rows: Array = []
	for i in range(i0, i1 + 1):
		if surf[i] < 0.12:
			break   # the sea takes over at the mouth
		var p: Vector2 = pts[i]
		var tan: Vector2 = ((pts[mini(i + 1, n - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var side := Vector2(-tan.y, tan.x)
		var half := wid[i] + 0.7   # a little under the banks, so the water's edge is hidden in them
		var row: Array = []
		for k in 5:
			var u := (k / 4.0) * 2.0 - 1.0
			var q := p + side * half * u
			row.append([Vector3(q.x, surf[i], q.y) - centre, Vector2((u + 1.0) * half, along)])
		rows.append(row)
		if i < n - 1:
			along += p.distance_to(pts[i + 1])
	if rows.size() < 2:
		return null
	for r in rows.size() - 1:
		for k in 4:
			var a: Array = rows[r][k]
			var b: Array = rows[r][k + 1]
			var c: Array = rows[r + 1][k]
			var d: Array = rows[r + 1][k + 1]
			for v: Array in [a, c, b, b, c, d]:
				st.set_uv(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	return mi
