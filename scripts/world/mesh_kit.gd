class_name MeshKit
extends RefCounted
## Helper for building stylized meshes in code, with vertex colors.
## Normals are smooth by default (painterly look). A `puff_center` makes a group of shapes
## light as one soft volume, which is what makes tree canopies look painted and fluffy.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var force_up_normals := false   ## grass: light it like the ground under it

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
		if shade_jitter > 0.0:
			var j := _noise.get_noise_3dv(p * 1.7) * shade_jitter
			c = Color(c.r + j, c.g + j, c.b + j)
		col[i] = c.srgb_to_linear()
	for t in idx.size():
		var k := idx[t]
		verts.append(moved[k])
		normals.append(nrm[k])
		colors.append(col[k])


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
