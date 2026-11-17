extends SceneTree
## Shovel terrain test: godot --headless --path . -s tests/terrain_test.gd
## Digs, piles and flattens the ground, checks the dirt bookkeeping, and checks that the edits
## survive a save and reload.

var TerrainEditScript: GDScript
var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _p := Vector3.ZERO
var _h0 := 0.0
var _dirt0 := 0


func _initialize() -> void:
	TerrainEditScript = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Terrain Test", 555)
			if _main.state == _main.State.PLAYING:
				_p = _game.world_gen.find_spawn_point()
				_h0 = _game.world_gen.get_height(_p.x, _p.z)
				_next(1)
		1:   # dig
			var inv: Inventory = _game.inventory_of(1)
			_dirt0 = inv.count("dirt")
			var res: Dictionary = TerrainEditScript.apply({"mode": TerrainEdit.Mode.DIG, "x": _p.x, "z": _p.z, "r": 2.0, "s": 0.8}, inv)
			_check(res.ok, "dig works")
			TerrainEditScript.commit(res.cells)
			var h1: float = _game.world_gen.get_height(_p.x, _p.z)
			_check(h1 < _h0 - 0.2, "dug ground is lower: %.2f -> %.2f" % [_h0, h1])
			_check(inv.count("dirt") > _dirt0, "digging gives dirt: %d" % inv.count("dirt"))
			_next(2)
		2:   # pile
			var inv: Inventory = _game.inventory_of(1)
			var before: int = inv.count("dirt")
			var h_before: float = _game.world_gen.get_height(_p.x, _p.z)
			var res: Dictionary = TerrainEditScript.apply({"mode": TerrainEdit.Mode.PILE, "x": _p.x, "z": _p.z, "r": 2.0, "s": 0.5}, inv)
			_check(res.ok, "pile works")
			TerrainEditScript.commit(res.cells)
			var h_after: float = _game.world_gen.get_height(_p.x, _p.z)
			_check(h_after > h_before, "piled ground is higher: %.2f -> %.2f" % [h_before, h_after])
			_check(inv.count("dirt") < before, "piling used dirt: %d -> %d" % [before, inv.count("dirt")])
			_next(3)
		3:   # flatten toward a height
			var target: float = _game.world_gen.get_height(_p.x, _p.z) + 0.5
			var res: Dictionary = TerrainEditScript.apply({"mode": TerrainEdit.Mode.FLATTEN, "x": _p.x, "z": _p.z, "r": 3.0, "s": 1.0, "target": target}, _game.inventory_of(1))
			TerrainEditScript.commit(res.cells)
			var h2: float = _game.world_gen.get_height(_p.x, _p.z)
			_check(absf(h2 - target) < 0.3, "flatten pulls toward %.2f (got %.2f)" % [target, h2])
			_next(4)
		4:   # chunks around the edit get rebuilt
			var w = _main.get_node("World")
			if w._dirty.is_empty() and _f > 30:
				_check(true, "touched chunks rebuilt")
				_next(7)
			elif _f > 600:
				_check(false, "touched chunks never rebuilt: %d left" % w._dirty.size())
				return _finish()
		5:   # save, reload: edits come back
			var before_h: float = _game.world_gen.get_height(_p.x, _p.z)
			_main.save_now()
			var id: String = _game.save_id
			_main._to_title()
			_main.load_world(id)
			_next(6)
		7:   # pickaxe carves stone, refuses soft ground; bricks chiseled at a workbench
			var rock := Vector3.INF
			var sand := Vector3.INF
			for k in 400:
				var x := _p.x + (k % 20 - 10) * 9.0
				var z := _p.z + (k / 20 - 10) * 9.0
				var surf: String = _game.world_gen.get_surface(x, z)
				if rock == Vector3.INF and surf == "rock":
					rock = Vector3(x, 0, z)
				if sand == Vector3.INF and surf == "sand":
					sand = Vector3(x, 0, z)
			if rock == Vector3.INF:
				_check(true, "no rock nearby to test on (skipped)")
			else:
				var inv: Inventory = _game.inventory_of(1)
				var s0: int = inv.count("stone")
				var res: Dictionary = TerrainEditScript.apply({"mode": TerrainEditScript.Mode.DIG, "x": rock.x, "z": rock.z, "r": 1.5, "s": 0.2, "rock": true}, inv)
				_check(res.ok and inv.count("stone") > s0, "pickaxe carves stone: +%d" % (inv.count("stone") - s0))
			if sand != Vector3.INF:
				var res2: Dictionary = TerrainEditScript.apply({"mode": TerrainEditScript.Mode.DIG, "x": sand.x, "z": sand.z, "r": 1.5, "s": 0.2, "rock": true}, _game.inventory_of(1))
				_check(not res2.ok, "pickaxe refuses soft ground: %s" % res2.get("reason", ""))
			var inv3: Inventory = _game.inventory_of(1)
			inv3.add("stone", 4, true)
			_game.structures["test_bench"] = {"id": "test_bench", "kind": "workbench", "pos": [_p.x, _p.y, _p.z], "yaw": 0.0, "hp": 3}
			var brick_id := ""
			for rc: Dictionary in load("res://scripts/items/recipes.gd").all():
				if rc.out == "brick":
					brick_id = rc.id
			var made: Dictionary = load("res://scripts/core/game_actions.gd").craft(1, brick_id, _p)
			_check(made.ok and inv3.count("brick") >= 2, "chiseled stone into bricks at a workbench (%d bricks)" % inv3.count("brick"))
			_next(5)
		6:
			if _main.state == _main.State.PLAYING or _f > 600:
				var after_h: float = _game.world_gen.get_height(_p.x, _p.z)
				_check(_main.state == _main.State.PLAYING, "reloaded into the world")
				_check(absf(after_h - _h0) > 0.05 or _game.world_gen.edits.size() > 0, "terrain edits survive reload (%d cells)" % _game.world_gen.edits.size())
				return _finish()
	return false


func _next(s: int) -> void:
	_step = s
	_f = 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _finish() -> bool:
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	return true
