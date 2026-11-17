extends Node
## Player settings (autoloaded as "Settings"). Saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

## Render distance presets, in chunks (64 m each).
const VIEW_DISTANCES := {"Low": 4, "Medium": 6, "High": 8, "Ultra": 10}
const QUALITY_LEVELS := ["Low", "Medium", "High"]

var mouse_sensitivity := 1.0     ## multiplier
var fov := 80.0
var view_distance := "Medium"
var quality := "Medium"
var master_volume := 0.8
var show_fps := false
var last_seed := 0


func _ready() -> void:
	load_settings()
	apply()


func view_radius() -> int:
	return VIEW_DISTANCES.get(view_distance, 6)


## How much grass/flowers to place near the player.
func grass_density() -> float:
	return {"Low": 0.4, "Medium": 1.0, "High": 1.5}.get(quality, 1.0)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	fov = cfg.get_value("video", "fov", fov)
	view_distance = cfg.get_value("video", "view_distance", view_distance)
	quality = cfg.get_value("video", "quality", quality)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	last_seed = cfg.get_value("game", "last_seed", last_seed)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "view_distance", view_distance)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("game", "last_seed", last_seed)
	cfg.save(PATH)


## Call after changing any value.
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	changed.emit()
