class_name HUD
extends Control
## In-game overlay: stat bars, compass, biome name, crosshair + target label,
## damage / underwater effects, arrival banner and debug readout.

var player: CharacterBody3D
var world: Node

var _health: StatBar
var _hunger: StatBar
var _stamina: StatBar
var _warmth: StatBar
var _cold_fx: ColorRect
var _compass: Compass
var _biome: Label
var _crosshair: Control
var _target_name: Label
var _target_kind: Label
var _debug: Label
var _banner: VBoxContainer
var _banner_name: Label
var _damage_fx: ColorRect
var _water_fx: ColorRect
var _damage := 0.0
var _last_biome := -1
var _biome_timer := 0.0
var _debug_on := false
var _crosshair_scale := 1.0
var _hotbar: InventoryUI.Hotbar
var _held_name: Label
var _feed: InventoryUI.PickupFeed
var _hint: Label
var _target_bar: StatBar
var _prompt: Label
var _wheel: BuildWheel
var _target_box: Control
var _effects: Label
var _hit_marker := 0.0
var _clock: Label
var _time_banner: Label
var _was_night := false
var _dusk_warned := false


func setup(p: CharacterBody3D, w: Node) -> void:
	player = p
	world = w
	player.stats.damaged.connect(func(amount: float) -> void: _damage = minf(_damage + amount / 25.0, 1.0))
	_hotbar.setup(player.inventory, _held_name)
	player.inventory.item_added.connect(_feed.add_item)
	player.hint.connect(show_hint)
	player.hit_landed.connect(hit_marker)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_water_fx = _overlay(Color(0.05, 0.25, 0.35), 0.0, 0.9)
	_damage_fx = _overlay(Color(0.65, 0.02, 0.02), 0.0, 0.5)
	_cold_fx = _overlay(Color(0.7, 0.85, 1.0), 0.0, 0.75)
	_wheel = BuildWheel.new()
	add_child(_wheel)

	# Crosshair: a dot that grows into a ring when you can interact with something.
	_crosshair = Control.new()
	UITheme.place(_crosshair, Control.PRESET_CENTER, Vector2.ZERO)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)

	var target := VBoxContainer.new()
	_target_box = target
	UITheme.place(target, Control.PRESET_CENTER, Vector2(-200, 26), Vector2(400, 0))
	target.add_theme_constant_override("separation", 0)
	add_child(target)
	_target_name = UITheme.label("", 24, UITheme.TEXT, 6, true)
	_target_kind = UITheme.label("", 14, UITheme.TEXT_DIM, 4)
	for l in [_target_name, _target_kind]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.add_child(l)
	_target_bar = StatBar.new(Color(0.92, 0.82, 0.55), "")
	_target_bar.custom_minimum_size = Vector2(150, 22)
	_target_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.add_child(_target_bar)
	_prompt = UITheme.label("", 16, UITheme.TEXT, 5)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.add_child(_prompt)

	# Stat bars, bottom-left.
	var bars := VBoxContainer.new()
	UITheme.place(bars, Control.PRESET_BOTTOM_LEFT, Vector2(28, -132))
	_effects = UITheme.label("", 15, Color(0.95, 0.9, 0.7), 4)
	UITheme.place(_effects, Control.PRESET_BOTTOM_LEFT, Vector2(28, -164), Vector2(420, 24))
	add_child(_effects)
	bars.add_theme_constant_override("separation", 4)
	add_child(bars)
	_health = StatBar.new(Color(0.90, 0.30, 0.30), "HEALTH")
	_hunger = StatBar.new(Color(0.93, 0.62, 0.25), "FOOD")
	_stamina = StatBar.new(Color(0.55, 0.85, 0.45), "STAM")
	_stamina.auto_hide = true
	_stamina.warn_below = 0.15
	_warmth = StatBar.new(Color(0.55, 0.78, 1.0), "WARM")
	_warmth.auto_hide = true
	_warmth.warn_below = 0.25
	for b in [_health, _hunger, _warmth, _stamina]:
		bars.add_child(b)

	# Compass + biome, top-center.
	var top := VBoxContainer.new()
	UITheme.place(top, Control.PRESET_CENTER_TOP, Vector2(-260, 18), Vector2(520, 0))
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	_compass = Compass.new()
	top.add_child(_compass)
	_biome = UITheme.label("", 19, UITheme.TEXT, 5, true)
	_biome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_biome)

	# "Welcome to ..." banner.
	_banner = VBoxContainer.new()
	UITheme.place(_banner, Control.PRESET_CENTER, Vector2(-400, -230), Vector2(800, 0))
	_banner.modulate.a = 0.0
	add_child(_banner)
	var welcome := UITheme.label("You have washed ashore on", 22, UITheme.TEXT_DIM, 5, true)
	_banner_name = UITheme.label("", 64, UITheme.TEXT, 10, true)
	for l in [welcome, _banner_name]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.add_child(l)

	# Hotbar, bottom-center, with the held item's name above it.
	var bottom := VBoxContainer.new()
	UITheme.place(bottom, Control.PRESET_CENTER_BOTTOM, Vector2(-280, -112), Vector2(560, 0))
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_held_name = UITheme.label("", 17, UITheme.TEXT, 5)
	_held_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_held_name)
	_hotbar = InventoryUI.Hotbar.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_hotbar)

	_feed = InventoryUI.PickupFeed.new()
	UITheme.place(_feed, Control.PRESET_CENTER_RIGHT, Vector2(-320, -40), Vector2(290, 0))
	add_child(_feed)

	_hint = UITheme.label("", 19, Color(1, 0.88, 0.7), 5)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(_hint, Control.PRESET_CENTER, Vector2(-300, 70), Vector2(600, 0))
	_hint.modulate.a = 0.0
	add_child(_hint)

	# Day counter + clock, top-right.
	_clock = UITheme.label("", 19, UITheme.TEXT, 5, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.place(_clock, Control.PRESET_TOP_RIGHT, Vector2(-268, 22), Vector2(240, 0))
	add_child(_clock)
	_time_banner = UITheme.label("", 36, UITheme.TEXT, 8, true)
	_time_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(_time_banner, Control.PRESET_CENTER, Vector2(-400, -170), Vector2(800, 0))
	_time_banner.modulate.a = 0.0
	add_child(_time_banner)

	_debug = UITheme.label("", 14, UITheme.TEXT, 4)
	_debug.position = Vector2(14, 10)
	add_child(_debug)


func _overlay(tint: Color, intensity: float, softness: float) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vignette.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("softness", softness)
	r.material = mat
	add_child(r)
	return r


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.6)


