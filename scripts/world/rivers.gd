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
const BANK := 0.28         ## how steeply the valley sides rise from the water's edge (rise per metre)
const LIP := 0.35           ## the bank's lip: an extra rise of this much over LIP_RUN metres from the water's edge
const LIP_RUN := 3.2       ## (together with BANK, the steepest the bank gets is about 25 degrees)
const END_RISE := 1.6      ## how fast a stretch's cut rises past its ends (rise per metre)
const REACH := 28.0        ## how far past the water's edge a valley may reach before it blends back into the land
const MAX_CUT := 13.0      ## a river ends (in a pond) rather than cut deeper than this below the land it runs into
const FLOW_BIG := 1.3      ## metres per second the big rivers flow (the streams half that)

static var material: ShaderMaterial   ## the rivers' water (Atmosphere keeps its sky and night in step with the sea's)
static var pond_material: ShaderMaterial


static func plan(gen: WorldGen) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "rivers"])
	var out := {"lines": [], "segs": [], "buckets": {}, "ponds": [], "heads": []}
	var taken: Array = []   # sources so far, kept apart
	var wide := Game.WORLD_SIZE / 2048.0   # a bigger island has more rivers (and longer ones, to reach its coast)
	var big := _sources(gen, rng, 24.0, 1e9, 360.0, roundi(rng.randi_range(2, 4) * wide), taken)
	var small := _sources(gen, rng, 9.0, 34.0, 150.0, roundi(rng.randi_range(5, 9) * wide), taken)
	for src: Vector2 in big:
		_add_river(gen, rng, out, src, true)
	for src: Vector2 in small:
		_add_river(gen, rng, out, src, false)
	return out


