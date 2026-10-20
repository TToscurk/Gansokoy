extends SceneTree
## JEV 實機試跑：正式村莊（main.tscn --map=village_v2），只有魔理沙改用 JEV 決策，其他 HERO 照舊。
## godot --headless --path godot -s res://tools/npc_life/jev_live_run.gd -- --map=village_v2 [--mode=jev|mock] [--secs=300] [--ts=2]
##   三段：前 60% 正常；60–80% 端點改成連不上（應逾時退回）；最後 20% 拿掉金鑰（應直接用原本決策）。
##   檢查：JEV 選的事件是否由既有系統執行（Traveling → Interacting／SESSION_TALK → Completed），NPC 有沒有停擺。

var main: Node
var dir: Node
var mode := "jev"
var secs := 300.0
var ts := 2.0
var log_all: Array = []
var t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="): mode = a.substr(7)
		if a.begins_with("--secs="): secs = float(a.substr(7))
		if a.begins_with("--ts="): ts = float(a.substr(5))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	while true:
		dir = root.get_tree().get_first_node_in_group("npc_life_director")
		if dir != null and bool(dir.get("_ready_done")):
			break
		await process_frame
	dir.set("jev_mode", mode)
	dir.set("jev_heroes", PackedStringArray(["marisa"]))
	dir.call("_setup_jev")
	dir.set("time_scale", ts)
	dir.connect("event_state", func(h, e, s, i): log_all.append([Time.get_ticks_msec() - t0, h, e, s, i]))
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	pl.global_position = Vector3(330, 0.6, 150)   # 玩家停遠處，不干擾
	var saved := OS.get_environment("TYPESAFE_API_KEY")
	t0 = Time.get_ticks_msec()
	var phase := 0
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await physics_frame
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if phase == 0 and el > secs * 0.6:
			phase = 1
			ProjectSettings.set_setting("jev/endpoint/base_url", "https://10.255.255.1")
			print("[LIVE] %.0fs 階段 2：端點改成連不上" % el)
		elif phase == 1 and el > secs * 0.8:
			phase = 2
			ProjectSettings.set_setting("jev/endpoint/base_url", "https://api.typesafe.ai")
			OS.set_environment("TYPESAFE_API_KEY", "")
			print("[LIVE] %.0fs 階段 3：拿掉金鑰" % el)
	OS.set_environment("TYPESAFE_API_KEY", saved)
	_report()
	quit(0)


func _report() -> void:
	var decided: Array = []
	for i in log_all.size():
		var r: Array = log_all[i]
		if r[1] == "marisa" and r[3] == "DECIDE":
			decided.append(i)
	var by := {}
	var executed := 0
	var jev_n := 0
	for i in decided:
		var r: Array = log_all[i]
		var b := String(r[4].get("by", ""))
		by[b] = int(by.get(b, 0)) + 1
		var line := "[LIVE] %6.1fs DECIDE by=%s 事件=%s %s" % [r[0] / 1000.0, b, r[2], JSON.stringify(r[4])]
		if r[2] == "" or b == "fallback":
			print(line)
			continue
		# 這個決策之後，既有系統有沒有把它執行到互動／交談／完成
		var states: Array = []
		for k in range(i + 1, log_all.size()):
			var q: Array = log_all[k]
			if q[1] == "marisa" and q[3] == "DECIDE":
				break
			if q[1] == "marisa" and q[3] in ["Reserved", "Traveling", "Interacting", "SESSION_TALK", "Completed", "Failed", "Interrupted", "PAUSED", "RESUMED"]:
				if not states.has(q[3]): states.append(q[3])
		var ok := states.has("Interacting") or states.has("SESSION_TALK") or states.has("Completed")
		if b == "jev":
			jev_n += 1
			if ok: executed += 1
		print(line + "  → " + "/".join(states))
	var st: Dictionary = dir.get("jev").get("stats")
	print("[LIVE] 決策來源 %s" % JSON.stringify(by))
	print("[LIVE] JEV 選中並由既有系統執行到互動／交談／完成：%d/%d" % [executed, jev_n])
	print("[LIVE] provider stats %s" % JSON.stringify(st))
	var others := {}
	for r in log_all:
		if r[1] != "marisa" and r[3] == "Completed":
			others[r[1]] = int(others.get(r[1], 0)) + 1
	print("[LIVE] 其他 HERO（原本決策）完成事件數 %s" % JSON.stringify(others))
	print("[LIVE] 魔理沙最後狀態 %s" % dir.get("heroes")["marisa"].call("life_state"))
