extends SceneTree
## S01 地表＋森林探針（離線、秒級）：用 s01_forest_inputs.json 的道具腳印（上一次生成寫的）當輸入，現場跑一次森林規劃
## （layout 現在的 S01 候選設定），再用規劃出的樹重建地表情境、重算 s01_ground.gd 的通道，
## 輸出分類俯視圖＋沿進度的組成表＋S01 森林統計（群聚／最近鄰／離路距離）。調分布時不必重生整個場景。
## 注意：道具腳印來自上一次生成；改了柵欄／道具之後要先跑一次 generate（--only=S01）才會更新。
##   godot --headless --path godot --script res://tools/beast_path/probe_s01_ground.gd -- --out=<png> [--x0=-60 --x1=60 --z0=-106 --z1=20 --px=0.5]
## 色：草＝綠、壓實土＝褐黃、礫＝淺灰、泥＝深褐、落葉＝橘褐、岩＝深灰；苔以亮綠疊加。小圓點＝樹（綠）、岩/道具腳印（灰）。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")
const S01Ground := preload("res://tools/beast_path/s01_ground.gd")


func _initialize() -> void:
	var out := "user://s01_ground_map.png"
	var x0 := -60.0
	var x1 := 60.0
	var z0 := -106.0
	var z1 := 20.0
	var px := 0.5
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--x0="):
			x0 = float(a.trim_prefix("--x0="))
		elif a.begins_with("--x1="):
			x1 = float(a.trim_prefix("--x1="))
		elif a.begins_with("--z0="):
			z0 = float(a.trim_prefix("--z0="))
		elif a.begins_with("--z1="):
			z1 = float(a.trim_prefix("--z1="))
		elif a.begins_with("--px="):
			px = float(a.trim_prefix("--px="))
	var lib := BP.new()
	lib.setup(true, true)
	var inp: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/beast_path/gen/s01_forest_inputs.json"))
	var feet: Array = []
	for e: Dictionary in (inp as Dictionary)["footprints"]:
		feet.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
	var fp := ForestPlanner.new()
	fp.setup(lib, feet)
	var t_plan := Time.get_ticks_msec()
	fp.plan()
	if String(fp.freeze_error) != "":
		print("[plan] 規劃失敗：", fp.freeze_error)
		quit(1)
		return
	print("[plan] %d ms  s01_info = %s" % [Time.get_ticks_msec() - t_plan, str(fp.s01_info)])
	var trees: Array = fp.trees
	var ctx := S01Ground.build_ctx(lib, trees, fp.kit, feet)
	var G = ctx["s01"]
	var W := int((x1 - x0) / px)
	var H := int((z1 - z0) / px)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var cols := {"grass": Vector3(0.30, 0.55, 0.20), "dirt": Vector3(0.78, 0.60, 0.36), "gravel": Vector3(0.82, 0.82, 0.80), "mud": Vector3(0.27, 0.17, 0.11), "leaf": Vector3(0.58, 0.34, 0.14), "rock": Vector3(0.36, 0.36, 0.40)}
	var dec := {}          # 進度十分位 → [格數, trodden, gravel, mud, leaf, rock, moss, grass]（路廊 ±hw+3 內外分開）
	var s0: float = G.s0
	var sl: float = G.s_len
	for j in H:
		for i in W:
			var x := x0 + (float(i) + 0.5) * px
			var z := z0 + (float(j) + 0.5) * px
			var ix := int(round((x - lib.lx0) / lib.cell))
			var iz := int(round((z - lib.lz0) / lib.cell))
			var g: PackedFloat32Array = G.channels(ix, iz, ctx)
			var gr := maxf(1.0 - g[0] - g[1] - g[2] - g[3] - g[4], 0.0)
			var c: Vector3 = (cols["dirt"] as Vector3) * g[0] + (cols["gravel"] as Vector3) * g[1] + (cols["mud"] as Vector3) * g[2] + (cols["rock"] as Vector3) * g[3] + (cols["leaf"] as Vector3) * g[4] + (cols["grass"] as Vector3) * gr
			c = c.lerp(Vector3(0.45, 0.95, 0.30), clampf(g[6], 0.0, 1.0) * 0.45)
			img.set_pixel(i, j, Color(c.x, c.y, c.z))
			if x >= -50.0 and x <= 50.0 and z <= 16.0 and z >= -100.0:
				var q := lib.main.q(Vector2(x, z))
				var u := clampf((float(q["s"]) - s0) / sl, 0.0, 0.999)
				var band := int(u * 10.0)
				var near := absf(float(q["off"])) < 6.0
				var key := "%d%s" % [band, "n" if near else "f"]
				if not dec.has(key):
					dec[key] = [0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
				var d: Array = dec[key]
				d[0] += 1
				d[1] += g[0]
				d[2] += g[1]
				d[3] += g[2]
				d[4] += g[4]
				d[5] += g[3]
				d[6] += g[6]
				d[7] += gr
	# 樹與腳印的小圓點
	for t: Dictionary in trees:
		var kind := String(t["kind"])
		if kind == "under":
			continue
		_dot(img, t["x"], t["z"], x0, z0, px, Color(0.0, 0.35, 0.0), 2 if kind == "tree" else 3)
	for f: Dictionary in feet:
		var q2: Vector2 = f["p"]
		_dot(img, q2.x, q2.y, x0, z0, px, Color(0.15, 0.15, 0.15), 1)
	# 主路中心線
	var s := 0.0
	while s <= lib.main.length:
		var cp := lib.main.pos_at(s)
		_dot(img, cp.x, cp.y, x0, z0, px, Color(1, 1, 1), 0)
		s += 1.0
	img.save_png(out)
	_forest_stats(lib, fp)
	_road_light(lib, fp, feet)
	print("[probe] %s %dx%d  樹冠 %d 棵、岩腳 %d 處" % [out, W, H, int(ctx["n_crowns"]), int(ctx["n_rocks"])])
	print("[probe] 進度十分位（n＝離路心 6 m 內、f＝以外；只算 play_rect 內）：格數｜壓實土 礫 泥 落葉 岩 苔均值｜草")
	var keys := dec.keys()
	keys.sort()
	for k in keys:
		var d2: Array = dec[k]
		var n := float(d2[0])
		print("   %s  %5d｜土 %4.1f%% 礫 %4.1f%% 泥 %4.1f%% 葉 %4.1f%% 岩 %4.1f%% 苔 %.2f｜草 %4.1f%%" % [k, int(n), d2[1] / n * 100.0, d2[2] / n * 100.0, d2[3] / n * 100.0, d2[4] / n * 100.0, d2[5] / n * 100.0, d2[6] / n, d2[7] / n * 100.0])
	quit(0)


## 路面日照（10:00 的太陽）：沿主路每 1 m 取 3 點（中心、左右各 1.5 m），朝太陽射線對『樹冠球體』求交。
## 樹冠球：中心高 0.62×樹高，半徑 0.35×樹冠寬（不含半透明葉隙，所以是偏保守的陰影）。S01（含背景林）＋S02（越過接縫的）樹都算。
## 輸出每 10 m 窗的受光比例，並與 V1.3 原版（replay 模式）對比；另輸出中心線最長連續暗段。
func _road_light(lib, fp, feet: Array) -> void:
	var sd: Array = (lib.L["forest"]["s01_candidate"] as Dictionary)["sun_dir"]       # 10:00 的 Main/Sun（daynight.gd），layout 的值
	var sun := Vector3(float(sd[0]), float(sd[1]), float(sd[2])).normalized()
	var fp0 := ForestPlanner.new()
	fp0.setup(lib, feet)
	(fp0._fcfg["s01_candidate"] as Dictionary)["mode"] = "replay"
	fp0.plan()
	var s0f: float = lib.st_s("village")
	var Lf: float = lib.st_s("s01_s02") - s0f
	var res := {}
	for tag in ["原版", "新版"]:
		var plan_trees: Array = fp0.trees if tag == "原版" else fp.trees
		var crowns: Array = []
		for t: Dictionary in plan_trees:
			var kind := String(t["kind"])
			if kind != "tree" and kind != "pin" and kind != "landmark":
				continue
			if float(t["z"]) < -150.0 or float(t["z"]) > 30.0:
				continue
			var k: Dictionary = fp.kit[String(t["id"])]
			var h := float(k["h"]) * float(t["s"])
			var r := maxf(float(k["wx"]) * float(t["s"]) * 0.5 * 0.7, 1.0)
			crowns.append([Vector3(float(t["x"]), float(t["y"]) + 0.62 * h, float(t["z"])), r])
		var win := {}
		var run_cur := 0.0
		var run_max := 0.0
		var run_at := 0.0
		var s := 0.0
		while s <= Lf:
			var c: Vector2 = lib.main.pos_at(s0f + s)
			var tg: Vector2 = lib.main.tan_at(s0f + s)
			var rv := Vector2(-tg.y, tg.x)
			var center_lit := true
			for off in [-1.5, 0.0, 1.5]:
				var q: Vector2 = c + rv * off
				var o := Vector3(q.x, lib.h_at(q.x, q.y) + 0.3, q.y)
				var lit := true
				for cr: Array in crowns:
					var cc: Vector3 = cr[0]
					if absf(cc.x - o.x) > 30.0 or absf(cc.z - o.z) > 30.0:
						continue
					var oc := cc - o
					var tt := oc.dot(sun)
					if tt < 0.0:
						continue
					if oc.length_squared() - tt * tt < float(cr[1]) * float(cr[1]):
						lit = false
						break
				var w := int(s / 10.0)
				if not win.has(w):
					win[w] = [0, 0]
				win[w][0] += 1
				win[w][1] += 1 if lit else 0
				if off == 0.0:
					center_lit = lit
			if center_lit:
				run_cur = 0.0
			else:
				run_cur += 1.0
				if run_cur > run_max:
					run_max = run_cur
					run_at = s
			s += 1.0
		res[tag] = {"win": win, "run": run_max, "at": run_at}
	var line0 := "[light] 路面受光比例（每 10 m 窗；u 從村口 0 → 接縫 1）："
	var l_old := ""
	var l_new := ""
	for w in range(0, 12):
		var a: Array = res["原版"]["win"].get(w, [1, 0])
		var b: Array = res["新版"]["win"].get(w, [1, 0])
		l_old += " %3d" % int(round(100.0 * float(a[1]) / float(a[0])))
		l_new += " %3d" % int(round(100.0 * float(b[1]) / float(b[0])))
	print(line0)
	print("[light]   原版 %%：%s   最長連續暗段 %.0f m（約在 s=%.0f）" % [l_old, float(res["原版"]["run"]), float(res["原版"]["at"])])
	print("[light]   新版 %%：%s   最長連續暗段 %.0f m（約在 s=%.0f）" % [l_new, float(res["新版"]["run"]), float(res["新版"]["at"])])


func _forest_stats(lib, fp) -> void:
	var s0f: float = lib.st_s("village")
	var Lf: float = lib.st_s("s01_s02") - s0f
	var corridor: Array = []
	var third := [0, 0, 0]
	var under_third := [0, 0, 0]
	var close_road := 0
	var min_clear := 99.0
	var heights: Array = []
	var species := {}
	var n_all := 0
	var n_tree := 0
	var n_under := 0
	var n_pin := 0
	for t: Dictionary in fp.trees:
		if String(t["scene"]) != "S01":
			continue
		n_all += 1
		var kind := String(t["kind"])
		match kind:
			"tree": n_tree += 1
			"under": n_under += 1
			_: n_pin += 1
		var p := Vector2(float(t["x"]), float(t["z"]))
		var qq: Dictionary = lib.main.q(p)
		var uu := (float(qq["s"]) - s0f) / Lf
		if kind == "tree" and lib.mask_sdf(p) < 6.0 and uu > 0.02 and uu < 1.0:
			corridor.append(p)
			third[clampi(int(uu * 3.0), 0, 2)] += 1
			var dedge: float = lib.sample_arr(lib.DM, p.x, p.y) - lib.sample_arr(lib.WM, p.x, p.y) - float(t["r"])
			min_clear = minf(min_clear, dedge)
			if dedge < 1.5:
				close_road += 1
			heights.append(float((fp.kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"]))
			species[String(t["id"])] = int(species.get(String(t["id"]), 0)) + 1
		elif kind == "under" and uu > 0.02 and uu < 1.0:
			under_third[clampi(int(uu * 3.0), 0, 2)] += 1
	var nn: Array = []
	for i in corridor.size():
		var best := 1e9
		for j in corridor.size():
			if i != j:
				best = minf(best, (corridor[i] as Vector2).distance_to(corridor[j]))
		nn.append(best)
	nn.sort()
	heights.sort()
	var q := func(a: Array, f: float) -> float: return snappedf(float(a[clampi(int(float(a.size()) * f), 0, a.size() - 1)]), 0.1) if a.size() > 0 else -1.0
	print("[forest] S01 總 %d 筆＝樹 %d＋林下 %d＋釘點 %d（目標 380）" % [n_all, n_tree, n_under, n_pin])
	print("[forest] 路廊內的樹 %d 棵（村緣／中段／深處＝%s）、林下（%s）" % [corridor.size(), str(third), str(under_third)])
	print("[forest] 路廊樹 最近鄰 m（0/10/25/50/75/90 %%）：%s   （原版 2.7/4.0/4.3/5.2/6.2/9.5＝等距）" % str([q.call(nn, 0.0), q.call(nn, 0.1), q.call(nn, 0.25), q.call(nn, 0.5), q.call(nn, 0.75), q.call(nn, 0.9)]))
	print("[forest] 路廊樹 樹高 m（min/25/50/75/max）：%s   樹幹離路緣最近 %.2f m、< 1.5 m 的 %d 棵" % [str([q.call(heights, 0.0), q.call(heights, 0.25), q.call(heights, 0.5), q.call(heights, 0.75), q.call(heights, 0.999)]), min_clear, close_road])
	print("[forest] 路廊樹種（%d 種）：%s" % [species.size(), str(species)])


func _dot(img: Image, wx: float, wz: float, x0: float, z0: float, px: float, col: Color, r: int) -> void:
	var cx := int((wx - x0) / px)
	var cy := int((wz - z0) / px)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var xx := cx + dx
			var yy := cy + dy
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height() and dx * dx + dy * dy <= r * r + 1:
				img.set_pixel(xx, yy, col)
