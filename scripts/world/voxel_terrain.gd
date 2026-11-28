class_name VoxelTerrain
extends RefCounted
## Ground for chunks that have caves in them. The heightfield is still the ground; the cave voids are
## cut out of it, so a cave is a real opening in a slope with rock above it. A density field (metres
## above the surface of solid rock: positive inside rock, negative in air) is sampled on a grid, and
## surface nets turn it into a mesh. The same triangles are the collider.
##
## Seams: every chunk owns the faces that start on its own grid samples, so neighbouring chunks
## build exactly the same surface along their border with no gaps and no duplicates. Runs on
## worker threads; reads only the world's base data and the cave plan.

const DEPTH_PAD := 2.0      ## metres of solid rock sampled below the lowest ground
const PAD := 2              ## spare samples on each side of the chunk (see build)
const ROCK_BAND := 1.2      ## vertices this far below the ground are cave walls (rock colour)
const SKIN_UP := 1.4        ## rock kept over a cave, at least (the caves are planned with a little more: Caves.CLEARANCE)
const SKIN := 2.2           ## and at least about this much between a cave and the open air beside it (see _seal)
const MOUTH_FREE := 6.0     ## a cave opens to the air only this far round its mouth (past its own radius)...
const MOUTH_RAMP := 8.0     ## ...the rock closing in over the next few metres


