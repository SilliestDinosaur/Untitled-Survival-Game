class_name Menus
extends RefCounted
## Builders for the title screen, pause menu, settings panel and loading screen.


## Title screen: world card with seed controls, Play / Settings / Quit.
class TitleScreen extends Control:
	signal play_pressed
	signal seed_requested(seed_value: int)
	signal settings_pressed

	var _world_name: Label
	var _world_info: Label
	var _seed_edit: LineEdit

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Darken the left side so text reads well over the flyover.
		var shade := TextureRect.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var grad := Gradient.new()
		grad.set_color(0, Color(0.02, 0.025, 0.035, 0.88))
		grad.set_color(1, Color(0.02, 0.025, 0.035, 0.0))
		grad.set_offset(1, 0.62)
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 256
		gt.height = 4
		shade.texture = gt
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)

		var col := VBoxContainer.new()
		UITheme.place(col, Control.PRESET_LEFT_WIDE, Vector2(90, 0), Vector2(470, 0))
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 12)
		add_child(col)

		col.add_child(UITheme.label("UNTITLED SURVIVAL", 52, Color.WHITE, 10))
		col.add_child(UITheme.label("Explore by day.  Survive the night.", 19, UITheme.TEXT_DIM, 4))
		col.add_child(_spacer(34))

		col.add_child(UITheme.label("WORLD", 13, UITheme.ACCENT, 3))
		_world_name = UITheme.label("", 34, Color.WHITE, 8)
		col.add_child(_world_name)
		_world_info = UITheme.label("", 15, UITheme.TEXT_DIM, 4)
		col.add_child(_world_info)

		var seed_row := HBoxContainer.new()
		seed_row.add_theme_constant_override("separation", 8)
		_seed_edit = LineEdit.new()
		_seed_edit.placeholder_text = "Seed"
		_seed_edit.custom_minimum_size = Vector2(200, 44)
		_seed_edit.max_length = 9
		_seed_edit.text_submitted.connect(func(t: String) -> void: _submit_seed(t))
		_seed_edit.focus_exited.connect(func() -> void: _submit_seed(_seed_edit.text))
		seed_row.add_child(_seed_edit)
		var dice := UITheme.button("New World", false, 150)
		dice.pressed.connect(func() -> void: seed_requested.emit(Game.random_seed()))
		seed_row.add_child(dice)
		col.add_child(seed_row)
		col.add_child(_spacer(26))

		var play := UITheme.button("Play", true, 360)
		play.pressed.connect(func() -> void: play_pressed.emit())
		col.add_child(play)
		var settings := UITheme.button("Settings", false, 360)
		settings.pressed.connect(func() -> void: settings_pressed.emit())
		col.add_child(settings)
		var quit := UITheme.button("Quit", false, 360)
		quit.pressed.connect(func() -> void: get_tree().quit())
		col.add_child(quit)
		for b in [play, settings, quit]:
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		var version := UITheme.label("prototype v0.2", 13, UITheme.TEXT_DIM)
		UITheme.place(version, Control.PRESET_BOTTOM_LEFT, Vector2(90, -44))
		add_child(version)
		refresh()

	func refresh() -> void:
		_world_name.text = Game.world_name
		var tags: Array[String] = ["Seed %d" % Game.world_seed]
		if Game.palette.exotic:
			tags.append("Exotic world")
		tags.append("Mountainous" if Game.world_gen.mountain_scale > 110.0 else "Rolling hills")
		_world_info.text = "  ·  ".join(tags)
		_seed_edit.text = str(Game.world_seed)

	func _submit_seed(t: String) -> void:
		var v := t.strip_edges()
		if v.is_valid_int() and int(v) > 0 and int(v) != Game.world_seed:
			seed_requested.emit(int(v))
		elif not v.is_valid_int() and v != "":
			# Any text works as a seed too.
			seed_requested.emit(absi(hash(v)) % Game.MAX_SEED + 1)

	func _spacer(h: int) -> Control:
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, h)
		return c


