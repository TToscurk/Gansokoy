extends SceneTree
## P12 Wave 1（只讀、headless）：village_v2.tscn の載入を段階ごとに分けて量る。
##   godot --headless --path . --script res://tools/p12/probe_load_phases.gd -- [--deps]
## 段階：A 依存 ext_resource を種類別に個別 load（キャッシュに積む）／B 場景 load（parse＋残り）／C instantiate。
## --deps なし：A を飛ばして terrain gate と同じ load()+instantiate() の内訳（load と instantiate）だけ。
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var deps_mode := "--deps" in OS.get_cmdline_user_args()
	var by_type := {}
	var slow: Array = []
	if deps_mode:
		var txt := FileAccess.get_file_as_string(SCENE)
		var re := RegEx.new()
		re.compile('\\[ext_resource type="([^"]+)"[^\\]]*path="([^"]+)"')
		for m in re.search_all(txt):
			var t := m.get_string(1)
			var p := m.get_string(2)
			var a := Time.get_ticks_usec()
			ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
			var ms := (Time.get_ticks_usec() - a) / 1000.0
			var e: Array = by_type.get(t, [0, 0.0])
			e[0] += 1
			e[1] += ms
			by_type[t] = e
			slow.append([ms, p])
		slow.sort_custom(func(x, y): return x[0] > y[0])
	var t0 := Time.get_ticks_usec()
	var ps := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	var t1 := Time.get_ticks_usec()
	var v := ps.instantiate()
	var t2 := Time.get_ticks_usec()
	root.add_child(v)
	var t3 := Time.get_ticks_usec()
	await process_frame
	var t4 := Time.get_ticks_usec()
	if deps_mode:
		var tot := 0.0
		for t in by_type:
			tot += by_type[t][1]
		print("[P12LOAD] A 依存 %d 個 個別 load 合計 %.0f ms" % [slow.size(), tot])
		for t in by_type:
			print("[P12LOAD]   %-28s %4d 個 %8.1f ms" % [t, by_type[t][0], by_type[t][1]])
		for k in mini(15, slow.size()):
			print("[P12LOAD]   slow %7.1f ms %s" % [slow[k][0], slow[k][1]])
	print("[P12LOAD] B 場景 load %.0f ms／C instantiate %.0f ms／add_child(_ready) %.0f ms／first frame %.0f ms" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
	quit(0)
