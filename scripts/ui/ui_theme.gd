class_name UITheme
extends RefCounted
## The painterly UI: parchment cards with ragged painted edges, ink text, brush-stroke
## buttons and bars. Every texture is generated in code (no image files).

# Ink-on-parchment palette.
const PAPER := Color(0.95, 0.91, 0.82)
const PAPER_DARK := Color(0.86, 0.8, 0.68)
const INK := Color(0.19, 0.15, 0.12)
const INK_DIM := Color(0.19, 0.15, 0.12, 0.62)
const ACCENT := Color(0.77, 0.38, 0.22)      ## terracotta paint
const ACCENT_2 := Color(0.86, 0.62, 0.28)    ## ochre
# Light text for things drawn straight over the 3D world.
const TEXT := Color(0.98, 0.95, 0.88)
const TEXT_DIM := Color(0.98, 0.95, 0.88, 0.7)

const HEADING_FONT := preload("res://fonts/Alegreya.ttf")
const BODY_FONT := preload("res://fonts/AlegreyaSans-Medium.ttf")
const BOLD_FONT := preload("res://fonts/AlegreyaSans-Bold.ttf")

static var _cache := {}


# --- Generated textures --------------------------------------------------------------

## A sheet of parchment with a ragged, slightly darker painted border.
static func paper_texture(tint := PAPER, seed_value := 1, size := 160) -> ImageTexture:
	var key := "paper_%s_%d_%d" % [tint.to_html(), seed_value, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var edge := FastNoiseLite.new()
	edge.seed = seed_value
	edge.frequency = 0.09 if size >= 128 else 0.045   # broader wobble on small tiles
	edge.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = seed_value + 7
	grain.frequency = 0.35
	var wash := FastNoiseLite.new()
	wash.seed = seed_value + 3
	wash.frequency = 0.03
	var m := 8.0
	var radius := 14.0
	for y in size:
		for x in size:
			# Distance inside a rounded rect, roughened by noise -> torn/painted edge.
			var qx := absf(x + 0.5 - size * 0.5) - (size * 0.5 - m - radius)
			var qy := absf(y + 0.5 - size * 0.5) - (size * 0.5 - m - radius)
			var d := Vector2(maxf(qx, 0), maxf(qy, 0)).length() + minf(maxf(qx, qy), 0.0) - radius
			d += edge.get_noise_2d(x, y) * 5.0 * clampf(size / 160.0, 0.35, 1.0)   # gentler on small tiles
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(tint, 0))
				continue
			var c := tint
			c = c.darkened(clampf(1.0 + d / 7.0, 0.0, 1.0) * 0.16)       # pigment pools at the edge
			c = c.darkened(wash.get_noise_2d(x, y) * 0.05 + 0.02)
			c = c.lightened(grain.get_noise_2d(x, y) * 0.04)
			img.set_pixel(x, y, Color(c, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A single horizontal brush stroke with ragged edges and bristle streaks.
static func stroke_texture(color: Color, seed_value := 1, w := 256, h := 56) -> ImageTexture:
	var key := "stroke_%s_%d_%d_%d" % [color.to_html(), seed_value, w, h]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.05
	var bristle := FastNoiseLite.new()
	bristle.seed = seed_value + 11
	bristle.frequency = 0.25
	for x in w:
		var t := float(x) / w
		# Ragged top/bottom edges and tapered, uneven ends.
		var top := h * 0.16 + n.get_noise_1d(x) * h * 0.1
		var bottom := h * 0.84 + n.get_noise_1d(x + 400.0) * h * 0.1
		var end_fade := smoothstep(0.0, 0.06 + n.get_noise_1d(x * 0.5 + 99.0) * 0.03, t) * smoothstep(1.0, 0.92 + n.get_noise_1d(x * 0.5 + 33.0) * 0.04, t)
		for y in h:
			var inside := smoothstep(top - 1.0, top + 1.0, y) * (1.0 - smoothstep(bottom - 1.0, bottom + 1.0, y))
			var streak := 0.82 + bristle.get_noise_2d(x * 0.15, y * 2.2) * 0.25
			var a := inside * end_fade * clampf(streak, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.darkened(0.08 * (1.0 - streak)), a * color.a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func paper_box(tint := PAPER, seed_value := 1, pad := 26, margin := 30, tex_size := 160) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = paper_texture(tint, seed_value, tex_size)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(pad)
	return sb


static func stroke_box(color: Color, seed_value := 1, pad_x := 22, pad_y := 8) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = stroke_texture(color, seed_value)
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 8
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## Simple flat box (used for small chips where a texture would be overkill).
static func box(bg: Color, radius := 10, border := Color(0, 0, 0, 0), border_w := 0, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


## Polygon for a hand-painted bar: a rectangle whose top/bottom edges wobble.
static func stroke_polygon(rect: Rect2, seed_value: int, rough := 0.18, steps := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var top := []
	var bottom := []
	for i in steps + 1:
		top.append(rng.randf_range(-1, 1) * rect.size.y * rough)
		bottom.append(rng.randf_range(-1, 1) * rect.size.y * rough)
	for i in steps + 1:
		pts.append(Vector2(rect.position.x + rect.size.x * i / steps, rect.position.y + top[i]))
	pts.append(Vector2(rect.end.x + rect.size.y * 0.25, rect.position.y + rect.size.y * 0.5))
	for i in range(steps, -1, -1):
		pts.append(Vector2(rect.position.x + rect.size.x * i / steps, rect.end.y + bottom[i]))
	pts.append(Vector2(rect.position.x - rect.size.y * 0.25, rect.position.y + rect.size.y * 0.5))
	return pts


# --- Theme ---------------------------------------------------------------------------

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 19

	t.set_stylebox("panel", "PanelContainer", paper_box())
	t.set_stylebox("panel", "Panel", paper_box())

	# Buttons: ink text on bare paper; a paint stroke appears behind on hover.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 22
	empty.content_margin_right = 22
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	var hover := stroke_box(Color(ACCENT_2, 0.45), 3)
	var pressed := stroke_box(Color(ACCENT_2, 0.75), 4)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, stroke_box(Color(INK, 0.07), 2))
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("disabled", type, empty)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, INK_DIM)
		t.set_font("font", type, BOLD_FONT)
	t.set_stylebox("normal", "CheckButton", empty)

	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", stroke_box(ACCENT, 5))
	t.set_stylebox("hover", "PrimaryButton", stroke_box(ACCENT.lightened(0.12), 5))
	t.set_stylebox("pressed", "PrimaryButton", stroke_box(ACCENT.darkened(0.1), 6))
	t.set_stylebox("hover_pressed", "PrimaryButton", stroke_box(ACCENT.darkened(0.1), 6))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "PrimaryButton", PAPER)

	# Danger buttons (delete).
	t.add_type("DangerButton")
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("hover", "DangerButton", stroke_box(Color(0.75, 0.2, 0.15, 0.5), 7))
	t.set_color("font_color", "DangerButton", Color(0.55, 0.16, 0.12))
	t.set_color("font_hover_color", "DangerButton", Color(0.45, 0.1, 0.08))

	# Text input: ink underline on paper.
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(INK, 0.06)
	edit.border_color = Color(INK, 0.55)
	edit.border_width_bottom = 2
	edit.set_corner_radius_all(4)
	edit.set_content_margin_all(9)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT_2, 0.4))

	# Sliders: ink line with a paint fill.
	var track := box(Color(INK, 0.18), 3, Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := box(ACCENT, 3, Color(0, 0, 0, 0), 0, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Dropdowns
	t.set_stylebox("panel", "PopupMenu", paper_box(PAPER, 9, 10))
	t.set_stylebox("hover", "PopupMenu", stroke_box(Color(ACCENT_2, 0.5), 8, 8, 2))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_font("font", "PopupMenu", BODY_FONT)

	# Tabs
	for type in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", type, stroke_box(Color(ACCENT_2, 0.6), 12, 18, 6))
		t.set_stylebox("tab_unselected", type, stroke_box(Color(INK, 0.06), 13, 18, 6))
		t.set_stylebox("tab_hovered", type, stroke_box(Color(ACCENT_2, 0.35), 14, 18, 6))
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_unselected_color", type, INK_DIM)
		t.set_color("font_hovered_color", type, INK)
		t.set_font("font", type, BOLD_FONT)
		t.set_font_size("font_size", type, 19)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	# Scrolling lists
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", box(Color(INK, 0.08), 4, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(INK, 0.35), 4, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(ACCENT, 0.7), 4, Color(0, 0, 0, 0), 0, 2))

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckButton", INK)
	t.set_stylebox("background", "ProgressBar", stroke_box(Color(INK, 0.15), 21, 0, 0))
	t.set_stylebox("fill", "ProgressBar", stroke_box(ACCENT, 22, 0, 0))
	return t


# --- Builders -------------------------------------------------------------------------

## Anchor a control to a screen spot, then offset it (in pixels) from that anchor point.
static func place(c: Control, preset: Control.LayoutPreset, offset: Vector2, size := Vector2.ZERO) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


## Text. `shadow` > 0 adds a soft drop shadow (for text over the 3D world).
## `heading` uses the serif storybook face.
static func label(text: String, size := 18, color := INK, shadow := 0, heading := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heading:
		l.add_theme_font_override("font", HEADING_FONT)
	if shadow > 0:
		l.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.03, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", maxi(shadow / 2, 2))
	return l


static func heading(text: String, size := 34) -> Label:
	return label(text, size, INK, 0, true)


static func button(text: String, primary := false, min_width := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48)
	b.add_theme_font_size_override("font_size", 20)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.mouse_entered.connect(func() -> void: Audio.hover())
	b.pressed.connect(func() -> void: Audio.click())
	return b


## A thin hand-drawn divider line.
static func divider() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 10)
	c.draw.connect(func() -> void:
		var pts := PackedVector2Array()
		for i in 25:
			var t := i / 24.0
			pts.append(Vector2(c.size.x * t, 5.0 + sin(t * 17.0) * 0.8 + sin(t * 41.0) * 0.5))
		c.draw_polyline(pts, Color(INK, 0.35), 1.6, true))
	return c
