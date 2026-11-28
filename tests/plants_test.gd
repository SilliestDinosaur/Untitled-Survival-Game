extends SceneTree
## Plants of every land: godot --headless --path . -s tests/plants_test.gd
## Every kind in the biome tables is a real plant with a model; every land grows some of the newer shrubs, ground
## plants or gatherables; hand-gathering each gatherable gives real items; juniper berries keep the cold off.

var _main: Node
var _game: Node
var _f := 0
var _fails: Array[String] = []
var FL: GDScript
var CG: GDScript
var GA: GDScript

const NEW := ["dune_grass", "sea_thrift", "alpine_cushion", "edelweiss", "heather", "juniper", "sagebrush", "bramble", "rhododendron", "ocotillo", "hibiscus", "spore_bush", "cattail", "aloe",
	"wild_garlic", "lingonberry", "lupin", "daisy", "foxglove", "sedge", "desert_bloom", "bromeliad", "cotton_grass", "lichen", "puffball"]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_game = root.get_node("Game")


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_main.create_world("Plants Test", 629946553)
	if _f > 5 and _main.state == _main.State.PLAYING:
		FL = load("res://scripts/world/flora_library.gd")
		CG = load("res://scripts/world/chunk_generator.gd")
		GA = load("res://scripts/core/game_actions.gd")
		var flora = _game.flora
		# Every kind named in a biome table exists and has a model.
		for table: Dictionary in [FL.BIOME_BUSHES, FL.BIOME_CLUTTER, FL.BIOME_GROUND]:
			for b in table:
				for e: Array in table[b]:
					_check(FL.KINDS.has(e[0]), "%s is a plant kind" % e[0])
		for kind: String in NEW:
			var key: String = flora.variants[kind][0]
			var m: Mesh = flora.mesh(key)
			var tris := 0
			for si in m.get_surface_count():
				tris += (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			_check(tris > 10, "%s has a model (%d triangles)" % [kind, tris])
			if FL.KINDS[kind].category == "flower":
				_check(tris < 400, "%s is light enough for ground cover (%d)" % [kind, tris])
		# Each land grows some new plants: sample chunks and count by the biome under each.
		var gen = _game.world_gen
		var by_biome := {}
		var n := int(_game.WORLD_SIZE / _game.CHUNK_SIZE)
		for cz in range(1, n - 1, 3):
			for cx in range(1, n - 1, 3):
				var origin := Vector3(cx * 64, 0, cz * 64)
				var res: Array = CG._place_resources(Vector2i(cx, cz), origin, gen, flora, {}, [], false)
				for r: Dictionary in res:
					if String(r.kind) in NEW:
						var p: Vector3 = r.transform.origin
						var b: int = gen.get_biome(p.x, p.z)
						by_biome[b] = int(by_biome.get(b, 0)) + 1
				var bufs := {}
				CG._place_ground_cover(Vector2i(cx, cz), origin, gen, flora, 1.0, bufs)
				for key: String in bufs:
					if FL.kind_of_key(key) in NEW:
						var bb: PackedFloat32Array = bufs[key]
						var b: int = gen.get_biome(origin.x + bb[3], origin.z + bb[11])
						by_biome[b] = int(by_biome.get(b, 0)) + bb.size() / 16
		for b in gen.BIOME_NAMES.size():
			if gen.BIOME_NAMES[b] == "":
				continue
			print("    ", gen.BIOME_NAMES[b], ": ", by_biome.get(b, 0), " new plants")
		var lands := 0
		for b in by_biome:
			if int(by_biome[b]) > 0:
				lands += 1
		_check(lands >= 9, "new plants grow in most lands (%d)" % lands)
		# Gathering by hand gives real items.
		var inv = _game.inventory_of(1)
		var rng := RandomNumberGenerator.new()
		for kind: String in ["heather", "juniper", "sagebrush", "bramble", "spore_bush", "lingonberry", "cattail", "aloe", "wild_garlic", "rhododendron", "hibiscus", "ocotillo"]:
			var r := {"id": "t_%s" % kind, "kind": kind, "key": flora.variants[kind][0], "hp": 10}
			var res: Dictionary = GA.harvest_resource_r(1, r, rng)
			var ok: bool = res.get("ok", false)
			_check(ok and not (res.items as Dictionary).is_empty(), "gathering %s gives %s" % [kind, str(res.get("items", {}))])
			for item: String in res.get("items", {}):
				_check(load("res://scripts/items/item_db.gd").exists(item), "%s is a real item" % item)
		# Juniper berries: Warmed.
		var p = _main.player
		_game.time_of_day = 0.95
		p._update_exposure()
		var cold0: float = p._cold
		p.stats.add_effect("warm", 60.0)
		p._update_exposure()
		_check(p._cold < cold0 * 0.5 + 0.001, "juniper's warmth keeps the cold off (%.2f -> %.2f)" % [cold0, p._cold])
		print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
		return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("  FAIL " + what)
		_fails.append(what)
