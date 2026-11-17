class_name Compass
extends Control
## A parchment ribbon compass with ink bearings. North is -Z.

var heading := 0.0   ## degrees, 0 = north, 90 = east
## Other players: [{bearing: degrees from north, name, color}] shown as dots on the strip.
var markers: Array = []
const SPAN := 150.0  ## degrees visible across the strip
const LETTERS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}


func _init() -> void:
	custom_minimum_size = Vector2(520, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var mid := w * 0.5
	draw_texture_rect(UITheme.stroke_texture(Color(UITheme.PAPER, 0.92), 31, 512, 64), Rect2(Vector2(-14, -10), Vector2(w + 28, size.y + 20)), false)
	for deg in range(0, 360, 15):
		var diff := wrapf(deg - heading, -180.0, 180.0)
		if absf(diff) > SPAN * 0.5:
			continue
		var x := mid + diff / (SPAN * 0.5) * (w * 0.5 - 30)
		var fade := 1.0 - pow(absf(diff) / (SPAN * 0.5), 2.0)
		if LETTERS.has(deg):
			var txt: String = LETTERS[deg]
			var major := deg % 90 == 0
			var fs := 21 if major else 15
			var col := UITheme.ACCENT if deg == 0 else Color(UITheme.INK, 0.95 if major else 0.6)
			col.a *= fade
			var font := UITheme.HEADING_FONT
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(x - tw * 0.5, 27), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			draw_line(Vector2(x, 14), Vector2(x, 24), Color(UITheme.INK, 0.45 * fade), 1.5, true)
	for m: Dictionary in markers:
		var diff := wrapf(float(m.bearing) - heading, -180.0, 180.0)
		if absf(diff) > SPAN * 0.5:
			continue
		var x := mid + diff / (SPAN * 0.5) * (w * 0.5 - 30)
		var at := Vector2(x, 7.0)
		draw_circle(at, 7.5, Color(0.12, 0.09, 0.07, 0.85))
		draw_circle(at, 5.8, m.color)
		var font := UITheme.BOLD_FONT
		var initial: String = String(m.name).substr(0, 1).to_upper()
		var iw := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, at + Vector2(-iw * 0.5, 4.0), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))
	draw_colored_polygon(PackedVector2Array([Vector2(mid - 6, size.y + 4), Vector2(mid + 6, size.y + 4), Vector2(mid, size.y - 4)]), UITheme.ACCENT)
