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
			"world_size": float(data.get("world_size", 2048.0)),
			"world_v": int(data.get("world_v", 1)),
			"last_played": float(data.get("last_played", 0)),
			"created": float(data.get("created", 0)),
			"play_time": float(data.get("play_time", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.last_played > b.last_played)
	return out


## A world's save. If the file is missing or unreadable (a crash, a full disk), the copy kept from the save before
## it is used, then a save that was written but never swapped in, so a bad write loses minutes, not the world.
static func read(id: String) -> Dictionary:
	for path: String in _all_paths(id):
		var data := _read_file(path)
		if not data.is_empty():
			return data
	return {}


## A world's file and its fallbacks, newest first: the last good save, a half-written one, then the older snapshots.
static func _all_paths(id: String) -> Array:
	var out := [_path(id), _path(id) + ".bak", _path(id) + ".tmp"]
	for k in range(1, SNAPSHOTS + 1):
		out.append(_path(id) + ".old%d" % k)
	return out


## Older snapshots kept besides the last save (a save that loads but went wrong, not just a broken file, can be
## gone back from by hand): one every SNAPSHOT_EVERY seconds, the oldest dropped.
const SNAPSHOTS := 3
const SNAPSHOT_EVERY := 600


static func _snapshot(id: String) -> void:
	var path := _path(id)
	if not FileAccess.file_exists(path):
		return
	var newest := path + ".old1"
	if FileAccess.file_exists(newest) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(newest) < SNAPSHOT_EVERY:
		return
	for k in range(SNAPSHOTS, 1, -1):
		var from := path + ".old%d" % (k - 1)
		if FileAccess.file_exists(from):
			DirAccess.copy_absolute(from, path + ".old%d" % k)
	DirAccess.copy_absolute(path, newest)


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
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
	var path := _path(id)
	if FileAccess.file_exists(path):
		_snapshot(id)
		DirAccess.copy_absolute(path, path + ".bak")   # the last good save, in case this one is ever unreadable
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK and FileAccess.file_exists(path):
		# Some systems won't rename over an existing file: clear it (the copy above keeps it) and try again.
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("Could not save world %s (error %d)" % [id, err])
		return false
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
	for path: String in _all_paths(id):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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
