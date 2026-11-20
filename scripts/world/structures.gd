extends Node3D
## Shows placed structures (Game.structures): campfires with flickering firelight, workbenches,
## forges with glowing coals. Pure view of shared data, re-synced when it changes.

var _nodes := {}   # structure id -> Node3D
var _lit := {}     # structure id -> [node, light, flame, fire fx] for the ones with a light (animated each frame)
## Fires' embers and smoke: where (over the fuel), how big, and where the smoke comes out relative to that.
const FIRE_FX := {
	"campfire": [Vector3(0, 0.2, 0), 1.0, Vector3(0, 0.8, 0)],
	"forge": [Vector3(0, 0.98, -0.05), 0.8, Vector3(0, 1.8, 0.15)],   # coals; smoke out of the chimney
	"brazier": [Vector3(0, 0.78, 0), 0.7, Vector3(0, 0.35, 0)],
	"standing_torch": [Vector3(0, 1.55, 0), 0.4, Vector3(0, 0.25, 0)],
}
const FIRE_FX_RANGE := 55.0
var _corners := {}  # wall corners -> the wall pieces ending there (StructureModels.corner_index), for butt joints
var _mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _flame_mesh: ArrayMesh
var _blueprint_mat: ShaderMaterial   ## see-through blue above a piece's build line (shaders/blueprint.gdshader)
var _build_mat: ShaderMaterial       ## the painted look below it (shaders/painted_build.gdshader)
var _finishing := {}                 ## ids whose blueprint was just finished: they get a puff when rebuilt solid

## Dust from hammering, by material.
const DUST := Effects.MAT_DUST


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
	_blueprint_mat = ShaderMaterial.new()
	_blueprint_mat.shader = preload("res://shaders/blueprint.gdshader")
	_build_mat = ArtStyle.material(preload("res://shaders/painted_build.gdshader"), {"brush_strength": 0.22, "rim_amount": 0.3})
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
			if not GameActions.is_blueprint(st):
				_finishing[id] = true
			_free_node(id)   # a blueprint just finished: rebuild it solid
		if not _nodes.has(id) or not is_instance_valid(_nodes[id]):
			_nodes[id] = _make(st)
			var light := _nodes[id].get_node_or_null("Light") as OmniLight3D
			if light:
				_lit[id] = [_nodes[id], light, _nodes[id].get_node_or_null("Flame") as Node3D, _nodes[id].get_node_or_null("FireFx")]
			if _finishing.has(id):
				_finishing.erase(id)
				_finished_fx(_nodes[id], st)
		else:
			_apply_door(_nodes[id], Game.structures[id])
			_apply_ends(_nodes[id], Game.structures[id])
			_apply_build(_nodes[id], st)


## Where a blueprint's build line is (in the piece's own height) for how much of it is built.
static func _cut_for(mesh: Mesh, built: float) -> float:
	var box := mesh.get_aabb() if mesh else AABB(Vector3.ZERO, Vector3.ONE)
	return box.position.y - 0.01 + (box.size.y + 0.02) * clampf(built, 0.0, 1.0)


func _set_cut(root: Node3D, cut: float) -> void:
	if not is_instance_valid(root):
		return
	root.set_meta("cut", cut)
	for n in ["Body", "Ghost"]:
		var mi := root.get_node_or_null(n) as GeometryInstance3D
		if mi:
			mi.set_instance_shader_parameter("build_cut", cut)


