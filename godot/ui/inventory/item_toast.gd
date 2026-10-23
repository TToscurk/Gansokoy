extends CanvasLayer
## 取得／交付道具時的短暫提示，不阻斷操作。

@onready var _label: Label = $Panel/Label
var _serial := 0


func _ready() -> void:
	$Panel.visible = false
	InventoryManager.item_added.connect(_on_item_added)
	InventoryManager.item_removed.connect(_on_item_removed)


func _on_item_added(item_id: String, amount: int, _total: int) -> void:
	var item := InventoryManager.definition(item_id)
	if item != null:
		_show_message("獲得　%s%s" % [String(item.get("display_name")), " ×%d" % amount if amount > 1 else ""])


func _on_item_removed(item_id: String, amount: int, _total: int) -> void:
	var item := InventoryManager.definition(item_id)
	if item != null:
		_show_message("交付　%s%s" % [String(item.get("display_name")), " ×%d" % amount if amount > 1 else ""])


func _show_message(message: String) -> void:
	_serial += 1
	var current := _serial
	_label.text = message
	$Panel.visible = true
	$Panel.modulate.a = 1.0
	await get_tree().create_timer(2.2).timeout
	if current != _serial:
		return
	var tween := create_tween()
	tween.tween_property($Panel, "modulate:a", 0.0, 0.35)
	await tween.finished
	if current == _serial:
		$Panel.visible = false
