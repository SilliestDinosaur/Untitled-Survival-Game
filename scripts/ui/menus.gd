class_name Menus
extends RefCounted
## Title screen, world list, new-world form, pause menu, settings and loading screen.
## All drawn as parchment cards (see UITheme).


static func _card(parent: Control, min_size: Vector2, seed_value := 1) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, seed_value, 34))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	return col


static func _dim(parent: Control, alpha := 0.45) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.03, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)


static func _row(children: Array, sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


## "Open to friends" switch (shared by New World and Load World).
static func _host_toggle() -> CheckButton:
	var c := CheckButton.new()
	c.text = "Open to friends (multiplayer)"
	c.button_pressed = Net.host_on_start
	c.toggled.connect(func(on: bool) -> void: Net.host_on_start = on)
	c.visibility_changed.connect(func() -> void: c.set_pressed_no_signal(Net.host_on_start))
	c.add_theme_color_override("font_color", UITheme.INK)
	c.add_theme_color_override("font_pressed_color", UITheme.INK)
	c.add_theme_color_override("font_hover_color", UITheme.INK)
	return c


static func _spacer(h := 8, w := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if w == 0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func _world_tags(seed_value: int) -> String:
	var pal := WorldPalette.new(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mountains := rng.randf_range(60.0, 115.0)
	var tags: Array[String] = ["Seed %d" % seed_value]
	if pal.exotic:
		tags.append("Exotic")
	tags.append("Mountainous" if mountains > 92.0 else "Rolling hills")
	return "  ·  ".join(tags)


## Title screen: a parchment card beside a flyover of the island.
class TitleScreen extends Control:
	signal continue_pressed
	signal new_world_pressed
	signal load_world_pressed
	signal multiplayer_pressed
	signal settings_pressed

	var _continue: Button
	var _message: Label
	var _continue_info: Label
	var _viewing: Label

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 2, 40))
		UITheme.place(panel, Control.PRESET_CENTER_LEFT, Vector2(70, -300), Vector2(470, 600))
		add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(col)

		col.add_child(UITheme.heading("Untitled Survival", 52))
		col.add_child(UITheme.label("Explore by day.  Survive the night.", 21, UITheme.INK_DIM))
		col.add_child(UITheme.divider())
		col.add_child(Menus._spacer(6))

		_continue = UITheme.button("Continue", true, 380)
		_continue.pressed.connect(func() -> void: continue_pressed.emit())
		col.add_child(_continue)
		_continue_info = UITheme.label("", 15, UITheme.INK_DIM)
		_continue_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_continue_info)
		for entry in [["New World", new_world_pressed], ["Load World", load_world_pressed], ["Play with Friends", multiplayer_pressed], ["Settings", settings_pressed]]:
			var b := UITheme.button(entry[0], false, 380)
			var sig: Signal = entry[1]
			b.pressed.connect(func() -> void: sig.emit())
			col.add_child(b)
		var quit := UITheme.button("Quit", false, 380)
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)
		_message = UITheme.label("", 15, UITheme.ACCENT)
		_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message.custom_minimum_size = Vector2(380, 0)
		col.add_child(_message)

		_viewing = UITheme.label("", 17, UITheme.TEXT_DIM, 5, true)
		UITheme.place(_viewing, Control.PRESET_BOTTOM_RIGHT, Vector2(-520, -54), Vector2(490, 30))
		_viewing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_viewing)
		var version := UITheme.label("prototype v0.3", 14, UITheme.TEXT_DIM, 4)
		UITheme.place(version, Control.PRESET_BOTTOM_LEFT, Vector2(76, -40))
		add_child(version)
		refresh()

	## e.g. why a multiplayer game ended.
	func show_message(text: String) -> void:
		_message.text = text

	func refresh() -> void:
		var saves := SaveManager.list_saves()
		_continue.visible = not saves.is_empty()
		_continue_info.visible = not saves.is_empty()
		if not saves.is_empty():
			var s: Dictionary = saves[0]
			_continue_info.text = "%s  ·  %s" % [s.name, SaveManager.format_when(s.last_played)]
		_viewing.text = Game.world_name


