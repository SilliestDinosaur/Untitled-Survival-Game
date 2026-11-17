extends Node
## Global game state (autoloaded as "Game").
##
## Anything that defines "what the world is" lives here, separate from visuals and input.
## When co-op is added, this is the stuff the host owns and syncs to clients.

signal world_changed

const WORLD_SIZE := 2048.0   ## Map is WORLD_SIZE x WORLD_SIZE meters (about 2 km).
const CHUNK_SIZE := 64.0     ## Terrain is streamed in square chunks of this size.
const SEA_LEVEL := 0.0
const MAX_SEED := 999_999_999

## Everything about a world comes from its seed: terrain, biomes, colors, plants, names.
## For multiplayer, clients only need the seed (plus changes like chopped trees).
var world_seed: int = 0
var world_name := ""
var palette: WorldPalette
var world_gen: WorldGen
var flora: FloraLibrary

## Resource ids that were gathered/destroyed (chunks skip these when regenerating).
var removed_resources := {}


func _ready() -> void:
	_setup_input()
	var start_seed: int = Settings.last_seed if Settings.last_seed > 0 else random_seed()
	new_world(start_seed)


func random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, MAX_SEED)


func new_world(seed_value: int) -> void:
	world_seed = clampi(seed_value, 1, MAX_SEED)
	world_name = NameGen.world_name(world_seed)
	palette = WorldPalette.new(world_seed)
	world_gen = WorldGen.new(world_seed, palette)
	flora = FloraLibrary.new(world_seed, palette)
	removed_resources = {}
	Settings.last_seed = world_seed
	Settings.save_settings()
	world_changed.emit()


## Input actions are registered in code so they're easy to read and change in one place.
func _setup_input() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"pause": [KEY_ESCAPE],
		"toggle_debug": [KEY_F3],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
