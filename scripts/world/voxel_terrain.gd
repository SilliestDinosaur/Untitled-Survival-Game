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
	for s: Array in segs:
		_carve(d, s, origin, ylo, step, nx, ny, nz)

	# Surface nets: one vertex per cell that the surface passes through.
	var ncx := nx - 1
	var ncy := ny - 1
	var ncz := nz - 1
	var cell_vert := PackedInt32Array()
	cell_vert.resize(ncx * ncy * ncz)
	cell_vert.fill(-1)
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
				var gh: float = gen.get_height(vert.x, vert.z)
				if absf(vert.y - gh) < 6.0 and Caves.void_distance(plan, vert) > 2.5:
					vert.y = gh
				var nrm := nsum.normalized() if nsum.length_squared() > 0.000001 else Vector3.UP
				var col: Color
				if vert.y < gh - ROCK_BAND:
					col = Game.palette.rock.darkened(0.3)
				else:
					col = gen.get_terrain_color(vert.y, nrm.y, vert.x, vert.z)
				cell_vert[(ck * ncy + cj) * ncx + ci] = verts.size()
				verts.append(vert - origin)
				normals.append(nrm)
				colors.append(col.srgb_to_linear())

	# Faces: every grid edge that crosses the surface makes a quad from the four cells around it.
	# An edge belongs to the chunk whose sample grid it starts in (i and k inside 1..res).
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for k in range(PAD, PAD + res):
		for i in range(PAD, PAD + res):
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
	return {"verts": verts, "normals": normals, "colors": colors, "indices": indices, "faces": faces}


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


## Cut the density by one cave piece: its wall distance, where that is closer than the rock.
static func _carve(d: PackedFloat32Array, s: Array, origin: Vector3, ylo: float, step: float, nx: int, ny: int, nz: int) -> void:
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
	for k in range(k0, k1 + 1):
		var z := origin.z + (k - PAD) * step
		for j in range(j0, j1 + 1):
			var y := ylo + j * step
			var row := (k * ny + j) * nx
			for i in range(i0, i1 + 1):
				var p := Vector3(origin.x + (i - PAD) * step, y, z)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var dist := p.distance_to(a + ab * t) - lerpf(ra, rb, t)
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
