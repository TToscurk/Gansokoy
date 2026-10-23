extends SceneTree
## 探針：讀 iai_clips.glb 的 Hips 位置軌（決定 build_react_clips.gd 的 hips_ref 基準）。
## 執行：godot --headless --path godot -s tools/_probe_iai_hips.gd

const GLB := "res://characters/yoriichi/anim_src/iai_clips.glb"


func _init() -> void:
	var ps := load(GLB) as PackedScene
	if ps == null:
		push_error("載不到 " + GLB)
		quit(1)
		return
	var inst := ps.instantiate()
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_error("GLB 沒有 AnimationPlayer")
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]
	print("GLB 動畫：", str(ap.get_animation_list()))
	for nm in ap.get_animation_list():
		var a: Animation = ap.get_animation(nm)
		print("=== %s  len=%.3f  tracks=%d" % [String(nm), a.length, a.get_track_count()])
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			var bone := path.get_slice(":", 1) if path.contains(":") else path.get_file()
			if bone != "Hips":
				continue
			var tt := a.track_get_type(t)
			if tt != Animation.TYPE_POSITION_3D:
				continue
			var n := a.track_get_key_count(t)
			var ys: Array[float] = []
			for k in n:
				ys.append(a.track_get_key_value(t, k).y)
			print("   Hips 位置軌 keys=%d  y: f0=%.5f  ymin=%.5f  ymax=%.5f" % [
				n, ys[0], ys.min(), ys.max()])
	inst.free()
	quit(0)
