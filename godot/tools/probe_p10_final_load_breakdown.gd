extends SceneTree
## 唯讀診断（P10 FINAL D4）：terrain gate の「base load ≤ 3000 ms」が 10-07（R3b 全回歸 PASS）以後に超えた原因の内訳。
##   godot --headless --path godot --script res://tools/probe_p10_final_load_breakdown.gd                    village_v2.tscn の load＋instantiate（通常キャッシュ）
##   godot --headless --path godot --script res://tools/probe_p10_final_load_breakdown.gd -- --only-overlays  10-07 以後に掛けた overlay だけを、
##       新しいプロセスで順に load＋instantiate（通常キャッシュ・依存は共有＝最初の NPC モデル等の読み込みを含む）
## 場景には書き込まない。CACHE_MODE_IGNORE_DEEP は使わない（全依存を複製してメモリを食い尽くす：24 GB で止めた）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const NEW_OVERLAYS := [
	"res://maps/village_v2/gen/population_core_p10.tscn",
	"res://maps/village_v2/gen/entrance_cue_p10.tscn",
	"res://maps/village_v2/gen/population_outer_p10.tscn",
	"res://maps/village_v2/gen/human_use_p10.scn",
	"res://maps/village_v2/gen/human_use_exp_p10.scn",
]


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	if not ("--only-overlays" in OS.get_cmdline_user_args()):
		var t0 := Time.get_ticks_usec()
		var ps := ResourceLoader.load(SCENE) as PackedScene
		var t1 := Time.get_ticks_usec()
		var v := ps.instantiate()
		var t2 := Time.get_ticks_usec()
		print("[LOAD] full village_v2.tscn load %.0f ms + instantiate %.0f ms = %.0f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t2 - t0) / 1000.0])
		v.free()
		quit(0)
		return
	var tot := 0.0
	for p: String in NEW_OVERLAYS:
		var a := Time.get_ticks_usec()
		var s := ResourceLoader.load(p) as PackedScene
		var b := Time.get_ticks_usec()
		var inst := s.instantiate()
		var c := Time.get_ticks_usec()
		inst.free()
		tot += (c - a) / 1000.0
		print("[LOAD] overlay %7.0f ms（load %6.0f + inst %6.0f） %s" % [(c - a) / 1000.0, (b - a) / 1000.0, (c - b) / 1000.0, p.get_file()])
	print("[LOAD] 10-07 以後の overlay 合計 %.0f ms（依存共有・順番どおり）" % tot)
	quit(0)
