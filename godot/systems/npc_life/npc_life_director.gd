extends Node
## NPC Autonomous Life Director（docs/NPC自主生活系統.md）
## 掛在地圖場景（village_v2.tscn 的 NpcLife 節點）。不改既有 NPC／戰鬥／對話系統：
##   - 讀 data/npc_life/heroes.json（身分／性格／關係／動作對照／事件）、social.json（雙人對話主題）、
##     data/npc_life/<map>.json（地點、Smart Object、據點、世界觸發）、<map>_walk.bin（烘焙可走格）
##   - HERO 本體（npc_life_actor.gd）註冊進來；Director 負責「挑事件」「預約」「雙人同步」「事實／傳聞」「事件鏈」，
##     Actor 負責「走路、轉身、動作、對白泡泡、被玩家打斷」。
##   - 事件狀態：Available → Reserved → Traveling → Interacting → Completed / Interrupted / Failed → Cooldown
##   - 遠距 HERO 降頻（actor 自己依距離跳幀）；尋路用 AStarGrid2D，每次只在 HERO 需要新目標時算一次。
## 測試：time_scale 加速「生活時鐘」（冷卻、持續時間、世界觸發），不動 Engine.time_scale。

signal event_state(hero_id: String, event_id: String, state: String, info: Dictionary)
signal fact_changed(fact: String, active: bool, source: String)
signal hero_said(hero_id: String, text: String, to: String)

@export var map_id := "village_v2"
@export var enabled := true
@export var verbose := true
## 生活時鐘倍率（只影響本系統的冷卻／持續／觸發；測試加速用）
@export var time_scale := 1.0
@export var start_stagger_max := 6.0
@export_group("Decision provider（JEV，可切換）")
## 用 JEV 挑下一個生活事件的 HERO（空＝全部用原本的權重決策）。反應事件（priority ≥ 5）永遠用原本決策
@export var jev_heroes: PackedStringArray = []
@export_enum("jev", "mock") var jev_mode := "jev"
@export var jev_timeout := 3.0
@export var jev_model := "jev-1.13.0"

const HEROES_PATH := "res://data/npc_life/heroes.json"
const SOCIAL_PATH := "res://data/npc_life/social.json"

var heroes := {}          # id -> actor
var defs := {}            # id -> hero def
var shared := {}          # heroes.json 的 _shared
var topics: Array = []
var mapd := {}
var objects := {}         # id -> {def, node, reserved_by, hidden_until, enabled}
var world := {}           # 世界事實 name -> {until, source}
var knows := {}           # hero -> {fact: until}
var memory := {}          # hero -> {last: {event_id: clock}, recent: [ids], pair: {other: clock}}
var sessions: Array = []
var clock := 0.0
var history: Array = []   # [clock, hero, event, state, info]
var stats := {}           # hero -> {state: count}
var triggers: Array = []
var _kedama: Node3D

var grid: AStarGrid2D
var gcode := PackedByteArray()
var gheight := PackedByteArray()
var gx0 := 0.0
var gz0 := 0.0
var gcell := 0.5
var gw := 0
var gh := 0
var _ready_done := false
var path_stats := {"n": 0, "max_ms": 0.0, "total_ms": 0.0}
var voice: Node               # npc_voice.gd（data/npc_life/voices.json）
var jev: Node                 # npc_life_jev_provider.gd（jev_heroes 不空時才建立）
var _pending := {}            # hero -> {"t": ticket, "map": {option_id: {ev, partner}}}
var decision_stats := {}      # hero -> {"jev": n, "builtin": n, "priority": n, "fallback": {why: n}}


func _ready() -> void:
	add_to_group("npc_life_director")
	if not enabled:
		return
	defs = _json(HEROES_PATH)
	shared = defs.get("_shared", {})
	defs.erase("_shared")
	defs.erase("_note")
	topics = _json(SOCIAL_PATH).get("topics", [])
	mapd = _json("res://data/npc_life/%s.json" % map_id)
	_load_grid()
	for o in mapd.get("objects", []):
		var rec := {"def": o, "node": null, "reserved_by": "", "hidden_until": -1.0, "enabled": not bool(o.get("dynamic", false))}
		objects[o.id] = rec
	_setup_jev()
	if FileAccess.file_exists("res://data/npc_life/voices.json"):
		voice = (load("res://systems/npc_life/npc_voice.gd") as GDScript).new()
		voice.name = "NpcVoice"
		add_child(voice)
	triggers = mapd.get("world_triggers", []).duplicate(true)
	for t in triggers:
		t["next"] = _rand_range(t.get("first", [60, 90]))
	_late_init.call_deferred()


func _late_init() -> void:
	var root := get_parent()
	for id in objects:
		var o: Dictionary = objects[id]
		var np := String(o.def.get("node", ""))
		if np != "":
			o.node = root.get_node_or_null(np)
			if o.node == null:
				o.enabled = false
				_log("", "", "OBJECT_INVALID", {"object": id, "node": np})
	for a in get_tree().get_nodes_in_group("npc_life_hero"):
		register_hero(a)
	_ready_done = true
	_log("", "", "READY", {"heroes": heroes.keys(), "objects": objects.size(), "grid": "%dx%d" % [gw, gh]})


func register_hero(a: Node) -> void:
	var id := String(a.get("hero_id"))
	if id == "" or heroes.has(id) or not defs.has(id):
		return
	heroes[id] = a
	memory[id] = {"last": {}, "recent": [], "pair": {}}
	knows[id] = {}
	stats[id] = {}
	a.call("life_setup", self, defs[id], shared, _rand_range([0.5, start_stagger_max]))


# ─────────────────────────────── 時鐘、世界觸發、對話同步 ───────────────────────────────

func _physics_process(dt: float) -> void:
	if not enabled or not _ready_done:
		return
	var ld := dt * time_scale
	clock += ld
	# 事實過期
	for f in world.keys():
		if float(world[f].until) >= 0.0 and clock > float(world[f].until):
			_clear_world(f, "expired")
	for h in knows:
		for f in (knows[h] as Dictionary).keys():
			if clock > float(knows[h][f]):
				knows[h].erase(f)
	# 物件重生
	for id in objects:
		var o: Dictionary = objects[id]
		if float(o.hidden_until) >= 0.0 and clock >= float(o.hidden_until):
			o.hidden_until = -1.0
			if o.node != null:
				(o.node as Node3D).visible = true
	_tick_triggers()
	for s in sessions.duplicate():
		s.rt = float(s.get("rt", 0.0)) + dt
		_tick_session(s, ld)