## "A New World": name it, pick or roll a seed, preview what it will be.
class NewWorldPanel extends Control:
	signal create_pressed(world_label: String, seed_value: int)
	signal seed_previewed(seed_value: int)
	signal back_pressed

	var _name: LineEdit
	var _seed: LineEdit
	var _preview_name: Label
	var _preview_tags: Label
	var _seed_value := 0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self, 0.25)
		var col := Menus._card(self, Vector2(560, 0), 3)
		col.add_child(UITheme.heading("A New World", 40))
		col.add_child(UITheme.divider())
		col.add_child(UITheme.label("Name", 16, UITheme.INK_DIM))
		_name = LineEdit.new()
		_name.placeholder_text = "My island"
		_name.max_length = 32
		col.add_child(_name)
		col.add_child(UITheme.label("Seed (a number or any word)", 16, UITheme.INK_DIM))
		_seed = LineEdit.new()
		_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seed.text_submitted.connect(func(_t: String) -> void: _apply_seed_text())
		_seed.focus_exited.connect(_apply_seed_text)
		var reroll := UITheme.button("Reroll", false, 130)
		reroll.pressed.connect(func() -> void: set_seed(Game.random_seed()))
		col.add_child(Menus._row([_seed, reroll]))
		col.add_child(Menus._spacer(4))
		_preview_name = UITheme.label("", 30, UITheme.ACCENT, 0, true)
		col.add_child(_preview_name)
		_preview_tags = UITheme.label("", 16, UITheme.INK_DIM)
		col.add_child(_preview_tags)
		col.add_child(Menus._spacer(4))
		col.add_child(Menus._host_toggle())
		col.add_child(Menus._spacer(4))
		var back := UITheme.button("Back", false, 160)
		back.pressed.connect(func() -> void: back_pressed.emit())
		var create := UITheme.button("Create World", true, 240)
		create.pressed.connect(func() -> void:
			_apply_seed_text()
			create_pressed.emit(_name.text.strip_edges(), _seed_value))
		col.add_child(Menus._row([back, Menus._spacer(), create]))

	func open() -> void:
		_name.text = ""
		set_seed(Game.random_seed())
		show()

	func set_seed(v: int) -> void:
		_seed_value = v
		_seed.text = str(v)
		_preview_name.text = NameGen.world_name(v)
		_preview_tags.text = Menus._world_tags(v)
		seed_previewed.emit(v)

	func _apply_seed_text() -> void:
		var t := _seed.text.strip_edges()
		var v := _seed_value
		if t.is_valid_int() and int(t) > 0:
			v = clampi(int(t), 1, Game.MAX_SEED)
		elif t != "":
			v = absi(hash(t)) % Game.MAX_SEED + 1   # any word works as a seed
		if v != _seed_value:
			set_seed(v)


## List of saved worlds: play, rename, delete.
class LoadPanel extends Control:
	signal play_pressed(save_id: String)
	signal back_pressed

	var _list: VBoxContainer

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self, 0.25)
		var col := Menus._card(self, Vector2(720, 520), 4)
		col.add_child(UITheme.heading("Your Worlds", 40))
		col.add_child(UITheme.divider())
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 380)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		_list = VBoxContainer.new()
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_theme_constant_override("separation", 8)
		scroll.add_child(_list)
		var back := UITheme.button("Back", false, 160)
		back.pressed.connect(func() -> void: back_pressed.emit())
		col.add_child(Menus._row([back, Menus._spacer(), Menus._host_toggle()]))

	func open() -> void:
		refresh()
		show()

	func refresh() -> void:
		for c in _list.get_children():
			c.queue_free()
		var saves := SaveManager.list_saves()
		if saves.is_empty():
			_list.add_child(UITheme.label("No saved worlds yet. Start a new one!", 19, UITheme.INK_DIM))
			return
		for i in saves.size():
			_list.add_child(_make_row(saves[i], i))

	func _make_row(s: Dictionary, i: int) -> Control:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER_DARK, 80 + i, 16, 22, 128))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		panel.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		var title := UITheme.label(s.name, 25, UITheme.INK, 0, true)
		var rename_edit := LineEdit.new()
		rename_edit.text = s.name
		rename_edit.max_length = 32
		rename_edit.visible = false
		info.add_child(title)
		info.add_child(rename_edit)
		info.add_child(UITheme.label("%s  ·  seed %d" % [s.world_name, s.seed], 15, UITheme.INK_DIM))
		info.add_child(UITheme.label("%s played  ·  %s" % [SaveManager.format_play_time(s.play_time), SaveManager.format_when(s.last_played)], 15, UITheme.INK_DIM))
		h.add_child(info)

		var play := UITheme.button("Play", true, 100)
		play.pressed.connect(func() -> void: play_pressed.emit(s.id))
		var rename := UITheme.button("Rename", false, 110)
		var commit_rename := func() -> void:
			SaveManager.rename(s.id, rename_edit.text)
			refresh()
		rename.pressed.connect(func() -> void:
			if rename_edit.visible:
				commit_rename.call()
			else:
				title.visible = false
				rename_edit.visible = true
				rename_edit.grab_focus()
				rename_edit.select_all()
				rename.text = "Save")
		rename_edit.text_submitted.connect(func(_t: String) -> void: commit_rename.call())
		var delete := UITheme.button("Delete", false, 100)
		delete.theme_type_variation = "DangerButton"
		delete.pressed.connect(func() -> void:
			if delete.text == "Sure?":
				SaveManager.delete(s.id)
				refresh()
			else:
				delete.text = "Sure?"
				get_tree().create_timer(3.0).timeout.connect(func() -> void:
					if is_instance_valid(delete):
						delete.text = "Delete"))
		for b in [play, rename, delete]:
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(b)
		return panel


