extends SceneTree
## 探針：讀 yoriichi_iai_run.res 的實際內容（Hips z 範圍、軌數、長度、loop）。
## 執行：godot --headless --path godot -s tools/_probe_iai_run_res.gd

const RES := "res://characters/yoriichi/animations/yoriichi_iai_run.res"


func _init() -> void:
	var a := load(RES) as Animation
	if a == null:
		push_error("載不到 " + RES)
		quit(1)
		return
	print("length=%.4f s  loop=%d  tracks=%d" % [a.length, a.loop_mode, a.get_track_count()])
	for t in a.get_track_count():
		var path := String(a.track_get_path(t))
		var tt := a.track_get_type(t)
		if tt == Animation.TYPE_POSITION_3D:
			var ys: Array[float] = []
			var ts: Array[float] = []
			for k in a.track_get_key_count(t):
				ys.append(a.track_get_key_value(t, k).z)
				ts.append(a.track_get_key_time(t, k))
			print("  POS %s  keys=%d  t=%.3f..%.3f  z=%.4f..%.4f (彈幅 %.1f cm)  首=%.4f 末=%.4f" % [
				path, a.track_get_key_count(t), ts[0], ts[-1], ys.min(), ys.max(),
				(ys.max() - ys.min()) * 100.0, ys[0], ys[-1]])
		elif tt == Animation.TYPE_ROTATION_3D:
			var q0: Quaternion = a.track_get_key_value(t, 0)
			var qn: Quaternion = a.track_get_key_value(t, a.track_get_key_count(t) - 1)
			if path.ends_with(":Hips"):
				print("  ROT %s  keys=%d  首末夾角=%.4f°" % [
					path, a.track_get_key_count(t), rad_to_deg(q0.angle_to(qn))])
	quit(0)
