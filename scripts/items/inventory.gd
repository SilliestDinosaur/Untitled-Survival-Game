class_name Inventory
extends RefCounted
## A player's items in slots: 8 hotbar slots (0-7) then 24 backpack slots (8-31).
## Each slot is {} (empty) or {"id", "count", "dur"} (dur = durability for tools, -1 otherwise).
## Pure data (no nodes) so it can be saved and later owned/synced by a multiplayer host.

signal changed
signal item_added(id: String, amount: int)
signal tool_broke(id: String)

const HOTBAR_SIZE := 8
const BACKPACK_SIZE := 24
const SIZE := HOTBAR_SIZE + BACKPACK_SIZE

var slots: Array[Dictionary] = []
var selected := 0
## Multiplayer guest: the host owns this inventory. Rearranging asks the host (which sends the
## result back); only the hotbar selection is local.
var remote := false


func _init() -> void:
	slots.resize(SIZE)
	clear(true)


func clear(silent := false) -> void:
	for i in SIZE:
		slots[i] = {}
	selected = 0
	if not silent:
		changed.emit()


static func is_hotbar(i: int) -> bool:
	return i < HOTBAR_SIZE


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s.get("id", "") == id:
			n += int(s.count)
	return n


func is_full_for(id: String) -> bool:
	return _space_for(id) <= 0


func _space_for(id: String) -> int:
	var cap := ItemDB.stack_size(id)
	var space := 0
	for s in slots:
		if s.is_empty():
			space += cap
		elif s.id == id and ItemDB.info(id).kind != "tool":
			space += cap - int(s.count)
	return space


## Add items. Tops up existing stacks first, then fills empty slots
## (tools and food prefer the hotbar). Returns how many fit.
func add(id: String, amount: int, silent := false, dur := -1) -> int:
	if amount <= 0 or not ItemDB.exists(id):
		return 0
	var info := ItemDB.info(id)
	var cap := ItemDB.stack_size(id)
	var left := amount
	if info.kind != "tool":
		for s in slots:
			if left <= 0:
				break
			if not s.is_empty() and s.id == id and s.count < cap:
				var put := mini(left, cap - int(s.count))
				s.count += put
				left -= put
	var order: Array = range(SIZE) if info.kind in ["tool", "food"] else range(HOTBAR_SIZE, SIZE) + range(HOTBAR_SIZE)
	for i: int in order:
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := 1 if info.kind == "tool" else mini(left, cap)
			var d := dur
			if info.kind == "tool" and d < 0:
				d = int(info.tool.durability)
			slots[i] = {"id": id, "count": put, "dur": d}
			left -= put
	var added := amount - left
	if added > 0:
		if not silent:
			item_added.emit(id, added)
		changed.emit()
	return added


## Remove `amount` of an item from anywhere (hotbar last). Returns true if there were enough.
func remove(id: String, amount := 1) -> bool:
	if count(id) < amount:
		return false
	var left := amount
	for i in range(SIZE - 1, -1, -1):
		var s := slots[i]
		if left <= 0:
			break
		if not s.is_empty() and s.id == id:
			var take := mini(left, int(s.count))
			s.count -= take
			left -= take
			if s.count <= 0:
				slots[i] = {}
	changed.emit()
	return true


func take_from_slot(i: int, amount := 1) -> Dictionary:
	var s := slots[i]
	if s.is_empty():
		return {}
	var take := mini(amount, int(s.count))
	var out := {"id": s.id, "count": take, "dur": s.get("dur", -1)}
	s.count -= take
	if s.count <= 0:
		slots[i] = {}
	changed.emit()
	return out


# --- Hotbar --------------------------------------------------------------------------

func selected_slot() -> Dictionary:
	return slots[selected]


func selected_item() -> String:
	return slots[selected].get("id", "")


func select(index: int) -> void:
	selected = wrapi(index, 0, HOTBAR_SIZE)
	changed.emit()


## Wear down the held tool. Returns true if it broke.
func damage_selected(amount := 1) -> bool:
	var s := slots[selected]
	if s.is_empty() or int(s.get("dur", -1)) < 0:
		return false
	s.dur = int(s.dur) - amount
	if s.dur <= 0:
		var id: String = s.id
		slots[selected] = {}
		tool_broke.emit(id)
		changed.emit()
		return true
	changed.emit()
	return false


# --- Moving things around (drag & drop) -------------------------------------------------

