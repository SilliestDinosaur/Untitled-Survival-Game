extends SceneTree
## Model gallery: renders tools and flora/ore models in a row, for judging their look.
## Environment variables:
##   OUT=/path/a.png   where to save (default /tmp/gallery.png)
##   ITEMS=hatchet_t1,pickaxe_t2  tool ids to show (default: a set of tools)
##   KEYS=willow_0,palm_0         flora mesh keys to show (default: a set)
##   KEYS_ONLY=1       print the flora mesh keys and exit
##   ROT_Y=90          turn the tools about the vertical axis (degrees), e.g. 90 for a side view
##   CAM_Z=4.2         camera distance (default 26; items are small at that range)
##   COLS=2 SPACING=0.9 SCALE=2.2   grid layout for close-ups (default: one row of SCALE 2.2, 1.1 apart)
##   FOCUS=1.4         aim the camera at this height (for close-ups of a tall head)

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
		var names: Array = game.flora.mesh_keys()
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
	# Layout: one row by default; COLS=2 makes a grid (for close-ups), SPACING and SCALE set the gaps and size.
	var grid := OS.get_environment("COLS") != ""
	var cols := int(OS.get_environment("COLS")) if grid else items.size()
	var spacing := float(OS.get_environment("SPACING")) if OS.get_environment("SPACING") != "" else 1.1
	var item_scale := float(OS.get_environment("SCALE")) if OS.get_environment("SCALE") != "" else 2.2
	var rows := ceili(float(items.size()) / cols)
	for i in items.size():
		var mi := MeshInstance3D.new()
		mi.mesh = items_script.mesh_for(items[i], mat)
		var col := i % cols
		var row := i / cols
		mi.position = Vector3((col - (mini(cols, items.size()) - 1) * 0.5) * spacing, 1.2 + (rows - 1) * spacing * 0.5 - row * spacing, 0.0)
		mi.scale = Vector3.ONE * item_scale
		mi.rotation.y = deg_to_rad(float(OS.get_environment("ROT_Y")) if OS.get_environment("ROT_Y") != "" else 0.0)
		gal.add_child(mi)
	var keys := OS.get_environment("KEYS").split(",") if OS.get_environment("KEYS") != "" else PackedStringArray(["willow_0", "palm_0", "ore_t2_0", "ore_t3_0", "gem_t4_0"])
	for i in keys.size():
		if not game.flora.has_mesh(keys[i]):
			print("MISSING ", keys[i])
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = game.flora.mesh(keys[i])
		mi.position = Vector3(i * 4.5 - (keys.size() - 1) * 2.25, 0.0, -9.0)
		gal.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 60.0
	var dist := float(OS.get_environment("CAM_Z")) if OS.get_environment("CAM_Z") != "" else 26.0
	# FOCUS=y aims the camera at height y (for a close-up of a tall head); by default it looks slightly down at the row.
	var focus := float(OS.get_environment("FOCUS")) if OS.get_environment("FOCUS") != "" else -1.0
	cam.position = Vector3(0, focus if focus >= 0.0 else dist * 0.25, dist)
	gal.add_child(cam)
	cam.current = true
	# look_at takes a world point: aim at the row, in the gallery's own space.
	var look := Vector3(0, focus, 0.0) if focus >= 0.0 else (Vector3(0, 1.2, 0.0) if grid else Vector3(0, 1.4, -2.0))
	cam.look_at(gal.to_global(look), Vector3.UP)
