extends Control
## The journal page (the journal key): the player's milestones in groups, ticked as they're earned, with the day each
## was. Also home to the first-steps guide in the corner of the screen and the little toast shown when a milestone
## is earned (see Guide and Toast below; the HUD holds those).

const Progress := preload("res://scripts/gameplay/progress.gd")

var player: Node3D
var _body: VBoxContainer
var _sub: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 17, 34, 30, 200))
	UITheme.place(panel, Control.PRESET_CENTER, Vector2(-620, -380), Vector2(1240, 760))
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UITheme.heading("Journal", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.label("%s or Esc to close" % Progress.key_name("journal"), 16, UITheme.INK_DIM))
	_sub = UITheme.label("", 18, UITheme.INK_DIM)
	col.add_child(_sub)
	col.add_child(UITheme.divider())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func open() -> void:
	_fill()
	visible = true


func _fill() -> void:
	for c in _body.get_children():
		c.queue_free()
	var p: Dictionary = player.progress
	var done: Dictionary = p.get("done", {})
	var lands := (p.get("biomes", {}) as Dictionary).size()
	_sub.text = "%s  ·  Day %d  ·  %d of %d milestones  ·  %d %s walked  ·  %d of %d landmarks found" % [Game.world_name, Game.day,
		done.size(), Progress.MILESTONES.size(), lands, "land" if lands == 1 else "lands",
		(p.get("landmarks", {}) as Dictionary).size(), Game.world_gen.landmarks.size() if Game.world_gen else 0]
	# Four columns, the short Hunting list under Survival, so it all fits on the page.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	_body.add_child(cols)
	for groups: Array in [["Survival", "Hunting"], ["Crafting"], ["Exploring"], ["Landmarks"]]:
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(278, 0)
		box.add_theme_constant_override("separation", 6)
		cols.add_child(box)
		for g: String in groups:
			if box.get_child_count() > 0:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 10)
				box.add_child(gap)
			box.add_child(UITheme.label(g, 24, UITheme.ACCENT, 0, true))
			for m: Array in Progress.MILESTONES:
				if m[1] == g:
					box.add_child(_row(m, done))


func _row(m: Array, done: Dictionary) -> Control:
	var got := done.has(m[0])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tick := Tick.new()
	tick.on = got
	row.add_child(tick)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var t := UITheme.label(String(m[2]) + ("   (day %d)" % int(done[m[0]]) if got else ""), 19, UITheme.INK if got else UITheme.INK_DIM)
	if got:
		t.add_theme_font_override("font", UITheme.BOLD_FONT)
	text.add_child(t)
	var d := UITheme.label(m[3], 15, UITheme.INK_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(236, 0)
	text.add_child(d)
	return row


## A hand-drawn check box, ticked or not.
class Tick extends Control:
	var on := false
	var grow := 1.0   ## 0..1 while the tick is being drawn in

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(3, 4), Vector2(17, 17))
		var pts := UITheme.stroke_polygon(r, 7, 0.08, 12)
		pts.append(pts[0])
		draw_polyline(pts, Color(UITheme.INK, 0.7), 1.8, true)
		if on:
			var a := Vector2(6, 12)
			var b := Vector2(10.5, 17.5)
			var c := Vector2(21, 3)
			var k := clampf(grow, 0.0, 1.0)
			if k < 0.4:
				draw_line(a, a.lerp(b, k / 0.4), UITheme.ACCENT, 3.0, true)
			else:
				draw_polyline(PackedVector2Array([a, b, b.lerp(c, (k - 0.4) / 0.6)]), UITheme.ACCENT, 3.0, true)