## High spots well inside the island to start rivers from, the highest first, at least `apart` from each other and
## from those already taken.
static func _sources(gen: WorldGen, rng: RandomNumberGenerator, min_h: float, max_h: float, apart: float, count: int, taken: Array) -> Array:
	var cands: Array = []
	for k in roundi(900 * pow(Game.WORLD_SIZE / 2048.0, 2.0)):   # (as many tries per square metre on any size of island)
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
	if channel_distance(out, src) < REACH + 8.0:
		return   # starting right by another river: their valleys would undercut each other
	var traced := _trace(gen, rng, out, src, 21.0 if big else 10.0)
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
		var nxt: Vector2 = pts[mini(i + 1, n - 1)]
		var tan: Vector2 = (nxt - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var side := Vector2(-tan.y, tan.x) * (w + 1.5)
		# The surface sits under the lowest ground of the middle and both banks, here and all along the stretch to the
		# next point (the water runs straight from point to point, so it must clear the lowest dip in between), and
		# never rises downstream.
		var low := INF
		for k in 5:
			var c: Vector2 = p.lerp(nxt, k / 4.0)
			low = minf(low, minf(gen.get_base_height(c.x, c.y), minf(gen.get_base_height(c.x + side.x, c.y + side.y), gen.get_base_height(c.x - side.x, c.y - side.y))))
		# Well below the land, so the river runs in a bed of its own with banks standing over the water.
		s = minf(s, low - (1.1 if big else 0.75))
		if join_surface < INF and i >= n - 4:
			s = minf(s, lerpf(s, join_surface + 0.05, float(i - (n - 4)) / 3.0))
		surf[i] = s
		wid[i] = w
		dep[i] = d
	var line := (out.lines as Array).size()
	# A river that ends short of the sea ends in a pond, kept clear of every river's course (its valley would undercut
	# their banks), its own too; with no room for one the river isn't made at all (it would just stop, dry).
	var pond: Array = []
	if traced.end == "pond":
		var c: Vector2 = pts[n - 1]
		var r := wid[n - 1] * 1.6 + 2.5
		for s2: Array in out.segs:
			var a2: Vector2 = s2[0]
			var ab2: Vector2 = s2[1] - a2
			var t2 := clampf((c - a2).dot(ab2) / maxf(ab2.length_squared(), 0.0001), 0.0, 1.0)
			r = minf(r, c.distance_to(a2 + ab2 * t2) - lerpf(s2[4], s2[5], t2) - REACH)
		for k2 in n - 4:
			r = minf(r, c.distance_to(pts[k2]) - wid[k2] - REACH)
		if r < 3.0:
			return
		pond = [c, r, surf[n - 1], dep[n - 1] + 0.4]
	# Where it rises: a pool at its head, the river running out of it. Against a steep rise (the head cut into a
	# hillside, a wall above it) the water comes out of the rock above the pool; on gentler ground it wells up into
	# the pool itself. The pool sits a little below the ground round it, and the river never above the pool.
	var head: Vector2 = pts[0]
	var up: Vector2 = (head - (pts[1] as Vector2)).normalized()
	var rise := 0.0
	for d2 in [3.0, 6.0]:
		var q: Vector2 = head + up * d2
		rise = maxf(rise, gen.get_base_height(q.x, q.y) - surf[0])
	var rock := rise > 4.0
	var hr := wid[0] * 1.5 + (1.6 if rock else 1.2)
	var hc := head + up * hr * 0.45
	var rim := INF
	for k in 12:
		var a := TAU * k / 12.0
		var q := hc + Vector2(cos(a), sin(a)) * (hr + 1.5)
		rim = minf(rim, gen.get_base_height(q.x, q.y))
	var hs := minf(surf[0], rim - 0.35)
	for i in n:
		surf[i] = minf(surf[i], hs)
	var reach_h := 5.0 if rock else 10.0
	# [centre, radius, surface, depth, bank reach, "head"/"neck", outlet direction]. The neck, between the pool and
	# the channel, flares the banks from the round pool into the river's, so they meet in a curve, not a corner.
	var head_pond := [hc, hr, hs, dep[0] + 0.35, reach_h, "head", -up]
	var out_p: Vector2 = pts[1]
	var neck := [hc.lerp(out_p, 0.55), lerpf(hr, wid[1] + 0.6, 0.55), hs, lerpf(dep[0] + 0.35, dep[1], 0.5), reach_h, "neck", -up]
	out.heads.append({"c": hc, "up": up, "rock": rock, "r": hr, "surface": hs, "rise": rise, "big": big,
		"out_p": out_p, "out_s": surf[1], "out_w": wid[1]})
	out.lines.append({"pts": pts, "surface": surf, "width": wid, "depth": dep, "big": big, "end": traced.end, "head_c": hc, "head_r": hr})
	var segs: Array = out.segs
	for i in n - 1:
		var si := segs.size()
		segs.append([pts[i], pts[i + 1], surf[i], surf[i + 1], wid[i], wid[i + 1], dep[i], dep[i + 1], line])
		var reach := maxf(wid[i], wid[i + 1]) + REACH
		_bucket(out.buckets, pts[i], pts[i + 1], reach, si)
	if pond.is_empty() == false:
		out.ponds.append(pond)
		_bucket(out.buckets, pond[0], pond[0], float(pond[1]) + REACH, -1 - (out.ponds.size() - 1))
	for hp: Array in [head_pond, neck]:
		out.ponds.append(hp)
		_bucket(out.buckets, hp[0], hp[0], float(hp[1]) + float(hp[4]), -1 - (out.ponds.size() - 1))


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
static func _trace(gen: WorldGen, rng: RandomNumberGenerator, out: Dictionary, start: Vector2, clear: float) -> Dictionary:
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
			if _near_own(pts, q, clear):
				continue   # never back across its own course
			if h < best_h:
				best_h = h
				best_dir = dd
		if best_h == INF:
			return {"pts": pts, "end": "pond"}   # boxed in by its own bends
		dir = (dir * 0.35 + best_dir * 0.65).normalized()
		if _near_own(pts, p + dir * STEP, clear):
			dir = best_dir
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
		if i > 2 and (channel_distance(out, p) < 1.0 or channel_distance(out, p - dir * STEP * 0.5) < 1.0):
			return {"pts": pts, "end": "join"}
		# Close to another river: run into it (rivers side by side at different heights would undercut each other's
		# banks with their valleys).
		if i > 2:
			var near_pt: Variant = _nearest_channel_point(out, p, 25.0)
			if near_pt != null:
				var to: Vector2 = near_pt
				for k in 8:
					var step := minf(STEP, p.distance_to(to))
					if step < 0.5:
						break
					p += (to - p).normalized() * step
					pts.append(p)
					if channel_distance(out, p) < 1.0:
						break
				return {"pts": pts, "end": "join"}
	return {"pts": pts, "end": "pond"}


## Whether q comes within `reach` of the river's own course, short of its last few points.
static func _near_own(pts: Array, q: Vector2, reach: float) -> bool:
	for k in maxi(pts.size() - 4, 0):
		if (pts[k] as Vector2).distance_to(q) < reach:
			return true
	return false


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
		var beyond := 0.0
		if si >= 0:
			var s: Array = plan.segs[si]
			var a: Vector2 = s[0]
			var ab: Vector2 = s[1] - a
			var len2 := maxf(ab.length_squared(), 0.0001)
			var raw_t := (p - a).dot(ab) / len2
			var t := clampf(raw_t, 0.0, 1.0)
			d = p.distance_to(a + ab * t)
			w = lerpf(s[4], s[5], t)
			sf = lerpf(s[2], s[3], t)
			dep = lerpf(s[6], s[7], t)
			# Past its upstream end a stretch's cut rises quickly: its banks run beside it, not up the slope above it
			# (on a steep river the stretch below would otherwise dig under the water of the stretch above). Not past
			# its downstream end: the next stretch (as low or lower) carries on from there, and raising it would heap
			# up the outside of every bend, a crease up the bank and a spit of land poking out of the water.
			beyond = maxf(-raw_t, 0.0) * sqrt(len2)
		var reach := REACH
		if si < 0:
			var pd: Array = plan.ponds[-1 - si]
			d = p.distance_to(pd[0])
			w = pd[1]
			sf = pd[2]
			dep = pd[3]
			if pd.size() > 4:
				reach = pd[4]   # a spring's pool: a short bank, the rise behind it left standing
		if d > w + reach:
			continue
		var prof: float
		if d < w:
			var u := d / w
			prof = sf - dep * (1.0 - u * u)
		else:
			prof = sf + LIP * smoothstep(0.0, LIP_RUN, d - w) + BANK * (d - w)
			# Far out the valley blends back into the land, so it never ends in a step.
			prof = lerpf(prof, maxf(prof, land), smoothstep(w + reach * 0.55, w + reach, d))
		if beyond > 0.0:
			prof += beyond * END_RISE
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


## The nearest river piece or pond within `margin` metres of its edge ({surface, past, edge, big}; {} if none).
static func nearest_water(plan: Dictionary, x: float, z: float, margin: float) -> Dictionary:
	return _nearest(plan, x, z, margin)


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
static func _nearest(plan: Dictionary, x: float, z: float, margin: float, skip_line := -1) -> Dictionary:
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
			if int(s[8]) == skip_line:
				continue
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


## The middle of the nearest river channel planned so far whose edge is within `reach` of p; null if none.
static func _nearest_channel_point(plan: Dictionary, p: Vector2, reach: float) -> Variant:
	if plan.is_empty():
		return null
	var list: Variant = plan.buckets.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)))
	if list == null:
		return null
	var best := reach
	var out: Variant = null
	for si: int in list:
		if si < 0:
			continue
		var s: Array = plan.segs[si]
		var a: Vector2 = s[0]
		var ab: Vector2 = s[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * t
		var past := p.distance_to(c) - lerpf(s[4], s[5], t)
		if past < best:
			best = past
			out = c
	return out


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
	pond_material = sea_material.duplicate() as ShaderMaterial   # still water: the sea's own shoreline foam
	pond_material.set_shader_parameter("depth_scale", 3.0)
	material.set_shader_parameter("flow", 1.0)
	material.set_shader_parameter("depth_scale", 3.0)
	# The ribbon draws its own foam line where its edges meet the banks, so the depth-based band is kept narrow: a
	# wide one turns a whole stream white (they're well under a metre deep). Murkier shallows show where it ends.
	material.set_shader_parameter("foam_width", 0.55)
	material.set_shader_parameter("clarity", 1.2)
	var gen: WorldGen = Game.world_gen
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "river dressing"])
	var mat := ArtStyle.painted({"brush_strength": 0.25})
	for line: Dictionary in plan.lines:
		var pts: Array = line.pts
		var n := pts.size()
		var piece_start := 0
		while piece_start < n - 1:
			var piece_end := mini(piece_start + 16, n - 1)
			var mi := _ribbon(plan, line, piece_start, piece_end)
			if mi:
				parent.add_child(mi)
			var deco := _dress(gen, plan, line, piece_start, piece_end, rng, mat)
			if deco:
				parent.add_child(deco)
			piece_start = piece_end
	_cascades(plan, parent)
	for pd: Array in plan.ponds:
		if pd.size() > 5 and pd[5] == "neck":
			continue
		var deco := _dress_pond(gen, pd, rng, mat)
		if deco:
			parent.add_child(deco)
	for hd: Dictionary in plan.get("heads", []):
		_dress_head(gen, hd, rng, mat, parent)
	for hd: Dictionary in plan.get("heads", []):
		parent.add_child(_head_water(hd))
	for pd: Array in plan.ponds:
		if pd.size() > 5:
			continue   # a spring's pool: its water is drawn with its outlet (see _head_water)
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
		mi.material_override = pond_material
		mi.position = Vector3(c.x, float(pd[2]) - 0.04, c.y)   # just under the stream running into it (no flicker where they overlap)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 420.0
		mi.set_meta("water", true)
		parent.add_child(mi)


