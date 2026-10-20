extends SceneTree
## JEV Decision Provider 對照測試（小型測試場景：director＋5 名 HERO 替身，不載村莊）
## godot --headless --path godot -s res://tools/npc_life/jev_decision_bench.gd -- [--jev] [--reps=3] [--builtin=20] [--failures]
##   不帶 --jev：只跑原本決策＋mock（不連網、不花錢）
##   --jev：另外用 TypeSafe Jev（金鑰只從環境變數 TYPESAFE_API_KEY 讀；沒有就記為 no_key、不假裝測過）
## 量：決策延遲、選擇是否在「合理集合」內、API 呼叫次數、輸入 token、同情境重複一致性、失敗時退回原決策。

const STUB := preload("res://tools/npc_life/_bench_stub_hero.gd")

var dir: Node
var stubs := {}
var use_jev := false
var reps := 3
var n_builtin := 20
var do_fail := false
var report: Array = []
var fails := 0

## 情境：魔理沙的位置／時間／所知／旁人 → 合理選項集合（option id；社交為 event@對象）
var SCENARIOS := [
	{"id": "S1_morning_kirisame", "desc": "早上 07:30 在霧雨道具店前，後院蘑菇都在", "hour": 7.5, "pos": [238.5, 60.0],
		"accept": ["marisa_mushroom", "marisa_herb"]},
	{"id": "S2_market_after_harvest", "desc": "11:00 在市集北口，蘑菇剛採光、藥草也採過", "hour": 11.0, "pos": [244.0, -26.0], "harvested": true, "recent": ["marisa_mushroom", "marisa_herb"],
		"accept": ["marisa_market"]},
	{"id": "S3_keine_nearby", "desc": "10:00 霧雨店前，剛採完蘑菇也逛過市集，慧音就在 3 m 外閒著", "hour": 10.0, "pos": [238.5, 60.0], "harvested": true, "recent": ["marisa_mushroom", "marisa_market"], "cool": ["marisa_market", "marisa_mushroom", "marisa_herb"],
		"others": {"keine": [240.5, 62.0]}, "accept": ["marisa_chat@keine"]},
	{"id": "S4_has_mushroom_bench", "desc": "13:00 帶著剛採的蘑菇，在主街長椅旁", "hour": 13.0, "pos": [244.5, 36.0], "know": ["marisa_has_mushroom"], "recent": ["marisa_mushroom"], "cool": ["marisa_mushroom"],
		"accept": ["marisa_study"]},
	{"id": "S5_evening", "desc": "18:40 天快黑，在村口附近", "hour": 18.67, "pos": [236.0, 98.0],
		"accept": ["marisa_leave"]},
	{"id": "S6_reimu_nearby", "desc": "09:00 村口，靈夢就在 2 m 外閒著，蘑菇剛採過", "hour": 9.0, "pos": [236.0, 98.0], "harvested": true, "recent": ["marisa_mushroom"], "cool": ["marisa_mushroom", "marisa_herb"],
		"others": {"reimu": [237.8, 99.0]}, "accept": ["marisa_chat@reimu"]},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	use_jev = args.has("--jev")
	do_fail = args.has("--failures")
	for a in args:
		if a.begins_with("--reps="): reps = int(a.substr(7))
		if a.begins_with("--builtin="): n_builtin = int(a.substr(10))
	var sc := Node3D.new()
	sc.name = "BenchScene"
	root.add_child(sc)
	for h in ["marisa", "keine", "kosuzu", "akyuu", "reimu"]:
		var s: Node3D = STUB.new()
		s.name = "Stub_" + h
		s.hero_id = h
		sc.add_child(s)
		stubs[h] = s
	dir = (load("res://systems/npc_life/npc_life_director.gd") as GDScript).new()
	dir.name = "NpcLife"
	dir.set("verbose", false)
	sc.add_child(dir)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	# 替身場景沒有村莊節點：物件改為有效（只測決策）
	for id in dir.get("objects"):
		var o: Dictionary = dir.get("objects")[id]
		o.enabled = not bool(o.def.get("dynamic", false))
	_secret_guard()
	await _bench("builtin")
	await _bench("mock")
	if use_jev:
		await _bench("jev")
	else:
		_line("JEV 雲端：未執行（沒有 --jev 參數）")
	if do_fail:
		await _failures()
	_summary()
	quit(1 if fails > 0 else 0)


func _setup(s: Dictionary) -> void:
	var wt := root.get_node_or_null("/root/WorldTimeManager")
	if wt != null:
		wt.set("hour", float(s.hour))
	var dn := root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
	# 其他 HERO 預設在各自據點、遠處（不在附近）
	var home := {"keine": [201.0, 30.0], "kosuzu": [253.7, -5.4], "akyuu": [395.0, -45.7], "reimu": [222.6, 204.0], "marisa": s.pos}
	for h in stubs:
		var p: Array = s.get("others", {}).get(h, home[h])
		(stubs[h] as Node3D).global_position = Vector3(float(p[0]), dir.call("ground_y", Vector2(float(p[0]), float(p[1])), 0.5), float(p[1]))
		(stubs[h] as Node3D).visible = not (h == "reimu" and not s.get("others", {}).has("reimu"))
	var mem: Dictionary = dir.get("memory")
	var clk := float(dir.get("clock"))
	for h in mem:
		mem[h].last = {}
		mem[h].recent = []
		mem[h].pair = {}
	for e in s.get("recent", []):
		(mem.marisa.recent as Array).append(e)
	for e in s.get("cool", []):
		mem.marisa.last[e] = clk
	var kn: Dictionary = dir.get("knows")
	for h in kn:
		(kn[h] as Dictionary).clear()
	for f in s.get("know", []):
		kn.marisa[f] = clk + 9999.0
	(dir.get("world") as Dictionary).clear()
	for id in dir.get("objects"):
		var o: Dictionary = dir.get("objects")[id]
		o.reserved_by = ""
		o.hidden_until = clk + 9999.0 if (bool(s.get("harvested", false)) and (o.def.tags as Array).has("material")) else -1.0


func _decide(provider: String) -> Dictionary:
	dir.set("jev_heroes", PackedStringArray(["marisa"]) if provider != "builtin" else PackedStringArray())
	var t0 := Time.get_ticks_usec()
	var mark := (dir.get("history") as Array).size()
	var p: Dictionary = {}
	var polls := 0
	while true:
		p = dir.call("request_plan", "marisa")
		polls += 1
		if not p.has("pending"):
			break
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var info := {}
	for i in range(mark, (dir.get("history") as Array).size()):
		var r: Array = dir.get("history")[i]
		if r[1] == "marisa" and r[3] == "DECIDE":
			info = r[4]
	var opt := ""
	if not p.is_empty():
		opt = String(p.event.id)
		if String(p.get("partner", "")) != "":
			opt += "@" + String(p.partner)
		dir.call("release", "marisa", p)
		if String(p.get("object", "")) != "":
			dir.get("objects")[p.object].reserved_by = ""
	return {"opt": opt, "ms": ms, "by": String(info.get("by", "")), "info": info, "polls": polls}


func _bench(provider: String) -> void:
	if provider != "builtin":
		dir.set("jev_mode", "mock" if provider == "mock" else "jev")
		if dir.get("jev") != null:
			dir.get("jev").queue_free()
			dir.set("jev", null)
			await process_frame
		dir.set("jev_heroes", PackedStringArray(["marisa"]))
		dir.call("_setup_jev")
		if provider == "jev" and not bool(dir.get("jev").call("available")):
			_line("JEV 雲端：環境變數沒有 TYPESAFE_API_KEY → 未測（不假裝已測），只完成 mock／本機驗證")
			return
	var n := n_builtin if provider == "builtin" else (reps if provider == "jev" else 5)
	var tot_hit := 0
	var tot := 0
	var lat: Array = []
	var confs: Array = []
	var stable := 0
	_line("── %s（每情境 %d 次）──" % [provider, n])
	for s in SCENARIOS:
		var picks := {}
		var hit := 0
		for k in n:
			_setup(s)
			var r: Dictionary = await _decide(provider)
			picks[r.opt] = int(picks.get(r.opt, 0)) + 1
			if (s.accept as Array).has(r.opt):
				hit += 1
			if provider != "builtin":
				if r.by == "jev":
					lat.append(float(r.info.get("ms", r.ms)))
					confs.append(float(r.info.get("conf", 0.0)))
				else:
					_line("   ！%s 第 %d 次未用 %s：by=%s %s" % [s.id, k + 1, provider, r.by, r.info])
		tot_hit += hit
		tot += n
		var top := 0
		for k2 in picks: top = maxi(top, int(picks[k2]))
		if top == n: stable += 1
		_line("  %s %s：合理 %d/%d　分布 %s" % [s.id, s.desc, hit, n, picks])
	var st: Dictionary = dir.get("jev").get("stats") if provider != "builtin" else {}
	lat.sort()
	var p50: float = lat[lat.size() / 2] if not lat.is_empty() else -1.0
	var p95: float = lat[mini(lat.size() - 1, int(lat.size() * 0.95))] if not lat.is_empty() else -1.0
	var row := {"provider": provider, "accept_rate": snappedf(float(tot_hit) / maxf(tot, 1), 0.001), "hits": "%d/%d" % [tot_hit, tot], "stable_scenarios": "%d/%d" % [stable, SCENARIOS.size()]}
	if provider != "builtin":
		var cs := 0.0
		for c in confs: cs += c
		row["conf_mean"] = snappedf(cs / maxf(confs.size(), 1), 0.001)
		row.merge({"calls": st.calls, "ok": st.ok, "fail": st.fail, "errors": st.errors, "input_tokens": st.input_tokens, "lat_p50_ms": snappedf(p50, 0.1), "lat_p95_ms": snappedf(p95, 0.1)})
	report.append(row)
	_line("  → %s" % JSON.stringify(row))


## 失敗情境：沒有金鑰、壞金鑰、連不上／逾時 → 必須在期限內退回原本決策並產出合法 plan
func _failures() -> void:
	_line("── 失敗退回測試 ──")
	var saved := OS.get_environment("TYPESAFE_API_KEY")
	var saved2 := OS.get_environment("JEV_API_KEY")
	var cases := [
		{"name": "mock 永不回應（逾時）", "mode": "mock", "mock_fail": "timeout", "timeout": 1.0},
		{"name": "mock 立刻錯誤", "mode": "mock", "mock_fail": "error", "timeout": 1.0},
		{"name": "沒有金鑰", "mode": "jev", "env": "", "timeout": 2.0},
	]
	if use_jev and saved != "":
		cases.append({"name": "連不上（不可路由位址）", "mode": "jev", "env": "keep", "url": "https://10.255.255.1", "timeout": 1.5})
		cases.append({"name": "無效金鑰（401）", "mode": "jev", "env": "invalid-key-for-test", "timeout": 4.0})
	for c in cases:
		if dir.get("jev") != null:
			dir.get("jev").queue_free()
			dir.set("jev", null)
			await process_frame
		if c.has("env"):
			var v: String = saved if c.env == "keep" else String(c.env)
			OS.set_environment("TYPESAFE_API_KEY", v)
			OS.set_environment("JEV_API_KEY", "" if c.env != "keep" else saved2)
		if c.has("url"):
			ProjectSettings.set_setting("jev/endpoint/base_url", c.url)
		dir.set("jev_mode", c.mode)
		dir.set("jev_timeout", float(c.timeout))
		dir.set("jev_heroes", PackedStringArray(["marisa"]))
		dir.call("_setup_jev")
		dir.get("jev").set("mock_fail", c.get("mock_fail", "none"))
		_setup(SCENARIOS[0])
		var r: Dictionary = await _decide("fail")
		var ok: bool = r.opt != "" and r.by == "builtin_after_fallback" and r.ms <= float(c.timeout) * 1000.0 + 600.0
		if c.name == "沒有金鑰":
			ok = r.opt != "" and r.ms < 100.0     # 沒金鑰時 provider 視為不可用 → 直接原本決策
		if not ok:
			fails += 1
		_line("  [%s] %s → 選 %s，by=%s，%.0f ms %s" % ["PASS" if ok else "FAIL", c.name, r.opt, r.by, r.ms, r.info])
		ProjectSettings.set_setting("jev/endpoint/base_url", "https://api.typesafe.ai")
	OS.set_environment("TYPESAFE_API_KEY", saved)
	OS.set_environment("JEV_API_KEY", saved2)
	dir.set("jev_timeout", 3.0)
	# 反應事件（priority ≥ 5）不送 JEV
	if dir.get("jev") != null:
		dir.get("jev").queue_free()
		dir.set("jev", null)
		await process_frame
	dir.set("jev_mode", "mock")
	dir.set("jev_heroes", PackedStringArray(["marisa"]))
	dir.call("_setup_jev")
	_setup(SCENARIOS[0])
	(dir.get("world") as Dictionary)["anomaly_south_forest"] = {"until": -1.0, "source": "bench"}
	dir.get("knows").marisa["anomaly_south_forest"] = float(dir.get("clock")) + 9999.0
	dir.get("objects")["anomaly_spot"].enabled = true
	var calls0: int = dir.get("jev").get("stats").calls
	var r2: Dictionary = await _decide("mock")
	var ok2: bool = r2.opt == "marisa_investigate" and r2.by == "priority" and int(dir.get("jev").get("stats").calls) == calls0
	if not ok2: fails += 1
	_line("  [%s] 反應事件優先權保留：選 %s，by=%s，JEV 呼叫 +%d" % ["PASS" if ok2 else "FAIL", r2.opt, r2.by, int(dir.get("jev").get("stats").calls) - calls0])


func _secret_guard() -> void:
	var pg := FileAccess.get_file_as_string("res://project.godot")
	var bad := pg.find("jev/config/api_key") >= 0
	if bad: fails += 1
	_line("[%s] project.godot 沒有 jev/config/api_key 設定" % ["FAIL" if bad else "PASS"])


func _summary() -> void:
	_line("── 總表 ──")
	for r in report:
		_line(JSON.stringify(r))


func _line(s: String) -> void:
	print("[BENCH] " + s)
