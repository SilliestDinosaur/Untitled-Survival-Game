class_name ItemIcon
extends Control
## Draws a small painted-style icon for an item, entirely in code (no image files).

var item := "":
	set(v):
		item = v
		queue_redraw()


func _init(id := "", size_px := 40.0) -> void:
	item = id
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if item == "":
		return
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var pal: WorldPalette = Game.palette
	match item:
		"wood":
			for i in 2:
				var y := c.y + (i - 0.5) * s * 0.26
				var col := pal.bark.lightened(0.1 * i)
				_capsule(Vector2(c.x - s * 0.3, y), Vector2(c.x + s * 0.3, y), s * 0.13, col)
				draw_circle(Vector2(c.x + s * 0.3, y), s * 0.1, Color(0.85, 0.7, 0.5))
				draw_arc(Vector2(c.x + s * 0.3, y), s * 0.05, 0, TAU, 12, col.darkened(0.2), 1.0)
		"stone", "rock":
			_blob(c, s * 0.32, pal.rock.lightened(0.05), 7, 3)
			if item == "rock":
				draw_arc(c, s * 0.4, -0.6, 0.6, 8, Color(1, 1, 1, 0.5), 2.0)
		"metal_ore":
			_blob(c + Vector2(0, s * 0.05), s * 0.3, pal.rock, 7, 5)
			for i in 3:
				var base := c + Vector2((i - 1) * s * 0.14, -s * 0.02)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.05, 0), base + Vector2(s * 0.05, 0), base + Vector2(0, -s * 0.25 + i % 2 * s * 0.06)]), pal.ore_crystal)
		"fiber":
			for i in 5:
				var x := c.x + (i - 2) * s * 0.07
				var pts := PackedVector2Array()
				for k in 6:
					var t := k / 5.0
					pts.append(Vector2(x + sin(t * 3.0 + i) * s * 0.08, c.y + s * 0.35 - t * s * 0.7))
				draw_polyline(pts, pal.meadow_grass.lerp(Color(0.8, 0.75, 0.4), 0.3), 2.5, true)
		"berries":
			for i in 7:
				var a := i * 2.4
				var r := s * (0.0 if i == 0 else 0.16)
				var p := c + Vector2(cos(a), sin(a)) * r
				draw_circle(p, s * 0.11, pal.berry.darkened(0.1))
				draw_circle(p + Vector2(-s * 0.03, -s * 0.03), s * 0.035, Color(1, 1, 1, 0.5))
		"raw_meat":
			_blob(c, s * 0.3, Color(0.8, 0.35, 0.38), 9, 11)
			draw_arc(c, s * 0.18, 0.5, 2.5, 10, Color(1, 0.85, 0.85, 0.7), 3.0)
			_capsule(c + Vector2(s * 0.15, s * 0.15), c + Vector2(s * 0.38, s * 0.38), s * 0.05, Color(0.95, 0.93, 0.86))
		"hide":
			_blob(c, s * 0.34, Color(0.6, 0.45, 0.32), 10, 17)
			_blob(c, s * 0.2, Color(0.7, 0.55, 0.4), 8, 19)
		"bone":
			var a := c + Vector2(-s * 0.28, s * 0.28)
			var b := c + Vector2(s * 0.28, -s * 0.28)
			_capsule(a, b, s * 0.06, Color(0.95, 0.93, 0.86))
			for p in [a, b]:
				draw_circle(p + Vector2(-s * 0.05, -s * 0.05), s * 0.07, Color(0.95, 0.93, 0.86))
				draw_circle(p + Vector2(s * 0.05, s * 0.05), s * 0.07, Color(0.95, 0.93, 0.86))
		_:
			draw_circle(c, s * 0.3, Color(1, 1, 1, 0.5))


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0, true)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


## Irregular rounded shape with a lighter top-left highlight (painted look).
func _blob(c: Vector2, r: float, col: Color, points: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in points:
		var a := TAU * i / points
		pts.append(c + Vector2(cos(a), sin(a) * 0.85) * r * rng.randf_range(0.8, 1.1))
	draw_colored_polygon(pts, col.darkened(0.15))
	var hi := PackedVector2Array()
	for p in pts:
		hi.append(c + (p - c) * 0.75 + Vector2(-r * 0.12, -r * 0.12))
	draw_colored_polygon(hi, col)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.15, Color(1, 1, 1, 0.25))