## Where a river drops steeply (a run of rapids, a little fall): spray hanging over the white water and the rush of it.
## The steepest spot of each steep run, kept well apart, a dozen at most on an island.
static func _cascades(plan: Dictionary, parent: Node3D) -> void:
	var spots: Array = []
	for line: Dictionary in plan.lines:
		var pts: Array = line.pts
		var surf: PackedFloat32Array = line.surface
		for i in range(1, pts.size() - 1):
			var run := (pts[i - 1] as Vector2).distance_to(pts[i + 1])
			var steep := (surf[i - 1] - surf[i + 1]) / maxf(run, 0.5)
			if steep < 0.3 or surf[i] < 0.5:
				continue
			spots.append([steep, Vector3((pts[i] as Vector2).x, surf[i], (pts[i] as Vector2).y), float(line.width[i])])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var kept: Array = []
	for sp: Array in spots:
		if kept.size() >= 12:
			break
		var far := true
		for k: Array in kept:
			if (k[1] as Vector3).distance_to(sp[1]) < 35.0:
				far = false
				break
		if far:
			kept.append(sp)
	for sp: Array in kept:
		var node := Node3D.new()
		node.name = "Cascade"
		node.position = sp[1]
		parent.add_child(node)
		var spray := Effects.spray(float(sp[2]))
		node.add_child(spray)
		node.set_meta("spray", spray)
		Audio.rush_loop(node)