## Pause menu.
class PauseMenu extends Control:
	signal resume_pressed
	signal save_pressed
	signal settings_pressed
	signal quit_to_title_pressed
	signal quit_game_pressed

	var _sub: Label
	var _status: Label
	var _mp: MultiplayerBox

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self)
		var card := Menus._card(self, Vector2(780, 0), 5)
		var title := UITheme.heading("Paused", 44)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(title)
		_sub = UITheme.label("", 17, UITheme.INK_DIM)
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(_sub)
		card.add_child(UITheme.divider())
		# Two columns: the usual buttons, and multiplayer beside them.
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 28)
		card.add_child(cols)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		cols.add_child(col)
		for entry in [["Resume", resume_pressed, true], ["Save Game", save_pressed, false], ["Settings", settings_pressed, false],
				["Save & Quit to Title", quit_to_title_pressed, false], ["Save & Quit Game", quit_game_pressed, false]]:
			var b := UITheme.button(entry[0], entry[2], 340)
			var sig: Signal = entry[1]
			b.pressed.connect(func() -> void: sig.emit())
			col.add_child(b)
		_status = UITheme.label("", 15, UITheme.ACCENT)
		_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_status)
		_mp = MultiplayerBox.new()
		_mp.custom_minimum_size = Vector2(360, 0)
		cols.add_child(_mp)
		visibility_changed.connect(func() -> void:
			if visible:
				if Net.is_client():
					_sub.text = "Playing in %s's world" % Net.host_name()
				else:
					_sub.text = "%s  ·  %s played" % [Game.save_name, SaveManager.format_play_time(Game.play_time)]
				_status.text = ""
				_mp.refresh())

	func show_status(text: String) -> void:
		_status.text = text


