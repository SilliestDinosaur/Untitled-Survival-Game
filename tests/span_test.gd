extends SceneTree
## Roofs and upper floors held up through each other: godot --headless --path . -s tests/span_test.gd
## A 3x3 room walled round its outside takes a roof over every cell (the middle one has no walls of its own, it's
## held by the roofs round it); a porch roof can reach out past the walls, but not more than SPAN cells from what
## holds it up; a link in that chain can't be taken down while something hangs from it; and an upper floor can
## reach out over open ground beside a floor that's held up (a balcony).

var _main: Node
var _game: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _o := Vector3.ZERO   # the middle of the room's first cell (cell 0, 0)
var _GA: GDScript
var _Terrain: GDScript


func _initialize() -> void:
	_GA = load("res://scripts/core/game_actions.gd")
	_Terrain = load("res://scripts/world/terrain_edit.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _c(i: int, j: int) -> Vector3:
	return _o + Vector3(i * 3.0, 0, j * 3.0)


func _place(kind: String, aim: Vector3) -> Dictionary:
	var sn: Dictionary = _GA.snap_piece(kind, aim)
	var why: String = _GA.placement_problem(sn.pos, kind, sn.yaw)
	if why != "":
		return {"ok": false, "reason": why, "pos": sn.pos, "level": sn.level}
	var r: Dictionary = _GA.place_blueprint(1, kind, sn.pos, sn.yaw)
	if r.get("ok", false) and kind in _GA.FLOOR_KINDS and int(sn.level) == 0:
		_Terrain.commit(_Terrain.level_ground(sn.pos, 1.5, 1.5, 0.0, sn.pos.y))
	return r


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Span Test", 777)
			if _main.state == _main.State.PLAYING:
				_o = _find_site()
				_game.inventory_of(1).add("building_plan", 1, true)
				_step = 1
		1:
			# Floors 3x3, walls all round the outside.
			for j in 3:
				for i in 3:
					_check(_place("wood_floor", _c(i, j)).get("ok", false), "floor %d,%d placed" % [i, j])
			var walls := 0
			for i in 3:
				walls += int(_place("wood_wall", _c(i, 0) + Vector3(0, 0.6, -1.2)).get("ok", false))
				walls += int(_place("wood_wall", _c(i, 2) + Vector3(0, 0.6, 1.2)).get("ok", false))
				walls += int(_place("wood_wall", _c(0, i) + Vector3(-1.2, 0.6, 0)).get("ok", false))
				walls += int(_place("wood_wall", _c(2, i) + Vector3(1.2, 0.6, 0)).get("ok", false))
			_check(walls == 12, "twelve walls round the room (%d)" % walls)
			# The middle can't be roofed first: nothing beside it yet, no walls of its own.
			var lone := _place("wood_roof", _c(1, 1) + Vector3(0, 3.2, 0))
			_check(not lone.get("ok", false), "a lone roof over the middle is refused: %s" % lone.get("reason", ""))
			# Corners first (two walls each), then the sides, then the middle: all held up.
			var order := [[0, 0], [2, 0], [0, 2], [2, 2], [1, 0], [0, 1], [2, 1], [1, 2], [1, 1]]
			for ij: Array in order:
				var r := _place("wood_roof", _c(ij[0], ij[1]) + Vector3(0, 3.2, 0))
				_check(r.get("ok", false), "roof over %d,%d (%s)" % [ij[0], ij[1], r.get("reason", "ok")])
			# A porch roof one and two cells out past the east wall, over open ground.
			var p1 := _place("wood_roof", _c(3, 1) + Vector3(0, 3.2, 0))
			_check(p1.get("ok", false), "a porch roof one cell out (%s)" % p1.get("reason", "ok"))
			if p1.get("ok", false):
				_check(absf(float(p1.pos.y) - float(_game.structures[p1.id].pos[1])) < 0.01 and absf(float(p1.pos.y) - _roof_y(1, 1)) < 0.01,
					"the porch roof lines up with the room's roof")
			var p2 := _place("wood_roof", _c(4, 1) + Vector3(0, 3.2, 0))
			# (4,1): (3,1) is 1 away, (2,1) 2 away, the nearest roof on two walls (2,0)/(2,2) 3 away: too far.
			_check(not p2.get("ok", false), "a roof three cells from what holds it is refused: %s" % p2.get("reason", ""))
			# The roof the porch hangs from can't come down while it does.
			var link: Dictionary = _GA.cover_in(_GA.cell_of(_c(2, 1)), 0)
			var why: String = _GA.removal_problem(link)
			_check(why != "", "the roof a porch hangs from can't be taken down: %s" % why)
			# The porch itself can.
			if p1.get("ok", false):
				_check(_GA.removal_problem(_game.structures[p1.id]) == "", "the porch roof itself can be taken down")
			# A corner wall holds up the corner roof (its only two walls) ... but the roofs beside hold it too.
			var corner_wall := _wall_at(_c(0, 0) + Vector3(0, 0, -1.5))
			_check(not corner_wall.is_empty() and _GA.removal_problem(corner_wall) == "",
				"a wall can come down when the roofs round its roof still hold it (%s)" % ("no wall" if corner_wall.is_empty() else _GA.removal_problem(corner_wall)))
			_step = 2
		2:
			# A balcony: an upper floor over the north-west cell's stack, and one out over open ground beside it.
			# (The room's roof covers the rest, so this one is built off its own little tower to the west.)
			var t := _c(-3, 0)
			_check(_place("wood_floor", t).get("ok", false), "tower floor placed")
			var tw := 0
			tw += int(_place("wood_wall", t + Vector3(0, 0.6, -1.2)).get("ok", false))
			tw += int(_place("wood_wall", t + Vector3(0, 0.6, 1.2)).get("ok", false))
			tw += int(_place("wood_wall", t + Vector3(-1.2, 0.6, 0)).get("ok", false))
			_check(tw == 3, "tower walls (%d)" % tw)
			var base: float = _GA.base_y(_GA.cell_of(t))
			var up := _place("wood_floor", t + Vector3(0, 3.5, 0))
			_check(up.get("ok", false) and int(up.get("level", 0)) == 1, "an upper floor on the tower (%s)" % up.get("reason", "ok"))
			var bal := _place("wood_floor", t + Vector3(0, 3.6, -3.0))
			_check(bal.get("ok", false) and int(bal.get("level", 0)) == 1, "a balcony out over the ground beside it (%s, level %s)" % [bal.get("reason", "ok"), bal.get("level", "?")])
			if bal.get("ok", false):
				_check(absf(float(bal.pos.y) - (base + 3.5)) < 0.01, "the balcony is level with the upper floor")
			var far := _place("wood_floor", t + Vector3(0, 3.6, -9.0))
			_check(not far.get("ok", false) or int(far.get("level", 0)) == 0, "a floor far out in the air isn't an upper floor")
			print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
			return true
	return false


func _roof_y(i: int, j: int) -> float:
	return float(_GA.cover_in(_GA.cell_of(_c(i, j)), 0).pos[1])


func _wall_at(p: Vector3) -> Dictionary:
	for id: String in _game.structures:
		var st: Dictionary = _game.structures[id]
		if st.kind in _GA.EDGE_KINDS and Vector2(float(st.pos[0]) - p.x, float(st.pos[2]) - p.z).length() < 0.3:
			return st
	return {}


## Flat, open ground for a 6x4 cell plot.
func _find_site() -> Vector3:
	var gen = _game.world_gen
	var spot: Vector3 = gen.find_spawn_point()
	for k in 3600:
		var c := spot + Vector3((k % 60 - 30) * 3.0, 0, (k / 60 - 30) * 3.0)
		c.x = floorf(c.x / 3.0) * 3.0 + 1.5
		c.z = floorf(c.z / 3.0) * 3.0 + 1.5
		var ok := true
		var h0: float = gen.get_height(c.x, c.z)
		for j in range(-1, 4):
			for i in range(-4, 6):
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
