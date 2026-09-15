extends Node
## 環境音（autoload：Ambience）—— 全地圖統一，依「地圖 × 時刻」自動選曲。
##
## 為什麼是 autoload 而不是每張圖擺一個 AudioStreamPlayer：
##   ①「同一首蟲鳴」在 slice / shrine / trail 各放一份，等於同一個檔案在
##     四個 .tscn 裡各存一次路徑；換素材要改四個場景檔。
##   ② 場景內的 player 會隨 load_map() 的 queue_free() 一起死。切圖時聲音
##     斷一拍再從頭起——玩家聽得出來「換場景了」，而蟲鳴本來該是連續的。
##   ③ 日夜切換要跨場景保持相位。autoload 不重建，淡入淡出才接得順。
##
## 設計：兩個 AudioStreamPlayer 互相對淡（A/B）。切換時新曲從 -60 dB 起、
## 舊曲往 -60 dB 落，同時走完 FADE_SEC；沒有「先靜音再播」的空檔。

## ── 音軌表 ───────────────────────────────────────────────
## 一張圖可登記多個時段。時段用 [起, 迄) 的遊戲時刻表示，跨午夜寫成
## 起 > 迄（例：[19.0, 5.0] = 傍晚七點到隔天清晨五點）。
## 找不到符合的時段就靜音——沒有素材時保持安靜，比硬塞一首錯的好。
##
## ⚠ 表由上往下比對，**第一個命中的就用**。晝夜交界要「過渡」而不是
##   「切換」，靠的是 FADE_DUSK / FADE_DAWN 把對淡拉長（見 _fade_for）：
##   19:00 一到就換曲，但那個換法是 12 秒的對淡，蟲鳴此消彼長，
##   不是硬切。想調交界時刻改 from/to，想調過渡長度改 FADE_DUSK/DAWN。
##
## ⚠ dB 不是「想多大聲」而是「補多少增益」。夜間素材本身比白天素材
##   安靜 8.1 dB（實測 mean -36.4 vs -28.3），所以夜間各項的 dB 都比
##   白天高約 8——聽起來才是同一個世界的音量，數字高不代表比較吵。
const TRACKS := {
	"slice": [
		{"from": 5.0, "to": 19.0, "stream": "res://assets/audio/ambience/insects_day.ogg", "db": -14.0},
		{"from": 19.0, "to": 5.0, "stream": "res://assets/audio/ambience/insects_night.ogg", "db": -6.0},
	],
	"shrine": [
		{"from": 5.0, "to": 19.0, "stream": "res://assets/audio/ambience/insects_day.ogg", "db": -16.0},
		{"from": 19.0, "to": 5.0, "stream": "res://assets/audio/ambience/insects_night.ogg", "db": -8.0},
	],
	"trail": [
		{"from": 5.0, "to": 19.0, "stream": "res://assets/audio/ambience/insects_day.ogg", "db": -12.0},
		{"from": 19.0, "to": 5.0, "stream": "res://assets/audio/ambience/insects_night.ogg", "db": -4.0},
	],
	"kourindou": [
		{"from": 5.0, "to": 19.0, "stream": "res://assets/audio/ambience/insects_day.ogg", "db": -18.0},
		{"from": 19.0, "to": 5.0, "stream": "res://assets/audio/ambience/insects_night.ogg", "db": -10.0},
	],
}

## 一般對淡秒數（切圖、同時段換曲）。
const FADE_SEC := 2.5
## 日落／日出的對淡秒數。晝夜之間不該是「換曲」而是「天色變了」——
## 2.5 秒聽得出是兩個檔案在交接，12 秒才像蟲鳴自己慢慢換了一批。
## 遊戲一天 20 分鐘（day_seconds=1200）→ 1 遊戲小時 = 50 實時秒，
## 12 秒 ≒ 0.24 遊戲小時，黃昏的長度剛好。
const FADE_DUSK := 12.0
const FADE_DAWN := 10.0
## 交界前後多少「遊戲小時」內算是日落／日出過渡期。
## 0.5 h = 實時 25 秒，涵蓋 12 秒的對淡有餘。
const TRANSITION_WINDOW := 0.5
## 日落與日出的時刻，須與上表的 19.0 / 5.0 一致。
const DUSK_HOUR := 19.0
const DAWN_HOUR := 5.0
## 淡出的目標音量。-60 dB 實質等於無聲，但保留 player 在播放狀態，
## 下次淡入不必重新 seek。
const SILENT_DB := -60.0
## 匯流排名稱。獨立於 Master，之後要單獨調環境音音量（或做選項選單的
## 「環境音」滑桿）不必碰每個 player。
const BUS_NAME := "Ambience"

