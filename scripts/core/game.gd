extends Node
## Global game state (autoloaded as "Game").
##
## Anything that defines "what the world is" lives here, separate from visuals and input.
## When co-op is added, this is the stuff the host owns and syncs to clients.

signal world_changed
signal assets_rebuilt   ## meshes were regenerated (model detail setting changed)

const NEW_WORLD_SIZE := 3072.0   ## New worlds are this many metres a side (about 3 km).
const OLD_WORLD_SIZE := 2048.0   ## Saves from before the island grew (no "world_size" in them) keep their 2 km.
## This world's map is WORLD_SIZE x WORLD_SIZE metres. Set per world (see new_world); kept in its save.
var WORLD_SIZE := NEW_WORLD_SIZE
## What a world's generation includes, so an old save's island never changes under it: 1 before ruins, 2 with them.
## Kept in the save (missing: 1) and sent to guests.
const WORLD_V := 2
var world_v := WORLD_V
const CHUNK_SIZE := 64.0     ## Terrain is streamed in square chunks of this size.
const SEA_LEVEL := 0.0
const MAX_SEED := 999_999_999
const REGROW_SECONDS := 900.0   ## gathered trees/rocks grow back after 15 minutes of play

## Everything about a world comes from its seed: terrain, biomes, colors, plants, names.
## For multiplayer, clients only need the seed (plus changes like chopped trees).
var world_seed: int = 0
var world_name := ""
var palette: WorldPalette
var difficulty := 1   ## the chosen Difficulty level of this world (see Difficulty)
var world_gen: WorldGen
var flora: FloraLibrary
var fauna: FaunaLibrary

## Resource id -> play time when it was gathered (chunks skip these until they regrow).
var removed_resources := {}
## Resource id -> remaining HP for things that were hit but not finished off.
var resource_hp := {}

## Resource id -> play time it was last hand-harvested (berries, fiber... come back later).
var harvested := {}
## Items whose hidden effect the player has discovered by eating them.
var known_items := {}
## Supply caches already looted (permanent).
var looted := {}
## What the player has walked near, one byte per 8 m cell of the island (1 = explored). See reveal().
const EXPLORE_CELL := 8.0
var explored := PackedByteArray()
## Items lying in the world: entity id -> {id, item, count, dur, pos: [x, y, z]}.
var pickups := {}
## Placed structures (campfires, workbenches, forges): id -> {id, kind, pos [x,y,z], yaw, hp}.
var structures := {}
## Counter for network-stable entity ids (pickups now; more entity kinds later).
var next_entity_id := 1

## Every player's inventory by player id. Single-player uses LOCAL_PLAYER; a multiplayer host
## would keep one per connected peer (keyed by peer id) and be the only one that changes them.
const LOCAL_PLAYER := 1
var inventories := {}

signal pickups_changed
signal terrain_changed(cells: Array)   ## a placed piece changed the ground here (rebuild those chunks)
signal structures_changed
signal impact(at: Vector3, strength: float)   ## something heavy hit the ground here (cameras nearby shake)
signal new_day(day: int)

## Day/night: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset. One full cycle takes
## DAY_SECONDS; daylight runs from SUNRISE to SUNSET (about 60% of the cycle).
const DAY_SECONDS := 960.0
const SUNRISE := 0.21
const SUNSET := 0.79
var time_of_day := 0.3
var day := 1
var menu_open := false     ## the satchel or the pause menu is up (the world behind blurs)
var time_paused := false   ## title screen keeps a fixed afternoon
const HARVEST_REGROW := 240.0   ## seconds before a hand-harvested plant can be harvested again

## Guests who have played in this world: their uid -> saved character (inventory, position, stats).
var guests := {}
## Playing in someone else's world: time comes from the host and nothing is saved here.
var net_client := false
## Underground: the player is in a cave (see Caves). Caves are far below the surface.
var in_cave := false

## The save file this session is playing ("" = not saved yet / title preview).
var save_id := ""
var save_name := ""
var play_time := 0.0