## Settings, in tabs. Changes apply and save immediately.
class SettingsPanel extends Control:
	signal closed

	var _waiting_action := ""
	var _bind_buttons := {}

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self, 0.5)
		var col := Menus._card(self, Vector2(720, 600), 6)
		col.add_child(UITheme.heading("Settings", 40))
		var tabs := TabContainer.new()
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(tabs)

		var game := _tab(tabs, "Game")
		_slider(game, "Mouse sensitivity", 0.2, 3.0, 0.05, Settings.mouse_sensitivity, "%.2fx",
			func(v: float) -> void: Settings.mouse_sensitivity = v)
		_check(game, "Invert mouse Y", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
		_slider(game, "Field of view", 60.0, 110.0, 1.0, Settings.fov, "%d°", func(v: float) -> void: Settings.fov = v)
		_check(game, "Show FPS", Settings.show_fps, func(on: bool) -> void: Settings.show_fps = on)

		var gfx := _tab(tabs, "Graphics", true)
		_options(gfx, "View distance", Settings.VIEW_DISTANCES.keys(), Settings.view_distance,
			func(v: String) -> void: Settings.view_distance = v)
		_options(gfx, "Model detail", Settings.MODEL_DETAIL.keys(), Settings.model_detail,
			func(v: String) -> void: Settings.model_detail = v)
		_options(gfx, "Shadows", Settings.SHADOW_LEVELS, Settings.shadow_quality,
			func(v: String) -> void: Settings.shadow_quality = v)
		_options(gfx, "Anti-aliasing", Settings.AA_MODES, Settings.anti_aliasing,
			func(v: String) -> void: Settings.anti_aliasing = v)
		_options(gfx, "Grass & flowers", Settings.GRASS_LEVELS.keys(), Settings.grass,
			func(v: String) -> void: Settings.grass = v)
		var scales: Array = Settings.RENDER_SCALES.map(func(x: float) -> String: return "%d%%" % roundi(x * 100.0))
		_options(gfx, "Render scale (FSR)", scales, "%d%%" % roundi(Settings.render_scale * 100.0),
			func(v: String) -> void: Settings.render_scale = float(v.trim_suffix("%")) / 100.0)
		var caps: Array = Settings.FPS_CAPS.map(func(x: int) -> String: return "Unlimited" if x == 0 else str(x))
		_options(gfx, "FPS limit", caps, "Unlimited" if Settings.fps_cap == 0 else str(Settings.fps_cap),
			func(v: String) -> void: Settings.fps_cap = 0 if v == "Unlimited" else int(v))
		_check(gfx, "V-Sync", Settings.vsync, func(on: bool) -> void: Settings.vsync = on)
		_check(gfx, "Ambient occlusion", Settings.ambient_occlusion, func(on: bool) -> void: Settings.ambient_occlusion = on)
		_check(gfx, "Glow", Settings.glow, func(on: bool) -> void: Settings.glow = on)
		var note := UITheme.label("Model detail sets how smooth plants, rocks, animals and items are.\nView distance, model detail and grass apply as new terrain loads.", 14, UITheme.INK_DIM)
		gfx.get_parent().get_parent().add_child(note)

		var audio := _tab(tabs, "Audio")
		_slider(audio, "Master volume", 0.0, 1.0, 0.01, Settings.master_volume, "%d%%",
			func(v: float) -> void: Settings.master_volume = v, 100.0)
		_slider(audio, "Music", 0.0, 1.0, 0.01, Settings.music_volume, "%d%%",
			func(v: float) -> void: Settings.music_volume = v, 100.0)
		_slider(audio, "Effects", 0.0, 1.0, 0.01, Settings.sfx_volume, "%d%%",
			func(v: float) -> void: Settings.sfx_volume = v, 100.0)

		var controls := _tab(tabs, "Controls", true)
		for entry: Array in Settings.ACTIONS:
			controls.add_child(UITheme.label(entry[1], 17))
			var b := UITheme.button("", false, 200)
			b.custom_minimum_size = Vector2(200, 40)
			var action: String = entry[0]
			b.pressed.connect(func() -> void: _start_rebind(action))
			controls.add_child(b)
			_bind_buttons[action] = b
		var reset := UITheme.button("Reset to defaults", false, 220)
		reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		reset.pressed.connect(func() -> void:
			Settings.reset_bindings()
			_refresh_bindings())
		controls.get_parent().get_parent().add_child(reset)
		_refresh_bindings()

		var back := UITheme.button("Done", true, 180)
		back.pressed.connect(func() -> void:
			_waiting_action = ""
			closed.emit())
		col.add_child(Menus._row([Menus._spacer(), back]))

	func _tab(tabs: TabContainer, title: String, scroll := false) -> GridContainer:
		var page := VBoxContainer.new()
		page.name = title
		page.add_theme_constant_override("separation", 12)
		tabs.add_child(page)
		page.add_child(Menus._spacer(6))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		grid.add_theme_constant_override("v_separation", 10)
		if scroll:
			var sc := ScrollContainer.new()
			sc.custom_minimum_size = Vector2(0, 300)
			sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			page.add_child(sc)
			sc.add_child(grid)
		else:
			page.add_child(grid)
		return grid

	func _changed() -> void:
		Settings.apply()
		Settings.save_settings()

	func _slider(grid: GridContainer, title: String, lo: float, hi: float, step: float, value: float, fmt: String, setter: Callable, display_mul := 1.0) -> void:
		grid.add_child(UITheme.label(title, 18))
		var s := HSlider.new()
		s.min_value = lo
		s.max_value = hi
		s.step = step
		s.value = value
		s.custom_minimum_size = Vector2(230, 24)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lbl := UITheme.label(fmt % (value * display_mul), 16, UITheme.INK_DIM)
		lbl.custom_minimum_size = Vector2(60, 0)
		s.value_changed.connect(func(v: float) -> void:
			setter.call(v)
			lbl.text = fmt % (v * display_mul)
			_changed())
		grid.add_child(Menus._row([s, lbl], 12))

	func _check(grid: GridContainer, title: String, value: bool, setter: Callable) -> void:
		grid.add_child(UITheme.label(title, 18))
		var c := CheckButton.new()
		c.button_pressed = value
		c.toggled.connect(func(on: bool) -> void:
			setter.call(on)
			_changed())
		grid.add_child(c)

	func _options(grid: GridContainer, title: String, items: Array, current: String, setter: Callable) -> void:
		grid.add_child(UITheme.label(title, 18))
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(230, 42)
		for i in items.size():
			ob.add_item(items[i])
			if items[i] == current:
				ob.select(i)
		ob.item_selected.connect(func(i: int) -> void:
			setter.call(ob.get_item_text(i))
			_changed())
		grid.add_child(ob)

	# --- Rebinding -----------------------------------------------------------------

	func _start_rebind(action: String) -> void:
		_refresh_bindings()
		_waiting_action = action
		_bind_buttons[action].text = "Press a key..."

	func _input(event: InputEvent) -> void:
		if _waiting_action == "" or not visible:
			return
		var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
		if not pressed:
			return
		get_viewport().set_input_as_handled()
		if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
			_waiting_action = ""   # cancel
		else:
			var code := Settings.code_from_event(event)
			if code != "":
				Settings.rebind(_waiting_action, code)
			_waiting_action = ""
		_refresh_bindings()

	func _refresh_bindings() -> void:
		for action: String in _bind_buttons:
			_bind_buttons[action].text = Settings.code_label(Settings.binding_of(action))


## Loading screen shown while the area around the player generates.
class LoadingScreen extends Control:
	const TIPS := [
		"Every seed is a different island: new terrain, colors, plants, animals and names.",
		"Shadow creatures come at night. They will break through weak walls.",
		"Sprinting burns food faster, and animals hear you coming.",
		"Ore deposits are more common high in the mountains.",
		"Falling from high places hurts. Water breaks your fall.",
		"Territorial beasts leave you alone... until you hit them.",
		"Mushrooms grow near fallen logs in damp forests.",
		"Gathered trees and rocks grow back after a while.",
		"Your world saves when you pause, quit, and every couple of minutes.",
	]
	var _bar: ProgressBar
	var _name: Label
	var _heading: Label
	var _tip: Label

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0.13, 0.1, 0.08)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var col := Menus._card(self, Vector2(640, 0), 7)
		_heading = UITheme.label("Generating", 18, UITheme.ACCENT)
		_name = UITheme.heading("", 56)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size = Vector2(560, 26)
		_bar.show_percentage = false
		_bar.max_value = 1.0
		_tip = UITheme.label("", 17, UITheme.INK_DIM)
		_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip.custom_minimum_size = Vector2(560, 0)
		for c in [_heading, _name, _bar, _tip]:
			if c is Label:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(c)

	func set_world(world_name: String, heading := "Generating") -> void:
		_name.text = world_name
		_heading.text = heading
		_bar.value = 0.0
		_tip.text = TIPS[randi() % TIPS.size()]

	func set_progress(p: float) -> void:
		_bar.value = lerpf(_bar.value, p, 0.25)


