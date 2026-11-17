class_name ItemIcon
extends Control
## Draws a small painted-style icon for any item (including generated ones) from its
## "icon" type and colors, entirely in code (no image files).

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
	var info := ItemDB.info(item)
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var pal: WorldPalette = Game.palette
	var col: Color = info.get("color", Color(0.8, 0.8, 0.8))
	match String(info.get("icon", "")):
		"logs":
			for i in 2:
				var y := c.y + (i - 0.5) * s * 0.26
				var lc := pal.bark.lightened(0.1 * i)
				_capsule(Vector2(c.x - s * 0.3, y), Vector2(c.x + s * 0.3, y), s * 0.13, lc)
				draw_circle(Vector2(c.x + s * 0.3, y), s * 0.1, Color(0.85, 0.7, 0.5))
				draw_arc(Vector2(c.x + s * 0.3, y), s * 0.05, 0, TAU, 12, lc.darkened(0.2), 1.0)
		"sticks":
			for i in 3:
				var a := Vector2(c.x - s * 0.32, c.y + s * (0.18 - i * 0.12))
				var b := Vector2(c.x + s * 0.32, c.y + s * (-0.1 + i * 0.1))
				_capsule(a, b, s * 0.035, pal.bark.lightened(0.15 + i * 0.05))
		"stone":
			_blob(c, s * 0.32, pal.rock.lightened(0.05), 7, 3)
		"flint":
			var pts := PackedVector2Array([c + Vector2(-0.3, 0.2) * s, c + Vector2(-0.05, -0.32) * s, c + Vector2(0.3, -0.05) * s, c + Vector2(0.12, 0.28) * s])
			draw_colored_polygon(pts, Color(0.35, 0.37, 0.42))
			draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c + Vector2(0.02, 0.0) * s]), Color(0.55, 0.57, 0.62))
		"ore":
			_blob(c + Vector2(0, s * 0.05), s * 0.3, pal.rock, 7, 5)
			for i in 3:
				var base := c + Vector2((i - 1) * s * 0.14, -s * 0.02)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.06, 0), base + Vector2(s * 0.06, 0), base + Vector2(0, -s * 0.22 + i % 2 * s * 0.06)]), col)
		"gem":
			for i in 3:
				var base := c + Vector2((i - 1) * s * 0.16, s * 0.25)
				var h := s * (0.5 if i == 1 else 0.35)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.08, 0), base + Vector2(s * 0.08, 0), base + Vector2(s * 0.05, -h), base + Vector2(0, -h - s * 0.08), base + Vector2(-s * 0.05, -h)]), col.lightened(i * 0.1))
			draw_circle(c + Vector2(-s * 0.03, -s * 0.12), s * 0.04, Color(1, 1, 1, 0.6))
		"fiber":
			for i in 5:
				var x := c.x + (i - 2) * s * 0.07
				var pts := PackedVector2Array()
				for k in 6:
					var t := k / 5.0
					pts.append(Vector2(x + sin(t * 3.0 + i) * s * 0.08, c.y + s * 0.35 - t * s * 0.7))
				draw_polyline(pts, pal.meadow_grass.lerp(Color(0.8, 0.75, 0.4), 0.3), 2.5, true)
		"resin":
			_blob(c, s * 0.24, Color(0.85, 0.6, 0.2), 9, 21)
			draw_circle(c + Vector2(-s * 0.08, -s * 0.08), s * 0.06, Color(1, 0.95, 0.7, 0.7))
		"berries":
			for i in 7:
				var a := i * 2.4
				var r := s * (0.0 if i == 0 else 0.16)
				var p := c + Vector2(cos(a), sin(a)) * r
				draw_circle(p, s * 0.11, col.darkened(0.1))
				draw_circle(p + Vector2(-s * 0.03, -s * 0.03), s * 0.035, Color(1, 1, 1, 0.5))
		"fruit":
			draw_circle(c + Vector2(0, s * 0.04), s * 0.27, col)
			draw_circle(c + Vector2(-s * 0.09, -s * 0.04), s * 0.08, Color(1, 1, 1, 0.35))
			_capsule(c + Vector2(0, -s * 0.2), c + Vector2(s * 0.05, -s * 0.33), s * 0.025, pal.bark)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.04, -s * 0.28), c + Vector2(s * 0.22, -s * 0.36), c + Vector2(s * 0.1, -s * 0.22)]), pal.oak_leaves)
		"mushroom":
			draw_rect(Rect2(c + Vector2(-s * 0.07, -s * 0.02), Vector2(s * 0.14, s * 0.3)), Color(0.93, 0.89, 0.8))
			var cap := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				cap.append(c + Vector2(cos(a) * s * 0.32, sin(a) * s * 0.26))
			draw_colored_polygon(cap, col)
			draw_circle(c + Vector2(-s * 0.1, -s * 0.12), s * 0.04, Color(1, 1, 1, 0.75))
			draw_circle(c + Vector2(s * 0.09, -s * 0.08), s * 0.03, Color(1, 1, 1, 0.75))
		"herb":
			for i in 5:
				var a := -PI * 0.5 + (i - 2) * 0.45
				var tip := c + Vector2(0, s * 0.3) + Vector2(cos(a), sin(a)) * s * 0.55
				_leaf(c + Vector2(0, s * 0.3), tip, s * 0.08, col.lightened(i * 0.04))
		"meat":
			_blob(c, s * 0.3, Color(0.8, 0.35, 0.38), 9, 11)
			draw_arc(c, s * 0.18, 0.5, 2.5, 10, Color(1, 0.85, 0.85, 0.7), 3.0)
			_capsule(c + Vector2(s * 0.15, s * 0.15), c + Vector2(s * 0.38, s * 0.38), s * 0.05, Color(0.95, 0.93, 0.86))
		"cactus":
			draw_circle(c, s * 0.26, pal.cactus.lightened(0.15))
			draw_circle(c, s * 0.18, Color(0.8, 0.9, 0.6))
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
		"essence":
			for i in 3:
				draw_circle(c, s * (0.3 - i * 0.08), Color(0.45, 0.25, 0.7, 0.35 + i * 0.25))
		"tool":
			_tool(info, c, s)
		_:
			draw_circle(c, s * 0.3, Color(1, 1, 1, 0.5))