## Returns {verts, normals, colors, indices, faces}. Vertices are local to the chunk origin.
## `segs` are the cave pieces that reach this chunk (see Caves.segments_near).
static func build(gen: WorldGen, origin: Vector3, size: float, step: float, segs: Array) -> Dictionary:
	var plan: Dictionary = gen.caves
	var res := roundi(size / step)
	# Samples per side: PAD spare samples on each side, so every cell that owned faces touch has its
	# full neighbourhood (normals agree across chunk borders).
	var nx := res + 2 * PAD + 1
	var nz := res + 2 * PAD + 1
	var ox := origin.x
	var oz := origin.z

	# Ground heights on the sample grid, and the vertical range the caves need.
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var hmin := 1e9
	var hmax := -1e9
	for k in nz:
		for i in nx:
			var h := gen.get_height(ox + (i - PAD) * step, oz + (k - PAD) * step)
			hs[k * nx + i] = h
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
	var low := hmin - DEPTH_PAD
	for s: Array in segs:
		low = minf(low, minf(s[0].y, s[1].y) - maxf(float(s[2]), float(s[3])) - 1.0)
	# The vertical lattice is absolute (multiples of step), so neighbouring chunks agree on it.
	var ylo := floorf(low / step) * step
	var yhi := ceilf((hmax + 2.0) / step) * step
	var ny := roundi((yhi - ylo) / step) + 1

	# Density: ground minus height, then the caves subtracted (min with each tunnel's wall distance).
	var d := PackedFloat32Array()
	d.resize(nx * ny * nz)
	for k in nz:
		for j in ny:
			var y := ylo + j * step
			var row := (k * ny + j) * nx
			for i in nx:
				d[row + i] = hs[k * nx + i] - y
	var seal := _seal(gen, plan, origin, step, hs, nx, nz)
	for s: Array in segs:
		_carve(d, s, origin, ylo, step, nx, ny, nz, seal)

	# Surface nets: one vertex per cell that the surface passes through.
	var ncx := nx - 1
	var ncy := ny - 1
	var ncz := nz - 1
	var cell_vert := PackedInt32Array()
	cell_vert.resize(ncx * ncy * ncz)
	cell_vert.fill(-1)
	var col_weights := {}   ## biome mix per grid column (the colours' dear part), worked out the first time it's needed
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var corner := PackedVector3Array()
	corner.resize(8)
	var corner_v := PackedFloat32Array()
	corner_v.resize(8)
	var corner_n := PackedVector3Array()
	corner_n.resize(8)
	# Per sample column, the lowest and highest sample that is air. A cell can only cross the surface
	# between those rows (one below to the top of the range), so the rest of each column is skipped.
	var snorm := PackedVector3Array()
	snorm.resize(nx * ny * nz)
	var sdone := PackedByteArray()
	sdone.resize(nx * ny * nz)
	var col_lo := PackedInt32Array()
	col_lo.resize(nx * nz)
	var col_hi := PackedInt32Array()
	col_hi.resize(nx * nz)
	for k in nz:
		for i in nx:
			var lo := ny
			var hi := -1
			for j in ny:
				if d[(k * ny + j) * nx + i] <= 0.0:
					if j < lo:
						lo = j
					hi = j
			col_lo[k * nx + i] = lo
			col_hi[k * nx + i] = hi
	for ck in ncz:
		for ci in ncx:
			# The rows where any of this cell's four columns has air.
			var span := _span(col_lo, col_hi, ck * nx + ci, ncy)
			span = _union(span, _span(col_lo, col_hi, ck * nx + ci + 1, ncy))
			span = _union(span, _span(col_lo, col_hi, (ck + 1) * nx + ci, ncy))
			span = _union(span, _span(col_lo, col_hi, (ck + 1) * nx + ci + 1, ncy))
			var j0 := maxi(span.x, 0)
			var j1 := mini(span.y, ncy - 1)
			for cj in range(j0, j1 + 1):
				var base := (ck * ny + cj) * nx + ci
				var base2 := base + nx * ny
				corner_v[0] = d[base]
				corner_v[1] = d[base + 1]
				corner_v[2] = d[base + nx]
				corner_v[3] = d[base + nx + 1]
				corner_v[4] = d[base2]
				corner_v[5] = d[base2 + 1]
				corner_v[6] = d[base2 + nx]
				corner_v[7] = d[base2 + nx + 1]
				var any_in := false
				var any_out := false
				for c in 8:
					if corner_v[c] > 0.0:
						any_in = true
					else:
						any_out = true
				if not (any_in and any_out):
					continue
				# Corner positions (world) for this cell.
				var wx := ox + (ci - PAD) * step
				var wy := ylo + cj * step
				var wz := oz + (ck - PAD) * step
				for c in 8:
					corner[c] = Vector3(wx + (c & 1) * step, wy + ((c >> 1) & 1) * step, wz + ((c >> 2) & 1) * step)
				# Corner normals (pointing out of the rock), for the surface planes at each crossing.
				# Each sample's gradient is worked out once: a sample is a corner of up to eight cells.
				for c in 8:
					var si := ci + (c & 1)
					var sj := cj + ((c >> 1) & 1)
					var sk := ck + ((c >> 2) & 1)
					var sidx := (sk * ny + sj) * nx + si
					if sdone[sidx] == 0:
						snorm[sidx] = _corner_normal(d, nx, ny, nz, si, sj, sk)
						sdone[sidx] = 1
					corner_n[c] = snorm[sidx]
				# The vertex is the least-squares point of the crossing planes, kept inside its cell. Plain
				# averaging of the crossings put vertices in mid-air on cliffs, stretching sheets over the ground.
				var mass := Vector3.ZERO
				var count := 0
				var a00 := 0.0
				var a01 := 0.0
				var a02 := 0.0
				var a11 := 0.0
				var a12 := 0.0
				var a22 := 0.0
				var bsum := Vector3.ZERO
				var nsum := Vector3.ZERO
				for e in _EDGES:
					var a: int = e[0]
					var b: int = e[1]
					if (corner_v[a] > 0.0) == (corner_v[b] > 0.0):
						continue
					var t := corner_v[a] / (corner_v[a] - corner_v[b])
					var p: Vector3 = corner[a].lerp(corner[b], t)
					var n: Vector3 = corner_n[a].lerp(corner_n[b], t)
					mass += p
					count += 1
					a00 += n.x * n.x
					a01 += n.x * n.y
					a02 += n.x * n.z
					a11 += n.y * n.y
					a12 += n.y * n.z
					a22 += n.z * n.z
					bsum += n * n.dot(p)
					nsum += corner_n[a]
				mass /= float(count)
				const LAM := 0.05   # a light pull towards the crossings' average, so flat cells stay stable
				a00 += LAM
				a11 += LAM
				a22 += LAM
				bsum += LAM * mass
				var det := a00 * (a11 * a22 - a12 * a12) - a01 * (a01 * a22 - a12 * a02) + a02 * (a01 * a12 - a11 * a02)
				var vert := mass
				if absf(det) > 0.000000001:
					vert = Vector3(
						(bsum.x * (a11 * a22 - a12 * a12) - a01 * (bsum.y * a22 - a12 * bsum.z) + a02 * (bsum.y * a12 - a11 * bsum.z)) / det,
						(a00 * (bsum.y * a22 - a12 * bsum.z) - bsum.x * (a01 * a22 - a12 * a02) + a02 * (a01 * bsum.z - bsum.y * a02)) / det,
						(a00 * (a11 * bsum.z - bsum.y * a12) - a01 * (a01 * bsum.z - bsum.y * a02) + bsum.x * (a01 * a12 - a11 * a02)) / det)
				vert = vert.clamp(corner[0], corner[7])
				# Ground surface (not cave walls): sit exactly on the ground height at this spot, so steep
				# cliffs can't leave the surface hanging above the ground. Shared vertices agree across chunks.
				# The ground height here, from the heights already sampled on the grid (between its four corners: the
				# same sums in every chunk that shares the spot, so the shared vertices still agree).
				var fx := clampf((vert.x - ox) / step + PAD, 0.0, nx - 1.001)
				var fz := clampf((vert.z - oz) / step + PAD, 0.0, nz - 1.001)
				var hi0 := int(fx)
				var hk0 := int(fz)
				var tx := fx - hi0
				var tz := fz - hk0
				var gh := lerpf(lerpf(hs[hk0 * nx + hi0], hs[hk0 * nx + hi0 + 1], tx), lerpf(hs[(hk0 + 1) * nx + hi0], hs[(hk0 + 1) * nx + hi0 + 1], tx), tz)
				var sd := Caves.sky_and_distance(plan, vert)   # how much sky it sees (the shader's ambient occlusion), and the void's distance
				# Above the seal no cave is cut (see _seal), so a vertex there is on the ground too, even close over a cave.
				var sl := lerpf(lerpf(seal[hk0 * nx + hi0], seal[hk0 * nx + hi0 + 1], tx), lerpf(seal[(hk0 + 1) * nx + hi0], seal[(hk0 + 1) * nx + hi0 + 1], tx), tz)
				if absf(vert.y - gh) < 6.0 and (sd.y > 2.5 or vert.y > sl + 0.3):
					vert.y = gh
				var nrm := nsum.normalized() if nsum.length_squared() > 0.000001 else Vector3.UP
				var col: Color
				# Rock below the ground's skin; grass, sand or snow on it. Near the surface the two blend, and a face that
				# turns down or sideways (the lip and ceiling of a cave mouth) is rock even close under the ground, rather
				# than a smear of the meadow's colour on the roof.
				var depth := gh - vert.y
				var rock_w := maxf(smoothstep(0.15, ROCK_BAND, depth), smoothstep(0.55, 0.05, nrm.y) * smoothstep(0.0, 0.35, depth))
				rock_w = maxf(rock_w, smoothstep(0.0, -0.3, nrm.y))   # anything facing down is a cave's roof or lip
				if rock_w >= 0.999:
					col = Caves.rock_color(plan, vert, nrm.y)
				else:
					var ckey := ck * ncx + ci
					if not col_weights.has(ckey):
						var cx := ox + (ci - PAD + 0.5) * step
						var cz := oz + (ck - PAD + 0.5) * step
						col_weights[ckey] = gen.biome_weights_at(cx, cz, gh)
					col = gen.get_terrain_color(vert.y, nrm.y, vert.x, vert.z, col_weights[ckey])
					if rock_w > 0.001:
						col = col.lerp(Caves.rock_color(plan, vert, nrm.y), rock_w)
				col = col.srgb_to_linear()
				col.a = sd.x
				# The rock left over a cave where it came close to the air (see _seal) is inside the planned void, which
				# reads as dark, but it faces outside: lit like the ground, if a step out from it is in the open air.
				if sd.y < 0.5 and sd.x < 0.99:
					for reach: float in [1.0, 2.0, 3.0]:   # (a cave's own walls are further than this from the air)
						var out_p := vert + nrm * reach
						if out_p.y > gen.get_height(out_p.x, out_p.z) + 0.2:
							col.a = 1.0
							break
				cell_vert[(ck * ncy + cj) * ncx + ci] = verts.size()
				verts.append(vert - origin)
				normals.append(nrm)
				colors.append(col)

	# Faces: every grid edge that crosses the surface makes a quad from the four cells around it. Faces are made a
	# cell past each edge of the chunk, and then clipped to the chunk's square (see _clip_to_chunk), so the surface
	# reaches the chunk border exactly where the neighbour's does.
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for k in range(PAD - 1, PAD + res + 1):
		for i in range(PAD - 1, PAD + res + 1):
			for j in ny - 1:
				var s0 := d[(k * ny + j) * nx + i] > 0.0
				# x edge: (i,j,k) -> (i+1,j,k); cells around it differ in y and z.
				if j >= 1 and s0 != (d[(k * ny + j) * nx + i + 1] > 0.0):
					_quad(indices, faces, verts, normals, cell_vert, [
						(k - 1) * ncy * ncx + (j - 1) * ncx + i, (k - 1) * ncy * ncx + j * ncx + i,
						k * ncy * ncx + j * ncx + i, k * ncy * ncx + (j - 1) * ncx + i])
				# y edge: (i,j,k) -> (i,j+1,k); cells around it differ in x and z.
				if s0 != (d[((k * ny) + j + 1) * nx + i] > 0.0):
					_quad(indices, faces, verts, normals, cell_vert, [
						(k - 1) * ncy * ncx + j * ncx + (i - 1), (k - 1) * ncy * ncx + j * ncx + i,
						k * ncy * ncx + j * ncx + i, k * ncy * ncx + j * ncx + (i - 1)])
				# z edge: (i,j,k) -> (i,j,k+1); cells around it differ in x and y.
				if j >= 1 and s0 != (d[(((k + 1) * ny) + j) * nx + i] > 0.0):
					_quad(indices, faces, verts, normals, cell_vert, [
						k * ncy * ncx + (j - 1) * ncx + (i - 1), k * ncy * ncx + (j - 1) * ncx + i,
						k * ncy * ncx + j * ncx + i, k * ncy * ncx + j * ncx + (i - 1)])
	return _shared(_match_borders(_clip_to_chunk(verts, normals, colors, indices, size), gen, plan, origin, size))


