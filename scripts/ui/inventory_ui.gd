class_name InventoryUI
extends RefCounted
## Hotbar, pickup feed and the inventory panel.


## Six slots along the bottom of the screen.
class Hotbar extends HBoxContainer:
	var inventory: Inventory
	var _slots: Array[PanelContainer] = []
	var _icons: Array[ItemIcon] = []
	var _counts: Array[Label] = []
	var _name: Label

	func setup(inv: Inventory, name_label: Label) -> void:
		inventory = inv
		_name = name_label
		inv.changed.connect(refresh)
		refresh()

	func _ready() -> void:
		add_theme_constant_override("separation", 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in Inventory.HOTBAR_SIZE:
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(62, 62)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var stack := Control.new()
			stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(stack)
			var icon := ItemIcon.new("", 44)
			icon.position = Vector2(-1, -1)
			icon.size = Vector2(44, 44)
			stack.add_child(icon)
			var num := UITheme.label(str(i + 1), 12, UITheme.INK_DIM)
			num.position = Vector2(-4, -8)
			stack.add_child(num)
			var count := UITheme.label("", 15, UITheme.INK)
			count.add_theme_font_override("font", UITheme.BOLD_FONT)
			count.position = Vector2(28, 24)
			stack.add_child(count)
			add_child(slot)
			_slots.append(slot)
			_icons.append(icon)
			_counts.append(count)

	func refresh() -> void:
		if not inventory or _slots.is_empty():
			return
		for i in _slots.size():
			var id: String = inventory.hotbar[i]
			_icons[i].item = id
			var n := inventory.count(id)
			_counts[i].text = str(n) if n > 1 else ""
			var sel := i == inventory.selected
			# Paper tiles; the selected one is washed with ochre and lifted slightly.
			var tint := UITheme.PAPER.lerp(UITheme.ACCENT_2, 0.45) if sel else Color(UITheme.PAPER, 0.88)
			_slots[i].add_theme_stylebox_override("panel", UITheme.paper_box(tint, 40 + i, 9, 16, 96))
			_slots[i].pivot_offset = Vector2(31, 31)
			_slots[i].scale = Vector2(1.08, 1.08) if sel else Vector2.ONE
		var held := inventory.selected_item()
		_name.text = ItemDB.display_name(held) if held != "" else "Bare hands"


## "+5 Wood" messages stacking on the right; repeated pickups merge into one line.
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
			tw.tween_property(e.row, "scale", Vector2(1.08, 1.08), 0.06)
			tw.tween_property(e.row, "scale", Vector2.ONE, 0.1)
			return
		# A small paper tag per item type.
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


## Tab / I: everything you're carrying.
class InventoryPanel extends Control:
	var inventory: Inventory
	var _grid: GridContainer
	var _food_hint: Label

	func setup(inv: Inventory) -> void:
		inventory = inv
		inv.changed.connect(func() -> void:
			if visible:
				refresh())

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.35)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(560, 380)
		center.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		panel.add_child(col)
		var title_row := HBoxContainer.new()
		title_row.add_child(UITheme.heading("Satchel", 34))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(spacer)
		title_row.add_child(UITheme.label("Tab to close", 15, UITheme.INK_DIM))
		col.add_child(title_row)
		_grid = GridContainer.new()
		_grid.columns = 5
		_grid.add_theme_constant_override("h_separation", 10)
		_grid.add_theme_constant_override("v_separation", 10)
		col.add_child(_grid)
		col.add_child(UITheme.divider())
		_food_hint = UITheme.label("Select food on the hotbar (1-6) and click to eat.", 15, UITheme.INK_DIM)
		col.add_child(_food_hint)
		visibility_changed.connect(func() -> void:
			if visible:
				refresh())

	func refresh() -> void:
		for c in _grid.get_children():
			c.queue_free()
		var ids := inventory.counts.keys()
		ids.sort_custom(func(a: String, b: String) -> bool:
			return ItemDB.info(a).kind + a < ItemDB.info(b).kind + b)
		if ids.is_empty():
			_grid.add_child(UITheme.label("Empty. Go hit some trees!", 17, UITheme.INK_DIM))
		for id: String in ids:
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(96, 100)
			cell.add_theme_stylebox_override("panel", UITheme.paper_box(UITheme.PAPER_DARK, 70 + _grid.get_child_count(), 8, 16, 96))
			var v := VBoxContainer.new()
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			v.add_theme_constant_override("separation", 2)
			var icon := ItemIcon.new(id, 46)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(icon)
			var name_lbl := UITheme.label(ItemDB.display_name(id), 15, UITheme.INK)
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(name_lbl)
			var count := UITheme.label("x%d" % inventory.count(id), 15, UITheme.ACCENT)
			count.add_theme_font_override("font", UITheme.BOLD_FONT)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(count)
			cell.add_child(v)
			_grid.add_child(cell)
