extends Node
## Plays procedural sounds (autoloaded as "Audio").

## Named one-shot sounds, e.g. Audio.play_3d(Audio.sfx.chop, pos)
var sfx := {}

var _steps := {}            # surface -> Array[AudioStreamWAV]
var _variants := {}         # name -> Array[AudioStreamWAV] (picked at random)
var _pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer
var _cave: AudioStreamPlayer
var _ocean: AudioStreamPlayer
var _river: AudioStreamPlayer
var _jungle: AudioStreamPlayer
var _rush: Array = []   ## cascades' rush players (started once the river loop is made)
var _rng := RandomNumberGenerator.new()
var _build_task := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 42
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for surface in ["grass", "sand", "rock", "snow", "water", "wood"]:
		_steps[surface] = []
		for i in 4:
			_steps[surface].append(SoundGen.footstep(surface, _rng))
	# Sounds with a few takes each, picked at random so repeats don't sound copied. They take most of a second to
	# make, so they're made on a worker thread; until then those names just play nothing.
	for name: String in VARIANTS:
		sfx[name] = name
	_build_task = WorkerThreadPool.add_task(_build_variants)
	sfx.land = SoundGen.land()
	sfx.click = SoundGen.tick(1.0, 0.22)
	sfx.hover = SoundGen.tick(1.35, 0.08)
	sfx.slot = SoundGen.tick(0.75, 0.2)
	sfx.pickup = SoundGen.pop()
	sfx.chime = SoundGen.chime()
	sfx.open = SoundGen.panel(true)
	sfx.close = SoundGen.panel(false)
	sfx.error = SoundGen.error()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		p3.attenuation_filter_cutoff_hz = 6000.0
		p3.bus = "SFX"
		add_child(p3)
		_pool_3d.append(p3)
	_wind = _loop_player(SoundGen.wind())
	_ocean = _loop_player(SoundGen.ocean())
	_cave = _loop_player(SoundGen.cave_tone())
	_river = _loop_player(null)
	_jungle = _loop_player(null)
	Settings.apply()


## name -> how many takes to make.
const VARIANTS := {"chop": 4, "clink": 4, "ore": 3, "rustle": 4, "thud": 3, "swoosh": 4, "tool_break": 2, "hurt": 3,
	"tree_fall": 2, "munch": 3, "gulp": 2, "place_wood": 3, "place_stone": 3, "hammer": 3, "creak": 2, "chest": 2,
	"splash": 3, "stroke": 4, "drip": 3, "rumble": 3, "squeak": 3}


func _build_variants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var made := {}
	for name: String in VARIANTS:
		made[name] = []
		for i in int(VARIANTS[name]):
			made[name].append(_make(name, rng))
	var fire := SoundGen.fire_loop()
	var river := SoundGen.river_loop()
	var jungle := SoundGen.jungle_loop()
	_finish_build.call_deferred(made, fire, river, jungle)


func _finish_build(made: Dictionary, fire: AudioStreamWAV, river: AudioStreamWAV, jungle: AudioStreamWAV) -> void:
	_jungle.stream = jungle
	_jungle.play()
	_variants.merge(made, true)
	sfx.fire = fire
	_river.stream = river
	_river.play()
	for p: AudioStreamPlayer3D in _rush:
		if is_instance_valid(p) and p.stream == null:
			p.stream = river
	WorkerThreadPool.wait_for_task_completion(_build_task)
	_build_task = -1


## Waits for the sounds being made in the background (for tests and quitting).
func wait_ready() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1


func _exit_tree() -> void:
	wait_ready()


