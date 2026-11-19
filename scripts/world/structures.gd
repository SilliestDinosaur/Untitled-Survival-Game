extends Node3D
## Shows placed structures (Game.structures): campfires with flickering firelight, workbenches,
## forges with glowing coals. Pure view of shared data, re-synced when it changes.

var _nodes := {}   # structure id -> Node3D
var _corners := {}  # wall corners -> the wall pieces ending there (StructureModels.corner_index), for butt joints
var _mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _flame_mesh: ArrayMesh
var _blueprint_mat: StandardMaterial3D   ## see-through blue for pieces not yet finished with the hammer


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
	_blueprint_mat = StandardMaterial3D.new()
	_blueprint_mat.albedo_color = Color(0.45, 0.72, 1.0, 0.38)
	_blueprint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blueprint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# The first world was built before this node existed, so its models are built here too.
	_prewarm()
	Game.structures_changed.connect(_sync)
	Game.world_changed.connect(func() -> void:
		StructureModels.clear_cache()
		_prewarm()
		for id: String in _nodes.keys():
			_free_node(id)
		_nodes.clear()
		_sync())
	_sync()


## Build the model of every placeable now, while the world loads. The first placement of a kind otherwise stalled
## the game for 150-900 ms while its model was built.
func _prewarm() -> void:
	var seen := {}
	for id: String in ItemDB.all_ids():
		var info: Dictionary = ItemDB.info(id)
		var kind: String = info.get("station", "")
		if info.get("kind", "") in ["placeable", "piece"] and kind != "" and not seen.has(kind):
			seen[kind] = true
			StructureModels.get_model(kind, _mat, _glow_mat)
	for piece: String in GameActions.PIECES:   # building pieces too (a fraction of a second for all of them)
		StructureModels.get_model(piece, _mat, _glow_mat)


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
			_free_node(id)
	_corners = StructureModels.corner_index(Game.structures)
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if _nodes.has(id) and is_instance_valid(_nodes[id]) and bool(_nodes[id].get_meta("blueprint", false)) != GameActions.is_blueprint(st):
			_free_node(id)   # a blueprint just finished: rebuild it solid
		if not _nodes.has(id) or not is_instance_valid(_nodes[id]):
			_nodes[id] = _make(st)
		else:
			_apply_door(_nodes[id], Game.structures[id])
			_apply_ends(_nodes[id], Game.structures[id])


## A wall's ends follow the walls it meets: placing or removing a neighbour can turn its corner joint around.
func _apply_ends(root: Node3D, st: Dictionary) -> void:
	if not st.kind in GameActions.EDGE_KINDS:
		return
	var ends := StructureModels.wall_ends(st, _corners)
	if root.get_meta("ends", Vector2.ZERO) == ends:
		return
	root.set_meta("ends", ends)
	var body := root.get_node_or_null("Body") as MeshInstance3D
	if body:
		body.mesh = StructureModels.get_model(st.kind, _mat, _glow_mat, ends).body


func _free_node(id: String) -> void:
	if is_instance_valid(_nodes[id]):
		_nodes[id].queue_free()
	_nodes.erase(id)


