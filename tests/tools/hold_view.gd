extends SceneTree
## First-person held items (diagnostic): godot --headless --path . -s tests/tools/hold_view.gd (under xvfb-run,
## it needs a real render). Holds each item in the player's viewmodel and saves a crop of the hand's area.
## Environment: IDS=hatchet_t1,pickaxe_t1 (default: one of each tool and a placeable), OUT=dir (default /tmp)

var _main: Node
var _f := 0
var _started := false
var _ids: Array = []
var _i := 0
var _wait := 0
var _out := "/tmp"


func _initialize() -> void:
	var ids_env := OS.get_environment("IDS")
	_ids = ids_env.split(",", false) if ids_env != "" else ["hatchet_t1", "pickaxe_t1", "knife_t1", "spear_t1", "torch", "rock", "campfire"]
	_out = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if not _started:
		if _f == 5:
			_main.create_world("Hold View", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_main._hud.hide()
			_main.get_node("Player").set_physics_process(false)
			_main.get_node("Player").set_process_input(false)
		return false
	if _i >= _ids.size():
		return true
	var vm = _main.get_node("Player").viewmodel
	if _wait == 0:
		vm.hold(_ids[_i])
	_wait += 1
	if _wait < 6:
		return false
	var img: Image = root.get_viewport().get_texture().get_image()
	var size := img.get_size()
	var crop := img.get_region(Rect2i(int(size.x * 0.45), int(size.y * 0.35), int(size.x * 0.55), int(size.y * 0.65)))
	crop.save_png("%s/held_%s.png" % [_out, _ids[_i]])
	print("saved held_%s.png" % _ids[_i])
	_i += 1
	_wait = 0
	return false
