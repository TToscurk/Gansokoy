extends SceneTree
## Wind V1 實機取證：同一台 TPS 機位、固定風時鐘步進，逐 preset 連拍（非 headless、Forward+）。
##
##   Godot_v4.7.2-stable_win64_console.exe --path godot \
##     --script res://tools/wind/wind_capture.gd -- \
##     --scene=village_v2 --views=res://tools/wind/views_village.json \
##     --out=C:/.../wind_v1/village --presets=calm,breeze,gust,off --frames=8 [--step=0.12]
##
## 為什麼要固定風時鐘：shader 的風相位吃 gw_time，不是引擎 TIME。
## 本工具把 Wind 凍結後以固定 dt 推進，所以每一幀的風狀態可重現、可直接比對像素差。
## 水的 TIME 動畫仍會走——所以另外拍一組 off（強制 0 風）當視覺雜訊基線。
## 輸出：<out>/<view>_<preset>_<NN>.png ＋ manifest.json（每幀風狀態）
##
## V1.2 選項：
##   --heat=1   場景有 heat_view(on) 就切熱圖（植被位移→灰階 emission，0.6 m＝白；無光、黑背景）
##   --seq=...  取代 preset 迴圈，逐鏡位跑一串指令（; 分隔）：
##                reset｜preset:<名>｜wind:<deg>,<strength>｜settle:<秒>｜gust:<amp>,<dur>｜label:<名>｜frames:<N>
##                vprof:<α>,<z0>,<elev_ref>,<elev_gain>｜noshelter（同一風時鐘的 A/B：只差剖面／遮蔽）
##                run:<秒>（真實時間、風時鐘解凍：浮物／燈籠等物理物件跟風同步前進）｜rframes:<N>（真實時間每 0.1 s 一張）
##              例：reset;preset:calm;wind:0,0.55;settle:4;label:gustline;gust:0.9,3.0;frames:80
##   場景有 probe_points() → 每個鏡位把探針世界座標投影成像素寫進 manifest（views[].probes）

const SIZE := Vector2i(960, 540)

var wind: Node
var _cam: Camera3D


func _init() -> void:
	_run.call_deferred()