## @export 給使用者自己在 autoload 面板上調總音量（dB 偏移，疊在音軌表上）。
@export_range(-40.0, 12.0, 0.5) var master_offset_db := 0.0:
	set(v):
		master_offset_db = v
		if _active != null and not _fading:
			_active.volume_db = _current_db + master_offset_db

var _a: AudioStreamPlayer = null
var _b: AudioStreamPlayer = null
var _active: AudioStreamPlayer = null
var _tween: Tween = null
var _fading := false
## 目前播放中的音軌路徑；同一首不重播（切圖時蟲鳴要連續，不能從頭起）
var _current_stream := ""
var _current_db := SILENT_DB
var _bound_map: Node = null
var _last_hour_bucket := -1
## 目前這次對淡的總長度（秒）——驗收時要能證明黃昏真的用了長對淡。
var _fade_total := 0.0


func _ready() -> void:
	_ensure_bus()
	_a = _make_player("環境音A")
	_b = _make_player("環境音B")
	_active = _a
	# DayNight 的時刻是連續變化的（一天 20 分鐘 → 每幀都在動）。
	# 不接 hour_changed 每幀重算，改在 _process 裡用「整點桶」判斷，
	# 只有跨時段時才真的做事。
	set_process(true)


func _make_player(nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.bus = BUS_NAME
	p.volume_db = SILENT_DB
	# 環境音在暫停選單、對話中都該繼續響——世界沒有停下來。
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## 建立 Ambience 匯流排（若專案還沒有）。專案目前沒有 default_bus_layout.tres，
## 全部走 Master；這裡在執行期補一條，不強迫使用者去編輯器開匯流排面板。
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, "Master")


## autoload 之間不保證彼此可見（--script / 工具模式下 DayNight 根本不存在，
## 直接寫 `DayNight.hour` 會是**編譯期**的 "Identifier not found"，整份腳本
## 載不起來——驗收工具第一次跑就是這樣掛的）。走場景樹查名字，拿不到就回
## 預設值，讓這支腳本在任何模式下都能被 load()。
func _daynight_hour() -> float:
	var dn := get_tree().root.get_node_or_null("DayNight")
	return dn.hour if dn != null else 12.0


func _process(_delta: float) -> void:
	var map := _current_map()
	var map_id := String(map.name).to_lower() if map != null else ""
	var hour := _daynight_hour()
	# 每 0.25 遊戲小時（實時 12.5 秒）才檢查一次時段，不是每幀。
	# ⚠ 但晝夜交界附近要細看：0.25 h 的取樣間隔正好和 12 秒的黃昏對淡
	#   同一個數量級，19:00 的換曲最晚可能拖到 19:15 才被發現——玩家會
	#   看到天黑了、蟲鳴還是白天的。交界前後 TRANSITION_WINDOW 內改用
	#   0.02 h（實時 1 秒）取樣，其餘時段維持粗取樣。
	var bucket := int(hour * (50.0 if _near_transition(hour) else 4.0))
	if map == _bound_map and bucket == _last_hour_bucket:
		return
	_bound_map = map
	_last_hour_bucket = bucket
	_apply(map_id, hour)


## 是否落在日落／日出的過渡窗內。跨午夜與跨 24→0 都要算得對，
## 所以用「時刻環上的最短距離」比較，不能直接相減。
func _near_transition(hour: float) -> bool:
	return _hour_distance(hour, DUSK_HOUR) <= TRANSITION_WINDOW \
		or _hour_distance(hour, DAWN_HOUR) <= TRANSITION_WINDOW


## 24 小時環上兩個時刻的距離（0..12）。23.9 與 0.1 的距離是 0.2，不是 23.8。
func _hour_distance(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 24.0 - d)


## 這次換曲該用多長的對淡。晝夜交界拉長成「過渡」，其餘用一般值。
func _fade_for(hour: float) -> float:
	if _hour_distance(hour, DUSK_HOUR) <= TRANSITION_WINDOW:
		return FADE_DUSK
	if _hour_distance(hour, DAWN_HOUR) <= TRANSITION_WINDOW:
		return FADE_DAWN
	return FADE_SEC


## 依 map_id + hour 找出該播哪首，跟現在播的比對，不同才對淡。
func _apply(map_id: String, hour: float) -> void:
	var want := _pick(map_id, hour)
	var want_stream := String(want.get("stream", ""))
	var want_db := float(want.get("db", -14.0))
	if want_stream == _current_stream:
		# 同一首但音量該變（例如同圖不同時段用同素材、不同 db）
		if not is_equal_approx(want_db, _current_db) and _active != null:
			_current_db = want_db
			if not _fading:
				_active.volume_db = want_db + master_offset_db
		return
	_current_stream = want_stream
	_current_db = want_db
	if want_stream.is_empty():
		_fade_out_all()
		return
	_crossfade_to(want_stream, want_db, _fade_for(hour))


