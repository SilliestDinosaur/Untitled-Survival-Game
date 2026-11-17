class_name StatBar
extends Control
## A hand-painted stat bar: an ink wash with a stroke of color on top,
## a pale "ghost" trail that shows recent losses, and a pulse when low.

var color := Color.WHITE
var tag := ""
var value := 1.0          ## 0..1 target
var auto_hide := false    ## fade out when full (stamina)
var warn_below := 0.25    ## pulse when this low

var _shown := 1.0
var _ghost := 1.0
var _ghost_delay := 0.0
var _time := 0.0
var _seed := 0


func _init(c: Color, t: String) -> void:
	color = c
	tag = t
	_seed = hash(t)
	custom_minimum_size = Vector2(290, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	if value < _shown - 0.01:
		_ghost_delay = 0.5
	_shown = lerpf(_shown, value, 1.0 - exp(-14.0 * delta))
	if _ghost_delay > 0.0:
		_ghost_delay -= delta
	else:
		_ghost = lerpf(_ghost, _shown, 1.0 - exp(-4.0 * delta))
	_ghost = maxf(_ghost, _shown)
	if auto_hide:
		var target := 0.0 if value >= 0.999 else 1.0
		modulate.a = lerpf(modulate.a, target, 1.0 - exp(-(3.0 if target > 0.5 else 1.5) * delta))
	queue_redraw()


func _draw() -> void:
	var tag_w := 70.0 if tag != "" else 6.0
	if tag != "":
		var font := UITheme.BOLD_FONT
		draw_string(font, Vector2(1, 19), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.08, 0.05, 0.03, 0.5))
		draw_string(font, Vector2(0, 18), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)
	var r := Rect2(tag_w, 7, size.x - tag_w - 6, 12)
	draw_colored_polygon(UITheme.stroke_polygon(r.grow(2), _seed, 0.14), Color(0.1, 0.07, 0.05, 0.5))
	if _ghost > _shown + 0.002:
		draw_colored_polygon(_clip(UITheme.stroke_polygon(r, _seed + 1, 0.12), r.position.x + r.size.x * _ghost), Color(1, 0.95, 0.85, 0.45))
	var c := color
	if value < warn_below:
		c = c.lerp(Color(1, 0.95, 0.85), (sin(_time * 7.0) * 0.5 + 0.5) * 0.4)
	if _shown > 0.005:
		draw_colored_polygon(_clip(UITheme.stroke_polygon(r, _seed + 2, 0.12), r.position.x + r.size.x * _shown), c)
		# A lighter streak along the top, like a loaded brush.
		draw_line(Vector2(r.position.x + 3, r.position.y + 3), Vector2(r.position.x + maxf(r.size.x * _shown - 4, 3), r.position.y + 3), Color(1, 1, 1, 0.22), 2.0, true)


## Cut a bar polygon off at x = limit (keeps the painted top/bottom edges).
func _clip(pts: PackedVector2Array, limit: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(minf(p.x, limit), p.y))
	return out