## Bumped whenever the structures change (see GameActions' cell index, which rebuilds when it moves on).
var structures_version := 0


func _ready() -> void:
	structures_changed.connect(func() -> void: structures_version += 1)
	Settings.apply_bindings()
	var saves := SaveManager.list_saves()
	new_world(saves[0].seed if not saves.is_empty() else random_seed(), float(saves[0].get("world_size", OLD_WORLD_SIZE)) if not saves.is_empty() else NEW_WORLD_SIZE,
		int(saves[0].get("world_v", 1)) if not saves.is_empty() else WORLD_V)
	Settings.changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	if (save_id != "" or net_client) and not get_tree().paused:
		play_time += delta
		if not time_paused:
			time_of_day += delta / DAY_SECONDS
			if time_of_day >= 1.0:
				time_of_day -= 1.0
				day += 1
				new_day.emit(day)


## Sun angle around the sky: 0 at sunrise, PI/2 at noon, PI at sunset, then under the world.
## Days are longer than nights, so the two halves run at different speeds.
func sun_angle(t := -1.0) -> float:
	if t < 0.0:
		t = time_of_day
	if t >= SUNRISE and t <= SUNSET:
		return (t - SUNRISE) / (SUNSET - SUNRISE) * PI
	var into_night := fposmod(t - SUNSET, 1.0) / (1.0 - (SUNSET - SUNRISE))
	return PI + into_night * PI


## 0 at night .. 1 in daylight (soft around sunrise and sunset).
func daylight(t := -1.0) -> float:
	return smoothstep(-0.12, 0.12, sin(sun_angle(t)))


func is_night() -> bool:
	return time_of_day < SUNRISE or time_of_day > SUNSET


## "14:20" style clock.
func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, MAX_SEED)


## Build everything that comes from the seed. Clears per-save state.
func new_world(seed_value: int, size := NEW_WORLD_SIZE, version := WORLD_V) -> void:
	world_seed = clampi(seed_value, 1, MAX_SEED)
	WORLD_SIZE = size
	world_v = version
	world_name = NameGen.world_name(world_seed)
	palette = WorldPalette.new(world_seed)
	world_gen = WorldGen.new(world_seed, palette)
	_build_assets()
	removed_resources = {}
	resource_hp = {}
	harvested = {}
	known_items = {}
	looted = {}
	pickups = {}
	structures = {}
	guests = {}
	explored = PackedByteArray()
	explored.resize(explore_size() * explore_size())
	net_client = false
	in_cave = false
	next_entity_id = 1
	for pid: int in inventories:
		inventories[pid].clear()
	save_id = ""
	save_name = ""
	play_time = 0.0
	time_of_day = 0.3
	day = 1
	world_changed.emit()


func _build_assets() -> void:
	MeshKit.detail = Settings.mesh_detail()
	MeshKit.leaves = Settings.leaf_detail
	ItemDB.build(world_seed, palette)   # first: plants and ore use item colors
	flora = FloraLibrary.new(world_seed, palette)
	flora.prebuild()   # while loading, so no flora mesh is built in the middle of play
	fauna = FaunaLibrary.new(world_seed, palette)
	# The detail setting stays in force after the build: item models, animals and structures are made later too.


var _last_detail := ""
var _last_leaves := true

func _on_settings_changed() -> void:
	if _last_detail == "":
		_last_detail = Settings.model_detail
	# Model detail and leaf cards are baked into the flora meshes, so changing either rebuilds them.
	if (Settings.model_detail != _last_detail or Settings.leaf_detail != _last_leaves) and palette:
		_last_detail = Settings.model_detail
		_last_leaves = Settings.leaf_detail
		ItemModels.clear_cache()   # held items and dropped items pick up the new detail too
		_build_assets()
		assets_rebuilt.emit()


## True if a gathered resource should still be missing (it regrows after a while).
func is_removed(id: String) -> bool:
	if not removed_resources.has(id):
		return false
	return play_time - float(removed_resources[id]) < REGROW_SECONDS