## F9: every item in this world, click to add (Shift-click for a full stack). For testing tiers
## until crafting arrives.
class DebugItems extends Control:
	var inventory: Inventory
	var _grid: GridContainer

	func setup(inv: Inventory) -> void:
		inventory = inv
		Game.world_changed.connect(func() -> void:
			if visible:
				_fill())

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self, 0.3)
		var col := Menus._card(self, Vector2(860, 560), 11)
		col.add_child(UITheme.heading("Debug: items", 32))
		col.add_child(UITheme.label("Click to add one, Shift-click for a stack. F9 or Esc to close.", 15, UITheme.INK_DIM))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 430)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		_grid = GridContainer.new()
		_grid.columns = 4
		_grid.add_theme_constant_override("h_separation", 6)
		_grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(_grid)
		hide()
		visibility_changed.connect(func() -> void:
			if visible:
				_fill())

	func _fill() -> void:
		for c in _grid.get_children():
			c.queue_free()
		var ids := ItemDB.all_ids()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var ia := ItemDB.info(a)
			var ib := ItemDB.info(b)
			return "%s%d%s" % [ia.kind, ia.get("tier", 0), a] < "%s%d%s" % [ib.kind, ib.get("tier", 0), b])
		for id: String in ids:
			var b := Button.new()
			b.text = ItemDB.display_name(id)
			b.icon = null
			b.custom_minimum_size = Vector2(200, 40)
			b.add_theme_font_size_override("font_size", 15)
			b.tooltip_text = ItemDB.describe(id)
			b.pressed.connect(func() -> void:
				Net.request("debug_add", {"item": id, "count": ItemDB.stack_size(id) if Input.is_key_pressed(KEY_SHIFT) else 1}))
			_grid.add_child(b)