## Spray and rush only near the camera (they cost nothing further off).
static func update_cascades(parent: Node3D, eye: Vector3) -> void:
	for c in parent.get_children():
		if c.has_meta("spray"):
			var p := c.get_meta("spray") as CPUParticles3D
			var on := (c as Node3D).global_position.distance_squared_to(eye) < 70.0 * 70.0
			var rush_off := false
			for a in c.get_children():
				if a is AudioStreamPlayer3D and on and (a as AudioStreamPlayer3D).stream and not a.playing:
					rush_off = true   # (its sound was made after the spray came on)
			if p.emitting != on or rush_off:
				p.emitting = on
				# The rush too: nothing to mix while it's out of earshot.
				for a in c.get_children():
					if a is AudioStreamPlayer3D and (a as AudioStreamPlayer3D).stream:
						if on and not a.playing:
							a.play(randf() * 5.0)
						elif not on:
							a.stop()


## How far the river water is drawn: never past the terrain that's loaded (with a low view distance it would
## otherwise run on out over the empty sea beyond the land's edge).
static func set_view_range(parent: Node, metres: float) -> void:
	for c in parent.get_children():
		if c is MeshInstance3D and c.has_meta("water"):
			(c as MeshInstance3D).visibility_range_end = minf(420.0, metres)


