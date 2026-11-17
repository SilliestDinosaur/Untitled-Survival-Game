class_name MeshKit
extends RefCounted
## Tiny helper for building low-poly meshes in code: flat-shaded triangles with vertex colors.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var force_up_normals := false   ## grass: light it like the ground under it
var _noise: FastNoiseLite


func _init(noise_seed := 0) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.frequency = 0.9


## Colors are given in sRGB (what you'd pick in a color picker) and stored linear.
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


## Adds a primitive (cylinder, sphere...) with a transform, a color, and optional lumpy noise.
## `lumpy` pushes vertices in/out along their direction from the primitive's center.
## Shared vertices get the same push, so the mesh stays watertight.
func add_primitive(prim: PrimitiveMesh, xf: Transform3D, color: Color, lumpy := 0.0, shade_jitter := 0.04) -> void:
	var arrays := prim.get_mesh_arrays()
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	moved.resize(src.size())
	for i in src.size():
		var v := src[i]
		if lumpy > 0.0 and v.length_squared() > 1e-6:
			var key := v * 3.0 + xf.origin
			v += v.normalized() * _noise.get_noise_3dv(key) * lumpy
		moved[i] = xf * v
	for t in range(0, idx.size(), 3):
		var c := color
		if shade_jitter > 0.0:
			var j := _noise.get_noise_1d(t * 7.31 + xf.origin.x * 13.0) * shade_jitter
			c = Color(c.r + j, c.g + j, c.b + j)
		add_tri(moved[idx[t]], moved[idx[t + 1]], moved[idx[t + 2]], c)


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


static func cylinder(top: float, bottom: float, height: float, segments: int, caps := true) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	m.cap_top = caps and top > 0.0
	m.cap_bottom = caps
	return m


static func sphere(radius: float, segments := 7, rings := 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m
