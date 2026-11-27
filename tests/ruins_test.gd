extends SceneTree
## Ruins: godot --headless --path . -s tests/ruins_test.gd
## A new island has temples, watchtowers and cave vaults; an older save's has none. Nothing grows or lies on a
## ruin's ground. Every ruin and vault has a chest you can open, once (a vault's has the better things), and finding
## one marks it in your progress (the map and the journal show it).

var _main: Node
var _g: Node
var _f := 0
var _step := 0
var _fails: Array[String] = []
var _CG: GDScript
var _GA: GDScript
var _Progress: GDScript


func _initialize() -> void:
	_CG = load("res://scripts/world/chunk_generator.gd")
	_GA = load("res://scripts/core/game_actions.gd")
	_Progress = load("res://scripts/gameplay/progress.gd")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_g = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			if _f == 5:
				_main.create_world("Ruins Test", 4242)
			if _main.state == _main.State.PLAYING:
				_step = 1
		1:
			var gen = _g.world_gen
			var temples: Array = gen.ruins.filter(func(r: Dictionary) -> bool: return r.kind == "temple")
			var towers: Array = gen.ruins.filter(func(r: Dictionary) -> bool: return r.kind == "tower")
			var vaults: Array = gen.caves.get("vaults", [])
			_check(_g.world_v == 2 and _g.WORLD_SIZE == 3072.0, "a new world is the current kind (v%d, %d m)" % [_g.world_v, _g.WORLD_SIZE])
			_check(temples.size() >= 4, "it has temples (%d)" % temples.size())
			_check(towers.size() >= 4, "and watchtowers (%d)" % towers.size())
			_check(vaults.size() >= 1, "and vaults in its caves (%d)" % vaults.size())
			# Every ruin and vault has its chest.
			var keys := {}
			for n in _all(root):
				if n.has_meta("loot_key"):
					keys[String(n.get_meta("loot_key"))] = n
			var missing := 0
			for i in gen.ruins.size():
				if not keys.has("ruin_chest_%d" % i):
					missing += 1
			for i in vaults.size():
				if not keys.has("vault_chest_%d" % i):
					missing += 1
			_check(missing == 0, "every ruin and vault has a chest (%d missing)" % missing)
			# Nothing on a ruin's ground (trees, rocks, bushes, clutter).
			var on := 0
			for ru: Dictionary in gen.ruins.slice(0, 6):
				var p: Vector3 = ru.pos
				var c := Vector2i(floori(p.x / _g.CHUNK_SIZE), floori(p.z / _g.CHUNK_SIZE))
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var coord := c + Vector2i(dx, dz)
						var origin := Vector3(coord.x * _g.CHUNK_SIZE, 0, coord.y * _g.CHUNK_SIZE)
						for r: Dictionary in _CG._place_resources(coord, origin, gen, _g.flora, {}):
							var q: Vector3 = (r.transform as Transform3D).origin
							if Vector2(q.x - p.x, q.z - p.z).length() < float(ru.r) - 0.5 and q.y > p.y - 6.0:
								on += 1
			_check(on == 0, "nothing grows or lies on a ruin's ground (%d things)" % on)
			# A ruin's chest opens once; a vault's has the better things in it.
			var key := "ruin_chest_0"
			var first: Dictionary = _GA.open_cache(1, key)
			_check(first.ok and not (first.items as Dictionary).is_empty(), "a ruin's chest has things in it (%s)" % str(first.items.keys()))
			var again: Dictionary = _GA.open_cache(1, key)
			_check(not again.ok and again.empty, "and it's empty the second time")
			var metal := 0
			for i in vaults.size():
				var v: Dictionary = _GA.open_cache(1, "vault_chest_%d" % i)
				for k: String in v.items:
					if k.begins_with("ingot") or k.begins_with("gem"):
						metal += 1
			_check(vaults.is_empty() or metal > 0, "the vaults' coffers hold worked metal (%d lots)" % metal)
			_check(not (_GA.open_cache(1, "nonsense_7") as Dictionary).ok and not (_GA.open_cache(1, "ruin_chest_x") as Dictionary).ok, "a made-up chest key opens nothing")
			# Finding one: walk onto a temple and it's marked, and the milestone comes.
			var player = _main.get_node("Player")
			var t: Dictionary = temples[0]
			player.global_position = (t.pos as Vector3) + Vector3(0, 3, 0)
			var p: Dictionary = _Progress.blank()
			var earned: Array = _Progress.update(p, player, [])
			_check((p.ruins as Dictionary).values().has("temple"), "walking onto a temple marks it found")
			_check(earned.has("ruin_temple"), "and earns 'Lost temple'")
			_check(_Progress.ruin_total(gen) == gen.ruins.size() + vaults.size(), "the journal counts every ruin and vault (%d)" % _Progress.ruin_total(gen))
			# An older save's island (v1) has no ruins and no vaults: nothing appears over somebody's base.
			_g.new_world(4242, 3072.0, 1)
			_check(_g.world_gen.ruins.is_empty() and (_g.world_gen.caves.get("vaults", []) as Array).is_empty(), "an older world has no ruins or vaults")
			print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
			quit()
			return true
	return false


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)
