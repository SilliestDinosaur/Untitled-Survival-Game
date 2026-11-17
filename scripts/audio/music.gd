extends Node
## Procedural music (autoloaded as "Music").
##
## Every world gets its own key, scales, motifs and chord progressions from the world seed. A mood
## is picked from what's happening (title screen, calm day, exploring, dusk, night, combat), and
## each mood has its own generative sequencer playing synthesized instruments. When the mood
## changes, the old one fades out while the new one fades in. Now and then the music thins out to
## a quiet stretch so it never feels like a wall of sound.

const STEPS_PER_BAR := 16
const FADE_SECONDS := 5.0

## Scales as semitone offsets.
const SCALES := {
	"major_penta": [0, 2, 4, 7, 9],
	"ionian": [0, 2, 4, 5, 7, 9, 11],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"aeolian": [0, 2, 3, 5, 7, 8, 10],
	"minor_penta": [0, 3, 5, 7, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
}

## Mood recipes. Values are ranges or choices; the world seed picks the exact values.
const MOODS := {
	"title": {"tempo": [62, 72], "scales": ["lydian", "major_penta"], "pad": "pad", "lead": "bell",
		"arp": "", "bass": false, "drums": "", "lead_density": 0.18, "arp_density": 0.0, "volume": -9.0},
	"day": {"tempo": [84, 100], "scales": ["major_penta", "ionian", "mixolydian"], "pad": "pad", "lead": "flute",
		"arp": "pluck", "bass": true, "drums": "light", "lead_density": 0.3, "arp_density": 0.55, "volume": -10.0},
	"explore": {"tempo": [92, 108], "scales": ["lydian", "major_penta", "dorian"], "pad": "pad", "lead": "bell",
		"arp": "pluck", "bass": true, "drums": "travel", "lead_density": 0.35, "arp_density": 0.75, "volume": -10.0},
	"dusk": {"tempo": [70, 80], "scales": ["dorian", "mixolydian"], "pad": "pad", "lead": "flute",
		"arp": "bell", "bass": true, "drums": "", "lead_density": 0.2, "arp_density": 0.3, "volume": -10.0},
	"night": {"tempo": [58, 68], "scales": ["aeolian", "phrygian", "minor_penta"], "pad": "dark_pad", "lead": "bell",
		"arp": "pluck", "bass": true, "drums": "heartbeat", "lead_density": 0.12, "arp_density": 0.22, "volume": -9.0},
	"combat": {"tempo": [118, 132], "scales": ["harmonic_minor", "phrygian"], "pad": "strings", "lead": "strings",
		"arp": "pluck", "bass": true, "drums": "battle", "lead_density": 0.25, "arp_density": 0.9, "volume": -8.0},
}

var mood := ""                     ## current target mood
var combat_heat := 0.0             ## rises when fighting, decays over time
var enabled := true

var _instruments := {}
var _ready_to_play := false
var _task := -1
var _layers := {}                  ## mood -> Layer
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _travel := 0.0                 ## metres moved recently (decays)
var _last_pos := Vector3.INF
var _rest_timer := 0.0             ## time until the next quiet stretch
var _rest_left := 0.0


class Layer:
	var name := ""
	var player: AudioStreamPlayer
	var playback: AudioStreamPlaybackPolyphonic
	var gain := 0.0                ## 0..1 fade
	var target := 0.0
	var recipe: Dictionary
	var tempo := 90.0
	var root := 50                 ## midi root
	var scale: Array = []
	var progression: Array = []    ## scale degrees, one per 2 bars
	var motif: Array = []          ## 16 steps of melody offsets (or null for rests)
	var arp_shape: Array = []
	var step := 0
	var bar := 0
	var clock := 0.0
	var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.75
		reverb.damping = 0.4
		reverb.wet = 0.28
		reverb.dry = 0.85
		AudioServer.add_bus_effect(AudioServer.bus_count - 1, reverb)
	Settings.apply()
	Game.world_changed.connect(_on_world_changed)
	_on_world_changed()


func _on_world_changed() -> void:
	# Re-render instruments with this world's timbres (on a worker thread, music resumes when done).
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	_ready_to_play = false
	for l: Layer in _layers.values():
		l.player.queue_free()
	_layers.clear()
	_seed = Game.world_seed
	var s := _seed
	_task = WorkerThreadPool.add_task(func() -> void: _instruments = Instruments.build(s))


## Called by combat events: getting hit, hitting an animal, an animal charging.
func combat_ping(amount := 1.0) -> void:
	combat_heat = minf(combat_heat + amount, 3.0)


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_ready_to_play = true
	if not _ready_to_play or not enabled:
		return
	combat_heat = maxf(0.0, combat_heat - delta / 10.0)
	_track_travel(delta)
	var want := _choose_mood()
	if want != mood:
		mood = want
		if mood != "combat":
			_rest_timer = maxf(_rest_timer, 40.0)
	# Quiet stretches (not during combat or on the title screen).
	_rest_timer -= delta
	if _rest_timer <= 0.0 and mood not in ["combat", "title"]:
		_rest_left = _rng.randf_range(25.0, 60.0)
		_rest_timer = _rng.randf_range(150.0, 300.0) + _rest_left
	_rest_left = maxf(0.0, _rest_left - delta)
	var resting := _rest_left > 0.0 and mood != "combat"

	if not _layers.has(mood):
		_layers[mood] = _make_layer(mood)
	for name: String in _layers.keys():
		var l: Layer = _layers[name]
		l.target = (0.45 if resting else 1.0) if name == mood else 0.0
		var rate := delta / (FADE_SECONDS * (0.4 if mood == "combat" else 1.0))
		l.gain = move_toward(l.gain, l.target, rate)
		l.player.volume_db = l.recipe.volume + linear_to_db(maxf(l.gain, 0.0001))
		if l.gain <= 0.0 and l.target <= 0.0:
			l.player.queue_free()
			_layers.erase(name)
			continue
		_run(l, delta, resting and name == mood)


func _track_travel(delta: float) -> void:
	_travel = maxf(0.0, _travel - delta * 1.2)
	var cam := get_viewport().get_camera_3d()
	if not cam or Game.save_id == "":
		_last_pos = Vector3.INF
		return
	var p := cam.global_position
	if _last_pos != Vector3.INF:
		var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
		if d < 20.0:   # ignore teleports / respawns
			_travel = minf(_travel + d, 160.0)
	_last_pos = p


func _choose_mood() -> String:
	if Game.save_id == "" or Game.time_paused:
		return "title"
	if combat_heat > 0.6 or (mood == "combat" and combat_heat > 0.15):
		return "combat"
	var st := _light(Game.time_of_day)
	if st.night > 0.7:
		return "night"
	if st.golden > 0.45:
		return "dusk"
	# Sustained travel (roughly a minute of walking) switches day music to the exploring theme.
	if _travel > 90.0 or (mood == "explore" and _travel > 40.0):
		return "explore"
	return "day"


static func _light(t: float) -> Dictionary:
	var elev := sin((t - 0.25) * TAU)
	var day := smoothstep(-0.12, 0.12, elev)
	var golden := (1.0 - smoothstep(0.08, 0.45, absf(elev))) * smoothstep(-0.2, 0.0, elev)
	return {"night": 1.0 - day, "golden": golden}


# --- Composition ---------------------------------------------------------------------

func _make_layer(name: String) -> Layer:
	var l := Layer.new()
	l.name = name
	l.recipe = MOODS[name]
	l.rng.seed = hash([_seed, name])
	var r := l.rng
	l.tempo = r.randf_range(l.recipe.tempo[0], l.recipe.tempo[1])
	# The world has one home key; moods sit on related roots so changes feel connected.
	var home := 45 + (hash([_seed, "key"]) % 12 + 12) % 12          # A2..G#3
	var shift := {"title": 0, "day": 0, "explore": 7, "dusk": 5, "night": -3, "combat": -3}
	l.root = home + int(shift.get(name, 0))
	if l.root > 57:
		l.root -= 12
	var scales: Array = l.recipe.scales
	l.scale = SCALES[scales[r.randi() % scales.size()]]
	l.progression = _progression(l)
	l.motif = _motif(l)
	l.arp_shape = _arp_shape(l)
	l.player = AudioStreamPlayer.new()
	l.player.bus = "Music"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 40
	l.player.stream = poly
	l.player.volume_db = -60.0
	add_child(l.player)
	l.player.play()
	l.playback = l.player.get_stream_playback()
	return l


## Chord roots as scale degrees: starts on the tonic, wanders, and resolves home.
func _progression(l: Layer) -> Array:
	var n := l.scale.size()
	var choices := [0, 2, 3, 4, 5] if n >= 7 else [0, 1, 2, 3, 4]
	var prog := [0]
	for i in 3:
		var d: int = choices[l.rng.randi() % choices.size()]
		while d == prog[-1]:
			d = choices[l.rng.randi() % choices.size()]
		prog.append(d)
	return prog


## A one-bar melody: scale steps (or -99 for rest) with a stepwise contour.
func _motif(l: Layer) -> Array:
	var m := []
	var deg := l.rng.randi_range(0, 4)
	var density: float = l.recipe.lead_density
	for i in STEPS_PER_BAR:
		var on_beat := i % 4 == 0
		if l.rng.randf() < density * (1.8 if on_beat else 0.6):
			deg = clampi(deg + [-2, -1, -1, 1, 1, 2, 0][l.rng.randi() % 7], -2, 9)
			m.append(deg)
		else:
			m.append(-99)
	return m


func _arp_shape(l: Layer) -> Array:
	var shapes := [[0, 2, 4, 2], [0, 4, 2, 4], [0, 2, 4, 7], [4, 2, 0, 2], [0, 4, 7, 4], [0, 1, 2, 4]]
	return shapes[l.rng.randi() % shapes.size()]


func _note(l: Layer, degree: int, octave := 0) -> int:
	var n := l.scale.size()
	var o := floori(float(degree) / n)
	var idx := degree - o * n
	return l.root + int(l.scale[idx]) + 12 * (o + octave)


func _play(l: Layer, inst: String, midi: int, vol_db := 0.0) -> void:
	if not _instruments.has(inst) or not l.playback:
		return
	var info: Dictionary = _instruments[inst]
	var pitch := pow(2.0, (midi - int(info.base)) / 12.0)
	l.playback.play_stream(info.stream, 0.0, vol_db, pitch)


func _hit(l: Layer, inst: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _instruments.has(inst) or not l.playback:
		return
	l.playback.play_stream(_instruments[inst].stream, 0.0, vol_db, pitch * l.rng.randf_range(0.97, 1.03))


func _run(l: Layer, delta: float, resting: bool) -> void:
	l.clock += delta
	var step_len := 60.0 / l.tempo / 4.0
	var guard := 0
	while l.clock >= step_len and guard < 4:
		l.clock -= step_len
		guard += 1
		_step(l, resting)
		l.step += 1
		if l.step >= STEPS_PER_BAR:
			l.step = 0
			l.bar += 1
			# Every 8 bars the melody mutates a little; every 32 a new motif and progression.
			if l.bar % 8 == 0:
				var i := l.rng.randi() % STEPS_PER_BAR
				l.motif[i] = -99 if l.motif[i] != -99 else l.rng.randi_range(0, 6)
			if l.bar % 32 == 0:
				l.motif = _motif(l)
				l.progression = _progression(l)
				l.arp_shape = _arp_shape(l)


func _step(l: Layer, resting: bool) -> void:
	var r := l.rng
	var rc := l.recipe
	var chord_deg: int = l.progression[(l.bar / 2) % l.progression.size()]
	var s := l.step
	# Pad chord at the start of every two bars.
	if s == 0 and l.bar % 2 == 0:
		var pad: String = rc.pad
		for k in [0, 2, 4]:
			_play(l, pad, _note(l, chord_deg + k, 1 if pad != "dark_pad" else 0), -6.0 if pad == "strings" else -3.0)
		if r.randf() < 0.4:
			_play(l, pad, _note(l, chord_deg + 6, 1), -9.0)   # colour tone
	if resting:
		return
	# Bass
	if rc.bass:
		var pattern := [0] if rc.drums in ["", "heartbeat"] else ([0, 8] if rc.drums != "battle" else [0, 3, 6, 8, 11, 14])
		if s in pattern:
			_play(l, "bass", _note(l, chord_deg, -1), -4.0 if s == 0 else -8.0)
	# Arpeggio
	var arp: String = rc.arp
	if arp != "" and s % 2 == 0 and r.randf() < rc.arp_density:
		var k: int = l.arp_shape[(s / 2) % l.arp_shape.size()]
		_play(l, arp, _note(l, chord_deg + k, 1), -10.0 + r.randf_range(-2.0, 0.0))
	# Melody (sits out some bars so it breathes)
	var lead_bar := (l.bar / 4) % 3 != 2
	if lead_bar and l.motif[s] != -99:
		var lead: String = rc.lead
		_play(l, lead, _note(l, int(l.motif[s]) + chord_deg / 2, 1), -7.0 if lead != "strings" else -11.0)
	# Percussion
	match rc.drums:
		"light":
			if s % 4 == 2 and r.randf() < 0.7:
				_hit(l, "shaker", -14.0)
			if s == 0 and l.bar % 2 == 0:
				_hit(l, "kick", -12.0)
		"travel":
			if s % 2 == 1:
				_hit(l, "shaker", -15.0 + (3.0 if s % 4 == 3 else 0.0))
			if s in [0, 10]:
				_hit(l, "kick", -10.0)
			if s == 12 and r.randf() < 0.5:
				_hit(l, "rim", -14.0)
		"heartbeat":
			if s == 0 or s == 3:
				_hit(l, "kick", -14.0 if s == 0 else -18.0, 0.8)
		"battle":
			if s % 4 == 0:
				_hit(l, "kick", -6.0)
			if s in [6, 14] or (s == 15 and r.randf() < 0.4):
				_hit(l, "tom", -8.0, 1.0 if s != 15 else 1.3)
			if s % 2 == 1:
				_hit(l, "shaker", -14.0)
			if s == 4 or s == 12:
				_hit(l, "rim", -11.0)
