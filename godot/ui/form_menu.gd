extends CanvasLayer
class_name FormMenu
## 日之呼吸・型選單（FF7R Tactical Mode 式）。
##
## 按住／切換 form_menu 鍵 → 時間降到 slow_scale → 十二型直排 → 選定 → 發動。
## 即時戰鬥完全保留：這一層是疊在上面的「有餘裕思考」窗口，不是回合制。
##
## 設計規則：
##   1. **十二型永遠全部列出來。** 未修得的灰掉標「未修得」——玩家看得到
##      日之呼吸的完整全貌，那本身就是敘事。缺動畫的型同樣列出，標「未傳」。
##   2. 不可用的原因要寫清楚（呼吸不足 / 冷卻 / 未修得 / 未傳），
##      不是單純變灰讓玩家猜。
##   3. 全部程式繪製，不依賴任何貼圖資產（同 combat_hud.gd 的做法，避免美術債）。
##
## ⚠ 時間放慢用 Engine.time_scale：它會連 Tween、AudioStreamPlayer 的
##   播放速率一起拖慢。本選單的動畫因此一律用 _process(delta) 手算並除以
##   time_scale 還原成真實時間，不用 Tween —— 否則選單自己會跟著變慢。

## 型列表的繪製節點。
##
## ⚠ draw_rect() / draw_string() 是 CanvasItem 的方法，必須由「要被畫上去的
##   那個節點自己」呼叫。FormMenu 是 CanvasLayer（不是 CanvasItem），把
##   _draw_list 接到 Control.draw 訊號上會編不過（Function "draw_rect()"
##   not found in base self）。所以列表自己是一個 Control 子類別，
##   繪製邏輯寫在它的 _draw() 裡，資料反向從 menu 讀。
class FormList extends Control:
	var menu: Node = null

	func _draw() -> void:
		if menu != null:
			menu.draw_rows(self)


const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")

## 型的顯示順序：壹到拾貳。
const FORM_ORDER: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

signal form_chosen(id: int)
signal menu_opened
signal menu_closed

## 開啟時的時間倍率。0.15 = 慢到看得清，但世界沒有停住。
@export_range(0.02, 1.0, 0.01) var slow_scale := 0.15
## 開／關的過場秒數（真實時間）。
@export var fade_time := 0.12
@export var panel_width := 460.0
@export var row_height := 38.0
@export var margin := 44.0

var open := false
var selected := 0

var _player: Node = null
var _root: Control = null
var _list: Control = null
var _title: Label = null
var _hint: Label = null
var _fade := 0.0
## 開啟前的 time_scale，關閉時原樣還原（不要假設一定是 1.0 ——
## 過場或其他系統可能也在動它）。
var _prev_time_scale := 1.0


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func bind_player(p: Node) -> void:
	_player = p


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := Control.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = margin
	panel.offset_top = -(FORM_ORDER.size() * row_height) * 0.5 - 40.0
	panel.offset_right = margin + panel_width
	panel.offset_bottom = (FORM_ORDER.size() * row_height) * 0.5 + 40.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "日之呼吸"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title.add_theme_constant_override("outline_size", 6)
	_title.position = Vector2(0, 0)
	panel.add_child(_title)

	var list := FormList.new()
	list.name = "List"
	list.menu = self
	list.position = Vector2(0, 34)
	list.size = Vector2(panel_width, FORM_ORDER.size() * row_height)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(list)
	_list = list

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "W/S   Enter"
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.73, 0.68))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.position = Vector2(0, 42 + FORM_ORDER.size() * row_height)
	panel.add_child(_hint)


# ---------------------------------------------------------------------------
# 開關
# ---------------------------------------------------------------------------

func toggle() -> void:
	if open:
		close()
	else:
		open_menu()


func open_menu() -> void:
	if open or _player == null:
		return
	# 死亡、硬直、收放刀中不給開 —— 選單不是逃生口。
	var p: Variant = _player.get("posture")
	if p != null and p.is_dead():
		return
	open = true
	visible = true
	selected = _first_usable_index()
	_prev_time_scale = Engine.time_scale
	Engine.time_scale = slow_scale
	menu_opened.emit()


func close() -> void:
	if not open:
		return
	open = false
	Engine.time_scale = _prev_time_scale
	visible = false
	menu_closed.emit()


## 開選單時游標停在第一個真的能用的型；全部不能用就停在第一列。
func _first_usable_index() -> int:
	if _player == null:
		return 0
	for i in FORM_ORDER.size():
		if _block_reason(FORM_ORDER[i]) == "":
			return i
	return 0


func _block_reason(id: int) -> String:
	if _player == null or not _player.has_method("form_block_reason"):
		return "unknown"
	return String(_player.form_block_reason(id))


