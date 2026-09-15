extends SceneTree
## 量測 slice.tscn（人間之里）載入耗時，拆解到「哪個子場景/資源類別」花最久。
##
## 做法：headless load()+instantiate() 對整個場景計時是一個數字，看不出熱點。
## 這裡改用兩層量測：
##   1. 對場景內第一層具名子節點（鈴奈庵、霧雨店、灌木叢、路燈街牌...）分別
##      量測它們對應的 .glb/.tscn 外部資源獨立 load() 耗時——外部資源快取一次
##      清空重載，才能看出「這個資產本身」的解碼/匯入成本。
##   2. 對整個 slice.tscn 做一次 load() + instantiate() 的總表，交叉核對。
##
## Run: godot --headless --path godot --script tools/audit_load_time.gd

const SCENE_PATH := "res://maps/slice/slice.tscn"

func _init() -> void:
	var t_total0 := Time.get_ticks_usec()
	var packed: PackedScene = load(SCENE_PATH)
	var t_load := Time.get_ticks_usec() - t_total0

	var t_inst0 := Time.get_ticks_usec()
	var root: Node3D = packed.instantiate()
	var t_inst := Time.get_ticks_usec() - t_inst0

	print("=== slice.tscn（人間之里）總體載入耗時 ===")
	print("  load()（讀檔+解析 .tscn 文本+解 ext_resource）：%.1f ms" % (t_load / 1000.0))
	print("  instantiate()（建節點樹+套用屬性）：%.1f ms" % (t_inst / 1000.0))
	print("  合計：%.1f ms\n" % ((t_load + t_inst) / 1000.0))

	# 找出 ext_resource 清單，逐一單獨 load() 計時（清 ResourceLoader 快取沒有公開
	# API，這裡改用「第一次全新載入」的觀察：把場景整個 free 後，同一份資源
	# 若被 RAM 快取，第二次會非常快——藉此區分「磁碟/解碼成本」vs「純結構耗時」。
	var res_list := _collect_ext_resources(SCENE_PATH)
	print("=== 場景引用的外部資源，逐一單獨 load() 計時（前 40 慢）===\n")
	var rows: Array = []
	for path in res_list:
		var t0 := Time.get_ticks_usec()
		var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var dt := Time.get_ticks_usec() - t0
		rows.append({"path": path, "ms": dt / 1000.0})

	rows.sort_custom(func(a, b): return a["ms"] > b["ms"])
	print("%-70s %10s" % ["資源", "ms"])
	for i in min(40, rows.size()):
		var r = rows[i]
		print("%-70s %10.2f" % [_short(r["path"]), r["ms"]])

	var total_ms := 0.0
	for r in rows:
		total_ms += r["ms"]
	print("\n全部 %d 個外部資源、單獨載入耗時總和：%.1f ms（會比整場景 load() 慢，因為場景內同一資源只解一次、這裡逐一重解且忽略快取）" % [rows.size(), total_ms])

	root.free()
	quit()


func _collect_ext_resources(scene_path: String) -> Array:
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	var seen := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("[ext_resource"):
			var m := RegEx.new()
			m.compile("path=\"(res://[^\"]+)\"")
			var res := m.search(line)
			if res != null:
				var p := res.get_string(1)
				if not seen.has(p):
					seen[p] = true
					out.append(p)
	f.close()
	return out


func _short(p: String) -> String:
	var s := p
	if s.length() > 70:
		s = "..." + s.substr(s.length() - 67)
	return s
