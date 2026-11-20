class_name DofBlur
extends MeshInstance3D
## Depth of field for one camera: hang it under the camera, set focus / range / amount. Hidden (free) at amount 0.
## (Our own pass: the engine's blurred the whole frame whatever the focus.)

var _mat: ShaderMaterial


static func attach(cam: Camera3D) -> DofBlur:
	var d := DofBlur.new()
	cam.add_child(d)
	return d


func _init() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/dof_blur.gdshader")
	_mat.render_priority = 100   # after everything else
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	position = Vector3(0, 0, -0.5)
	visible = false


func set_blur(focus: float, range_m: float, amount: float) -> void:
	visible = amount > 0.002
	if visible:
		_mat.set_shader_parameter("focus", focus)
		_mat.set_shader_parameter("range", range_m)
		_mat.set_shader_parameter("amount", amount)
