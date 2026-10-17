extends SceneTree
## 動態跳動實測（V1.3；非 headless、真渲染、正式 main.tscn＋玩家）。只量，不改任何東西。
##  A. 水：瀑布特寫／潭面／潭＋瀑布 3 個固定鏡位，時鐘停在 hour，連拍 N 幀（max_fps 60），量水區逐幀差——
##     平滑的流動＝每幀差接近；UV 捲動回繞、法線跳格、透明排序翻轉＝某一幀的差突然變成中位數的好幾倍（spike）。
##  B. 陰影切換：戰鬥圓 TPS 鏡位，時鐘從 h0 到 h1 每 1 遊戲分鐘一步（正常遊玩 1 遊戲分鐘 ≈ 2.5 秒；ShadowBudget 每 1 秒重算），
##     每步讓 ShadowBudget 依新太陽重算、拍一張，記「被關掉投影的幾何體數」變化與畫面 32×32 區塊的最大變化：
##     太陽緩慢移動的正常陰影位移 vs. 投影開關造成的整塊突變（pop）。
##   godot --path godot --script res://tools/beast_path/anim_jitter_beast_path.gd -- --map=beast_path --out=<dir> [--hour=10] [--frames=120] [--shadow=16.67,17.33]
const BP := preload("res://tools/beast_path/bp_lib.gd")
const TG := preload("res://tools/beast_path/terrain_generator.gd")