## Keeps only the part of the surface inside the chunk's square (x and z from 0 to size). Each chunk makes faces a
## little past its edges and keeps its own side of them, so neighbours meet exactly along the border: no strip of
## ground is left out, and nothing is drawn twice.
static func _clip_to_chunk(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, size: float) -> Dictionary:
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_i := PackedInt32Array()
	var faces := PackedVector3Array()
	for t in range(0, indices.size(), 3):
		# A triangle lying flat in this chunk's far border (a cell vertex can be clamped onto it) belongs to the
		# neighbour on the other side, which keeps it as lying on its near border: otherwise both chunks draw it.
		var far_x := true
		var far_z := true
		for c in 3:
			var q: Vector3 = verts[indices[t + c]]
			far_x = far_x and q.x > size - 0.0001
			far_z = far_z and q.z > size - 0.0001
		if far_x or far_z:
			continue
		var tri: Array = []
		var inside := true
		for c in 3:
			var vi: int = indices[t + c]
			var p: Vector3 = verts[vi]
			if p.x < 0.0 or p.x > size or p.z < 0.0 or p.z > size:
				inside = false
			tri.append([p, normals[vi], colors[vi]])
		var poly: Array = tri if inside else _clip_polygon(tri, size)
		for q in range(1, poly.size() - 1):
			for corner: Array in [poly[0], poly[q], poly[q + 1]]:
				var p: Vector3 = corner[0]
				out_i.append(out_v.size())
				out_v.append(p)
				out_n.append(corner[1])
				out_c.append(corner[2])
				faces.append(p)
	return {"verts": out_v, "normals": out_n, "colors": out_c, "indices": out_i, "faces": faces}


