extends Node
## Player settings (autoloaded as "Settings"). Saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

## Render distance presets, in chunks (64 m each).
const VIEW_DISTANCES := {"Low": 4, "Medium": 6, "High": 8, "Ultra": 10}
const QUALITY_LEVELS := ["Low", "Medium", "High"]
## Model detail: multiplies the number of segments in every generated plant, rock and animal.
const MODEL_DETAIL := {"Low": 0.55, "Medium": 0.8, "High": 1.0, "Ultra": 1.5}
const SHADOW_LEVELS := ["Off", "Low", "Medium", "High", "Ultra"]
const AA_MODES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "TAA"]
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]
const GRASS_LEVELS := {"Off": 0.0, "Low": 0.45, "Medium": 1.0, "High": 1.5, "Ultra": 2.0}

## Remappable actions, in the order the Controls tab lists them: [action, label, default events].
## Events are "key:<keycode>" or "mouse:<button index>".
const ACTIONS := [
	["move_forward", "Move forward", ["key:%d" % KEY_W]],
	["move_back", "Move back", ["key:%d" % KEY_S]],
	["move_left", "Move left", ["key:%d" % KEY_A]],
	["move_right", "Move right", ["key:%d" % KEY_D]],
	["jump", "Jump / swim up", ["key:%d" % KEY_SPACE]],
	["sprint", "Sprint", ["key:%d" % KEY_SHIFT]],
	["attack", "Swing / destroy / eat", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	["interact", "Harvest / pick up / open", ["key:%d" % KEY_E]],
	["drop", "Drop held item", ["key:%d" % KEY_Q]],
	["inventory", "Satchel", ["key:%d" % KEY_TAB]],
	["slot_1", "Hotbar 1", ["key:%d" % KEY_1]],
	["slot_2", "Hotbar 2", ["key:%d" % KEY_2]],
	["slot_3", "Hotbar 3", ["key:%d" % KEY_3]],
	["slot_4", "Hotbar 4", ["key:%d" % KEY_4]],
	["slot_5", "Hotbar 5", ["key:%d" % KEY_5]],
	["slot_6", "Hotbar 6", ["key:%d" % KEY_6]],
	["slot_7", "Hotbar 7", ["key:%d" % KEY_7]],
	["slot_8", "Hotbar 8", ["key:%d" % KEY_8]],
	["debug_items", "Debug item menu", ["key:%d" % KEY_F9]],
	["toggle_debug", "Debug info", ["key:%d" % KEY_F3]],
]
## Not remappable (so you can always get back to the menu).
const FIXED := {"pause": ["key:%d" % KEY_ESCAPE]}

var mouse_sensitivity := 1.0     ## multiplier
var invert_y := false
var fov := 80.0
var view_distance := "Medium"
var quality := "Medium"
var model_detail := "High"
var shadow_quality := "High"
var anti_aliasing := "MSAA 2x"
var render_scale := 1.0
var ambient_occlusion := true
var glow := true
var vsync := false
var fps_cap := 0
var grass := "Medium"
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 1.0
var show_fps := false
var bindings := {}               ## action -> Array[String] overrides


func _ready() -> void:
	load_settings()
	apply()


func view_radius() -> int:
	return VIEW_DISTANCES.get(view_distance, 6)


## How much grass/flowers/clutter to place near the player.
func grass_density() -> float:
	return GRASS_LEVELS.get(grass, 1.0)


func mesh_detail() -> float:
	return MODEL_DETAIL.get(model_detail, 1.0)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	bindings = cfg.get_value("input", "bindings", {})
	fov = cfg.get_value("video", "fov", fov)
	view_distance = cfg.get_value("video", "view_distance", view_distance)
	quality = cfg.get_value("video", "quality", quality)
	model_detail = cfg.get_value("video", "model_detail", model_detail)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	shadow_quality = cfg.get_value("video", "shadow_quality", shadow_quality)
	anti_aliasing = cfg.get_value("video", "anti_aliasing", anti_aliasing)
	render_scale = cfg.get_value("video", "render_scale", render_scale)
	ambient_occlusion = cfg.get_value("video", "ambient_occlusion", ambient_occlusion)
	glow = cfg.get_value("video", "glow", glow)
	vsync = cfg.get_value("video", "vsync", vsync)
	fps_cap = cfg.get_value("video", "fps_cap", fps_cap)
	grass = cfg.get_value("video", "grass", grass)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "bindings", bindings)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "view_distance", view_distance)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "model_detail", model_detail)
	cfg.set_value("video", "show_fps", show_fps)
	for k: String in ["shadow_quality", "anti_aliasing", "render_scale", "ambient_occlusion", "glow", "vsync", "fps_cap", "grass"]:
		cfg.set_value("video", k, get(k))
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(PATH)


## Call after changing any value.
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	for pair: Array in [["Music", music_volume], ["SFX", sfx_volume]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(pair[1], 0.0001)))
	changed.emit()


# --- Key bindings -----------------------------------------------------------------

## Rebuild the InputMap from defaults + the player's overrides.
func apply_bindings() -> void:
	for entry: Array in ACTIONS:
		_set_action(entry[0], bindings.get(entry[0], entry[2]))
	for action: String in FIXED:
		_set_action(action, FIXED[action])


func binding_of(action: String) -> String:
	for entry: Array in ACTIONS:
		if entry[0] == action:
			var list: Array = bindings.get(action, entry[2])
			return list[0] if not list.is_empty() else ""
	return ""


## Bind an action to one event; if another action used it, that action gets this one's old key.
func rebind(action: String, event_code: String) -> void:
	var previous := binding_of(action)
	for entry: Array in ACTIONS:
		if entry[0] != action and binding_of(entry[0]) == event_code:
			bindings[entry[0]] = [previous]
	bindings[action] = [event_code]
	apply_bindings()
	save_settings()


func reset_bindings() -> void:
	bindings = {}
	apply_bindings()
	save_settings()


static func event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(parts[1]) as MouseButton
		return mb
	var k := InputEventKey.new()
	k.physical_keycode = int(parts[1]) as Key
	return k


static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return "key:%d" % key
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


## Human-readable name for a binding, e.g. "W", "Space", "Left Click".
static func code_label(code: String) -> String:
	var parts := code.split(":")
	if parts.size() != 2:
		return "-"
	if parts[0] == "mouse":
		match int(parts[1]):
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			_: return "Mouse %s" % parts[1]
	return OS.get_keycode_string(int(parts[1]) as Key)


func _set_action(action: String, codes: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	for c: String in codes:
		var ev := event_from_code(c)
		if ev:
			InputMap.action_add_event(action, ev)
