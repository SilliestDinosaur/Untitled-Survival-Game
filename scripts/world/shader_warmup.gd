extends Node3D
## Draws every material the game uses once, behind the loading screen, so their shaders are compiled then and not
## the first time something new comes into view mid-game (a new biome's plants, a cave, a first spark or splash),
## which stalled play for up to a second or more on some machines.
##
## Each material goes on a tiny quad just in front of the camera, drawn both on its own and as a one-instance
## MultiMesh (plants, grass and particles are drawn that way, and that is a separate shader variant), casting
## shadows (the shadow pass is another). The materials come from everything already in the scene, plus what is only
## made later (all the plants' and animals' meshes, the effects' and caves' shared materials).

const FRAMES := 4

var _frames := 0
var done := false


func start(cam: Camera3D, extra: Array) -> void:
	var mats := {}
	_collect(get_tree().root, mats)
	for m in extra:
		_add(m, mats)
	for m in _shader_files():
		_add(m, mats)
	var quad := _quad()
	var i := 0
	var cols := 24
	for m: Material in mats:
		# A small grid a couple of metres ahead: each quad a few millimetres, all well inside the view.
		var off := Vector3((i % cols - cols * 0.5) * 0.012, (i / cols) * 0.012 - 0.1, -2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.extra_cull_margin = 1.0
		add_child(mi)
		mi.global_transform = cam.global_transform * Transform3D(Basis(), off)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_color(0, Color.WHITE)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		add_child(mmi)
		mmi.global_transform = cam.global_transform * Transform3D(Basis(), off + Vector3(0, 0, 0.004))
		i += 1
	print("Shader warm-up: %d materials" % mats.size())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= FRAMES:
		done = true


## One material for each 3D shader in res://shaders (a shader compiles once whatever its parameters, so this covers
## the materials that are only made when they're needed: cave water, light shafts, glows...).
static func _shader_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://shaders")
	if not dir:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if not f.ends_with(".gdshader"):
			continue
		var sh := load("res://shaders/" + f) as Shader
		if sh and sh.get_mode() == Shader.MODE_SPATIAL:
			var m := ShaderMaterial.new()
			m.shader = sh
			out.append(m)
	return out


## A quad carrying every vertex attribute the game's meshes use (normals, colours, uvs), a few mm across.
static func _quad() -> ArrayMesh:
	var s := 0.004
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-s, -s, 0), Vector3(s, -s, 0), Vector3(s, s, 0), Vector3(-s, -s, 0), Vector3(s, s, 0), Vector3(-s, s, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _add(m: Variant, mats: Dictionary) -> void:
	var guard := 0
	while m is Material and guard < 4:
		if m is ShaderMaterial or m is BaseMaterial3D:
			mats[m] = true
		m = (m as Material).next_pass
		guard += 1


static func _add_mesh(mesh: Mesh, mats: Dictionary) -> void:
	if not mesh:
		return
	for s in mesh.get_surface_count():
		_add(mesh.surface_get_material(s), mats)


func _collect(n: Node, mats: Dictionary) -> void:
	if n == self or n is CanvasItem:
		return
	if n is GeometryInstance3D:
		_add((n as GeometryInstance3D).material_override, mats)
		_add((n as GeometryInstance3D).material_overlay, mats)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_add_mesh(mi.mesh, mats)
		for s in mi.get_surface_override_material_count():
			_add(mi.get_surface_override_material(s), mats)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		_add_mesh((n as MultiMeshInstance3D).multimesh.mesh, mats)
	elif n is CPUParticles3D:
		_add_mesh((n as CPUParticles3D).mesh, mats)
	elif n is GPUParticles3D:
		var gp := n as GPUParticles3D
		for p in gp.draw_passes:
			_add_mesh(gp.get_draw_pass_mesh(p), mats)
	for c in n.get_children():
		_collect(c, mats)
