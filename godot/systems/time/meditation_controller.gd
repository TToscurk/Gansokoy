extends Node
## 冥想模式 —— 玩家主動快轉世界時間（緣一坐下調息，睜眼時已經入夜）。
##
## **不是另一套時間**：只把 DayNight.time_scale 拉高。天空、日照、提燈、時段、
## 夜雀屋台、任務條件全部照原本的系統跑，只是走得快。時間的真相只有一個
## 時鐘（autoload DayNight），這裡只是它的速率旋鈕。
##
## 一次冥想：
##   ① 選時長（ui/meditation/meditation_menu）
##   ② 入定：緣一坐下 → 鏡頭緩慢拉遠 → 上下黑邊浮現 → 環境音壓低
##   ③ 快轉：把 time_scale 拉到算出來的值，直到 total_minutes 到點
##   ④ 出定：鏡頭拉回、流速還原、黑邊收掉、解鎖玩家
##
## ⚠ 跨日：目標一律換算成 DayNight.total_minutes 再比。
##   「23:00 冥想到清晨 06:00」用 `hour >= 6.0` 永遠不成立。
##
## 風險：野外圖（RISK_BY_MAP）冥想有機率被打斷 —— 表上沒有的圖就是安全休息點
## （博麗神社、人間之里、寺子屋、鯢吞亭都在村／神社圖，不在表上＝一定安全）。

signal meditation_started(label: String, target_total: int)
signal meditation_finished(interrupted: bool)
## 被打斷時另外發一次，附帶當時的風險分級（"day"/"dusk"/"night"/"storm_night"），
## 讓之後的內容（埋伏、任務、成就）不必自己重算時段。
signal meditation_interrupted(period_key: String)

enum State { IDLE, MENU, MEDITATING }

## 冥想選項。全部換算成「幾分鐘後」，跨日由 total_minutes 吸收。
const OPTIONS := [
	{"label": "30 分鐘", "minutes": 30},
	{"label": "1 小時", "minutes": 60},
	{"label": "3 小時", "minutes": 180},
	{"label": "直到黃昏", "hour": 18.0},     # DayNight.Period.DUSK 起點
	{"label": "直到夜晚", "hour": 19.5},     # DayNight.Period.NIGHT 起點
	{"label": "直到清晨", "hour": 5.0},      # 跨日（23:40 選它 → 隔天 05:00）
]

## 野外圖的冥想風險：{圖 id: {風險分級: 機率}}。**不在表上的圖 = 安全**。
## 分級由 _period_key() 決定：白天／黃昏／夜晚／夜晚＋壞天氣。
const RISK_BY_MAP := {
	"trail": {"day": 0.05, "dusk": 0.15, "night": 0.35, "storm_night": 0.50},
}

## 打斷後播的獨白（data/dialogue/）。內容是「醒來發現有東西」。
const INTERRUPT_DIALOGUE := "yoriichi_meditation"
const HOWL_PATH := "res://assets/audio/sfx/wolf_howl_distant.wav"

## 一次冥想的真實秒數：越長的冥想坐越久，但有上下限（太短沒戲、太長拖台錢）。
@export var min_real_seconds := 5.0
@export var max_real_seconds := 20.0
## 目標真實秒數 = 遊戲分鐘 × 這個比例，再夾到上下限。
@export var duration_fraction := 0.05
## 入定／出定的運鏡秒數。
@export var camera_in_seconds := 2.6
@export var camera_out_seconds := 1.6
## 上下黑邊佔畫面高度的比例。
@export var letterbox_ratio := 0.11
## 冥想期間環境音壓低幾 dB（出定還原 0）。
@export var ambience_duck_db := -14.0

var _main: Node = null
var _player: Node = null
var _menu: Node = null
var _state: State = State.IDLE
var _label := ""
var _target_total := 0
var _interrupt_at := -1
var _period_key := ""
var _cam: Camera3D = null
var _bars: Array[ColorRect] = []
var _duck_tween: Tween = null
var _original_offset := 0.0


func _ready() -> void:
	add_to_group("meditation")
	_main = get_parent()
	_player = _main.get("player") if _main != null else null
	# 冥想中被打了就中斷：世界沒有為你停下來。
	if _player != null and _player.has_signal("player_was_hit"):
		_player.connect("player_was_hit", func(_info: Dictionary) -> void: _interrupt())


## main.gd 掛 UI 時把選單交進來（沿用「UI 由 main 統一 preload 掛載」的寫法）。
func bind_menu(menu: Node) -> void:
	_menu = menu
	if _menu == null:
		return
	_menu.connect("chosen", func(i: int) -> void: start(i))
	_menu.connect("cancelled", func() -> void: _close_menu(true))


