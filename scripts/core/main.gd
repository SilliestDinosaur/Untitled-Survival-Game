extends Node3D
## Game flow: title screen (with a flyover of the island) -> new / load world -> loading ->
## playing <-> paused. Handles saving: autosave, save on pause / quit / window close.

enum State { TITLE, LOADING, PLAYING, PAUSED }

const AUTOSAVE_SECONDS := 120.0

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var menu_camera: Camera3D = $MenuCamera

var state := State.TITLE
var _ui: CanvasLayer
var _hud: HUD
var _title: Menus.TitleScreen
var _new_world: Menus.NewWorldPanel
var _load: Menus.LoadPanel
var _pause: Menus.PauseMenu
var _settings: Menus.SettingsPanel
var _loading: Menus.LoadingScreen
var _inventory: InventoryUI.InventoryPanel
var _debug_items: Menus.DebugItems
var _multiplayer: Menus.MultiplayerPanel
var _wildlife: Node3D
var _spawn := Vector3.ZERO
var _load_pos := Vector3.ZERO       ## where the player will appear once loading finishes
var _pending_player := {}           ## saved player data to apply after loading
var _orbit := 0.0
var _ambience_timer := 0.0
var _ocean_level := 0.0
var _autosave := AUTOSAVE_SECONDS
var _cave_features: CaveFeatures
var _cave_check := 0.0            ## counts down to the next look at whether the player is underground
var _map: WorldMap
var _reveal_timer := 0.0          ## counts down to the next uncovering of the map around the player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().set_auto_accept_quit(false)   # so closing the window saves first

	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_hud = HUD.new()
	root.add_child(_hud)
	_hud.setup(player, world)
	_inventory = InventoryUI.InventoryPanel.new()
	root.add_child(_inventory)
	_inventory.setup(player.inventory, player)
	_map = WorldMap.new()
	root.add_child(_map)
	_map.player = player
	_debug_items = Menus.DebugItems.new()
	root.add_child(_debug_items)
	_debug_items.setup(player.inventory)
	_title = Menus.TitleScreen.new()
	root.add_child(_title)
	_new_world = Menus.NewWorldPanel.new()
	root.add_child(_new_world)
	_load = Menus.LoadPanel.new()
	root.add_child(_load)
	_pause = Menus.PauseMenu.new()
	root.add_child(_pause)
	_settings = Menus.SettingsPanel.new()
	root.add_child(_settings)
	_loading = Menus.LoadingScreen.new()
	root.add_child(_loading)
	_multiplayer = Menus.MultiplayerPanel.new()
	root.add_child(_multiplayer)
	_multiplayer.hide()
	_multiplayer.back_pressed.connect(_back_to_title_menu)
	_title.multiplayer_pressed.connect(func() -> void:
		_title.hide()
		_multiplayer.open())

	_title.continue_pressed.connect(func() -> void:
		var saves := SaveManager.list_saves()
		if not saves.is_empty():
			load_world(saves[0].id))
	_title.new_world_pressed.connect(func() -> void:
		_title.hide()
		_new_world.open())
	_title.load_world_pressed.connect(func() -> void:
		_title.hide()
		_load.open())
	_title.settings_pressed.connect(func() -> void: _settings.show())
	_new_world.back_pressed.connect(_back_to_title_menu)
	_new_world.seed_previewed.connect(_preview_seed)
	_new_world.create_pressed.connect(create_world)
	_load.back_pressed.connect(_back_to_title_menu)
	_load.play_pressed.connect(load_world)
	_pause.resume_pressed.connect(_resume)
	_pause.save_pressed.connect(func() -> void:
		save_now()
		_pause.show_status("Saved."))
	_pause.settings_pressed.connect(func() -> void: _settings.show())
	_pause.quit_to_title_pressed.connect(func() -> void:
		save_now()
		Net.stop()
		_to_title())
	_pause.quit_game_pressed.connect(func() -> void:
		save_now()
		Net.stop()
		get_tree().quit())
	_settings.closed.connect(func() -> void: _settings.hide())

	# Dying drops everything you carried and sends you back to the spawn point.
	player.stats.died.connect(func() -> void:
		player.reset_inventory()
		_start_loading(_spawn, "You collapsed... waking up on")
		save_now())

	# Multiplayer
	Net.main = self
	Net.world = world
	Net.player = player
	Net.joined.connect(_join_world)
	Net.session_ended.connect(func(reason: String) -> void:
		if state != State.TITLE:
			_to_title()
		_multiplayer.hide()
		_title.show()
		_title.show_message(reason))
	Net.player_message.connect(func(t: String) -> void:
		if state in [State.PLAYING, State.PAUSED]:
			_hud.show_hint(t))

	var pickups := preload("res://scripts/world/pickups.gd").new()
	pickups.name = "Pickups"
	add_child(pickups)
	var structures := preload("res://scripts/world/structures.gd").new()
	structures.name = "Structures"
	add_child(structures)
	player.cave_chest.connect(_open_cave_chest)
	player.open_crafting.connect(func() -> void:
		if state == State.PLAYING and not _inventory.visible:
			_toggle_inventory(true))

	_wildlife = preload("res://scripts/wildlife/wildlife_manager.gd").new()
	_wildlife.name = "Wildlife"
	_wildlife.process_mode = Node.PROCESS_MODE_PAUSABLE
	_wildlife.player = player
	Net.wildlife = _wildlife
	add_child(_wildlife)

	_set_focus(menu_camera)
	_new_world_loaded()
	_to_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state in [State.PLAYING, State.PAUSED]:
			save_now()
		Net.stop()
		get_tree().quit()


