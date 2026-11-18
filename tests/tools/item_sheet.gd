extends SceneTree
## Item sheet (diagnostic): godot --headless --path . -s tests/tools/item_sheet.gd (under xvfb-run, it needs a real
## render). Stands each item's model upright on a plain stage in three-quarter view, in a row, to compare shapes.
## Environment: IDS=hatchet_t1,pickaxe_t1,... (default: the five hatchets), OUT=file.png, ZOOM=1 for a close view of the head

var _main: Node
var _f := 0
var _started := false
var _wait := 0
var _built := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if not _started:
		if _f == 5:
			_main.create_world("Item Sheet", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
		return false
	if not _built:
		_build()
		_built = true
		return false
	_wait += 1
	if _wait < 6:
		return false
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/item_sheet.png"
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	return true


func _build() -> void:
	_main.visible = false
	_main._hud.hide()
	var ids_env := OS.get_environment("IDS")
	var ids: Array = ids_env.split(",", false) if ids_env != "" else ["hatchet_t1", "hatchet_t2", "hatchet_t3", "hatchet_t4", "hatchet_t5", "pickaxe_t1", "pickaxe_t2", "pickaxe_t3", "pickaxe_t4", "pickaxe_t5"]
	var IM = load("res://scripts/items/item_models.gd")
	var art = load("res://scripts/world/art_style.gd")
	var mat: Material = art.painted({"brush_strength": 0.16, "rim_amount": 0.3})
	var stage := Node3D.new()
	root.add_child(stage)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.9, 0.9, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.85)
	env.ambient_light_energy = 0.9
	world_env.environment = env
	stage.add_child(world_env)
	root.get_viewport().world_3d.environment = env
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.5, 0.0)
	light.light_energy = 1.2
	stage.add_child(light)
	var spacing := 0.7
	var x0 := -(ids.size() - 1) * spacing * 0.5
	for i in ids.size():
		var mi := MeshInstance3D.new()
		mi.mesh = IM.mesh_for(ids[i], mat)
		mi.position = Vector3(x0 + i * spacing, 0.0, 0.0)
		mi.rotation = Vector3(0.0, PI * 0.25, 0.0)
		stage.add_child(mi)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0.0, 0.42, 2.6)
	cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
	cam.fov = 40.0
	if OS.get_environment("ZOOM") != "":   # ZOOM=1: close on the head
		cam.position = Vector3(0.0, 0.36, 1.0)
		cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
		cam.fov = 24.0
	cam.make_current()