func _arg(a: Array, key: String, dflt: String) -> String:
	for s: String in a:
		if s.begins_with(key + "="):
			return s.substr(key.length() + 1)
	return dflt


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var scene_id := _arg(a, "--scene", "village_v2")
	var views_path := _arg(a, "--views", "res://tools/wind/views_village.json")
	var out := _arg(a, "--out", "user://wind_v1")
	var presets := _arg(a, "--presets", "calm,breeze,gust,off").split(",")
	var frames := int(_arg(a, "--frames", "8"))
	var step := float(_arg(a, "--step", "0.12"))
	var dolly := Vector3.ZERO
	var dv := _arg(a, "--dolly", "")
	if dv != "":
		var parts := dv.split(",")
		dolly = Vector3(parts[0].to_float(), 0.0, parts[1].to_float())
	var only := PackedStringArray()
	if _arg(a, "--only", "") != "":
		only = _arg(a, "--only", "").split(",")
	DirAccess.make_dir_recursive_absolute(out)

	wind = root.get_node_or_null("Wind")
	if wind == null:
		print("FAIL 找不到 Wind autoload")
		quit(1)
		return

	root.size = SIZE
	# TAA 的逐幀 jitter 會在高對比特寫上製造假動量（實測：風關時整片邊緣都在閃）。
	# 取證用固定時鐘＋關 TAA，量到的才是物件真的在動。
	root.use_taa = false
	var map_path := "res://maps/village_v2/village_v2.tscn"
	if scene_id.begins_with("res://"):
		map_path = scene_id
	elif scene_id != "village_v2":
		map_path = "res://maps/beast_path/%s.tscn" % scene_id
	var ps := ResourceLoader.load(map_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		print("FAIL 載不到 ", map_path)
		quit(1)
		return
	var v: Node3D = ps.instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors", "Population"]:
		var n := v.get_node_or_null(nm)
		if n is Node3D:
			(n as Node3D).visible = false
	for n in v.find_children("*ParcelLines*", "", true, false):
		if n is Node3D:
			(n as Node3D).visible = false

	# 日光固定 10:00（太陽高、影子清楚）；天氣關雨。
	var day := root.get_node_or_null("DayNight")
	if day and day.has_method("set_hour"):
		day.set("flowing", false)
		day.set_hour(10.0)
	var weather := root.get_node_or_null("Weather")
	if weather and weather.has_method("set_weather"):
		weather.set_weather("clear")

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	_cam = cam

	for i in 25:
		await process_frame

	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(views_path))
	var sp := v.get_world_3d().direct_space_state
	var man := {"scene": map_path, "size": [SIZE.x, SIZE.y], "step": step, "frames": frames, "shots": [], "views": {}}
	var heat := _arg(a, "--heat", "0") == "1"
	if heat and v.has_method("heat_view"):
		v.call("heat_view", true)
	man["heat"] = heat
	var seq := _arg(a, "--seq", "")
	wind.set_frozen(true)
	# 先關風、讓有慣性的物件（燈籠／落葉）完全靜下來，第一個 preset（通常是 off）才是乾淨基線。
	wind.set_enabled(false)
	for i in 90:
		await process_frame

	for vw in views:
		if not only.is_empty() and not (str(vw[0]) in only):
			continue
		if vw.size() > 1 and str(vw[1]) == "cam":
			# ["<name>", "cam", x,y,z, tx,ty,tz, fov, <view_mode>]：絕對鏡位（道具特寫用，不經地面 raycast）
			# 第 10 欄（選填）＝場景 view_mode(...) 的參數（圖層隔離，例如 pilot 的 trees／grass）
			_cam.global_position = Vector3(float(vw[2]), float(vw[3]), float(vw[4]))
			_cam.look_at(Vector3(float(vw[5]), float(vw[6]), float(vw[7])), Vector3.UP)
			_cam.fov = float(vw[8]) if vw.size() > 8 else 55.0
			if v.has_method("view_mode"):
				v.call("view_mode", str(vw[9]) if vw.size() > 9 else "all")
		elif vw.size() > 1 and str(vw[1]) == "cloth":
			await _aim_cloth(v, float(vw[2]), float(vw[3]))
		else:
			_aim(vw, sp)
			_cam.fov = 70.0
		for i in 3:
			await process_frame
		man["views"][str(vw[0])] = _probe_view(v)
		if seq != "":
			await _run_seq(v, str(vw[0]), seq, step, out, man)
			continue
		for pname: String in presets:
			wind.set_enabled(true)
			if pname == "off":
				wind.set_enabled(false)
			else:
				wind.set_preset(_preset_index(pname))
			# 先把風場推到穩定（3 秒的風時鐘），再開始連拍
			for i in 90:
				wind.debug_advance(1.0 / 30.0)
			# 讓有慣性的物件（燈籠／落葉）在真實時間裡安定下來；只推進風時鐘不夠，
			# 因為它們的 _physics_process 走的是引擎時間。
			for i in 90:
				await process_frame
			# 場景若有 reset_dynamic（pilot），每個 preset 都從靜止開始 → 拍到累積過程。
			if v.has_method("reset_dynamic"):
				v.call("reset_dynamic")
			var key := "%s_%s" % [str(vw[0]), pname]
			for i in frames:
				wind.debug_advance(step)
				await RenderingServer.frame_post_draw
				var st: Dictionary = wind.get_wind()
				var img := root.get_texture().get_image()
				var p := "%s/%s_%02d.png" % [out, key, i]
				img.save_png(p)
				man["shots"].append({
					"key": key, "frame": i, "file": p,
					"preset": st["preset"], "enabled": st["enabled"],
					"strength": st["strength"], "gust": st["gust"], "time": st["time"],
				})
				await process_frame
			print("SHOT %s %d frames" % [key, frames])

	# 過渡序列：breeze → 手動陣風 → calm。用來證明「陣風起落沒有瞬切」。
	if _arg(a, "--transition", "0") == "1":
		if views[0].size() > 1 and str(views[0][1]) == "cloth":
			await _aim_cloth(v, float(views[0][2]), float(views[0][3]))
		else:
			_aim(views[0], sp)
			_cam.fov = 70.0
		wind.set_enabled(true)
		wind.set_preset(1)
		for i in 90:
			wind.debug_advance(1.0 / 30.0)
		for i in 4:
			await process_frame
		if v.has_method("reset_dynamic"):
			v.call("reset_dynamic")
		var phases := [["trans_breeze", 8, false], ["trans_gust", 14, true], ["trans_calm", 18, false]]
		var calmed := false
		for ph in phases:
			if bool(ph[2]):
				wind.trigger_gust(0.7, 3.2)
			if String(ph[0]) == "trans_calm" and not calmed:
				wind.set_preset(0)
				calmed = true
			for i in int(ph[1]):
				wind.debug_advance(0.12)
				if dolly != Vector3.ZERO:
					_cam.position += dolly
				await RenderingServer.frame_post_draw
				var st: Dictionary = wind.get_wind()
				var img := root.get_texture().get_image()
				var p := "%s/%s_%02d.png" % [out, String(ph[0]), i]
				img.save_png(p)
				man["shots"].append({"key": String(ph[0]), "frame": i, "file": p,
					"preset": st["preset"], "enabled": st["enabled"],
					"strength": st["strength"], "gust": st["gust"], "time": st["time"]})
				await process_frame
			print("SHOT %s %d frames" % [String(ph[0]), int(ph[1])])

	# 收工：把風平滑關掉（也驗證關風真的到 0），再退出。
	wind.set_enabled(false)
	for i in 90:
		wind.debug_advance(1.0 / 30.0)
	var st2: Dictionary = wind.get_wind()
	var ok := (not bool(st2["enabled"])) and float(st2["effective"]) < 0.01
	print("%s 收工狀態：enabled=%s effective=%.3f（關風 3 s 後）" % [
		"PASS" if ok else "FAIL", str(st2["enabled"]), float(st2["effective"])])
	var f := FileAccess.open("%s/manifest.json" % out, FileAccess.WRITE)
	f.store_string(JSON.stringify(man, "  "))
	f.close()
	print("manifest -> %s/manifest.json" % out)
	quit(0 if ok else 1)