# ---------------------------------------------------------------------------
# 輸入
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("form_menu"):  # C 或 Esc 關閉
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_forward") or event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_back") or event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("attack_light"):
		_confirm()
		get_viewport().set_input_as_handled()


## 游標在十二型之間循環。不可用的型照樣停得上去 ——
## 玩家要能停在「壹ノ型 圓舞」上讀它為什麼用不了。
func _move_cursor(step: int) -> void:
	selected = wrapi(selected + step, 0, FORM_ORDER.size())
	if _list:
		_list.queue_redraw()


func _confirm() -> void:
	var id: int = FORM_ORDER[selected]
	if _block_reason(id) != "":
		return   # 不可用：不關選單，讓玩家改選
	close()
	if _player != null and _player.has_method("execute_form"):
		if _player.execute_form(id):
			form_chosen.emit(id)


func _process(delta: float) -> void:
	if not open:
		return
	# ⚠ Engine.time_scale 已經把 delta 壓縮了，這裡還原成真實秒數，
	#   否則選單自己的脈動會跟著世界一起變慢。
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_fade = minf(_fade + real_delta / maxf(fade_time, 0.001), 1.0)
	if _list:
		_list.queue_redraw()


# ---------------------------------------------------------------------------
# 繪製
# ---------------------------------------------------------------------------

## 由 FormList._draw() 呼叫；ci 就是那個 Control，所有 draw_* 都畫在它身上。
func draw_rows(ci: CanvasItem) -> void:
	if _player == null:
		return
	var font := ThemeDB.fallback_font
	var gauge: float = float(_player.get("sun_breath_gauge"))

	for i in FORM_ORDER.size():
		var id: int = FORM_ORDER[i]
		var def: Dictionary = SunBreathing.FORMS[id]
		var y: float = i * row_height
		var reason := _block_reason(id)
		var usable := reason == ""
		var is_sel := i == selected

		# --- 列底 ---
		var bg := Color(0, 0, 0, 0.55)
		if is_sel:
			bg = Color(0.32, 0.16, 0.04, 0.85) if usable else Color(0.18, 0.18, 0.18, 0.85)
		ci.draw_rect(Rect2(0, y, panel_width, row_height - 3.0), bg)
		if is_sel:
			# 選中列左側的火色標記
			var mark := Color(1.0, 0.72, 0.25) if usable else Color(0.6, 0.6, 0.6)
			ci.draw_rect(Rect2(0, y, 4.0, row_height - 3.0), mark)

		# --- 型名 ---
		var name_col: Color
		if not usable:
			name_col = Color(0.48, 0.46, 0.44)
		elif is_sel:
			name_col = Color(1.0, 0.94, 0.78)
		else:
			name_col = Color(0.88, 0.85, 0.78)
		ci.draw_string(font, Vector2(14, y + row_height * 0.62),
			String(def.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, name_col)

		# --- 右側狀態：可用時顯示呼吸消耗，否則顯示原因 ---
		var status := ""
		var status_col := Color(0.6, 0.78, 1.0)
		match reason:
			"":
				status = "呼 %d" % int(def.breath_cost)
				# 呼吸剛好夠與綽綽有餘給不同的顏色，讓「還能發幾次」讀得出來
				status_col = Color(0.62, 0.82, 1.0) if gauge >= float(def.breath_cost) * 2.0 \
					else Color(0.95, 0.85, 0.45)
			"mastery":
				status = "未修得"
				status_col = Color(0.45, 0.43, 0.41)
			"no_anim":
				status = "未傳"
				status_col = Color(0.45, 0.43, 0.41)
			"cooldown":
				status = "%.1f s" % _player.form_cooldown_left(id)
				status_col = Color(0.55, 0.62, 0.72)
			"breath":
				status = "呼 %d" % int(def.breath_cost)
				status_col = Color(0.72, 0.32, 0.28)
			"airborne":
				status = "需著地"
				status_col = Color(0.72, 0.55, 0.28)
		ci.draw_string(font, Vector2(panel_width - 96.0, y + row_height * 0.62),
			status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_col)

	# --- 底部呼吸槽 ---
	var gy: float = FORM_ORDER.size() * row_height + 6.0
	var gmax: float = maxf(float(_player.get("sun_breath_max")), 0.001)
	ci.draw_rect(Rect2(0, gy, panel_width, 8.0), Color(0, 0, 0, 0.6))
	var w: float = panel_width * clampf(gauge / gmax, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(0, gy, w, 8.0), Color(1.0, 0.68, 0.22))
	ci.draw_rect(Rect2(0, gy, panel_width, 8.0), Color(0, 0, 0, 0.85), false, 1.0)
