class_name UITheme
extends RefCounted
## One place for the look of every menu and HUD element.

const ACCENT := Color(0.98, 0.72, 0.36)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_DIM := Color(0.93, 0.94, 0.96, 0.55)
const PANEL := Color(0.055, 0.06, 0.08, 0.86)


static func box(bg: Color, radius := 10, border := Color(0, 0, 0, 0), border_w := 0, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	var panel := box(PANEL, 14, Color(1, 1, 1, 0.07), 1, 26)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# Buttons
	var b_normal := box(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0.08), 1, 10)
	b_normal.content_margin_left = 18
	b_normal.content_margin_right = 18
	var b_hover := b_normal.duplicate() as StyleBoxFlat
	b_hover.bg_color = Color(1, 1, 1, 0.13)
	b_hover.border_color = ACCENT
	var b_pressed := b_normal.duplicate() as StyleBoxFlat
	b_pressed.bg_color = Color(ACCENT, 0.35)
	b_pressed.border_color = ACCENT
	var b_focus := box(Color(0, 0, 0, 0), 8, Color(ACCENT, 0.6), 1, 10)
	var b_disabled := b_normal.duplicate() as StyleBoxFlat
	b_disabled.bg_color = Color(1, 1, 1, 0.02)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, b_normal)
		t.set_stylebox("hover", type, b_hover)
		t.set_stylebox("pressed", type, b_pressed)
		t.set_stylebox("hover_pressed", type, b_pressed)
		t.set_stylebox("focus", type, b_focus)
		t.set_stylebox("disabled", type, b_disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_DIM)
	var primary := b_normal.duplicate() as StyleBoxFlat
	primary.bg_color = Color(ACCENT, 0.85)
	primary.border_color = ACCENT
	var primary_hover := primary.duplicate() as StyleBoxFlat
	primary_hover.bg_color = ACCENT.lightened(0.15)
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", primary)
	t.set_stylebox("hover", "PrimaryButton", primary_hover)
	t.set_stylebox("pressed", "PrimaryButton", primary)
	t.set_color("font_color", "PrimaryButton", Color(0.1, 0.07, 0.04))
	t.set_color("font_hover_color", "PrimaryButton", Color(0.1, 0.07, 0.04))
	t.set_color("font_pressed_color", "PrimaryButton", Color(0.1, 0.07, 0.04))
	t.set_color("font_focus_color", "PrimaryButton", Color(0.1, 0.07, 0.04))

	# Text input
	var edit := box(Color(0, 0, 0, 0.35), 8, Color(1, 1, 1, 0.1), 1, 10)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))

	# Sliders
	var track := box(Color(1, 1, 1, 0.12), 4, Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := box(ACCENT, 4, Color(0, 0, 0, 0), 0, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Popups (dropdown lists)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.09, 0.11, 0.98), 8, Color(1, 1, 1, 0.08), 1, 6))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.25), 6, Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, Color(0, 0, 0, 0), 0, 0))
	return t


## Anchor a control to a screen spot, then offset it (in pixels) from that anchor point.
static func place(c: Control, preset: Control.LayoutPreset, offset: Vector2, size := Vector2.ZERO) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


static func label(text: String, size := 18, color := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		# Soft drop shadow reads better over the 3D world than a hard outline.
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", maxi(outline / 2, 2))
	return l


static func button(text: String, primary := false, min_width := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.mouse_entered.connect(func() -> void: Audio.hover())
	b.pressed.connect(func() -> void: Audio.click())
	return b