## Pause menu: open the world to friends, show the invite codes and who's here.
class MultiplayerBox extends VBoxContainer:
	var _title: Label
	var _open: Button
	var _code_row: HBoxContainer
	var _code: Label
	var _lan_row: HBoxContainer
	var _lan: Label
	var _info: Label
	var _who: Label

	func _ready() -> void:
		add_theme_constant_override("separation", 6)
		_title = UITheme.label("Multiplayer", 19, UITheme.INK)
		_title.add_theme_font_override("font", UITheme.BOLD_FONT)
		add_child(_title)
		_open = UITheme.button("Open to Friends", false, 340)
		_open.pressed.connect(func() -> void:
			Net.host()
			refresh())
		add_child(_open)
		_code = UITheme.label("", 30, UITheme.ACCENT, 0, true)
		_code_row = _copy_row("Invite code", _code)
		add_child(_code_row)
		_lan = UITheme.label("", 20, UITheme.INK)
		_lan_row = _copy_row("Same network", _lan)
		add_child(_lan_row)
		_info = UITheme.label("", 14, UITheme.INK_DIM)
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.custom_minimum_size = Vector2(340, 0)
		add_child(_info)
		_who = UITheme.label("", 15, UITheme.INK)
		_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_who.custom_minimum_size = Vector2(340, 0)
		add_child(_who)
		Net.invite_ready.connect(refresh)
		Net.roster_changed.connect(refresh)
		Net.status_changed.connect(func(_t: String) -> void: refresh())

	func _copy_row(caption: String, value: Label) -> HBoxContainer:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.add_child(UITheme.label(caption, 13, UITheme.INK_DIM))
		v.add_child(value)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var copy := UITheme.button("Copy", false, 90)
		copy.custom_minimum_size = Vector2(90, 36)
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(value.text)
			copy.text = "Copied"
			get_tree().create_timer(1.2).timeout.connect(func() -> void: copy.text = "Copy"))
		return Menus._row([v, copy])

	func refresh() -> void:
		if not is_inside_tree():
			return
		_open.visible = not Net.is_online()
		_code_row.visible = Net.is_host() and Net.invite_code != ""
		_lan_row.visible = Net.is_host()
		_code.text = Net.invite_code
		_lan.text = Net.lan_code
		match Net.upnp_state:
			"working": _info.text = "Setting up your router..."
			"ok": _info.text = "Give your friend the invite code. They enter it under Play with Friends."
			"failed": _info.text = "Your router didn't allow automatic setup, so the invite code isn't available. Friends on your Wi-Fi can use the same-network code. For internet play, forward UDP port %d to this computer, or both join a virtual LAN (Tailscale, ZeroTier, Radmin) and share that address." % Net.port
			_: _info.text = "Let up to %d friends join this world. Their characters are saved here." % (Net.MAX_PLAYERS - 1) if not Net.is_client() else ""
		var names: Array[String] = []
		for p: int in Net.players:
			names.append(String(Net.players[p].name))
		_who.text = ("Here: " + ", ".join(names)) if not names.is_empty() else ("Waiting for friends..." if Net.is_host() else "")