## The first steps, in the corner: the step to do now and the one after it, ticked off as they're done, gone once
## the basics are learned (with a pointer to the journal). Off in the settings if you'd rather not.
class Guide extends PanelContainer:
	var player: Node3D
	var _rows: VBoxContainer
	var _shown := -2       ## the step shown at the top (-1: all done)
	var _finished := false
	var _ticking := false

	func _init() -> void:
		add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 23, 18, 22, 128))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(360, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		add_child(col)
		col.add_child(UITheme.label("First steps", 20, UITheme.ACCENT, 0, true))
		_rows = VBoxContainer.new()
		_rows.add_theme_constant_override("separation", 6)
		col.add_child(_rows)
		modulate.a = 0.0
		visible = false

	## Called when the progress changes (and once on start). `just_done`: steps finished just now (they tick first).
	func refresh(just_done: Array) -> void:
		if not player or player.progress.is_empty():
			return
		if _ticking:
			return   # the tick in progress moves on to whatever step is current when it's done
		var p: Dictionary = player.progress
		var step := Progress.guide_step(p)
		var want := Settings.show_guide and not _finished
		if step == -1 and not _finished:
			_finished = true
			if just_done.is_empty():
				want = false   # learned in an earlier session: nothing to show
			else:
				_show_done()
				return
		if not want:
			_fade(false)
			return
		if step == _shown and just_done.is_empty():
			_fade(true)
			return
		if not just_done.is_empty() and _rows.get_child_count() > 0:
			# Tick the one just done, then move on (to the step current by then: several can finish at once).
			var tick: Tick = _rows.get_child(0).get_child(0)
			tick.on = true
			_ticking = true
			var tw := tick.create_tween()   # (dies with the tick)
			tw.tween_property(tick, "grow", 1.0, 0.35).from(0.0)
			tw.parallel().tween_method(func(_k: float) -> void: tick.queue_redraw(), 0.0, 1.0, 0.35)
			var later := create_tween()
			later.tween_interval(1.25)
			later.tween_callback(func() -> void:
				_ticking = false
				var now := Progress.guide_step(player.progress)
				if now == -1:
					refresh([""])
				else:
					_build(now))
			Audio.play(Audio.sfx.chime, -10.0, 1.15)
		else:
			_build(step)
		_fade(true)

	func _build(step: int) -> void:
		_shown = step
		for c in _rows.get_children():
			c.queue_free()
		for i in [step, step + 1]:
			if i < 0 or i >= Progress.GUIDE.size():
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var tick := Tick.new()
			row.add_child(tick)
			var l := UITheme.label(Progress.guide_text(Progress.GUIDE[i]), 17 if i == step else 15, UITheme.INK if i == step else UITheme.INK_DIM)
			if i == step:
				l.add_theme_font_override("font", UITheme.BOLD_FONT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(300, 0)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			_rows.add_child(row)

	func _show_done() -> void:
		for c in _rows.get_children():
			c.queue_free()
		var l := UITheme.label("You've got the basics. Your journal (%s) has more to aim for." % Progress.key_name("journal"), 16, UITheme.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(320, 0)
		_rows.add_child(l)
		_fade(true)
		var tw := create_tween()
		tw.tween_interval(8.0)
		tw.tween_callback(func() -> void: _fade(false))

	func _fade(on: bool) -> void:
		if on:
			visible = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0 if on else 0.0, 0.5)
		if not on:
			tw.tween_callback(func() -> void: visible = false)


## "Journal: Through the night" when a milestone is earned: slides in under the compass, one at a time.
class Toast extends PanelContainer:
	var _queue: Array = []
	var _busy := false
	var _title: Label

	func _init() -> void:
		add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 31, 14, 20, 128))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		add_child(col)
		var small := UITheme.label("New in your journal", 14, UITheme.INK_DIM)
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(small)
		_title = UITheme.label("", 24, UITheme.INK, 0, true)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(_title)
		modulate.a = 0.0
		visible = false

	func show_milestone(id: String) -> void:
		var m := Progress.milestone(id)
		if m.is_empty():
			return
		_queue.append(m)
		if not _busy:
			_next()

	func _next() -> void:
		if _queue.is_empty():
			_busy = false
			visible = false
			return
		_busy = true
		var m: Array = _queue.pop_front()
		_title.text = m[2]
		visible = true
		Audio.play(Audio.sfx.chime, -6.0)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.4)
		tw.tween_interval(3.2)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(_next)
