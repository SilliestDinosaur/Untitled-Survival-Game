extends Node
## Plays procedural sounds (autoloaded as "Audio").

## Named one-shot sounds, e.g. Audio.play_3d(Audio.sfx.chop, pos)
var sfx := {}

var _steps := {}            # surface -> Array[AudioStreamWAV]
var _variants := {}         # name -> Array[AudioStreamWAV] (picked at random)
var _pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _wind: AudioStreamPlayer
var _ocean: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 42
	for surface in ["grass", "sand", "rock", "snow", "water"]:
		_steps[surface] = []
		for i in 4:
			_steps[surface].append(SoundGen.footstep(surface, _rng))
	for name in ["chop", "clink", "rustle", "thud", "swoosh"]:
		_variants[name] = []
		for i in 3:
			_variants[name].append(_make(name))
		sfx[name] = name
	sfx.land = SoundGen.land()
	sfx.click = SoundGen.blip(660.0, 0.07, 0.22)
	sfx.hover = SoundGen.blip(990.0, 0.035, 0.08)
	sfx.pickup = SoundGen.blip(1320.0, 0.05, 0.1)
	sfx.tree_fall = SoundGen.tree_fall(_rng)
	sfx.munch = SoundGen.munch(_rng)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		p3.attenuation_filter_cutoff_hz = 6000.0
		add_child(p3)
		_pool_3d.append(p3)
	_wind = _loop_player(SoundGen.wind())
	_ocean = _loop_player(SoundGen.ocean())


func _make(name: String) -> AudioStreamWAV:
	match name:
		"chop": return SoundGen.chop(_rng)
		"clink": return SoundGen.clink(_rng)
		"rustle": return SoundGen.rustle(_rng)
		"thud": return SoundGen.thud(_rng)
		_: return SoundGen.swoosh(_rng)


func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
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


## Wind gets louder up high; the ocean gets louder near the shore.
func set_ambience(wind_level: float, ocean_level: float, delta: float) -> void:
	var k := 1.0 - exp(-delta * 1.5)
	_wind.volume_db = lerpf(_wind.volume_db, linear_to_db(maxf(wind_level, 0.0005) * 0.35), k)
	_ocean.volume_db = lerpf(_ocean.volume_db, linear_to_db(maxf(ocean_level, 0.0005) * 0.5), k)
