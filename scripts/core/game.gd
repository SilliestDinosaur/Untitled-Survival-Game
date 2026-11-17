extends Node
## Global game state (autoloaded as "Game").
##
## Anything that defines "what the world is" lives here, separate from visuals and input.
## When co-op is added, this is the stuff the host owns and syncs to clients.

signal world_changed
signal assets_rebuilt   ## meshes were regenerated (model detail setting changed)

const WORLD_SIZE := 2048.0   ## Map is WORLD_SIZE x WORLD_SIZE meters (about 2 km).
const CHUNK_SIZE := 64.0     ## Terrain is streamed in square chunks of this size.
const SEA_LEVEL := 0.0
const MAX_SEED := 999_999_999
const REGROW_SECONDS := 900.0   ## gathered trees/rocks grow back after 15 minutes of play

## Everything about a world comes from its seed: terrain, biomes, colors, plants, names.
## For multiplayer, clients only need the seed (plus changes like chopped trees).
var world_seed: int = 0
var world_name := ""
var palette: WorldPalette
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
## Items lying in the world: entity id -> {id, item, count, dur, pos: [x, y, z]}.
var pickups := {}
## Counter for network-stable entity ids (pickups now; more entity kinds later).
var next_entity_id := 1

## Every player's inventory by player id. Single-player uses LOCAL_PLAYER; a multiplayer host
## would keep one per connected peer (keyed by peer id) and be the only one that changes them.
const LOCAL_PLAYER := 1
var inventories := {}

signal pickups_changed
const HARVEST_REGROW := 240.0   ## seconds before a hand-harvested plant can be harvested again

## The save file this session is playing ("" = not saved yet / title preview).
var save_id := ""
var save_name := ""
var play_time := 0.0


func _ready() -> void:
	Settings.apply_bindings()
	var saves := SaveManager.list_saves()
	new_world(saves[0].seed if not saves.is_empty() else random_seed())
	Settings.changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	if save_id != "" and not get_tree().paused:
		play_time += delta


func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, MAX_SEED)


## Build everything that comes from the seed. Clears per-save state.
func new_world(seed_value: int) -> void:
	world_seed = clampi(seed_value, 1, MAX_SEED)
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
	next_entity_id = 1
	for pid: int in inventories:
		inventories[pid].clear()
	save_id = ""
	save_name = ""
	play_time = 0.0
	world_changed.emit()


func _build_assets() -> void:
	MeshKit.detail = Settings.mesh_detail()
	ItemDB.build(world_seed, palette)   # first: plants and ore use item colors
	flora = FloraLibrary.new(world_seed, palette)
	fauna = FaunaLibrary.new(world_seed, palette)
	MeshKit.detail = 1.0


var _last_detail := ""

func _on_settings_changed() -> void:
	if _last_detail == "":
		_last_detail = Settings.model_detail
	if Settings.model_detail != _last_detail and palette:
		_last_detail = Settings.model_detail
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
	new_world(int(data.seed))
	save_id = id
	save_name = data.get("name", world_name)
	play_time = float(data.get("play_time", 0.0))
	removed_resources = data.get("removed", {})
	resource_hp = data.get("resource_hp", {})
	harvested = data.get("harvested", {})
	known_items = data.get("known_items", {})
	looted = data.get("looted", {})
	pickups = data.get("pickups", {})
	next_entity_id = int(data.get("next_entity_id", 1))
	pickups_changed.emit()
	# Saves keep a map of players (the local one is LOCAL_PLAYER); older saves had one player.
	var players: Dictionary = data.get("players", {})
	if players.is_empty() and data.has("player"):
		players = {str(LOCAL_PLAYER): data.player}
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
		"created": SaveManager.read(save_id).get("created", Time.get_unix_time_from_system()),
		"last_played": Time.get_unix_time_from_system(),
		"play_time": play_time,
		"removed": removed_resources,
		"resource_hp": resource_hp,
		"harvested": harvested,
		"known_items": known_items,
		"looted": looted,
		"pickups": pickups,
		"next_entity_id": next_entity_id,
		"players": {str(LOCAL_PLAYER): player_data},
	})


func _prune_regrown() -> void:
	for id: String in removed_resources.keys():
		if not is_removed(id):
			removed_resources.erase(id)
