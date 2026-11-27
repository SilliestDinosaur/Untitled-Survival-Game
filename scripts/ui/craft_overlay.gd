class_name CraftOverlay
extends Control
## The cues for a crafting minigame, drawn over the view and anchored to the work. Every step is a movement of the
## mouse, and the overlay shows the hand on the screen and what to do with it: a glowing spot to flick down
## through, a piece to grab and the place it goes, the stroke to make (side to side, up and down), the heat of the
## fire, the tip of the crucible and the mould's fill line, a circle to go round (and how fast).
## Plus what's being made, which step of how many, how far along, what to do, and how the last action went.

const GREEN := Color(0.56, 0.86, 0.45)
const OCHRE := UITheme.ACCENT_2
const RED := Color(0.95, 0.45, 0.35)
const SHADE := Color(0.08, 0.06, 0.04, 0.55)
const PALE := Color(0.95, 0.91, 0.82, 0.3)
const STEP_NAMES := {"knap": "Knap the head", "fit": "Fit the head on", "socket": "Bind the socket", "grip": "Wind the grip",
	"shape": "Shape the handle", "seat": "Seat the head", "wedge": "Drive the wedge", "heat": "Heat the bar",
	"hammer": "Hammer it out", "quench": "Quench it", "haft": "Fit the handle", "load": "Load the ore",
	"melt": "Melt it", "pour": "Pour", "tap": "Knock it out", "add": "Add the ingredients", "stir": "Stir",
	"skewer": "Skewer it", "cook": "Turn the spit"}

var session: CraftSession


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not session or not is_instance_valid(session):
		return
	var s := session.ui_scale()
	var p := session.screen(session.work_point())
	if not session._busy:
		match session.mech():
			CraftSession.Mech.FLICK: _flick(s)
			CraftSession.Mech.DRAG, CraftSession.Mech.DIP: _drag(s)
			CraftSession.Mech.SAW: _saw(s)
			CraftSession.Mech.PUMP:
				_pump(s)
				_heat(p + Vector2(150, -110) * s, s)
			CraftSession.Mech.TILT:
				_tilt(s)
				_fill(p + Vector2(150, -120) * s, s)
			CraftSession.Mech.STIR: _circle(p, s, true)
			CraftSession.Mech.WRAP: _circle(p, s, false)
	_feedback(p, s)
	_panel()


func _pulse(speed := 4.0) -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * speed)


## The hand: a ring with a dot (filled in while something's held).
func _hand(at: Vector2, s: float, holding := false) -> void:
	draw_circle(at, 13.0 * s, SHADE)
	draw_arc(at, 10.0 * s, 0, TAU, 24, UITheme.TEXT, 2.5 * s, true)
	draw_circle(at, (6.0 if holding else 3.0) * s, UITheme.TEXT)


## A chevron pointing along `dir`.
func _chevron(at: Vector2, dir: Vector2, size: float, col: Color, width: float) -> void:
	var side := dir.orthogonal()
	draw_polyline(PackedVector2Array([at - dir * size + side * size, at, at - dir * size - side * size]), col, width, true)


## Striking: the glowing spot, its sweet zone, and chevrons showing the flick down through it.
func _flick(s: float) -> void:
	var sp := session.screen(session.spot_world())
	var near := session.ptr.distance_to(sp) < CraftSession.FLICK_AIM * s
	var glow := Color(1.0, 0.8, 0.4).lerp(GREEN, 1.0 if near else _pulse() * 0.4)
	var perfect := CraftSession.FLICK_AIM * (1.0 - CraftSession.PERFECT_Q) * s
	draw_circle(sp, perfect + 10.0 * s * _pulse(), Color(glow, 0.18))
	draw_arc(sp, perfect, 0, TAU, 32, SHADE, 5.0 * s, true)
	draw_arc(sp, perfect, 0, TAU, 32, glow, 2.5 * s, true)
	draw_circle(sp, 5.0 * s, glow)
	# Chevrons running down through it: the way to flick.
	var t := fmod(Time.get_ticks_msec() / 1000.0 * 1.4, 1.0)
	for i in 3:
		var y := (-50.0 + (t + i / 3.0) * 100.0) * s
		var a := 1.0 - absf(y / (50.0 * s))
		_chevron(sp + Vector2(perfect + 26.0 * s, y), Vector2.DOWN, 7.0 * s, Color(UITheme.TEXT, 0.7 * a), 3.0 * s)
	_hand(session.ptr, s)


