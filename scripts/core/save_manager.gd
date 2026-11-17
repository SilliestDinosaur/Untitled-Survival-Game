class_name SaveManager
extends RefCounted
## World saves on disk: user://saves/<id>.json, one file per world.
## A save stores the seed (the world regenerates from it) plus everything that changed:
## gathered/damaged resources, the player's position, stats and inventory, play time.

const DIR := "user://saves"
const VERSION := 1


static func _path(id: String) -> String:
	return "%s/%s.json" % [DIR, id]


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## All saves, most recently played first. Each entry: {id, name, seed, last_played, play_time, created}
static func list_saves() -> Array[Dictionary]:
	_ensure_dir()
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if not dir:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data := read(f.get_basename())
		if data.is_empty():
			continue
		out.append({
			"id": f.get_basename(),
			"name": data.get("name", "Unnamed"),
			"world_name": data.get("world_name", ""),
			"seed": int(data.get("seed", 0)),
			"last_played": float(data.get("last_played", 0)),
			"created": float(data.get("created", 0)),
			"play_time": float(data.get("play_time", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.last_played > b.last_played)
	return out


static func read(id: String) -> Dictionary:
	var f := FileAccess.open(_path(id), FileAccess.READ)
	if not f:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func write(id: String, data: Dictionary) -> bool:
	_ensure_dir()
	data.version = VERSION
	# Write to a temp file first so a crash mid-save can't corrupt the world.
	var tmp := _path(id) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if not f:
		push_error("Could not save world %s" % id)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, _path(id))
	return true


## Make a new, empty save for a seed. Returns its id.
static func create(seed_value: int, display_name: String) -> String:
	var id := "world_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	var now := Time.get_unix_time_from_system()
	write(id, {
		"name": display_name,
		"world_name": NameGen.world_name(seed_value),
		"seed": seed_value,
		"created": now,
		"last_played": now,
		"play_time": 0.0,
	})
	return id


static func delete(id: String) -> void:
	DirAccess.remove_absolute(_path(id))


static func rename(id: String, new_name: String) -> void:
	var data := read(id)
	if data.is_empty():
		return
	data.name = new_name.strip_edges() if new_name.strip_edges() != "" else data.get("name", "Unnamed")
	write(id, data)


## "2h 14m", "35m", "< 1m"
static func format_play_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 1:
		return "< 1m"
	if m < 60:
		return "%dm" % m
	return "%dh %02dm" % [m / 60, m % 60]


## "Just now", "5 minutes ago", "Yesterday", or a date.
static func format_when(unix: float) -> String:
	var ago := Time.get_unix_time_from_system() - unix
	if ago < 90:
		return "Just now"
	if ago < 3600:
		var m := int(ago / 60)
		return "1 minute ago" if m == 1 else "%d minutes ago" % m
	if ago < 86400:
		var h := int(ago / 3600)
		return "1 hour ago" if h == 1 else "%d hours ago" % h
	if ago < 172800:
		return "Yesterday"
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]
