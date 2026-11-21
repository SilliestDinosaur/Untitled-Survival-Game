extends SceneTree
## Stairs test: godot --headless --path . -s tests/stairs_test.gd
## Builds a floor and a staircase, stands the player at the bottom and holds forward: the body should
## walk up the treads (a step is 0.29 m, the body climbs up to 0.36 m) and reach the upper level.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _GA: GDScript
var _Terrain: GDScript
var _start_y := 0.0
var _max_y := -1000.0
var _frames := 0


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Stairs Test", 4242)
			if _main.state == _main.State.PLAYING:
				var spot := _find_clear_cell()
				var inv = _game.inventory_of(1)
				inv.add("building_plan", 1, true)
				var fsnap: Dictionary = _GA.snap_piece("brick_floor", spot)
				_build(String(_GA.place_blueprint(1, "brick_floor", fsnap.pos, 0.0).id))
				_Terrain.commit(_Terrain.level_ground(fsnap.pos, 1.5, 1.5, 0.0, fsnap.pos.y))
				var ssnap: Dictionary = _GA.snap_piece("stone_stairs", spot, -1.0, 0.0)
				var placed: Dictionary = _GA.place_blueprint(1, "stone_stairs", ssnap.pos, ssnap.yaw)
				_check(placed.ok, "stairs placed on the floor (%s)" % placed.get("reason", ""))
				if placed.ok:
					_build(String(placed.id))
				# A second floor south of the stairs: the player starts there and walks north, up the treads.
				var south := spot + Vector3(0, 0, 3.0)
				south.y = _game.world_gen.get_height(south.x, south.z)
				var ssouth: Dictionary = _GA.snap_piece("brick_floor", south)
				var placed_south: Dictionary = _GA.place_blueprint(1, "brick_floor", ssouth.pos, 0.0)
				_check(placed_south.ok, "the floor the player starts on is placed (%s)" % placed_south.get("reason", ""))
				if placed_south.ok:
					_build(String(placed_south.id))
				_Terrain.commit(_Terrain.level_ground(ssouth.pos, 1.5, 1.5, 0.0, ssouth.pos.y))
				var floor_top: float = ssouth.pos.y + _GA.FLOOR_TOP
				_main.player.global_position = Vector3(south.x, floor_top + 0.2, south.z)
				_main.player.rotation.y = 0.0
				_start_y = _main.player.global_position.y
				_max_y = _start_y
				Input.action_press("move_forward")
				_step = 1
				_f = 0
		1:
			_frames += 1
			_max_y = maxf(_max_y, _main.player.global_position.y)
			if _frames >= 480 or _max_y > _start_y + _GA.STACK_H - 0.3:
				Input.action_release("move_forward")
				var climbed := _max_y - _start_y
				_check(climbed > _GA.STACK_H - 0.5, "the body walks up the stairs (rose %.2f m of %.2f)" % [climbed, _GA.STACK_H])
				return _finish()
	return false


func _find_clear_cell() -> Vector3:
	var spot: Vector3 = _game.world_gen.find_spawn_point()
	spot.x = floorf(spot.x / 3.0) * 3.0 + 1.5
	spot.z = floorf(spot.z / 3.0) * 3.0 + 1.5
	for k in 200:
		var cand := spot + Vector3((k % 14 - 7) * 3.0, 0, (k / 14 - 7) * 3.0)
		cand.x = floorf(cand.x / 3.0) * 3.0 + 1.5
		cand.z = floorf(cand.z / 3.0) * 3.0 + 1.5
		cand.y = _game.world_gen.get_height(cand.x, cand.z)
		if _Terrain.tree_near(cand, 6.0) == null and _game.world_gen.get_height(cand.x, cand.z) > 2.0 \
				and not _game.world_gen.near_river(cand.x, cand.z, 8.0) \
				and _GA.placement_problem(_GA.snap_piece("brick_floor", cand).pos, "brick_floor", 0.0) == "":
			return cand
	return spot


func _slot_of(inv, id: String) -> int:
	for i in inv.slots.size():
		if inv.slots[i].get("id", "") == id:
			return i
	return 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true

## Finish a blueprint the way a player does: a hammer in hand and the materials in the pack, hit until it's built.
func _build(id: String) -> void:
	var inv = _game.inventory_of(1)
	var st: Dictionary = _game.structures[id]
	for item: String in _GA.PIECE_COSTS[st.kind]:
		inv.add(item, int(_GA.PIECE_COSTS[st.kind][item]), true)
	if inv.count("hammer") < 1:
		inv.add("hammer", 1, true)
	var keep: int = inv.selected
	inv.select(_slot_of(inv, "hammer"))
	for i in 20:
		if not _GA.is_blueprint(_game.structures[id]):
			break
		_GA.hit_structure(1, id)
	inv.select(keep)
