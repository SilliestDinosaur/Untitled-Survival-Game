class_name StatBar
extends Control
## A smooth, rounded stat bar with a "ghost" trail that shows recent losses.

var color := Color.WHITE
var tag := ""
var value := 1.0          ## 0..1 target
var auto_hide := false    ## fade out when full (stamina)
var warn_below := 0.25    ## pulse when this low

var _shown := 1.0
var _ghost := 1.0
var _ghost_delay := 0.0
var _time := 0.0


func _init(c: Color, t: String) -> void:
	color = c
	tag = t
	custom_minimum_size = Vector2(270, 22)
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
	var font := get_theme_default_font()
	var tag_w := 64.0
	draw_string(font, Vector2(1, 17), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.4))
	draw_string(font, Vector2(0, 16), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	var r := Rect2(tag_w, 6, size.x - tag_w, 10)
	_rounded(r, Color(0, 0, 0, 0.45))
	if _ghost > _shown:
		_rounded(Rect2(r.position, Vector2(r.size.x * _ghost, r.size.y)), Color(1, 1, 1, 0.35))
	var c := color
	if value < warn_below:
		c = c.lerp(Color.WHITE, (sin(_time * 7.0) * 0.5 + 0.5) * 0.45)
	if _shown > 0.005:
		_rounded(Rect2(r.position, Vector2(maxf(r.size.x * _shown, r.size.y), r.size.y)), c)
		# subtle top highlight
		draw_rect(Rect2(r.position + Vector2(3, 1), Vector2(maxf(r.size.x * _shown - 6, 0), 2)), Color(1, 1, 1, 0.18))


func _rounded(r: Rect2, c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
