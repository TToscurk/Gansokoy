extends SceneTree
## P13 W9 FIX：建物の見た目＋碰撞の可視化擷取（唯讀・場景ファイルは書かない・有視窗で実行）。
##   godot --path godot --resolution 1280x800 --script res://tools/p13/w9/shot_w9fix.gd -- --out=<png> --body=<村直下 body パス>
##       --cam=x,y,z --at=x,y,z（body 局部）[--mode=runtime|editor] [--collision] [--arch-off] [--fov=55] [--time=10]
##       [--seq=N --dx=0.01]（N 枚を横に dx m ずつ動かして連番保存：<out>_000.png…＝閃爍の時間的検査用）
##       [--shell-off]（修正前の碰撞構成：Shell を無効・body の元の箱を有効。見た目は同じ W9R2）
## --collision では disabled の CollisionShape3D を描かない（有効な形だけを描く＝実際に当たる物）。
## --collision：SceneTree.debug_collisions_hint（実際に有効な碰撞形状を遊戲内で描く＝編輯器の gizmo ではなく runtime の形）。
## --mode=editor：@tool でない腳本を外す（編輯器で走るのは @tool だけ）。
func _init() -> void:
	if "--collision" in OS.get_cmdline_user_args():
		debug_collisions_hint = true
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for s in OS.get_cmdline_user_args():
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return d


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	if _arg("--mode", "runtime") == "editor":
		for n in [v] + v.find_children("*", "", true, false):
			var sc: Script = n.get_script()
			if sc != null and not sc.is_tool():
				n.set_script(null)
	root.add_child(v)
	var sky := v.get_node_or_null("Lighting/天象系統")
	if sky and sky.has_method("設定時刻"):
		sky.call("設定時刻", float(_arg("--time", "10")))
	for i in 10:
		await process_frame
	if "--arch-off" in OS.get_cmdline_user_args():
		v.get_node("ArchW9R2P13").set("enabled", false)
	if "--shell-off" in OS.get_cmdline_user_args():
		for b in v.get_node("ArchW9R2P13").get_children():
			var sh := b.get_node_or_null("Shell")
			if sh == null:
				continue
			for cs in v.get_node(NodePath(String(b.get_meta("body_path")))).get_children():
				if cs is CollisionShape3D:
					(cs as CollisionShape3D).disabled = false
			for cs in sh.get_children():
				(cs as CollisionShape3D).disabled = true
	if debug_collisions_hint:
		for cs in v.find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).disabled:
				(cs as CollisionShape3D).visible = false
	var body := v.get_node(_arg("--body", "")) as Node3D
	var xf := body.global_transform
	var cam := Camera3D.new()
	cam.fov = float(_arg("--fov", "55"))
	cam.near = 0.05
	cam.far = 1500.0
	root.add_child(cam)
	var c0 := xf * _v3(_arg("--cam", "0,3,14"))
	var at := xf * _v3(_arg("--at", "0,2,0"))
	cam.global_position = c0
	cam.look_at(at)
	cam.make_current()
	for i in 120:
		await process_frame
	var seq := int(_arg("--seq", "0"))
	var outp := _arg("--out", "user://shot.png")
	if seq <= 0:
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(outp)
		print("[W9SHOT] → ", outp)
	else:
		var right := cam.global_transform.basis.x
		var dx := float(_arg("--dx", "0.01"))
		for k in seq:
			cam.global_position = c0 + right * dx * k
			cam.look_at(at + right * dx * k)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(outp.trim_suffix(".png") + "_%03d.png" % k)
		print("[W9SHOT] seq %d → %s_###.png" % [seq, outp.trim_suffix(".png")])
	quit(0)
