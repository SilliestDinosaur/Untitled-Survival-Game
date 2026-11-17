class_name Inventory
extends RefCounted
## A player's items: a count per item id, plus a 6-slot hotbar for tools and food.
## Pure data (no nodes), so it can be saved and later synced for co-op.

signal changed
signal item_added(id: String, amount: int)

const HOTBAR_SIZE := 6

var counts := {}                  # id -> int
var hotbar: Array[String] = []    # item ids ("" = empty)
var selected := 0


func _init() -> void:
	hotbar.resize(HOTBAR_SIZE)
	hotbar.fill("")


func count(id: String) -> int:
	return counts.get(id, 0)


func add(id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var cap: int = ItemDB.info(id).stack
	var added := mini(amount, cap - count(id))
	if added <= 0:
		return 0
	counts[id] = count(id) + added
	# Tools and food go on the hotbar automatically the first time you get them.
	if ItemDB.info(id).kind in ["tool", "food"] and not hotbar.has(id):
		var free := hotbar.find("")
		if free >= 0:
			hotbar[free] = id
	item_added.emit(id, added)
	changed.emit()
	return added


func remove(id: String, amount := 1) -> bool:
	if count(id) < amount:
		return false
	counts[id] = count(id) - amount
	if counts[id] <= 0:
		counts.erase(id)
		var slot := hotbar.find(id)
		if slot >= 0:
			hotbar[slot] = ""
	changed.emit()
	return true


func selected_item() -> String:
	var id := hotbar[selected]
	return id if count(id) > 0 else ""


func select(index: int) -> void:
	selected = wrapi(index, 0, HOTBAR_SIZE)
	changed.emit()


func clear() -> void:
	counts.clear()
	hotbar.fill("")
	selected = 0
	changed.emit()
