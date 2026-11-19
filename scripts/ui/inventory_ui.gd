class_name InventoryUI
extends RefCounted
## Inventory slots (drag & drop, split, quick-move, tooltips, durability), the HUD hotbar,
## the pickup feed and the satchel panel.


## One inventory slot. Interactive in the satchel, display-only on the HUD hotbar.
class SlotView extends PanelContainer:
	var inv: Inventory
	var index := 0
	var interactive := true
	var _icon: ItemIcon
	var _count: Label
	var _num: Label
	var _dur: Control
	var _dur_frac := -1.0
	var _seed := 0
	var _shown := ""   ## what this slot last showed (item, count, wear, selected)

	func _init(inventory: Inventory, slot_index: int, is_interactive := true) -> void:
		inv = inventory
		index = slot_index
		interactive = is_interactive
		_seed = 40 + slot_index
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var stack := Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stack)
		_icon = ItemIcon.new("", 46)
		_icon.position = Vector2(-2, -2)
		_icon.size = Vector2(46, 46)
		stack.add_child(_icon)
		if Inventory.is_hotbar(index):
			_num = UITheme.label(str(index + 1), 12, UITheme.INK_DIM)
			_num.position = Vector2(-4, -8)
			stack.add_child(_num)
		_count = UITheme.label("", 15, UITheme.INK)
		_count.add_theme_font_override("font", UITheme.BOLD_FONT)
		_count.position = Vector2(26, 25)
		stack.add_child(_count)
		_dur = Control.new()
		_dur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dur.position = Vector2(2, 42)
		_dur.size = Vector2(40, 5)
		_dur.draw.connect(func() -> void:
			if _dur_frac < 0.0:
				return
			_dur.draw_rect(Rect2(Vector2.ZERO, _dur.size), Color(0.1, 0.08, 0.06, 0.45))
			var c := Color(0.45, 0.7, 0.3).lerp(Color(0.85, 0.3, 0.2), 1.0 - _dur_frac)
			_dur.draw_rect(Rect2(Vector2.ZERO, Vector2(_dur.size.x * _dur_frac, _dur.size.y)), c))
		stack.add_child(_dur)
		refresh()

	func refresh() -> void:
		if not _icon:
			return
		var s: Dictionary = inv.slots[index]
		var id: String = s.get("id", "")
		# Nothing to do if this slot shows the same thing as last time (most slots, on most changes): restyling all
		# of them on every change was most of the cost of moving an item or changing the selection.
		var sel_now := Inventory.is_hotbar(index) and index == inv.selected
		var key := "%s|%s|%s|%s" % [id, str(s.get("count", 0)), str(s.get("dur", -1)), str(sel_now)]
		if key == _shown:
			return
		_shown = key
		_icon.item = id
		_count.text = str(s.count) if not s.is_empty() and int(s.count) > 1 else ""
		_dur_frac = -1.0
		if not s.is_empty() and int(s.get("dur", -1)) >= 0:
			_dur_frac = clampf(float(s.dur) / float(ItemDB.tool_stats(id).durability), 0.0, 1.0)
		_dur.queue_redraw()
		tooltip_text = ItemDB.display_name(id) if id != "" else ""
		var sel := sel_now
		add_theme_stylebox_override("panel", style(sel, _seed))
		pivot_offset = Vector2(32, 32)
		scale = Vector2(1.06, 1.06) if sel and not interactive else Vector2.ONE

	## A slot's painted background: plain, or warm when it's the selected hotbar slot.
	static func style(selected: bool, seed_value: int) -> StyleBoxTexture:
		var tint := UITheme.PAPER.lerp(UITheme.ACCENT_2, 0.45) if selected else Color(UITheme.PAPER, 0.9)
		return UITheme.paper_box(tint, seed_value, 9, 16, 96)

	# Painted tooltip with the item's details.
	func _make_custom_tooltip(_for_text: String) -> Object:
		var s: Dictionary = inv.slots[index]
		if s.is_empty():
			return null
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 77, 18, 22, 128))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)
		var info := ItemDB.info(s.id)
		var title := UITheme.label(info.name, 22, UITheme.INK, 0, true)
		if info.has("tier") and int(info.tier) >= 2:
			title.add_theme_color_override("font_color", ItemDB.tier_info(info.tier).color.darkened(0.35))
		v.add_child(title)
		var body := UITheme.label(ItemDB.describe(s.id, int(s.get("dur", -1))), 15, UITheme.INK_DIM)
		body.custom_minimum_size = Vector2(260, 0)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(body)
		return p

	func _get_drag_data(_at: Vector2) -> Variant:
		if not interactive or inv.slots[index].is_empty():
			return null
		var preview := ItemIcon.new(inv.slots[index].id, 52)
		preview.position = -Vector2(26, 26)
		var holder := Control.new()
		holder.add_child(preview)
		set_drag_preview(holder)
		return {"slot": index, "inv": inv}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not interactive or not data is Dictionary or not data.has("slot"):
			return false
		return data.has("chest") or data.get("inv") == inv

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.has("chest"):   # out of a chest, onto this slot
			ChestPanel.request({"structure": data.chest, "op": "move", "from": "chest", "a": data.slot, "to": "bag", "b": index})
		else:
			inv.move(int(data.slot), index)
		Audio.play(Audio.sfx.click, -10.0, 1.2)

	func _gui_input(event: InputEvent) -> void:
		if not interactive or not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Split half the stack into the first free slot.
			for i in Inventory.SIZE:
				if inv.slots[i].is_empty():
					inv.split(index, i)
					break
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
			if ChestPanel.open_id != "":   # a chest is open: shift-click sends it in
				ChestPanel.request({"structure": ChestPanel.open_id, "op": "quick", "from": "bag", "a": index})
			else:
				inv.quick_move(index)
			accept_event()