## Dragging: the piece to grab (while it's not held), the place it goes, and a line between them while it's held.
## Quenching, the ring over the water fills while the blade's held under.
func _drag(s: float) -> void:
	if session.drag_node == null:
		return
	var from := session.screen(session.drag_focus())
	var to := session.screen(session.drag_target())
	var snap := CraftSession.SNAP * s * (1.5 if session.mech() == CraftSession.Mech.DIP else 1.0)
	var close := from.distance_to(to) < snap
	var col := GREEN if close else Color(1.0, 0.85, 0.5)
	# Where it goes: a dashed ring (and the sweet middle).
	for i in 16:
		var a := TAU * i / 16.0 + Time.get_ticks_msec() / 1000.0 * 0.6
		draw_arc(to, snap, a, a + TAU / 32.0, 4, SHADE, 6.0 * s, true)
		draw_arc(to, snap, a, a + TAU / 32.0, 4, col, 3.0 * s, true)
	if session.mech() == CraftSession.Mech.DIP:
		var held := clampf(session.hold_t / CraftSession.DIP_HOLD, 0.0, 1.0)
		if held > 0.0:
			draw_arc(to, snap + 8.0 * s, -PI * 0.5, -PI * 0.5 + held * TAU, 40, Color(0.55, 0.8, 1.0), 5.0 * s, true)
	else:
		draw_circle(to, CraftSession.SNAP * (1.0 - CraftSession.PERFECT_Q) * s, Color(col, 0.25))
	if session.dragging:
		_dashes(from, to, Color(col, 0.6), s)
	elif not session._snapping:
		# What to grab: a pulsing ring round it.
		var r := (22.0 + 6.0 * _pulse(5.0)) * s
		draw_arc(from, r, 0, TAU, 32, SHADE, 6.0 * s, true)
		draw_arc(from, r, 0, TAU, 32, Color(1.0, 0.92, 0.7), 3.0 * s, true)
	_hand(session.ptr, s, session.dragging)


func _dashes(a: Vector2, b: Vector2, col: Color, s: float) -> void:
	var n := int(a.distance_to(b) / (14.0 * s))
	for i in range(0, n, 2):
		draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 3.0 * s, true)


## Shaping: a long track side to side, the hand on it, and how far into a stroke it is.
func _saw(s: float) -> void:
	var c := session._anchor
	var w := 150.0 * s
	draw_line(c - Vector2(w, 0), c + Vector2(w, 0), SHADE, 10.0 * s, true)
	draw_line(c - Vector2(w, 0), c + Vector2(w, 0), PALE, 4.0 * s, true)
	_chevron(c - Vector2(w + 10.0 * s, 0), Vector2.LEFT, 9.0 * s, UITheme.TEXT, 3.0 * s)
	_chevron(c + Vector2(w + 10.0 * s, 0), Vector2.RIGHT, 9.0 * s, UITheme.TEXT, 3.0 * s)
	# This stroke: green once it's long enough to count.
	var len := clampf(session._stroke / (CraftSession.SAW_STROKE * s), 0.0, 1.0)
	var dir := float(session._stroke_dir)
	if dir != 0.0:
		draw_line(Vector2(session.ptr.x, c.y), Vector2(session.ptr.x - dir * len * CraftSession.SAW_STROKE * s, c.y), GREEN if len >= 1.0 else OCHRE, 5.0 * s, true)
	_hand(session.ptr, s)
	_text(c + Vector2(0, 34) * s, "%d / %d strokes" % [session.strokes, int(CraftSession.SAW_STROKES)], int(16 * s), UITheme.TEXT_DIM)