var main: Node
var player: CharacterBody3D
var adapter: Node
var lib: BP


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var hour := 10.0
	var frames := 120
	var shadow_spans: Array = [[6.67, 7.33], [16.67, 17.33]]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
	if out == "":
		push_error("需要 --out=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	lib = BP.new()
	lib.setup(true, true)
	get_root().size = Vector2i(1280, 720)
	Engine.max_fps = 60
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[JIT] ✗ 120 秒內沒進到 beast_path")
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("DayNight")
	dn.set("flowing", false)
	dn.call("set_hour", hour)
	var sbn := main.find_child("ShadowBudget", true, false)
	for _i in 10:
		await process_frame
	if sbn != null:
		sbn.call("apply", true)
	var rep := {"water": [], "shadow": []}
	# ---------------- A. 水
	var free_cam := Camera3D.new()
	free_cam.fov = 62.0
	free_cam.far = 900.0
	root.add_child(free_cam)
	var g: Dictionary = TG.waterfall_geom(lib)
	var wf_x := float(lib.L["boss_arena"]["waterfall"]["x"])
	var wf_z := float(lib.L["boss_arena"]["waterfall"]["z"])
	var views := [
		{"name": "waterfall_close", "cam": Vector3(wf_x + 1.5, float(g["pw"]) + 3.0, wf_z + 11.0), "look": Vector3(wf_x, float(g["pw"]) + 7.0, wf_z)},
		{"name": "pool_surface", "cam": Vector3(wf_x + 4.0, float(g["pw"]) + 1.6, wf_z + 9.0), "look": Vector3(wf_x - 1.0, float(g["pw"]), wf_z + 2.5)},
		{"name": "pool_and_falls", "cam": Vector3(wf_x - 6.0, float(g["pw"]) + 4.0, wf_z + 20.0), "look": Vector3(wf_x, float(g["pw"]) + 9.0, wf_z)},
	]
	player.visible = false
	for v: Dictionary in views:
		free_cam.global_position = v["cam"]
		free_cam.look_at(v["look"])
		free_cam.make_current()
		for _i in 30:
			await process_frame
		var prev: Image = null
		var diffs := PackedFloat32Array()
		var dts := PackedFloat32Array()
		var tprev := Time.get_ticks_usec()
		for f in frames:
			await process_frame
			var img := get_root().get_texture().get_image()
			img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
			var tn := Time.get_ticks_usec()
			if prev != null:
				diffs.append(_mean_diff(prev, img))
				dts.append(float(tn - tprev) / 1000.0)
			tprev = tn
			prev = img
			if f == frames / 2:
				get_root().get_texture().get_image().save_png(out.path_join("%s_mid.png" % String(v["name"])))
		var srt := Array(diffs)
		srt.sort()
		var med := float(srt[srt.size() / 2])
		var mx := float(srt[srt.size() - 1])
		# 每幀時間不一定相同 → 以「差÷幀時間」再看一次（時間正規化的 spike）
		var rate := PackedFloat32Array()
		for i in diffs.size():
			rate.append(diffs[i] / maxf(dts[i], 1.0))
		var sr := Array(rate)
		sr.sort()
		var rmed := float(sr[sr.size() / 2])
		var spikes := 0
		for i in rate.size():
			if rate[i] > 3.0 * rmed and diffs[i] > 2.0 * med:
				spikes += 1
		var dsorted := Array(dts)
		dsorted.sort()
		var rec := {"view": v["name"], "frames": diffs.size(), "diff_med": snappedf(med, 0.0001), "diff_max": snappedf(mx, 0.0001),
			"max_over_med": snappedf(mx / maxf(med, 1e-6), 0.01), "rate_med": snappedf(rmed, 0.00001), "spikes_3x": spikes,
			"dt_ms_med": snappedf(float(dsorted[dsorted.size() / 2]), 0.1), "dt_ms_max": snappedf(float(dsorted[dsorted.size() - 1]), 0.1)}
		(rep["water"] as Array).append(rec)
		print("[JIT] 水 %-16s %d 幀：逐幀差 中位 %.4f、最大 %.4f（%.2f×）；時間正規化後 > 3× 中位的突變 %d 幀" % [rec["view"], rec["frames"], med, mx, rec["max_over_med"], spikes])
	# ---------------- B. 陰影切換
	player.visible = true
	var gp_cam: Camera3D = player.get_viewport().get_camera_3d()
	for c in root.find_children("*", "Camera3D", true, false):
		if c != free_cam and c.get_parent() is SpringArm3D:
			gp_cam = c
	var spots := [{"name": "arena_tps", "arena": [180.0, 6.0], "face": 0.0}, {"name": "arena_edge_east", "arena": [100.0, 17.0], "face": 280.0}]
	for sp: Dictionary in spots:
		for span: Array in shadow_spans:
			var q := lib.arena_pos(float(sp["arena"][0]), float(sp["arena"][1]))
			await _put(q, -deg_to_rad(float(sp["face"])), -0.18, 8.5)
			gp_cam.make_current()
			var h := float(span[0])
			dn.call("set_hour", h)
			if sbn != null:
				sbn.call("apply", true)
			for _i in 20:
				await process_frame
			var prev2: Image = null
			var prev2_full: Image = null
			var prev_off := int(sbn.get_meta("shadow_off_geoms", -1)) if sbn != null else -1
			var steps: Array = []
			while h <= float(span[1]) + 1e-4:
				dn.call("set_hour", h)
				if sbn != null:
					sbn.call("apply", true)
				for _i in 3:
					await process_frame
				var full := get_root().get_texture().get_image()
				var img2 := full.duplicate() as Image
				img2.resize(320, 180, Image.INTERPOLATE_BILINEAR)
				var off := int(sbn.get_meta("shadow_off_geoms", -1)) if sbn != null else -1
				if prev2 != null:
					var bd := _block_max(prev2, img2, 8)
					steps.append({"h": snappedf(h, 0.001), "off": off, "d_off": off - prev_off, "mean": snappedf(_mean_diff(prev2, img2), 0.0001), "block_max": snappedf(bd, 0.0001)})
					if bd > 0.1:
						prev2_full.save_png(out.path_join("pop_%s_%05.2f_before.png" % [String(sp["name"]), h]))
						full.save_png(out.path_join("pop_%s_%05.2f_after.png" % [String(sp["name"]), h]))
				prev2 = img2
				prev2_full = full
				prev_off = off
				h += 1.0 / 60.0
			var tog: Array = steps.filter(func(s: Dictionary) -> bool: return int(s["d_off"]) != 0)
			var calm: Array = steps.filter(func(s: Dictionary) -> bool: return int(s["d_off"]) == 0)
			var bm_t := 0.0
			for s2: Dictionary in tog:
				bm_t = maxf(bm_t, float(s2["block_max"]))
			var cb: Array = calm.map(func(s3: Dictionary) -> float: return float(s3["block_max"]))
			cb.sort()
			var bm_c_med := float(cb[cb.size() / 2]) if not cb.is_empty() else 0.0
			var bm_c_max := float(cb[cb.size() - 1]) if not cb.is_empty() else 0.0
			var rec2 := {"spot": sp["name"], "span": span, "steps": steps.size(), "toggle_steps": tog.size(),
				"toggled_geoms_total": tog.reduce(func(acc: int, s4: Dictionary) -> int: return acc + absi(int(s4["d_off"])), 0),
				"block_max_at_toggles": snappedf(bm_t, 0.0001), "block_max_calm_med": snappedf(bm_c_med, 0.0001), "block_max_calm_max": snappedf(bm_c_max, 0.0001), "detail": steps}
			(rep["shadow"] as Array).append(rec2)
			print("[JIT] 影 %-16s %.2f→%.2f h：%d 步、其中 %d 步有投影開關（共 %d 個幾何體）；32 px 區塊最大變化 開關步 %.4f vs 無開關步 中位 %.4f／最大 %.4f" % [
				sp["name"], float(span[0]), float(span[1]), steps.size(), tog.size(), int(rec2["toggled_geoms_total"]), bm_t, bm_c_med, bm_c_max])
			get_root().get_texture().get_image().save_png(out.path_join("%s_%02d.png" % [String(sp["name"]), int(float(span[1]))]))
	var fo := FileAccess.open(out.path_join("anim_jitter.json"), FileAccess.WRITE)
	fo.store_string(JSON.stringify(rep, "  "))
	fo.close()
	print("[JIT] 完成 → %s" % out)
	quit(0)


func _mean_diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			s += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			n += 1
	return s / float(maxi(n, 1)) / 3.0


## 每 bs×bs 區塊（320×180 縮圖上 8 px＝原圖 32 px）的平均差，取最大
func _block_max(a: Image, b: Image, bs: int) -> float:
	var best := 0.0
	for by in range(0, a.get_height() - bs + 1, bs):
		for bx in range(0, a.get_width() - bs + 1, bs):
			var s := 0.0
			for y in range(by, by + bs, 2):
				for x in range(bx, bx + bs, 2):
					var p := a.get_pixel(x, y)
					var q := b.get_pixel(x, y)
					s += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			best = maxf(best, s / float((bs / 2) * (bs / 2)) / 3.0)
	return best


func _put(q: Vector2, yaw: float, pitch: float, dist: float) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 80.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.2, q.y)
	adapter.set("_target_yaw", yaw)
	adapter.set("_target_pitch", pitch)
	adapter.set("_current_pitch", pitch)
	adapter.set("_target_distance", dist)
	adapter.set("_current_distance", dist)
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	for i in 30:
		await physics_frame
