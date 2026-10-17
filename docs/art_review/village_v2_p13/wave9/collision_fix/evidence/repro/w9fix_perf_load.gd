extends SceneTree
## 一時：overlay .scn（HEAD 版＝Shell なし／現行＝Shell 391 箱）の読み込み＋instantiate 時間（各 7 回・中央値）
func _init() -> void:
	var paths := OS.get_cmdline_user_args()
	for rep in 2:
		for p in paths:
			var tl: Array = []
			var ti: Array = []
			var nodes := 0
			for i in 7:
				var t0 := Time.get_ticks_usec()
				var ps := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
				var t1 := Time.get_ticks_usec()
				var n := ps.instantiate()
				var t2 := Time.get_ticks_usec()
				nodes = n.find_children("*", "", true, false).size()
				n.free()
				tl.append((t1 - t0) / 1000.0)
				ti.append((t2 - t1) / 1000.0)
			tl.sort()
			ti.sort()
			if rep == 1:
				print("[W9PERF] %s：load 中央値 %.2f ms・instantiate 中央値 %.2f ms・節点 %d" % [p.get_file(), tl[3], ti[3], nodes])
	quit(0)
