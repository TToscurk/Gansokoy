extends SceneTree
## P13 Wave 6：village_v2.tscn の load()+instantiate() 時間（Wave 6 overlay あり／なし）の比較（唯読）。
func _init() -> void:
	_run.call_deferred()
func _t(p: String) -> int:
	var t0 := Time.get_ticks_usec()
	var ps := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var n := ps.instantiate()
	var t1 := Time.get_ticks_usec()
	n.free()
	return (t1 - t0) / 1000
func _run() -> void:
	var a := PackedInt32Array()
	var b := PackedInt32Array()
	for i in 3:
		b.append(_t("res://maps/village_v2/_w6_nooverlay_tmp.tscn"))
		a.append(_t("res://maps/village_v2/village_v2.tscn"))
	print("[LOADT2] without W6 overlays (ms): ", b)
	print("[LOADT2] with    W6 overlays (ms): ", a)
	quit(0)
