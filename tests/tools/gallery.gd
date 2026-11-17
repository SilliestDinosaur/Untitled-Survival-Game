extends SceneTree
## Model gallery: renders tools and flora/ore models in a row, for judging their look.
## Environment variables:
##   OUT=/path/a.png   where to save (default /tmp/gallery.png)
##   ITEMS=hatchet_t1,pickaxe_t2  tool ids to show (default: a set of tools)
##   KEYS=willow_0,palm_0         flora mesh keys to show (default: a set)
##   KEYS_ONLY=1       print the flora mesh keys and exit

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
			_main.create_world("Gallery", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
			_build()
		return false
	if _f >= 30:
		var out := OS.get_environment("OUT")
		root.get_viewport().get_texture().get_image().save_png(out if out != "" else "/tmp/gallery.png")
		print("saved ", out)
		return true
	return false


func _build() -> void:
	var game = root.get_node("Game")
	if OS.get_environment("KEYS_ONLY") != "":
		var names: Array = game.flora.meshes.keys()
		names.sort()
		print("FLORA KEYS ", names)
		quit()
		return
	_main.player.set_physics_process(false)
	_main._hud.hide()
	var gal := Node3D.new()
	gal.position = Vector3(300, 300, 300)
	root.add_child(gal)
	var art = load("res://scripts/world/art_style.gd")
	var items_script = load("res://scripts/items/item_models.gd")
	var mat: Material = art.painted({"brush_strength": 0.1, "rim_amount": 0.3})
	var items := OS.get_environment("ITEMS").split(",") if OS.get_environment("ITEMS") != "" else PackedStringArray(["hatchet_t1", "hatchet_t3", "pickaxe_t2", "pickaxe_t4", "spear_t2", "knife_t2"])
	for i in items.size():
		var mi := MeshInstance3D.new()
		mi.mesh = items_script.mesh_for(items[i], mat)
		mi.position = Vector3(i * 1.1 - (items.size() - 1) * 0.55, 1.2, 0.0)
		mi.scale = Vector3.ONE * 2.2
		gal.add_child(mi)
	var keys := OS.get_environment("KEYS").split(",") if OS.get_environment("KEYS") != "" else PackedStringArray(["willow_0", "palm_0", "ore_t2_0", "ore_t3_0", "gem_t4_0"])
	for i in keys.size():
		if not game.flora.meshes.has(keys[i]):
			print("MISSING ", keys[i])
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = game.flora.meshes[keys[i]]
		mi.position = Vector3(i * 4.5 - (keys.size() - 1) * 2.25, 0.0, -9.0)
		gal.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 60.0
	var dist := float(OS.get_environment("CAM_Z")) if OS.get_environment("CAM_Z") != "" else 26.0
	cam.position = Vector3(0, dist * 0.25, dist)
	gal.add_child(cam)
	cam.current = true
	# look_at takes a world point: aim at the row, in the gallery's own space.
	cam.look_at(gal.to_global(Vector3(0, 1.4, -2.0)), Vector3.UP)
