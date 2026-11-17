extends Node3D
## Game flow: title screen (with a flyover of the island) -> loading -> playing <-> paused.

enum State { TITLE, LOADING, PLAYING, PAUSED }

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var menu_camera: Camera3D = $MenuCamera

var state := State.TITLE
var _ui: CanvasLayer
var _hud: HUD
var _title: Menus.TitleScreen
var _pause: Menus.PauseMenu
var _settings: Menus.SettingsPanel
var _loading: Menus.LoadingScreen
var _spawn := Vector3.ZERO
var _orbit := 0.0
var _ambience_timer := 0.0
var _ocean_level := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.process_mode = Node.PROCESS_MODE_PAUSABLE

	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_hud = HUD.new()
	_hud.setup(player, world)
	root.add_child(_hud)
	_title = Menus.TitleScreen.new()
	root.add_child(_title)
	_pause = Menus.PauseMenu.new()
	root.add_child(_pause)
	_settings = Menus.SettingsPanel.new()
	root.add_child(_settings)
	_loading = Menus.LoadingScreen.new()
	root.add_child(_loading)

	_title.play_pressed.connect(_start_loading)
	_title.seed_requested.connect(_change_seed)
	_title.settings_pressed.connect(func() -> void: _settings.show())
	_pause.resume_pressed.connect(_resume)
	_pause.settings_pressed.connect(func() -> void: _settings.show())
	_pause.quit_to_title_pressed.connect(_to_title)
	_settings.closed.connect(func() -> void: _settings.hide())

	# Dying sends you back through the loading screen so the spawn area is ready.
	player.stats.died.connect(func() -> void: _start_loading("You collapsed... waking up on"))

	world.focus = menu_camera
	_new_world_loaded()
	_to_title()


func _change_seed(seed_value: int) -> void:
	Game.new_world(seed_value)
	world.reset()
	_new_world_loaded()
	_title.refresh()


func _new_world_loaded() -> void:
	_spawn = Game.world_gen.find_spawn_point()
	player.spawn_point = _spawn


func _to_title() -> void:
	get_tree().paused = false
	state = State.TITLE
	player.set_active(false)
	world.focus = menu_camera
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.hide()
	_pause.hide()
	_settings.hide()
	_loading.hide()
	_title.show()
	_title.refresh()


func _start_loading(heading := "GENERATING") -> void:
	state = State.LOADING
	player.set_active(false)
	_hud.hide()
	_title.hide()
	_loading.set_world(Game.world_name, heading)
	_loading.modulate.a = 1.0
	_loading.show()
	player.global_position = _spawn + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0, randf() * TAU, 0)
	player.stats.reset()
	world.focus = player


func _start_playing() -> void:
	state = State.PLAYING
	player.set_active(true)
	_hud.show()
	_hud.show_arrival(Game.world_name)
	var tw := create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_loading.hide)


func _pause_game() -> void:
	state = State.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause.show()


func _resume() -> void:
	state = State.PLAYING
	get_tree().paused = false
	_pause.hide()
	_settings.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _settings.visible:
		_settings.hide()
	elif state == State.PLAYING:
		_pause_game()
	elif state == State.PAUSED:
		_resume()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match state:
		State.TITLE:
			_fly_menu_camera(delta)
		State.LOADING:
			_loading.set_progress(world.area_progress(_spawn, 1))
			if world.is_area_ready(_spawn, 1):
				_start_playing()
	if state == State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _settings.visible:
		# Clicking back into the game window recaptures the mouse.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ambience(delta)


## Slow orbit around the spawn area for the title screen background.
func _fly_menu_camera(delta: float) -> void:
	_orbit += delta * 0.035
	var radius := 120.0
	var pos := _spawn + Vector3(cos(_orbit) * radius, 0.0, sin(_orbit) * radius)
	var ground: float = Game.world_gen.get_height(pos.x, pos.z)
	pos.y = maxf(ground, 0.0) + 38.0
	menu_camera.global_position = menu_camera.global_position.lerp(pos, 1.0 - exp(-2.0 * delta)) if menu_camera.global_position.distance_to(pos) < 200.0 else pos
	menu_camera.look_at(_spawn + Vector3.UP * 12.0)


func _update_ambience(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var p := cam.global_position
	# Check for ocean around the listener a couple of times per second.
	_ambience_timer -= delta
	if _ambience_timer <= 0.0:
		_ambience_timer = 0.5
		var water := 0
		for i in 8:
			var a := TAU * i / 8.0
			if Game.world_gen.get_height(p.x + cos(a) * 45.0, p.z + sin(a) * 45.0) < 0.0:
				water += 1
		_ocean_level = clampf(water / 4.0, 0.0, 1.0) * clampf(1.0 - p.y / 50.0, 0.1, 1.0)
	var wind := 0.25 + clampf((p.y - 10.0) / 60.0, 0.0, 0.75)
	Audio.set_ambience(wind, _ocean_level, delta)
