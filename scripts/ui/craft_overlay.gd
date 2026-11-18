class_name CraftOverlay
extends Control
## The cues for a crafting minigame, drawn over the station view and anchored to the piece being worked:
## a ring closing on the strike point (anvil, knapping), a marker sweeping past a mark (workbench), a dial
## that browns round to "turn now" (campfire), and the forge's heat gauge. Plus what's being made, how far
## along it is, what to do, and how the last strike went.

const GREEN := Color(0.56, 0.86, 0.45)
const OCHRE := UITheme.ACCENT_2
const SHADE := Color(0.08, 0.06, 0.04, 0.55)

var session: CraftSession


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not session or not is_instance_valid(session):
		return
	var cam := get_viewport().get_camera_3d()
	var wp := session.work_point()
	var p := size * 0.5
	if cam and not cam.is_position_behind(wp):
		p = cam.unproject_position(wp)
	match session.mode:
		CraftSession.Mode.COOK:
			_dial(p + Vector2(120, -30))
		CraftSession.Mode.CARVE:
			_sweep(p + Vector2(0, 80))
		CraftSession.Mode.SMELT:
			_heat(p + Vector2(150, -110))
		CraftSession.Mode.SMITH:
			if session.phase == 0:
				_heat(p + Vector2(150, -110))
			else:
				_ring(p)
		CraftSession.Mode.KNAP:
			_ring(p)
	_feedback(p)
	_panel()


## A ring closing on the strike point: click as it lands on the mark.
func _ring(p: Vector2) -> void:
	var t := session.cue_t
	var r_mark := 26.0
	var r := lerpf(120.0, r_mark, minf(t, 1.0)) if t <= 1.0 else r_mark * (1.0 - (t - 1.0) * 1.5)
	draw_arc(p, r_mark, 0, TAU, 40, SHADE, 7.0, true)
	draw_arc(p, r_mark, 0, TAU, 40, GREEN, 3.0, true)
	if r > 2.0:
		var q := clampf(1.0 - absf(t - 1.0) / 0.2, 0.0, 1.0)
		draw_arc(p, r, 0, TAU, 48, SHADE, 6.0, true)
		draw_arc(p, r, 0, TAU, 48, OCHRE.lerp(GREEN, q), 3.0, true)


## The workbench: a marker sweeps along a bar under the piece; click as it crosses the mark.
func _sweep(p: Vector2) -> void:
	var w := 320.0
	var h := 16.0
	var x0 := p.x - w * 0.5
	draw_rect(Rect2(x0 - 4, p.y - h * 0.5 - 4, w + 8, h + 8), SHADE)
	draw_rect(Rect2(x0, p.y - h * 0.5, w, h), Color(0.95, 0.91, 0.82, 0.25))
	var good := 0.11 * (1.0 - CraftSession.GOOD_Q)
	var perfect := 0.11 * (1.0 - CraftSession.PERFECT_Q)
	draw_rect(Rect2(x0 + (session.target - good) * w, p.y - h * 0.5, good * 2.0 * w, h), Color(OCHRE, 0.75))
	draw_rect(Rect2(x0 + (session.target - perfect) * w, p.y - h * 0.5, perfect * 2.0 * w, h), GREEN)
	var mx := x0 + session.sweep_pos() * w
	draw_line(Vector2(mx, p.y - h), Vector2(mx, p.y + h), SHADE, 6.0)
	draw_line(Vector2(mx, p.y - h), Vector2(mx, p.y + h), UITheme.TEXT, 3.0)


## The campfire: a dial browns round; click (turn the spit) when it reaches the green.
func _dial(p: Vector2) -> void:
	var r := 34.0
	draw_circle(p, r + 8.0, SHADE)
	draw_arc(p, r, 0, TAU, 40, Color(0.95, 0.91, 0.82, 0.25), 8.0, true)
	var good := 0.12 * (1.0 - CraftSession.GOOD_Q)
	var perfect := 0.12 * (1.0 - CraftSession.PERFECT_Q)
	_arc(p, r, 0.85 - good, 0.85 + good, Color(OCHRE, 0.8), 8.0)
	_arc(p, r, 0.85 - perfect, 0.85 + perfect, GREEN, 8.0)
	_arc(p, r, 0.0, session.cue_t, Color(0.86, 0.5, 0.25), 4.0)
	var a := -PI * 0.5 + session.cue_t * TAU
	draw_line(p, p + Vector2(cos(a), sin(a)) * (r + 6.0), UITheme.TEXT, 3.0, true)


