extends SceneTree
## 實驗：把「文字 .tscn」轉成「二進位 .scn」後，冷載入快多少。
##
##   Godot --headless --path godot --script tools/diag_binary_scene_gain.gd
##
## 只寫到 user:// 底下的暫存檔，不動 res:// 任何一個檔案。
## 目的是取得可信數字，再決定要不要真的轉換。

const TARGETS := [
	"res://maps/slice/slice.tscn",
	"res://maps/slice/gen/ground_collision.tscn",
	"res://maps/slice/prototypes/waterway_art_review.tscn",
	"res://maps/slice/gen/building_collision.tscn",
	"res://maps/slice/gen/b1_street.tscn",
	"res://maps/slice/gen/village_trees.tscn",
]


func _init() -> void:
	_run.call_deferred()


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _run() -> void:
	print("[BIN] 檔案                                     文字 ms    二進位 ms   加速   文字 MB  二進位 MB")
	var tot_txt := 0.0
	var tot_bin := 0.0
	for p in TARGETS:
		if not ResourceLoader.exists(p):
			print("[BIN] (缺) ", p)
			continue

		var t0 := Time.get_ticks_usec()
		var res := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var t_txt := _ms(t0, Time.get_ticks_usec())
		if res == null:
			print("[BIN] 載入失敗 ", p)
			continue

		var out := "user://bin_%s.scn" % p.get_file().get_basename()
		var err := ResourceSaver.save(res, out)
		if err != OK:
			print("[BIN] 存檔失敗(%d) %s" % [err, out])
			continue
		res = null

		t0 = Time.get_ticks_usec()
		var res2 := ResourceLoader.load(out, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var t_bin := _ms(t0, Time.get_ticks_usec())
		res2 = null

		var sz_txt := FileAccess.open(p, FileAccess.READ).get_length() / 1048576.0
		var sz_bin := FileAccess.open(out, FileAccess.READ).get_length() / 1048576.0
		tot_txt += t_txt
		tot_bin += t_bin
		print("[BIN] %-42s %8.1f %10.1f %7.1fx %8.2f %9.2f" % [
			p.get_file(), t_txt, t_bin, t_txt / maxf(t_bin, 0.001), sz_txt, sz_bin])

	print("[BIN] 合計 文字 %.1f ms → 二進位 %.1f ms（省 %.1f ms）" % [
		tot_txt, tot_bin, tot_txt - tot_bin])
	print("[BIN] done")
	quit(0)