## Pause menu.
class PauseMenu extends Control:
	signal resume_pressed
	signal settings_pressed
	signal quit_to_title_pressed

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		center.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		panel.add_child(col)
		var title := UITheme.label("PAUSED", 30, Color.WHITE)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		var sub := UITheme.label(Game.world_name, 15, UITheme.TEXT_DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		visibility_changed.connect(func() -> void: sub.text = "%s  ·  seed %d" % [Game.world_name, Game.world_seed])
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		col.add_child(gap)
		var resume := UITheme.button("Resume", true, 300)
		resume.pressed.connect(func() -> void: resume_pressed.emit())
		var settings := UITheme.button("Settings", false, 300)
		settings.pressed.connect(func() -> void: settings_pressed.emit())
		var title_btn := UITheme.button("Quit to Title", false, 300)
		title_btn.pressed.connect(func() -> void: quit_to_title_pressed.emit())
		var quit := UITheme.button("Quit Game", false, 300)
		quit.pressed.connect(func() -> void: get_tree().quit())
		for b in [resume, settings, title_btn, quit]:
			col.add_child(b)


## Settings panel; changes apply and save immediately.
class SettingsPanel extends Control:
	signal closed

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(560, 0)
		center.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		panel.add_child(col)
		col.add_child(UITheme.label("SETTINGS", 28, Color.WHITE))

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 14)
		col.add_child(grid)

		_slider(grid, "Mouse sensitivity", 0.2, 3.0, 0.05, Settings.mouse_sensitivity, "%.2fx",
			func(v: float) -> void: Settings.mouse_sensitivity = v)
		_slider(grid, "Field of view", 60.0, 110.0, 1.0, Settings.fov, "%d°",
			func(v: float) -> void: Settings.fov = v)
		_options(grid, "View distance", Settings.VIEW_DISTANCES.keys(), Settings.view_distance,
			func(v: String) -> void: Settings.view_distance = v)
		_options(grid, "Graphics quality", Settings.QUALITY_LEVELS, Settings.quality,
			func(v: String) -> void: Settings.quality = v)
		_slider(grid, "Master volume", 0.0, 1.0, 0.01, Settings.master_volume, "%d%%",
			func(v: float) -> void: Settings.master_volume = v, 100.0)
		grid.add_child(UITheme.label("Show FPS", 17))
		var fps := CheckButton.new()
		fps.button_pressed = Settings.show_fps
		fps.toggled.connect(func(on: bool) -> void:
			Settings.show_fps = on
			_changed())
		grid.add_child(fps)

		var back := UITheme.button("Back", true, 200)
		back.size_flags_horizontal = Control.SIZE_SHRINK_END
		back.pressed.connect(func() -> void: closed.emit())
		col.add_child(back)

	func _changed() -> void:
		Settings.apply()
		Settings.save_settings()

	func _slider(grid: GridContainer, title: String, lo: float, hi: float, step: float, value: float, fmt: String, setter: Callable, display_mul := 1.0) -> void:
		grid.add_child(UITheme.label(title, 17))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var s := HSlider.new()
		s.min_value = lo
		s.max_value = hi
		s.step = step
		s.value = value
		s.custom_minimum_size = Vector2(210, 24)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lbl := UITheme.label(fmt % (value * display_mul), 15, UITheme.TEXT_DIM)
		lbl.custom_minimum_size = Vector2(56, 0)
		s.value_changed.connect(func(v: float) -> void:
			setter.call(v)
			lbl.text = fmt % (v * display_mul)
			_changed())
		row.add_child(s)
		row.add_child(lbl)
		grid.add_child(row)

	func _options(grid: GridContainer, title: String, items: Array, current: String, setter: Callable) -> void:
		grid.add_child(UITheme.label(title, 17))
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(210, 40)
		for i in items.size():
			ob.add_item(items[i])
			if items[i] == current:
				ob.select(i)
		ob.item_selected.connect(func(i: int) -> void:
			setter.call(ob.get_item_text(i))
			_changed())
		grid.add_child(ob)


## Loading screen shown while the area around the spawn point generates.
class LoadingScreen extends Control:
	const TIPS := [
		"Every seed is a different island: new terrain, colors, plants and names.",
		"Shadow creatures come at night. They will break through weak walls.",
		"Sprinting burns food faster. Pace yourself.",
		"Ore deposits are more common high in the mountains.",
		"Falling from high places hurts. Water breaks your fall.",
		"Type any word into the seed box to turn it into a world.",
	]
	var _bar: ProgressBar
	var _name: Label
	var _heading: Label

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.035, 0.05)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		center.add_child(col)
		_heading = UITheme.label("GENERATING", 14, UITheme.ACCENT)
		var gen := _heading
		_name = UITheme.label("", 40, Color.WHITE)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size = Vector2(460, 8)
		_bar.show_percentage = false
		_bar.max_value = 1.0
		var tip := UITheme.label(TIPS[randi() % TIPS.size()], 15, UITheme.TEXT_DIM)
		for c in [gen, _name, _bar, tip]:
			if c is Label:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(c)

	func set_world(world_name: String, heading := "GENERATING") -> void:
		_name.text = world_name
		_heading.text = heading.to_upper()
		_bar.value = 0.0

	func set_progress(p: float) -> void:
		_bar.value = lerpf(_bar.value, p, 0.25)
