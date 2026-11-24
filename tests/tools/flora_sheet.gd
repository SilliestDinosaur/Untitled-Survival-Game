extends SceneTree
## Flora sheet: every model whose key starts with one of PREFIX (comma list), or the keys in KEYS, laid out in a grid
## sized from the models themselves, on a plain grey stage, seen three-quarter on. For hunting visual bugs.
##   PREFIX=oak_,pine_   KEYS=a,b   COLS=6   OUT=file.png   LOD=1 to include the _lod/_bare keys   ROT=deg turn
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
			_main.create_world("Sheet", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_f = 0
			_build()
		return false
	if _f >= 40:
		var out := OS.get_environment("OUT")
		root.get_viewport().get_texture().get_image().save_png(out if out != "" else "/tmp/flora_sheet.png")
		print("saved ", out)
		return true
	return false


func _build() -> void:
	var game = root.get_node("Game")
	_main.player.set_physics_process(false)
	_main._hud.hide()
	var keys: Array = []
	if OS.get_environment("KEYS") != "":
		keys = Array(OS.get_environment("KEYS").split(","))
	else:
		var all: Array = game.flora.mesh_keys()
		all.sort()
		for k: String in all:
			if OS.get_environment("LOD") == "" and (k.ends_with("_lod") or k.ends_with("_bare")):
				continue
			for p: String in OS.get_environment("PREFIX").split(","):
				if p != "" and k.begins_with(p):
					keys.append(k)
					break
	var gal := Node3D.new()
	gal.position = Vector3(300, 400, 300)
	root.add_child(gal)
	var stage := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	stage.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.45, 0.47, 0.45)
	stage.material_override = sm
	gal.add_child(stage)
	var cols := int(OS.get_environment("COLS")) if OS.get_environment("COLS") != "" else ceili(sqrt(keys.size()))
	var cell := 0.5
	var tall := 0.5
	for k: String in keys:
		var bb: AABB = game.flora.mesh(k).get_aabb()
		cell = maxf(cell, maxf(bb.size.x, bb.size.z) * 1.15)
		tall = maxf(tall, bb.end.y)
	var rows := ceili(float(keys.size()) / cols)
	for i in keys.size():
		var mi := MeshInstance3D.new()
		mi.mesh = game.flora.mesh(keys[i])
		mi.position = Vector3((i % cols - (cols - 1) * 0.5) * cell, 0.0, (i / cols - (rows - 1) * 0.5) * cell)
		mi.rotation.y = deg_to_rad(float(OS.get_environment("ROT")) if OS.get_environment("ROT") != "" else 0.0)
		gal.add_child(mi)
		print("cell ", i, " ", keys[i])
	var span := maxf(cols, rows) * cell
	var cam := Camera3D.new()
	cam.fov = 50.0
	gal.add_child(cam)
	cam.position = Vector3(0, tall * 0.5 + span * 0.38, span * 0.62 + tall * 0.4)
	cam.current = true
	cam.look_at(gal.to_global(Vector3(0, tall * 0.3, 0)), Vector3.UP)