## The HUD hotbar (display only; select with 1-8 or the mouse wheel).
class Hotbar extends HBoxContainer:
	var inventory: Inventory
	var _slots: Array[SlotView] = []
	var _name: Label

	func setup(inv: Inventory, name_label: Label) -> void:
		inventory = inv
		_name = name_label
		for i in Inventory.HOTBAR_SIZE:
			var sv := SlotView.new(inv, i, false)
			add_child(sv)
			_slots.append(sv)
		inv.changed.connect(refresh)
		refresh()

	func _ready() -> void:
		add_theme_constant_override("separation", 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func refresh() -> void:
		for sv in _slots:
			sv.refresh()
		var held := inventory.selected_item()
		_name.text = ItemDB.display_name(held) if held != "" else "Bare hands"


## "+5 Wood" tags stacking on the right; repeated pickups merge into one line.
class PickupFeed extends VBoxContainer:
	var _rows := {}   # item -> {row, label, amount, life}

	func _ready() -> void:
		add_theme_constant_override("separation", 4)
		alignment = BoxContainer.ALIGNMENT_END
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_item(id: String, amount: int) -> void:
		if _rows.has(id):
			var e: Dictionary = _rows[id]
			e.amount += amount
			e.life = 3.0
			e.label.text = "+%d  %s" % [e.amount, ItemDB.display_name(id)]
			e.row.modulate.a = 1.0
			var tw: Tween = e.row.create_tween()
			tw.tween_property(e.row, "scale", Vector2(1.06, 1.06), 0.06)
			tw.tween_property(e.row, "scale", Vector2.ONE, 0.1)
			return
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", UITheme.stroke_box(Color(UITheme.PAPER, 0.9), 60 + _rows.size(), 18, 2))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		row.add_child(h)
		h.add_child(ItemIcon.new(id, 30))
		var lbl := UITheme.label("+%d  %s" % [amount, ItemDB.display_name(id)], 17, UITheme.INK)
		lbl.add_theme_font_override("font", UITheme.BOLD_FONT)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(lbl)
		add_child(row)
		_rows[id] = {"row": row, "label": lbl, "amount": amount, "life": 3.0}
		Audio.play(Audio.sfx.pickup, -14.0)

	func _process(delta: float) -> void:
		for id: String in _rows.keys():
			var e: Dictionary = _rows[id]
			e.life -= delta
			if e.life < 0.6:
				e.row.modulate.a = maxf(e.life / 0.6, 0.0)
			if e.life <= 0.0:
				e.row.queue_free()
				_rows.erase(id)


## Tab: the satchel. Backpack grid + hotbar row; drag outside the card to drop items.
class InventoryPanel extends Control:
	signal left_station   ## the station whose panel is open is out of reach now

	var inventory: Inventory
	var player: Node
	var _slots: Array[SlotView] = []
	var _craft: CraftingPanel
	var _chest: ChestPanel

	func setup(inv: Inventory, p: Node) -> void:
		inventory = inv
		player = p
		inv.changed.connect(func() -> void:
			if visible:
				for sv in _slots:
					sv.refresh())
		_build()
		_prewarm()

	## Open beside the satchel: a station's own crafting panel, or ("") what you can make by hand.
	func show_for(station_kind: String) -> void:
		close_chest()
		_craft.set_station(station_kind)
		show()

	## Open a chest beside the satchel (in place of the crafting panel).
	func show_chest(sid: String) -> void:
		_craft.hide()
		_chest.open(sid)
		show()

	func close_chest() -> void:
		if _chest and _chest.visible:
			_chest.close()
			_craft.show()

	## Make now, while the game starts, what the menus would otherwise make the first time they're used: every
	## slot's painted background (and each hotbar slot's selected one) and every recipe's row. Done then, it was a
	## hitch of 20-30 ms the first time you opened a tab, moved an item or picked a hotbar slot.
	func _prewarm() -> void:
		for i in Inventory.SIZE:
			SlotView.style(false, 40 + i)
			if Inventory.is_hotbar(i):
				SlotView.style(true, 40 + i)
		_craft.prewarm()

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _build() -> void:
		var dim := ColorRect.new()
		dim.color = Color(0.06, 0.04, 0.03, 0.35)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		center.add_child(row)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 8, 30))
		row.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		panel.add_child(col)
		var craft := CraftingPanel.new()
		craft.setup(inventory, player)
		row.add_child(craft)
		_craft = craft
		craft.left_station.connect(func() -> void: left_station.emit())
		_chest = ChestPanel.new()
		_chest.player = player
		_chest.hide()
		row.add_child(_chest)
		_chest.left.connect(func() -> void: left_station.emit())
		var title_row := HBoxContainer.new()
		title_row.add_child(UITheme.heading("Satchel", 36))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(spacer)
		title_row.add_child(UITheme.label("Tab to close", 15, UITheme.INK_DIM))
		col.add_child(title_row)
		var help := UITheme.label("Drag to move  ·  Right-click to split  ·  Shift-click to send to/from the hotbar\nDrag outside to drop", 14, UITheme.INK_DIM)
		col.add_child(help)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
			var sv := SlotView.new(inventory, i)
			grid.add_child(sv)
			_slots.append(sv)
		col.add_child(grid)
		col.add_child(UITheme.divider())
		col.add_child(UITheme.label("Hotbar", 17, UITheme.INK))
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 6)
		for i in Inventory.HOTBAR_SIZE:
			var sv := SlotView.new(inventory, i)
			bar.add_child(sv)
			_slots.append(sv)
		col.add_child(bar)
		visibility_changed.connect(func() -> void:
			if visible:
				for sv in _slots:
					sv.refresh())

	# Anything dropped on the background (outside the card) is dropped into the world.
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slot") and data.inv == inventory

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if player:
			player.drop_slot(int(data.slot), true)



