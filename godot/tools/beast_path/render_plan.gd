extends SceneTree
## 獸道 平面圖／高度剖面渲染（唯讀，審圖與調參用）
##   godot --headless --path godot --script res://tools/beast_path/render_plan.gd -- --out=<dir/> [--ppm=3] [--nocache]
## 產出：plan_base.png（山影＋等高線＋路／溪／鋪石／玩區），profile.txt（主路逐 10 m 剖面與統計）
const BP := preload("res://tools/beast_path/bp_lib.gd")

var lib: BP
var out := "res://../docs/art_review/beast_path_v01/"
var ppm := 3


func _initialize() -> void:
	var use_cache := true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--ppm="):
			ppm = int(a.trim_prefix("--ppm="))
		elif a == "--nocache":
			use_cache = false
		elif a.begins_with("--crop="):
			var v := a.trim_prefix("--crop=").split(",")
			crop = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	if not out.ends_with("/"):
		out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	lib = BP.new()
	lib.setup(true, use_cache)
	_render()
	_profile()
	quit(0)


var crop := Rect2()


func _render() -> void:
	var xr: Array = lib.L["terrain"]["x_range"]
	var zr: Array = lib.L["terrain"]["z_range"]
	var x0 := float(xr[0])
	var z0 := float(zr[0])
	var wx := float(xr[1]) - x0
	var wz := float(zr[1]) - z0
	if crop.size.x > 0.0:
		x0 = crop.position.x
		z0 = crop.position.y
		wx = crop.size.x
		wz = crop.size.y
	var W := int(wx * ppm)
	var Hh := int(wz * ppm)
	var hmap := PackedFloat32Array()
	hmap.resize(W * Hh)
	var cls := PackedByteArray()
	cls.resize(W * Hh)
	for py in Hh:
		for px in W:
			var x := x0 + (px + 0.5) / ppm
			var z := z0 + (py + 0.5) / ppm
			hmap[py * W + px] = lib.h_at(x, z)
			var c := 0
			var dm := lib.sample_arr(lib.DM, x, z)
			var wm := lib.sample_arr(lib.WM, x, z)
			if dm <= wm:
				c = 1
			if lib.sample_arr(lib.DB, x, z) <= 0.0:
				c = 4
			if lib.sample_arr(lib.PV, x, z) > 0.5:
				c = 2
			if lib.sample_arr(lib.DS, x, z) <= 0.0:
				c = 3
			cls[py * W + px] = c
	var img := Image.create(W, Hh, false, Image.FORMAT_RGB8)
	var Ldir := Vector3(-0.55, 0.65, -0.52).normalized()    # 光自西北上方
	var cell_m := 1.0 / ppm
	for py in Hh:
		for px in W:
			var h := hmap[py * W + px]
			var hx := hmap[py * W + mini(px + 1, W - 1)] - hmap[py * W + maxi(px - 1, 0)]
			var hz := hmap[mini(py + 1, Hh - 1) * W + px] - hmap[maxi(py - 1, 0) * W + px]
			var n := Vector3(-hx * 2.0, 2.0 * cell_m * 2.0, -hz * 2.0).normalized()    # 垂直誇張 2×
			var sh := clampf(n.dot(Ldir), 0.15, 1.0)
			var t := clampf((h + 2.0) / 40.0, 0.0, 1.0)
			var base := Color(0.20, 0.30, 0.16).lerp(Color(0.62, 0.66, 0.46), t)
			var x := x0 + (px + 0.5) / ppm
			var z := z0 + (py + 0.5) / ppm
			var col := base
			match cls[py * W + px]:
				1: col = Color(0.72, 0.58, 0.36)
				2: col = Color(0.66, 0.64, 0.60)
				3: col = Color(0.20, 0.45, 0.80)
				4: col = Color(0.78, 0.66, 0.44)
			col = col * (0.35 + 0.75 * sh)
			var inside := lib.inside_play(Vector2(x, z))
			if not inside:
				col = col.darkened(0.45)
			else:
				# 玩區內坡度警示（真實坡度，不含垂直誇張）
				var slope := rad_to_deg(atan(Vector2(hx, hz).length() / (2.0 * cell_m)))
				if slope > 40.0:
					col = col.lerp(Color(1, 0.1, 0.1), 0.65)
				elif slope > 30.0:
					col = col.lerp(Color(1, 0.85, 0.1), 0.40)
			# 2 m 等高線
			var h_r := hmap[py * W + mini(px + 1, W - 1)]
			var h_d := hmap[mini(py + 1, Hh - 1) * W + px]
			if floor(h / 2.0) != floor(h_r / 2.0) or floor(h / 2.0) != floor(h_d / 2.0):
				col = col.darkened(0.22)
			img.set_pixel(px, py, col)
	# 疊線
	for r: Dictionary in lib.rects:
		_rect(img, r["rect"], Color(1, 0.95, 0.4), x0, z0)
	var ac := lib.arena_c()
	_circle(img, ac, float(lib.L["boss_arena"]["r_effective"]), Color(1.0, 0.45, 0.2), x0, z0)
	var name := "plan_base.png" if crop.size.x <= 0.0 else "plan_crop_%d_%d.png" % [int(crop.position.x), int(crop.position.y)]
	img.save_png(out + name)
	print("[plan] %s  %dx%d" % [out + name, W, Hh])


func _px(p: Vector2, x0: float, z0: float) -> Vector2i:
	return Vector2i(int((p.x - x0) * ppm), int((p.y - z0) * ppm))


