class_name MeshKit
extends RefCounted
## Helper for building stylized meshes in code, with vertex colors.
## Normals are smooth by default (painterly look). A `puff_center` makes a group of shapes
## light as one soft volume, which is what makes tree canopies look painted and fluffy.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var force_up_normals := false   ## grass: light it like the ground under it
var flat_shading := false       ## chipped stone, gems: crisp facets instead of smooth shading
## Foliage volumes (shapes with a puff_center) get painted depth baked into their colors:
## sunlit tops, cool shadowed undersides. Free at runtime.
var canopy_shading := true

## Global polygon multiplier (the "Model detail" setting). Set while building assets.
static var detail := 1.0
## Whether trees get their small leaf cards and needle cards (the "Leaf details" setting).
static var leaves := true
var _noise: FastNoiseLite
## Where each separate part (primitive, loft, extrusion, lathe) starts in `verts`. At commit each part is moved by
## its own fraction of a millimetre, so two parts' faces that happen to lie in exactly the same plane (a board's top
## flush with a rail's, a tile's edge on a beam's end) don't fight over the same pixels and flicker.
var _parts := PackedInt32Array()
## How far (metres, at most) a part may be nudged. 0 turns it off.
static var nudge := 0.0009


func _init(noise_seed := 0) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.frequency = 0.9


## A single triangle (used for grass blades). Colors are sRGB and stored linear.
func add_tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb := Color(-1, 0, 0), cc := Color(-1, 0, 0)) -> void:
	var n := (c - a).cross(b - a)   # Godot front faces are clockwise
	if n.length_squared() < 1e-10:
		return
	n = Vector3.UP if force_up_normals else n.normalized()
	if cb.r < 0.0: cb = ca
	if cc.r < 0.0: cc = ca
	verts.append_array([a, b, c])
	normals.append_array([n, n, n])
	colors.append_array([ca.srgb_to_linear(), cb.srgb_to_linear(), cc.srgb_to_linear()])


## Adds a primitive (cylinder, sphere...) with a transform and color.
## lumpy:        pushes vertices in/out with noise (stays watertight).
## shade_jitter: soft blotchy color variation across the surface.
## puff_center:  if set, normals point away from this point (soft, volumetric lighting).
## color_fn:     optional Callable(local_pos: Vector3) -> Color for patterns (stripes, bellies).
func add_primitive(prim: PrimitiveMesh, xf: Transform3D, color: Color, lumpy := 0.0, shade_jitter := 0.05,
		puff_center: Variant = null, color_fn := Callable()) -> void:
	_parts.append(verts.size())
	var arrays := prim.get_mesh_arrays()
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := xf.basis.inverse().transposed()
	var moved := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	moved.resize(src.size())
	nrm.resize(src.size())
	col.resize(src.size())
	for i in src.size():
		var v := src[i]
		if lumpy > 0.0 and v.length_squared() > 1e-6:
			v += v.normalized() * _noise.get_noise_3dv(v * 3.0 + xf.origin) * lumpy
		var p := xf * v
		moved[i] = p
		if puff_center != null:
			nrm[i] = (p - (puff_center as Vector3)).normalized()
		else:
			nrm[i] = (normal_basis * src_n[i]).normalized()
		var c: Color = color_fn.call(p) if color_fn.is_valid() else color
		if puff_center != null and canopy_shading:
			var up := smoothstep(-0.75, 0.65, nrm[i].y)
			c = c.lerp(Color(c.r * 0.55, c.g * 0.62, c.b * 0.78), (1.0 - up) * 0.55)   # cool shade below
			c = c.lerp(Color(minf(c.r * 1.12 + 0.03, 1.0), minf(c.g * 1.1 + 0.03, 1.0), c.b * 0.95), up * up * 0.4)   # warm sunlit top
		if shade_jitter > 0.0:
			var j := _noise.get_noise_3dv(p * 1.7) * shade_jitter
			c = Color(c.r + j, c.g + j, c.b + j, c.a)
		col[i] = c.srgb_to_linear()
	# A mirrored transform turns every triangle inside out; swapping two corners puts it back.
	var mirrored := xf.basis.determinant() < 0.0
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		if mirrored:
			var tmp := b
			b = c
			c = tmp
		var fn := (moved[c] - moved[a]).cross(moved[b] - moved[a])
		if fn.length_squared() < 1e-20:   # no area at all (sphere poles): nothing to draw
			continue
		if flat_shading:
			fn = fn.normalized()
			verts.append_array([moved[a], moved[b], moved[c]])
			normals.append_array([fn, fn, fn])
		else:
			verts.append_array([moved[a], moved[b], moved[c]])
			normals.append_array([nrm[a], nrm[b], nrm[c]])
		colors.append_array([col[a], col[b], col[c]])