## Sutherland-Hodgman against the four sides of the square; each point is [position, normal, colour].
## Where this chunk meets a heightfield chunk, the ground along the border has to be the very same line, or thin
## cracks show. A heightfield border runs straight between samples every ChunkGenerator.FINE metres, so: the ground
## points on the border are put on that line, and border edges are split at its samples, so both sides share every
## point. (Cave walls crossing a border are left alone: they're nowhere near the line, and the neighbour is solid
## ground there too, cut the same way.)
static func _match_borders(m: Dictionary, gen: WorldGen, plan: Dictionary, origin: Vector3, size: float) -> Dictionary:
	var v_in: PackedVector3Array = m.verts
	var n_in: PackedVector3Array = m.normals
	var c_in: PackedColorArray = m.colors
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_i := PackedInt32Array()
	var faces := PackedVector3Array()
	var line := {}   # border sample heights, by world xz
	for t in range(0, v_in.size(), 3):
		var tri: Array = []
		for c in 3:
			var p := v_in[t + c]
			var b := _border_plane(p, size)
			if b >= 0:
				var want := _border_line(gen, origin, p, b, line)
				if absf(p.y - want) < 1.0 and Caves.void_distance(plan, p + origin) > 1.5:
					p.y = want
			tri.append([p, n_in[t + c], c_in[t + c]])
		for piece: Array in _split_on_border(tri, gen, plan, origin, size, line):
			for corner: Array in piece:
				out_i.append(out_v.size())
				out_v.append(corner[0])
				out_n.append(corner[1])
				out_c.append(corner[2])
				faces.append(corner[0])
	return {"verts": out_v, "normals": out_n, "colors": out_c, "indices": out_i, "faces": faces}