## The bellows: a track up and down, the hand on it.
func _pump(s: float) -> void:
	var c := session._anchor
	var h := 100.0 * s
	draw_line(c - Vector2(0, h), c + Vector2(0, h), SHADE, 10.0 * s, true)
	draw_line(c - Vector2(0, h), c + Vector2(0, h), PALE, 4.0 * s, true)
	_chevron(c - Vector2(0, h + 10.0 * s), Vector2.UP, 9.0 * s, UITheme.TEXT, 3.0 * s)
	_chevron(c + Vector2(0, h + 10.0 * s), Vector2.DOWN, 9.0 * s, UITheme.TEXT, 3.0 * s)
	_hand(session.ptr, s)


## The forge: how hot the fire is. Fastest in the green band, slow just below it, nothing when cold or too hot.
func _heat(p: Vector2, s: float) -> void:
	var h := 200.0 * s
	var w := 24.0 * s
	var top := p.y
	draw_rect(Rect2(p.x - 4 * s, top - 4 * s, w + 8 * s, h + 8 * s), SHADE)
	var y_of := func(v: float) -> float: return top + h * (1.0 - v)
	var band := CraftSession.HEAT_BAND
	draw_rect(Rect2(p.x, y_of.call(band.x), w, y_of.call(CraftSession.HEAT_WARM) - y_of.call(band.x)), Color(OCHRE, 0.45))
	draw_rect(Rect2(p.x, y_of.call(band.y), w, y_of.call(band.x) - y_of.call(band.y)), Color(GREEN, 0.6))
	var heat := session.heat
	var col := Color(0.55, 0.2, 0.1).lerp(Color(1.0, 0.75, 0.3), heat)
	draw_rect(Rect2(p.x + 5 * s, y_of.call(heat), w - 10 * s, h - (y_of.call(heat) - top)), col)
	draw_line(Vector2(p.x - 6 * s, y_of.call(heat)), Vector2(p.x + w + 6 * s, y_of.call(heat)), UITheme.TEXT, 3.0 * s)
	var word := "Too hot!" if heat > band.y else ("Hot" if heat >= band.x else ("Warm" if heat >= CraftSession.HEAT_WARM else "Cold"))
	_text(Vector2(p.x + w * 0.5, top - 12 * s), word, int(18 * s), UITheme.TEXT)


## Pouring: a quarter dial for the crucible's tip (it pours past the first mark), the hand on it.
func _tilt(s: float) -> void:
	var c := session._anchor
	var w := 110.0 * s
	draw_line(c - Vector2(w, 0), c + Vector2(w, 0), SHADE, 10.0 * s, true)
	var pour_x := c.x - w + 2.0 * w * 0.3
	draw_line(c - Vector2(w, 0), Vector2(pour_x, c.y), PALE, 4.0 * s, true)
	draw_line(Vector2(pour_x, c.y), c + Vector2(w, 0), Color(1.0, 0.55, 0.15, 0.7), 4.0 * s, true)
	_text(c + Vector2(-w, 26 * s), "upright", int(14 * s), UITheme.TEXT_DIM)
	_text(c + Vector2(w, 26 * s), "tipped", int(14 * s), UITheme.TEXT_DIM)
	_hand(session.ptr, s)


## The mould's fill, with the line to stop at (and the brim it spills over).
func _fill(p: Vector2, s: float) -> void:
	var h := 200.0 * s
	var w := 24.0 * s
	var top := p.y
	draw_rect(Rect2(p.x - 4 * s, top - 4 * s, w + 8 * s, h + 8 * s), SHADE)
	var y_of := func(v: float) -> float: return top + h * (1.0 - v)
	var band := CraftSession.POUR_BAND
	draw_rect(Rect2(p.x, y_of.call(band.y), w, y_of.call(band.x) - y_of.call(band.y)), Color(GREEN, 0.6))
	draw_rect(Rect2(p.x, top, w, y_of.call(band.y) - top), Color(0.9, 0.35, 0.25, 0.4))
	var f := clampf(session.fill, 0.0, 1.0)
	draw_rect(Rect2(p.x + 5 * s, y_of.call(f), w - 10 * s, h - (y_of.call(f) - top)), Color(1.0, 0.55, 0.15))
	_text(Vector2(p.x + w * 0.5, top - 12 * s), "Tip back!" if f >= band.x else "Pour", int(18 * s), UITheme.TEXT)


