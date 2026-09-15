extends CanvasLayer
## 存讀檔選單 —— Esc 開，↑↓ 選槽，Enter 執行，Tab 切換存／讀模式。
##
## 只認識 SaveManager 與 main 的 save_to_slot / load_from_slot。
## 不自己碰檔案、不自己算玩家朝向 —— 那些都在 main 那一份，避免兩套邏輯分叉。
##
## ⚠ 覆寫既有存檔要二次確認。這是唯一「一個按鍵就會毀掉玩家幾小時進度」的操作，
##   而 ↑↓ + Enter 很容易手滑（選單開起來時預設就停在某一格上）。
##   讀檔不需要確認 —— 讀錯了再讀一次就好，沒有東西被毀。

enum Mode { SAVE, LOAD }

## 槽位面板的底色：未選中／選中／選中且待確認覆寫
const COL_IDLE := Color(0.12, 0.13, 0.12, 0.85)
const COL_SEL := Color(0.26, 0.24, 0.16, 0.95)
const COL_WARN := Color(0.34, 0.18, 0.12, 0.95)
const COL_HEAD_EMPTY := Color(0.6, 0.6, 0.58)
const COL_HEAD_FILLED := Color(0.95, 0.85, 0.6)

var _main: Node = null
var _mode: Mode = Mode.SAVE
var _sel := 0
var _confirming := false
var _slots: Array[Panel] = []

@onready var _title: Label = $Panel/Title
@onready var _confirm: Label = $Panel/Confirm
@onready var _hint: Label = $Panel/Hint


func _ready() -> void:
	_main = get_parent()
	visible = false
	add_to_group("modal_ui")
	for i in SaveManager.SLOT_COUNT:
		var p: Panel = $Panel/Slots.get_node("Slot%d" % i)
		_slots.append(p)
	# 存檔後要重畫摘要（時間、任務標題都變了）
	SaveManager.game_saved.connect(func(_s: int) -> void:
		if visible:
			_refresh())


## 別的全螢幕面板（目前是地圖）開著嗎？
##
## ⚠ 不能靠掛載順序解決 Esc 的爭用。_unhandled_input 是**後加入的節點先收到**，
##   所以本選單掛在地圖之後時會先吃掉 Esc：自己開起來、set_input_as_handled，
##   地圖反而關不掉（實測：地圖開著按 Esc → 地圖仍開、選單也開）。
##   反過來把本選單掛在地圖前面雖然能work，但那是隱性依賴，
##   以後有人動 _setup_story_systems 的順序就又壞了。改成顯式互斥。
func _other_modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
		if n != self and n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		# Esc 開選單。對話中不開 —— 存到半段對話讀回來是死狀態（見 SaveManager）。
		# 地圖等別的面板開著時也不開，讓那個面板自己吃掉 Esc（見 _other_modal_open）。
		if event.is_action_pressed("ui_cancel") and not DialogueManager.is_active() \
				and not _other_modal_open():
			_set_open(true)
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		if _confirming:
			_confirming = false          # 先取消確認，不要一路關掉選單
			_refresh()
		else:
			_set_open(false)
	elif event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_focus_next"):     # Tab
		_mode = Mode.LOAD if _mode == Mode.SAVE else Mode.SAVE
		_confirming = false
		_refresh()
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif event.is_action_pressed("ui_text_delete"):     # Del
		if SaveManager.has_save(_sel):
			SaveManager.delete_save(_sel)
			_confirming = false
			_refresh()


func _move(d: int) -> void:
	_sel = wrapi(_sel + d, 0, SaveManager.SLOT_COUNT)
	_confirming = false          # 換格子就取消待確認狀態
	_refresh()


func _activate() -> void:
	if _mode == Mode.LOAD:
		if not SaveManager.has_save(_sel):
			return               # 空槽讀不了，安靜忽略
		_set_open(false)         # 先關選單再讀 —— 讀檔會重建世界
		_main.call("load_from_slot", _sel)
		return
	# 存檔：覆寫既有存檔要先確認
	if SaveManager.has_save(_sel) and not _confirming:
		_confirming = true
		_refresh()
		return
	_confirming = false
	_main.call("save_to_slot", _sel)
	_refresh()


func _set_open(open: bool) -> void:
	visible = open
	_confirming = false
	# 借 input_locked 鎖玩家，與地圖 UI 同一套做法
	if _main != null and _main.get("player") != null:
		_main.player.set("input_locked", open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		# 開選單時預設停在「最近存過的槽」上：存檔想覆寫舊的，讀檔想讀最新的，
		# 兩者都是這一格。全空就停在第一格。
		_sel = _latest_slot()
		_refresh()


## 最近存過的槽（用 saved_at 字串比大小 —— ISO8601 的字典序就是時間序）。
func _latest_slot() -> int:
	var best := 0
	var best_at := ""
	for i in SaveManager.SLOT_COUNT:
		var info: Dictionary = SaveManager.slot_info(i)
		if info.is_empty():
			continue
		var at := String(info.get("saved_at", ""))
		if at > best_at:
			best_at = at
			best = i
	return best


func _refresh() -> void:
	_title.text = "存檔" if _mode == Mode.SAVE else "讀取存檔"
	for i in SaveManager.SLOT_COUNT:
		var panel: Panel = _slots[i]
		var head: Label = panel.get_node("Head")
		var body: Label = panel.get_node("Body")
		var info: Dictionary = SaveManager.slot_info(i)
		var filled := not info.is_empty()
		head.text = "槽 %d" % (i + 1)
		head.add_theme_color_override("font_color",
			COL_HEAD_FILLED if filled else COL_HEAD_EMPTY)
		if filled:
			var where := WaypointResolver.map_info(String(info.get("map", "")))
			body.text = "%s　%s　%s" % [
				_pretty_time(String(info.get("saved_at", ""))),
				String(where.get("name", info.get("map", "？"))),
				String(info.get("quest", ""))]
		else:
			body.text = "（空）"
		# 選中的格子上色；待確認覆寫時轉紅
		var col := COL_IDLE
		if i == _sel:
			col = COL_WARN if _confirming else COL_SEL
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_width_left = 3 if i == _sel else 0
		sb.border_color = COL_HEAD_FILLED
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		panel.add_theme_stylebox_override("panel", sb)
	_confirm.visible = _confirming
	if _mode == Mode.SAVE:
		_hint.text = "↑↓ 選擇　Enter 存檔　Tab 改讀取　Del 刪除　Esc 關閉"
	else:
		_hint.text = "↑↓ 選擇　Enter 讀取　Tab 改存檔　Del 刪除　Esc 關閉"


## "2026-09-15T10:14:39" → "09/15 10:14"。存檔清單不需要秒與年。
func _pretty_time(iso: String) -> String:
	var parts := iso.split("T")
	if parts.size() != 2:
		return iso
	var d := parts[0].split("-")
	var t := parts[1].split(":")
	if d.size() < 3 or t.size() < 2:
		return iso
	return "%s/%s %s:%s" % [d[1], d[2], t[0], t[1]]