## ── 外部查詢 ─────────────────────────────────────────────
func is_meditating() -> bool:
	return _state == State.MEDITATING


func is_busy() -> bool:
	return _state != State.IDLE


## 現在能不能起冥想。時間被鎖住時**必須**拒絕：DayNight.advance_minutes() 在
## 暫停中直接 return，時間永遠走不到目標，冥想會卡在那裡不會結束。
func can_meditate() -> bool:
	if _state != State.IDLE or _player == null:
		return false
	if bool(_player.get("input_locked")):
		return false
	var dm := _node("/root/DialogueManager")
	if dm != null and bool(dm.call("is_active")):
		return false
	var wtm := _node("/root/WorldTimeManager")
	if wtm != null and bool(wtm.call("is_time_paused")):
		return false
	return true


## 這個圖／這個時段的被打斷機率（驗收與 UI 都讀這個，不要在別處重算）。
func interrupt_chance() -> float:
	return float((RISK_BY_MAP.get(String(_main.current_id), {}) as Dictionary).get(_period_key_now(), 0.0))


## 第 index 個選項換算結果：{label, minutes, target_total, clock, crossed_day}
func resolve_option(index: int) -> Dictionary:
	var opt: Dictionary = OPTIONS[clampi(index, 0, OPTIONS.size() - 1)]
	var wtm := _node("/root/WorldTimeManager")
	var now_total: int = int(wtm.get("total_minutes")) if wtm != null else 0
	var minutes := 0
	if opt.has("minutes"):
		minutes = int(opt["minutes"])
	else:
		# 固定時刻的選項換成「還有多久」：已經過了就順延一天（跨日）。
		var target := int(round(fmod(float(opt["hour"]) + 24.0, 24.0) * 60.0))
		minutes = target - (now_total % 1440)
		if minutes <= 0:
			minutes += 1440
	var total := now_total + minutes
	return {
		"label": String(opt["label"]),
		"minutes": minutes,
		"target_total": total,
		"clock": clock_at(total),
		"crossed_day": int(total / 1440) != int(now_total / 1440),
	}


## 絕對分鐘 → "HH:MM"（驗收也用這個，不要在別處另寫一份）。
static func clock_at(total_minutes: int) -> String:
	var t := posmod(total_minutes, 1440)
	return "%02d:%02d" % [int(t / 60), t % 60]


## ── 輸入 ─────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("meditate"):
		return
	if _state == State.MENU:
		return                       # 選單自己處理關閉
	if not can_meditate():
		if _state == State.IDLE:
			_flash("現在不能調息")
		return
	_open_menu()
	get_viewport().set_input_as_handled()