static func _ribbon(plan: Dictionary, line: Dictionary, i0: int, i1: int) -> MeshInstance3D:
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
	var joins: bool = line.end == "join"
	var own := (plan.lines as Array).find(line)
	var mouth := false
	for i in range(i0, i1 + 1):
		if mouth:
			break
		var p: Vector2 = pts[i]
		var y := surf[i]
		if y < 0.12:   # the sea takes over at the mouth: one last row sunk just under it, so there's no edge or step
			y = Game.SEA_LEVEL - 0.08
			mouth = true
		# Another river's water takes over where this one runs into it (two sheets of water at one height flicker): one
		# last row, just under that river's surface, so this one runs right in rather than stopping short on the bank.
		if joins and i >= n - 4:
			var other := _nearest(plan, p.x, p.y, -0.2, own)
			if not other.is_empty():
				y = minf(y, float(other.surface) - 0.05)
				mouth = true
		var tan: Vector2 = ((pts[mini(i + 1, n - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		# How steeply the water falls here (rise per metre): white water where it's steep (see water.gdshader).
		var i_a := maxi(i - 1, 0)
		var i_b := mini(i + 1, n - 1)
		var steep := clampf((surf[i_a] - surf[i_b]) / maxf((pts[i_a] as Vector2).distance_to(pts[i_b]), 0.5), 0.0, 1.0)
		var side := Vector2(-tan.y, tan.x)
		var half := wid[i] + 0.7   # a little under the banks, so the water's edge is hidden in them
		# Out of its spring's pool: the flowing water fades in over the pool's still water, from inside the pool to
		# past its rim, so there's no edge where one becomes the other.
		var fade := 0.0
		if line.has("head_c"):
			var hr: float = line.head_r
			fade = 1.0 - smoothstep(hr * 0.6, hr + 2.5, p.distance_to(line.head_c))
		var row: Array = []
		for k in 5:
			var u := (k / 4.0) * 2.0 - 1.0
			var q := p + side * half * u
			# No waterline foam where a stream runs out into the river it joins (where its edges are over that river's
			# water); up to there its banks foam like any other.
			var inset := 0.7
			if joins and i >= n - 4 and not _nearest(plan, q.x, q.y, 0.0, own).is_empty():
				inset = -99.0
			# An edge that opens into another river (where a stream comes in): no waterline across that opening.
			if (k == 0 or k == 4) and not _nearest(plan, q.x + side.x * u, q.y + side.y * u, 0.6, own).is_empty():
				inset = -99.0
			row.append([Vector3(q.x, y, q.y) - centre, Vector2((u + 1.0) * half, along), half, inset, steep, fade])
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
				st.set_color(Color(v[4], 0.0, v[5]))   # how steep (white water); b: faded out (out of a spring's pool)
				st.set_uv2(Vector2(v[2], v[3]))   # the ribbon's half width, and how far in from its edge the waterline is (far out: none)
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	mi.set_meta("water", true)
	return mi


# --- River dressing (main thread) ------------------------------------------------------------------

const STONE_COLOURS := [Color(0.52, 0.5, 0.47), Color(0.6, 0.57, 0.52), Color(0.44, 0.43, 0.42), Color(0.58, 0.52, 0.44)]


## Stones and gravel on the bed and the bars, reeds and cattails along the water's edge, lily pads in the quiet water,
## driftwood up on the banks and a boulder now and then in a stream: for one stretch of a river, as one mesh.
static func _dress(gen: WorldGen, plan: Dictionary, line: Dictionary, i0: int, i1: int, rng: RandomNumberGenerator, mat: Material) -> MeshInstance3D:
	var pts: Array = line.pts
	var surf: PackedFloat32Array = line.surface
	var wid: PackedFloat32Array = line.width
	var n := pts.size()
	var big: bool = line.big
	var centre := Vector3((pts[i0] as Vector2).x, surf[i0], (pts[i0] as Vector2).y)
	var kit := MeshKit.new(i0 + int(surf[i0] * 10.0))
	var own := (plan.lines as Array).find(line)
	var count := 0
	for i in range(i0, i1):
		if surf[i] < 0.15:
			break
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		var tan := (q - p).normalized()
		var side := Vector2(-tan.y, tan.x)
		var w := wid[i]
		var at_point := func(along: float, across: float) -> Vector3:
			var xz: Vector2 = p.lerp(q, along) + side * across
			return Vector3(xz.x, ChunkGenerator.surface_height(gen, xz.x, xz.y), xz.y) - centre
		var in_other := func(v: Vector3) -> bool:   # in another river's water (at a meeting): leave it to that one
			return not _nearest(plan, v.x + centre.x, v.z + centre.z, 0.0, own).is_empty()
		# Stones on the bed, more in the streams (where you see them best), some breaking the surface.
		for k in (rng.randi_range(2, 4) if not big else rng.randi_range(1, 3)):
			var v: Vector3 = at_point.call(rng.randf(), rng.randf_range(-0.9, 0.9) * w)
			var r := rng.randf_range(0.12, 0.3) * (1.3 if big else 1.0)
			_stone(kit, v + Vector3(0, r * 0.25, 0), r, rng)
			count += 1
		if not big and rng.randf() < 0.18:   # a boulder in the stream, the water parting round it
			var v: Vector3 = at_point.call(rng.randf(), rng.randf_range(-0.4, 0.4) * w)
			var r := rng.randf_range(0.45, 0.75)
			_stone(kit, v + Vector3(0, r * 0.35, 0), r, rng)
			count += 1
		# Gravel bars on the inside of the banks.
		if rng.randf() < 0.45:
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var base_t := rng.randf()
			for k in rng.randi_range(5, 9):
				var v: Vector3 = at_point.call(clampf(base_t + rng.randf_range(-0.25, 0.25), 0.0, 1.0), sgn * (w + rng.randf_range(-0.3, 1.2)))
				_stone(kit, v + Vector3(0, 0.02, 0), rng.randf_range(0.06, 0.14), rng)
			count += 1
		# Reeds and cattails in clumps at the water's edge, half in the water.
		for k in (rng.randi_range(1, 3) if rng.randf() < 0.75 else 0):
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var v: Vector3 = at_point.call(rng.randf(), sgn * (w + rng.randf_range(-0.5, 0.5)))
			if in_other.call(v):
				continue
			_reeds(kit, v, rng)
			count += 1
		# Lily pads in the quiet water near the banks of the big rivers.
		if big and rng.randf() < 0.3:
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var xz: Vector2 = p.lerp(q, rng.randf()) + side * sgn * w * rng.randf_range(0.55, 0.85)
			var lv := Vector3(xz.x, lerpf(surf[i], surf[i + 1], 0.5) + 0.015, xz.y) - centre
			if not in_other.call(lv):
				_lilies(kit, lv, rng, rng.randi_range(3, 7), 1.2)
				count += 1
		# Driftwood washed up on the bank.
		if rng.randf() < (0.1 if big else 0.06):
			var sgn := 1.0 if rng.randf() < 0.5 else -1.0
			var v: Vector3 = at_point.call(rng.randf(), sgn * (w + rng.randf_range(0.6, 1.6)))
			_driftwood(kit, v, Vector3(tan.x, 0, tan.y).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)), rng)
			count += 1
	if count == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit(mat)
	mi.position = centre
	mi.visibility_range_end = 160.0
	mi.visibility_range_end_margin = 15.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


static func _dress_pond(gen: WorldGen, pd: Array, rng: RandomNumberGenerator, mat: Material) -> MeshInstance3D:
	var c2: Vector2 = pd[0]
	var r: float = pd[1]
	var centre := Vector3(c2.x, float(pd[2]), c2.y)
	var kit := MeshKit.new(int(c2.x))
	_lilies(kit, Vector3(rng.randf_range(-0.3, 0.3), 0.015, rng.randf_range(-0.3, 0.3)) * r, rng, rng.randi_range(8, 14), r * 0.55)
	var outlet: Variant = pd[6] if pd.size() > 6 else null
	for k in rng.randi_range(6, 10):
		var a := rng.randf() * TAU
		if outlet != null and absf(angle_difference(a, (outlet as Vector2).angle())) < 0.75:
			continue   # not across the mouth where the river runs out
		var xz := c2 + Vector2(cos(a), sin(a)) * (r + rng.randf_range(-0.4, 0.4))
		_reeds(kit, Vector3(xz.x, ChunkGenerator.lowest_ground(gen, xz.x, xz.y, 0.3, 0.3) - 0.03, xz.y) - centre, rng)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit(mat)
	mi.position = centre
	mi.visibility_range_end = 160.0
	mi.visibility_range_end_margin = 15.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


## A river's source. Out of the rock: a heap of mossy boulders built into the rise above the pool, the water
## spilling white from a cleft between them down into it, with spray and the rush of it. A spring: mossy stones
## round the pool, ferny tufts, and bubbles welling up in the middle.
static func _dress_head(gen: WorldGen, hd: Dictionary, rng: RandomNumberGenerator, mat: Material, parent: Node3D) -> void:
	var c2: Vector2 = hd.c
	var r: float = hd.r
	var up2: Vector2 = hd.up
	var surface: float = hd.surface
	var centre := Vector3(c2.x, surface, c2.y)
	var up := Vector3(up2.x, 0, up2.y)
	var side := Vector3(-up.z, 0, up.x)
	var kit := MeshKit.new(int(c2.x * 7.0))
	var pal: WorldPalette = Game.palette
	var moss: Color = pal.moss
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_SOLID
	body.collision_mask = 0
	var solid := func(at: Vector3, rad: float) -> void:
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = rad
		cs.shape = sph
		cs.position = at
		body.add_child(cs)
	if hd.rock:
		var rise := clampf(float(hd.rise), 4.0, 12.0)
		var lip := clampf(rise * 0.35, 1.2, 3.0)   # how high above the pool the water comes out
		# The outcrop: a craggy heap of chipped stone round the upslope side of the pool, big blocks sunk into the rise
		# and smaller ones tumbled at the water's edge, moss in patches on their tops. Left open in the middle, where
		# the water comes out.
		var rk := MeshKit.new(int(c2.y * 5.0))
		rk.flat_shading = true
		var big_rise := float(hd.rise) > 8.0
		for k in rng.randi_range(9, 13):
			var a := rng.randf_range(-1.4, 1.4)
			if absf(a) < 0.2:
				a = signf(a + 0.001) * rng.randf_range(0.25, 0.5)   # the cleft stays open
			var high := rng.randf() < 0.45
			var dir := (up * cos(a) + side * sin(a)).normalized()
			var dist := r + rng.randf_range(-0.4, 0.6) + (rng.randf_range(0.8, 2.2) if high else 0.0)
			var bs := rng.randf_range(0.9, 1.6) if high else rng.randf_range(0.45, 1.0)
			bs *= 1.25 if big_rise else 1.0
			var at := Vector3(c2.x, 0, c2.y) + dir * dist
			var g := gen.get_height(at.x, at.z)
			at.y = maxf(g, surface - 0.3) + bs * rng.randf_range(0.0, 0.25) + (lip * rng.randf_range(0.2, 0.6) if high else 0.0)
			var col := pal.rock.darkened(rng.randf_range(0.0, 0.2)).lerp(Color(0.52, 0.5, 0.46), 0.25)
			var mossy := rng.randf() < 0.55
			var moss_top := moss.darkened(rng.randf_range(0.0, 0.15))
			var sq := Vector3(bs * rng.randf_range(1.0, 1.5), bs * rng.randf_range(0.6, 0.95), bs * rng.randf_range(0.8, 1.2))
			# Down to the ground all round its foot: a block lifted up the crag (or on a slope) reaches down to the
			# lowest ground under it, taller rather than hanging there.
			var low := maxf(ChunkGenerator.lowest_ground(gen, at.x, at.z, sq.x * 0.8, sq.x * 0.8), surface - 0.6) - 0.15
			if at.y - sq.y * 0.7 > low:
				var top := at.y + sq.y
				sq.y = (top - low) / 1.7
				at.y = top - sq.y
			var cy := at.y - centre.y
			var cf := func(pl: Vector3) -> Color:
				var y := pl.y - cy
				return moss_top if mossy and y > sq.y * 0.6 else (col.darkened(0.3) if y < -sq.y * 0.3 else col)
			var tilt := Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.35))
			rk.add_primitive(MeshKit.sphere(1.0, 7, 4), Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(sq), at - centre), col, 0.35, 0.06, null, cf)
			solid.call(at, minf(sq.x, minf(sq.y, sq.z)) * 0.9)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rk.commit(mat)
		rmi.position = centre
		rmi.visibility_range_end = 300.0
		parent.add_child(rmi)
		# The fall: a sheet of white water from the cleft, curving out and down into the pool.
		var spout := Vector3(c2.x, surface + lip, c2.y) + up * (r + 0.35)
		var path: Array = []
		var radii: Array = []
		for k in 7:
			var t := k / 6.0
			path.append(spout - up * (0.15 + 0.9 * t) + Vector3(0, -lip * t * t - 0.05, 0) - centre)
			radii.append(lerpf(0.32, 0.5, t) * (1.4 if hd.big else 1.0))
		var foam := Color(0.86, 0.93, 0.96)
		kit.loft(path, radii, 6, foam, func(t: float, ang: float) -> Color:
			return foam.lerp(Color(0.55, 0.72, 0.8), 0.35 * absf(sin(ang * 2.0 + t * 9.0))),
			func(_t: float, _ang: float) -> Vector2: return Vector2(1.0, 0.35), false, true, 0.02)
		# Spray and the rush where it lands (only when someone is near, see update_cascades).
		var node := Node3D.new()
		node.name = "Spring"
		node.position = Vector3(c2.x, surface + 0.2, c2.y) + up * (r - 0.4)
		parent.add_child(node)
		var spray := Effects.spray(0.9 if hd.big else 0.6)
		node.add_child(spray)
		node.set_meta("spray", spray)
		Audio.rush_loop(node)
	else:
		# Mossy stones round the rim, half in the water.
		for k in rng.randi_range(7, 11):
			var a := rng.randf() * TAU
			if absf(angle_difference(a, atan2(-up2.y, -up2.x))) < 0.5:
				continue   # where the stream runs out
			var at := Vector3(c2.x + cos(a) * (r + rng.randf_range(-0.2, 0.5)), 0, c2.y + sin(a) * (r + rng.randf_range(-0.2, 0.5)))
			var sr := rng.randf_range(0.3, 0.6)
			at.y = maxf(ChunkGenerator.lowest_ground(gen, at.x, at.z, sr * 1.1, sr * 1.1), surface - 0.15)
			var col := pal.rock.lerp(Color(0.55, 0.53, 0.5), 0.3).darkened(rng.randf_range(0.0, 0.15))
			var mt := moss.darkened(rng.randf_range(0.0, 0.12))
			var hy := sr * 0.7
			var cy := at.y - centre.y
			var cf := func(pl: Vector3) -> Color:
				return mt if pl.y - cy > hy * 0.55 else col
			kit.add_primitive(MeshKit.sphere(1.0, 7, 5), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sr * 1.3, sr * 0.7, sr)), at - centre), col, 0.2, 0.06, null, cf)
		# Bubbles welling up in the middle (near the camera only, like the cascades' spray).
		var node := Node3D.new()
		node.name = "Spring"
		node.position = centre + Vector3(0, 0.02, 0)
		parent.add_child(node)
		var bub := Effects.bubbles(r * 0.35, Color(0.8, 0.9, 0.95))
		bub.amount = 10
		bub.lifetime = 0.9
		bub.scale_amount_min = 0.03
		bub.scale_amount_max = 0.06   # (pot bubbles, a spring's are bigger)
		node.add_child(bub)
		node.set_meta("spray", bub)
	if body.get_child_count() > 0:
		parent.add_child(body)
	else:
		body.free()
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit(mat)
	mi.position = centre
	mi.visibility_range_end = 260.0
	parent.add_child(mi)