## Circling: a ring round the work, the hand going round it, and the ring filling as it goes. Stirring and turning
## also show the pace: green when it's steady, red when it's too fast.
func _circle(p: Vector2, s: float, paced: bool) -> void:
	var r := 70.0 * s
	var pace_col := GREEN
	if paced:
		var rate := session.turn_rate
		pace_col = RED if rate > CraftSession.STIR_PACE.y else (GREEN if rate >= CraftSession.STIR_PACE.x else OCHRE)
	draw_arc(p, r, 0, TAU, 48, SHADE, 10.0 * s, true)
	draw_arc(p, r, 0, TAU, 48, PALE, 4.0 * s, true)
	_arc(p, r, 0.0, clampf(session.step_t, 0.0, 1.0), pace_col if paced else GREEN, 5.0 * s)
	var dot := p + session.wrap_vec.normalized() * r
	_hand(dot, s)
	# Arrows round the circle, showing the way to go.
	var t := fmod(Time.get_ticks_msec() / 1000.0, TAU)
	for i in 3:
		var a := t + TAU * i / 3.0
		var at := p + Vector2(cos(a), sin(a)) * (r + 18.0 * s)
		_chevron(at, Vector2(-sin(a), cos(a)), 6.0 * s, Color(UITheme.TEXT, 0.6), 3.0 * s)
	if paced:
		var rate := session.turn_rate
		var word := "Too fast!" if rate > CraftSession.STIR_PACE.y else ("Steady" if rate >= CraftSession.STIR_PACE.x else "Faster")
		_text(p + Vector2(0, r + 40.0 * s), word, int(17 * s), pace_col)


func _arc(p: Vector2, r: float, from: float, to: float, col: Color, width: float) -> void:
	if to <= from:
		return
	draw_arc(p, r, -PI * 0.5 + from * TAU, -PI * 0.5 + to * TAU, maxi(4, roundi((to - from) * 48.0)), col, width, true)


func _feedback(p: Vector2, s: float) -> void:
	var fb := session.feedback
	var life := 1.8 if fb.get("long", false) else 0.9
	if not fb.has("age") or fb.age > life:
		return
	var a := 1.0 - smoothstep(life * 0.55, life, fb.age)
	var col: Color = fb.color
	col.a = a
	_text(p + Vector2(0, -80 * s - fb.age * 30.0 * s), String(fb.text), int(26 * s), col)


## What's being made, which step, how far along, and what to do.
func _panel() -> void:
	var total := session.made + session.left
	var title := ItemDB.display_name(String(session.recipe.out))
	if total > 1:
		title += "   %d of %d" % [mini(session.made + 1, total), total]
	_text(Vector2(size.x * 0.5, 64), title, 30, UITheme.TEXT)
	var n := session.steps.size()
	if n > 0:
		var name: String = STEP_NAMES.get(session.step_id(), "")
		_text(Vector2(size.x * 0.5, 100), "Step %d of %d  ·  %s" % [mini(session.step + 1, n), n, name], 18, UITheme.TEXT_DIM)
	var w := 380.0
	var y := size.y - 120.0
	var x0 := size.x * 0.5 - w * 0.5
	draw_rect(Rect2(x0 - 4, y - 4, w + 8, 22), SHADE)
	draw_rect(Rect2(x0, y, w * clampf(session.progress, 0.0, 1.0), 14), OCHRE)
	for i in range(1, n):   # step marks along the bar
		var mx := x0 + w * float(i) / n
		draw_line(Vector2(mx, y - 2), Vector2(mx, y + 16), Color(0.08, 0.06, 0.04, 0.8), 2.0)
	var key := Settings.code_label(Settings.binding_of("attack")).replace(" Click", "")
	var say := String(session.cur().get("say", "")).replace("{key}", "[%s]" % key)
	_text(Vector2(size.x * 0.5, y + 46), say, 19, UITheme.TEXT)
	_text(Vector2(size.x * 0.5, y + 74), "[Esc] Stop", 15, UITheme.TEXT_DIM)


func _text(center: Vector2, text: String, font_size: int, col: Color) -> void:
	var font := UITheme.BOLD_FONT
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := center - Vector2(w * 0.5, -font_size * 0.35)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.08, 0.06, 0.04, col.a * 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