## Crafting list beside the satchel: recipes by group, ingredients you have / need, and Craft buttons (Shift-click
## crafts five). From the satchel (Tab) it lists what you can make by hand; at a campfire, workbench or forge it's
## that station's own panel, with only its recipes, under a header in the station's colours.
class CraftingPanel extends PanelContainer:
	signal left_station   ## you walked out of reach of the station this panel is for

	## Each station's look: its colour (header, panel tint) and a line under its name.
	const STATION_LOOK := {
		"": {"title": "Crafting", "sub": "By hand", "tint": Color(0.95, 0.91, 0.82), "accent": Color(0.42, 0.3, 0.2)},
		"campfire": {"title": "Campfire", "sub": "Cook over the flames, and burn charcoal", "tint": Color(0.98, 0.88, 0.74), "accent": Color(0.78, 0.36, 0.12)},
		"workbench": {"title": "Workbench", "sub": "Saw, shape and fit", "tint": Color(0.94, 0.88, 0.76), "accent": Color(0.5, 0.34, 0.18)},
		"forge": {"title": "Forge", "sub": "Smelt ore and forge metal", "tint": Color(0.96, 0.84, 0.78), "accent": Color(0.66, 0.2, 0.12)},
	}

	var inventory: Inventory
	var player: Node
	var station := ""   ## "" by hand (the satchel), or the station this panel is for
	var _group := "Basics"
	var _list: VBoxContainer
	var _near_label: Label
	var _title: Label
	var _head_icon: ItemIcon
	var _glow: ColorRect
	var _glow_t := 0.0
	var _status: Label
	var _tabs := {}
	var _near: Array = []
	var _timer := 0.0
	var _rows := {}    ## recipe id -> {box, icon, needs, button, ok}: made once, then only updated
	var _sig := ""     ## what the list last showed (see _signature); unchanged means nothing to do

	func setup(inv: Inventory, p: Node) -> void:
		inventory = inv
		player = p
		add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 12, 30))
		custom_minimum_size = Vector2(400, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		add_child(col)
		# The header: the station's picture on a soft glow (it breathes, like the fire's light), its name and a line.
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		col.add_child(head)
		var badge := Control.new()
		badge.custom_minimum_size = Vector2(64, 64)
		head.add_child(badge)
		_glow = ColorRect.new()
		_glow.size = Vector2(64, 64)
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.material = _glow_material()
		badge.add_child(_glow)
		_head_icon = ItemIcon.new("", 60)
		_head_icon.position = Vector2(2, 2)
		_head_icon.size = Vector2(60, 60)
		badge.add_child(_head_icon)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -4)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(names)
		_title = UITheme.heading("Crafting", 36)
		names.add_child(_title)
		_near_label = UITheme.label("", 15, UITheme.INK_DIM)
		names.add_child(_near_label)
		# One row of tabs: tighter padding than the theme's buttons, so all the groups fit across the panel.
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 2)
		col.add_child(tabs)
		for g: String in Recipes.GROUPS:
			var b := Button.new()
			b.text = g
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 15)
			# The painted theme only applies once the button is in the scene, so its styles are tightened then.
			b.ready.connect(func() -> void:
				for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
					var sb := b.get_theme_stylebox(state)
					if sb:
						sb = sb.duplicate()
						sb.content_margin_left = 6.0
						sb.content_margin_right = 6.0
						b.add_theme_stylebox_override(state, sb), CONNECT_ONE_SHOT)
			b.pressed.connect(func() -> void:
				_group = g
				Audio.click()
				refresh())
			tabs.add_child(b)
			_tabs[g] = b
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(380, 380)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		_list = VBoxContainer.new()
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_theme_constant_override("separation", 6)
		scroll.add_child(_list)
		_status = UITheme.label("", 15, UITheme.ACCENT)
		col.add_child(_status)
		inv.changed.connect(func() -> void:
			if is_visible_in_tree():
				refresh())
		visibility_changed.connect(func() -> void:
			if is_visible_in_tree():
				_status.text = ""
				refresh())

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or not player:
			return
		if station != "":
			_glow_t += delta
			(_glow.material as ShaderMaterial).set_shader_parameter("pulse", 0.75 + 0.25 * sin(_glow_t * 2.2))
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.5
			var near := GameActions.stations_near(player.global_position)
			if station != "" and not near.has(station):
				left_station.emit()
				return
			if near != _near:
				refresh()

	## Show this station's recipes (or "" for what you can make by hand), under its own header.
	func set_station(kind: String) -> void:
		station = kind
		var look: Dictionary = STATION_LOOK.get(kind, STATION_LOOK[""])
		_title.text = look.title
		_title.add_theme_color_override("font_color", (look.accent as Color).darkened(0.1))
		_near_label.text = look.sub
		_head_icon.item = kind
		_glow.get_parent().visible = kind != ""
		(_glow.material as ShaderMaterial).set_shader_parameter("tint", look.accent)
		add_theme_stylebox_override("panel", UITheme.paper_box(look.tint, 12, 30))
		# Only the groups this station has anything in, and start on the first of them.
		var first := ""
		for g: String in _tabs:
			var any := Recipes.all().any(func(r: Dictionary) -> bool: return r.group == g and r.at == kind)
			_tabs[g].visible = any
			if any and first == "":
				first = g
		if not (_tabs.has(_group) and _tabs[_group].visible):
			_group = first
		_sig = ""
		_status.text = ""
		refresh()

	## A soft round glow behind the station's picture, its strength set each frame ("pulse").
	static func _glow_material() -> ShaderMaterial:
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float pulse = 1.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(tint.rgb, tint.a * pulse * 0.55 * (1.0 - smoothstep(0.1, 0.5, d)));
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		return m

	## Bring the list up to date. Rows are made once per recipe and kept; a refresh only rewrites their numbers,
	## colours and buttons and re-sorts them, and does nothing at all when nothing it shows has changed (a hotbar
	## selection, or a multiplayer sync that changed nothing here). Rebuilding every row on every change cost
	## 30-70 ms a time with the satchel open.
	func refresh() -> void:
		if not player:
			return
		for g: String in _tabs:   # (before the early out: clicking the open tab again mustn't un-press it)
			_tabs[g].set_pressed_no_signal(g == _group)
		_near = GameActions.stations_near(player.global_position)
		var sig := _signature()
		if sig == _sig:
			return
		_sig = sig
		var recipes: Array = Recipes.all().filter(func(r: Dictionary) -> bool: return r.group == _group and r.at == station)
		# Things you can make right now first, then things you're close to, then the rest.
		var scores := {}
		for r: Dictionary in recipes:
			scores[r.id] = _score(r)
		recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return scores[a.id] > scores[b.id] or (scores[a.id] == scores[b.id] and a.id < b.id))
		var shown := {}
		for i in recipes.size():
			var r: Dictionary = recipes[i]
			if not _rows.has(r.id):
				_rows[r.id] = _make_row(r)
				_list.add_child(_rows[r.id].box)
			_update_row(r, _rows[r.id])
			_rows[r.id].box.visible = true
			_list.move_child(_rows[r.id].box, i)
			shown[r.id] = true
		for id: String in _rows:
			if not shown.has(id):
				_rows[id].box.visible = false

	## Every recipe's row, made ahead (hidden), so no tab builds its rows the first time it's opened.
	func prewarm() -> void:
		for r: Dictionary in Recipes.all():
			if not _rows.has(r.id):
				_rows[r.id] = _make_row(r)
				_rows[r.id].box.visible = false
				_list.add_child(_rows[r.id].box)
		# Fill every tab in once too: the first fill sets up each row's look and buttons, the slow part.
		if player and player.is_inside_tree():
			for kind: String in STATION_LOOK:
				station = kind
				for g: String in Recipes.GROUPS:
					_group = g
					refresh()
			set_station("")

	## Everything the list shows: the tab, the stations in reach, and how many of each ingredient you have.
	func _signature() -> String:
		var parts: Array[String] = [station, _group, ",".join(_near)]
		for r: Dictionary in Recipes.all():
			if r.group != _group or r.at != station:
				continue
			for item: String in r.needs:
				parts.append("%s=%d" % [item, inventory.count(item)])
		return "|".join(parts)

	func _score(r: Dictionary) -> float:
		var at_ok: bool = r.at == "" or _near.has(r.at)
		var have := 0.0
		for item: String in r.needs:
			have += minf(float(inventory.count(item)) / float(r.needs[item]), 1.0)
		have /= r.needs.size()
		return (2.0 if at_ok and have >= 1.0 else 0.0) + have

	func _make_row(r: Dictionary) -> Dictionary:
		var box := PanelContainer.new()
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		box.add_child(h)
		var icon := ItemIcon.new(r.out, 44)
		h.add_child(icon)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		var title := UITheme.label(("%s x%d" % [ItemDB.display_name(r.out), r.count]) if int(r.count) > 1 else ItemDB.display_name(r.out), 17, UITheme.INK)
		title.add_theme_font_override("font", UITheme.BOLD_FONT)
		title.tooltip_text = ItemDB.describe(r.out)
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(title)
		var needs := RichTextLabel.new()
		needs.bbcode_enabled = true
		needs.fit_content = true
		needs.scroll_active = false
		needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		needs.add_theme_font_size_override("normal_font_size", 14)
		needs.add_theme_color_override("default_color", UITheme.INK)
		v.add_child(needs)
		var row := {"box": box, "icon": icon, "needs": needs, "button": null, "ok": null}
		row.button = _craft_button(r, true)
		h.add_child(row.button)
		return row

	func _craft_button(r: Dictionary, on: bool) -> Button:
		var b := UITheme.button("Craft", on, 84)
		b.custom_minimum_size = Vector2(84, 38)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: _craft(r))
		return b

	func _update_row(r: Dictionary, row: Dictionary) -> void:
		var can := GameActions.craftable_count(inventory, r) >= 1
		var at_ok: bool = r.at == "" or _near.has(r.at)
		var ok := can and at_ok
		if row.ok != ok:   # only when it flips
			(row.box as PanelContainer).add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PAPER_DARK, 0.55 if ok else 0.25), 8, Color(0, 0, 0, 0), 0, 6))
			(row.icon as Control).modulate.a = 1.0 if ok else 0.6
			(row.button as Button).theme_type_variation = "PrimaryButton" if ok else ""
			row.ok = ok
		(row.button as Button).disabled = not ok
		var parts: Array[String] = []
		for item: String in r.needs:
			var have := inventory.count(item)
			var need := int(r.needs[item])
			var c := "#3d6b2e" if have >= need else "#a3402a"
			parts.append("[color=%s]%s %d/%d[/color]" % [c, ItemDB.display_name(item), have, need])
		var text := "  ·  ".join(parts)
		if (row.needs as RichTextLabel).text != text:
			(row.needs as RichTextLabel).text = text

	func _craft(r: Dictionary) -> void:
		var times := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
		player.craft(r, times, func(res: Dictionary) -> void:
			if res.get("ok", false):
				Audio.play("chop" if r.at in ["workbench", ""] else "clink", -6.0, 1.2)
				_status.text = "Made %s%s" % [ItemDB.display_name(res.out), (" x%d" % res.made) if res.made > 1 else ""]
			else:
				_status.text = String(res.get("reason", "")))



