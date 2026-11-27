extends SceneTree
## Lights on the building: godot --headless --path . -s tests/light_test.gd
## Wall lights go only on the set spots of a wall, doorway, window or arch (both faces), one per spot; a hanging
## lantern goes under a roof; a light on a blueprint is refused; when the wall comes down its lights come down
## with it (their materials dropped); a wall torch warms you a little.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _o := Vector3.ZERO
var _GA: GDScript
var _Terrain: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _place(kind: String, aim: Vector3, finish := true) -> Dictionary:
	var sn: Dictionary = _GA.snap_piece(kind, aim)
	var why: String = _GA.placement_problem(sn.pos, kind, sn.yaw)
	if why != "":
		print("    (", kind, ": ", why, ")")
		return {"ok": false, "reason": why}
	var r: Dictionary = _GA.place_blueprint(1, kind, sn.pos, sn.yaw)
	if r.get("ok", false) and kind in _GA.FLOOR_KINDS and int(sn.level) == 0:
		_Terrain.commit(_Terrain.level_ground(sn.pos, 1.5, 1.5, 0.0, sn.pos.y))
	if r.get("ok", false) and finish:
		_finish_piece(r.id)
	return r


func _finish_piece(id: String) -> void:
	var st: Dictionary = _game.structures[id]
	st.built = 1.0
	st.hp = st.max_hp
	_game.structures_changed.emit()


