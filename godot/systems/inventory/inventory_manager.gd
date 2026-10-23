extends Node
## 任務道具背包（autoload）。
##
## 只存 item_id → 數量；名稱、說明與堆疊上限來自 data/items/*.tres。
## 世界／任務／對話只能透過公開 API 增減，避免各自維護一份狀態。

signal item_added(item_id: String, amount: int, new_total: int)
signal item_removed(item_id: String, amount: int, new_total: int)
signal inventory_changed

const ITEM_DIR := "res://data/items"

var _definitions: Dictionary = {}
var _amounts: Dictionary = {}


func _ready() -> void:
	_reload_definitions()


func _reload_definitions() -> void:
	_definitions.clear()
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_error("[InventoryManager] 找不到道具資料夾：%s" % ITEM_DIR)
		return
	for filename in dir.get_files():
		if not filename.ends_with(".tres"):
			continue
		var item: Resource = ResourceLoader.load(ITEM_DIR.path_join(filename))
		if item == null or not item.has_method("is_valid") or not item.call("is_valid"):
			push_warning("[InventoryManager] 忽略無效道具：%s" % filename)
			continue
		var item_id := String(item.get("item_id"))
		if _definitions.has(item_id):
			push_error("[InventoryManager] 重複 item_id：%s" % item_id)
			continue
		_definitions[item_id] = item


func definition(item_id: String) -> Resource:
	return _definitions.get(item_id) as Resource


func all_definitions() -> Array[Resource]:
	var out: Array[Resource] = []
	for item in _definitions.values():
		out.append(item as Resource)
	out.sort_custom(func(a: Resource, b: Resource) -> bool:
		if int(a.get("category")) != int(b.get("category")):
			return int(a.get("category")) < int(b.get("category"))
		return String(a.get("display_name")).naturalnocasecmp_to(String(b.get("display_name"))) < 0)
	return out


## 加入道具，回傳因堆疊上限而未能加入的數量。未知 id 不改狀態並全數退回。
func add_item(item_id: String, amount: int = 1) -> int:
	if amount <= 0:
		return maxi(amount, 0)
	var item: Resource = definition(item_id)
	if item == null:
		push_warning("[InventoryManager] 未知道具：%s" % item_id)
		return amount
	var old := count_item(item_id)
	var accepted := mini(amount, int(item.get("max_stack")) - old)
	if accepted <= 0:
		return amount
	_amounts[item_id] = old + accepted
	item_added.emit(item_id, accepted, old + accepted)
	inventory_changed.emit()
	return amount - accepted


## 移除道具。數量不足或未知 id 時不會部分扣除。
func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var old := count_item(item_id)
	if old < amount:
		return false
	var left := old - amount
	if left == 0:
		_amounts.erase(item_id)
	else:
		_amounts[item_id] = left
	item_removed.emit(item_id, amount, left)
	inventory_changed.emit()
	return true


func count_item(item_id: String) -> int:
	return int(_amounts.get(item_id, 0))


func has_item(item_id: String, amount: int = 1) -> bool:
	return amount > 0 and count_item(item_id) >= amount


func owned_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in all_definitions():
		var item_id := String(item.get("item_id"))
		var amount := count_item(item_id)
		if amount > 0:
			out.append({"item": item, "amount": amount})
	return out


func serialize() -> Dictionary:
	var out := {}
	for item_id in _amounts:
		var amount := count_item(String(item_id))
		if amount > 0 and definition(String(item_id)) != null:
			out[String(item_id)] = amount
	return out


## 還原時不發 signal，避免場景重建途中出現獲得道具提示。
func deserialize(data: Dictionary) -> void:
	_amounts.clear()
	for raw_id in data:
		var item_id := String(raw_id)
		var item: Resource = definition(item_id)
		if item == null:
			continue
		var amount := clampi(int(data[raw_id]), 0, int(item.get("max_stack")))
		if amount > 0:
			_amounts[item_id] = amount


func reset() -> void:
	_amounts.clear()
	inventory_changed.emit()
