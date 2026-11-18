extends SceneTree
## Building piece gallery: renders placed pieces and stations in a row (or grid), for judging their look.
## godot ... -s tests/tools/piece_gallery.gd (run under xvfb-run, it needs a real render).
## Environment variables:
##   OUT=/path/a.png        where to save (default /tmp/pieces.png)
##   PIECES=foundation,wall  kinds to show (default: every building piece, grouped by shape)
##   COLS=3 SPACING=3.4 SCALE=1.0   grid layout (default: one row)
##   CAM_Z=12 FOCUS=1.5 CAM_Y=4   camera distance, look-at height (default: middle of the grid), and camera height
##   OPEN=1                 swing the doors open (the panels hang from their hinges)

var _main: Node
var _f := 0
var _started := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if not _started:
		if _f == 5:
			_main.create_world("Pieces", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
			_build()
		return false
	if _f >= 30:
		var out := OS.get_environment("OUT")
		root.get_viewport().get_texture().get_image().save_png(out if out != "" else "/tmp/pieces.png")
		print("saved ", out)
		return true
	return false


## Every building piece, grouped by shape and material (wood, brick, stone), so they read as a set.
func _all_kinds() -> Array:
	var gal_script = load("res://scripts/core/game_actions.gd")
	var out: Array = []
	for shape in ["floor", "wall", "half", "window", "doorway", "door", "stairs", "roof"]:
		for mat in ["brick", "wood", "stone"]:
			for id: String in gal_script.PIECES:
				if gal_script.PIECES[id].shape == shape and gal_script.PIECES[id].mat == mat:
					out.append(id)
	return out


func _build() -> void:
	_main.player.set_physics_process(false)
	_main._hud.hide()
	var sm = load("res://scripts/world/structure_models.gd")
	var art = load("res://scripts/world/art_style.gd")
	var mat: Material = art.painted({"brush_strength": 0.22, "rim_amount": 0.3})
	var glow: Material = StandardMaterial3D.new()
	var kinds_env := OS.get_environment("PIECES")
	var kinds: PackedStringArray = kinds_env.split(",") if kinds_env != "" else PackedStringArray(_all_kinds())
	var gal := Node3D.new()
	gal.position = Vector3(300, 300, 300)
	root.add_child(gal)
	var grid := OS.get_environment("COLS") != ""
	var cols := int(OS.get_environment("COLS")) if grid else kinds.size()
	var spacing := float(OS.get_environment("SPACING")) if OS.get_environment("SPACING") != "" else 3.6
	var item_scale := float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 1.0
	var rows := ceili(float(kinds.size()) / cols)
	for i in kinds.size():
		var col := i % cols
		var row := i / cols
		var mi := MeshInstance3D.new()
		mi.mesh = sm.get_model(kinds[i], mat, glow).body
		mi.position = Vector3((col - (mini(cols, kinds.size()) - 1) * 0.5) * spacing, (rows - 1 - row) * spacing, 0.0)
		mi.scale = Vector3.ONE * item_scale
		gal.add_child(mi)
		var parts = sm.get_model(kinds[i], mat, glow)
		if parts.door != null:   # a door's panel hangs from its hinge; OPEN=1 swings it open
			var hinge := Node3D.new()
			hinge.position = mi.position + Vector3(-0.7 * item_scale, 0.0, 0.0)
			hinge.rotation.y = -PI * 0.5 if OS.get_environment("OPEN") != "" else 0.0
			var panel := MeshInstance3D.new()
			panel.mesh = parts.door
			panel.scale = Vector3.ONE * item_scale
			hinge.add_child(panel)
			gal.add_child(hinge)
		var label := Label3D.new()
		label.text = kinds[i]
		label.font_size = 48
		label.position = mi.position + Vector3(0, -0.6, 1.0)
		gal.add_child(label)
	var dist := float(OS.get_environment("CAM_Z")) if OS.get_environment("CAM_Z") != "" else 12.0
	# Look at the middle of the grid unless FOCUS says otherwise; CAM_Y lifts the camera (to see decks from above).
	var focus := float(OS.get_environment("FOCUS")) if OS.get_environment("FOCUS") != "" else (rows - 1) * spacing * 0.5 + 1.0
	var cam_y := float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else focus
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(0, cam_y, dist)
	gal.add_child(cam)
	cam.current = true
	cam.look_at(gal.to_global(Vector3(0, focus, 0)), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0.0)
	light.light_energy = 1.1
	gal.add_child(light)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.82, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	gal.add_child(world_env)