# --- Sculpting helpers: shapes built vertex by vertex ---------------------------------

## One flat triangle facing `normal` (it's turned round if its corners wind the other way). sRGB colour.
func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	_emit(a, b, c, normal, normal, normal, color, color, color, normal)


## Emit one triangle, flipping it if needed so it faces `outward`. Colors are sRGB.
func _emit(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-20:   # only true zero-area triangles; millimetre tips must survive
		return
	if fn.dot(outward) < 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
		var tc := cb
		cb = cc
		cc = tc
	if flat_shading:
		var f := (c - a).cross(b - a).normalized()
		na = f
		nb = f
		nc = f
	verts.append_array([a, b, c])
	normals.append_array([na, nb, nc])
	colors.append_array([ca.srgb_to_linear(), cb.srgb_to_linear(), cc.srgb_to_linear()])


## A solid of revolution: `profile` is a run of Vector2(radius, height) points, spun round the vertical axis of
## `xf`. Walk it so the outside is on your right: for a hollow vessel, from the middle of its base out and up the
## outside, over the rim, down the inside and in to the middle of its floor. Then the outside faces out and the
## inside faces into the hollow, and it's closed all the way round (no seams, no pretend holes).
## color_fn: optional Callable(t: float (0..1 along the profile), angle: float) -> Color.
func lathe(profile: Array, segments: int, color: Color, color_fn := Callable(), xf := Transform3D()) -> void:
	_parts.append(verts.size())
	var n := profile.size()
	if n < 2:
		return
	var seg := maxi(6, roundi(segments * detail))
	# Each profile point's normal (in the r-y plane): the run's direction turned a quarter to the right, averaged
	# over the segments either side.
	var nrm: Array = []
	for i in n:
		var t := Vector2.ZERO
		if i > 0:
			t += ((profile[i] as Vector2) - (profile[i - 1] as Vector2)).normalized()
		if i < n - 1:
			t += ((profile[i + 1] as Vector2) - (profile[i] as Vector2)).normalized()
		nrm.append(Vector2(t.y, -t.x).normalized())
	var ring := func(i: int, a: float) -> Array:
		var p: Vector2 = profile[i]
		var q: Vector2 = nrm[i]
		var pos := xf * Vector3(cos(a) * p.x, p.y, sin(a) * p.x)
		var nn := (xf.basis * Vector3(cos(a) * q.x, q.y, sin(a) * q.x)).normalized()
		var c: Color = color_fn.call(float(i) / (n - 1), a) if color_fn.is_valid() else color
		return [pos, nn, c]
	for i in n - 1:
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var p00: Array = ring.call(i, a0)
			var p01: Array = ring.call(i, a1)
			var p10: Array = ring.call(i + 1, a0)
			var p11: Array = ring.call(i + 1, a1)
			var out: Vector3 = (p00[1] as Vector3) + (p01[1] as Vector3) + (p10[1] as Vector3) + (p11[1] as Vector3)
			_emit(p00[0], p10[0], p11[0], p00[1], p10[1], p11[1], p00[2], p10[2], p11[2], out)
			_emit(p00[0], p11[0], p01[0], p00[1], p11[1], p01[1], p00[2], p11[2], p01[2], out)


## A tube along a path: handles, branches, horns, stems, logs, curved pick heads.
## radii:    one radius per path point (tapers, bulges).
## shape_fn: optional Callable(t: float, angle: float) -> Vector2 cross-section scale (ovals, flats).
## color_fn: optional Callable(t: float, angle: float) -> Color (wraps, bands, bark ridges).
## bumps:    noise displacement of the surface (gnarled wood, bark).
## closed:   the path is a loop (a ring or coil): the tube joins itself, with no caps.
func loft(path: Array, radii: Array, sides := 8, color := Color.WHITE, color_fn := Callable(),
		shape_fn := Callable(), cap_start := true, cap_end := true, bumps := 0.0, closed := false) -> void:
	_parts.append(verts.size())
	var n := path.size()
	if n < 2:
		return
	if closed and (path[n - 1] as Vector3).distance_to(path[0]) < 1e-6:
		n -= 1   # the path already comes back to its start: the tube joins itself there
	var rings: Array = []
	var ring_n: Array = []
	var ring_c: Array = []
	var tangent := ((path[1] as Vector3) - (path[0] as Vector3)).normalized()
	var normal := tangent.cross(Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	for i in n:
		var p: Vector3 = path[i]
		var prev: Vector3 = path[(i - 1 + n) % n] if closed else path[maxi(i - 1, 0)]
		var next: Vector3 = path[(i + 1) % n] if closed else path[mini(i + 1, n - 1)]
		var t_new := (next - prev).normalized()
		# Parallel transport keeps the ring from twisting along curves.
		normal = (normal - t_new * normal.dot(t_new)).normalized()
		tangent = t_new
		var binormal := tangent.cross(normal)
		var t := float(i) / (n - 1)
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		var rc := PackedColorArray()
		for j in sides:
			var ang := TAU * j / sides
			var sc := Vector2.ONE
			if shape_fn.is_valid():
				sc = shape_fn.call(t, ang)
			var dir := normal * cos(ang) * sc.x + binormal * sin(ang) * sc.y
			var r: float = radii[i]
			var v := p + dir * r
			if bumps > 0.0:
				v += dir.normalized() * _noise.get_noise_3dv(v * 9.0) * bumps
			ring.append(v)
			rn.append((normal * cos(ang) / maxf(sc.x, 0.01) + binormal * sin(ang) / maxf(sc.y, 0.01)).normalized())
			rc.append(color_fn.call(t, ang) if color_fn.is_valid() else color)
		rings.append(ring)
		ring_n.append(rn)
		ring_c.append(rc)
	var segments := n if closed else n - 1
	for i in segments:
		var i2 := (i + 1) % n
		for j in sides:
			var j2 := (j + 1) % sides
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][j2]
			var c: Vector3 = rings[i2][j2]
			var d: Vector3 = rings[i2][j]
			var out := ((a + b + c + d) * 0.25 - ((path[i] as Vector3) + (path[i2] as Vector3)) * 0.5)
			_emit(a, b, c, ring_n[i][j], ring_n[i][j2], ring_n[i2][j2], ring_c[i][j], ring_c[i][j2], ring_c[i2][j2], out)
			_emit(a, c, d, ring_n[i][j], ring_n[i2][j2], ring_n[i2][j], ring_c[i][j], ring_c[i2][j2], ring_c[i2][j], out)
	if closed:
		return
	for cap in [[cap_start, 0, -1.0], [cap_end, n - 1, 1.0]]:
		if not cap[0]:
			continue
		var ri: int = cap[1]
		var center: Vector3 = path[ri]
		var axis := ((path[mini(ri + 1, n - 1)] as Vector3) - (path[maxi(ri - 1, 0)] as Vector3)).normalized() * float(cap[2])
		for j in sides:
			var j2 := (j + 1) % sides
			_emit(center, rings[ri][j], rings[ri][j2], axis, axis, axis, ring_c[ri][j], ring_c[ri][j], ring_c[ri][j2], axis)


## A flat shape cut from a 2D outline (in the XY plane of `xf`) and given thickness, with a
## bevel that thins it toward the edge: blades, axe heads, leaves, fins, petals.
## edge_color colors the bevel (e.g. a bright sharpened edge on metal).
func extrude(outline: PackedVector2Array, xf: Transform3D, thickness: float, bevel: float, color: Color,
		edge_color: Color, edge_thin := 0.15) -> void:
	_parts.append(verts.size())
	var count := outline.size()
	if count < 3:
		return
	var cw := Geometry2D.is_polygon_clockwise(outline)
	# Outward normal of each outline edge, from the outline's own orientation (right for counter-clockwise).
	var seg_out: Array[Vector2] = []
	for i in count:
		var e := outline[(i + 1) % count] - outline[i]
		var en := Vector2(e.y, -e.x).normalized()
		seg_out.append(-en if cw else en)
	# The bevelled face: each vertex moved inward along the bisector of its two edges (a mitred
	# inset), so the face keeps one point per outline vertex and concave notches stay clean. Where
	# the inset folds over itself (a narrow waist), the bevel is halved until the face covers its area.
	var inner := PackedVector2Array()
	var tris := PackedInt32Array()
	var bev := bevel
	for attempt in 6:
		inner = PackedVector2Array()
		for i in count:
			var n_prev := seg_out[(i - 1 + count) % count]
			var n_next := seg_out[i]
			var bis := (n_prev + n_next)
			var inward := -bis.normalized() if bis.length_squared() > 1e-10 else -n_next
			var cos_half := maxf(absf(inward.dot(-n_next)), 0.35)
			inner.append(outline[i] + inward * minf(bev / cos_half, bev * 3.0))
		tris = Geometry2D.triangulate_polygon(inner)
		if _covers(inner, tris):
			break
		bev *= 0.5
	if not _covers(inner, tris):
		inner = outline
		tris = Geometry2D.triangulate_polygon(outline)
		bev = 0.0
	var half := thickness * 0.5
	var edge := half * edge_thin
	var zx := xf.basis.z.normalized()
	var to3 := func(p: Vector2, z: float) -> Vector3: return xf * Vector3(p.x, p.y, z)
	for side in [1.0, -1.0]:
		var fz: float = half * side
		for k in range(0, tris.size(), 3):
			var a: Vector3 = to3.call(inner[tris[k]], fz)
			var b: Vector3 = to3.call(inner[tris[k + 1]], fz)
			var c: Vector3 = to3.call(inner[tris[k + 2]], fz)
			_emit(a, b, c, zx * side, zx * side, zx * side, color, color, color, zx * side)
		for i in count:
			var i2 := (i + 1) % count
			var ia: Vector3 = to3.call(inner[i], fz)
			var ib: Vector3 = to3.call(inner[i2], fz)
			var oa: Vector3 = to3.call(outline[i], edge * side)
			var ob: Vector3 = to3.call(outline[i2], edge * side)
			var out: Vector3 = xf.basis * Vector3(seg_out[i].x, seg_out[i].y, 0.0) + zx * float(side) * 0.6
			var out_n := out.normalized()
			_emit(ia, ib, ob, out_n, out_n, out_n, color, color, edge_color, out_n)
			_emit(ia, ob, oa, out_n, out_n, out_n, color, edge_color, edge_color, out_n)
	for i in count:   # the thin edge band
		var i2 := (i + 1) % count
		var a: Vector3 = to3.call(outline[i], edge)
		var b: Vector3 = to3.call(outline[i2], edge)
		var c: Vector3 = to3.call(outline[i2], -edge)
		var d: Vector3 = to3.call(outline[i], -edge)
		var out := (xf.basis * Vector3(seg_out[i].x, seg_out[i].y, 0.0)).normalized()
		_emit(a, b, c, out, out, out, edge_color, edge_color, edge_color, out)
		_emit(a, c, d, out, out, out, edge_color, edge_color, edge_color, out)


## True when the triangles tile the polygon: their areas add up to the polygon's own area.
static func _covers(poly: PackedVector2Array, tris: PackedInt32Array) -> bool:
	if tris.is_empty() or poly.size() < 3:
		return false
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var tri_area := 0.0
	for t in range(0, tris.size(), 3):
		var p := poly[tris[t]]
		var q := poly[tris[t + 1]]
		var r := poly[tris[t + 2]]
		tri_area += absf((q - p).cross(r - p)) * 0.5
	return absf(tri_area - absf(area) * 0.5) <= absf(area) * 0.5 * 0.005


## A solid cut from a 2D outline (x, y in the plane of `xf`) whose thickness varies across it:
## thick_fn(p: Vector2) -> full thickness there. Blades can be thick at the spine and come to a
## real edge; axe heads swell around the handle. The faces are triangulated over the outline plus a
## lattice of interior points (spacing max_seg), so the triangles are evenly shaped and the surface
## shades smoothly. col_fn(p: Vector2, thickness: float) -> Color. (`_levels` is unused, kept for callers.)
func sculpt(outline: PackedVector2Array, xf: Transform3D, thick_fn: Callable, col_fn: Callable, _levels := 2, max_seg := 0.008) -> void:
	var ring := _resample(outline, max_seg)
	var n := ring.size()
	if n < 3:
		return
	# Points: the outline, plus a lattice of points inside it (kept off the edge). Triangles made from
	# the outline alone come out long and skinny; with interior points they are evenly shaped.
	var h := max_seg
	var pts := PackedVector2Array(ring)
	var closed := PackedVector2Array(ring)
	closed.append(ring[0])
	var lo := ring[0]
	var hi := ring[0]
	for p in ring:
		lo = lo.min(p)
		hi = hi.max(p)
	var gap := h * 1.0   # interior points stay a full step in, so the outline's own points form the rim
	var y := lo.y + h * 0.5
	while y < hi.y:
		var x := lo.x + h * 0.5
		while x < hi.x:
			var g := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(g, ring) and dist_to_polyline(g, closed) > gap:
				pts.append(g)
			x += h
		y += h
	var del := Geometry2D.triangulate_delaunay(pts)
	# Keep the triangles whose middle lies inside the outline, each one counter-clockwise.
	var faces: Array = []
	var has := {}
	for t in range(0, del.size(), 3):
		var i: int = del[t]
		var j: int = del[t + 1]
		var k: int = del[t + 2]
		var centre := (pts[i] + pts[j] + pts[k]) / 3.0
		if not Geometry2D.is_point_in_polygon(centre, ring):
			continue
		var area := (pts[j] - pts[i]).cross(pts[k] - pts[i])
		if absf(area) < 1e-12:
			continue
		if area < 0.0:
			var tmp := j
			j = k
			k = tmp
		faces.append([i, j, k])
		has[Vector2i(i, j)] = true
		has[Vector2i(j, k)] = true
		has[Vector2i(k, i)] = true
	if faces.is_empty():
		return
	# The boundary of the faces: directed edges whose reverse is not a face edge. Walking them gives
	# the loops the rim is built on, so the rim and the faces always share their edge points.
	var out_b := {}
	var b_edges: Array = []
	for f: Array in faces:
		for e in 3:
			var u: int = f[e]
			var v: int = f[(e + 1) % 3]
			if not has.has(Vector2i(v, u)):
				if not out_b.has(u):
					out_b[u] = []
				out_b[u].append(v)
				b_edges.append(Vector2i(u, v))
	# Walk the boundary into closed loops. Every boundary edge is used exactly once, so a point where
	# two boundary runs touch is simply passed through in turn.
	var used := {}
	var loops: Array = []
	for e0: Vector2i in b_edges:
		if used.has(e0):
			continue
		var loop: Array = []
		var e := e0
		var guard := 0
		while guard < 100000:
			guard += 1
			used[e] = true
			loop.append(e.x)
			var nxt := Vector2i(-1, -1)
			for cand: int in out_b.get(e.y, []):
				if not used.has(Vector2i(e.y, cand)):
					nxt = Vector2i(e.y, cand)
					break
			if nxt.x == -1:
				break
			e = nxt
		if loop.size() >= 3:
			loops.append(loop)
	# Thickness and colour at every point, from the same function for faces and rim.
	var th := PackedFloat32Array()
	var cols: Array[Color] = []
	for p in pts:
		var t: float = maxf(thick_fn.call(p), 0.0004)
		th.append(t)
		cols.append(col_fn.call(p, t))
	var zdir := xf.basis.z.normalized()
	for side in [1.0, -1.0]:
		var pos := PackedVector3Array()
		var nrm: Array[Vector3] = []
		for i in pts.size():
			pos.append(xf * Vector3(pts[i].x, pts[i].y, th[i] * 0.5 * side))
			nrm.append(Vector3.ZERO)
		var out_dir: Vector3 = zdir * side
		for f: Array in faces:
			var fn := (pos[f[2]] - pos[f[0]]).cross(pos[f[1]] - pos[f[0]])
			if fn.dot(out_dir) < 0.0:
				fn = -fn
			for v: int in f:
				nrm[v] += fn
		for f: Array in faces:
			var a: int = f[0]
			var b: int = f[1]
			var c: int = f[2]
			_emit(pos[a], pos[b], pos[c], nrm[a].normalized(), nrm[b].normalized(), nrm[c].normalized(), cols[a], cols[b], cols[c], out_dir)
	# The rim: a wall along each boundary loop. The loops run counter-clockwise, so the outward
	# direction of an edge is to its right.
	for loop: Array in loops:
		var m := loop.size()
		var edge_out: Array[Vector2] = []
		for k in m:
			var e: Vector2 = pts[loop[(k + 1) % m]] - pts[loop[k]]
			edge_out.append(Vector2(e.y, -e.x).normalized())
		# Rim normals: a point where the outline turns gently shares a smoothed normal with its
		# neighbours; a sharp corner keeps each wall's own normal, so no wall faces inward.
		var smooth: Array[bool] = []
		var vnorm: Array[Vector3] = []
		for k in m:
			var before: Vector2 = edge_out[(k - 1 + m) % m]
			var after: Vector2 = edge_out[k]
			var ok := before.dot(after) > 0.2
			smooth.append(ok)
			var v2 := (before + after).normalized() if ok else after
			vnorm.append((xf.basis * Vector3(v2.x, v2.y, 0.0)).normalized())
		for k in m:
			var u: int = loop[k]
			var v: int = loop[(k + 1) % m]
			var pu := pts[u]
			var pv := pts[v]
			var out := xf.basis * Vector3(edge_out[k].x, edge_out[k].y, 0.0)
			var a := xf * Vector3(pu.x, pu.y, th[u] * 0.5)
			var b := xf * Vector3(pv.x, pv.y, th[v] * 0.5)
			var c := xf * Vector3(pv.x, pv.y, -th[v] * 0.5)
			var d := xf * Vector3(pu.x, pu.y, -th[u] * 0.5)
			var own := (xf.basis * Vector3(edge_out[k].x, edge_out[k].y, 0.0)).normalized()
			var na: Vector3 = vnorm[k] if smooth[k] else own
			var nb: Vector3 = vnorm[(k + 1) % m] if smooth[(k + 1) % m] else own
			_emit(a, b, c, na, nb, nb, cols[u], cols[v], cols[v], out)
			_emit(a, c, d, na, nb, na, cols[u], cols[v], cols[u], out)


static func _resample(o: PackedVector2Array, max_seg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in o.size():
		var a := o[i]
		var b := o[(i + 1) % o.size()]
		var steps := maxi(1, ceili(a.distance_to(b) / max_seg))
		for s in steps:
			out.append(a.lerp(b, float(s) / steps))
	return out


## Distance from p to a polyline (used for "how far from the cutting edge").
static func dist_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := 1e9
	for i in line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best


func commit(material: Material) -> ArrayMesh:
	if nudge > 0.0 and _parts.size() > 1:
		for pi in _parts.size():
			var from := _parts[pi]
			var to := _parts[pi + 1] if pi + 1 < _parts.size() else verts.size()
			if to <= from:
				continue
			# Steps on each axis that differ for any two parts built within a dozen of each other (neighbouring parts
			# are the ones that touch), so their faces never land in one plane.
			var off := Vector3(float(pi % 13) - 6.0, float((pi * 5) % 17) - 8.0, float((pi * 7) % 19) - 9.0) * (nudge / 9.0)
			for vi in range(from, to):
				verts[vi] += off
		_parts.clear()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func is_empty() -> bool:
	return verts.is_empty()


static func cylinder(top: float, bottom: float, height: float, segments: int, caps := true) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = maxi(4, int(round(segments * detail)))
	m.rings = 1
	m.cap_top = caps and top > 0.0
	m.cap_bottom = caps
	return m


static func sphere(radius: float, segments := 10, rings := 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = maxi(4, int(round(segments * detail)))
	m.rings = maxi(2, int(round(rings * detail)))
	return m