## An open chest beside the satchel: its slots, dragged to and from the satchel's (or shift-clicked across). Every
## move asks the host (GameActions.chest_op), so two players at one chest can't both take the same thing.
class ChestPanel extends PanelContainer:
	signal left   ## the chest is gone, or you walked away from it

	static var open_id := ""   ## the chest open on this machine ("" for none): shift-clicks in the satchel go into it
	static var _player: Node   ## who's asking (for where they stand)

	var player: Node:
		set(p):
			player = p
			_player = p
	var _sid := ""
	var _grid: GridContainer
	var _title: Label
	var _icon: ItemIcon
	var _views: Array = []
	var _timer := 0.0

	static func request(args: Dictionary) -> void:
		if is_instance_valid(_player):
			args["pos"] = _player.global_position
		Net.request("chest", args, func(res: Dictionary) -> void:
			if not res.get("ok", false) and String(res.get("reason", "")) != "":
				Audio.play(Audio.sfx.click, -6.0, 0.7))

	func _ready() -> void:
		add_theme_stylebox_override("panel", UITheme.paper_box(Color(0.95, 0.88, 0.76), 14, 30))
		custom_minimum_size = Vector2(400, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		col.add_child(head)
		_icon = ItemIcon.new("chest", 56)
		_icon.custom_minimum_size = Vector2(56, 56)
		head.add_child(_icon)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -4)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(names)
		_title = UITheme.heading("Chest", 36)
		names.add_child(_title)
		names.add_child(UITheme.label("Drag to move  ·  Shift-click to send across", 14, UITheme.INK_DIM))
		_grid = GridContainer.new()
		_grid.columns = 8
		_grid.add_theme_constant_override("h_separation", 6)
		_grid.add_theme_constant_override("v_separation", 6)
		col.add_child(_grid)
		Game.structures_changed.connect(func() -> void:
			if visible:
				_refresh())

	func open(sid: String) -> void:
		_sid = sid
		open_id = sid
		var st: Dictionary = Game.structures.get(sid, {})
		var n := int(GameActions.DECOR.get(st.get("kind", ""), {}).get("slots", 0))
		_title.text = ItemDB.display_name(st.get("kind", "chest"))
		_icon.item = st.get("kind", "chest")
		while _views.size() < n:
			var v := ChestSlotView.new(_views.size())
			_grid.add_child(v)
			_views.append(v)
		for i in _views.size():
			_views[i].visible = i < n
		show()
		_refresh()

	func close() -> void:
		open_id = ""
		_sid = ""
		hide()

	func _refresh() -> void:
		if not Game.structures.has(_sid):
			left.emit()
			return
		var items: Array = Game.structures[_sid].get("items", [])
		for i in _views.size():
			if _views[i].visible:
				_views[i].show_slot(_sid, items[i] if i < items.size() else {})

	func _process(delta: float) -> void:
		if not visible or not player:
			return
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.4
			var st: Dictionary = Game.structures.get(_sid, {})
			if st.is_empty():
				left.emit()
				return
			var p: Array = st.pos
			if Vector3(p[0], p[1], p[2]).distance_to(player.global_position) > GameActions.CHEST_REACH - 0.5:
				left.emit()


