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
	# Building pieces draw from their shape and material (the piece table), so all 24 match whatever their items say.
	if GameActions.is_building(item):
		_piece(GameActions.PIECES[item], c, s)
		return
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
		"hammer":   # a wooden mallet: a round head across the top of the haft, with iron hoops
			var hb := c + Vector2(s * 0.12, -s * 0.14)
			_capsule(c + Vector2(-s * 0.3, s * 0.32), hb, s * 0.045, Color(0.55, 0.4, 0.26))
			var across := Vector2(0.7, 0.7).normalized()   # square to the haft
			var head := PackedVector2Array()
			var w := s * 0.17
			var hh := s * 0.11
			var along := Vector2(across.y, -across.x)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				head.append(hb + across * corner.x * w + along * corner.y * hh)
			draw_colored_polygon(head, Color(0.6, 0.45, 0.3))
			for f in [-0.62, 0.62]:
				var m: Vector2 = hb + across * f * w
				draw_line(m + along * hh, m - along * hh, Color(0.36, 0.35, 0.38), s * 0.05)
			for f in [-1.0, 1.0]:
				var e: Vector2 = hb + across * f * w
				draw_line(e + along * hh, e - along * hh, Color(0.74, 0.6, 0.42), s * 0.035)
		"plan":
			_capsule(c + Vector2(-s * 0.3, s * 0.28), c + Vector2(s * 0.3, -s * 0.28), s * 0.12, Color(0.3, 0.46, 0.74))
			for p: Vector2 in [c + Vector2(-s * 0.3, s * 0.28), c + Vector2(s * 0.3, -s * 0.28)]:
				draw_circle(p, s * 0.12, Color(0.5, 0.65, 0.9))
			draw_line(c + Vector2(-s * 0.06, -s * 0.1), c + Vector2(s * 0.1, s * 0.06), Color(0.74, 0.64, 0.42), s * 0.06)
		"doorway":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.3), Vector2(s * 0.6, s * 0.6)), Color(0.7, 0.5, 0.38))
			draw_rect(Rect2(c + Vector2(-s * 0.13, -s * 0.12), Vector2(s * 0.26, s * 0.42)), Color(0.2, 0.14, 0.1))
		"wood_floor":
			for i in 4:
				draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.34 + i * s * 0.18), Vector2(s * 0.72, s * 0.14)), Color(0.62, 0.46, 0.3).lightened(i * 0.03))
			draw_rect(Rect2(c + Vector2(-s * 0.36, s * 0.32), Vector2(s * 0.72, s * 0.06)), Color(0.36, 0.25, 0.17))
		"window_wall":
			draw_rect(Rect2(c + Vector2(-s * 0.36, -s * 0.34), Vector2(s * 0.72, s * 0.68)), Color(0.7, 0.5, 0.38))
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.16), Vector2(s * 0.4, s * 0.32)), Color(0.72, 0.84, 0.88))
			draw_line(c + Vector2(0, -s * 0.16), c + Vector2(0, s * 0.16), Color(0.36, 0.26, 0.18), 1.5)
		"wood_doorway":
			for i in 5:
				draw_rect(Rect2(c + Vector2(-s * 0.34 + i * s * 0.135, -s * 0.34), Vector2(s * 0.11, s * 0.68)), Color(0.62, 0.46, 0.3).lightened(i * 0.02))
			draw_rect(Rect2(c + Vector2(-s * 0.13, -s * 0.12), Vector2(s * 0.26, s * 0.46)), Color(0.2, 0.14, 0.1))
		"piece":
			_piece(info, c, s)
		"brick":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.16), Vector2(s * 0.68, s * 0.32)), info.get("color", Color(0.7, 0.5, 0.38)))
			draw_line(c + Vector2(-s * 0.34, 0), c + Vector2(s * 0.34, 0), Color(0.35, 0.22, 0.15), 1.5)
			draw_line(c + Vector2(0, -s * 0.16), c + Vector2(0, 0), Color(0.35, 0.22, 0.15), 1.5)
		"rope":
			for i in 3:
				draw_arc(c + Vector2(0, (i - 1) * s * 0.06), s * (0.28 - i * 0.03), 0, TAU, 20, Color(0.74, 0.64, 0.42).darkened(i * 0.08), s * 0.07, true)
			_capsule(c + Vector2(s * 0.24, 0), c + Vector2(s * 0.4, s * 0.2), s * 0.035, Color(0.74, 0.64, 0.42))
		"plank":
			for i in 2:
				var o := Vector2(i * s * 0.06, -i * s * 0.16)
				draw_rect(Rect2(c + o + Vector2(-s * 0.36, 0), Vector2(s * 0.66, s * 0.15)), Color(0.62, 0.46, 0.3).lightened(i * 0.06))
				draw_line(c + o + Vector2(-s * 0.3, s * 0.07), c + o + Vector2(s * 0.2, s * 0.06), Color(0.45, 0.32, 0.2), 1.0)
		"leather":
			_blob(c, s * 0.32, Color(0.5, 0.32, 0.2), 8, 23)
			draw_arc(c, s * 0.22, 0, TAU, 16, Color(0.66, 0.46, 0.3), 1.5)
		"cooked_meat":
			_blob(c, s * 0.3, Color(0.5, 0.27, 0.15), 9, 11)
			for i in 3:
				draw_line(c + Vector2(-s * 0.18 + i * s * 0.12, -s * 0.15), c + Vector2(-s * 0.08 + i * s * 0.12, s * 0.15), Color(0.2, 0.1, 0.05), 2.0)
			_capsule(c + Vector2(s * 0.15, s * 0.15), c + Vector2(s * 0.38, s * 0.38), s * 0.05, Color(0.9, 0.85, 0.75))
		"roast_fruit":
			var fc: Color = ItemDB.info("fruit").get("color", Color(0.8, 0.3, 0.3))
			_capsule(c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.4, 0), s * 0.02, Color(0.45, 0.32, 0.2))
			for i in 2:
				draw_circle(c + Vector2((i - 0.5) * s * 0.34, 0), s * 0.17, fc.darkened(0.25))
				draw_arc(c + Vector2((i - 0.5) * s * 0.34, 0), s * 0.1, 3.5, 5.0, 6, Color(0.3, 0.15, 0.08), 2.0)
		"stew":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.05), c + Vector2(s * 0.36, -s * 0.05), c + Vector2(s * 0.22, s * 0.28), c + Vector2(-s * 0.22, s * 0.28)]), Color(0.56, 0.4, 0.26))
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.12), Vector2(s * 0.68, s * 0.08)), Color(0.55, 0.3, 0.16))
			for i in 4:
				draw_circle(c + Vector2((i - 1.5) * s * 0.14, -s * 0.11), s * 0.045, [Color(0.65, 0.38, 0.3), pal.berry][i % 2])
			for i in 2:
				draw_arc(c + Vector2((i - 0.5) * s * 0.2, -s * 0.28), s * 0.06, PI, TAU, 6, Color(1, 1, 1, 0.5), 1.5)
		"bandage":
			# A rolled wrap with its loose end, outlined so it reads on the paper slots, and a red cross.
			var edge := Color(0.55, 0.48, 0.38)
			_capsule(c + Vector2(-s * 0.2, 0), c + Vector2(s * 0.12, 0), s * 0.2, edge)
			_capsule(c + Vector2(-s * 0.2, 0), c + Vector2(s * 0.12, 0), s * 0.17, Color(0.96, 0.93, 0.84))
			draw_line(c + Vector2(-s * 0.05, -s * 0.17), c + Vector2(-s * 0.05, s * 0.17), edge, 1.5)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.035), Vector2(s * 0.14, s * 0.07)), Color(0.8, 0.18, 0.15))
			draw_rect(Rect2(c + Vector2(-s * 0.165, -s * 0.07), Vector2(s * 0.07, s * 0.14)), Color(0.8, 0.18, 0.15))
		"torch":
			_capsule(c + Vector2(-s * 0.28, s * 0.36), c + Vector2(s * 0.08, -s * 0.08), s * 0.05, Color(0.55, 0.4, 0.26))
			_capsule(c + Vector2(s * 0.04, -s * 0.04), c + Vector2(s * 0.14, -s * 0.14), s * 0.08, Color(0.4, 0.28, 0.18))
			draw_circle(c + Vector2(s * 0.2, -s * 0.24), s * 0.13, Color(1.0, 0.55, 0.15))
			draw_circle(c + Vector2(s * 0.2, -s * 0.22), s * 0.07, Color(1.0, 0.9, 0.5))
		"ingot":
			for i in 2:
				var o := c + Vector2(i * s * 0.05, -i * s * 0.18 + s * 0.1)
				draw_colored_polygon(PackedVector2Array([o + Vector2(-s * 0.32, s * 0.1), o + Vector2(s * 0.28, s * 0.1), o + Vector2(s * 0.2, -s * 0.06), o + Vector2(-s * 0.24, -s * 0.06)]), col.darkened(0.1 * (1 - i)))
				draw_line(o + Vector2(-s * 0.24, -s * 0.06), o + Vector2(s * 0.2, -s * 0.06), col.lightened(0.4), 1.5)
		"cut_gem":
			var top := PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.06), c + Vector2(-s * 0.14, -s * 0.24), c + Vector2(s * 0.14, -s * 0.24), c + Vector2(s * 0.3, -s * 0.06)])
			draw_colored_polygon(top, col.lightened(0.3))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.06), c + Vector2(s * 0.3, -s * 0.06), c + Vector2(0, s * 0.32)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.06), c + Vector2(s * 0.3, -s * 0.06), c + Vector2(0, s * 0.32)]), col.darkened(0.2))
		"campfire":
			for i in 7:
				var a := PI * 0.1 + PI * 0.8 * i / 6.0
				draw_circle(c + Vector2(cos(a) * s * 0.32, s * 0.2 + sin(a) * s * 0.08), s * 0.07, pal.rock.lightened(0.05 * (i % 2)))
			for i in 3:
				_capsule(c + Vector2((i - 1) * s * 0.22, s * 0.22), c + Vector2(0, -s * 0.1), s * 0.04, pal.bark)
			draw_circle(c + Vector2(0, -s * 0.1), s * 0.12, Color(1.0, 0.55, 0.15))
			draw_circle(c + Vector2(0, -s * 0.06), s * 0.06, Color(1.0, 0.9, 0.5))
		"workbench":
			draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.12), Vector2(s * 0.8, s * 0.1)), Color(0.62, 0.46, 0.3))
			for x in [-0.32, 0.26]:
				draw_rect(Rect2(c + Vector2(x * s, -s * 0.02), Vector2(s * 0.07, s * 0.36)), Color(0.42, 0.3, 0.19))
			draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.16), Vector2(s * 0.6, s * 0.05)), Color(0.42, 0.3, 0.19))
			_capsule(c + Vector2(s * 0.05, -s * 0.2), c + Vector2(s * 0.3, -s * 0.18), s * 0.025, Color(0.55, 0.4, 0.26))
		"forge":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, s * 0.38), c + Vector2(s * 0.36, s * 0.38), c + Vector2(s * 0.3, -s * 0.02), c + Vector2(-s * 0.3, -s * 0.02)]), pal.rock.darkened(0.1))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.16, -s * 0.02), c + Vector2(s * 0.16, -s * 0.02), c + Vector2(s * 0.08, -s * 0.42), c + Vector2(-s * 0.08, -s * 0.42)]), pal.rock.darkened(0.2))
			draw_circle(c + Vector2(0, s * 0.18), s * 0.12, Color(0.08, 0.06, 0.05))
			draw_circle(c + Vector2(0, s * 0.24), s * 0.08, Color(1.0, 0.5, 0.12))
		_:
			draw_circle(c, s * 0.3, Color(1, 1, 1, 0.5))