## A spring's pool and its outlet as one sheet of still water: the round pool, drawn out into a funnel that narrows
## to the river's width where the river has fully taken over (it fades in over this, see _ribbon). Just under the
## river's water where they overlap, so they don't flicker.
static func _head_water(hd: Dictionary) -> MeshInstance3D:
	var c: Vector2 = hd.c
	var r: float = float(hd.r) + 0.6
	var op: Vector2 = hd.out_p
	var dir := (op - c).normalized()
	var side := Vector2(-dir.y, dir.x)
	var ow := float(hd.out_w) + 0.7
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	pts.append(op + side * ow)
	pts.append(op - side * ow)
	var hull := Geometry2D.convex_hull(pts)
	hull.remove_at(hull.size() - 1)   # (the hull repeats its first point at the end)
	var tris := Geometry2D.triangulate_polygon(hull)
	var top := float(hd.surface) - 0.04
	var low := float(hd.out_s) - 0.06
	var reach := maxf((op - c).length() - r * 0.5, 0.1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(c.x, top, c.y)
	for k in tris:
		var q: Vector2 = hull[k]
		# Level over the pool, easing down toward the outlet's end to sit under the river there.
		var along := clampf(((q - c).dot(dir) - r * 0.5) / reach, 0.0, 1.0)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(q.x, lerpf(top, minf(top, low), along), q.y) - centre)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = pond_material
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	mi.set_meta("water", true)
	return mi