func _open_menu() -> void:
	_state = State.MENU
	_player.set("input_locked", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var wtm := _node("/root/WorldTimeManager")
	var now_total: int = int(wtm.get("total_minutes")) if wtm != null else 0
	var entries := []
	for i in OPTIONS.size():
		var r := resolve_option(i)
		var detail := "%s（+%s）" % [String(r["clock"]), _duration_text(int(r["minutes"]))]
		if bool(r["crossed_day"]):
			detail = "翌日 " + detail
		entries.append({"text": String(r["label"]), "detail": detail})
	if _menu != null:
		_menu.call("open", entries, "現在　第 %d 日 %s" % [int(now_total / 1440) + 1, clock_at(now_total)])


func _close_menu(unlock: bool) -> void:
	if _menu != null and bool(_menu.call("is_open")):
		_menu.call("close")
	if unlock and _state == State.MENU:
		_state = State.IDLE
		_player.set("input_locked", false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ── 開始 / 結束 ──────────────────────────────────────────
func start(index: int) -> void:
	if _state == State.MEDITATING:
		return
	var r := resolve_option(index)
	_target_total = int(r["target_total"])
	_label = String(r["label"])
	_period_key = _period_key_now()
	_close_menu(false)
	_state = State.MEDITATING

	# 真實秒數 → 流速倍率。**倍率是算出來的，不是固定的**：各圖的「一日長度分鐘」
	# 不同（trail 60 分／人里 20 分…），同一個倍率在不同圖會快慢差三倍。
	# 用「這個圖的基準速率」反推，玩家在任何圖坐 30 分鐘都是一樣的體感秒數。
	var wtm := _node("/root/WorldTimeManager")
	var base_rate := 1440.0 / maxf(float(wtm.get("day_seconds")), 1.0)   # 現實 1 秒走幾分
	var dur := clampf(float(r["minutes"]) * duration_fraction, min_real_seconds, max_real_seconds)
	var scale := maxf(1.0, float(r["minutes"]) / maxf(dur * base_rate, 0.0001))

	if _player.has_method("start_meditation_pose"):
		_player.call("start_meditation_pose")
	_player.set("input_locked", true)
	_setup_camera()
	_set_bars(true)
	_duck(true)
	wtm.set("time_scale", scale)
	_interrupt_at = _roll_interrupt()
	meditation_started.emit(_label, _target_total)
	print("[冥想] %s：%s → %s（流速 ×%.1f，%d 分，實際約 %.1f 秒）%s" % [
		_label, clock_at(int(wtm.get("total_minutes")) - int(r["minutes"])), clock_at(_target_total),
		scale, int(r["minutes"]), dur,
		"（野外風險 %d%%，會被打斷）" % int(interrupt_chance() * 100.0) if _interrupt_at > 0 else ""])


func _process(_delta: float) -> void:
	if _state != State.MEDITATING:
		return
	var wtm := _node("/root/WorldTimeManager")
	if wtm == null:
		_finish(true)
		return
	var now: int = int(wtm.get("total_minutes"))
	if _interrupt_at > 0 and now >= _interrupt_at:
		_interrupt()
		return
	if now >= _target_total:
		_finish(false)


func _interrupt() -> void:
	if _state != State.MEDITATING:
		return
	var key := _period_key
	_finish(true)
	_play_howl()
	meditation_interrupted.emit(key)
	var dm := _node("/root/DialogueManager")
	if dm != null and not bool(dm.call("is_active")):
		dm.call("start", INTERRUPT_DIALOGUE)


func _finish(interrupted: bool) -> void:
	if _state != State.MEDITATING:
		return
	var wtm := _node("/root/WorldTimeManager")
	_state = State.IDLE
	_interrupt_at = -1
	if wtm != null:
		wtm.set("time_scale", 1.0)
	_duck(false)
	if _player.has_method("end_meditation_pose"):
		_player.call("end_meditation_pose")
	# 姿勢解除會把 input_locked 放掉（finish_get_up 的既有行為），
	# 但鏡頭還在慢慢拉回來，那幾秒玩家不該已經能跑 —— 先鎖回去。
	_player.set("input_locked", true)
	await _camera_out()
	_set_bars(false)
	_player.set("input_locked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	meditation_finished.emit(interrupted)


## ── 鏡頭 ─────────────────────────────────────────────────
func _gameplay_camera() -> Camera3D:
	var cams := _player.find_children("*", "Camera3D", true, false)
	return cams[0] as Camera3D if not cams.is_empty() else null


## 入定構圖要看**實際頭高**：站姿頭頂約 1.4 m、打坐定姿只有約 0.72 m，
## 固定看 0.9 m 會讓坐著的緣一被拍成「頭頂在畫面下緣」。
func _pose_look_height() -> float:
	if _player == null:
		return 0.9
	var sks := _player.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return 0.9
	var s := sks[0] as Skeleton3D
	var i := s.find_bone("Head")
	if i < 0:
		return 0.9
	# ⚠ get_bone_global_pose 回的是骨骼空間，要再乘骨架自己的 global 才是世界座標
	var w := (s.global_transform * s.get_bone_global_pose(i)).origin
	return clampf(w.y - 0.10, 0.30, 1.30)


func _setup_camera() -> void:
	var gc := _gameplay_camera()
	if gc == null:
		return
	_cam = Camera3D.new()
	_cam.name = "MeditationCamera"
	_cam.fov = gc.fov
	_main.add_child(_cam)
	_cam.global_transform = gc.global_transform
	# 目標構圖：玩家後上方、看向頭下緣；高度隨坐姿/站姿自動調整。
	var body := _player as Node3D
	var basis: Basis = body.global_transform.basis.orthonormalized()
	var look_h := _pose_look_height()
	var cam_h := clampf(look_h + 1.1, 1.2, 2.7)
	var back := 3.2 if look_h > 0.9 else 2.8
	var end_pos: Vector3 = body.global_position + basis * Vector3(0.0, cam_h, back)
	var start_pos: Vector3 = gc.global_position
	var start_look: Vector3 = start_pos + (-gc.global_transform.basis.z) * 8.0
	var end_look: Vector3 = body.global_position + Vector3(0.0, look_h, 0.0)
	_cam.current = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(w: float) -> void:
		if not is_instance_valid(_cam):
			return
		_cam.global_position = start_pos.lerp(end_pos, w)
		_cam.look_at(start_look.lerp(end_look, w), Vector3.UP)
	, 0.0, 1.0, camera_in_seconds)


func _camera_out() -> void:
	if not is_instance_valid(_cam):
		return
	var gc := _gameplay_camera()
	if gc == null:
		_cam.queue_free()
		_cam = null
		return
	var from := _cam.global_transform
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(w: float) -> void:
		if is_instance_valid(_cam) and is_instance_valid(gc):
			_cam.global_transform = from.interpolate_with(gc.global_transform, w)
	, 0.0, 1.0, camera_out_seconds)
	await tw.finished
	if is_instance_valid(gc):
		gc.current = true
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


## ── 黑邊 ─────────────────────────────────────────────────
func _set_bars(on: bool) -> void:
	if _bars.is_empty():
		var ui := CanvasLayer.new()
		ui.name = "MeditationOverlay"
		ui.layer = 19
		_main.add_child(ui)
		for i in 2:
			var bar := ColorRect.new()
			bar.name = "BarTop" if i == 0 else "BarBottom"
			bar.color = Color(0, 0, 0, 1)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.anchor_left = 0.0
			bar.anchor_right = 1.0
			bar.anchor_top = 0.0 if i == 0 else 1.0
			bar.anchor_bottom = bar.anchor_top
			bar.offset_bottom = 0.0
			ui.add_child(bar)
			_bars.append(bar)
	var h := _main.get_viewport().get_visible_rect().size.y * letterbox_ratio
	for i in _bars.size():
		var bar := _bars[i]
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
		tw.tween_property(bar, "offset_bottom", h if on else 0.0, camera_in_seconds if on else camera_out_seconds)


## ── 環境音 ───────────────────────────────────────────────
func _duck(on: bool) -> void:
	var amb := _node("/root/Ambience")
	if amb == null:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var target := float(amb.get("master_offset_db"))
	# 記住原本的偏移，還原時回到它（使用者可能自己在 autoload 面板調過）。
	if on:
		_original_offset = float(amb.get("master_offset_db"))
		target = _original_offset + ambience_duck_db
	else:
		target = _original_offset
	_duck_tween = create_tween()
	_duck_tween.tween_property(amb, "master_offset_db", target, 1.2)


func _play_howl() -> void:
	if not ResourceLoader.exists(HOWL_PATH):
		return
	var stream := load(HOWL_PATH)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = 2.0
	_main.add_child(p)
	p.global_position = _player.global_position + Vector3(0.0, 2.0, -18.0)
	p.finished.connect(p.queue_free)
	p.play()


## ── 風險 ─────────────────────────────────────────────────
## 時段分級（對齊 DayNight.Period：黃昏 18:00–19:29、夜晚 19:30 起、清晨 05:00）
const DUSK_HOUR := 18.0
const NIGHT_HOUR := 19.5
const DAWN_HOUR := 5.0


func _period_key_now() -> String:
	var wtm := _node("/root/WorldTimeManager")
	if wtm == null:
		return "day"
	var h := float(wtm.get("hour"))
	if h >= NIGHT_HOUR or h < DAWN_HOUR:
		return "storm_night" if _bad_weather() else "night"
	if h >= DUSK_HOUR:
		return "dusk"
	return "day"


## 雷雨／濃霧的夜。天象系統是**每張圖**一個（trail 有自己的太陽與天氣），
## 所以先問目前圖的天象系統，問不到才退回全域 Weather。
func _bad_weather() -> bool:
	var map_root = _main.get("map_root")
	if map_root != null:
		var sky := (map_root as Node).find_child("天象系統", true, false)
		if sky != null:
			match int(sky.get("天氣")):
				3, 4, 5:
					return true
				_:
					return false
	var w := _node("/root/Weather")
	if w != null:
		return String(w.get("current")) in ["rain", "fog", "snow"]
	return false


## 這次會不會被打斷；會的話回傳「打斷發生的絕對分鐘」，否則 -1。
## 一坐下就被打斷沒有戲，抓在整段的 25%～90% 之間。
func _roll_interrupt() -> int:
	var p := interrupt_chance()
	if p <= 0.0 or randf() >= p:
		return -1
	var wtm := _node("/root/WorldTimeManager")
	var now: int = int(wtm.get("total_minutes"))
	var span := maxi(_target_total - now, 2)
	return now + clampi(int(float(span) * randf_range(0.25, 0.9)), 1, span - 1)


func _duration_text(minutes: int) -> String:
	var h := int(minutes / 60)
	var m := minutes % 60
	if h > 0 and m > 0:
		return "%d 時 %d 分" % [h, m]
	if h > 0:
		return "%d 時" % h
	return "%d 分" % m


func _flash(text: String) -> void:
	if _main != null and _main.has_method("_flash_message"):
		_main.call("_flash_message", text)


func _node(path: String) -> Node:
	return get_tree().root.get_node_or_null(path) if is_inside_tree() else null
