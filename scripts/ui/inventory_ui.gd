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
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER, 8, 30))
		center.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		panel.add_child(col)
		var title_row := HBoxContainer.new()
		title_row.add_child(UITheme.heading("Satchel", 36))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(spacer)
		title_row.add_child(UITheme.label("Tab to close", 15, UITheme.INK_DIM))
		col.add_child(title_row)
		col.add_child(UITheme.label("Drag to move  ·  Right-click to split  ·  Shift-click to send to/from the hotbar  ·  Drag outside to drop", 14, UITheme.INK_DIM))
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