func _tick_triggers() -> void:
	for t in triggers:
		if clock < float(t.next):
			continue
		t.next = clock + _rand_range(t.get("repeat", [600, 900]))
		if t.has("forbid_world") and _any_world(t.forbid_world):
			continue
		match String(t.get("kind", "")):
			"spawn_kedama":
				if _kedama != null and is_instance_valid(_kedama):
					continue
				_spawn_kedama(t)
			"set_world":
				set_world(String(t.fact), float(t.get("ttl", 600)), "world")
		_log("", String(t.id), "TRIGGER", {"kind": t.get("kind", "")})


func _spawn_kedama(t: Dictionary) -> void:
	if _kedama != null and is_instance_valid(_kedama):
		return
	var at := _v2(mapd.anomaly.kedama_at)
	var ks := load("res://characters/yokai/kedama.tscn") as PackedScene
	_kedama = ks.instantiate() as Node3D
	_kedama.name = "LifeAnomalyKedama"
	_kedama.set("notice_range", 0.0)   # 不因玩家靠近就逃；由 HERO 事件結果決定
	get_parent().add_child(_kedama)
	_kedama.global_position = Vector3(at.x, ground_y(at, 1.0), at.y)
	objects["anomaly_spot"].enabled = true
	set_world(String(t.fact), float(t.get("ttl", 900)), "world")


func kedama_flee() -> void:
	if _kedama != null and is_instance_valid(_kedama):
		if _kedama.has_method("flee_away"):
			_kedama.call("flee_away", Vector3(-1, 0, 0.3).normalized())
		_kedama = null
	if objects.has("anomaly_spot"):
		objects["anomaly_spot"].enabled = false


# ─────────────────────────────── 事實／傳聞 ───────────────────────────────

func set_world(f: String, ttl: float, source: String) -> void:
	world[f] = {"until": clock + ttl if ttl > 0.0 else -1.0, "source": source}
	fact_changed.emit(f, true, source)
	_log(source, f, "FACT_SET", {"ttl": ttl})


func _clear_world(f: String, why: String) -> void:
	if not world.has(f):
		return
	world.erase(f)
	# 異狀事實消失（過期／被解決）→ 毛玉也離開，世界狀態一致
	if f.begins_with("anomaly") and f != "anomaly_resolved":
		kedama_flee()
	fact_changed.emit(f, false, why)
	_log("", f, "FACT_CLEAR", {"why": why})
	for h in knows:
		(knows[h] as Dictionary).erase(f)


## 事件的世界前提是否仍成立（執行途中被別人解決／取消時中止）
func event_still_valid(_hero: String, ev: Dictionary) -> bool:
	for f in ev.get("need_world", []):
		if not world.has(f):
			return false
	for f in ev.get("not_world", []):
		if world.has(f):
			return false
	return true


func object_valid(oid: String) -> bool:
	if not objects.has(oid):
		return false
	var o: Dictionary = objects[oid]
	if not o.enabled:
		return false
	var np := String(o.def.get("node", ""))
	return np == "" or (o.node != null and is_instance_valid(o.node) and (o.node as Node).is_inside_tree())


func has_world(f: String) -> bool:
	return world.has(f)


func learn(hero: String, f: String, ttl := 900.0) -> void:
	if not knows.has(hero) or (knows[hero] as Dictionary).has(f):
		return
	knows[hero][f] = clock + ttl
	_log(hero, f, "LEARN", {})
	if heroes.has(hero):
		heroes[hero].call("on_learn", f)


func hero_knows(hero: String, f: String) -> bool:
	return knows.has(hero) and (knows[hero] as Dictionary).has(f)


func _any_world(arr: Array) -> bool:
	for f in arr:
		if world.has(f):
			return true
	return false


## 知覺：actor 每秒呼叫一次（世界事物在視野半徑內 → 學到事實；看到感興趣的物件 → 依性格臨時改道）
func perceive(hero: String, pos: Vector3) -> void:
	_try_divert(hero, pos)
	var notice: Dictionary = defs[hero].get("notice", {})
	if notice.has("anomaly") and _kedama != null and is_instance_valid(_kedama):
		if pos.distance_to(_kedama.global_position) <= float(notice.anomaly.get("radius", 16.0)):
			for f in world:
				if String(f).begins_with("anomaly"):
					learn(hero, f)


## 性格：走路途中瞥見感興趣的東西（heroes.json 的 divert），以機率放下手上的事改去那裡
func _try_divert(hero: String, pos: Vector3) -> void:
	var dv: Dictionary = defs[hero].get("divert", {})
	var a: Node = heroes.get(hero)
	if dv.is_empty() or a == null:
		return
	var p: Dictionary = a.get("_plan")
	if p.is_empty() or String(a.get("_step").get("op", "")) != "goto" or String(a.get("_paused_for")) != "":
		return
	var ev: Dictionary = p.event
	if bool(ev.get("focus", false)) or int(ev.get("priority", 0)) >= 5 or String(ev.id) == String(dv.event):
		return
	if not a.get("_session").is_empty():
		return
	var seen: Dictionary = p.get("_divert_seen", {})
	p["_divert_seen"] = seen
	for oid in objects:
		var o: Dictionary = objects[oid]
		if seen.has(oid) or not o.enabled or String(o.reserved_by) != "" or float(o.hidden_until) >= 0.0:
			continue
		var tag_ok := false
		for t in dv.get("tags", []):
			if (o.def.tags as Array).has(t):
				tag_ok = true
		if not tag_ok or pos.distance_to(_v3(o.def.stand)) > float(dv.get("radius", 8.0)):
			continue
		seen[oid] = true
		var mem: Dictionary = memory[hero]
		if clock - float(mem.last.get(String(dv.event), -1e9)) < float(dv.get("cooldown", 60.0)):
			return
		if randf() < float(dv.get("chance", 0.5)):
			_log(hero, String(ev.id), "DIVERT", {"to": oid, "event": dv.event})
			a.call("say", String(dv.get("say", "")))
			force_event(hero, String(dv.event), "", oid)
		return


