extends CanvasLayer
## I 鍵開啟任務道具袋；只顯示 InventoryManager 的單一事實來源。

const CATEGORY_NAMES := ["任務", "重要", "素材", "消耗"]

var _selected := 0
@onready var _panel: Control = $Dim
@onready var _list: VBoxContainer = $Dim/Panel/Margin/Layout/Items
@onready var _description: Label = $Dim/Panel/Margin/Layout/Description
@onready var _empty: Label = $Dim/Panel/Margin/Layout/Empty


func _ready() -> void:
	visible = false
	add_to_group("modal_ui")
	InventoryManager.inventory_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("inventory_toggle") and not DialogueManager.is_active() \
				and not _other_modal_open():
			_set_open(true)
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("inventory_toggle") or event.is_action_pressed("ui_cancel"):
		_set_open(false)
	elif event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_move(-1)


func _other_modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
		if n != self and n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false


func _set_open(open: bool) -> void:
	visible = open
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.set("input_locked", open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_selected = 0
		_refresh()


func _move(delta: int) -> void:
	var entries := InventoryManager.owned_items()
	if entries.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, entries.size())
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	for child in _list.get_children():
		child.queue_free()
	var entries := InventoryManager.owned_items()
	_empty.visible = entries.is_empty()
	if entries.is_empty():
		_description.text = "任務中獲得的重要物品會收在這裡。"
		return
	_selected = clampi(_selected, 0, entries.size() - 1)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var item: Resource = entry.item
		var row := Label.new()
		var prefix := "◆" if i == _selected else "　"
		var amount := int(entry.amount)
		row.text = "%s %s%s" % [prefix, String(item.get("display_name")), "　×%d" % amount if amount > 1 else ""]
		row.add_theme_font_size_override("font_size", 21)
		row.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55) if i == _selected else Color(0.85, 0.84, 0.78))
		_list.add_child(row)
	var selected: Dictionary = entries[_selected]
	var selected_item: Resource = selected.item
	var category := int(selected_item.get("category"))
	var category_name: String = CATEGORY_NAMES[category] if category >= 0 and category < CATEGORY_NAMES.size() else "其他"
	_description.text = "【%s】\n%s" % [category_name, String(selected_item.get("description"))]