func show_arrival(world_name: String) -> void:
	_banner_name.text = world_name
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_banner, "modulate:a", 1.0, 1.2)
	tw.tween_interval(3.0)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.5)


## Bearings and colours of the other players, for the compass (north = -Z).
func _friend_markers() -> Array:
	var out := []
	if not Net.is_online():
		return out
	var here: Vector3 = player.global_position
	for peer: int in Net.avatars:
		var a = Net.avatars[peer]
		if not a.has_pose:
			continue
		var d: Vector3 = a.global_position - here
		if Vector2(d.x, d.z).length() < 1.0:
			continue
		var bearing := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
		out.append({"bearing": bearing, "name": a.display_name, "color": Settings.PLAYER_COLORS[int(Net.players.get(peer, {}).get("color", 0)) % Settings.PLAYER_COLORS.size()]})
	return out


func _update_clock() -> void:
	var night := Game.is_night()
	_clock.text = "%s  Day %d  ·  %s" % ["☾" if night else "☀", Game.day, Game.clock_text()]
	_clock.modulate = Color(0.75, 0.82, 1.0) if night else Color.WHITE
	# A warning shortly before dark, and a banner when night falls / the sun comes back.
	var t := Game.time_of_day
	var near_dusk := t > Game.SUNSET - 0.04 and t < Game.SUNSET
	if near_dusk and not _dusk_warned:
		_dusk_warned = true
		_flash_time("The sun is setting... nights are cold", Color(1.0, 0.75, 0.5))
	if not near_dusk and not night:
		_dusk_warned = false
	if night != _was_night:
		if night:
			_flash_time("Night falls", Color(0.7, 0.78, 1.0))
		else:
			_flash_time("Dawn of day %d" % Game.day, Color(1.0, 0.9, 0.65))
		_was_night = night


func sync_time() -> void:
	_was_night = Game.is_night()
	_dusk_warned = Game.time_of_day > Game.SUNSET - 0.04


