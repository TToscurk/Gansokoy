extends Node
## NPC Living World 的 JEV Decision Provider（可切換；預設不啟用）。
## 只負責「從 director 算好的合法候選事件裡挑一個」——不生成台詞、不碰導航／動畫／預約。
##   mode = "jev"  ：用 addons/godot_jev（TypeSafe Jev System One 的 Choice 問題）
##   mode = "mock" ：本機假提供者（延遲／失敗可設定），驗證非同步流程與退回機制用
## 金鑰：只讀環境變數 TYPESAFE_API_KEY／JEV_API_KEY。拒絕使用 ProjectSettings 的 jev/config/api_key
##   （寫在 project.godot 會進 Git、也會被打包進遊戲客戶端）；偵測到就當成沒有金鑰並報錯。
## 任何失敗（沒有金鑰、連線失敗、HTTP 錯誤、逾時）→ ticket.ok = false，director 立刻改用原本的權重決策。

@export_enum("jev", "mock") var mode := "jev"
## 固定版本以便重現（jev-latest 會隨新版移動，答案可能改變）
@export var model := "jev-1.13.0"
## 決策等待上限（秒）。超過就取消請求、改用原本決策
@export var timeout_s := 3.0
@export var mock_latency := Vector2(0.12, 0.35)
## mock 失敗注入："none" 正常、"timeout" 永不回應、"error" 立刻失敗、"flaky" 三成失敗
@export_enum("none", "timeout", "error", "flaky") var mock_fail := "none"

var stats := {"calls": 0, "ok": 0, "fail": 0, "timeout": 0, "no_key": 0, "input_tokens": 0, "lat_ms": [], "errors": {}}
var _jev: Node
var _warned_setting_key := false

const INSTRUCTIONS := "You are deciding what a Touhou Project character in a living-world village simulation does next, on her own initiative. Use the character profile, her personality, her relationships, her current location, the time of day, what she knows, what she did recently and who is nearby. Pick the ONE option this character would most plausibly choose right now. Prefer options that fit her personality and interests, avoid repeating what she just did, and consider travel distance (far trips need a reason). Every option listed is currently possible."


func available() -> bool:
	if mode == "mock":
		return true
	return _env_key() != ""


func _env_key() -> String:
	if str(ProjectSettings.get_setting("jev/config/api_key", "")).strip_edges() != "":
		if not _warned_setting_key:
			_warned_setting_key = true
			push_error("[NpcLife/JEV] project setting jev/config/api_key 有值——禁止把金鑰放進專案（會進 Git／打包）。JEV 停用，改用原本決策。")
		return ""
	var k := OS.get_environment("TYPESAFE_API_KEY").strip_edges()
	if k == "":
		k = OS.get_environment("JEV_API_KEY").strip_edges()
	return k


func _ensure_client() -> void:
	if _jev != null:
		return
	# 不啟用編輯器外掛／autoload（不改 project.godot），直接掛一個 client 節點
	_jev = (load("res://addons/godot_jev/jev.gd") as GDScript).new()
	_jev.name = "JevClient"
	add_child(_jev)
	ProjectSettings.set_setting("jev/config/timeout", timeout_s + 2.0)   # 只在記憶體，不存檔
	ProjectSettings.set_setting("jev/config/max_retries", 0)              # 遊戲內不重試：逾時就退回原決策


## 送出決策；回傳 ticket（Dictionary，非同步填入 done／ok／choice／conf／ms／why／tokens／probs）
func decide(state: Dictionary, options: Dictionary) -> Dictionary:
	var t := {"done": false, "ok": false, "choice": "", "conf": 0.0, "ms": 0.0, "why": "", "tokens": 0, "probs": {}, "t0": Time.get_ticks_msec(), "provider": mode}
	stats.calls += 1
	if mode == "mock":
		_mock(t, state, options)
		return t
	if _env_key() == "":
		_finish(t, false, "no_key")
		return t
	_ensure_client()
	var h: Object = _jev.call("choice", state, INSTRUCTIONS, options, model)
	t["handle"] = h
	h.connect("finished", func(_hh: Object) -> void: _on_jev_done(t, h))
	return t


func cancel(t: Dictionary, why := "timeout") -> void:
	if bool(t.done):
		return
	_finish(t, false, why)     # 先標記完成：handle.cancel() 會同步發 finished，避免重複計成 canceled
	if t.has("handle") and is_instance_valid(t.handle):
		t.handle.call("cancel", why)


func _on_jev_done(t: Dictionary, h: Object) -> void:
	if bool(t.done):
		return
	if bool(h.call("is_success")):
		t.choice = String(h.call("get_choice", "q", ""))
		t.conf = float(h.call("get_confidence", "q", 0.0))
		t.probs = h.call("get_probabilities", "q")
		t.tokens = int(h.call("get_input_tokens"))
		stats.input_tokens += int(t.tokens)
		t["model"] = String(h.call("get_model"))
		_finish(t, t.choice != "", "" if t.choice != "" else "empty_choice")
	else:
		var e: Object = h.call("get_error")
		var why := "error"
		if e != null:
			why = "auth" if bool(e.call("is_auth_error")) else ("rate_limited" if bool(e.call("is_rate_limited")) else ("canceled" if bool(e.call("is_canceled")) else "http_or_network"))
			t["error_text"] = str(e).left(160)
		_finish(t, false, why)


func _finish(t: Dictionary, ok: bool, why: String) -> void:
	t.done = true
	t.ok = ok
	t.why = why
	t.ms = float(Time.get_ticks_msec() - int(t.t0))
	if ok:
		stats.ok += 1
		(stats.lat_ms as Array).append(t.ms)
	else:
		stats.fail += 1
		if why == "timeout":
			stats.timeout += 1
		elif why == "no_key":
			stats.no_key += 1
		stats.errors[why] = int(stats.errors.get(why, 0)) + 1


# ─── mock：關鍵字貼合度＋距離＋近期重複懲罰（只為了驗證流程，不代表 JEV 品質） ───

func _mock(t: Dictionary, state: Dictionary, options: Dictionary) -> void:
	var lat := randf_range(mock_latency.x, mock_latency.y)
	match mock_fail:
		"timeout":
			return
		"error":
			_finish.call_deferred(t, false, "mock_error")
			return
		"flaky":
			if randf() < 0.3:
				get_tree().create_timer(lat).timeout.connect(func() -> void: _finish(t, false, "mock_error"))
				return
	var interests: Array = state.get("character", {}).get("interests", [])
	var recent: Array = state.get("now", {}).get("recent_activities", [])
	var best := ""
	var best_s := -INF
	for k in options:
		var desc := String(options[k])
		var s := randf() * 0.3
		for w in interests:
			if desc.find(String(w)) >= 0:
				s += 1.0
		for r in recent:
			if desc.find(String(r)) >= 0:
				s -= 0.8
		var m := RegEx.create_from_string("(\\d+) m away").search(desc)
		if m != null:
			s -= float(m.get_string(1)) / 150.0
		if s > best_s:
			best_s = s
			best = String(k)
	get_tree().create_timer(lat).timeout.connect(func() -> void:
		if bool(t.done):
			return
		t.choice = best
		t.conf = 0.5
		_finish(t, true, ""))