# ─────────────────────────────── 挑事件 ───────────────────────────────

## actor 閒下來時呼叫；回傳 plan（{} ＝暫時沒事，actor 會小待一下再問）
func request_plan(hero: String, near := 0.0) -> Dictionary:
	var a: Node = heroes.get(hero)
	if a == null:
		return {}
	var d: Dictionary = defs[hero]
	var hour := _hour()
	var cands: Array = []
	var total := 0.0
	for ev in d.get("events", []):
		var w := _score(hero, ev, hour)
		if w <= 0.0:
			continue
		cands.append([ev, w])
		total += w
	if near > 0.0:
		return _plan_near(hero, cands, near)
	if cands.is_empty():
		_pending.erase(hero)
		return {}
	# 優先度高（反應事件）先：priority ≥ 5 的候選直接取最高（不交給 JEV，保留事件優先權）
	var best_pri := -1
	for c in cands:
		best_pri = maxi(best_pri, int(c[0].get("priority", 0)))
	var by := "builtin"
	if best_pri >= 5:
		by = "priority"
		_pending.erase(hero)
		var pool := cands.filter(func(c): return int(c[0].get("priority", 0)) == best_pri)
		cands = pool
		total = 0.0
		for c in cands:
			total += float(c[1])
	elif _uses_jev(hero):
		var jr := _jev_decide(hero, cands)
		if not jr.is_empty():
			return jr          # {"pending": true} 或 JEV 選中的 plan
		by = "fallback"
	var r := randf() * total
	for c in cands:
		r -= float(c[1])
		if r <= 0.0:
			var p := _build_plan(hero, c[0])
			if not p.is_empty():
				_note_decision(hero, by, String(c[0].id), {})
				return p
	return {}


## 被約聊天、對方還在遠處時：只挑「不離開附近」的一般事件（不社交、不含反應事件），
## 讓等的人不要原地罰站；對方走近時由 actor 暫停此事件，聊完續做。
func _plan_near(hero: String, cands: Array, near: float) -> Dictionary:
	var from := _xz3((heroes[hero] as Node3D).global_position)
	var pool := cands.filter(func(c): return String(c[0].get("kind", "")) in ["object", "place", "route", "home"] and int(c[0].get("priority", 0)) < 5 and not bool(c[0].get("focus", false)))
	pool.shuffle()
	for c in pool:
		var p := _build_plan(hero, c[0])
		if p.is_empty():
			continue
		var ok := true
		for st in p.steps:
			if st.has("to") and _xz3(st.to).distance_to(from) > near:
				ok = false
				break
		if ok:
			_note_decision(hero, "held_local", String(c[0].id), {})
			return p
		if String(p.get("object", "")) != "":
			objects[p.object].reserved_by = ""
	return {}


