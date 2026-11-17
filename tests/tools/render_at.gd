extends SceneTree
## Renders one still from a chosen place in a chosen world, with no boilerplate.
## Environment variables:
##   SEED=12345        world seed (default 629946553)
##   CAM=x,y,z         camera position (default: 6 m in front of the spawn, 2 m up)
##   LOOK=x,y,z        point to look at (default: the spawn)
##   TOD=0.5           time of day, 0..1 (default 0.5 = noon)
##   OUT=/path/a.png   where to save (default: /tmp/render.png)
##   FRAMES=40         frames to wait before saving (default 40)
##   SETUP=res://x.gd  optional script: a class with static func setup(game, main) to place things
## Example:
##   SEED=777 CAM=100,30,100 LOOK=120,20,120 OUT=/tmp/a.png \
##     godot --headless --path . --rendering-driver vulkan -s tests/tools/render_at.gd

var _main: Node
var _f := 0
var _started := false


func _initialize() -> void:
	root.get_node("Settings").view_distance = "Low"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _vec(name: String, fallback: Vector3) -> Vector3:
	var s := OS.get_environment(name)
	if s == "":
		return fallback
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _process(_d: float) -> bool:
	_f += 1
	if not _started:
		if _f == 5:
			var seed_v := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 629946553
			_main.create_world("Render", seed_v)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
			_place()
		return false
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40
	if _f >= frames:
		var out := OS.get_environment("OUT")
		root.get_viewport().get_texture().get_image().save_png(out if out != "" else "/tmp/render.png")
		print("saved ", out)
		return true
	return false


func _place() -> void:
	var g = root.get_node("Game")
	var p = _main.get_node("Player")
	p.set_physics_process(false)
	_main._hud.hide()
	g.time_paused = true
	g.time_of_day = float(OS.get_environment("TOD")) if OS.get_environment("TOD") != "" else 0.5
	var setup_path := OS.get_environment("SETUP")
	if setup_path != "":
		var script: GDScript = load(setup_path)
		script.setup(g, _main)
	var spawn: Vector3 = g.world_gen.find_spawn_point()
	var look := _vec("LOOK", spawn + Vector3(0, 1.5, 0))
	var cam_pos := _vec("CAM", spawn + Vector3(0, 2.0, 6.0))
	cam_pos.y = maxf(cam_pos.y, g.world_gen.get_height(cam_pos.x, cam_pos.z) + 1.7) if OS.get_environment("CAM") == "" else cam_pos.y
	var cam: Camera3D = p.get_node("Head/Camera3D")
	cam.global_position = cam_pos
	cam.look_at(look, Vector3.UP)