## Move a whole slot onto another: merge stacks of the same item, otherwise swap.
func move(from: int, to: int) -> void:
	if from == to or slots[from].is_empty():
		return
	if remote:
		Net.request("inv", {"op": "move", "a": from, "b": to})
		return
	var a := slots[from]
	var b := slots[to]
	if not b.is_empty() and b.id == a.id and ItemDB.info(a.id).kind != "tool":
		var cap := ItemDB.stack_size(a.id)
		var put := mini(int(a.count), cap - int(b.count))
		b.count += put
		a.count -= put
		if a.count <= 0:
			slots[from] = {}
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## Move half a stack into an empty slot (or onto the same item).
func split(from: int, to: int) -> void:
	var a := slots[from]
	if a.is_empty() or int(a.count) < 2 or from == to:
		return
	if remote:
		Net.request("inv", {"op": "split", "a": from, "b": to})
		return
	var half := int(a.count) / 2
	var b := slots[to]
	if b.is_empty():
		slots[to] = {"id": a.id, "count": half, "dur": a.get("dur", -1)}
		a.count -= half
	elif b.id == a.id:
		var put := mini(half, ItemDB.stack_size(a.id) - int(b.count))
		b.count += put
		a.count -= put
	changed.emit()


## Middle-click: take one off a stack into an empty slot (or onto the same item).
func split_one(from: int, to: int) -> void:
	var a := slots[from]
	if a.is_empty() or int(a.count) < 2 or from == to:
		return
	if remote:
		Net.request("inv", {"op": "one", "a": from, "b": to})
		return
	var b := slots[to]
	if b.is_empty():
		slots[to] = {"id": a.id, "count": 1, "dur": a.get("dur", -1)}
		a.count -= 1
	elif b.id == a.id and int(b.count) < ItemDB.stack_size(a.id):
		b.count += 1
		a.count -= 1
	changed.emit()


## Tidy the backpack (the hotbar is left as it is): like stacks merged, then ordered by kind (tools, then
## materials, food...), tier and name, empty slots at the end.
func sort_backpack() -> void:
	if remote:
		Net.request("inv", {"op": "sort", "a": HOTBAR_SIZE, "b": HOTBAR_SIZE})
		return
	var items: Array = []
	for i in range(HOTBAR_SIZE, SIZE):
		if not slots[i].is_empty():
			items.append(slots[i])
		slots[i] = {}
	# Merge stacks of the same thing (tools never stack).
	var merged: Array = []
	for s: Dictionary in items:
		var done := false
		if ItemDB.info(s.id).kind != "tool":
			for m: Dictionary in merged:
				if m.id == s.id and int(m.count) < ItemDB.stack_size(s.id):
					var put := mini(int(s.count), ItemDB.stack_size(s.id) - int(m.count))
					m.count = int(m.count) + put
					s.count = int(s.count) - put
					if int(s.count) <= 0:
						done = true
						break
		if not done:
			merged.append(s)
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _sort_key(a) < _sort_key(b))
	for i in merged.size():
		slots[HOTBAR_SIZE + i] = merged[i]
	changed.emit()


const _KIND_ORDER := {"tool": 0, "placeable": 1, "material": 2, "food": 3}


static func _sort_key(s: Dictionary) -> String:
	var info := ItemDB.info(s.id)
	return "%d_%02d_%s_%04d" % [int(_KIND_ORDER.get(String(info.get("kind", "")), 4)), 9 - int(info.get("tier", 0)), String(info.get("name", s.id)), 9999 - int(s.count)]


## Shift-click: send a stack between the hotbar and the backpack.
func quick_move(from: int) -> void:
	var s := slots[from]
	if s.is_empty():
		return
	if remote:
		Net.request("inv", {"op": "quick", "a": from})
		return
	var targets: Array = range(HOTBAR_SIZE, SIZE) if is_hotbar(from) else range(HOTBAR_SIZE)
	for i: int in targets:   # merge first
		if not slots[i].is_empty() and slots[i].id == s.id and ItemDB.info(s.id).kind != "tool":
			move(from, i)
			if slots[from].is_empty():
				return
	for i: int in targets:
		if slots[i].is_empty():
			move(from, i)
			return


# --- Saving -------------------------------------------------------------------------

func to_data() -> Dictionary:
	var out := []
	for s in slots:
		out.append(s.duplicate())
	return {"slots": out, "selected": selected}


func from_data(d: Dictionary, keep_selection := false) -> void:
	var sel := selected
	clear(true)
	# Building pieces used to be items; any still in a pack from an older save turn back into their materials.
	var returned := {}
	if d.has("slots"):
		var list: Array = d.slots
		for i in mini(list.size(), SIZE):
			var s: Dictionary = list[i]
			var id := String(s.get("id", ""))
			if s.is_empty() or not ItemDB.exists(id):
				continue
			if GameActions.PIECE_COSTS.has(id):
				var cost: Dictionary = GameActions.PIECE_COSTS[id]
				for item: String in cost:
					returned[item] = int(returned.get(item, 0)) + int(cost[item]) * int(s.count)
				continue
			slots[i] = {"id": id, "count": int(s.count), "dur": int(s.get("dur", -1))}
	for item: String in returned:
		add(item, int(returned[item]), true)
	selected = sel if keep_selection else clampi(int(d.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	changed.emit()
