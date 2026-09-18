extends SceneTree
## 量測：iai_stance / iai_slash 兩支 .res 的時間軸 —— 每條 Hips 位置軌的 key 時間與 z，
## 以及 RightHand 旋轉軌的 key 時間。給引擎接線定「進姿結束幀／斬擊接觸幀」用，不猜。
## 執行：godot --headless --path godot -s res://tools/probe_iai_res.gd

func _dump(path: String) -> void:
	var a: Animation = load(path)
	print("== ", path.get_file(), " length=", a.length, " loop=", a.loop_mode)
	for t in a.get_track_count():
		var p := String(a.track_get_path(t))
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			print("   POS ", p)
			for k in a.track_get_key_count(t):
				var v: Vector3 = a.track_get_key_value(t, k)
				print("     t=%.4f  (%.4f, %.4f, %.4f)" % [a.track_get_key_time(t, k), v.x, v.y, v.z])
	for t in a.get_track_count():
		var p := String(a.track_get_path(t))
		if p.contains("RightHand") and a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			print("   ROT ", p, " keys=", a.track_get_key_count(t))
			for k in a.track_get_key_count(t):
				print("     t=%.4f" % a.track_get_key_time(t, k))

func _init() -> void:
	_dump("res://characters/yoriichi/animations/yoriichi_iai_stance.res")
	_dump("res://characters/yoriichi/animations/yoriichi_iai_slash.res")
	var idle: Animation = load("res://characters/yoriichi/animations/yoriichi_idle_grounded.res")
	print("== idle length=", idle.length)
	for t in idle.get_track_count():
		if idle.track_get_type(t) == Animation.TYPE_POSITION_3D:
			var v: Vector3 = idle.track_get_key_value(t, 0)
			print("   idle POS ", idle.track_get_path(t), " key0=", v)
	quit(0)