func _xz3(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ─────────────────────────────── JEV Decision Provider ───────────────────────────────

func _setup_jev() -> void:
	if jev_heroes.is_empty() or jev != null:
		return
	jev = (load("res://systems/npc_life/npc_life_jev_provider.gd") as GDScript).new()
	jev.name = "JevProvider"
	jev.set("mode", jev_mode)
	jev.set("timeout_s", jev_timeout)
	jev.set("model", jev_model)
	add_child(jev)
	_log("", "", "JEV_PROVIDER", {"mode": jev_mode, "heroes": jev_heroes, "available": bool(jev.call("available"))})


func _uses_jev(hero: String) -> bool:
	return jev != null and jev_heroes.has(hero) and bool(jev.call("available"))


func _note_decision(hero: String, by: String, ev_id: String, info: Dictionary) -> void:
	var ds: Dictionary = decision_stats.get(hero, {"jev": 0, "builtin": 0, "priority": 0, "fallback": {}, "builtin_after_fallback": 0})
	decision_stats[hero] = ds
	if by == "fallback" and ev_id != "" and not info.has("why"):
		by = "builtin_after_fallback"       # 退回後由原本權重決策選出的事件
		ds[by] = int(ds.get(by, 0)) + 1
	elif by.begins_with("fallback"):
		var why := String(info.get("why", "?"))
		ds.fallback[why] = int(ds.fallback.get(why, 0)) + 1
	else:
		ds[by] = int(ds.get(by, 0)) + 1
	var inf := info.duplicate()
	inf["by"] = by
	_log(hero, ev_id, "DECIDE", inf)


## 非同步：第一次呼叫送出請求並回 {"pending": true}；之後輪詢。失敗／逾時／選項失效 → 回 {}（呼叫端用原本決策）
func _jev_decide(hero: String, cands: Array) -> Dictionary:
	var pd: Dictionary = _pending.get(hero, {})
	if pd.is_empty():
		var opts := _jev_options(hero, cands)
		if opts.map.size() < 2:
			return {}                         # 只有一個選項，不必問
		var tk: Dictionary = jev.call("decide", _jev_state(hero), opts.desc)
		_pending[hero] = {"t": tk, "map": opts.map, "n": opts.map.size()}
		return {"pending": true}
	var tk: Dictionary = pd.t
	if not bool(tk.done):
		if Time.get_ticks_msec() - int(tk.t0) > int(jev_timeout * 1000.0):
			jev.call("cancel", tk, "timeout")
		else:
			return {"pending": true}
	_pending.erase(hero)
	if not bool(tk.ok):
		_note_decision(hero, "fallback", "", {"why": tk.why, "ms": tk.ms})
		return {}
	var sel: Dictionary = pd.map.get(tk.choice, {})
	if sel.is_empty():
		_note_decision(hero, "fallback", "", {"why": "unknown_choice", "choice": tk.choice})
		return {}
	var ev: Dictionary = sel.ev
	var e2: Dictionary = ev.duplicate(true)
	if String(sel.partner) != "":
		e2["partners"] = [sel.partner]
	# 等待期間世界可能變了：重新檢查合法性（冷卻、條件、對象可否、物件預約）
	if _score(hero, e2, _hour()) <= 0.0:
		_note_decision(hero, "fallback", String(ev.id), {"why": "stale", "choice": tk.choice})
		return {}
	var p := _build_plan(hero, e2)
	if p.is_empty():
		_note_decision(hero, "fallback", String(ev.id), {"why": "build_failed", "choice": tk.choice})
		return {}
	p.event = ev
	_note_decision(hero, "jev", String(ev.id), {"choice": tk.choice, "conf": snappedf(float(tk.conf), 0.001), "ms": tk.ms, "options": pd.n, "tokens": tk.tokens, "provider": tk.provider})
	return p


## 候選 → JEV 選項（社交依對象展開；每項附目標與距離）
func _jev_options(hero: String, cands: Array) -> Dictionary:
	var desc := {}
	var map := {}
	var me: Node3D = heroes[hero]
	for c in cands:
		var ev: Dictionary = c[0]
		var label := String(ev.get("label", ev.id))
		match String(ev.get("kind", "")):
			"social":
				var rel: Dictionary = defs[hero].get("relationships", {})
				for other in ev.get("partners", rel.keys()):
					if not _partner_ok(hero, ev, String(other)):
						continue
					var o: Node3D = heroes[other]
					var oid := "%s@%s" % [ev.id, other]
					var doing := String(o.call("current_event"))
					desc[oid] = "%s：去找%s聊天（關係：%s；%d m away；她現在：%s）" % [label, defs[other].get("name", other), rel.get(other, {}).get("style", ""), int(me.global_position.distance_to(o.global_position)), _event_label(String(other), doing) if doing != "" else "閒著"]
					map[oid] = {"ev": ev, "partner": other}
			"object":
				var obj := _pick_object(hero, ev)
				var o_def: Dictionary = objects[obj].def if obj != "" else {}
				var dist := int(me.global_position.distance_to(_v3(o_def.stand))) if obj != "" else 0
				desc[ev.id] = "%s（地點：%s；%d m away）" % [label, o_def.get("label", obj), dist]
				map[ev.id] = {"ev": ev, "partner": ""}
			"place", "route":
				var pl: Array = ev.get("places", [])
				var dist2 := int(me.global_position.distance_to(_v3(mapd.places[pl[0]]))) if not pl.is_empty() else 0
				desc[ev.id] = "%s（%s；%d m away）" % [label, "、".join(pl.map(func(x): return _place_label(String(x)))), dist2]
				map[ev.id] = {"ev": ev, "partner": ""}
			"home":
				var hd: Dictionary = mapd.get("homes", {}).get(hero, {})
				desc[ev.id] = "%s（%s）" % [label, "離開人里回家" if bool(hd.get("leave", false)) else "回到自己的據點"]
				map[ev.id] = {"ev": ev, "partner": ""}
	return {"desc": desc, "map": map}


func _partner_ok(hero: String, ev: Dictionary, other: String) -> bool:
	if not heroes.has(other) or other == hero:
		return false
	var o: Node3D = heroes[other]
	if ev.has("max_dist") and (heroes[hero] as Node3D).global_position.distance_to(o.global_position) > float(ev.max_dist):
		return false
	if not bool(o.call("can_accept_social", hero)):
		return false
	if _pick_topic(hero, other, ev).is_empty():
		return false
	return clock - float(memory[hero].pair.get(other, -1e9)) >= float(ev.get("pair_cooldown", 150.0))


## JEV state：角色檔案、性格、關係、位置、時間、所知、近況、附近的人、世界狀態（不放台詞、不放座標以外的雜訊）
func _jev_state(hero: String) -> Dictionary:
	var d: Dictionary = defs[hero]
	var me: Node3D = heroes[hero]
	var ft: Dictionary = shared.get("fact_text", {})
	var rel := {}
	for other in d.get("relationships", {}):
		rel[String(defs.get(other, {}).get("name", other))] = d.relationships[other].get("style", "")
	var recent: Array = []
	for eid in (memory[hero].recent as Array):
		recent.append(_event_label(hero, String(eid)))
	var known: Array = []
	for f in (knows[hero] as Dictionary):
		known.append(String(ft.get(f, f)))
	var wl: Array = []
	for f in world:
		wl.append(String(ft.get(f, f)))
	var near: Array = []
	for other in heroes:
		if other == hero or not (heroes[other] as Node3D).visible:
			continue
		var dd := me.global_position.distance_to((heroes[other] as Node3D).global_position)
		if dd < 60.0:
			var ce := String(heroes[other].call("current_event"))
			near.append({"name": defs[other].get("name", other), "distance_m": int(dd), "doing": _event_label(String(other), ce) if ce != "" else "閒著"})
	var h := _hour()
	var pers := {}
	for k in d.get("personality", {}):
		pers[k] = d.personality[k]
	return {
		"character": {"name": d.get("name", hero), "identity": d.get("identity", ""), "personality_0_to_1": pers, "interests": d.get("interests", [])},
		"relationships": rel,
		"now": {"time": "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)], "day_phase": _day_phase(h), "location": _place_label(_nearest_place(me.global_position)), "recent_activities": recent, "knows": known},
		"world": wl,
		"nearby_characters": near,
	}


static func _day_phase(h: float) -> String:
	if h < 5.0: return "深夜"
	if h < 9.0: return "早上"
	if h < 11.5: return "上午"
	if h < 13.5: return "中午"
	if h < 17.0: return "下午"
	if h < 19.0: return "傍晚，天快黑了"
	return "夜晚"


func _event_label(hero: String, eid: String) -> String:
	for ev in defs.get(hero, {}).get("events", []):
		if String(ev.id) == eid:
			return String(ev.get("label", eid))
	for t in topics:
		if String(t.id) == eid:
			return "與人交談"
	return eid


func _nearest_place(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for k in mapd.get("places", {}):
		var dd := Vector2(p.x, p.z).distance_to(_v2(mapd.places[k]))
		if dd < bd:
			bd = dd
			best = k
	return best


func _place_label(pid: String) -> String:
	return String(mapd.get("place_labels", {}).get(pid, pid))


func _score(hero: String, ev: Dictionary, hour: float) -> float:
	var w := float(ev.get("weight", 1.0))
	var hrs: Array = ev.get("hours", [])
	if hrs.size() == 2 and not _in_hours(hour, float(hrs[0]), float(hrs[1])):
		return 0.0
	var mem: Dictionary = memory[hero]
	var last: float = float(mem.last.get(ev.id, -1e9))
	if clock - last < float(ev.get("cooldown", 60.0)):
		return 0.0
	for f in ev.get("need_world", []):
		if not world.has(f): return 0.0
	for f in ev.get("not_world", []):
		if world.has(f): return 0.0
	for f in ev.get("need_know", []):
		if not hero_knows(hero, f): return 0.0
	for f in ev.get("not_know", []):
		if hero_knows(hero, f): return 0.0
	match String(ev.get("kind", "")):
		"object":
			if _pick_object(hero, ev) == "":
				return 0.0
		"social":
			if _pick_partner(hero, ev) == "":
				return 0.0
	# 性格：近期做過的降權（新鮮感），社交依 sociability，責任事依 diligence
	var pers: Dictionary = defs[hero].get("personality", {})
	if (mem.recent as Array).has(ev.id):
		w *= 0.35
	if String(ev.get("kind", "")) == "social":
		w *= lerpf(0.4, 1.6, float(pers.get("sociability", 0.5)))
	if ev.get("tags", []).has("duty"):
		w *= lerpf(0.5, 1.8, float(pers.get("diligence", 0.5)))
	if ev.get("tags", []).has("curious"):
		w *= lerpf(0.5, 1.8, float(pers.get("curiosity", 0.5)))
	return w


func _pick_object(hero: String, ev: Dictionary) -> String:
	var tags: Array = ev.get("object_tags", [])
	var a: Node3D = heroes[hero]
	var best := ""
	var best_d := INF
	var ids := objects.keys()
	ids.shuffle()
	for id in ids:
		var o: Dictionary = objects[id]
		if not o.enabled or String(o.reserved_by) != "" or float(o.hidden_until) >= 0.0:
			continue
		var ok := false
		for t in tags:
			if (o.def.tags as Array).has(t):
				ok = true
		if not ok:
			continue
		if ev.has("object_ids") and not (ev.object_ids as Array).has(id):
			continue
		var d := a.global_position.distance_to(_v3(o.def.stand))
		if ev.get("nearest", false):
			if d < best_d:
				best_d = d
				best = id
		else:
			return id
	return best


func _pick_partner(hero: String, ev: Dictionary) -> String:
	var rel: Dictionary = defs[hero].get("relationships", {})
	var pool: Array = ev.get("partners", rel.keys())
	var best := ""
	var best_w := 0.0
	for other in pool:
		if not _partner_ok(hero, ev, String(other)):
			continue
		var w := float(rel.get(other, {}).get("affinity", 0.5)) * (0.5 + randf())
		if w > best_w:
			best_w = w
			best = other
	return best


func _pick_topic(a: String, b: String, ev: Dictionary) -> Dictionary:
	var pool: Array = []
	var tw := 0.0
	var want: Array = ev.get("topics", [])
	for t in topics:
		var pr: Array = t.get("pair", [])
		if not (pr.size() == 2 and ((pr[0] == a and pr[1] == b) or (pr[0] == b and pr[1] == a))):
			continue
		if want.size() > 0 and not want.has(t.id):
			continue
		if t.has("initiator") and String(t.initiator) != a:
			continue
		var ok := true
		for f in t.get("need_know", []):   # 開口的人（a）要知道
			if not hero_knows(a, f): ok = false
		for f in t.get("need_world", []):
			if not world.has(f): ok = false
		for f in t.get("not_world", []):
			if world.has(f): ok = false
		for f in t.get("listener_not_know", []):
			if hero_knows(b, f): ok = false
		for f in t.get("listener_know", []):
			if not hero_knows(b, f): ok = false
		if not ok:
			continue
		var w := float(t.get("weight", 1.0)) * (3.0 if (memory[a].recent as Array).has(t.id) == false else 0.3)
		pool.append([t, w])
		tw += w
	if pool.is_empty():
		return {}
	var r := randf() * tw
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return pool[0][0]


func _build_plan(hero: String, ev: Dictionary) -> Dictionary:
	var kind := String(ev.get("kind", ""))
	var steps: Array = []
	var plan := {"event": ev, "hero": hero, "object": "", "partner": "", "topic": {}}
	match kind:
		"object":
			var oid := _pick_object(hero, ev)
			if oid == "":
				return {}
			var o: Dictionary = objects[oid]
			o.reserved_by = hero
			plan.object = oid
			if ev.has("say_go"):
				steps.append({"op": "say", "text": _pick_line(ev.say_go)})
			steps.append({"op": "goto", "to": _v3(o.def.stand), "label": oid})
			steps.append({"op": "face", "to": _v3(o.def.face)})
			steps.append({"op": "act", "action": String(ev.get("action", "inspect")), "dur": _rand_range(ev.get("dur", [5, 8])), "say": _pick_line(ev.get("say_act", []))})
			steps.append({"op": "outcome"})
			if ev.has("say_done"):
				steps.append({"op": "say", "text": _pick_line(ev.say_done)})
		"place", "route":
			var places: Array = ev.get("places", [])
			if kind == "place" and places.size() > 1:
				places = [places[randi() % places.size()]]
			for pid in places:
				if not mapd.places.has(pid):
					continue
				steps.append({"op": "goto", "to": _v3(mapd.places[pid]), "label": pid})
				steps.append({"op": "act", "action": String(ev.get("action", "look")), "dur": _rand_range(ev.get("dur", [3, 6])), "say": _pick_line(ev.get("say_act", []))})
			steps.append({"op": "outcome"})
		"social":
			var partner := _pick_partner(hero, ev)
			if partner == "":
				return {}
			var topic := _pick_topic(hero, partner, ev)
			if topic.is_empty():
				return {}
			plan.partner = partner
			plan.topic = topic
			steps.append({"op": "seek", "hero": partner})
			steps.append({"op": "converse"})
			steps.append({"op": "outcome"})
		"home":
			var hd: Dictionary = mapd.homes.get(hero, {})
			if hd.is_empty():
				return {}
			if bool(hd.get("leave", false)):
				steps.append({"op": "goto", "to": _v3(hd.at), "label": "exit"})
				steps.append({"op": "vanish", "dur": _rand_range(ev.get("dur", [240, 420]))})
			else:
				var at := _v3(hd.at)
				if hd.has("link"):
					steps.append({"op": "goto", "to": _v3(hd.link), "label": "home_link"})
					steps.append({"op": "step_to", "to": at})
				else:
					steps.append({"op": "goto", "to": at, "label": "home"})
				steps.append({"op": "face", "to": _v3(hd.get("yaw_to", hd.at))})
				steps.append({"op": "act", "action": String(ev.get("action", hd.get("pose", "idle"))), "dur": _rand_range(ev.get("dur", [20, 40])), "say": _pick_line(ev.get("say_act", []))})
			steps.append({"op": "outcome"})
		_:
			return {}
	plan["steps"] = steps
	return plan


## 測試／除錯：讓 HERO 立刻做指定事件（可指定對象／物件）。回傳是否成功排入
func force_event(hero: String, event_id: String, partner := "", object := "") -> bool:
	if not heroes.has(hero):
		return false
	for ev in defs[hero].get("events", []):
		if String(ev.id) != event_id:
			continue
		var e: Dictionary = ev.duplicate(true)
		if partner != "":
			e["partners"] = [partner]
			e.erase("max_dist")
			e["pair_cooldown"] = 0
		if object != "":
			e["object_ids"] = [object]
		var p := _build_plan(hero, e)
		if p.is_empty():
			_log(hero, event_id, "FORCE_FAIL", {"partner": partner, "object": object})
			return false
		p.event = ev
		heroes[hero].call("force_plan", p)
		return true
	return false


## actor 回報事件狀態
func report(hero: String, plan: Dictionary, state: String, info := {}) -> void:
	var ev: Dictionary = plan.get("event", {})
	var eid := String(ev.get("id", "?"))
	stats[hero][state] = int(stats[hero].get(state, 0)) + 1
	_log(hero, eid, state, info)
	if state in ["Completed", "Failed", "Interrupted"]:
		var mem: Dictionary = memory[hero]
		mem.last[eid] = clock if state == "Completed" else clock - float(ev.get("cooldown", 60.0)) + float(ev.get("retry", 20.0))
		(mem.recent as Array).push_front(eid)
		if (mem.recent as Array).size() > 4:
			(mem.recent as Array).pop_back()
		release(hero, plan)


func release(hero: String, plan: Dictionary) -> void:
	var oid := String(plan.get("object", ""))
	if oid != "" and objects.has(oid) and String(objects[oid].reserved_by) == hero:
		objects[oid].reserved_by = ""
	# 只收掉「這個事件自己發起的」交談；被找的一方結束手上事件時，交談預約照舊（它會閒下來等對方）
	if String(plan.get("event", {}).get("kind", "")) == "social":
		for s in sessions.duplicate():
			if s.a == hero:
				end_session(s, "Interrupted" if s.state != "done" else "Completed", "release:" + hero)


## outcome 步驟：套用事件結果（設事實、教傳聞、藏物件、毛玉逃走…）
func apply_outcome(hero: String, plan: Dictionary) -> void:
	var ev: Dictionary = plan.get("event", {})
	var out: Dictionary = ev.get("outcome", {})
	var oid := String(plan.get("object", ""))
	if oid != "" and objects.has(oid):
		var o: Dictionary = objects[oid]
		if bool(o.def.get("hide_on_use", false)) and o.node != null:
			(o.node as Node3D).visible = false
			o.hidden_until = clock + float(o.def.get("regrow", 300))
			_log(hero, String(ev.id), "OBJECT_USED", {"object": oid, "hidden": true})
	for f in out.get("set_world", {}):
		set_world(f, float(out.set_world[f]), hero)
	for f in out.get("clear_world", []):
		_clear_world(f, hero)
	for f in out.get("learn", []):
		learn(hero, f)
	for f in out.get("forget", []):
		(knows[hero] as Dictionary).erase(f)
	if bool(out.get("kedama_flee", false)):
		kedama_flee()


# ─────────────────────────────── 雙人同步交談 ───────────────────────────────

## 發起者抵達前就建立 session：預約雙方，被找的人原地等候並在對方靠近時轉身
func open_session(a: String, b: String, topic: Dictionary) -> Dictionary:
	if not heroes.has(b) or not bool(heroes[b].call("can_accept_social", a)):
		return {}
	var s := {"a": a, "b": b, "topic": topic, "state": "approach", "i": -1, "t": 0.0, "line_left": 0.0, "wait": 0.0, "paused": 0.0}
	# 先讓對方收手（它結束手上事件時會 release，此時 session 還不在清單裡，不會被誤關），再登記
	heroes[b].call("hold_for_session", s)
	sessions.append(s)
	_prefetch_voice(s)
	_log(a, String(topic.get("id", "")), "SESSION_OPEN", {"with": b})
	return s


## 發起者到位（≤ talk_dist、互相面對）後呼叫
func session_arrived(s: Dictionary) -> void:
	if s.state == "approach":
		s.state = "talk"
		s.i = -1
		s.line_left = 0.4
		_log(s.a, String(s.topic.get("id", "")), "SESSION_TALK", {"with": s.b, "dist": snappedf(_dist(s.a, s.b), 0.01)})


func _tick_session(s: Dictionary, ld: float) -> void:
	var A: Node3D = heroes.get(s.a)
	var B: Node3D = heroes.get(s.b)
	if A == null or B == null or not A.is_inside_tree() or not B.is_inside_tree() or not A.visible or not B.visible:
		end_session(s, "Failed", "participant_gone")
		return
	s.t += ld
	if s.state == "approach":
		if float(s.rt) > 300.0:   # 實際秒數（跨村可能要走 150 m 以上）
			end_session(s, "Failed", "approach_timeout")
		return
	if s.state != "talk":
		return
	var d := _dist(s.a, s.b)
	if d > 3.2:
		end_session(s, "Interrupted", "too_far:%.2f" % d)
		return
	if float(s.paused) > 0.0:
		return
	s.line_left -= ld
	if s.line_left > 0.0:
		return
	var lines: Array = s.topic.get("lines", [])
	var ni: int = s.i + 1
	if ni >= lines.size():
		s.state = "done"
		_apply_topic(s)
		end_session(s, "Completed", "done")
		return
	var ln: Array = lines[ni]
	var who := String(ln[0])
	var spk: String = s.a if who == "a" or who == s.a else s.b
	var lis: String = s.b if spk == s.a else s.a
	var text := String(ln[1])
	# 語音：有快取就用；正在生成就最多等 3 秒（字幕不先跳）；沒有就只顯示字幕
	var vtext := _voice_text(s.topic, ni)
	var vclip: Dictionary = {}
	if voice != null and vtext != "":
		vclip = voice.call("lookup", spk, vtext)
		if vclip.is_empty() and bool(voice.call("is_pending", spk, vtext)) and float(s.get("vwait", 0.0)) < 3.0:
			s["vwait"] = float(s.get("vwait", 0.0)) + ld
			s.line_left = 0.05
			return
	s["vwait"] = 0.0
	s.i = ni
	var dur := clampf(0.13 * text.length() + 1.4, 2.4, 6.5)
	if not vclip.is_empty():
		dur = float(vclip.dur) + 0.45
	s.line_left = dur
	heroes[spk].call("session_speak", text, dur, heroes[lis], String(ln[2]) if ln.size() > 2 else "", vclip)
	heroes[lis].call("session_listen", heroes[spk])
	hero_said.emit(spk, text, lis)
	# sub＝目前語言的原文字幕（沒有該語言語音時照樣提供，例如英文字幕）；voice＝實際播出的語音台詞
	_log(spk, String(s.topic.get("id", "")), "SAY", {"to": lis, "text": text, "sub": vtext, "voice": vtext if not vclip.is_empty() else "", "voice_s": snappedf(float(vclip.get("dur", 0.0)), 0.01)})


func _voice_text(topic: Dictionary, i: int) -> String:
	if voice == null:
		return ""
	var arr: Array = topic.get("voice", {}).get(String(voice.get("lang")), [])
	return String(arr[i]) if i < arr.size() else ""


## 交談一開就請語音系統先生成（快取沒有的才會真的送引擎）
func _prefetch_voice(s: Dictionary) -> void:
	if voice == null:
		return
	var lines: Array = s.topic.get("lines", [])
	for i in lines.size():
		var who := String(lines[i][0])
		var spk: String = s.a if who == "a" or who == s.a else s.b
		var vt := _voice_text(s.topic, i)
		if vt != "":
			voice.call("prefetch", spk, vt)


func _apply_topic(s: Dictionary) -> void:
	var out: Dictionary = s.topic.get("outcome", {})
	for f in out.get("teach", []):     # 開口者知道的事傳給聽者（傳聞擴散）
		learn(s.b, f)
		learn(s.a, f)
	for f in out.get("set_world", {}):
		set_world(f, float(out.set_world[f]), s.a)
	for f in out.get("clear_world", []):
		_clear_world(f, s.a)
	if bool(out.get("kedama_flee", false)):
		kedama_flee()
	for h in [s.a, s.b]:
		var mem: Dictionary = memory[h]
		mem.pair[s.b if h == s.a else s.a] = clock
		(mem.recent as Array).push_front(String(s.topic.get("id", "")))


func end_session(s: Dictionary, state: String, why: String) -> void:
	if not sessions.has(s):
		return
	sessions.erase(s)
	_log(s.a, String(s.topic.get("id", "")), "SESSION_" + state.to_upper(), {"with": s.b, "why": why})
	for h in [s.a, s.b]:
		if heroes.has(h):
			heroes[h].call("session_ended", s, state)


func session_of(hero: String) -> Dictionary:
	for s in sessions:
		if s.a == hero or s.b == hero:
			return s
	return {}


## 玩家打擾正在交談的雙方：暫停；停太久就散場
func session_player_pause(s: Dictionary, on: bool) -> void:
	s.paused = 1.0 if on else 0.0


# ─────────────────────────────── 尋路（烘焙可走格） ───────────────────────────────

func _load_grid() -> void:
	var gd: Dictionary = mapd.get("grid", {})
	if gd.is_empty():
		return
	gx0 = float(gd.origin[0])
	gz0 = float(gd.origin[1])
	gcell = float(gd.cell)
	gw = int(gd.w)
	gh = int(gd.h)
	var f := FileAccess.open_compressed(String(gd.file), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("[NpcLife] 讀不到可走格 %s" % gd.file)
		return
	gcode = f.get_buffer(gw * gh)
	gheight = f.get_buffer(gw * gh * 2)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, gw, gh)
	grid.cell_size = Vector2(gcell, gcell)
	grid.offset = Vector2(gx0 + gcell * 0.5, gz0 + gcell * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	const W8 := [0.0, 1.0, 1.25, 1.8, 3.0]
	for j in gh:
		for i in gw:
			var c := gcode[j * gw + i]
			if c == 0:
				grid.set_point_solid(Vector2i(i, j), true)
			elif c != 1:
				grid.set_point_weight_scale(Vector2i(i, j), W8[c])


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - gx0) / gcell), floori((p.z - gz0) / gcell))


func walkable(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh and gcode[c.y * gw + c.x] != 0


func _nearest_walkable(c: Vector2i, rmax := 6) -> Vector2i:
	if walkable(c):
		return c
	for r in range(1, rmax + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := c + Vector2i(di, dj)
				if walkable(q):
					return q
	return Vector2i(-1, -1)


## 地面高（烘焙值，雙線性；不可走的鄰格不參與）。fallback＝傳入值
func ground_y(p: Vector2, fallback: float) -> float:
	var fx := (p.x - gx0) / gcell - 0.5
	var fz := (p.y - gz0) / gcell - 0.5
	var i0 := floori(fx)
	var j0 := floori(fz)
	var tx := fx - i0
	var tz := fz - j0
	var acc := 0.0
	var wsum := 0.0
	for dj in 2:
		for di in 2:
			var c := Vector2i(i0 + di, j0 + dj)
			if not walkable(c):
				continue
			var w := (tx if di == 1 else 1.0 - tx) * (tz if dj == 1 else 1.0 - tz)
			acc += w * gheight.decode_s16((c.y * gw + c.x) * 2) / 100.0
			wsum += w
	if wsum < 1e-4:
		return fallback
	return acc / wsum


## 尋路：回傳世界座標折線（含起點之後的各點；y＝地面）。找不到回空陣列。
## 同步版（工具／測試用）。遊戲中 HERO 一律走 request_path（背景執行緒，主執行緒不卡）
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _path_busy:
		return PackedVector3Array()   # 背景正在用 grid（AStarGrid2D 查詢不可並行）
	var t_us := Time.get_ticks_usec()
	var out := _find_path(from, to)
	_path_stat((Time.get_ticks_usec() - t_us) / 1000.0)
	return out


## 非同步尋路：排隊、一次一個背景工作（AStarGrid2D 查詢會改內部暫存，不能並行），結果用 cb.call(path) 送回主執行緒
var _path_q: Array = []
var _path_busy := false
var _path_task := -1


## 離開場景樹（換圖／關遊戲）前等背景尋路做完，避免執行緒碰到已釋放的資料
func _exit_tree() -> void:
	_path_q.clear()
	if _path_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_path_task)
		_path_task = -1


func request_path(from: Vector3, to: Vector3, cb: Callable) -> void:
	_path_q.append({"from": from, "to": to, "cb": cb})
	_pump_path()


func _pump_path() -> void:
	if _path_busy or _path_q.is_empty():
		return
	_path_busy = true
	var job: Dictionary = _path_q.pop_front()
	_path_task = WorkerThreadPool.add_task(func() -> void:
		var t_us := Time.get_ticks_usec()
		var p := _find_path(job.from, job.to)
		_path_done.call_deferred(job, p, (Time.get_ticks_usec() - t_us) / 1000.0))


func _path_done(job: Dictionary, p: PackedVector3Array, ms: float) -> void:
	if _path_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_path_task)   # 已結束，回收 task id
		_path_task = -1
	_path_busy = false
	_path_stat(ms)
	var cb: Callable = job.cb
	if cb.is_valid():
		cb.call(p)
	_pump_path()


func _path_stat(ms: float) -> void:
	path_stats.n += 1
	path_stats.total_ms += ms
	path_stats.max_ms = maxf(path_stats.max_ms, ms)


func _find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if grid == null:
		return out
	var c0 := _nearest_walkable(cell_of(from))
	var c1 := _nearest_walkable(cell_of(to))
	if c0.x < 0 or c1.x < 0:
		return out
	var ids := grid.get_id_path(c0, c1)
	if ids.is_empty():
		return out
	var pts: Array[Vector2] = []
	for c in ids:
		pts.append(Vector2(gx0 + (c.x + 0.5) * gcell, gz0 + (c.y + 0.5) * gcell))
	# 終點用精確座標（在可走格內）
	if walkable(cell_of(to)):
		pts[pts.size() - 1] = Vector2(to.x, to.z)
	# 拉直：從目前點往後找最遠的可直視點（每段 ≤ 10 m）
	var sm: Array[Vector2] = [Vector2(from.x, from.z)]
	var k := 0
	while k < pts.size() - 1:
		var far := k + 1
		var j := pts.size() - 1
		while j > k + 1:
			if sm[sm.size() - 1].distance_to(pts[j]) <= 10.0 and _los(sm[sm.size() - 1], pts[j]):
				far = j
				break
			j -= 1
		sm.append(pts[far])
		k = far
	for i in range(1, sm.size()):
		out.append(Vector3(sm[i].x, ground_y(sm[i], from.y), sm[i].y))
	return out


func _los(a: Vector2, b: Vector2) -> bool:
	var L := a.distance_to(b)
	var n := ceili(L / (gcell * 0.4))
	var prev_h := INF
	for t in range(1, n + 1):
		var p := a.lerp(b, float(t) / maxf(n, 1))
		var c := Vector2i(floori((p.x - gx0) / gcell), floori((p.y - gz0) / gcell))
		if not walkable(c):
			return false
		# 「貼近障礙」格只允許出現在線段兩端 0.75 m 內（站位常貼著物件），中段不可切牆角
		if gcode[c.y * gw + c.x] == 4 and p.distance_to(a) > 0.75 and p.distance_to(b) > 0.75:
			return false
		var h := gheight.decode_s16((c.y * gw + c.x) * 2) / 100.0
		if prev_h != INF and absf(h - prev_h) > 0.45:
			return false
		prev_h = h
	return true


## 在 target 周圍找一個可走、離 from 最近的交談站位（距 target 約 dist）
func approach_point(target: Vector3, from: Vector3, dist := 1.25) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for k in 12:
		var ang := TAU * k / 12.0
		var p := target + Vector3(sin(ang), 0, cos(ang)) * dist
		if not walkable(cell_of(p)):
			continue
		var d := p.distance_to(from)
		if d < best_d:
			best_d = d
			best = p
	if best == Vector3.INF:
		return target
	best.y = ground_y(Vector2(best.x, best.z), target.y)
	return best


# ─────────────────────────────── 工具 ───────────────────────────────

func _hour() -> float:
	var wt := get_node_or_null("/root/WorldTimeManager")
	return float(wt.get("hour")) if wt != null else 10.0


static func _in_hours(h: float, a: float, b: float) -> bool:
	return (h >= a and h < b) if a <= b else (h >= a or h < b)


func _rand_range(r: Variant) -> float:
	if r is Array and (r as Array).size() == 2:
		return randf_range(float(r[0]), float(r[1]))
	return float(r)


func _pick_line(arr: Variant) -> String:
	if arr is Array and not (arr as Array).is_empty():
		return String(arr[randi() % (arr as Array).size()])
	if arr is String:
		return arr
	return ""


func _dist(a: String, b: String) -> float:
	var A: Node3D = heroes[a]
	var B: Node3D = heroes[b]
	var d := A.global_position - B.global_position
	d.y = 0.0
	return d.length()


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _v3(a: Array) -> Vector3:
	var p := _v2(a)
	return Vector3(p.x, ground_y(p, 0.0), p.y)


func _json(p: String) -> Dictionary:
	var t := FileAccess.get_file_as_string(p)
	if t.is_empty():
		push_error("[NpcLife] 讀不到 %s" % p)
		return {}
	var v: Variant = JSON.parse_string(t)
	return v if v is Dictionary else {}


func _log(hero: String, ev: String, state: String, info: Dictionary) -> void:
	history.append([snappedf(clock, 0.01), hero, ev, state, info])
	if history.size() > 4000:
		history.pop_front()
	event_state.emit(hero, ev, state, info)
	if verbose:
		print("[LIFE] t=%.1f %s %s %s %s" % [clock, hero, ev, state, JSON.stringify(info) if not info.is_empty() else ""])