## The same surface with each corner stored once and the triangles indexing them (about a third of the vertices to
## hand to the renderer, which is done on the main thread). The collider keeps its flat list of faces.
static func _shared(m: Dictionary) -> Dictionary:
	var v_in: PackedVector3Array = m.verts
	var n_in: PackedVector3Array = m.normals
	var c_in: PackedColorArray = m.colors
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_i := PackedInt32Array()
	out_i.resize(v_in.size())
	var seen := {}   # position -> index
	for i in v_in.size():
		var p := v_in[i]
		var at: int = seen.get(p, -1)
		if at >= 0 and out_n[at].dot(n_in[i]) > 0.999:
			out_i[i] = at
			continue
		at = out_v.size()
		if not seen.has(p):
			seen[p] = at
		out_v.append(p)
		out_n.append(n_in[i])
		out_c.append(c_in[i])
		out_i[i] = at
	return {"verts": out_v, "normals": out_n, "colors": out_c, "indices": out_i, "faces": m.faces}


## Which border a local point is on: 0 = x 0, 1 = x size, 2 = z 0, 3 = z size; -1 for none.
static func _border_plane(p: Vector3, size: float) -> int:
	if absf(p.x) < 0.001:
		return 0
	if absf(p.x - size) < 0.001:
		return 1
	if absf(p.z) < 0.001:
		return 2
	if absf(p.z - size) < 0.001:
		return 3
	return -1


## The heightfield's ground height at a local border point: straight between the FINE samples either side.
static func _border_line(gen: WorldGen, origin: Vector3, p: Vector3, plane: int, cache: Dictionary) -> float:
	var along := p.z if plane < 2 else p.x
	var f := ChunkGenerator.FINE
	var i0 := floori(along / f + 0.0001)
	var t := clampf(along / f - i0, 0.0, 1.0)
	var h0 := _sample(gen, origin, p, plane, i0 * f, cache)
	if t < 0.0001:
		return h0
	return lerpf(h0, _sample(gen, origin, p, plane, (i0 + 1) * f, cache), t)


