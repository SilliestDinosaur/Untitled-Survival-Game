class_name WorldMap
extends Control
## The map: the whole island, under a veil of fog that lifts where you've been. Shows the cave
## entrances you've found, your bases, your friends, your own marks, where you last fell and where you are.
## Opened with the map key. Click to put a mark down (and name it), right-click a mark to take it away.

const MARK_COLORS := [Color(0.85, 0.55, 0.2), Color(0.3, 0.6, 0.85), Color(0.45, 0.72, 0.35), Color(0.7, 0.42, 0.75), Color(0.85, 0.75, 0.3)]
var _origin := Vector2.ZERO
var _side_px := 1.0
var _naming := -1           ## the mark being named
var _name_edit: LineEdit

const PX := 8.0            ## metres per terrain pixel on the map
const ROWS_PER_FRAME := 24 ## terrain rows built per frame (keeps opening the map smooth)

var _ground: Image
var _ground_tex: ImageTexture
var _fog_tex: ImageTexture
var _ground_row := 0       ## next row to build; equals the map size when done
var _fog_dirty := true
var _fog_timer := 0.0
var player: Node3D   ## set by the main scene: whose position and heading the map shows


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## A new world: the terrain picture is made again the next time the map opens.
func reset_for_world() -> void:
	_ground = null
	_ground_tex = null
	_fog_tex = null
	_ground_row = 0
	_fog_dirty = true


func mark_dirty() -> void:
	_fog_dirty = true


func _process(delta: float) -> void:
	if not visible or not Game.world_gen:
		return
	if _ground_row < _side():
		_build_ground_rows(ROWS_PER_FRAME)
		queue_redraw()
	_fog_timer -= delta
	if _fog_dirty and _fog_timer <= 0.0:
		_fog_timer = 0.5
		_fog_dirty = false
		_build_fog()
		queue_redraw()


func _side() -> int:
	return int(Game.WORLD_SIZE / PX)


func _build_ground_rows(rows: int) -> void:
	var gen: WorldGen = Game.world_gen
	var pal: WorldPalette = Game.palette
	var n := _side()
	if _ground == null:
		_ground = Image.create(n, n, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.45, 1.0, -0.55).normalized()
	var paper := UITheme.PAPER
	var last := mini(_ground_row + rows, n)
	for j in range(_ground_row, last):
		for i in n:
			var x := (i + 0.5) * PX
			var z := (j + 0.5) * PX
			var h := gen.get_base_height(x, z)
			var col: Color
			var river := Rivers.surface_at(gen.rivers, x, z)
			if h < river:
				col = pal.water_shallow.lerp(pal.water_deep, 0.35)
			elif h < Game.SEA_LEVEL:
				col = pal.water_deep.lerp(Color(0.45, 0.66, 0.74), clampf(h / -8.0 + 0.2, 0.0, 1.0))
			elif h < 2.5:
				col = pal.sand
			else:
				col = pal.meadow_grass.lerp(pal.rock_light, clampf((h - 35.0) / 70.0, 0.0, 1.0))
			# Hillshade from the neighbouring heights.
			var gx := (gen.get_base_height(x + PX, z) - gen.get_base_height(x - PX, z)) / (2.0 * PX)
			var gz := (gen.get_base_height(x, z + PX) - gen.get_base_height(x, z - PX)) / (2.0 * PX)
			var nrm := Vector3(-gx, 1.0, -gz).normalized()
			var shade := 0.8 + 0.3 * maxf(0.0, nrm.dot(light))
			col = col * shade
			# A little paper in the colour, so it reads as drawn.
			col = col.lerp(paper, 0.18)
			_ground.set_pixel(i, j, col)
	_ground_row = last
	if _ground_row >= n:
		_ground_tex = ImageTexture.create_from_image(_ground)


## The paper fog over what you haven't seen. Filled in one go, then cleared only where you've been (found with the
## array's own search): pixel by pixel it was 13 ms, every half second while the map was open and you explored.
func _build_fog() -> void:
	var n := Game.explore_size()
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var paper := UITheme.PAPER
	img.fill(Color(paper.r, paper.g, paper.b, 0.93))
	if Game.explored.size() == n * n:
		var data := img.get_data()
		var i := Game.explored.find(1)
		while i >= 0:
			data[i * 4 + 3] = 0
			i = Game.explored.find(1, i + 1)
		img = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	if _fog_tex and _fog_tex.get_size() == Vector2(n, n):
		_fog_tex.update(img)
	else:
		_fog_tex = ImageTexture.create_from_image(img)


## Where a world position lands on the map, given the map's square.
func _to_map(p: Vector3, origin: Vector2, side: float) -> Vector2:
	return origin + Vector2(p.x, p.z) / Game.WORLD_SIZE * side