static func _stone(kit: MeshKit, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var col: Color = STONE_COLOURS[rng.randi() % STONE_COLOURS.size()]
	kit.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.3, 0.62, 1.0)), at),
		col.darkened(rng.randf_range(0.0, 0.2)), r * 0.18, 0.06)


## A clump of reeds, a few of them topped with a cattail.
static func _reeds(kit: MeshKit, at: Vector3, rng: RandomNumberGenerator) -> void:
	for k in rng.randi_range(5, 9):
		var base := at + Vector3(rng.randf_range(-0.3, 0.3), -0.1, rng.randf_range(-0.3, 0.3))
		var h := rng.randf_range(0.8, 1.6)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)) * h
		var top := base + Vector3(0, h, 0) + lean
		var green := Color(0.36, 0.5, 0.22).lerp(Color(0.55, 0.55, 0.3), rng.randf() * 0.5)
		kit.loft([base, base + Vector3(0, h * 0.5, 0) + lean * 0.3, top], [0.018, 0.012, 0.004], 4, green, Callable(), Callable(), false, false)
		if rng.randf() < 0.35:
			var head := base + Vector3(0, h * 0.78, 0) + lean * 0.62
			kit.loft([head, head + Vector3(0, 0.16, 0) + lean * 0.08], [0.03, 0.028], 6, Color(0.42, 0.27, 0.16), Callable(), Callable(), true, true)