static func _sample(gen: WorldGen, origin: Vector3, p: Vector3, plane: int, along: float, cache: Dictionary) -> float:
	var w := Vector2(origin.x + p.x, origin.z + along) if plane < 2 else Vector2(origin.x + along, origin.z + p.z)
	if not cache.has(w):
		cache[w] = gen.get_height(w.x, w.y)
	return cache[w]


## A triangle, split wherever one of its edges runs along the border past a heightfield sample, so the sample is a
## corner here too. Corners are [position, normal, colour].
static func _split_on_border(tri: Array, gen: WorldGen, plan: Dictionary, origin: Vector3, size: float, line: Dictionary) -> Array:
	for e in 3:
		var a: Array = tri[e]
		var b: Array = tri[(e + 1) % 3]
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var plane := -1
		for pl in 4:
			if _on_plane(pa, pl, size) and _on_plane(pb, pl, size):
				plane = pl
				break
		if plane < 0:
			continue
		var sa := pa.z if plane < 2 else pa.x
		var sb := pb.z if plane < 2 else pb.x
		var f := ChunkGenerator.FINE
		var lo := minf(sa, sb)
		var hi := maxf(sa, sb)
		var k := ceili((lo + 0.01) / f)
		var s := k * f
		if s >= hi - 0.01:
			continue
		# Split this edge at the sample s.
		var t := (s - sa) / (sb - sa)
		var q: Vector3 = pa.lerp(pb, t)
		var want := _border_line(gen, origin, q, plane, line)
		if absf(q.y - want) < 1.0 and Caves.void_distance(plan, q + origin) > 1.5:
			q.y = want
		var mid := [q, (a[1] as Vector3).lerp(b[1], t).normalized(), (a[2] as Color).lerp(b[2], t)]
		var c: Array = tri[(e + 2) % 3]
		var out: Array = []
		out.append_array(_split_on_border([a, mid, c], gen, plan, origin, size, line))
		out.append_array(_split_on_border([mid, b, c], gen, plan, origin, size, line))
		return out
	return [tri]


static func _on_plane(p: Vector3, plane: int, size: float) -> bool:
	match plane:
		0: return absf(p.x) < 0.001
		1: return absf(p.x - size) < 0.001
		2: return absf(p.z) < 0.001
		_: return absf(p.z - size) < 0.001


static func _clip_polygon(poly: Array, size: float) -> Array:
	for plane in 4:
		var out: Array = []
		for i in poly.size():
			var a: Array = poly[i]
			var b: Array = poly[(i + 1) % poly.size()]
			var da := _side(a[0], plane, size)
			var db := _side(b[0], plane, size)
			if da >= 0.0:
				out.append(a)
			if (da >= 0.0) != (db >= 0.0):
				var t := da / (da - db)
				var pa: Vector3 = a[0]
				var na: Vector3 = a[1]
				var ca: Color = a[2]
				out.append([pa.lerp(b[0], t), na.lerp(b[1], t).normalized(), ca.lerp(b[2], t)])
		poly = out
		if poly.size() < 3:
			return []
	return poly


## How far inside side `plane` a point is (0 = left, 1 = right, 2 = near, 3 = far); negative is outside.
static func _side(p: Vector3, plane: int, size: float) -> float:
	match plane:
		0:
			return p.x
		1:
			return size - p.x
		2:
			return p.z
	return size - p.z


## Rows (from, to) of a sample column where a cell can cross the surface: one below its first air sample
## up to its last air sample. An empty column gives (ncy, -1).
static func _span(col_lo: PackedInt32Array, col_hi: PackedInt32Array, col: int, ncy: int) -> Vector2i:
	if col_hi[col] < 0:
		return Vector2i(ncy, -1)
	return Vector2i(col_lo[col] - 1, col_hi[col])