func _arc(p: Vector2, r: float, from: float, to: float, col: Color, width: float) -> void:
	if to <= from:
		return
	draw_arc(p, r, -PI * 0.5 + from * TAU, -PI * 0.5 + to * TAU, maxi(4, roundi((to - from) * 48.0)), col, width, true)


## The forge: how hot the fire is. Fastest in the green band, slow just below it, nothing when cold or too hot.
func _heat(p: Vector2) -> void:
	var h := 200.0
	var w := 24.0
	var top := p.y
	draw_rect(Rect2(p.x - 4, top - 4, w + 8, h + 8), SHADE)
	var y_of := func(v: float) -> float: return top + h * (1.0 - v)
	var band := CraftSession.HEAT_BAND
	draw_rect(Rect2(p.x, y_of.call(band.x), w, y_of.call(CraftSession.HEAT_WARM) - y_of.call(band.x)), Color(OCHRE, 0.45))
	draw_rect(Rect2(p.x, y_of.call(band.y), w, y_of.call(band.x) - y_of.call(band.y)), Color(GREEN, 0.6))
	var heat := session.heat
	var col := Color(0.55, 0.2, 0.1).lerp(Color(1.0, 0.75, 0.3), heat)
	draw_rect(Rect2(p.x + 5, y_of.call(heat), w - 10, h - (y_of.call(heat) - top)), col)
	draw_line(Vector2(p.x - 6, y_of.call(heat)), Vector2(p.x + w + 6, y_of.call(heat)), UITheme.TEXT, 3.0)
	var word := "Too hot!" if heat > band.y else ("Hot" if heat >= band.x else ("Warm" if heat >= CraftSession.HEAT_WARM else "Cold"))
	_text(Vector2(p.x + w * 0.5, top - 12), word, 18, UITheme.TEXT)


func _feedback(p: Vector2) -> void:
	var fb := session.feedback
	if not fb.has("age") or fb.age > 0.9:
		return
	var a := 1.0 - smoothstep(0.5, 0.9, fb.age)
	var col: Color = fb.color
	col.a = a
	_text(p + Vector2(0, -80 - fb.age * 30.0), String(fb.text), 26, col)


## What's being made, how far along, and what to do.
func _panel() -> void:
	var total := session.made + session.left
	var title := ItemDB.display_name(String(session.recipe.out))
	if total > 1:
		title += "   %d of %d" % [mini(session.made + 1, total), total]
	_text(Vector2(size.x * 0.5, 64), title, 30, UITheme.TEXT)
	var w := 380.0
	var y := size.y - 120.0
	var x0 := size.x * 0.5 - w * 0.5
	draw_rect(Rect2(x0 - 4, y - 4, w + 8, 22), SHADE)
	draw_rect(Rect2(x0, y, w * clampf(session.progress, 0.0, 1.0), 14), OCHRE)
	var key := Settings.code_label(Settings.binding_of("attack")).replace(" Click", "")
	_text(Vector2(size.x * 0.5, y + 46), _how(key), 19, UITheme.TEXT)
	_text(Vector2(size.x * 0.5, y + 74), "[Esc] Stop", 15, UITheme.TEXT_DIM)


func _how(key: String) -> String:
	match session.mode:
		CraftSession.Mode.COOK:
			return "[%s] %s when the dial reaches the green" % [key, "Stir" if session.recipe.out == "stew" else "Turn the spit"]
		CraftSession.Mode.SMELT:
			return "Hold [%s] to pump the bellows. Keep the heat in the green" % key
		CraftSession.Mode.SMITH:
			if session.phase == 0:
				return "Hold [%s] to pump the bellows and heat the head" % key
			return "[%s] Strike as the ring closes on the mark" % key
		CraftSession.Mode.CARVE:
			return "[%s] Strike as the marker crosses the mark" % key
	return "[%s] Strike as the ring closes on the edge" % key


func _text(center: Vector2, text: String, font_size: int, col: Color) -> void:
	var font := UITheme.BOLD_FONT
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := center - Vector2(w * 0.5, -font_size * 0.35)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.08, 0.06, 0.04, col.a * 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