func _preset_index(n: String) -> int:
	match n:
		"calm": return 0
		"breeze": return 1
		"moderate": return 2
		"gust": return 3
	return 1


## view = [name, x, z, tx, tz, pitch, dist, side]
func _aim(vw: Array, sp: PhysicsDirectSpaceState3D) -> void:
	var pp := Vector2(float(vw[1]), float(vw[2]))
	var tt := Vector2(float(vw[3]), float(vw[4]))
	var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 60.0, pp.y), Vector3(pp.x, -40.0, pp.y))
	var gy := 0.0
	var found := false
	var first_y := 0.0
	var ex: Array[RID] = []
	for k in 12:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			break
		if not found and k == 0:
			first_y = hit.position.y
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			gy = hit.position.y
			found = true
			break
		ex.append(hit.rid)
	if not found and ex.size() > 0:
		gy = first_y
	var fwd := (tt - pp).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var pitch := float(vw[5])
	var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	var look := Vector3(fwd.x * cos(pitch), sin(pitch), fwd.y * cos(pitch))
	var cp := piv - look * float(vw[6]) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	# 相機避開地形／樹幹：從 pivot 往相機拉一條射線，撞到就把相機拉到撞點前 0.3 m
	# （斜坡上的獸道往後退 3.6 m 很容易退進山壁，拍出來會是整片灰）。
	var qc := PhysicsRayQueryParameters3D.create(piv, cp)
	var hc: Dictionary = sp.intersect_ray(qc)
	if not hc.is_empty():
		var dir := (cp - piv).normalized()
		cp = hc.position - dir * 0.3
	_cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)