func _set_focus(n: Node3D) -> void:
	world.focus = n
	_wildlife.focus = n


# --- Worlds & saves -----------------------------------------------------------------

## Switch the generated world (title-screen preview or before starting a save).
func _switch_world(seed_value: int) -> void:
	if seed_value != Game.world_seed or Game.save_id != "":
		Game.new_world(seed_value)
	world.reset()
	_new_world_loaded()


func _preview_seed(seed_value: int) -> void:
	_switch_world(seed_value)
	_title.refresh()


func _new_world_loaded() -> void:
	_spawn = Game.world_gen.find_spawn_point()
	player.spawn_point = _spawn
	_build_cave_features()
	_map.reset_for_world()


## Chests and glowing fungus in the caves of this island (the caves themselves are ground).
func _build_cave_features() -> void:
	if _cave_features:
		remove_child(_cave_features)   # out of the tree now, so the new one can take its name
		_cave_features.queue_free()
	_cave_features = CaveFeatures.new()
	_cave_features.name = "CaveFeatures"
	add_child(_cave_features)
	_cave_features.build(Game.world_gen.caves)


## Whether the player is inside a cave tunnel right now (sets Game.in_cave for the sky, music and
## the swimming / underwater checks).
func _update_cave_state(delta: float) -> void:
	_cave_check -= delta
	if _cave_check > 0.0:
		return
	_cave_check = 0.25
	if not Game.world_gen:
		return
	var p: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	Game.in_cave = Caves.void_distance(Game.world_gen.caves, p) < 0.0


func create_world(display_name: String, seed_value: int, difficulty := Difficulty.NORMAL) -> void:
	Game.difficulty = difficulty
	_switch_world(seed_value)
	Game.start_new_save(display_name)
	player.reset_inventory()
	player.stats.reset()
	_pending_player = {}
	_new_world.hide()
	_start_loading(_spawn, "Generating")


func load_world(save_id: String) -> void:
	var player_data := Game.load_save(save_id)
	if Game.save_id == "":
		return   # unreadable save
	world.reset()
	_new_world_loaded()
	_pending_player = player_data
	var p: Array = player_data.get("pos", [])
	var pos := Vector3(p[0], p[1], p[2]) if p.size() == 3 else _spawn
	_load.hide()
	_title.hide()
	_start_loading(pos, "Loading")


func is_playing() -> bool:
	return state == State.PLAYING or state == State.PAUSED


## Guest: the host's world arrived; load it like a save.
func _join_world(snap: Dictionary) -> void:
	world.reset()
	_new_world_loaded()
	var sp: Array = snap.get("spawn", [])
	if sp.size() == 3:
		_spawn = Vector3(sp[0], sp[1], sp[2])
		player.spawn_point = _spawn
	_pending_player = snap.get("you", {})
	player.stats.reset()
	var p: Array = _pending_player.get("pos", [])
	var pos := Vector3(p[0], p[1], p[2]) if p.size() == 3 else _spawn
	_multiplayer.hide()
	_title.hide()
	_start_loading(pos, "Joining %s's world:" % Net.host_name())


func save_now() -> void:
	if Game.save_id == "" or state == State.TITLE:
		return
	if Net.is_host():
		Net.store_all_guests()
	var data: Dictionary = player.to_save_data()
	Game.write_save(data)
	_autosave = AUTOSAVE_SECONDS


func _open_cave_chest(index: int) -> void:
	var key := "cave_chest_%d" % index
	if Game.looted.has(key):
		_hud.show_hint("Empty already")
		return
	var inv := Game.inventory_of(Game.LOCAL_PLAYER)
	var out := {}
	GameActions._loot_cache(inv, key, RandomNumberGenerator.new(), out)
	Game.looted[key] = true
	Audio.play(Audio.sfx.pickup, -4.0)
	_hud.show_hint("Found %d things in the chest" % out.size() if not out.is_empty() else "Nothing useful inside")