## A building piece: its shape, in its material's colour.
func _piece(info: Dictionary, c: Vector2, s: float) -> void:
	var colours := {"brick": Color(0.72, 0.5, 0.38), "wood": Color(0.6, 0.45, 0.3), "stone": Color(0.56, 0.57, 0.61)}
	var base: Color = colours.get(String(info.get("mat", "")), Color(0.6, 0.6, 0.6))
	var line := base.darkened(0.35)
	match String(info.get("shape", "")):
		"floor":   # a slab seen from above at an angle: a tiled top and a darker front edge
			var tl := c + Vector2(-s * 0.24, -s * 0.2)
			var tr := c + Vector2(s * 0.4, -s * 0.2)
			var br := c + Vector2(s * 0.24, s * 0.14)
			var bl := c + Vector2(-s * 0.4, s * 0.14)
			draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]), base.lightened(0.08))
			draw_colored_polygon(PackedVector2Array([bl, br, br + Vector2(0, s * 0.14), bl + Vector2(0, s * 0.14)]), base.darkened(0.2))
			for i in range(1, 3):   # the tiles' joints, both ways
				var f := i / 3.0
				draw_line(tl.lerp(bl, f), tr.lerp(br, f), line, 1.2)
				draw_line(tl.lerp(tr, f), bl.lerp(br, f), line, 1.2)
		"wall":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.36), Vector2(s * 0.68, s * 0.72)), base)
			for i in 3:
				draw_line(c + Vector2(-s * 0.34, -s * 0.36 + (i + 1) * s * 0.18), c + Vector2(s * 0.34, -s * 0.36 + (i + 1) * s * 0.18), line, 1.2)
		"half":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.08), Vector2(s * 0.68, s * 0.42)), base)
			draw_line(c + Vector2(-s * 0.34, s * 0.1), c + Vector2(s * 0.34, s * 0.1), line, 1.2)
		"window":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.36), Vector2(s * 0.68, s * 0.72)), base)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.16), Vector2(s * 0.4, s * 0.32)), Color(0.72, 0.84, 0.88))
		"doorway":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.36), Vector2(s * 0.68, s * 0.72)), base)
			draw_rect(Rect2(c + Vector2(-s * 0.14, -s * 0.12), Vector2(s * 0.28, s * 0.48)), Color(0.2, 0.14, 0.1))
		"door":
			draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.36), Vector2(s * 0.68, s * 0.72)), base)
			draw_rect(Rect2(c + Vector2(-s * 0.14, -s * 0.12), Vector2(s * 0.28, s * 0.48)), Color(0.5, 0.36, 0.24))
			draw_circle(c + Vector2(s * 0.08, s * 0.14), s * 0.03, Color(0.3, 0.3, 0.32))
		"stairs":   # a flight of four steps from the side, climbing to the right
			var steps := 4
			var w := s * 0.72 / steps
			var hh := s * 0.68 / steps
			var x0 := c.x - s * 0.36
			var y0 := c.y + s * 0.34
			var pts := PackedVector2Array([Vector2(x0, y0)])
			for i in steps:
				pts.append(Vector2(x0 + i * w, y0 - (i + 1) * hh))
				pts.append(Vector2(x0 + (i + 1) * w, y0 - (i + 1) * hh))
			pts.append(Vector2(x0 + steps * w, y0))
			draw_colored_polygon(pts, base)
			for i in steps:   # each tread's lighter nosing
				draw_line(Vector2(x0 + i * w, y0 - (i + 1) * hh), Vector2(x0 + (i + 1) * w, y0 - (i + 1) * hh), base.lightened(0.25), 2.0)
			draw_polyline(pts + PackedVector2Array([pts[0]]), line, 1.2)
		"roof":
			for i in 3:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.12 + i * s * 0.2), c + Vector2(s * 0.36, -s * 0.12 + i * s * 0.2), c + Vector2(s * 0.28, s * 0.06 + i * s * 0.2), c + Vector2(-s * 0.28, s * 0.06 + i * s * 0.2)]), base.lightened(i * 0.06))
		_:
			draw_circle(c, s * 0.3, base)


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
		"pickaxe":   # one long point lashed across the top of the haft
			_capsule(a, b, s * 0.045, wood)
			var dir := (b - a).normalized()
			var across := Vector2(dir.y, -dir.x)   # square to the haft, toward the upper left
			var back := b - across * s * 0.08
			var tip := b + across * s * 0.36
			draw_colored_polygon(PackedVector2Array([back + dir * s * 0.07, tip, back - dir * s * 0.07]), head)
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