## A spread of lily pads on the water (round, with the notch), a pale flower on some.
static func _lilies(kit: MeshKit, at: Vector3, rng: RandomNumberGenerator, count: int, spread: float) -> void:
	for k in count:
		var p := at + Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var r := rng.randf_range(0.14, 0.28)
		var outline := PackedVector2Array()
		var notch := rng.randf() * TAU
		for i in 14:
			var a := notch + 0.35 + (TAU - 0.7) * i / 13.0
			outline.append(Vector2(cos(a), sin(a)) * r)
		outline.append(Vector2.ZERO)
		var green := Color(0.28, 0.48, 0.2).lerp(Color(0.42, 0.55, 0.25), rng.randf())
		kit.extrude(outline, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), p + Vector3(0, float(k % 5) * 0.002, 0)), 0.012, 0.0, green, green.darkened(0.2))
		if rng.randf() < 0.25:
			var petal := Color(0.98, 0.85, 0.9) if rng.randf() < 0.6 else Color(0.98, 0.96, 0.9)
			for i in 6:
				var a := TAU * i / 6.0
				kit.add_primitive(MeshKit.sphere(0.05, 5, 3), Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(1.0, 0.5, 0.45)), p + Vector3(cos(a) * 0.05, 0.04, sin(a) * 0.05)), petal, 0.0, 0.04)
			kit.add_primitive(MeshKit.sphere(0.025, 5, 3), Transform3D(Basis(), p + Vector3(0, 0.06, 0)), Color(1.0, 0.82, 0.3), 0.0, 0.03)


## A bleached log washed up on the bank, with a broken branch.
static func _driftwood(kit: MeshKit, at: Vector3, dir: Vector3, rng: RandomNumberGenerator) -> void:
	var len := rng.randf_range(1.4, 2.6)
	var r := rng.randf_range(0.08, 0.15)
	var a := at - dir * len * 0.5 + Vector3(0, r * 0.6, 0)
	var b := at + dir * len * 0.5 + Vector3(0, r * 0.5, 0)
	var col := Color(0.66, 0.6, 0.52).lerp(Color(0.52, 0.46, 0.38), rng.randf())
	kit.loft([a, a.lerp(b, 0.5) + Vector3(0, 0.03, 0), b], [r, r * 0.95, r * 0.7], 7, col, Callable(), Callable(), true, true, 0.015)
	var fork := a.lerp(b, rng.randf_range(0.3, 0.7))
	var out := dir.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
	kit.loft([fork, fork + (out * 0.5 + dir * 0.2 + Vector3(0, 0.18, 0))], [r * 0.5, r * 0.25], 5, col.lightened(0.05), Callable(), Callable(), true, true)