func _flash_time(text: String, tint: Color) -> void:
	_time_banner.text = text
	_time_banner.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	var tw := create_tween()
	tw.tween_property(_time_banner, "modulate:a", 1.0, 1.0)
	tw.tween_interval(2.5)
	tw.tween_property(_time_banner, "modulate:a", 0.0, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_on = not _debug_on


func _process(delta: float) -> void:
	if not player:
		return
	var s: PlayerStats = player.stats
	_health.value = s.health / s.max_health
	_hunger.value = s.hunger / s.max_hunger
	_stamina.value = s.stamina / s.max_stamina
	_warmth.value = s.warmth / s.max_warmth
	# Frosty screen edges as you get cold.
	var chill := 1.0 - smoothstep(0.0, 0.5, s.warmth / s.max_warmth)
	(_cold_fx.material as ShaderMaterial).set_shader_parameter("intensity", chill * 0.55)

	_compass.heading = fposmod(-rad_to_deg(player.rotation.y), 360.0)
	_compass.markers = _friend_markers()
	_compass.queue_redraw()
	_update_clock()

	# Biome name: update a few times a second, flash brighter when it changes.
	_biome_timer -= delta
	if _biome_timer <= 0.0:
		_biome_timer = 0.4
		var p := player.global_position
		var b: int = Game.world_gen.get_biome(p.x, p.z)
		if b != _last_biome:
			_last_biome = b
			_biome.text = WorldGen.BIOME_NAMES[b]
			_biome.modulate = Color(1.6, 1.4, 1.1)
	_biome.modulate = _biome.modulate.lerp(Color.WHITE, 1.0 - exp(-1.5 * delta))

	_wheel.player = player
	_banner.visible = not _wheel.visible   # the island's name card would sit on top of the wheel
	# At a crafting minigame the cues take the middle of the screen.
	var crafting: bool = player.crafting != null
	_crosshair.visible = not crafting
	_target_box.visible = not crafting
	# Crosshair target.
	var look: Dictionary = player.looking_at
	_target_name.text = look.get("name", "")
	_target_kind.text = String(look.get("label", "")).to_upper()
	var parts: Array[String] = []
	if look.get("interact", "") != "":
		parts.append("[%s] %s" % [Settings.code_label(Settings.binding_of("interact")), look.interact])
	if look.get("attack", "") != "":
		parts.append("[%s] %s" % [Settings.code_label(Settings.binding_of("attack")).replace(" Click", ""), look.attack])
	var holding_plan: bool = ItemDB.tool_stats(player.inventory.selected_item()).get("type", "") == "plan"
	if (look.is_empty() or holding_plan) and not player.placement.is_empty():
		var pl: Dictionary = player.placement
		if holding_plan:
			parts.clear()   # the plan only lays blueprints, whatever the crosshair is on
		parts.append(("[%s] Place %s" % [Settings.code_label(Settings.binding_of("attack")).replace(" Click", ""), pl.name]) if pl.ok else pl.reason)
		parts.append("[%s] Rotate" % Settings.code_label(Settings.binding_of("rotate_piece")))
		if holding_plan:
			parts.append("[%s] Building wheel" % Settings.code_label(Settings.binding_of("build_menu")))
	_prompt.text = "" if _wheel.visible or crafting else "     ".join(parts)   # the wheel has its own caption
	var eff: Array[String] = []
	for e: String in player.stats.effects:
		eff.append("%s %ds" % [ItemDB.EFFECTS[e].name, ceili(player.stats.effects[e])])
	if s.warmth <= 0.0:
		eff.append("Freezing! Find a fire")
	elif s.is_cold():
		eff.append("Cold")
	elif s.heat > 1.0 and s.warmth < s.max_warmth:
		eff.append("Warming up")
	_effects.text = "   ".join(eff)
	var frac := _target_health(look)
	_target_bar.visible = frac >= 0.0 and frac < 0.999
	if _target_bar.visible:
		_target_bar.value = frac
	_hit_marker = maxf(_hit_marker - delta * 3.0, 0.0)
	_crosshair_scale = lerpf(_crosshair_scale, 1.0 if look.is_empty() else 2.4, 1.0 - exp(-14.0 * delta))
	_crosshair.queue_redraw()

	# Screen effects.
	_damage = maxf(_damage - delta * 0.9, 0.0)
	var low := 1.0 - clampf(s.health / s.max_health / 0.3, 0.0, 1.0)
	(_damage_fx.material as ShaderMaterial).set_shader_parameter("intensity", maxf(_damage, low * 0.5))
	var water_target := 0.85 if player.underwater else 0.0
	var wm := _water_fx.material as ShaderMaterial
	wm.set_shader_parameter("intensity", lerpf(float(wm.get_shader_parameter("intensity")), water_target, 1.0 - exp(-10.0 * delta)))
	wm.set_shader_parameter("softness", 0.95)

	_debug.visible = _debug_on or Settings.show_fps
	if _debug.visible:
		var p := player.global_position
		_debug.text = "%d FPS" % Engine.get_frames_per_second()
		if _debug_on:
			_debug.text += "\npos %.0f, %.0f, %.0f\nchunks %d\nseed %d" % [p.x, p.y, p.z, world.get_chunk_count(), Game.world_seed]


## 0..1 health of what the crosshair is on (-1 if it has none).
func _target_health(look: Dictionary) -> float:
	if look.has("animal"):
		if not is_instance_valid(look.animal):
			return -1.0
		var a: Node = look.animal
		return a.carcass_hp / (60.0 * a.species.yield_scale) if a.dead else a.hp / a.species.hp
	if look.has("resource"):
		var r: Dictionary = look.resource
		if FloraLibrary.KINDS[r.kind].get("min_tier", -2) == -2 and float(r.hp) >= float(FloraLibrary.KINDS[r.kind].hp):
			return -1.0
		return float(r.hp) / float(FloraLibrary.KINDS[r.kind].hp)
	return -1.0


## Flash an "x" on the crosshair when a hit lands.
func hit_marker() -> void:
	_hit_marker = 1.0


func _draw_crosshair() -> void:
	if _hit_marker > 0.0:
		var k := 6.0 + (1.0 - _hit_marker) * 4.0
		var c := Color(1, 0.92, 0.8, _hit_marker)
		for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			_crosshair.draw_line(d * k, d * (k + 6.0), c, 2.0, true)
	var r := 2.5 * _crosshair_scale
	if _crosshair_scale > 1.3:
		_crosshair.draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(0, 0, 0, 0.4), 3.0, true)
		_crosshair.draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(1, 1, 1, 0.9), 1.6, true)
	else:
		_crosshair.draw_circle(Vector2.ZERO, r + 1.0, Color(0, 0, 0, 0.45))
		_crosshair.draw_circle(Vector2.ZERO, r, Color(1, 1, 1, 0.95))
