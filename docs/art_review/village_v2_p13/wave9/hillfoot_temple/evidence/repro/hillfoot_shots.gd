extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 BEFORE／AFTER 截圖] 唯讀・場景檔不寫。
##   godot --path godot --script <this> -- <outdir/> <BEFORE|AFTER> --map=village_v2
## AFTER＝磁碟場景原樣（Hero 已掛）。BEFORE＝同一場景在記憶體內把 Hero 隱藏、放回 P0 佔位 Block 的外觀
## （BoxMesh 18×9×12、材質同原 sub_resource：albedo (0.231, 0.176, 0.134)、roughness 0.95；只做外觀，不加碰撞）。
## 鏡位：玩家站點 → 注視點；固定相機＝玩家後方 5 m・地面 +2.4 m，看注視點地面 +1.5 m，FOV 60（同收尾 debug 比較圖）。
const SHOTS := [
	["street_s", Vector2(228.0, -149.0), Vector2(228.0, -170.0)],
	["street_w", Vector2(210.0, -149.0), Vector2(228.0, -170.0)],
	["street_e", Vector2(247.0, -151.0), Vector2(228.0, -170.0)],
	["forecourt", Vector2(224.0, -159.0), Vector2(228.0, -168.0)],
]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var anchor := vil.get_node("Landmarks/LANDMARK_HILLFOOT_TEMPLE") as Node3D
	if tag == "BEFORE":
		(anchor.get_node("Hero") as Node3D).visible = false
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(18, 9, 12)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.23099999, 0.17639999, 0.1344, 0.42)
		m.roughness = 0.95
		mi.material_override = m
		mi.position = Vector3(0, 4.5, 0)
		anchor.add_child(mi)
	await _frames(10)
	for s: Array in SHOTS:
		var at: Vector2 = s[1]
		var lk: Vector2 = s[2]
		await _tpw(at, (lk - at).normalized())
		var dir := (lk - at).normalized()
		var gy := player.global_position.y
		var fc := Camera3D.new()
		fc.fov = 60.0
		root.add_child(fc)
		fc.global_transform = Transform3D(Basis(), Vector3(at.x - dir.x * 5.0, gy + 2.4, at.y - dir.y * 5.0)).looking_at(
			Vector3(lk.x, gy + 1.5, lk.y), Vector3.UP)
		fc.make_current()
		await _shot("%s_%s" % [tag, s[0]], 20)
		fc.queue_free()
		await _frames(2)
	print("[HILLSHOT] %s done" % tag)
	quit(0)
