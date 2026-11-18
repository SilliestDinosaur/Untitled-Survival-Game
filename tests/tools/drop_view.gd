extends SceneTree
## Dropped items (diagnostic): godot --headless --path . -s tests/tools/drop_view.gd (under xvfb-run, it needs a
## real render). Builds each item as a dropped pickup (the game's own code) on a plain stage, in a row, beside a
## 1 m reference cube, and saves the view.
## Environment: IDS=hatchet_t1,wood,... (default: tools, materials and food), OUT=file.png

var _f := 0
var _done := false
var _wait := 0
var _main: Node
var _started := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if not _started:
		if _f == 5:
			_main.create_world("Drop View", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
		return false
	if _f < 3:
		return false
	if _done:
		_wait += 1
		if _wait < 8:
			return false
		var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/drop_view.png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	_main.visible = false
	_main._hud.hide()
	_build_stage()
	_done = true
	return false


func _build_stage() -> void:
	var ids_env := OS.get_environment("IDS")
	var ids: Array = ids_env.split(",", false) if ids_env != "" else ["hatchet_t1", "pickaxe_t1", "spear_t1", "knife_t1", "torch", "rock", "wood", "berries", "stone", "raw_meat", "ore_t2", "plank", "bone", "campfire"]
	var stage := Node3D.new()
	root.add_child(stage)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.85, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 0.9
	world_env.environment = env
	stage.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0.0)
	light.light_energy = 1.1
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.45, 0.62, 0.35)
	ground.material_override = g_mat
	stage.add_child(ground)
	var reference := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	reference.mesh = cube
	var r_mat := StandardMaterial3D.new()
	r_mat.albedo_color = Color(0.9, 0.2, 0.2)
	reference.material_override = r_mat
	var n := ids.size()
	var per_row := 7
	var spacing := 0.6
	var x0 := -(mini(n, per_row) - 1) * spacing * 0.5
	reference.position = Vector3(x0 - 0.9, 0.5, 0.0)
	stage.add_child(reference)
	var pickups = load("res://scripts/world/pickups.gd").new()
	stage.add_child(pickups)
	for i in n:
		var col := i % per_row
		var row := i / per_row
		pickups._make({"id": "view%d" % i, "item": ids[i], "count": 1, "dur": -1, "pos": [x0 + col * spacing, 0.0, -row * 0.8]})
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0.0, 2.8, 4.6)
	cam.look_at(Vector3(0.0, 0.0, -0.4), Vector3.UP)
	cam.fov = 50.0
	cam.make_current()
