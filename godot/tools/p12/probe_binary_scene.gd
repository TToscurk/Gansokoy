extends SceneTree
## P12 Wave 1 実験（場景ファイルは書き換えない）：village_v2.tscn をメモリで読み、scratch へ .scn（binary）として保存し、
## 別プロセスで load 時間を比べるための出力だけを作る。
##   godot --headless --path . --script res://tools/p12/probe_binary_scene.gd -- --out=<abs dir>/ [--mode=save|load] [--file=<path>]
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	var mode := "save"
	var file := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--file="):
			file = a.trim_prefix("--file=")
	if mode == "save":
		var ps := load(SCENE) as PackedScene
		var dst := out + "village_v2_probe.scn"
		var err := ResourceSaver.save(ps, dst, ResourceSaver.FLAG_COMPRESS)
		print("[P12BIN] save %s err=%d size %d bytes" % [dst, err, FileAccess.get_file_as_bytes(dst).size()])
	else:
		var t0 := Time.get_ticks_usec()
		var ps2 := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var t1 := Time.get_ticks_usec()
		var v := ps2.instantiate()
		var t2 := Time.get_ticks_usec()
		print("[P12BIN] load %s %.0f ms／instantiate %.0f ms／nodes %d" % [file.get_file(), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, v.get_child_count()])
		v.free()
	quit(0)