## 暖簾特寫：view = ["<名稱>", "cloth", x, z]。
## 用「離這個 xz 最近的暖簾」自動取景，不寫死節點路徑：
##   1. 依距離排序候選，把鏡頭放到布的街側（-Z 局部方向；+Z 是貼牆那面）
##   2. 等串流／LOD 讓 Kit 真的顯示（is_visible_in_tree），並用射線確認中間沒有牆
##   3. 都失敗就退到下一個候選，最後印出實際取景的那一片
func _aim_cloth(map_root: Node, px: float, pz: float) -> void:
	var list := map_root.find_children("nr_noren*", "MeshInstance3D", true, false)
	var cands := []
	for mi in list:
		var m := mi as MeshInstance3D
		var xf := m.global_transform
		var c := xf * Vector3(0.9, 1.90, 0.03)
		cands.append({"node": m, "center": c, "fwd": (xf.basis * Vector3(0, 0, 1)).normalized(),
			"d": Vector2(c.x - px, c.z - pz).length()})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var sp: PhysicsDirectSpaceState3D = map_root.get_world_3d().direct_space_state
	_cam.fov = 45.0
	for cand in cands.slice(0, 6):
		var m: MeshInstance3D = cand["node"]
		var center: Vector3 = cand["center"]
		var fwd: Vector3 = cand["fwd"]
		var cp: Vector3 = center - fwd * 2.6   # 街側
		_cam.global_transform = Transform3D(Basis(), cp).looking_at(center, Vector3.UP)
		for i in 10:
			await process_frame
		var q := PhysicsRayQueryParameters3D.create(cp, center)
		var los: Dictionary = sp.intersect_ray(q)
		if m.is_visible_in_tree() and los.is_empty():
			print("CLOTH 取景 %s center=%s d=%.1f" % [String(map_root.get_path_to(m)), center, float(cand["d"])])
			var nvis := 0
			for other in map_root.find_children("nr_noren*", "MeshInstance3D", true, false):
				if (other as MeshInstance3D).is_visible_in_tree():
					nvis += 1
			print("CLOTH 目前場景中可見的暖簾：%d／%d" % [nvis, map_root.find_children("nr_noren*", "MeshInstance3D", true, false).size()])
			return
		print("CLOTH 略過 %s vis=%s los=%s" % [String(m.name), str(m.is_visible_in_tree()),
			"clear" if los.is_empty() else String((los.collider as Node).name)])
	print("CLOTH 找不到可視且無遮擋的暖簾（px=%.1f pz=%.1f）" % [px, pz])


## 探針投影：場景 probe_points() 的世界座標 → 像素（同時寫世界座標，分析端可直接用）。
func _probe_view(scene: Node) -> Dictionary:
	var out := {"cam": [_cam.global_position.x, _cam.global_position.y, _cam.global_position.z]}
	if not scene.has_method("probe_points"):
		return out
	var pts: Dictionary = scene.call("probe_points")
	var px := {}
	for k: String in pts:
		var wp: Vector3 = pts[k]
		var sp := _cam.unproject_position(wp) if not _cam.is_position_behind(wp) else Vector2(-1, -1)
		px[k] = {"world": [wp.x, wp.y, wp.z], "px": [sp.x, sp.y]}
	out["probes"] = px
	return out