func _draw() -> void:
	var box := minf(size.x, size.y) * 0.84
	var side := box
	var origin := (size - Vector2(side, side)) * 0.5
	_origin = origin
	_side_px = side
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.72))
	draw_rect(Rect2(origin, Vector2(side, side)).grow(14.0), UITheme.PAPER)
	draw_rect(Rect2(origin, Vector2(side, side)).grow(14.0), UITheme.INK, false, 2.0)
	if _ground_tex:
		draw_texture_rect(_ground_tex, Rect2(origin, Vector2(side, side)), false)
	else:
		draw_string(UITheme.BOLD_FONT, origin + Vector2(side * 0.5 - 60, side * 0.5), "Drawing the island...", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.INK)
	if _fog_tex:
		draw_texture_rect(_fog_tex, Rect2(origin, Vector2(side, side)), false)
	if not Game.world_gen:
		return
	var plan: Dictionary = Game.world_gen.caves
	# Cave entrances you've found.
	for e: Vector3 in plan.get("entrances", []):
		if not Game.is_explored(e):
			continue
		var at := _to_map(e, origin, side)
		draw_circle(at, 7.0, Color(0.1, 0.08, 0.07))
		draw_circle(at, 4.5, Color(0.02, 0.02, 0.02))
		draw_arc(at, 7.0, 0.0, TAU, 20, UITheme.ACCENT, 1.5, true)
		draw_string(UITheme.BOLD_FONT, at + Vector2(9, 4), "Cave", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.INK)
	# Bases: foundations and the like, where you built them.
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if not st.kind in GameActions.FLOOR_KINDS:
			continue
		var pos: Array = st.pos
		var at := _to_map(Vector3(pos[0], 0, pos[2]), origin, side)
		draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), UITheme.INK)
	# Friends.
	if Net.is_online():
		for peer: int in Net.avatars:
			var a = Net.avatars[peer]
			if not a.has_pose:
				continue
			var at := _to_map(a.global_position, origin, side)
			var col: Color = Settings.PLAYER_COLORS[int(Net.players.get(peer, {}).get("color", 0)) % Settings.PLAYER_COLORS.size()]
			draw_circle(at, 6.0, Color(0.12, 0.09, 0.07))
			draw_circle(at, 4.6, col)
			var initial := String(a.display_name).substr(0, 1).to_upper()
			draw_string(UITheme.BOLD_FONT, at + Vector2(7, 4), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.INK)
	# Where you fell, and your marks.
	if player and player.death_pos.size() == 3:
		var at := _to_map(Vector3(player.death_pos[0], 0, player.death_pos[2]), origin, side)
		draw_circle(at, 8.0, Color(0.12, 0.08, 0.07))
		draw_string(UITheme.BOLD_FONT, at + Vector2(-5, 5), "✝", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.4, 0.35))
		draw_string(UITheme.BOLD_FONT, at + Vector2(11, 5), "Where you fell", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.INK)
	if player:
		for i in player.markers.size():
			var m: Dictionary = player.markers[i]
			var at := _to_map(Vector3(m.pos[0], 0, m.pos[1]), origin, side)
			var col: Color = MARK_COLORS[int(m.get("color", 0)) % MARK_COLORS.size()]
			# A pin: a dot on a little stalk.
			draw_line(at, at - Vector2(0, 12), UITheme.INK, 2.0, true)
			draw_circle(at - Vector2(0, 14), 6.0, UITheme.INK)
			draw_circle(at - Vector2(0, 14), 4.6, col)
			if i != _naming:
				draw_string(UITheme.BOLD_FONT, at + Vector2(9, -9), String(m.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.INK)
	# You.
	if player:
		var at := _to_map(player.global_position, origin, side)
		var fwd: Vector3 = -player.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var tip := at + dir * 11.0
		var side_v := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, at - dir * 4.0 + side_v * 5.0, at - dir * 4.0 - side_v * 5.0]), UITheme.ACCENT)
	# North, and how to close.
	draw_string(UITheme.HEADING_FONT, Vector2(size.x * 0.5 - 6, origin.y - 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.INK)
	draw_string(UITheme.BOLD_FONT, Vector2(origin.x, origin.y + side + 40), "Walk around to uncover the island  ·  Click to mark a place, right-click a mark to remove it  ·  M or Esc to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.92, 0.9, 0.84))


## Click: a new mark there, named straight away. Right-click: the mark under the mouse goes.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or player == null:
		return
	var mp: Vector2 = event.position
	var rel := (mp - _origin) / _side_px
	if rel.x < 0.0 or rel.y < 0.0 or rel.x > 1.0 or rel.y > 1.0:
		return
	var world := rel * Game.WORLD_SIZE
	if event.button_index == MOUSE_BUTTON_RIGHT:
		var near := -1
		var best := 14.0
		for i in player.markers.size():
			var at := _to_map(Vector3(player.markers[i].pos[0], 0, player.markers[i].pos[1]), _origin, _side_px) - Vector2(0, 10)
			if at.distance_to(mp) < best:
				best = at.distance_to(mp)
				near = i
		if near >= 0:
			player.markers.remove_at(near)
			_end_naming()
			Audio.play(Audio.sfx.click, -8.0, 0.8)
			queue_redraw()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if player.markers.size() >= player.MAX_MARKERS:
			return
		player.markers.append({"pos": [world.x, world.y], "name": "Mark %d" % (player.markers.size() + 1), "color": player.markers.size() % MARK_COLORS.size()})
		Audio.play(Audio.sfx.click, -8.0, 1.2)
		_start_naming(player.markers.size() - 1, mp)
		accept_event()


func _start_naming(i: int, at: Vector2) -> void:
	_end_naming()
	_naming = i
	_name_edit = LineEdit.new()
	_name_edit.text = String(player.markers[i].name)
	_name_edit.select_all_on_focus = true
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(170, 0)
	_name_edit.position = at + Vector2(10, -32)
	add_child(_name_edit)
	_name_edit.grab_focus()
	_name_edit.select_all()
	_name_edit.text_submitted.connect(func(_t: String) -> void: _end_naming())
	_name_edit.focus_exited.connect(_end_naming)
	queue_redraw()


func _end_naming() -> void:
	if _naming >= 0 and _name_edit and _naming < player.markers.size():
		var t := _name_edit.text.strip_edges()
		player.markers[_naming].name = t if t != "" else "Mark %d" % (_naming + 1)
	_naming = -1
	if _name_edit:
		var e := _name_edit
		_name_edit = null
		e.queue_free()
	queue_redraw()
