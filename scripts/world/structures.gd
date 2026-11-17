extends Node3D
## Shows placed structures (Game.structures): campfires with flickering firelight, workbenches,
## forges with glowing coals. Pure view of shared data, re-synced when it changes.

var _nodes := {}   # structure id -> Node3D
var _mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _flame_mesh: ArrayMesh


func _ready() -> void:
	_mat = ArtStyle.painted({"brush_strength": 0.22, "rim_amount": 0.3})
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.45, 0.12)
	_glow_mat.emission_energy_multiplier = 1.6
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.vertex_color_use_as_albedo = true
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mesh = _build_flame()
	Game.structures_changed.connect(_sync)
	Game.world_changed.connect(func() -> void:
		StructureModels.clear_cache()
		for id: String in _nodes.keys():
			_nodes[id].queue_free()
		_nodes.clear()
		_sync())
	_sync()


## Flame tongues: three lofted teardrops, yellow core fading to red tips.
func _build_flame() -> ArrayMesh:
	var k := MeshKit.new(9)
	for i in 3:
		var a := TAU * i / 3.0
		var base := Vector3(cos(a) * 0.06, 0.05, sin(a) * 0.06)
		var h := 0.45 - i * 0.07
		var path := []
		var radii := []
		for s in 8:
			var t := s / 7.0
			path.append(base.lerp(Vector3(0, base.y + h, 0), t) + Vector3(sin(t * 4.0 + i) * 0.02, 0, 0))
			radii.append(sin(pow(t, 0.6) * PI) * 0.09 * (1.0 - t * 0.5))
		k.loft(path, radii, 10, Color(1, 0.8, 0.3), func(t: float, _a: float) -> Color:
			return Color(1.0, 0.85, 0.4).lerp(Color(0.9, 0.25, 0.05), t))
	return k.commit(_flame_mat)


func _sync() -> void:
	for id: String in _nodes.keys():
		if not Game.structures.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id: String in Game.structures:
		if not _nodes.has(id):
			_nodes[id] = _make(Game.structures[id])


func _make(st: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pos: Array = st.pos
	root.position = Vector3(pos[0], pos[1], pos[2])
	root.rotation.y = float(st.get("yaw", 0.0))
	var model := StructureModels.get_model(st.kind, _mat, _glow_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = model.body
	root.add_child(mi)
	if model.glow:
		var gi := MeshInstance3D.new()
		gi.mesh = model.glow
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
	if st.kind in ["campfire", "forge"]:
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position = model.light
		light.light_color = Color(1.0, 0.62, 0.3)
		light.omni_range = 9.0 if st.kind == "campfire" else 6.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = st.kind == "campfire" and Settings.shadow_quality in ["High", "Ultra"]
		root.add_child(light)
	if st.kind == "campfire":
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		flame.mesh = _flame_mesh
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(flame)
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_SOLID | TerrainChunk.LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta("structure", st.id)
	var cs := CollisionShape3D.new()
	if GameActions.is_building(st.kind):
		var box := BoxShape3D.new()
		if st.kind == "foundation":
			box.size = Vector3(2.0, 0.5, 2.0)
			cs.position.y = 0.0
		else:
			box.size = Vector3(2.0, 2.4, 0.3)
			cs.position.y = 1.2
		cs.shape = box
	else:
		var shape := CylinderShape3D.new()
		shape.radius = model.radius
		shape.height = 0.9 if st.kind != "forge" else 2.0
		cs.shape = shape
		cs.position.y = shape.height * 0.5
	body.add_child(cs)
	root.add_child(body)
	root.set_meta("phase", randf() * TAU)
	add_child(root)
	return root


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var night := 1.0 - Game.daylight()
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		var ph: float = n.get_meta("phase")
		var flicker := 0.8 + 0.12 * sin(t * 11.0 + ph) + 0.08 * sin(t * 23.0 + ph * 2.0)
		var light := n.get_node_or_null("Light") as OmniLight3D
		if light:
			light.light_energy = flicker * lerpf(0.8, 2.2, night)
		var flame := n.get_node_or_null("Flame") as Node3D
		if flame:
			flame.scale = Vector3(1.0 + 0.08 * sin(t * 9.0 + ph), flicker * 1.1, 1.0 + 0.08 * cos(t * 7.0 + ph))
			flame.rotation.y = t * 0.8 + ph