## Come back up to the entrance.
# --- Screens ------------------------------------------------------------------------

func _back_to_title_menu() -> void:
	_new_world.hide()
	_load.hide()
	_multiplayer.hide()
	_title.show()
	_title.refresh()


func _to_title() -> void:
	get_tree().paused = false
	state = State.TITLE
	player.set_active(false)
	_set_focus(menu_camera)
	menu_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in [_hud, _pause, _settings, _inventory, _loading, _new_world, _load, _debug_items]:
		c.hide()
	Game.save_id = ""
	Game.time_of_day = 0.4   # the title screen sits in a warm afternoon
	_title.show()
	_title.refresh()


func _start_loading(at: Vector3, heading := "Generating") -> void:
	state = State.LOADING
	Game.time_paused = not Net.is_online()   # with friends, the world keeps going
	get_tree().paused = false
	player.set_active(false)
	for c in [_hud, _title, _pause, _inventory]:
		c.hide()
	_loading.set_world(Game.save_name if Game.save_name != "" else Game.world_name, heading)
	_loading.modulate.a = 1.0
	_loading.show()
	_load_pos = at
	player.global_position = at + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	if _pending_player.is_empty():
		player.rotation = Vector3(0, randf() * TAU, 0)
		player.stats.reset()
	_set_focus(player)


func _start_playing() -> void:
	state = State.PLAYING
	Game.time_paused = false
	player.stats.apply_difficulty(Game.difficulty)
	if not _pending_player.is_empty():
		player.apply_save_data(_pending_player)
		_pending_player = {}
	var ground: float = Game.world_gen.get_height(player.global_position.x, player.global_position.z)
	player.global_position.y = maxf(player.global_position.y, ground + 0.2)
	player.set_active(true)
	_hud.show()
	_hud.show_arrival(Game.world_name)
	_hud.sync_time()
	if Net.host_on_start and not Net.is_online():
		Net.host()
	_autosave = AUTOSAVE_SECONDS
	var tw := create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_loading.hide)


func _toggle_map(open: bool) -> void:
	_map.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _toggle_inventory(open: bool) -> void:
	_inventory.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _pause_game() -> void:
	state = State.PAUSED
	get_tree().paused = not Net.is_online()   # can't freeze a shared world
	if Net.is_online():
		player.set_physics_process(false)   # stand still while the menu is open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause.show()
	save_now()   # pausing is a natural checkpoint


func _resume() -> void:
	state = State.PLAYING
	get_tree().paused = false
	player.set_physics_process(true)
	_pause.hide()
	_settings.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_items") and state == State.PLAYING:
		_debug_items.visible = not _debug_items.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _debug_items.visible else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and state == State.PLAYING:
		_toggle_inventory(not _inventory.visible)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") and state == State.PLAYING and not _inventory.visible:
		_toggle_map(not _map.visible)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("pause"):
		return
	if _settings.visible:
		_settings.hide()
	elif _debug_items.visible:
		_debug_items.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif _inventory.visible:
		_toggle_inventory(false)
	elif _map.visible:
		_toggle_map(false)
	elif _new_world.visible or _load.visible or _multiplayer.visible:
		_back_to_title_menu()
	elif state == State.PLAYING:
		_pause_game()
	elif state == State.PAUSED:
		_resume()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.PLAYING:
		_update_cave_state(delta)
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_reveal_timer = 0.5
			if Game.reveal(player.global_position):
				_map.mark_dirty()
	match state:
		State.TITLE:
			_fly_menu_camera(delta)
		State.LOADING:
			_loading.set_progress(world.area_progress(_load_pos, 1))
			if world.is_area_ready(_load_pos, 1):
				_start_playing()
		State.PLAYING:
			_autosave -= delta
			if _autosave <= 0.0:
				save_now()
				_hud.show_hint("Game saved")
	if state == State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _settings.visible and not _inventory.visible and not _debug_items.visible:
		# Clicking back into the game window recaptures the mouse.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ambience(delta)


## Slow orbit around the spawn area for the title screen background.
func _fly_menu_camera(delta: float) -> void:
	if not Game.world_gen:
		return   # no island yet (the title screen before a world exists)
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
	if _ambience_timer <= 0.0 and Game.world_gen:
		_ambience_timer = 0.5
		var water := 0
		for i in 8:
			var a := TAU * i / 8.0
			if Game.world_gen.get_height(p.x + cos(a) * 45.0, p.z + sin(a) * 45.0) < 0.0:
				water += 1
		_ocean_level = clampf(water / 4.0, 0.0, 1.0) * clampf(1.0 - p.y / 50.0, 0.1, 1.0)
	var wind := 0.25 + clampf((p.y - 10.0) / 60.0, 0.0, 0.75)
	Audio.set_ambience(wind, _ocean_level, delta)