func _light(kind: String, spot: Dictionary) -> Dictionary:
	var why: String = _GA.placement_problem(spot.pos, kind, spot.yaw)
	if why != "":
		return {"ok": false, "reason": why}
	var r: Dictionary = _GA.place_blueprint(1, kind, spot.pos, spot.yaw)
	if r.get("ok", false):
		_finish_piece(r.id)
	return r


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Light Test", 777)
			if _main.state == _main.State.PLAYING:
				_o = _find_site()
				_game.inventory_of(1).add("building_plan", 1, true)
				_step = 1
		1:
			_place("wood_floor", _o)
			_place("wood_floor", _o + Vector3(3, 0, 0))
			var wall := _place("wood_wall", _o + Vector3(0, 0.6, -1.2))
			var door := _place("wood_doorway", _o + Vector3(3, 0.6, -1.2))
			var win := _place("wood_window", _o + Vector3(0, 0.6, 1.2))
			_place("wood_wall", _o + Vector3(-1.2, 0.6, 0))
			var wst: Dictionary = _game.structures.get(wall.get("id", ""), {})
			var dst: Dictionary = _game.structures.get(door.get("id", ""), {})
			var nst: Dictionary = _game.structures.get(win.get("id", ""), {})
			_check(_GA.mount_spots(wst, "wall").size() == 2, "a plain wall has a spot on each face (%d)" % _GA.mount_spots(wst, "wall").size())
			_check(_GA.mount_spots(dst, "wall").size() == 6, "a doorway has three spots a face: either side and over it (%d)" % _GA.mount_spots(dst, "wall").size())
			_check(_GA.mount_spots(nst, "wall").size() == 6, "a window has three spots a face (%d)" % _GA.mount_spots(nst, "wall").size())
			# A torch on the wall's spot; the same spot again is refused; off-spot is refused.
			var sp: Dictionary = _GA.mount_spots(wst, "wall")[0]
			var t := _light("wall_torch", sp)
			_check(t.get("ok", false), "a wall torch goes on the wall's spot (%s)" % t.get("reason", "ok"))
			var again := _light("wall_lantern", sp)
			_check(not again.get("ok", false), "a second light on the same spot is refused: %s" % again.get("reason", ""))
			var off := _light("wall_torch", {"pos": sp.pos + Vector3(0.5, 0.3, 0), "yaw": sp.yaw})
			_check(not off.get("ok", false), "a light off the set spots is refused: %s" % off.get("reason", ""))
			if t.get("ok", false):
				var tst: Dictionary = _game.structures[t.id]
				_check(String(tst.get("mount", "")) == String(wst.id) and absf(angle_difference(float(tst.yaw), float(sp.yaw))) < 0.01, "the torch remembers its wall and faces out from it")
			# Either side of the doorway: a lantern and a sconce.
			var ds: Array = _GA.mount_spots(dst, "wall")
			_check(_light("wall_lantern", ds[0]).get("ok", false) and _light("candle_sconce", ds[2]).get("ok", false), "a lantern and a sconce go by the doorway")
			# The ghost's aim: a hit on the wall's face near its spot picks that spot.
			var near: Dictionary = _GA.nearest_mount("wall_torch", dst, (ds[2].pos as Vector3) + Vector3(0.1, -0.2, 0), Basis(Vector3.UP, float(ds[2].yaw)) * Vector3.BACK)
			_check(not near.is_empty() and (near.pos as Vector3).distance_to(ds[2].pos) < 0.01, "aiming near a spot on a face picks that spot")
			# A blueprint wall takes no lights yet.
			var bp := _place("wood_wall", _o + Vector3(4.2, 0.6, 0), false)
			if bp.get("ok", false):
				var bsp: Dictionary = _GA.mount_spots(_game.structures[bp.id], "wall")[0]
				var on_bp := _light("wall_torch", bsp)
				_check(not on_bp.get("ok", false), "no lights on a blueprint: %s" % on_bp.get("reason", ""))
			# A lantern under a roof: the roof needs walls (the plain wall and the west wall hold the first cell's roof).
			var roof := _place("wood_roof", _o + Vector3(0, 3.2, 0))
			_check(roof.get("ok", false), "a roof over the first cell (%s)" % roof.get("reason", "ok"))
			if roof.get("ok", false):
				var rs: Array = _GA.mount_spots(_game.structures[roof.id], "ceiling")
				_check(rs.size() == 1, "a roof has one spot underneath")
				var hl := _light("hanging_lantern", rs[0])
				_check(hl.get("ok", false), "a hanging lantern goes under the roof (%s)" % hl.get("reason", "ok"))
				var walls_lantern := _light("wall_lantern", rs[0])
				_check(not walls_lantern.get("ok", false), "a wall lantern can't hang from a ceiling")
			# Warmth from the torch.
			var p = _main.player
			p.global_position = (sp.pos as Vector3) + Basis(Vector3.UP, float(sp.yaw)) * Vector3(0, -1.5, 1.0)
			_game.time_of_day = 0.95
			p._update_exposure()
			_check(p._heat > 0.1, "a wall torch warms you a little (heat %.2f)" % p._heat)
			# Down comes the doorway: its lights come down with it, and what they cost is dropped.
			var pickups_before: int = _game.pickups.size()
			_GA._remove_piece(dst)
			var left := 0
			for id: String in _game.structures:
				if String(_game.structures[id].get("mount", "")) == String(dst.id):
					left += 1
			_check(left == 0, "the doorway's lights came down with it")
			_check(_game.pickups.size() > pickups_before, "their materials were dropped (%d pickups)" % (_game.pickups.size() - pickups_before))
			print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
			return true
	return false


func _find_site() -> Vector3:
	var gen = _game.world_gen
	var spot: Vector3 = gen.find_spawn_point()
	for k in 3600:
		var c := spot + Vector3((k % 60 - 30) * 3.0, 0, (k / 60 - 30) * 3.0)
		c.x = floorf(c.x / 3.0) * 3.0 + 1.5
		c.z = floorf(c.z / 3.0) * 3.0 + 1.5
		var ok := true
		var h0: float = gen.get_height(c.x, c.z)
		for j in range(-1, 3):
			for i in range(-1, 4):
				var q := c + Vector3(i * 3.0, 0, j * 3.0)
				var h: float = gen.get_height(q.x, q.z)
				if h < 2.0 or absf(h - h0) > 1.5 or gen.near_river(q.x, q.z, 6.0) or _Terrain.tree_near(q, 3.6) != null:
					ok = false
					break
			if not ok:
				break
		if ok:
			c.y = h0
			return c
	print("no flat site found")
	return spot


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)
