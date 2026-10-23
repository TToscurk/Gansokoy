extends Node3D
## R9 技能音效事件（候選；可重用）。每個事件獨立設定，不必每次重配整組：
##   events（sun_breathing.json 的 audio 欄）：{名稱: {stream, at（技能秒，選用）, db, pitch, loop_from/loop_to（循環聲的時間窗）, on（"hit"＝命中時播）}}
##   * 揮刀聲／點燃聲：at＝技能時間（動畫時鐘，Hit Stop 停格時不前進）
##   * 火焰聲：loop_from..loop_to 之間淡入淡出（循環素材）
##   * 命中聲：on＝"hit"，只在真正命中時由場景呼叫 hit() 觸發；空揮不會播
## 素材全部重用 res://assets/audio/sfx/（正式音效，唯讀）。
var events := {}
var _fired := {}
var _players: Array = []
var _loop: AudioStreamPlayer3D
var _loop_ev := ""
var muted := false
var _cache := {}

## 預先載入（第一次 load 會卡一幀；R9 量測第一次出招 script 23 ms）
func preload_events(ev: Dictionary) -> void:
	for k in ev:
		_stream(str(ev[k]["stream"]))

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]
var ev_log: Array = []

func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 60.0
		add_child(p)
		_players.append(p)
	_loop = AudioStreamPlayer3D.new()
	_loop.unit_size = 6.0
	add_child(_loop)

func begin(ev: Dictionary) -> void:
	events = ev
	_fired = {}
	_loop_ev = ""
	for k in events:
		if (events[k] as Dictionary).has("loop_from"):
			_loop_ev = k
			_loop.stream = _stream(str(events[k]["stream"]))
			_loop.volume_db = -60.0
			_loop.pitch_scale = float(events[k].get("pitch", 1.0))
			if not muted:
				_loop.play()

func end() -> void:
	_loop_ev = ""

func _play(name_: String, t: float) -> void:
	var e: Dictionary = events[name_]
	ev_log.append({"ev": name_, "t": snappedf(t, 0.001)})
	if muted:
		return
	var p: AudioStreamPlayer3D = null
	for q in _players:
		if not (q as AudioStreamPlayer3D).playing:
			p = q
			break
	if p == null:
		p = _players[0]
	p.stream = _stream(str(e["stream"]))
	p.volume_db = float(e.get("db", 0.0))
	p.pitch_scale = float(e.get("pitch", 1.0)) * randf_range(0.97, 1.03)
	p.play()

## 每幀：技能時間 t（動畫時鐘）、真實 dt
func frame(t: float, dt: float, active: bool) -> void:
	if active:
		for k in events:
			var e: Dictionary = events[k]
			if e.has("at") and not _fired.has(k) and t >= float(e["at"]):
				_fired[k] = true
				_play(k, t)
	var want := -60.0
	if _loop_ev != "" and active:
		var e2: Dictionary = events[_loop_ev]
		if t >= float(e2["loop_from"]) and t <= float(e2["loop_to"]):
			want = float(e2.get("db", -10.0))
	_loop.volume_db = move_toward(_loop.volume_db, want, dt * 80.0)
	if _loop_ev == "" and _loop.volume_db <= -59.0 and _loop.playing:
		_loop.stop()

func hit(t: float) -> void:
	for k in events:
		if str((events[k] as Dictionary).get("on", "")) == "hit":
			_play(k, t)