static func _union(a: Vector2i, b: Vector2i) -> Vector2i:
	if a.x > a.y:
		return b
	if b.x > b.y:
		return a
	return Vector2i(mini(a.x, b.x), maxi(a.y, b.y))


## The outward surface normal at grid sample (i, j, k), from the density gradient around it.
static func _corner_normal(d: PackedFloat32Array, nx: int, ny: int, nz: int, i: int, j: int, k: int) -> Vector3:
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, nx - 1)
	var jl := maxi(j - 1, 0)
	var jr := mini(j + 1, ny - 1)
	var kl := maxi(k - 1, 0)
	var kr := mini(k + 1, nz - 1)
	var gx := d[(k * ny + j) * nx + ir] - d[(k * ny + j) * nx + il]
	var gy := d[(k * ny + jr) * nx + i] - d[(k * ny + jl) * nx + i]
	var gz := d[(kr * ny + j) * nx + i] - d[(kl * ny + j) * nx + i]
	var n := Vector3(-gx, -gy, -gz)
	return n.normalized() if n.length_squared() > 0.000001 else Vector3.UP


## The 12 edges of a cube, as corner index pairs (corner bit 0 = x, bit 1 = y, bit 2 = z).
const _EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


## Per sample column, the highest a cave may be cut there: a skin of rock is kept between every cave and the open
## air, so a tunnel planned close under a cliff or a steep side never breaks out through it (a hole in a mesa's
## face with the sky showing through). The skin is a ball's worth of rock round the cut: under the ground here, and
## under the ground a step or so to each side (a cliff face next to the column). Only round the cave mouths, where
## the caves are meant to open, is there none.
static func _seal(gen: WorldGen, plan: Dictionary, origin: Vector3, step: float, hs: PackedFloat32Array, nx: int, nz: int) -> PackedFloat32Array:
	var seal := PackedFloat32Array()
	seal.resize(nx * nz)
	# Never thinner than about a cell and a half of the grid: rock thinner than a cell melts into dents and slivers
	# in the mesh (its two faces share cells), showing the cave through the slope.
	var up := maxf(SKIN_UP, step * 1.1)
	var skin := maxf(SKIN, step * 1.6)
	var reach := ceili(skin / step - 0.001)   # neighbour samples within the skin
	var near_r := skin * skin - 0.001
	var offs: Array[Vector3] = []   # (di, dk, how far under that neighbour's ground the cut must stay)
	for dk in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var o2 := (di * di + dk * dk) * step * step
			if o2 > 0.0 and o2 < near_r:
				offs.append(Vector3(di, dk, sqrt(skin * skin - o2)))
	# Heights one ring past the grid's own, so the columns at its edge see the same neighbours as the next chunk's.
	var ex := nx + 2 * reach
	var ez := nz + 2 * reach
	var eh := PackedFloat32Array()
	eh.resize(ex * ez)
	for k in ez:
		for i in ex:
			var gi := i - reach
			var gk := k - reach
			if gi >= 0 and gi < nx and gk >= 0 and gk < nz:
				eh[k * ex + i] = hs[gk * nx + gi]
			else:
				eh[k * ex + i] = gen.get_height(origin.x + (gi - PAD) * step, origin.z + (gk - PAD) * step)
	# The mouths near this chunk.
	var mouths: Array[Vector2] = []
	var span := Game.CHUNK_SIZE + (PAD + 1) * step + MOUTH_FREE + MOUTH_RAMP + 4.0
	var mid := Vector2(origin.x + Game.CHUNK_SIZE * 0.5, origin.z + Game.CHUNK_SIZE * 0.5)
	for m: Vector3 in plan.get("entrances", []):
		if absf(m.x - mid.x) < span and absf(m.z - mid.y) < span:
			mouths.append(Vector2(m.x, m.z))
	var free := Caves.MOUTH_R + MOUTH_FREE
	for k in nz:
		for i in nx:
			var top := hs[k * nx + i] - up
			for o: Vector3 in offs:
				top = minf(top, eh[(k + reach + int(o.y)) * ex + i + reach + int(o.x)] - o.z)
			if not mouths.is_empty():
				var w := Vector2(origin.x + (i - PAD) * step, origin.z + (k - PAD) * step)
				var dm := 1e9
				for m: Vector2 in mouths:
					dm = minf(dm, w.distance_squared_to(m))
				# Open at the mouth; the rock closes in over the next few metres.
				top += (1.0 - clampf((sqrt(dm) - free) / MOUTH_RAMP, 0.0, 1.0)) * 60.0
			seal[k * nx + i] = top
	return seal