func _run_seq(scene: Node, view_name: String, seq: String, step: float, out: String, man: Dictionary) -> void:
	var label := view_name + "_seq"
	for cmd_raw in seq.split(";"):
		var cmd := cmd_raw.strip_edges()
		if cmd == "":
			continue
		var parts := cmd.split(":", true, 1)
		var op := parts[0]
		var arg := parts[1] if parts.size() > 1 else ""
		match op:
			"reset":
				wind.debug_reset()
				wind.set_frozen(true)
				if scene.has_method("apply_wind_setup"):
					scene.call("apply_wind_setup")
				if scene.has_method("reset_dynamic"):
					scene.call("reset_dynamic")
			"preset":
				wind.set_enabled(true)
				if arg == "off":
					wind.set_enabled(false)
				else:
					wind.set_preset(_preset_index(arg))
			"wind":
				var w := arg.split(",")
				wind.set_wind(w[0].to_float(), w[1].to_float())
			"settle":
				for i in int(arg.to_float() * 30.0):
					wind.debug_advance(1.0 / 30.0)
				for i in 4:
					await process_frame
			"gust":
				var g := arg.split(",")
				wind.trigger_gust(g[0].to_float(), g[1].to_float())
			"vprof":
				var vp := arg.split(",")
				wind.set_vertical_profile(vp[0].to_float(), vp[1].to_float(), vp[2].to_float(), vp[3].to_float())
			"noshelter":
				wind.clear_shelters()
			"dview":
				# 位移熱圖（0＝一般、1＝熱圖）：實際地圖也能用（植被 shader 改輸出位移灰階，0.6 m＝白）
				wind.set_debug_view(int(arg))
			"run":
				# 真實時間跑 N 秒（風時鐘解凍）：讓物理物件（浮物、燈籠）與風場同一個時鐘前進
				wind.set_frozen(false)
				var t_end := Time.get_ticks_msec() + int(arg.to_float() * 1000.0)
				while Time.get_ticks_msec() < t_end:
					await physics_frame
				wind.set_frozen(true)
			"label":
				label = view_name + "_" + arg
			"rframes":
				# 真實時間連拍（風時鐘解凍）：每 0.1 s 存一張；浮物等物理物件與風同一時鐘
				wind.set_frozen(false)
				for i in int(arg):
					var t_next := Time.get_ticks_msec() + 100
					while Time.get_ticks_msec() < t_next:
						await physics_frame
					await RenderingServer.frame_post_draw
					var st2: Dictionary = wind.get_wind()
					var p2 := "%s/%s_%03d.png" % [out, label, i]
					root.get_texture().get_image().save_png(p2)
					var fl_states := {}
					var demo := scene.find_child("WindRiverDemo", true, false)
					if demo and demo.has_method("floatables"):
						for f in demo.call("floatables"):
							var fs: Dictionary = f.call("state")
							var fp: Vector3 = fs["pos"]
							fl_states[String(f.name)] = [snappedf(fp.x, 0.01), snappedf(fp.y, 0.001), snappedf(fp.z, 0.01), snappedf(float(fs["fade"]), 0.01)]
					man["shots"].append({"key": label, "frame": i, "file": p2, "preset": st2["preset"],
						"strength": st2["strength"], "gust": st2["gust"], "time": st2["time"], "events": st2["events"],
						"floatables": fl_states})
				wind.set_frozen(true)
				print("SHOT %s %d frames (realtime)" % [label, int(arg)])
			"frames":
				for i in int(arg):
					wind.debug_advance(step)
					await RenderingServer.frame_post_draw
					var st: Dictionary = wind.get_wind()
					var img := root.get_texture().get_image()
					var p := "%s/%s_%03d.png" % [out, label, i]
					img.save_png(p)
					man["shots"].append({
						"key": label, "frame": i, "file": p,
						"preset": st["preset"], "enabled": st["enabled"],
						"strength": st["strength"], "gust": st["gust"], "time": st["time"],
						"events": st["events"],
					})
					await process_frame
				print("SHOT %s %d frames" % [label, int(arg)])
			_:
				print("WARN 未知 seq 指令 %s" % cmd)
