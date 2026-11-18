extends SceneTree
## Item sizes (diagnostic): godot --headless --path . -s tests/tools/item_sizes.gd
## Prints each item model's bounding box, so world and first-person sizes can be compared.

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
			_main.create_world("Item Sizes", 629946553)
		if _main.state == _main.State.PLAYING:
			_started = true
			_report()
			return true
	return false


func _report() -> void:
	var IM = load("res://scripts/items/item_models.gd")
	var IDB = load("res://scripts/items/item_db.gd")
	var art = load("res://scripts/world/art_style.gd")
	var mat: Material = art.painted({"brush_strength": 0.16, "rim_amount": 0.3})
	for id: String in IDB.all_ids():
		var info: Dictionary = IDB.info(id)
		var mesh: ArrayMesh = IM.mesh_for(id, mat)
		if mesh == null or mesh.get_surface_count() == 0:
			print("SIZE %-16s %-10s no model" % [id, info.get("kind", "")])
			continue
		var box := mesh.get_aabb()
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		print("SIZE %-16s %-10s longest %.3f m  box %.2f x %.2f x %.2f" % [id, info.get("kind", ""), longest, box.size.x, box.size.y, box.size.z])
