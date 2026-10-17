extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 BEFORE／AFTER 截圖] 唯讀・場景檔不寫。
##   godot --path godot --script <this> -- <outdir/> <TAG> <views.json> [--map=village_v2]
## 固定 10:00（DayNight 停流）、正式 main.tscn → village_v2、實際玩家為比例尺；相機＝世界座標固定（BEFORE／AFTER 完全相同）。
## views.json 的 ortho 為診斷用（不當審美證據）。


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var only := PackedStringArray()
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	await _frames(20)
	if "--disable-overlay" in args:
		# BEFORE（可逆的證明）：把 HillfootPrecinctE2.enabled 關掉＝E082 垣・草株還原、DistrictHF／Ground 隱藏
		var ov0 := vil.get_node_or_null("HillfootPrecinctE2")
		if ov0 != null:
			ov0.set("enabled", false)
			await _frames(6)
		print("[PSHOT] overlay disabled：", ov0 != null)
	for v: Dictionary in spec["views"]:
		if not only.is_empty() and not (String(v["name"]) in only):
			continue
		var pl: Array = v["player"]
		if pl[0] != null:
			await _tpw(Vector2(float(pl[0]), float(pl[1])), Vector2(float(pl[2]), float(pl[3])))
		else:
			# 石段頂：玩家站在相機正下方（石段頂的步行面）
			var pp: Array = v["pos"]
			await _tpw(Vector2(float(pp[0]), float(pp[2])), Vector2(float(pl[2]), float(pl[3])))
		if bool(v.get("tps", false)):
			await _frames(10)
			await _shot("%s_%s" % [tag, v["name"]], 24)
			print("[PSHOT] %s (TPS) player=%s" % [v["name"], str(player.global_position)])
			continue
		var fc := Camera3D.new()
		fc.fov = float(v["fov"])
		root.add_child(fc)
		var p: Array = v["pos"]
		var lk: Array = v["look"]
		fc.global_transform = Transform3D(Basis(), Vector3(p[0], p[1], p[2])).looking_at(Vector3(lk[0], lk[1], lk[2]), Vector3.UP)
		fc.make_current()
		await _shot("%s_%s" % [tag, v["name"]], 24)
		print("[PSHOT] %s player=%s" % [v["name"], str(player.global_position)])
		fc.queue_free()
		await _frames(2)
	if spec.has("ortho") and (only.is_empty() or String(spec["ortho"]["name"]) in only):
		var o: Dictionary = spec["ortho"]
		var oc := Camera3D.new()
		oc.projection = Camera3D.PROJECTION_ORTHOGONAL
		oc.size = float(o["size"])
		oc.near = 0.5
		oc.far = 200.0
		root.add_child(oc)
		var c: Array = o["center"]
		oc.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(c[0], float(o["height"]), c[1]))
		# 北（-z）在畫面上方
		oc.make_current()
		await _shot("%s_%s" % [tag, o["name"]], 24)
		oc.queue_free()
	print("[PSHOT] %s done" % tag)
	quit(0)
