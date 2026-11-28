class_name AvatarPreview
extends SubViewportContainer
## Your character as friends will see them (see Avatar), turning slowly on a little stage of their own: the
## Play with Friends screen shows it while you choose how you look.

var _viewport: SubViewport
var _figure: Node3D
var _mat: ShaderMaterial
var _turn := 0.4


func _init(size_px := Vector2i(240, 320)) -> void:
	custom_minimum_size = Vector2(size_px)
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = size_px
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.8, 0.75)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	# Set as a transform (not look_at: it isn't in the tree yet), in front of the figure (its face is toward -z).
	var from := Vector3(0, 1.4, -3.9)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.12, 0) - from, Vector3.UP), from)
	cam.current = true
	_viewport.add_child(cam)
	# A little round of grass to stand over.
	var stage := MeshInstance3D.new()
	stage.mesh = MeshKit.cylinder(0.75, 0.8, 0.08, 24)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.46, 0.62, 0.34)
	stage.material_override = sm
	stage.position = Vector3(0, 0.36, 0)
	_viewport.add_child(stage)
	_figure = Node3D.new()
	_viewport.add_child(_figure)


func set_look(look: Dictionary) -> void:
	if not _mat:
		_mat = ArtStyle.painted({"brush_strength": 0.18, "rim_amount": 0.35})
	for c in _figure.get_children():
		c.queue_free()
	var l := Avatar.clean(look)
	var torso := MeshInstance3D.new()
	torso.mesh = Avatar.torso_mesh(Settings.PLAYER_COLORS[l.shirt], _mat)
	_figure.add_child(torso)
	var head := MeshInstance3D.new()
	head.mesh = Avatar.head_mesh(l, _mat)
	head.position = Vector3(0, 1.6, 0)
	_figure.add_child(head)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_turn += delta * 0.6
	# Turning slowly, mostly facing you (a wide sway rather than spinning round).
	_figure.rotation.y = sin(_turn) * 1.3
	_figure.position.y = sin(_turn * 2.3) * 0.02
