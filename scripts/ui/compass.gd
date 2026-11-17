class_name Compass
extends Control
## Horizontal compass strip. North is -Z.

var heading := 0.0   ## degrees, 0 = north, 90 = east
const SPAN := 150.0  ## degrees visible across the strip
const LETTERS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}


func _init() -> void:
	custom_minimum_size = Vector2(520, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var mid := w * 0.5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.32)
	bg.set_corner_radius_all(8)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	for deg in range(0, 360, 15):
		var diff := wrapf(deg - heading, -180.0, 180.0)
		if absf(diff) > SPAN * 0.5:
			continue
		var x := mid + diff / (SPAN * 0.5) * (w * 0.5 - 16)
		var fade := 1.0 - pow(absf(diff) / (SPAN * 0.5), 2.0)
		if LETTERS.has(deg):
			var txt: String = LETTERS[deg]
			var major := deg % 90 == 0
			var fs := 17 if major else 13
			var col := (UITheme.ACCENT if deg == 0 else Color(1, 1, 1, 0.95 if major else 0.65))
			col.a *= fade
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(x - tw * 0.5, 23), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			draw_line(Vector2(x, 12), Vector2(x, 21), Color(1, 1, 1, 0.4 * fade), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(mid - 5, size.y), Vector2(mid + 5, size.y), Vector2(mid, size.y - 6)]), UITheme.ACCENT)
