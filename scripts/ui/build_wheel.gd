class_name BuildWheel
extends Control
## The Building Plan's wheel: hold the building-wheel button (right mouse by default) while holding the plan. The
## outer ring picks the shape, the inner ring picks the material, and the middle shows the piece turning in that
## material. Moving the mouse steers a pointer from the middle (the view doesn't turn while the wheel is up);
## hovering a ring sets its pick, and letting go of the button keeps the picks.

const R_PREVIEW := 92.0      ## the preview's radius
const R_MAT := Vector2(104.0, 150.0)     ## inner ring (materials)
const R_SHAPE := Vector2(166.0, 268.0)   ## outer ring (shapes)
const SHAPE_NAMES := {"floor": "Floor", "wall": "Wall", "half": "Half wall", "window": "Window", "doorway": "Doorway",
	"door": "Door", "stairs": "Stairs", "roof": "Roof", "fence": "Fence", "arch": "Archway", "shutters": "Shutters"}
const MAT_NAMES := {"wood": "Wood", "stone": "Stone", "brick": "Brick"}
const MAT_COLORS := {"wood": Color(0.62, 0.45, 0.29), "stone": Color(0.55, 0.56, 0.6), "brick": Color(0.72, 0.4, 0.3)}

var player: Node   ## the local player (set by the HUD)
var _pointer := Vector2.ZERO
var _shape := "wall"
var _mat := "wood"
var _icons: Array[ItemIcon] = []
var _caption: Label
var _viewport: SubViewport
var _preview: MeshInstance3D
var _preview_kind := ""
var _preview_mat: Material


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for i in GameActions.SHAPES.size():
		var icon := ItemIcon.new("", 46.0)
		add_child(icon)
		_icons.append(icon)
	_caption = UITheme.label("", 20, UITheme.TEXT, 4)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_caption)
	_build_preview()


## A little stage of its own (its own world, so the game's lights and fog don't reach it) with the piece on it.
func _build_preview() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.name = "Preview"
	add_child(box)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(roundi(R_PREVIEW * 2.0), roundi(R_PREVIEW * 2.0))
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.74)   # a cool sky fill, so the sunlit side reads warmer
	env.environment.ambient_light_energy = 0.4
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.0
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.4, 6.2)
	cam.fov = 42.0
	_viewport.add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	_preview = MeshInstance3D.new()
	_viewport.add_child(_preview)
	_preview_mat = ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.3})


func _process(delta: float) -> void:
	var want: bool = player != null and player.active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and ItemDB.tool_stats(player.inventory.selected_item()).get("type", "") == "plan" \
		and Input.is_action_pressed("build_menu")
	if want and not visible:
		_open()
	elif visible and not want:
		_close()
	if not visible:
		return
	_preview.rotation.y += delta * 0.8
	_layout()
	queue_redraw()


func _open() -> void:
	_shape = String(player.build_choice.shape)
	_mat = String(player.build_choice.mat)
	_pointer = Vector2.ZERO
	visible = true
	player.wheel_open = true
	_refresh()


func _close() -> void:
	visible = false
	if player:
		player.build_choice = {"shape": _shape, "mat": _mat}
		player.wheel_open = false


## The mouse steers the pointer instead of the view while the wheel is up.
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventMouseMotion:
		return
	_pointer += (event as InputEventMouseMotion).relative
	_pointer = _pointer.limit_length(R_SHAPE.y)
	var d := _pointer.length()
	if d >= R_MAT.x and d <= R_MAT.y:
		var m: String = GameActions.MATERIALS[_segment(_pointer, GameActions.MATERIALS.size())]
		if m != _mat:
			_mat = m
			_refresh()
	elif d >= R_SHAPE.x:
		var sh: String = GameActions.SHAPES[_segment(_pointer, GameActions.SHAPES.size())]
		if sh != _shape:
			_shape = sh
			_refresh()
	get_viewport().set_input_as_handled()


## Which of n equal segments (starting at the top, going clockwise) a direction falls in.
static func _segment(v: Vector2, n: int) -> int:
	var a := fposmod(atan2(v.x, -v.y), TAU)
	return int(floor(a / TAU * n + 0.5)) % n