## 時段比對。跨午夜（from > to）的段落分成兩截判斷。
func _pick(map_id: String, hour: float) -> Dictionary:
	var list: Array = TRACKS.get(map_id, [])
	for t in list:
		var f := float(t.get("from", 0.0))
		var to := float(t.get("to", 24.0))
		var hit := (hour >= f and hour < to) if f <= to else (hour >= f or hour < to)
		if hit:
			return t
	return {}


func _crossfade_to(path: String, db: float, fade: float = FADE_SEC) -> void:
	if not ResourceLoader.exists(path):
		push_error("[ambience] 音檔不存在：%s" % path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_error("[ambience] 載入失敗：%s" % path)
		return
	# OGG 的循環旗標寫在資源上，不是 player 上。匯入預設不循環，
	# 環境音一定要循環——播完 57 秒就靜音是最容易漏掉的 bug。
	if stream is AudioStreamOggVorbis:
		stream = (stream as AudioStreamOggVorbis).duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		stream = (stream as AudioStreamMP3).duplicate()
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		stream = (stream as AudioStreamWAV).duplicate()
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	var incoming := _b if _active == _a else _a
	var outgoing := _active
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_fading = true
	_fade_total = fade
	var target_db := db + master_offset_db
	var from_db: float = outgoing.volume_db if (outgoing != null and outgoing.playing) else SILENT_DB
	_tween = create_tween().set_parallel(true)
	# ⚠ 不要對 volume_db 直接線性補間。dB 是對數刻度，兩邊各走一半時
	#   總功率會在中點掉下去——12 秒的黃昏會聽到中間「凹」一塊，像有人
	#   把音量旋鈕轉下去再轉回來。改用等功率（equal-power）曲線：
	#   兩邊的**振幅**分別走 sin/cos，平方和恆為 1，聽感上音量不變。
	_tween.tween_method(
		func(t: float) -> void:
			var a := sin(t * PI * 0.5)          # 進場振幅 0→1
			var b := cos(t * PI * 0.5)          # 退場振幅 1→0
			incoming.volume_db = _amp_to_db(a, target_db)
			if outgoing != null and outgoing != incoming and outgoing.playing:
				outgoing.volume_db = _amp_to_db(b, from_db),
		0.0, 1.0, fade)
	_tween.chain().tween_callback(func() -> void:
		_fading = false
		incoming.volume_db = target_db
		if outgoing != null and outgoing != incoming:
			outgoing.stop())
	_active = incoming


## 把 0..1 的線性振幅換成 dB，並以 full_db 為滿刻度。
## amp=0 時回 SILENT_DB（-60），不是 -inf——tween 不吃無限大。
func _amp_to_db(amp: float, full_db: float) -> float:
	if amp <= 0.0001:
		return SILENT_DB
	return maxf(full_db + 20.0 * (log(amp) / log(10.0)), SILENT_DB)


func _fade_out_all() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_fading = true
	_tween = create_tween().set_parallel(true)
	for p in [_a, _b]:
		if p != null and p.playing:
			_tween.tween_property(p, "volume_db", SILENT_DB, FADE_SEC)
	_tween.chain().tween_callback(func() -> void:
		_fading = false
		for p in [_a, _b]:
			if p != null:
				p.stop())


func _current_map() -> Node:
	var main := get_tree().root.get_node_or_null("Main")
	return main.map_root if main != null else null


## ── 除錯 / 驗收 ──────────────────────────────────────────
## tools 腳本與 --playtest 用；回報「現在到底在播什麼、幾分貝」。
func debug_state() -> Dictionary:
	return {
		"stream": _current_stream,
		"db": _current_db,
		"offset_db": master_offset_db,
		"playing": _active != null and _active.playing,
		"active": _active.name if _active != null else "",
		"bus": BUS_NAME,
		"bus_index": AudioServer.get_bus_index(BUS_NAME),
		"map": String(_bound_map.name) if _bound_map != null else "",
		"hour": _daynight_hour(),
		"fading": _fading,
		"fade_total": _fade_total,
		"near_transition": _near_transition(_daynight_hour()),
		"a_db": _a.volume_db if _a != null else 0.0,
		"b_db": _b.volume_db if _b != null else 0.0,
		"a_playing": _a != null and _a.playing,
		"b_playing": _b != null and _b.playing,
	}
