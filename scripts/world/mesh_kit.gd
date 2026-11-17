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
var _noise: FastNoiseLite


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
			c = Color(c.r + j, c.g + j, c.b + j)
		col[i] = c.srgb_to_linear()
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		if flat_shading:
			var fn := (moved[c] - moved[a]).cross(moved[b] - moved[a])
			if fn.length_squared() < 1e-12:
				continue
			fn = fn.normalized()
			verts.append_array([moved[a], moved[b], moved[c]])
			normals.append_array([fn, fn, fn])
		else:
			verts.append_array([moved[a], moved[b], moved[c]])
			normals.append_array([nrm[a], nrm[b], nrm[c]])
		colors.append_array([col[a], col[b], col[c]])


# --- Sculpting helpers: shapes built vertex by vertex ---------------------------------

## Emit one triangle, flipping it if needed so it faces `outward`. Colors are sRGB.
func _emit(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	var fn := (c - a).cross(b - a)
	if fn.length_squared() < 1e-14:
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


## A tube along a path: handles, branches, horns, stems, logs, curved pick heads.
## radii:    one radius per path point (tapers, bulges).
## shape_fn: optional Callable(t: float, angle: float) -> Vector2 cross-section scale (ovals, flats).
## color_fn: optional Callable(t: float, angle: float) -> Color (wraps, bands, bark ridges).
## bumps:    noise displacement of the surface (gnarled wood, bark).
func loft(path: Array, radii: Array, sides := 8, color := Color.WHITE, color_fn := Callable(),
		shape_fn := Callable(), cap_start := true, cap_end := true, bumps := 0.0) -> void:
	var n := path.size()
	if n < 2:
		return
	var rings: Array = []
	var ring_n: Array = []
	var ring_c: Array = []
	var tangent := ((path[1] as Vector3) - (path[0] as Vector3)).normalized()
	var normal := tangent.cross(Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	for i in n:
		var p: Vector3 = path[i]
		var prev: Vector3 = path[maxi(i - 1, 0)]
		var next: Vector3 = path[mini(i + 1, n - 1)]
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
	for i in n - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][j2]
			var c: Vector3 = rings[i + 1][j2]
			var d: Vector3 = rings[i + 1][j]
			var out := ((a + b + c + d) * 0.25 - ((path[i] as Vector3) + (path[i + 1] as Vector3)) * 0.5)
			_emit(a, b, c, ring_n[i][j], ring_n[i][j2], ring_n[i + 1][j2], ring_c[i][j], ring_c[i][j2], ring_c[i + 1][j2], out)
			_emit(a, c, d, ring_n[i][j], ring_n[i + 1][j2], ring_n[i + 1][j], ring_c[i][j], ring_c[i + 1][j2], ring_c[i + 1][j], out)
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
	var count := outline.size()
	if count < 3:
		return
	var centroid := Vector2.ZERO
	for p in outline:
		centroid += p
	centroid /= count
	var inner := PackedVector2Array()
	for p in outline:
		var to_c := centroid - p
		inner.append(p + to_c.normalized() * minf(bevel, to_c.length() * 0.7))
	var tris := Geometry2D.triangulate_polygon(inner)
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
			var mid2 := (outline[i] + outline[i2]) * 0.5 - centroid
			var out: Vector3 = xf.basis * Vector3(mid2.x, mid2.y, 0.0).normalized() + zx * float(side) * 0.6
			_emit(ia, ib, ob, out, out, out, color, color, edge_color, out)
			_emit(ia, ob, oa, out, out, out, color, edge_color, edge_color, out)
	for i in count:   # the thin edge band
		var i2 := (i + 1) % count
		var a: Vector3 = to3.call(outline[i], edge)
		var b: Vector3 = to3.call(outline[i2], edge)
		var c: Vector3 = to3.call(outline[i2], -edge)
		var d: Vector3 = to3.call(outline[i], -edge)
		var mid2 := (outline[i] + outline[i2]) * 0.5 - centroid
		var out := xf.basis * Vector3(mid2.x, mid2.y, 0.0).normalized()
		_emit(a, b, c, out, out, out, edge_color, edge_color, edge_color, out)
		_emit(a, c, d, out, out, out, edge_color, edge_color, edge_color, out)


func commit(material: Material) -> ArrayMesh:
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
