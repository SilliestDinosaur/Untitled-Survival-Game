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
		_icon.item = id
		_count.text = str(s.count) if not s.is_empty() and int(s.count) > 1 else ""
		_dur_frac = -1.0
		if not s.is_empty() and int(s.get("dur", -1)) >= 0:
			_dur_frac = clampf(float(s.dur) / float(ItemDB.tool_stats(id).durability), 0.0, 1.0)
		_dur.queue_redraw()
		tooltip_text = ItemDB.display_name(id) if id != "" else ""
		var sel := Inventory.is_hotbar(index) and index == inv.selected
		var tint := UITheme.PAPER.lerp(UITheme.ACCENT_2, 0.45) if sel else Color(UITheme.PAPER, 0.9)
		add_theme_stylebox_override("panel", UITheme.paper_box(tint, _seed, 9, 16, 96))
		pivot_offset = Vector2(32, 32)
		scale = Vector2(1.06, 1.06) if sel and not interactive else Vector2.ONE

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
		return interactive and data is Dictionary and data.has("slot") and data.inv == inv

	func _drop_data(_at: Vector2, data: Variant) -> void:
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
	var inventory: Inventory
	var player: Node
	var _slots: Array[SlotView] = []

	func setup(inv: Inventory, p: Node) -> void:
		inventory = inv
		player = p
		inv.changed.connect(func() -> void:
			if visible:
				for sv in _slots:
					sv.refresh())
		_build()

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



## Crafting list beside the satchel: recipes by group, ingredients you have / need, the station
## each needs (and whether one is near), and Craft buttons (Shift-click crafts five).
class CraftingPanel extends PanelContainer:
	var inventory: Inventory
	var player: Node
	var _group := "Basics"
	var _list: VBoxContainer
	var _near_label: Label
	var _status: Label
	var _tabs := {}
	var _near: Array = []
	var _timer := 0.0

	func setup(inv: Inventory, p: Node) -> void:
		inventory = inv
		player = p
		add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 12, 30))
		custom_minimum_size = Vector2(430, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		add_child(col)
		col.add_child(UITheme.heading("Crafting", 36))
		_near_label = UITheme.label("", 15, UITheme.INK_DIM)
		col.add_child(_near_label)
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 4)
		col.add_child(tabs)
		for g: String in Recipes.GROUPS:
			var b := Button.new()
			b.text = g
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 15)
			b.pressed.connect(func() -> void:
				_group = g
				Audio.click()
				refresh())
			tabs.add_child(b)
			_tabs[g] = b
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(410, 400)
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
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.5
			var near := GameActions.stations_near(player.global_position)
			if near != _near:
				refresh()

	func refresh() -> void:
		if not player:
			return
		_near = GameActions.stations_near(player.global_position)
		var names: Array[String] = []
		for k: String in _near:
			names.append(Recipes.STATION_NAMES[k])
		_near_label.text = "Nearby: " + (", ".join(names) if not names.is_empty() else "no stations (place a campfire or workbench)")
		for g: String in _tabs:
			_tabs[g].button_pressed = g == _group
		for c in _list.get_children():
			c.queue_free()
		var recipes: Array = Recipes.all().filter(func(r: Dictionary) -> bool: return r.group == _group)
		# Things you can make right now first, then things you're close to, then the rest.
		recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _score(a) > _score(b))
		for r: Dictionary in recipes:
			_list.add_child(_row(r))

	func _score(r: Dictionary) -> float:
		var at_ok: bool = r.at == "" or _near.has(r.at)
		var have := 0.0
		for item: String in r.needs:
			have += minf(float(inventory.count(item)) / float(r.needs[item]), 1.0)
		have /= r.needs.size()
		return (2.0 if at_ok and have >= 1.0 else 0.0) + have

	func _row(r: Dictionary) -> Control:
		var can := GameActions.craftable_count(inventory, r) >= 1
		var at_ok: bool = r.at == "" or _near.has(r.at)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PAPER_DARK, 0.55 if can and at_ok else 0.25), 8, Color(0, 0, 0, 0), 0, 6))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		box.add_child(h)
		var icon := ItemIcon.new(r.out, 44)
		icon.modulate.a = 1.0 if can and at_ok else 0.6
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
		var parts: Array[String] = []
		for item: String in r.needs:
			var have := inventory.count(item)
			var need := int(r.needs[item])
			var c := "#3d6b2e" if have >= need else "#a3402a"
			parts.append("[color=%s]%s %d/%d[/color]" % [c, ItemDB.display_name(item), have, need])
		var text := "  ·  ".join(parts)
		if r.at != "":
			text += "\n[color=%s]At a %s%s[/color]" % ["#5a4a3a" if at_ok else "#a3402a", Recipes.STATION_NAMES[r.at], "" if at_ok else " (none nearby)"]
		needs.text = text
		v.add_child(needs)
		var b := UITheme.button("Craft", can and at_ok, 84)
		b.custom_minimum_size = Vector2(84, 38)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = not (can and at_ok)
		b.pressed.connect(func() -> void: _craft(r))
		h.add_child(b)
		return box

	func _craft(r: Dictionary) -> void:
		var times := 5 if Input.is_key_pressed(KEY_SHIFT) else 1
		var res := GameActions.craft(player.player_id, r.id, player.global_position, times)
		if res.ok:
			Audio.play("chop" if r.at in ["workbench", ""] else "clink", -6.0, 1.2)
			_status.text = "Made %s%s" % [ItemDB.display_name(res.out), (" x%d" % res.made) if res.made > 1 else ""]
		else:
			_status.text = res.reason