func mark_removed(id: String) -> void:
	removed_resources[id] = play_time
	resource_hp.erase(id)


func inventory_of(player_id: int) -> Inventory:
	if not inventories.has(player_id):
		inventories[player_id] = Inventory.new()
	return inventories[player_id]


const BUILD_V := 2     ## version of building heights (2: walls a full storey tall)
const TERRAIN_V := 2   ## version of how building shapes the ground (2: upper-storey floors leave it alone)


static func _has_upper_floor(sts: Dictionary) -> bool:
	for id: String in sts:
		if sts[id].kind in GameActions.FLOOR_KINDS and int(sts[id].get("level", 0)) > 0:
			return true
	return false


func new_entity_id(prefix: String) -> String:
	next_entity_id += 1
	return "%s%d" % [prefix, next_entity_id]


## True if a plant was hand-harvested recently and has nothing to give yet.
func is_harvested(id: String) -> bool:
	return harvested.has(id) and play_time - float(harvested[id]) < HARVEST_REGROW


# --- Saving -----------------------------------------------------------------------

## Load a save: regenerate its world and restore changes. Returns the player data.
func load_save(id: String) -> Dictionary:
	var data := SaveManager.read(id)
	if data.is_empty():
		return {}
	new_world(int(data.seed), float(data.get("world_size", OLD_WORLD_SIZE)), int(data.get("world_v", 1)))
	save_id = id
	save_name = data.get("name", world_name)
	play_time = float(data.get("play_time", 0.0))
	removed_resources = data.get("removed", {})
	resource_hp = data.get("resource_hp", {})
	harvested = data.get("harvested", {})
	known_items = data.get("known_items", {})
	looted = data.get("looted", {})
	explored = Marshalls.base64_to_raw(String(data.get("explored", "")))
	difficulty = int(data.get("difficulty", Difficulty.NORMAL))
	if explored.size() != explore_size() * explore_size():
		explored = PackedByteArray()
		explored.resize(explore_size() * explore_size())
	pickups = data.get("pickups", {})
	structures = data.get("structures", {})
	# Saves from when walls were 3 m: roofs sat on those, so they go up to the new wall tops.
	if int(data.get("build_v", 1)) < BUILD_V:
		for sid: String in structures:
			var st: Dictionary = structures[sid]
			if st.kind in GameActions.COVER_KINDS:
				st.pos = [float(st.pos[0]), float(st.pos[1]) + GameActions.WALL_H - 3.0, float(st.pos[2])]
	if world_gen:
		world_gen.edits = TerrainEdit.from_list(data.get("terrain", []))
		# Saves from before upper floors stopped raising the ground under them: work the ground out again.
		if int(data.get("terrain_v", 1)) < TERRAIN_V and _has_upper_floor(structures):
			TerrainEdit.rebuild(structures)
	next_entity_id = int(data.get("next_entity_id", 1))
	time_of_day = float(data.get("time_of_day", 0.3))
	day = int(data.get("day", 1))
	pickups_changed.emit()
	structures_changed.emit()
	# Saves keep a map of players (the local one is LOCAL_PLAYER); older saves had one player.
	var players: Dictionary = data.get("players", {})
	if players.is_empty() and data.has("player"):
		players = {str(LOCAL_PLAYER): data.player}
	for key: String in players:
		if key != str(LOCAL_PLAYER):
			guests[key] = players[key]
	_prune_regrown()
	return players.get(str(LOCAL_PLAYER), {})


## Start a brand-new save for the current seed.
func start_new_save(display_name: String) -> void:
	save_name = display_name if display_name.strip_edges() != "" else world_name
	save_id = SaveManager.create(world_seed, save_name)


