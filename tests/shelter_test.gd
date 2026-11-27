extends SceneTree
## What a building is good for: godot --headless --path . -s tests/shelter_test.gd
## A closed room is full shelter (the cold mostly kept out), a roof alone half; animals keep out of built ground;
## a bed in a sheltered room lets you sleep the night away (not by day, not out in the open), and the player wakes
## by their bed after a fall.

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _o := Vector3.ZERO
var _GA: GDScript
var _Terrain: GDScript
var _bed := ""


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _c(i: int, j: int) -> Vector3:
	return _o + Vector3(i * 3.0, 0, j * 3.0)


func _place(kind: String, aim: Vector3, yaw := 0.0) -> Dictionary:
	var sn: Dictionary = _GA.snap_piece(kind, aim) if _GA.is_building(kind) and not _GA.is_decor(kind) else {"pos": aim, "yaw": yaw, "level": 0}
	var why: String = _GA.placement_problem(sn.pos, kind, sn.yaw)
	if why != "":
		print("    (", kind, ": ", why, ")")
		return {"ok": false, "reason": why}
	var r: Dictionary = _GA.place_blueprint(1, kind, sn.pos, sn.yaw)
	if r.get("ok", false) and kind in _GA.FLOOR_KINDS and int(sn.level) == 0:
		_Terrain.commit(_Terrain.level_ground(sn.pos, 1.5, 1.5, 0.0, sn.pos.y))
	if r.get("ok", false):
		var st: Dictionary = _game.structures[r.id]
		st.built = 1.0   # (finished: the hammer's own test is elsewhere)
		st.hp = st.max_hp
	return r


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Shelter Test", 777)
			if _main.state == _main.State.PLAYING:
				_o = _find_site()
				_game.inventory_of(1).add("building_plan", 1, true)
				_step = 1
		1:
			# A 2x2 room, walls all round (one a doorway), roofed; a porch roof out past the east side.
			for j in 2:
				for i in 2:
					_place("wood_floor", _c(i, j))
			for i in 2:
				_place("wood_wall", _c(i, 0) + Vector3(0, 0.6, -1.2))
				_place("wood_doorway" if i == 0 else "wood_wall", _c(i, 1) + Vector3(0, 0.6, 1.2))
				_place("wood_wall", _c(0, i) + Vector3(-1.2, 0.6, 0))
				_place("wood_wall", _c(1, i) + Vector3(1.2, 0.6, 0))
			for ij: Array in [[0, 0], [1, 0], [0, 1], [1, 1]]:
				_place("wood_roof", _c(ij[0], ij[1]) + Vector3(0, 3.2, 0))
			_place("wood_roof", _c(2, 0) + Vector3(0, 3.2, 0))
			var floor_top: float = float(_GA.foundation_at(_GA.cell_of(_o), 0).pos[1]) + _GA.FLOOR_TOP
			var inside := _c(0, 0) + Vector3(0.3, 0, 0.2)
			inside.y = floor_top
			var sh: float = _GA.shelter_at(inside)
			_check(sh > 0.95, "a closed room is full shelter (%.2f)" % sh)
			var porch := _c(2, 0)
			porch.y = _game.world_gen.get_height(porch.x, porch.z)
			var sp: float = _GA.shelter_at(porch)
			_check(sp >= 0.5 and sp < 0.8, "under a porch roof is part shelter (%.2f)" % sp)
			var out := _c(4, 3)
			out.y = _game.world_gen.get_height(out.x, out.z)
			_check(_GA.shelter_at(out) == 0.0, "out in the open is no shelter")
			_check(_GA.in_building(inside) and not _GA.in_building(out), "built ground is marked for animals to keep out of")
			# The cold indoors: the player stands inside at night.
			var p = _main.player
			p.global_position = inside + Vector3(0, 0.05, 0)
			_game.time_of_day = 0.95
			p._update_exposure()
			var cold_in: float = p._cold
			p.global_position = out + Vector3(0, 0.1, 0)
			p._update_exposure()
			var cold_out: float = p._cold
			_check(cold_in < cold_out * 0.3, "much less cold indoors at night (%.2f vs %.2f outside)" % [cold_in, cold_out])
			# A bed in the room.
			var bp := _c(1, 0) + Vector3(0, 0, 0)
			bp.y = floor_top
			var b := _place("bed", bp)
			_check(b.get("ok", false), "a bed goes in the room (%s)" % b.get("reason", "ok"))
			_bed = String(b.get("id", ""))
			_game.time_of_day = 0.5
			var by_day: String = _GA.sleep_problem(_game.structures.get(_bed, {}))
			_check(by_day != "", "no sleeping by day: %s" % by_day)
			_game.time_of_day = 0.9
			var at_night: String = _GA.sleep_problem(_game.structures.get(_bed, {}))
			_check(at_night == "", "a bed in a closed room at night is fine (%s)" % at_night)
			# A bed out in the open is no good.
			var ob := _place("bed", out)
			if ob.get("ok", false):
				var open_bed: String = _GA.sleep_problem(_game.structures[ob.id])
				_check(open_bed != "", "a bed out in the open is too exposed: %s" % open_bed)
			# Sleep: the night passes, a new day, just after sunrise.
			var day0: int = _game.day
			p.global_position = inside + Vector3(0, 0.05, 0)
			p._use_bed(_bed)
			_check(_game.day == day0 + 1 and _game.time_of_day > _game.SUNRISE and _game.time_of_day < _game.SUNRISE + 0.05,
				"sleeping passes the night (day %d -> %d, time %.3f)" % [day0, _game.day, _game.time_of_day])
			_check(p.bed == _bed, "the bed is the player's now")
			# A fall: up again beside the bed.
			p.respawn()
			var d: float = Vector2(p.global_position.x - bp.x, p.global_position.z - bp.z).length()
			_check(d < 1.6, "after a fall you wake beside your bed (%.1f m off)" % d)
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
		for j in range(-1, 5):
			for i in range(-1, 6):
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
