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
const ROCK_BAND := 1.2      ## vertices this far below the ground are cave walls (rock colour)


## Returns {verts, normals, colors, indices, faces}. Vertices are local to the chunk origin.
## `segs` are the cave pieces that reach this chunk (see Caves.segments_near).
static func build(gen: WorldGen, origin: Vector3, size: float, step: float, segs: Array) -> Dictionary:
	var res := roundi(size / step)
	var nx := res + 3          # samples per side: one spare on each side for the border
	var nz := res + 3
	var ox := origin.x
	var oz := origin.z

	# Ground heights on the sample grid, and the vertical range the caves need.
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	var hmin := 1e9
	var hmax := -1e9
	for k in nz:
		for i in nx:
			var h := gen.get_height(ox + (i - 1) * step, oz + (k - 1) * step)
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
	for ck in ncz:
		for cj in ncy:
			for ci in ncx:
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
				var wx := ox + (ci - 1) * step
				var wy := ylo + cj * step
				var wz := oz + (ck - 1) * step
				for c in 8:
					corner[c] = Vector3(wx + (c & 1) * step, wy + ((c >> 1) & 1) * step, wz + ((c >> 2) & 1) * step)
				var sum := Vector3.ZERO
				var count := 0
				for e in _EDGES:
					var a: int = e[0]
					var b: int = e[1]
					if (corner_v[a] > 0.0) == (corner_v[b] > 0.0):
						continue
					var t := corner_v[a] / (corner_v[a] - corner_v[b])
					sum += corner[a].lerp(corner[b], t)
					count += 1
				var vert := sum / float(count)
				# Normal: the density gradient, pointing out of the rock.
				var v := corner_v
				var gx := (v[1] + v[3] + v[5] + v[7]) - (v[0] + v[2] + v[4] + v[6])
				var gy := (v[2] + v[3] + v[6] + v[7]) - (v[0] + v[1] + v[4] + v[5])
				var gz := (v[4] + v[5] + v[6] + v[7]) - (v[0] + v[1] + v[2] + v[3])
				var nrm := Vector3(-gx, -gy, -gz)
				nrm = nrm.normalized() if nrm.length_squared() > 0.000001 else Vector3.UP
				var col: Color
				if vert.y < gen.get_height(vert.x, vert.z) - ROCK_BAND:
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
	for k in range(1, res + 1):
		for i in range(1, res + 1):
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
	var i0 := clampi(floori((lo.x - origin.x) / step) + 1, 0, nx - 1)
	var i1 := clampi(ceili((hi.x - origin.x) / step) + 1, 0, nx - 1)
	var k0 := clampi(floori((lo.z - origin.z) / step) + 1, 0, nz - 1)
	var k1 := clampi(ceili((hi.z - origin.z) / step) + 1, 0, nz - 1)
	var j0 := clampi(floori((lo.y - ylo) / step), 0, ny - 1)
	var j1 := clampi(ceili((hi.y - ylo) / step), 0, ny - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for k in range(k0, k1 + 1):
		var z := origin.z + (k - 1) * step
		for j in range(j0, j1 + 1):
			var y := ylo + j * step
			var row := (k * ny + j) * nx
			for i in range(i0, i1 + 1):
				var p := Vector3(origin.x + (i - 1) * step, y, z)
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
