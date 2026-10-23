extends SceneTree
## R4：列出既有 v24 動畫資源的軌道格式（唯讀），供 R4 輸出沿用相同慣例。
func _initialize() -> void:
	for p in ["res://characters/yoriichi/v24/anims/atk_cross.res", "res://characters/yoriichi/v24/anims/ua_idle_b.res"]:
		var a: Animation = load(p)
		print("== ", p, " len=", a.length, " tracks=", a.get_track_count(), " loop=", a.loop_mode, " step=", a.step)
		for i in mini(a.get_track_count(), 6):
			print("  ", a.track_get_type(i), " ", a.track_get_path(i), " keys=", a.track_get_key_count(i), " interp=", a.track_get_interpolation_type(i))
		print("  meta: ", a.get_meta_list())
	quit()
