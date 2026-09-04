extends SceneTree
## F5 載入慢的成因診斷 —— 只量「載入」，不量 render。
##
## 用法（headless 就夠，載入是 CPU/IO，不需要 GPU）：
##   Godot --headless --path godot --script tools/diag_slice_load.gd
##   Godot --headless --path godot --script tools/diag_slice_load.gd -- --deps
##
## --deps 會把 slice.tscn 每一個 ext_resource 單獨計時（每個都 IGNORE_DEEP，
## 才不會被前一個的 cache 洗掉），列出最貴的前 25 個。不加旗標只跑整體分段。
##
## 為什麼是獨立 SceneTree 而不是塞節點進 slice.tscn：slice.tscn 是 16 MB 手調
## 場景，任何在編輯器裡動它的行為都有覆寫使用者手調內容的風險。

const TOP_N := 25


func _init() -> void:
	_run.call_deferred()


func _t() -> int:
	return Time.get_ticks_usec()


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _run() -> void:
	var want_deps := false
	for a in OS.get_cmdline_user_args():
		if a == "--deps":
			want_deps = true

	print("[DIAG] ===== slice 載入診斷 =====")
	_report_file_sizes()

	if want_deps:
		_per_dependency()

	await _whole_scene()
	print("[DIAG] done")
	quit(0)


## 磁碟成本：.tscn 是純文字，每次執行都要重新 parse，沒有 .import 快取。
func _report_file_sizes() -> void:
	var targets := [
		"res://maps/slice/slice.tscn",
		"res://maps/slice/gen/ground_collision.tscn",
		"res://maps/slice/gen/building_collision.tscn",
		"res://maps/slice/gen/b1_street.tscn",
		"res://maps/slice/gen/river_vegetation.tscn",
		"res://maps/slice/gen/bank_planting.tscn",
	]
	var total := 0
	print("[DIAG] --- 文字場景檔大小（.tscn 每次啟動都要重新文字解析）---")
	for p in targets:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			print("[DIAG]   (缺) ", p)
			continue
		var n := f.get_length()
		total += n
		print("[DIAG]   %8.2f MB  %s" % [n / 1048576.0, p])
	print("[DIAG]   %8.2f MB  合計文字場景" % [total / 1048576.0])


## 逐個相依資源計時。每個都用 CACHE_MODE_IGNORE_DEEP，量的是「這個資源自己
## 連同它的子相依，從冷狀態載進來要多久」。加總會大於整體時間（共用子資源被
## 重複載），這是預期行為 —— 這份表要看的是排名，不是總和。
func _per_dependency() -> void:
	var deps := ResourceLoader.get_dependencies("res://maps/slice/slice.tscn")
	print("[DIAG] --- 逐相依資源冷載入（%d 個 ext_resource）---" % deps.size())
	var rows: Array = []
	for d in deps:
		# 格式可能是 "uid://xxx::Type::res://path" 或 "res://path::Type"
		var path := String(d)
		var parts := path.split("::")
		# 取最後一段看起來像路徑的
		var chosen := ""
		for p in parts:
			if p.begins_with("res://") or p.begins_with("uid://"):
				chosen = p
		if chosen == "":
			chosen = parts[0]
		if not ResourceLoader.exists(chosen):
			continue
		var t0 := _t()
		var r := ResourceLoader.load(chosen, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var dt := _ms(t0, _t())
		rows.append({"p": chosen, "ms": dt, "ok": r != null})
		r = null
	rows.sort_custom(func(a, b): return a["ms"] > b["ms"])
	var shown := 0
	for r in rows:
		if shown >= TOP_N:
			break
		print("[DIAG]   %9.1f ms  %s%s" % [r["ms"], r["p"], "" if r["ok"] else "   ← 載入失敗"])
		shown += 1
	var sum := 0.0
	for r in rows:
		sum += r["ms"]
	print("[DIAG]   相依項加總 %.1f ms（含共用資源重複計算）" % sum)


## 整體分段：解析 → 實例化 → 進樹（_ready）。
func _whole_scene() -> void:
	print("[DIAG] --- 整體分段 ---")

	var t0 := _t()
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var t_parse := _ms(t0, _t())
	if packed == null:
		print("[DIAG] slice.tscn 載入失敗")
		return
	print("[DIAG]   冷解析 PackedScene      %9.1f ms" % t_parse)

	t0 = _t()
	var packed_warm := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene",
		ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	print("[DIAG]   熱快取 PackedScene      %9.1f ms" % _ms(t0, _t()))
	packed_warm = null

	t0 = _t()
	var scene := packed.instantiate()
	var t_inst := _ms(t0, _t())
	print("[DIAG]   instantiate()           %9.1f ms" % t_inst)

	t0 = _t()
	root.add_child(scene)
	var t_ready := _ms(t0, _t())
	print("[DIAG]   add_child()/_ready      %9.1f ms" % t_ready)

	await process_frame
	await process_frame

	print("[DIAG]   節點數 %d | 物件數 %d | 靜態記憶體 %.0f MB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])

	_node_census(scene)


## 節點普查：哪一支子樹貢獻了最多節點（節點數 = instantiate 與 _ready 的主成本）。
func _node_census(scene: Node) -> void:
	print("[DIAG] --- 子樹節點數（前 20 支）---")
	var rows: Array = []
	for c in scene.get_children():
		rows.append({"n": String(c.name), "c": _count(c), "t": c.get_class()})
	rows.sort_custom(func(a, b): return a["c"] > b["c"])
	var i := 0
	for r in rows:
		if i >= 20:
			break
		print("[DIAG]   %7d 個  %s  (%s)" % [r["c"], r["n"], r["t"]])
		i += 1


func _count(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count(c)
	return total
