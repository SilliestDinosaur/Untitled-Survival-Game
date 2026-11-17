extends Node
## Plays procedural sounds (autoloaded as "Audio").

var _steps := {}            # surface -> Array[AudioStreamWAV]
var _land: AudioStreamWAV
var _click: AudioStreamWAV
var _hover: AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
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
	_land = SoundGen.land()
	_click = SoundGen.blip(660.0, 0.07, 0.22)
	_hover = SoundGen.blip(990.0, 0.035, 0.08)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_wind = _loop_player(SoundGen.wind())
	_ocean = _loop_player(SoundGen.ocean())


func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func footstep(surface: String, loudness := 1.0) -> void:
	var list: Array = _steps.get(surface, _steps.grass)
	play(list[_rng.randi() % list.size()], linear_to_db(0.5 * loudness), _rng.randf_range(0.9, 1.1))


func land(strength: float) -> void:
	play(_land, linear_to_db(clampf(strength, 0.2, 1.0) * 0.8), _rng.randf_range(0.9, 1.05))


func click() -> void:
	play(_click, -4.0)


func hover() -> void:
	play(_hover, -8.0, _rng.randf_range(0.97, 1.03))


## Wind gets louder up high; the ocean gets louder near the shore.
func set_ambience(wind_level: float, ocean_level: float, delta: float) -> void:
	var k := 1.0 - exp(-delta * 1.5)
	_wind.volume_db = lerpf(_wind.volume_db, linear_to_db(maxf(wind_level, 0.0005) * 0.35), k)
	_ocean.volume_db = lerpf(_ocean.volume_db, linear_to_db(maxf(ocean_level, 0.0005) * 0.5), k)