func _make(name: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var _rng := rng
	match name:
		"chop": return SoundGen.chop(_rng)
		"clink": return SoundGen.clink(_rng)
		"ore": return SoundGen.ore_hit(_rng)
		"rustle": return SoundGen.rustle(_rng)
		"thud": return SoundGen.thud(_rng)
		"tool_break": return SoundGen.tool_break(_rng)
		"hurt": return SoundGen.hurt(_rng)
		"tree_fall": return SoundGen.tree_fall(_rng)
		"munch": return SoundGen.munch(_rng)
		"gulp": return SoundGen.gulp(_rng)
		"place_wood": return SoundGen.place_wood(_rng)
		"place_stone": return SoundGen.place_stone(_rng)
		"hammer": return SoundGen.hammer(_rng)
		"creak": return SoundGen.creak(_rng)
		"chest": return SoundGen.chest(_rng)
		"splash": return SoundGen.splash(_rng)
		"stroke": return SoundGen.stroke(_rng)
		"drip": return SoundGen.drip(_rng)
		"rumble": return SoundGen.rumble(_rng)
		"squeak": return SoundGen.squeak(_rng)
		_: return SoundGen.swoosh(_rng)


func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = -80.0
	add_child(p)
	if stream:
		p.play()
	return p


func _resolve(s: Variant) -> AudioStream:
	if s is String:
		var list: Array = _variants.get(s, [])
		return list[_rng.randi() % list.size()] if not list.is_empty() else null
	return s


## Non-positional sound (UI, the player's own actions).
func play(sound: Variant, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _resolve(sound)
	if not stream:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
			p.play()
			return


## Sound coming from a point in the world.
func play_3d(sound: Variant, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _resolve(sound)
	if not stream:
		return
	for p in _pool_3d:
		if not p.playing:
			p.stream = stream
			p.global_position = pos
			p.volume_db = volume_db
			p.pitch_scale = pitch * _rng.randf_range(0.93, 1.07)
			p.play()
			return


func footstep(surface: String, loudness := 1.0) -> void:
	var list: Array = _steps.get(surface, _steps.grass)
	play(list[_rng.randi() % list.size()], linear_to_db(0.5 * loudness), _rng.randf_range(0.9, 1.1))


func land(strength: float) -> void:
	play(sfx.land, linear_to_db(clampf(strength, 0.2, 1.0) * 0.8), _rng.randf_range(0.9, 1.05))


func click() -> void:
	play(sfx.click, -4.0)


func hover() -> void:
	play(sfx.hover, -8.0, _rng.randf_range(0.97, 1.03))


## Wind gets louder up high; the ocean gets louder near the shore; underground the open air fades and the cave's own
## hollow tone takes over (`cave_level` 0 outside .. 1 deep in).
func set_ambience(wind_level: float, ocean_level: float, delta: float, cave_level := 0.0, river_level := 0.0, jungle_level := 0.0) -> void:
	var k := 1.0 - exp(-delta * 1.5)
	_jungle.volume_db = lerpf(_jungle.volume_db, linear_to_db(maxf(jungle_level * (1.0 - cave_level), 0.0005) * 0.5), k)
	_river.volume_db = lerpf(_river.volume_db, linear_to_db(maxf(river_level * (1.0 - cave_level), 0.0005) * 0.45), k)
	wind_level *= 1.0 - cave_level * 0.85
	ocean_level *= 1.0 - cave_level
	_cave.volume_db = lerpf(_cave.volume_db, linear_to_db(maxf(cave_level, 0.0005) * 0.5), k)
	_wind.volume_db = lerpf(_wind.volume_db, linear_to_db(maxf(wind_level, 0.0005) * 0.35), k)
	_ocean.volume_db = lerpf(_ocean.volume_db, linear_to_db(maxf(ocean_level, 0.0005) * 0.5), k)


## A looping crackle for a fire, as a positional player under `parent` (the caller frees it with the fire).
func fire_loop(parent: Node3D) -> AudioStreamPlayer3D:
	if not sfx.has("fire"):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = sfx.fire
	p.unit_size = 3.0
	p.max_distance = 30.0
	p.volume_db = -4.0
	p.bus = "SFX"
	p.autoplay = true
	parent.add_child(p)
	if p.is_inside_tree():
		p.play(_rng.randf() * 5.0)
	return p


## The rush of white water at a cascade, as a positional loop under `parent` (lower and louder than the babble).
func rush_loop(parent: Node3D) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 5.0
	p.max_distance = 60.0
	p.volume_db = 2.0
	p.pitch_scale = 0.7
	p.bus = "SFX"
	parent.add_child(p)
	_rush.append(p)
	if _river and _river.stream:
		p.stream = _river.stream   # (started and stopped by distance: see Rivers.update_cascades)
	return p


func error_buzz() -> void:
	play(sfx.error, -6.0)


func slot() -> void:
	play(sfx.slot, -6.0, _rng.randf_range(0.95, 1.08))


## The sound of eating a food: soft and wet things are gulped, bandages rustle, the rest is crunched.
func eat_sound(id: String) -> String:
	if id == "bandage":
		return "rustle"
	if id in ["stew", "cactus_flesh"] or id.contains("soup") or id.contains("tea") or id.contains("water"):
		return "gulp"
	return "munch"