## Cut the density by one cave piece: its wall distance, where that is closer than the rock (and only below the
## column's seal, see _seal).
static func _carve(d: PackedFloat32Array, s: Array, origin: Vector3, ylo: float, step: float, nx: int, ny: int, nz: int, seal: PackedFloat32Array) -> void:
	var a: Vector3 = s[0]
	var b: Vector3 = s[1]
	var ra := float(s[2])
	var rb := float(s[3])
	var reach := maxf(ra, rb) + step
	var lo := Vector3(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach, minf(a.z, b.z) - reach)
	var hi := Vector3(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach, maxf(a.z, b.z) + reach)
	var i0 := clampi(floori((lo.x - origin.x) / step) + PAD, 0, nx - 1)
	var i1 := clampi(ceili((hi.x - origin.x) / step) + PAD, 0, nx - 1)
	var k0 := clampi(floori((lo.z - origin.z) / step) + PAD, 0, nz - 1)
	var k1 := clampi(ceili((hi.z - origin.z) / step) + PAD, 0, nz - 1)
	var j0 := clampi(floori((lo.y - ylo) / step), 0, ny - 1)
	var j1 := clampi(ceili((hi.y - ylo) / step), 0, ny - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var fa := float(s[6])   # the piece's flat floor at each end, and its flat top (see Caves._piece_distance)
	var fb := float(s[7])
	var ceil_y := float(s[8])
	for k in range(k0, k1 + 1):
		var z := origin.z + (k - PAD) * step
		for j in range(j0, j1 + 1):
			var y := ylo + j * step
			var row := (k * ny + j) * nx
			for i in range(i0, i1 + 1):
				var p := Vector3(origin.x + (i - PAD) * step, y, z)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var dist := maxf(maxf(maxf(p.distance_to(a + ab * t) - lerpf(ra, rb, t), lerpf(fa, fb, t) - y), y - ceil_y), y - seal[k * nx + i])
				if dist < d[row + i]:
					d[row + i] = dist


## One quad from four cell vertices, as two triangles. `facing` is the outward direction of the surface
## here. Godot shows the FRONT of a triangle as the side its winding points away from, so each
## triangle is wound to have its normal pointing into the rock; a triangle that's wound the other
## way is culled from outside and you see through the ground. Each triangle is checked on its own,
## so quads that aren't flat still come out right.
static func _quad(indices: PackedInt32Array, faces: PackedVector3Array, verts: PackedVector3Array, normals: PackedVector3Array, cell_vert: PackedInt32Array, cells: Array) -> void:
	var q := PackedInt32Array()
	for c: int in cells:
		var vi := cell_vert[c]
		if vi < 0:
			return   # should not happen: a crossing edge always has its four cells with vertices
		q.append(vi)
	_tri(indices, faces, verts, normals, q[0], q[1], q[2])
	_tri(indices, faces, verts, normals, q[0], q[2], q[3])


## One triangle, wound so its normal points against `outward` (into the rock).
static func _tri(indices: PackedInt32Array, faces: PackedVector3Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var pa := verts[a]
	var n := (verts[b] - pa).cross(verts[c] - pa)
	var outward := normals[a] + normals[b] + normals[c]
	if n.dot(outward) > 0.0:
		var t := b
		b = c
		c = t
	indices.append_array([a, b, c])
	faces.append_array([verts[a], verts[b], verts[c]])