func write_save(player_data: Dictionary) -> void:
	if save_id == "":
		return
	_prune_regrown()
	SaveManager.write(save_id, {
		"name": save_name,
		"world_name": world_name,
		"seed": world_seed,
		"world_size": WORLD_SIZE,
		"world_v": world_v,
		"created": SaveManager.read(save_id).get("created", Time.get_unix_time_from_system()),
		"last_played": Time.get_unix_time_from_system(),
		"play_time": play_time,
		"removed": removed_resources,
		"resource_hp": resource_hp,
		"harvested": harvested,
		"known_items": known_items,
		"looted": looted,
		"explored": Marshalls.raw_to_base64(explored),
		"difficulty": difficulty,
		"pickups": pickups,
		"structures": structures,
		"terrain": TerrainEdit.to_list(world_gen.edits) if world_gen else [],
		"terrain_v": TERRAIN_V,
		"build_v": BUILD_V,
		"next_entity_id": next_entity_id,
		"time_of_day": time_of_day,
		"day": day,
		"players": _players_for_save(player_data),
	})


func _players_for_save(host_data: Dictionary) -> Dictionary:
	var out := guests.duplicate()
	out[str(LOCAL_PLAYER)] = host_data
	return out


## Everything a guest needs to rebuild the host's world (sent once when they join).
## Cells per side of the explored grid.
func explore_size() -> int:
	return int(WORLD_SIZE / EXPLORE_CELL)


## Mark the ground within `radius` metres of p as explored. True if anything new was seen.
func reveal(p: Vector3, radius := 40.0) -> bool:
	var n := explore_size()
	if explored.size() != n * n:
		explored = PackedByteArray()
		explored.resize(n * n)
	var c := int(radius / EXPLORE_CELL) + 1
	var cx := floori(p.x / EXPLORE_CELL)
	var cz := floori(p.z / EXPLORE_CELL)
	var changed := false
	for z in range(cz - c, cz + c + 1):
		for x in range(cx - c, cx + c + 1):
			if x < 0 or z < 0 or x >= n or z >= n:
				continue
			var mid := Vector2((x + 0.5) * EXPLORE_CELL - p.x, (z + 0.5) * EXPLORE_CELL - p.z)
			if mid.length() > radius:
				continue
			var i := z * n + x
			if explored[i] == 0:
				explored[i] = 1
				changed = true
	return changed


## Whether the ground at a world position has been explored.
func is_explored(p: Vector3) -> bool:
	var n := explore_size()
	var x := floori(p.x / EXPLORE_CELL)
	var z := floori(p.z / EXPLORE_CELL)
	if x < 0 or z < 0 or x >= n or z >= n or explored.size() != n * n:
		return false
	return explored[z * n + x] == 1


func snapshot() -> Dictionary:
	return {
		"seed": world_seed, "world_size": WORLD_SIZE, "world_v": world_v, "name": save_name if save_name != "" else world_name,
		"play_time": play_time, "time_of_day": time_of_day, "day": day,
		"removed": removed_resources, "resource_hp": resource_hp, "harvested": harvested,
		"looted": looted, "pickups": pickups, "structures": structures,
		"explored": Marshalls.raw_to_base64(explored),
		"difficulty": difficulty,
		"terrain": TerrainEdit.to_list(world_gen.edits) if world_gen else [],
	}


## Guest side: become a copy of the host's world.
func apply_snapshot(s: Dictionary) -> void:
	new_world(int(s.seed), float(s.get("world_size", OLD_WORLD_SIZE)), int(s.get("world_v", 1)))
	net_client = true
	save_name = String(s.get("name", world_name))
	play_time = float(s.play_time)
	time_of_day = float(s.time_of_day)
	day = int(s.day)
	removed_resources = s.removed
	resource_hp = s.resource_hp
	harvested = s.harvested
	looted = s.looted
	pickups = s.pickups
	structures = s.structures
	if world_gen:
		world_gen.edits = TerrainEdit.from_list(s.get("terrain", []))
	explored = Marshalls.base64_to_raw(String(s.get("explored", "")))
	difficulty = int(s.get("difficulty", Difficulty.NORMAL))
	pickups_changed.emit()
	structures_changed.emit()


func _prune_regrown() -> void:
	for id: String in removed_resources.keys():
		if not is_removed(id):
			removed_resources.erase(id)