func _tool(info: Dictionary, c: Vector2, s: float) -> void:
	var t: Dictionary = info.tool
	var head: Color = info.get("color", Color(0.6, 0.6, 0.65))
	if int(t.tier) == 1:
		head = Color(0.5, 0.5, 0.55)
	var wood := Color(0.55, 0.4, 0.26)
	var a := c + Vector2(-s * 0.3, s * 0.32)
	var b := c + Vector2(s * 0.22, -s * 0.24)
	match String(t.type):
		"rock":
			_blob(c, s * 0.3, Color(0.42, 0.44, 0.48), 6, 4)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.2, -0.15) * s, c + Vector2(0.05, -0.28) * s, c + Vector2(0.0, -0.02) * s]), Color(0.6, 0.62, 0.66))
		"hatchet":
			_capsule(a, b, s * 0.045, wood)
			draw_colored_polygon(PackedVector2Array([b + Vector2(-s * 0.06, -s * 0.06), b + Vector2(s * 0.18, -s * 0.2), b + Vector2(s * 0.22, s * 0.06), b + Vector2(s * 0.04, s * 0.06)]), head)
		"pickaxe":
			_capsule(a, b, s * 0.045, wood)
			var pts := PackedVector2Array()
			for k in 9:
				var u := (k / 8.0 - 0.5) * 1.6
				pts.append(b + Vector2(u * s * 0.32 + s * 0.06, -s * 0.03 + u * u * s * 0.12 - s * 0.06))
			draw_polyline(pts, head, s * 0.09, true)
		"spear":
			_capsule(c + Vector2(-s * 0.36, s * 0.36), c + Vector2(s * 0.24, -s * 0.24), s * 0.035, wood)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.18, -s * 0.3), c + Vector2(s * 0.4, -s * 0.4), c + Vector2(s * 0.3, -s * 0.18)]), head)
		"knife":
			_capsule(c + Vector2(-s * 0.3, s * 0.3), c + Vector2(-s * 0.1, s * 0.1), s * 0.06, wood)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.12, s * 0.06), c + Vector2(s * 0.34, -s * 0.34), c + Vector2(-s * 0.04, s * 0.14)]), head.lightened(0.15))
	if int(t.get("tier", 0)) >= 2:   # tier pip
		draw_circle(c + Vector2(s * 0.34, s * 0.34), s * 0.08, head)
		draw_arc(c + Vector2(s * 0.34, s * 0.34), s * 0.08, 0, TAU, 10, Color(0.1, 0.08, 0.06, 0.6), 1.2)


func _capsule(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0, true)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


func _leaf(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var mid := (a + b) * 0.5
	var n := (b - a).orthogonal().normalized() * w
	draw_colored_polygon(PackedVector2Array([a, mid + n, b, mid - n]), col)


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