func _make(st: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pos: Array = st.pos
	root.position = Vector3(pos[0], pos[1], pos[2])
	root.rotation.y = float(st.get("yaw", 0.0))
	var ends := StructureModels.wall_ends(st, _corners) if st.kind in GameActions.EDGE_KINDS else Vector2.ZERO
	root.set_meta("ends", ends)
	var model := StructureModels.get_model(st.kind, _mat, _glow_mat, ends)
	var blueprint := GameActions.is_blueprint(st)
	root.set_meta("blueprint", blueprint)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = model.body
	if blueprint:
		mi.material_override = _blueprint_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif st.kind == "campfire":
		# Its light sits inside the log teepee: the logs would throw hard spokes of shadow across the ground.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if model.get("glass") != null:   # a window's pane: see-through, and no shadow
		var gl := MeshInstance3D.new()
		gl.name = "Glass"
		gl.mesh = model.glass
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if blueprint:
			gl.material_override = _blueprint_mat
		root.add_child(gl)
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
	# A blueprint can be aimed at (to hammer it) but walked through.
	body.collision_layer = TerrainChunk.LAYER_INTERACT if blueprint else TerrainChunk.LAYER_SOLID | TerrainChunk.LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta("structure", st.id)
	var panel: CollisionShape3D = null
	if GameActions.is_building(st.kind):
		panel = _add_piece_colliders(body, st.kind)
	else:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = model.radius
		shape.height = 0.9 if st.kind != "forge" else 2.0
		cs.shape = shape
		cs.position.y = shape.height * 0.5
		body.add_child(cs)
	root.add_child(body)
	if model.get("door") != null:
		var door_mesh: Mesh = model.door
		# The door panel swings on a pivot at its hinge; its collision follows the same swing.
		var pivot := Node3D.new()
		pivot.position = Vector3(-StructureModels.DOOR_W, 0.0, 0.0)
		var door_mi := MeshInstance3D.new()
		door_mi.mesh = door_mesh
		if blueprint:
			door_mi.material_override = _blueprint_mat
		pivot.add_child(door_mi)
		root.add_child(pivot)
		root.set_meta("pivot", pivot)
		root.set_meta("panel", panel)
		_apply_door(root, st)
	root.set_meta("phase", randf() * TAU)
	add_child(root)
	CaveShade.apply(root, CaveShade.at(root.position))   # built in a cave: the sky doesn't reach it
	return root


## Collision for a building piece: floors and roofs are slabs, half walls stand a metre high, stairs
## are their treads, doorways and doors leave the opening clear, everything else is a solid wall.
## Returns the door panel's shape (for doors), so it can follow the door's swing.
func _add_piece_colliders(body: StaticBody3D, kind: String) -> CollisionShape3D:
	var shape := GameActions.shape_of(kind)
	var h := GameActions.CELL * 0.5
	var panel: CollisionShape3D = null
	match shape:
		"floor":
			_box_collider(body, Vector3(GameActions.CELL, 0.5, GameActions.CELL), Vector3.ZERO)
		"roof":
			_box_collider(body, Vector3(GameActions.CELL, 0.3, GameActions.CELL), Vector3.ZERO)
		"half":
			_box_collider(body, Vector3(GameActions.CELL, 1.0, 0.3), Vector3(0, 0.5, 0))
		"stairs":
			var rise := GameActions.STACK_H / GameActions.STAIR_STEPS
			var run := GameActions.CELL / GameActions.STAIR_STEPS
			for i in GameActions.STAIR_STEPS:
				var top := GameActions.FLOOR_TOP + (i + 1) * rise
				var zc := h - (i + 0.5) * run
				_box_collider(body, Vector3(GameActions.CELL - 0.04, top, run + 0.02), Vector3(0, top * 0.5, zc))
		"doorway", "door":
			# Two posts and a lintel: walkable through the opening.
			_box_collider(body, Vector3(0.8, 3.0, 0.3), Vector3(-1.1, 1.5, 0))
			_box_collider(body, Vector3(0.8, 3.0, 0.3), Vector3(1.1, 1.5, 0))
			_box_collider(body, Vector3(1.4, 0.7, 0.3), Vector3(0, 2.65, 0))
			if shape == "door":
				panel = _box_collider(body, Vector3(StructureModels.DOOR_W * 2.0 - 0.04, StructureModels.DOOR_H - 0.06, 0.08), Vector3.ZERO)
		_:
			_box_collider(body, Vector3(GameActions.CELL, GameActions.WALL_H, 0.3), Vector3(0, 1.5, 0))
	return panel


func _box_collider(body: StaticBody3D, size: Vector3, at: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	body.add_child(cs)
	return cs


## Swing a door's panel to match its open state (the panel's collision follows it).
func _apply_door(root: Node3D, st: Dictionary) -> void:
	if not root.has_meta("pivot"):
		return
	var pivot: Node3D = root.get_meta("pivot")
	var panel: CollisionShape3D = root.get_meta("panel")
	var ang := -PI * 0.5 if bool(st.get("open", false)) else 0.0
	pivot.rotation.y = ang
	var hinge := Vector3(-StructureModels.DOOR_W, 0.0, 0.0)
	var centre := Vector3(StructureModels.DOOR_W - 0.02, StructureModels.DOOR_H * 0.5 - 0.03, 0.0)
	panel.transform = Transform3D(Basis(Vector3.UP, ang), hinge + Basis(Vector3.UP, ang) * centre)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var night := 1.0 - Game.daylight()
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		if not is_instance_valid(n) or not n.has_meta("phase"):
			continue
		var ph: float = n.get_meta("phase")
		var flicker := 0.8 + 0.12 * sin(t * 11.0 + ph) + 0.08 * sin(t * 23.0 + ph * 2.0)
		var light := n.get_node_or_null("Light") as OmniLight3D
		if light:
			light.light_energy = flicker * lerpf(0.8, 2.2, night)
		var flame := n.get_node_or_null("Flame") as Node3D
		if flame:
			flame.scale = Vector3(1.0 + 0.08 * sin(t * 9.0 + ph), flicker * 1.1, 1.0 + 0.08 * cos(t * 7.0 + ph))
			flame.rotation.y = t * 0.8 + ph