## A hammer hit on a blueprint: the build line rises to the new share (quickly, not in a jump), with a puff of dust
## in the piece's material along the line.
func _apply_build(root: Node3D, st: Dictionary) -> void:
	if not bool(root.get_meta("blueprint", false)):
		return
	var body := root.get_node_or_null("Body") as MeshInstance3D
	if not body:
		return
	var target := _cut_for(body.mesh, float(st.get("built", 0.0)))
	var now: float = root.get_meta("cut", target)
	if is_equal_approx(now, target):
		return
	root.set_meta("cut", target)
	# Bound to the piece: when the last hit finishes it, it's rebuilt solid, and the old one's rise stops with it.
	var tw := root.create_tween()
	tw.tween_method(func(c: float) -> void: _set_cut(root, c), now, target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var mat := GameActions.piece_mat(st.kind)
	var at := root.to_global(Vector3(0, target, 0))
	var col: Color = DUST.get(mat, Color(0.7, 0.6, 0.5))
	Effects.chips(self, at, col, 8, 0.05, 2.2)
	Effects.dust(self, at, col.lightened(0.15), 4, 0.4)


## A blueprint finished: a bigger puff all round, and the piece settles in with a little bounce.
func _finished_fx(root: Node3D, st: Dictionary) -> void:
	var mat := GameActions.piece_mat(st.kind)
	var body := root.get_node_or_null("Body") as MeshInstance3D
	var h := body.mesh.get_aabb().size.y if body and body.mesh else 1.0
	var col: Color = DUST.get(mat, Color(0.7, 0.6, 0.5))
	Effects.chips(self, root.to_global(Vector3(0, h * 0.5, 0)), col, 14, 0.07, 3.0)
	Effects.dust(self, root.to_global(Vector3(0, 0.2, 0)), col.lightened(0.15), 10, 0.8, 0.7)
	Audio.play_3d("thud", root.global_position, -4.0, 0.8)
	Game.impact.emit(root.global_position, 0.35)
	root.scale = Vector3(1.0, 0.94, 1.0)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
		var ghost := root.get_node_or_null("Ghost") as MeshInstance3D
		if ghost:
			ghost.mesh = body.mesh


func _free_node(id: String) -> void:
	if is_instance_valid(_nodes[id]):
		_nodes[id].queue_free()
	_nodes.erase(id)
	_lit.erase(id)


func _make(st: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pos: Array = st.pos
	root.position = Vector3(pos[0], pos[1], pos[2])
	# Things standing on a floor stand on its top (older saves put them on its collider, a little lower).
	if not GameActions.is_building(st.kind) or GameActions.is_decor(st.kind):
		var under := GameActions.floor_under(root.position)
		if not under.is_empty():
			root.position.y = float(under.pos[1]) + GameActions.FLOOR_TOP
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
		# The real piece up to the build line, and the plan's blue above it (the same mesh twice).
		mi.material_override = _build_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ghost := MeshInstance3D.new()
		ghost.name = "Ghost"
		ghost.mesh = model.body
		ghost.material_override = _blueprint_mat
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ghost)
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
	var deco: Dictionary = GameActions.DECOR.get(st.kind, {})
	if st.kind in ["campfire", "forge"] or (deco.has("light") and not blueprint):
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position = model.light
		light.light_color = deco.get("light", Color(1.0, 0.62, 0.3))
		light.omni_range = float(deco.get("range", 9.0 if st.kind == "campfire" else 6.0))
		light.omni_attenuation = 1.4
		light.shadow_enabled = st.kind == "campfire" and Settings.shadow_quality in ["High", "Ultra"]
		# Lights of furniture fade out a way off: a village of them mustn't all be lit at once.
		if not deco.is_empty():
			light.distance_fade_enabled = true
			light.distance_fade_begin = 45.0
			light.distance_fade_length = 12.0
		root.add_child(light)
	if st.kind == "campfire" or (st.kind in ["brazier", "standing_torch"] and not blueprint):
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		flame.mesh = _flame_mesh
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if st.kind == "standing_torch":
			flame.position = Vector3(0, 1.48, 0)
			flame.set_meta("size", 0.45)
		elif st.kind == "brazier":
			flame.position = Vector3(0, 0.72, 0)
			flame.set_meta("size", 0.85)
		root.add_child(flame)
	# Embers and smoke off the fires (switched off when far away: see _process).
	if not blueprint and st.kind in FIRE_FX:
		var fx: Array = FIRE_FX[st.kind]
		var fire := Effects.fire(fx[1], fx[2])
		fire.position = fx[0]
		root.add_child(fire)
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
	if blueprint:
		_set_cut(root, _cut_for(model.body, float(st.get("built", 0.0))))
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
			# Its top is the floor's drawn walking surface (it was 9 cm under it: feet and placed things sank in).
			_box_collider(body, Vector3(GameActions.CELL, 0.5, GameActions.CELL), Vector3(0, GameActions.FLOOR_TOP - 0.25, 0))
		"roof":
			_box_collider(body, Vector3(GameActions.CELL, 0.3, GameActions.CELL), Vector3.ZERO)
		"half":
			_box_collider(body, Vector3(GameActions.CELL, 1.0, 0.3), Vector3(0, 0.5, 0))
		"fence":
			_box_collider(body, Vector3(GameActions.CELL, 1.1, 0.2), Vector3(0, 0.55, 0))
		"decor":
			var size: Vector3 = GameActions.DECOR[kind].box
			if size != Vector3.ZERO:
				_box_collider(body, size, Vector3(0, size.y * 0.5, 0))
			else:   # a rug: something to aim at (to take it up), nothing to bump into
				body.collision_layer = TerrainChunk.LAYER_INTERACT
				_box_collider(body, Vector3(1.6, 0.04, 1.0), Vector3(0, 0.02, 0))
		"arch":
			# Two sides and the crown over the arch: walkable through the opening (its top is round; the crown's
			# box starts where the opening is still wide enough to walk under).
			var side_w := h - StructureModels.ARCH_R
			for s in [-1.0, 1.0]:
				_box_collider(body, Vector3(side_w, GameActions.WALL_H, 0.3), Vector3(s * (StructureModels.ARCH_R + side_w * 0.5), GameActions.WALL_H * 0.5, 0))
			var crown := StructureModels.ARCH_SPRING + StructureModels.ARCH_R * 0.75
			_box_collider(body, Vector3(StructureModels.ARCH_R * 2.0, GameActions.WALL_H - crown, 0.3), Vector3(0, (crown + GameActions.WALL_H) * 0.5, 0))
		"stairs":
			var rise := GameActions.STACK_H / GameActions.STAIR_STEPS
			var run := GameActions.CELL / GameActions.STAIR_STEPS
			for i in GameActions.STAIR_STEPS:
				var top := GameActions.FLOOR_TOP + (i + 1) * rise
				var zc := h - (i + 0.5) * run
				_box_collider(body, Vector3(GameActions.CELL - 0.04, top, run + 0.02), Vector3(0, top * 0.5, zc))
		"doorway", "door":
			# Two posts and a lintel: walkable through the opening.
			var wh := GameActions.WALL_H
			_box_collider(body, Vector3(0.8, wh, 0.3), Vector3(-1.1, wh * 0.5, 0))
			_box_collider(body, Vector3(0.8, wh, 0.3), Vector3(1.1, wh * 0.5, 0))
			_box_collider(body, Vector3(1.4, wh - 2.3, 0.3), Vector3(0, (wh + 2.3) * 0.5, 0))
			if shape == "door":
				panel = _box_collider(body, Vector3(StructureModels.DOOR_W * 2.0 - 0.04, StructureModels.DOOR_H - 0.06, 0.08), Vector3.ZERO)
		_:
			_box_collider(body, Vector3(GameActions.CELL, GameActions.WALL_H, 0.3), Vector3(0, GameActions.WALL_H * 0.5, 0))
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
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	# Only the lit things (fires and lamps), not every wall and floor of a base.
	for id: String in _lit:
		var e: Array = _lit[id]
		var n: Node3D = e[0]
		if not is_instance_valid(n):
			continue
		var ph: float = n.get_meta("phase")
		var flicker := 0.8 + 0.12 * sin(t * 11.0 + ph) + 0.08 * sin(t * 23.0 + ph * 2.0)
		var light := e[1] as OmniLight3D
		if is_instance_valid(light):
			light.light_energy = flicker * lerpf(0.8, 2.2, night)
		var flame := e[2] as Node3D
		if is_instance_valid(flame):
			var fs: float = flame.get_meta("size", 1.0)
			flame.scale = Vector3(1.0 + 0.08 * sin(t * 9.0 + ph), flicker * 1.1, 1.0 + 0.08 * cos(t * 7.0 + ph)) * fs
			flame.rotation.y = t * 0.8 + ph
		var fire: Node = e[3]
		if fire and is_instance_valid(fire):
			Effects.set_fire_on(fire, n.global_position.distance_squared_to(eye) < FIRE_FX_RANGE * FIRE_FX_RANGE)