## Title screen: your name and colour, and joining a friend's world by code.
class MultiplayerPanel extends Control:
	signal back_pressed

	var _name: LineEdit
	var _code: LineEdit
	var _status: Label
	var _join: Button
	var _games: VBoxContainer
	var _swatches: Array[Button] = []

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Menus._dim(self, 0.25)
		var col := Menus._card(self, Vector2(580, 0), 9)
		col.add_child(UITheme.heading("Play with Friends", 40))
		col.add_child(UITheme.divider())
		col.add_child(UITheme.label("Your name", 16, UITheme.INK_DIM))
		_name = LineEdit.new()
		_name.max_length = 20
		_name.text_changed.connect(func(t: String) -> void:
			Settings.player_name = t.strip_edges()
			Settings.save_settings())
		col.add_child(_name)
		var swatch_row := HBoxContainer.new()
		swatch_row.add_theme_constant_override("separation", 6)
		for i in Settings.PLAYER_COLORS.size():
			var b := Button.new()
			b.custom_minimum_size = Vector2(36, 36)
			b.focus_mode = Control.FOCUS_NONE
			var sb := UITheme.box(Settings.PLAYER_COLORS[i], 18, Color(0.15, 0.1, 0.08), 0, 0)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_stylebox_override("pressed", sb)
			b.pressed.connect(func() -> void:
				Settings.player_color = i
				Settings.save_settings()
				_mark_swatch())
			swatch_row.add_child(b)
			_swatches.append(b)
		col.add_child(swatch_row)
		col.add_child(Menus._spacer(6))
		col.add_child(UITheme.label("Join a friend: enter their invite code", 16, UITheme.INK_DIM))
		_code = LineEdit.new()
		_code.placeholder_text = "e.g. KQ7M-B3X"
		_code.text_submitted.connect(func(_t: String) -> void: _do_join())
		_join = UITheme.button("Join", true, 140)
		_join.pressed.connect(_do_join)
		_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Menus._row([_code, _join]))
		col.add_child(Menus._spacer(4))
		col.add_child(UITheme.label("Games on this Wi-Fi", 16, UITheme.INK_DIM))
		_games = VBoxContainer.new()
		_games.add_theme_constant_override("separation", 6)
		col.add_child(_games)
		_status = UITheme.label("", 15, UITheme.ACCENT)
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.custom_minimum_size = Vector2(520, 0)
		col.add_child(_status)
		col.add_child(Menus._spacer(4))
		var host_note := UITheme.label("To host: start or load a world with \"Open to friends\" switched on, or open it from the pause menu at any time. You'll get a code to share.", 14, UITheme.INK_DIM)
		host_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		host_note.custom_minimum_size = Vector2(520, 0)
		col.add_child(host_note)
		col.add_child(Menus._spacer(6))
		var back := UITheme.button("Back", false, 160)
		back.pressed.connect(func() -> void:
			Net.stop_listening()
			if Net.is_client():
				Net.stop()
			back_pressed.emit())
		col.add_child(Menus._row([back]))
		Net.status_changed.connect(func(t: String) -> void:
			_status.text = t
			_join.disabled = Net.is_client())
		Net.games_changed.connect(_refresh_games)
		_refresh_games()

	func open() -> void:
		_name.text = Settings.player_name
		_status.text = ""
		_join.disabled = false
		_mark_swatch()
		Net.start_listening()
		_refresh_games()
		show()

	## Rebuild the list of games heard on the local network: one tap joins, no code needed.
	func _refresh_games() -> void:
		if not _games:
			return
		for c in _games.get_children():
			c.queue_free()
		var keys: Array = Net.found_games.keys()
		if keys.is_empty():
			_games.add_child(UITheme.label("No games found yet. Ask your friend to open their world to friends (pause menu > Open to Friends).", 14, UITheme.INK_DIM))
			return
		for ip: String in keys:
			var g: Dictionary = Net.found_games[ip]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var info := UITheme.label("%s  ·  %s" % [g.name, g.world], 17, UITheme.INK)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var b := UITheme.button("Join", true, 110)
			b.custom_minimum_size = Vector2(110, 38)
			b.disabled = Net.is_online()
			var address := "%s:%d" % [ip, int(g.port)]
			b.pressed.connect(func() -> void:
				if Settings.player_name.strip_edges() == "":
					Settings.player_name = "Wanderer"
				b.disabled = true
				Net.join(address))
			row.add_child(b)
			_games.add_child(row)

	func _mark_swatch() -> void:
		for i in _swatches.size():
			_swatches[i].text = "✓" if i == Settings.player_color else ""

	func _do_join() -> void:
		if _code.text.strip_edges() == "":
			_status.text = "Enter your friend's code first."
			return
		if Settings.player_name.strip_edges() == "":
			Settings.player_name = "Wanderer"
		_join.disabled = true
		if not Net.join(_code.text):
			_join.disabled = false