static func _dir(i: int, n: int) -> Vector2:
	var a := TAU * i / n
	return Vector2(sin(a), -cos(a))


## The icons follow the chosen material; the preview and caption follow both picks.
func _refresh() -> void:
	for i in GameActions.SHAPES.size():
		_icons[i].item = GameActions.piece_kind(GameActions.SHAPES[i], _mat)
	var kind := GameActions.piece_kind(_shape, _mat)
	if kind != _preview_kind:
		_preview_kind = kind
		_preview.mesh = StructureModels.get_model(kind, _preview_mat, _preview_mat).body
		# Floors and roofs are low and wide, stairs climb a full storey: centre each on the stage.
		var aabb: AABB = _preview.mesh.get_aabb()
		_preview.position = Vector3(0.0, 1.2 - (aabb.position.y + aabb.size.y * 0.5), 0.0)
	var cost := GameActions.PIECE_COSTS.get(kind, {}) as Dictionary
	var parts: Array[String] = []
	for item: String in cost:
		parts.append("%d %s" % [int(cost[item]), ItemDB.display_name(item)])
	_caption.text = "%s  ·  %s" % [ItemDB.display_name(kind), ", ".join(parts)]


func _layout() -> void:
	var c := size * 0.5
	for i in _icons.size():
		var at := c + _dir(i, _icons.size()) * (R_SHAPE.x + R_SHAPE.y) * 0.5 - Vector2(0, 10)
		_icons[i].position = at - _icons[i].size * 0.5
	var box := get_node("Preview") as Control
	box.position = c - Vector2(R_PREVIEW, R_PREVIEW)
	box.size = Vector2(R_PREVIEW, R_PREVIEW) * 2.0
	_caption.position = Vector2(c.x - 300.0, c.y + R_SHAPE.y + 16.0)
	_caption.size = Vector2(600.0, 30.0)


func _draw() -> void:
	var c := size * 0.5
	var font: Font = UITheme.BOLD_FONT
	draw_circle(c, R_SHAPE.y + 6.0, Color(0.1, 0.08, 0.06, 0.55))
	# Outer ring: shapes.
	var n := GameActions.SHAPES.size()
	for i in n:
		var sh: String = GameActions.SHAPES[i]
		var col := Color(0.95, 0.91, 0.82, 0.16)
		if sh == _shape:
			col = Color(UITheme.ACCENT, 0.75)
		_ring_segment(c, R_SHAPE, i, n, col)
		var at := c + _dir(i, n) * (R_SHAPE.x + R_SHAPE.y) * 0.5 + Vector2(0, 32)
		var label: String = SHAPE_NAMES[sh]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, at - Vector2(w * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT)
	# Inner ring: materials, each in its own colour.
	var m := GameActions.MATERIALS.size()
	for i in m:
		var mat: String = GameActions.MATERIALS[i]
		var col: Color = MAT_COLORS[mat]
		col.a = 0.95 if mat == _mat else 0.45
		_ring_segment(c, R_MAT, i, m, col)
		var at := c + _dir(i, m) * (R_MAT.x + R_MAT.y) * 0.5 + Vector2(0, 6)
		var label: String = MAT_NAMES[mat]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, at - Vector2(w * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			UITheme.TEXT if mat == _mat else UITheme.TEXT_DIM)
	draw_circle(c, R_PREVIEW + 4.0, Color(0.1, 0.08, 0.06, 0.6))
	# The pointer.
	draw_circle(c + _pointer, 5.0, UITheme.TEXT)


## One segment of a ring, as a filled polygon, with a small gap either side.
func _ring_segment(c: Vector2, radii: Vector2, i: int, n: int, col: Color) -> void:
	var half := PI / n
	var a0 := TAU * i / n - half + 0.02
	var a1 := TAU * i / n + half - 0.02
	var pts := PackedVector2Array()
	var steps := 12
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		pts.append(c + Vector2(sin(a), -cos(a)) * radii.y)
	for k in steps + 1:
		var a := lerpf(a1, a0, float(k) / steps)
		pts.append(c + Vector2(sin(a), -cos(a)) * radii.x)
	draw_colored_polygon(pts, col)