## One slot of an open chest: the same painted look as the satchel's.
class ChestSlotView extends PanelContainer:
	var index := 0
	var _sid := ""
	var _slot := {}
	var _icon: ItemIcon
	var _count: Label
	var _dur: Control
	var _dur_frac := -1.0
	var _shown := "-"

	func _init(i: int) -> void:
		index = i
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("panel", SlotView.style(false, 140 + i))

	func _ready() -> void:
		var stack := Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stack)
		_icon = ItemIcon.new("", 46)
		_icon.position = Vector2(-2, -2)
		_icon.size = Vector2(46, 46)
		stack.add_child(_icon)
		_count = UITheme.label("", 15, UITheme.INK)
		_count.add_theme_font_override("font", UITheme.BOLD_FONT)
		_count.position = Vector2(26, 25)
		stack.add_child(_count)
		_dur = Control.new()
		_dur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dur.position = Vector2(2, 42)
		_dur.size = Vector2(40, 5)
		_dur.draw.connect(func() -> void:
			if _dur_frac < 0.0:
				return
			_dur.draw_rect(Rect2(Vector2.ZERO, _dur.size), Color(0.1, 0.08, 0.06, 0.45))
			_dur.draw_rect(Rect2(Vector2.ZERO, Vector2(_dur.size.x * _dur_frac, _dur.size.y)), Color(0.45, 0.7, 0.3).lerp(Color(0.85, 0.3, 0.2), 1.0 - _dur_frac)))
		stack.add_child(_dur)

	func show_slot(sid: String, s: Dictionary) -> void:
		_sid = sid
		_slot = s
		var key := str(s)
		if key == _shown or not _icon:
			return
		_shown = key
		var id: String = s.get("id", "")
		_icon.item = id
		_count.text = str(s.count) if not s.is_empty() and int(s.count) > 1 else ""
		_dur_frac = -1.0
		if not s.is_empty() and int(s.get("dur", -1)) >= 0:
			_dur_frac = clampf(float(s.dur) / float(ItemDB.tool_stats(id).durability), 0.0, 1.0)
		_dur.queue_redraw()
		tooltip_text = ItemDB.display_name(id) if id != "" else ""

	func _get_drag_data(_at: Vector2) -> Variant:
		if _slot.is_empty():
			return null
		var preview := ItemIcon.new(_slot.id, 52)
		preview.position = -Vector2(26, 26)
		var holder := Control.new()
		holder.add_child(preview)
		set_drag_preview(holder)
		return {"slot": index, "chest": _sid}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slot") and (data.get("chest", "") == _sid or data.has("inv"))

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var from := "chest" if data.has("chest") else "bag"
		ChestPanel.request({"structure": _sid, "op": "move", "from": from, "a": data.slot, "to": "chest", "b": index})
		Audio.play(Audio.sfx.click, -10.0, 1.2)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed and not _slot.is_empty():
			ChestPanel.request({"structure": _sid, "op": "quick", "from": "chest", "a": index})
			accept_event()