func _dot(img: Image, p: Vector2i, c: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
		img.set_pixelv(p, c)


func _rect(img: Image, rc: Rect2, c: Color, x0: float, z0: float) -> void:
	var n := int((rc.size.x + rc.size.y) * 2.0 * ppm)
	for i in n:
		var t := float(i) / float(n)
		var per := (rc.size.x + rc.size.y) * 2.0
		var d := t * per
		var p: Vector2
		if d < rc.size.x:
			p = rc.position + Vector2(d, 0)
		elif d < rc.size.x + rc.size.y:
			p = rc.position + Vector2(rc.size.x, d - rc.size.x)
		elif d < 2.0 * rc.size.x + rc.size.y:
			p = rc.position + Vector2(rc.size.x - (d - rc.size.x - rc.size.y), rc.size.y)
		else:
			p = rc.position + Vector2(0, rc.size.y - (d - 2.0 * rc.size.x - rc.size.y))
		_dot(img, _px(p, x0, z0), c)


func _circle(img: Image, ctr: Vector2, r: float, c: Color, x0: float, z0: float) -> void:
	var n := int(TAU * r * ppm * 2.0)
	for i in n:
		var a := TAU * float(i) / float(n)
		_dot(img, _px(ctr + Vector2(cos(a), sin(a)) * r, x0, z0), c)


func _profile() -> void:
	var m: BP.Poly = lib.main
	var lines: PackedStringArray = []
	lines.append("# 主路剖面（每 10 m）  s | 中心線 (x,z) | 路面 y | 地形 y(中心) | 縱坡° | 左/右 8 m 地形高差 | 半寬 | 最大橫坡°(±半寬+1)")
	var s := 0.0
	var prev_y := lib.h_at(m.pos_at(0.0).x, m.pos_at(0.0).y)
	var max_grade := 0.0
	var worst_s := 0.0
	while s <= m.length + 0.01:
		var p := m.pos_at(s)
		var t := m.tan_at(s)
		var r := BP.right_of(t)
		var yc := lib.h_at(p.x, p.y)
		var yl := lib.h_at(p.x - r.x * 8.0, p.y - r.y * 8.0)
		var yr := lib.h_at(p.x + r.x * 8.0, p.y + r.y * 8.0)
		var grade := 0.0
		if s > 0.0:
			grade = rad_to_deg(atan2(yc - prev_y, 10.0))
		prev_y = yc
		if absf(grade) > absf(max_grade):
			max_grade = grade
			worst_s = s
		var cross_max := 0.0
		var hw := m.w_at(s) * 0.5 + 1.0
		for k in range(-4, 5):
			var q := p + r * (hw * float(k) / 4.0)
			cross_max = maxf(cross_max, lib.slope_deg_at(q.x, q.y))
		lines.append("%6.1f | (%6.1f,%7.1f) | %5.2f | %5.2f | %5.1f | %+5.2f / %+5.2f | %.2f | %.1f" % [s, p.x, p.y, m.y_at(s), yc, grade, yl - yc, yr - yc, m.w_at(s) * 0.5, cross_max])
		s += 10.0
	lines.append("# 最大縱坡 %.1f° @ s=%.0f" % [max_grade, worst_s])
	# 全區統計：玩區內最大坡度（排除懸崖特徵的 8 m 內）
	var mx := 0.0
	var mx_at := Vector2.ZERO
	var cnt_over := 0
	var cnt_all := 0
	var z := -450.0
	while z <= 10.0:
		var x := -80.0
		while x <= 80.0:
			var p2 := Vector2(x, z)
			if lib.mask_sdf(p2) < -6.0:
				cnt_all += 1
				var sd := lib.slope_deg_at(x, z)
				if sd > float(lib.lim["play_slope_deg_max"]):
					cnt_over += 1
				if sd > mx:
					mx = sd
					mx_at = p2
			x += 2.0
		z += 2.0
	lines.append("# 玩區內（距遮罩邊 > 6 m）最大坡度 %.1f° @ (%.0f, %.0f)；超過 %.0f° 的格點 %d / %d" % [mx, mx_at.x, mx_at.y, float(lib.lim["play_slope_deg_max"]), cnt_over, cnt_all])
	# 溪：深度（周邊 12 m 內最高地形 − 床）
	for id: String in lib.streams:
		var st: BP.Poly = lib.streams[id]
		var ss := 0.0
		lines.append("# 溪 %s：s | (x,z) | 床 | 水面 | 兩岸 6 m 外地形高（左/右） | 較低岸到水面深" % id)
		while ss <= st.length + 0.01:
			var sp := st.pos_at(ss)
			var stn := st.tan_at(ss)
			var sr := BP.right_of(stn)
			var hl_ := lib.h_at(sp.x - sr.x * (st.w_at(ss) * 0.5 + 6.0), sp.y - sr.y * (st.w_at(ss) * 0.5 + 6.0))
			var hr_ := lib.h_at(sp.x + sr.x * (st.w_at(ss) * 0.5 + 6.0), sp.y + sr.y * (st.w_at(ss) * 0.5 + 6.0))
			var wy := lib.water_y_at_stream(id, ss)
			lines.append("  %6.1f | (%6.1f,%7.1f) | %5.2f | %5.2f | %5.2f / %5.2f | %4.2f" % [ss, sp.x, sp.y, st.bed_at(ss), wy, hl_, hr_, minf(hl_, hr_) - wy])
			ss += 20.0
	var f := FileAccess.open(out + "profile.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("[plan] profile.txt（最大縱坡 %.1f° @ s=%.0f；玩區最大坡 %.1f°）" % [max_grade, worst_s, mx])
