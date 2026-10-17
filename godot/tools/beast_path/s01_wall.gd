extends RefCounted
## 獸道 S01 R2：谷壁點綴（valley wall dressing）——規劃＋建造。
##
## 為什麼：R1 審圖的第一優先問題是『谷壁整面灰褐、像一堵連續的牆』。R1 試過兩輪只調地表 shader，改善有限；
## 使用者 R2 裁定：不要再只靠 shader，問題是『構圖』——大面坡缺少實體的打斷與自然細節。
## 而且量化顯示 R1 自己讓谷壁更禿：谷緣外 0–6 m 的樹 V1.3 有 35 棵、R1 只剩 14 棵（路廊樹被重排到路邊群落）。
##
## 做法（全部只在 S01、只在谷壁帶；不改地形高度與碰撞、不改 S02–S04、不改共用 bp_ground.*／bp_rock.*）：
##   1. 岩露頭（formation）：主岩＋0–3 顆衛星岩，半埋在陡坡（坡度越陡越可能是岩、低頻噪聲決定『哪一段坡有岩』，
##      所以有的坡段一組接一組、有的坡段整段沒有；間距不固定）。朝向：正面朝下坡，上方向在『鉛直』與『坡面法線』之間，
##      所以像從坡裡長出來的岩，不是擺在坡上的石頭；高度位置隨機，不排成水平層帶。
##   2. 坡腳碎石（debris）：只在岩露頭的正下方坡腳（崩落的方向性），2–5 顆小石，不沿坡腳整圈撒。
##   3. 土袋（pocket）：較緩（≤ 46°）的坡段或岩旁（岩擋住的土）才有土、才長植物；植物在 s01_forest 種（算進 380 總量），
##      地表由 s01_ground 在土袋內把『岩／土坡』換成草＋落葉＋苔（頂點 CUSTOM0.a）。
##   4. 露根（roots）：坡上的樹在下坡側露出幾條根（沿用 prop_builder._root_run，不另寫一套）。
## 碰撞：只有玩家走得到的岩（從主路出發、坡度 ≤ 50° 連通的格子）而且凸出地面 > 0.45 m 才有凸包碰撞；
##       陡坡上走不到的岩、碎石、露根都不加碰撞（使用者：不要加不必要的碰撞物）。
## 同 seed 同結果（亂數只由 zone seed＋salt 決定）。規劃是純函式：只讀 lib／fp 的現況，不寫 fp。

const RockBuilder := preload("res://tools/beast_path/rock_builder.gd")
const MESH_DIR := "res://maps/beast_path/gen/s01_wall/"
const SECTORS := 16


static func _rng(seed_: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_ & 0x7FFFFFFF
	return r


static func _noise(seed_: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_ & 0x7FFFFFFF
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	return n


## 地形梯度（每 m 的高差）：x、z 兩個分量
static func grad(lib, p: Vector2) -> Vector2:
	return Vector2(lib.h_at(p.x + 0.5, p.y) - lib.h_at(p.x - 0.5, p.y), lib.h_at(p.x, p.y + 0.5) - lib.h_at(p.x, p.y - 0.5))


## 離主路路緣的距離（m）
static func path_edge_d(lib, p: Vector2) -> float:
	return lib.sample_arr(lib.DM, p.x, p.y) - lib.sample_arr(lib.WM, p.x, p.y)


## 玩家走得到的格子（1 m）：從主路中心線出發，四鄰、坡度 ≤ max_deg 的格子連通。只算 S01 tile。
static func reach_map(lib, max_deg: float, z0 := -100, nzr := 131, st0 := "village", st1 := "s01_s02") -> Dictionary:
	var x0 := -110
	var nxr := 221
	var ok := PackedByteArray()
	ok.resize(nxr * nzr)
	var walk := PackedByteArray()
	walk.resize(nxr * nzr)
	for j in nzr:
		for i in nxr:
			walk[j * nxr + i] = 1 if lib.slope_deg_at(float(x0 + i), float(z0 + j)) <= max_deg else 0
	var q: Array = []
	var s0: float = lib.st_s(st0)
	var s1: float = lib.st_s(st1)
	var s := s0
	while s <= s1:
		var c: Vector2 = lib.main.pos_at(s)
		var ii := int(round(c.x)) - x0
		var jj := int(round(c.y)) - z0
		if ii >= 0 and ii < nxr and jj >= 0 and jj < nzr and walk[jj * nxr + ii] == 1 and ok[jj * nxr + ii] == 0:
			ok[jj * nxr + ii] = 1
			q.append(Vector2i(ii, jj))
		s += 1.0
	var head := 0
	while head < q.size():
		var cc: Vector2i = q[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cc + d
			if n.x < 0 or n.x >= nxr or n.y < 0 or n.y >= nzr:
				continue
			var k := n.y * nxr + n.x
			if ok[k] == 1 or walk[k] == 0:
				continue
			ok[k] = 1
			q.append(n)
	return {"x0": x0, "z0": z0, "nx": nxr, "nz": nzr, "ok": ok, "n": q.size()}


static func reachable(rm: Dictionary, p: Vector2) -> bool:
	var i := int(round(p.x)) - int(rm["x0"])
	var j := int(round(p.y)) - int(rm["z0"])
	if i < 0 or i >= int(rm["nx"]) or j < 0 or j >= int(rm["nz"]):
		return false
	return (rm["ok"] as PackedByteArray)[j * int(rm["nx"]) + i] == 1


## 這一點周圍有沒有樹幹（S01 已在 fp.trees 的＋S02 越過接縫的），回傳最近樹幹表面距離
static func _trunk_clear(fp, p: Vector2, extra: Array = []) -> float:
	var best := 1e9
	for t: Dictionary in fp.trees + extra:
		var tz := float(t["z"])
		if absf(tz - p.y) > 14.0:
			continue
		var kind := String(t["kind"])
		if kind != "tree" and kind != "pin" and kind != "landmark" and kind != "dead":
			continue
		var tr := float(t["r"]) if t.has("r") else float((fp.kit[String(t["id"])] as Dictionary)["r"]) * float(t["s"])
		var d := p.distance_to(Vector2(float(t["x"]), tz)) - tr
		best = minf(best, d)
	return best


static func _foot_clear(fp, p: Vector2) -> float:
	var best := 1e9
	for f: Dictionary in fp._foot:
		var q: Vector2 = f["p"]
		if absf(q.y - p.y) > 20.0:
			continue
		best = minf(best, p.distance_to(q) - float(f["r"]))
	return best


## 一般禁區（給岩、碎石、土袋中心用）：主路／支線／溪／鋪石／空地（農地、草地）／道具腳印
static func _site_ok(fp, p: Vector2, path_min: float, foot_min: float) -> bool:
	var lib = fp.lib
	if lib.scene_id_of_z(p.y) != "S01":
		return false
	if path_edge_d(lib, p) < path_min:
		return false
	if lib.sample_arr(lib.DB, p.x, p.y) < 3.0 or lib.sample_arr(lib.DS, p.x, p.y) < 3.0 or lib.sample_arr(lib.PV, p.x, p.y) > 0.05:
		return false
	if _foot_clear(fp, p) < foot_min:
		return false
	return true


## 岩的大小（半徑上限）也要整顆留在 S01：南端離 S01/S02 接縫（z＝−100）至少 1 m（大岩盤沿落水線可長到 9 m，只看中心會越過接縫）
static func _in_scope(p: Vector2, half: float) -> bool:
	return p.y - half * 1.45 >= -98.5 and p.y + half * 1.45 <= 29.0 and absf(p.x) + half * 1.45 <= 107.0


# ================================================================= 規劃
## wcfg＝layout.forest.s01_candidate.r2.wall。回傳 {rocks: [...], pockets: [...], info: {...}, reach: reach_map}
static func plan(fp, wcfg: Dictionary, seed_: int, extra: Array = []) -> Dictionary:
	var lib = fp.lib
	var rg := _rng(seed_ * 7 + 101)
	var n_out := _noise(seed_ + 811, float(wcfg.get("outcrop_freq", 0.045)))
	var n_soil := _noise(seed_ + 977, float(wcfg.get("soil_freq", 0.06)))
	var sdf_r: Array = wcfg.get("sdf", [0.8, 12.0])
	var z_r: Array = wcfg.get("z", [-95.0, 26.0])
	var rm := reach_map(lib, float(wcfg.get("reach_deg", 50.0)))
	var s0: float = lib.st_s("village")
	var Ls: float = lib.st_s("s01_s02") - s0
	var on_r: Array = wcfg.get("outcrop_noise", [0.30, 0.72])
	var vis_floor := float(wcfg.get("vis_floor", 1.0))
	var seg_tile := float(wcfg.get("seg_tile", 20.0))
	var n_h := _noise(seed_ + 1301, float(wcfg.get("height_freq", 0.03)))
	var hb_r: Array = wcfg.get("height_pref", [2.0, 16.0])
	var hb_w := float(wcfg.get("height_w", 4.0))
	var hb_floor := float(wcfg.get("height_floor", 1.0))
	# ---- 1) 候選格子。vis＝這格坡面「面向主路、在玩家常看的距離」的程度（下坡方向朝路 × 離路 12–55 m）——
	#      R1 審圖的問題是「玩家看得到的那一大面坡」，所以候選權重偏向看得到的坡面（vis_floor＝看不到的坡面保留的權重）。
	#      seg＝世界座標 seg_tile m 見方的一格：每格坡的岩組／主岩盤／土袋有上限，避免村口那面長牆把配額全吃光、其他看得到的坡面整段空白
	#      （用世界格而不是沿路進度：村口的北牆和東壁最近的路點都是 u≈0，用進度分段會被算成同一段）。
	var rock_c: Array = []
	var pock_c: Array = []
	var gul_c: Array = []
	var gmin := float(wcfg.get("gully_conc", 99.0))
	var z := float(z_r[0])
	while z <= float(z_r[1]):
		var x := -106.0
		while x <= 106.0:
			var p := Vector2(x, z)
			var sdf: float = lib.mask_sdf(p)
			var sl: float = lib.slope_deg_at(x, z) if sdf >= float(sdf_r[0]) else 0.0
			# 陡壁（> 54°）的上半段也算谷壁帶（到 steep_sdf_max）：R1 審圖那面看得到的坡高 20 m，上半段才是大面裸露的地方
			if sdf >= float(sdf_r[0]) and (sdf <= float(sdf_r[1]) or (sl > 54.0 and sdf <= float(wcfg.get("steep_sdf_max", sdf_r[1])))):
				var no := 0.5 + 0.5 * n_out.get_noise_2d(x, z)
				var ns := 0.5 + 0.5 * n_soil.get_noise_2d(x, z)
				var qq: Dictionary = lib.main.q(p)
				var tp: Vector2 = (qq["pos"] as Vector2) - p
				var dpath := tp.length()
				var gc := grad(lib, p)
				var ddc := (-gc).normalized() if gc.length() > 1e-4 else Vector2.ZERO
				var vis := clampf(ddc.dot(tp / maxf(dpath, 0.01)), 0.0, 1.0) * smoothstep(10.0, 20.0, dpath) * (1.0 - smoothstep(55.0, 80.0, dpath))
				var vk := lerpf(vis_floor, 1.0, vis)
				var seg := "%d,%d" % [int(floor(x / seg_tile)), int(floor(z / seg_tile))]
				# 每一區（低頻噪聲）偏好的露岩高度（谷緣外 pref m）不同：最陡的那條等高線不會整條排滿岩（審圖：岩在同一高度排成一條帶）
				var pref := lerpf(float(hb_r[0]), float(hb_r[1]), 0.5 + 0.5 * n_h.get_noise_2d(x, z))
				var hk := lerpf(hb_floor, 1.0, exp(-pow((sdf - pref) / hb_w, 2.0)))
				var sr := smoothstep(34.0, 54.0, sl) * smoothstep(float(on_r[0]), float(on_r[1]), no) * vk * hk
				if sr > 0.02:
					rock_c.append([p, sr, sl, sdf, seg, vis])
				var sp := (1.0 - smoothstep(40.0, 47.0, sl)) * smoothstep(20.0, 28.0, sl) * smoothstep(0.32, 0.70, ns) * vk
				if sp > 0.02 and sdf <= minf(float(wcfg.get("pocket_sdf_max", 9.0)), float(sdf_r[1])):
					pock_c.append([p, sp, sl, sdf, seg, vis])
				# 沖溝（gully）：陡壁上沿等高線方向是凹的地方（兩側比中間高）——水與土往這裡集中，植物沿沖溝往下長成一條縱向的綠；
				# 這是陡坡上合理長植物的第二種地方（第一種是岩後的土），而且方向是縱向的，不會形成水平帶
				if sl > 44.0 and sl < 62.0 and gmin < 50.0:
					var cc := Vector2(-ddc.y, ddc.x) * 2.0
					var conc: float = 0.5 * (lib.h_at(x + cc.x, z + cc.y) + lib.h_at(x - cc.x, z - cc.y)) - lib.h_at(x, z)
					var sg := smoothstep(gmin, gmin + 0.6, conc) * (1.0 - smoothstep(58.0, 62.0, sl)) * smoothstep(0.25, 0.65, ns) * vk
					if sg > 0.02:
						gul_c.append([p, sg, sl, sdf, seg, vis, conc])
			x += 1.0
		z += 1.0
	# 加權隨機排序（key＝u^(1/w)：權重大的較常排前面，但不是固定的『最高分優先』→ 不會整齊地每個最陡點都放）
	for c: Array in rock_c:
		c.append(pow(rg.randf(), 1.0 / float(c[1])))
	rock_c.sort_custom(func(a: Array, b: Array) -> bool: return float(a[6]) > float(b[6]))
	# 第一輪：主岩盤（major）。只從「面向主路的陡壁中段」挑（坡 > 54°、vis ≥ major_vis、谷緣外 4–16 m），每段坡最多一處；
	# 先放主岩盤，再放一般岩組（一般岩組要和它保持間距）→ 看得到的大面陡壁一定先拿到一處大片露岩，而不是被小岩組搶光位置
	var major_c: Array = []
	for c5: Array in rock_c:
		if float(c5[2]) > 54.0 and float(c5[5]) >= float(wcfg.get("major_vis", 2.0)) and float(c5[3]) >= 4.0 and float(c5[3]) <= 16.0:
			var mc: Array = c5.duplicate()
			mc[6] = pow(rg.randf(), 1.0 / maxf(float(c5[5]) * smoothstep(54.0, 66.0, float(c5[2])), 0.02))
			mc.append(true)
			major_c.append(mc)
	major_c.sort_custom(func(a: Array, b: Array) -> bool: return float(a[6]) > float(b[6]))
	var order: Array = major_c + rock_c
	# ---- 2) 岩露頭
	var forms: Array = []
	var rocks: Array = []
	var sp_r: Array = wcfg.get("spacing", [8.0, 19.0])
	var n_max := int(wcfg.get("formations", 20))
	var path_min := float(wcfg.get("rock_path_min", 6.0))
	var diag := {"cand": rock_c.size(), "site": 0, "spacing": 0, "trunk": 0, "rejected_sat": 0, "seg_full": 0}
	var seg_max := int(wcfg.get("seg_formations", 99))
	var seg_n := {}
	var seg_major := {}
	var ledges: Array = []
	for c2: Array in order:
		if forms.size() >= n_max:
			break
		var p2: Vector2 = c2[0]
		var segk := String(c2[4])
		var force_major := c2.size() > 7
		if force_major and (int(seg_major.get(segk, 0)) >= 1 or seg_major.size() >= int(wcfg.get("majors", 0))):
			continue
		if int(seg_n.get(segk, 0)) >= seg_max:
			diag["seg_full"] += 1
			continue
		var my_sp := lerpf(float(sp_r[0]), float(sp_r[1]), rg.randf())
		var close := false
		for f: Dictionary in forms:
			if p2.distance_to(f["c"]) < 0.5 * (my_sp + float(f["sp"])):
				close = true
				break
		if close:
			diag["spacing"] += 1
			continue
		if not _site_ok(fp, p2, path_min, 2.5):
			diag["site"] += 1
			continue
		var fi := forms.size()
		var g := grad(lib, p2)
		var dd := (-g).normalized() if g.length() > 1e-4 else Vector2(0, 1)       # 下坡方向（水平）
		var cont := Vector2(-dd.y, dd.x)                                            # 沿等高線
		# 陡（> 52°）的坡面：岩露頭大一點。更陡（> 56°）的多半是「岩肋」——沿坡的落水線拉長（d 3–6.5 m）、貼著坡面凸出（上方向接近坡面法線），
		# 讀起來是岩盤從坡裡露出來的一道肋，而不是擺在坡上的一顆圓石；也是打斷大面坡最有效的形狀（縱向，不是水平層帶）。
		var steep := float(c2[2]) > 52.0
		var rib := float(c2[2]) > 56.0 and rg.randf() < float(wcfg.get("rib_p", 0.0))
		var w := rg.randf_range(2.6, 5.0) if steep else rg.randf_range(1.7, 3.7)
		var main := {"w": w, "h": rg.randf_range(1.2, 2.6) if steep else rg.randf_range(1.0, 2.3), "d": rg.randf_range(1.5, 2.8) if steep else rg.randf_range(1.3, 2.4)}
		if rib:
			w = rg.randf_range(1.6, 3.4)
			main = {"w": w, "h": rg.randf_range(0.9, 1.9), "d": rg.randf_range(3.0, 6.5)}
		# 主岩盤（major）：面向主路、遠看（50–60 m）的大面陡壁上，每段坡最多一處大片露岩（寬 5–8 m、沿落水線 5–9 m、貼坡凸出 1.4–2.4 m）。
		# 遠處 2–5 m 的岩在畫面上只是幾個像素，打不斷那面坡；但也只給看得到的陡壁、每段最多一處（不是整面鋪岩）
		var major := force_major
		if major:
			rib = true
			w = rg.randf_range(5.0, 8.0)
			main = {"w": w, "h": rg.randf_range(1.4, 2.4), "d": rg.randf_range(5.0, 9.0)}
			seg_major[segk] = int(seg_major.get(segk, 0)) + 1
		if _trunk_clear(fp, p2, extra) < maxf(w, float(main["d"])) * 0.5 + 0.6:
			diag["trunk"] += 1
			continue
		if not _in_scope(p2, maxf(w, float(main["d"])) * 0.5):
			diag["site"] += 1
			continue
		seg_n[segk] = int(seg_n.get(segk, 0)) + 1
		var members: Array = [[p2, main, false]]
		var lean_main := rg.randf_range(0.65, 0.85) if rib else (rg.randf_range(0.30, 0.62) if steep else rg.randf_range(0.15, 0.45))
		var n_sat: int = [0, 1, 1, 2, 2, 3][rg.randi_range(0, 5)]
		for k in n_sat:
			var side := -1.0 if rg.randf() < 0.5 else 1.0
			var sz_k := rg.randf_range(0.32, 0.62)
			var sat := {"w": w * sz_k * rg.randf_range(0.8, 1.15), "h": float(main["h"]) * sz_k * rg.randf_range(0.8, 1.2), "d": float(main["d"]) * sz_k}
			var ang_s := deg_to_rad(rg.randf_range(-float(wcfg.get("sat_fan_deg", 0.0)), float(wcfg.get("sat_fan_deg", 0.0))))
			var sdir := (cont * cos(ang_s) + dd * sin(ang_s)).normalized()
			var q: Vector2 = p2 + sdir * side * (w * 0.5 + float(sat["w"]) * 0.5 + rg.randf_range(-0.2, 1.3)) + dd * rg.randf_range(-1.2, 1.1)
			if not _in_scope(q, maxf(float(sat["w"]), float(sat["d"])) * 0.5):
				diag["rejected_sat"] += 1
				continue
			if steep and maxf(float(sat["w"]), float(sat["d"])) < float(wcfg.get("sat_min_steep", 0.0)):
				diag["rejected_sat"] += 1
				continue
			if rib:
				q = p2 + dd * side * (float(main["d"]) * 0.5 + float(sat["d"]) * 0.5 + rg.randf_range(-0.3, 0.9)) + cont * rg.randf_range(-0.9, 0.9)
			if not _site_ok(fp, q, path_min - 1.0, 2.0) or _trunk_clear(fp, q, extra) < float(sat["w"]) * 0.55 + 0.45 or lib.slope_deg_at(q.x, q.y) < 26.0:
				diag["rejected_sat"] += 1
				continue
			members.append([q, sat, true])
		forms.append({"c": p2, "sp": my_sp, "dd": dd, "sdf": float(c2[3]), "slope": float(c2[2]), "n": members.size(), "seg": segk, "vis": float(c2[5]), "rib": rib, "major": major})
		# 岩後（上坡側）積的土：陡坡上唯一合理長植物的地方（岩擋住了土）。只給一部分岩組，所以不是每顆岩都戴一頂綠帽
		if float(c2[2]) > 46.0 and rg.randf() < float(wcfg.get("ledge_p", 0.0)):
			var lc: Vector2 = p2 - dd * (float(main["d"]) * 0.5 + rg.randf_range(0.4, 0.9)) + cont * rg.randf_range(-0.35, 0.35) * w
			ledges.append({"c": lc, "x": lc.x, "z": lc.y, "sp": 0.0, "R": rg.randf_range(1.0, 1.6), "slope": lib.slope_deg_at(lc.x, lc.y), "sdf": lib.mask_sdf(lc), "vis": float(c2[5]),
				"ledge": true, "form": forms.size() - 1, "seed": seed_ * 59 + forms.size() * 7877 + 9})
		for m: Array in members:
			var mp: Vector2 = m[0]
			var dims: Dictionary = m[1]
			var gq := grad(lib, mp)
			var ddq := (-gq).normalized() if gq.length() > 1e-4 else dd
			var slq := rad_to_deg(atan(gq.length()))
			rocks.append({
				"id": "s01wall_f%02d_%d" % [fi, rocks.size()], "kind": "outcrop", "form": fi, "sat": bool(m[2]), "embed": rg.randf_range(0.06, 0.22),
				"x": mp.x, "z": mp.y, "w": float(dims["w"]), "h": float(dims["h"]), "d": float(dims["d"]),
				"yaw": atan2(ddq.x, ddq.y) + rg.randf_range(-0.42, 0.42) * (0.4 if rib else 1.0), "lean_k": lean_main * rg.randf_range(0.9, 1.05), "slope": slq, "rib": rib,
				"roll": rg.randf_range(-0.14, 0.14), "moss": rg.randf_range(0.30, 0.70), "seed": seed_ * 31 + rocks.size() * 7919 + 13,
				"n": (11 if major else 8) if not bool(m[2]) else 6, "major": major and not bool(m[2]),
			})
		# ---- 坡腳碎石：從主岩往下坡走到坡腳（坡度 < 24° 或到谷底），只在那裡散 2–5 顆（崩落的方向性）
		if rg.randf() < float(wcfg.get("debris_p", 0.7)):
			var t := p2
			var steps := 0
			while steps < 30 and lib.slope_deg_at(t.x, t.y) >= 24.0 and lib.mask_sdf(t) > 0.2:
				t += dd * 0.5
				steps += 1
			var nd := rg.randi_range(2, 5)
			for k2 in nd:
				var along := rg.randf_range(-0.4, 2.6)
				var qd: Vector2 = t + dd * along + cont * rg.randf_range(-1.0, 1.0) * (0.8 + 0.5 * maxf(along, 0.0))   # 崩落錐：沿落水線往外、越外越寬
				var rr := rg.randf_range(0.13, 0.42)
				if not _site_ok(fp, qd, 2.2, 0.8) or _trunk_clear(fp, qd, extra) < rr + 0.4 or not _in_scope(qd, rr):
					continue
				var bad := false
				for r0: Dictionary in rocks:
					if Vector2(float(r0["x"]), float(r0["z"])).distance_to(qd) < rr + 0.5 * float(r0["w"]) + 0.15:
						bad = true
						break
				if bad:
					continue
				var gd := grad(lib, qd)
				rocks.append({
					"id": "s01wall_f%02d_d%d" % [fi, rocks.size()], "kind": "debris", "form": fi, "sat": true,
					"x": qd.x, "z": qd.y, "w": 2.0 * rr * rg.randf_range(0.85, 1.15), "h": 2.0 * rr * rg.randf_range(0.5, 0.8), "d": 2.0 * rr * rg.randf_range(0.75, 1.0),
					"yaw": rg.randf() * TAU, "lean_k": 0.6, "slope": rad_to_deg(atan(gd.length())), "roll": rg.randf_range(-0.2, 0.2),
					"moss": rg.randf_range(0.2, 0.55), "seed": seed_ * 31 + rocks.size() * 7919 + 17, "n": 4,
				})
	# ---- 3) 土袋（植物在 s01_forest 種）
	for c3: Array in pock_c:
		var near_rock := 99.0
		for f2: Dictionary in forms:
			near_rock = minf(near_rock, (c3[0] as Vector2).distance_to(f2["c"]))
		var bonus := 1.0 + 0.8 * (1.0 - smoothstep(2.5, 7.0, near_rock))        # 岩旁（岩擋住的土）較常有土
		c3[1] = clampf(float(c3[1]) * bonus, 0.0, 1.0)
		c3.append(pow(rg.randf(), 1.0 / float(c3[1])))
	pock_c.sort_custom(func(a: Array, b: Array) -> bool: return float(a[6]) > float(b[6]))
	var pseg_max := int(wcfg.get("seg_pockets", 99))
	var pseg_n := {}
	var pockets: Array = []
	var ps_r: Array = wcfg.get("pocket_spacing", [7.0, 15.0])
	var np_max := int(wcfg.get("pockets", 14))
	for c4: Array in pock_c:
		if pockets.size() >= np_max:
			break
		var p4: Vector2 = c4[0]
		var my_sp2 := lerpf(float(ps_r[0]), float(ps_r[1]), rg.randf())
		var close2 := false
		for pk: Dictionary in pockets:
			if p4.distance_to(pk["c"]) < 0.5 * (my_sp2 + float(pk["sp"])):
				close2 = true
				break
		if close2 or not _site_ok(fp, p4, float(wcfg.get("pocket_path_min", 5.0)), 2.0) or int(pseg_n.get(String(c4[4]), 0)) >= pseg_max:
			continue
		var on_rock := false
		for r1: Dictionary in rocks:
			if Vector2(float(r1["x"]), float(r1["z"])).distance_to(p4) < 0.5 * float(r1["w"]) + 0.8:
				on_rock = true
				break
		if on_rock:
			continue
		pseg_n[String(c4[4])] = int(pseg_n.get(String(c4[4]), 0)) + 1
		pockets.append({"c": p4, "x": p4.x, "z": p4.y, "sp": my_sp2, "R": rg.randf_range(2.0, 3.4), "slope": float(c4[2]), "sdf": float(c4[3]), "vis": float(c4[5]), "seed": seed_ * 53 + pockets.size() * 104729 + 5})
	# 沖溝的土袋：沿落水線兩個（上、下），每格最多一條、彼此與一般土袋保持距離
	var n_gully := 0
	for c6: Array in gul_c:
		c6.append(pow(rg.randf(), 1.0 / float(c6[1])))
	gul_c.sort_custom(func(a: Array, b: Array) -> bool: return float(a[7]) > float(b[7]))
	var gseg := {}
	var gs_r: Array = wcfg.get("gully_spacing", [10.0, 20.0])
	for c7: Array in gul_c:
		if n_gully >= int(wcfg.get("gullies", 0)):
			break
		var p7: Vector2 = c7[0]
		if gseg.has(String(c7[4])):
			continue
		var my_sp7 := lerpf(float(gs_r[0]), float(gs_r[1]), rg.randf())
		var bad7 := false
		for pk7: Dictionary in pockets:
			if p7.distance_to(pk7["c"]) < 0.5 * (my_sp7 + maxf(float(pk7["sp"]), 6.0)):
				bad7 = true
				break
		if not bad7:
			for r7: Dictionary in rocks:
				if Vector2(float(r7["x"]), float(r7["z"])).distance_to(p7) < 0.5 * maxf(float(r7["w"]), float(r7["d"])) + 1.2:
					bad7 = true
					break
		if bad7 or not _site_ok(fp, p7, float(wcfg.get("pocket_path_min", 5.0)), 2.0):
			continue
		var g7 := grad(lib, p7)
		var dd7 := (-g7).normalized() if g7.length() > 1e-4 else Vector2(0, 1)
		gseg[String(c7[4])] = true
		var R7 := rg.randf_range(1.3, 2.0)
		for k7 in 2:
			var c8: Vector2 = p7 + dd7 * (float(k7) * R7 * 1.7)
			pockets.append({"c": c8, "x": c8.x, "z": c8.y, "sp": my_sp7, "R": R7 * (1.0 if k7 == 0 else 0.8), "slope": lib.slope_deg_at(c8.x, c8.y), "sdf": lib.mask_sdf(c8),
				"vis": float(c7[5]), "ledge": true, "gully": true, "seed": seed_ * 61 + n_gully * 6151 + k7 * 37 + 3})
		n_gully += 1
	# 岩後的土（ledge）：不能落在道具腳印／路上（_site_ok），也不能壓到別的岩
	# 孤零零的小岩：一組岩只剩一顆露出（其餘整顆埋進地裡），而且露出不到 lonely_vis m——遠看是坡上一個貼上去的黑點，
	# 不是岩盤露頭。整組拿掉（含它的碎石與岩後小台）。大岩盤不拿。
	var dropped_forms := {}
	if float(wcfg.get("lonely_vis", 0.0)) > 0.0:
		var fstat := {}
		for r0: Dictionary in rocks:
			if String(r0["kind"]) != "outcrop":
				continue
			var vh := float(rock_geom(lib, r0)["vis_h"])
			var fs: Array = fstat.get(int(r0["form"]), [0, 0.0])
			if vh >= 0.35:
				fs[0] = int(fs[0]) + 1
				fs[1] = maxf(float(fs[1]), vh)
			fstat[int(r0["form"])] = fs
		for fi0: int in fstat:
			var fs2: Array = fstat[fi0]
			if not bool((forms[fi0] as Dictionary)["major"]) and int(fs2[0]) <= 1 and float(fs2[1]) < float(wcfg["lonely_vis"]):
				dropped_forms[fi0] = true
		rocks = rocks.filter(func(r9: Dictionary) -> bool: return not dropped_forms.has(int(r9["form"])))
	diag["lonely_dropped"] = dropped_forms.size()
	var skirts: Array = []
	var n_ledge := 0
	for lg: Dictionary in ledges:
		if dropped_forms.has(int(lg.get("form", -1))):
			continue
		var lp: Vector2 = lg["c"]
		if not _site_ok(fp, lp, float(wcfg.get("pocket_path_min", 5.0)), 1.5):
			continue
		var on_r2 := false
		for r3: Dictionary in rocks:
			if Vector2(float(r3["x"]), float(r3["z"])).distance_to(lp) < 0.5 * maxf(float(r3["w"]), float(r3["d"])) * 0.8:
				on_r2 = true
				break
		if on_r2:
			continue
		pockets.append(lg)
		n_ledge += 1
	var n_deb := 0
	for r2: Dictionary in rocks:
		if String(r2["kind"]) == "debris":
			n_deb += 1
	var segs := {}
	var n_rib := 0
	for f3: Dictionary in forms:
		segs[String(f3["seg"])] = int(segs.get(String(f3["seg"]), 0)) + 1
		if bool(f3["rib"]):
			n_rib += 1
	diag["ribs"] = n_rib
	diag["majors"] = seg_major.size()
	var info := {"formations": forms.size(), "rocks": rocks.size() - n_deb, "debris": n_deb, "pockets": pockets.size(), "ledges": n_ledge, "gullies": n_gully, "reach_cells": int(rm["n"]), "diag": diag, "form_segs": segs}
	return {"rocks": rocks, "pockets": pockets, "forms": forms, "info": info, "reach": rm, "face": wcfg.get("face", {}), "skirts": skirts}


## R3：指名岩組的局部修正（wcfg.r3_fix；使用者 S01 R3 第二優先：谷腳那組『疊石板』）。只動被點名的岩組，其他岩組逐顆不變。
## 在森林規劃『之後』才套用（s01_forest 交出 fp.s01_wall 前）：植物的擺放看到的仍是 R2 的岩 → 植被逐棵不變（總量 380、群落、櫻都不動）；
## 新岩與既有植物的衝突在 _apply_fix 裡檢查（衛星岩／碎石離樹幹、林下不足就不放）。
static func apply_r3_fixes(fp, wall: Dictionary, wcfg: Dictionary, seed_: int) -> Dictionary:
	var fixes: Array = wcfg.get("r3_fix", [])
	if fixes.is_empty():
		return wall
	var rocks: Array = wall["rocks"]
	var skirts: Array = []
	var infos: Array = []
	for fx: Dictionary in fixes:
		var res := _apply_fix(fp, wall["forms"], rocks, fx, seed_, [])
		rocks = res["rocks"]
		skirts.append_array(res["skirts"])
		infos.append(res["info"])
	wall["rocks"] = rocks
	wall["skirts"] = skirts
	(wall["info"] as Dictionary)["r3_fix"] = infos
	return wall


## 這一點離 S01 林下植物（灌木、羊齒…）的最近距離（_trunk_clear 只看樹幹）
static func _under_clear(fp, p: Vector2) -> float:
	var best := 1e9
	for t: Dictionary in fp.trees:
		if String(t["kind"]) != "under" or absf(float(t["z"]) - p.y) > 10.0:
			continue
		best = minf(best, p.distance_to(Vector2(float(t["x"]), float(t["z"]))))
	return best


## R3 指名岩組修正。fx＝{near:[x,z], r, main:{w,h,d,lean_k,yaw_add_deg,roll,embed,prm{}}, sats:[{along,down,w,h,d,lean_k,yaw_add_deg,roll,embed,prm{}}], debris:[{along,down,r}], skirt:{R,scree_R,scree_down}}
##   along＝沿等高線（以主岩寬為單位）、down＝沿下坡（m，正＝往下坡）。原本的衛星岩全部換掉（R2 的衛星岩是順落水線往下疊的板，正是『疊石板』的來源）。
##   回傳 {rocks, skirts, info}；skirts 只給地表用（岩腳的土、苔、落葉與下坡碎石扇），不種植物（植被總量不變）。
static func _apply_fix(fp, forms: Array, rocks: Array, fx: Dictionary, seed_: int, extra: Array) -> Dictionary:
	var lib = fp.lib
	var near: Array = fx.get("near", [0.0, 0.0])
	var c0 := Vector2(float(near[0]), float(near[1]))
	var fi := -1
	for k in forms.size():
		if ((forms[k] as Dictionary)["c"] as Vector2).distance_to(c0) <= float(fx.get("r", 3.0)):
			fi = k
			break
	if fi < 0:
		return {"rocks": rocks, "skirts": [], "info": {"near": near, "found": false}}
	var f: Dictionary = forms[fi]
	var c: Vector2 = f["c"]
	var dd: Vector2 = f["dd"]
	var cont := Vector2(-dd.y, dd.x)
	var rg := _rng(seed_ * 13 + fi * 7717 + 5)
	var out: Array = []
	var main_r: Dictionary = {}
	var removed: Array = []
	for r: Dictionary in rocks:
		if int(r["form"]) != fi:
			out.append(r)
			continue
		if String(r["kind"]) == "outcrop" and not bool(r["sat"]):
			main_r = r.duplicate(true)
		else:
			removed.append(String(r["id"]))
	var mcfg: Dictionary = fx.get("main", {})
	if not main_r.is_empty():
		for key: String in ["w", "h", "d", "lean_k", "roll", "embed", "ao_lift"]:
			if mcfg.has(key):
				main_r[key] = float(mcfg[key])
		main_r["yaw"] = float(main_r["yaw"]) + deg_to_rad(float(mcfg.get("yaw_add_deg", 0.0)))
		if mcfg.has("prm"):
			main_r["prm"] = mcfg["prm"]
		if mcfg.has("shift_down"):              # 主岩沿下坡移（負＝往坡裡縮，避免直立岩在下坡側懸出、底下黑洞）
			main_r["x"] = float(main_r["x"]) + dd.x * float(mcfg["shift_down"])
			main_r["z"] = float(main_r["z"]) + dd.y * float(mcfg["shift_down"])
		if mcfg.has("n"):
			main_r["n"] = int(mcfg["n"])
		main_r["r3"] = true
		out.append(main_r)
	var mw := float(main_r.get("w", 3.0))
	var added: Array = []
	var k2 := 0
	for sc: Dictionary in fx.get("sats", []):
		var q: Vector2 = c + cont * float(sc.get("along", 0.0)) * mw + dd * float(sc.get("down", 0.0))
		var gq := grad(lib, q)
		var ddq := (-gq).normalized() if gq.length() > 1e-4 else dd
		var r2 := {
			"id": "s01wall_f%02d_r3s%d" % [fi, k2], "kind": "outcrop", "form": fi, "sat": true, "r3": true,
			"embed": float(sc.get("embed", 0.3)), "x": q.x, "z": q.y, "w": float(sc["w"]), "h": float(sc["h"]), "d": float(sc["d"]),
			"yaw": atan2(ddq.x, ddq.y) + deg_to_rad(float(sc.get("yaw_add_deg", 0.0))), "lean_k": float(sc.get("lean_k", 0.3)),
			"slope": rad_to_deg(atan(gq.length())), "rib": false, "roll": float(sc.get("roll", 0.0)), "moss": float(sc.get("moss", 0.5)),
			"seed": seed_ * 31 + fi * 7919 + k2 * 131 + 29, "n": int(sc.get("n", 8)), "major": false}
		if sc.has("prm"):
			r2["prm"] = sc["prm"]
		if sc.has("ao_lift"):
			r2["ao_lift"] = float(sc["ao_lift"])
		k2 += 1
		var hr := maxf(float(sc["w"]), float(sc["d"])) * 0.5
		if not _in_scope(q, hr) or not _site_ok(fp, q, float(fx.get("path_min", 5.0)), 2.0) or _trunk_clear(fp, q, extra) < hr + 0.5 or _under_clear(fp, q) < hr + 0.3:
			continue
		out.append(r2)
		added.append(String(r2["id"]))
	var kd := 0
	for db: Dictionary in fx.get("debris", []):
		var qd: Vector2 = c + cont * float(db.get("along", 0.0)) * mw + dd * float(db.get("down", 0.0))
		var rr := float(db.get("r", 0.3))
		if not _site_ok(fp, qd, 2.2, 0.8) or _trunk_clear(fp, qd, extra) < rr + 0.4 or _under_clear(fp, qd) < rr + 0.3 or not _in_scope(qd, rr):
			continue
		var gd := grad(lib, qd)
		out.append({
			"id": "s01wall_f%02d_r3d%d" % [fi, kd], "kind": "debris", "form": fi, "sat": true, "r3": true,
			"x": qd.x, "z": qd.y, "w": 2.0 * rr * rg.randf_range(0.9, 1.15), "h": 2.0 * rr * rg.randf_range(0.5, 0.7), "d": 2.0 * rr * rg.randf_range(0.75, 1.0),
			"yaw": rg.randf() * TAU, "lean_k": 0.6, "slope": rad_to_deg(atan(gd.length())), "roll": rg.randf_range(-0.2, 0.2),
			"moss": rg.randf_range(0.3, 0.6), "seed": seed_ * 31 + fi * 7919 + kd * 977 + 61, "n": 5, "embed": float(db.get("embed", 0.12))})
		added.append("s01wall_f%02d_r3d%d" % [fi, kd])
		kd += 1
	var sk: Dictionary = fx.get("skirt", {})
	var skirts: Array = []
	if not sk.is_empty():
		var cso: Vector2 = c + dd * float(sk.get("soil_down", 0.0))
		skirts.append({"x": cso.x, "z": cso.y, "R": float(sk.get("R", 5.0)), "kind": "soil"})
		var cs: Vector2 = c + dd * float(sk.get("scree_down", 4.0))
		skirts.append({"x": cs.x, "z": cs.y, "R": float(sk.get("scree_R", 3.0)), "kind": "scree"})
	var mhr := maxf(float(main_r.get("w", 0.0)), float(main_r.get("d", 0.0))) * 0.5
	return {"rocks": out, "skirts": skirts, "info": {"near": near, "found": true, "form": fi, "removed": removed, "added": added, "main": String(main_r.get("id", "")),
		"main_trunk_clear": snappedf(_trunk_clear(fp, c, extra) - mhr, 0.01), "main_under_clear": snappedf(_under_clear(fp, c) - mhr, 0.01)}}


## 露根：在最後的樹裡挑『長在坡上』的（坡度 ≥ 24°、谷緣內外 −1…10 m），下坡側露出 2 條根。只挑 n 棵、彼此 ≥ 14 m。
static func plan_roots(fp, wcfg: Dictionary, seed_: int) -> Array:
	var lib = fp.lib
	var rg := _rng(seed_ * 11 + 404)
	var cand: Array = []
	for t: Dictionary in fp.trees:
		if String(t["scene"]) != "S01" or String(t["kind"]) != "tree":
			continue
		var p := Vector2(float(t["x"]), float(t["z"]))
		var sdf: float = lib.mask_sdf(p)
		var sl: float = lib.slope_deg_at(p.x, p.y)
		if sl < 24.0 or sdf < -1.0 or sdf > 10.0 or p.y < -94.0:
			continue
		if path_edge_d(lib, p) < 4.0:
			continue
		var h := float((fp.kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
		if h < 6.0:
			continue
		cand.append([p, sl + rg.randf() * 8.0, float(t["r"]), h])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out: Array = []
	for c: Array in cand:
		if out.size() >= int(wcfg.get("roots", 5)):
			break
		var p2: Vector2 = c[0]
		var close := false
		for o: Dictionary in out:
			if p2.distance_to(Vector2(float(o["x"]), float(o["z"]))) < 14.0:
				close = true
				break
		if close:
			continue
		var g := grad(lib, p2)
		var dd := (-g).normalized() if g.length() > 1e-4 else Vector2(0, 1)
		var thick := clampf(float(c[3]) * 0.009, 0.09, 0.17)
		out.append({"x": p2.x, "z": p2.y, "r": float(c[2]), "yaw": atan2(dd.x, dd.y), "len": rg.randf_range(1.3, 2.3), "thick": thick, "spread": rg.randf_range(0.45, 0.8), "seed": seed_ * 97 + out.size() * 389 + 3})
	return out


# ================================================================= 幾何（建造與驗證共用）
## 一顆岩的最終 transform 與網格：先用暫定高度建出頂點，再把『埋得最淺的方位扇區』壓到剛好埋入 embed m，
## 這樣每個方位都有一部分在地面以下（不會懸空），露出的部分最大。回傳 {xf, mesh, pts, vis_h, ok, ntri}
static func rock_geom(lib, r: Dictionary, embed_def: float = 0.07) -> Dictionary:
	var embed := float(r.get("embed", embed_def))
	var p := Vector2(float(r["x"]), float(r["z"]))
	var sz := Vector3(float(r["w"]), float(r["h"]), float(r["d"]))
	var g := grad(lib, p)
	var nrm := Vector3(-g.x, 1.0, -g.y).normalized()
	var up := Vector3.UP.lerp(nrm, float(r["lean_k"])).normalized()
	var yaw := float(r["yaw"])
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var zax := (fwd - up * fwd.dot(up)).normalized()
	var xax := up.cross(zax).normalized()
	var b := Basis(xax, up, zax) * Basis(Vector3(0, 0, 1), float(r["roll"]))
	var sd := int(r["seed"])
	var rng := _rng(sd)
	# 岩露頭＝岩盤：方一點（rho 小）、層理明顯（strata 大、層薄）；坡腳碎石＝崩落的石塊：圓一點
	var deb := String(r["kind"]) == "debris"
	var prm := {
		"seed": sd, "n": int(r["n"]), "rho": rng.randf_range(0.42, 0.82) if deb else rng.randf_range(0.24, 0.55), "taper": rng.randf_range(0.05, 0.28),
		"lean": Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05)),
		"lump": rng.randf_range(0.10, 0.2) if deb else rng.randf_range(0.07, 0.15), "strata": rng.randf_range(0.03, 0.07) if deb else rng.randf_range(0.05, 0.10),
		"ridge": rng.randf_range(0.03, 0.08), "rough": 0.02,
		"moss": float(r["moss"]), "step": rng.randf_range(0.45, 1.0) if deb else rng.randf_range(0.32, 0.75),
	}
	# R3 指名修正的岩：形狀參數覆寫（只有 r3_fix 的岩帶 "prm"；其他岩的 prm 與 R2 逐位元相同——亂數照樣先抽完再覆寫）
	if r.has("prm"):
		for pk: String in (r["prm"] as Dictionary):
			prm[pk] = float(r["prm"][pk])
	var ground := func(q: Vector2) -> float: return lib.h_at(q.x, q.y)
	var y0: float = lib.h_at(p.x, p.y)
	var xf0 := Transform3D(b, Vector3(p.x, y0, p.y))
	var rb0 := RockBuilder.build(sz, prm, xf0, ground)
	var P: PackedVector3Array = rb0["pts"]
	var shift := _sector_shift(lib, xf0, P, embed)
	var xf := Transform3D(b, Vector3(p.x, y0 - shift, p.y))
	var rb := RockBuilder.build(sz, prm, xf, ground)
	# R3 指名修正的岩：岩腳的頂點環境遮蔽沒那麼黑（RockBuilder 的貼地 AO 下限 0.52 → ao_lift；只改這幾顆的頂點色，共用 bp_rock.* 與 RockBuilder 不動）
	if r.has("ao_lift"):
		var arr: Array = (rb["mesh"] as ArrayMesh).surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var lift := float(r["ao_lift"])
		for ci in cols.size():
			var cc := cols[ci]
			var wv := xf * (rb["pts"] as PackedVector3Array)[ci]
			var above: float = wv.y - float(lib.h_at(wv.x, wv.z))
			cc.g = lerpf(cc.g, minf(cc.g / 0.52 * lift, 1.0), 1.0 - smoothstep(0.0, 1.9, above))
			cols[ci] = cc
		arr[Mesh.ARRAY_COLOR] = cols
		var m2 := ArrayMesh.new()
		m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		rb["mesh"] = m2
	var vis := 0.0
	for v: Vector3 in (rb["pts"] as PackedVector3Array):
		var w := xf * v
		vis = maxf(vis, w.y - lib.h_at(w.x, w.z))
	return {"xf": xf, "mesh": rb["mesh"], "pts": rb["pts"], "vis_h": vis, "ntri": int(rb["ntri"]), "bad": int(rb["bad"])}


## 回傳要往下移多少（負＝可以往上抬），使『最淺的方位扇區最低點』剛好在地下 embed m（沒有頂點的扇區不算）
static func _sector_shift(lib, xf: Transform3D, P: PackedVector3Array, embed: float) -> float:
	var mins := sector_min(lib, xf, P)
	var worst := -1e9
	for m: float in mins:
		if m < 1e8:
			worst = maxf(worst, m)
	return worst + embed


## 每個方位扇區（繞岩的水平投影中心 16 等分）裡，頂點離地高的最小值；沒有頂點的扇區＝1e9（呼叫端略過）。
## 全部 < 0＝四周都有一部分埋進地裡（沒有懸空的邊）。用投影中心而不是岩的原點：岩傾斜時頂點整體偏向一側。
static func sector_min(lib, xf: Transform3D, P: PackedVector3Array) -> PackedFloat32Array:
	var mins := PackedFloat32Array()
	mins.resize(SECTORS)
	mins.fill(1e9)
	var W := PackedVector3Array()
	W.resize(P.size())
	var cx := 0.0
	var cz := 0.0
	for i in P.size():
		W[i] = xf * P[i]
		cx += W[i].x
		cz += W[i].z
	cx /= maxf(float(P.size()), 1.0)
	cz /= maxf(float(P.size()), 1.0)
	for w: Vector3 in W:
		var a := atan2(w.z - cz, w.x - cx)
		var k := clampi(int(floor((a + PI) / TAU * float(SECTORS))), 0, SECTORS - 1)
		mins[k] = minf(mins[k], w.y - lib.h_at(w.x, w.z))
	return mins


# ================================================================= 建造（生成器呼叫；只在 S01）
## 回傳 {node, stats}
## 清掉上一次生成留下的谷壁岩網格（R2 重生前；或 mode 切回 r1／replay 時——讓 R1 的檔案樹與 R1 原樣相同，不留 R2 的孤兒檔）
static func clear_meshes() -> int:
	var n := 0
	var dir := DirAccess.open(MESH_DIR)
	if dir != null:
		for fn in dir.get_files():
			if fn.ends_with(".res"):
				dir.remove(fn)
				n += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MESH_DIR))
	return n


static func build(lib, props, wall: Dictionary, roots: Array) -> Dictionary:
	clear_meshes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var holder := Node3D.new()
	holder.name = "WallDressing"
	holder.set_meta("bp_kind", "s01_wall_dressing")
	holder.set_meta("bp_round", "S01-R2")
	var rocks_n := Node3D.new()
	rocks_n.name = "Rocks"
	holder.add_child(rocks_n)
	var rm: Dictionary = wall["reach"]
	var st := {"rocks": 0, "debris": 0, "collide": 0, "tris": 0, "dropped_buried": 0, "roots": 0}
	var mat: Material = props.rock_material()
	for r: Dictionary in wall["rocks"]:
		var geo := rock_geom(lib, r)
		var deb := String(r["kind"]) == "debris"
		if float(geo["vis_h"]) < (0.08 if deb else 0.35):
			st["dropped_buried"] += 1
			continue
		var mesh: ArrayMesh = geo["mesh"]
		mesh.surface_set_material(0, mat)
		mesh.resource_name = String(r["id"])
		var path := MESH_DIR + String(r["id"]) + ".res"
		ResourceSaver.save(mesh, path)
		var node := Node3D.new()
		node.name = String(r["id"])
		node.transform = geo["xf"]
		node.set_meta("bp_kind", String(r["kind"]))
		node.set_meta("bp_form", int(r["form"]))
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		mi.visibility_range_end = 70.0 if deb else 160.0
		mi.visibility_range_end_margin = 10.0 if deb else 25.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if deb or float(r["w"]) < 0.9:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		# 碰撞：只給玩家走得到、又凸出地面夠高的岩
		var collide := false
		if not deb and float(geo["vis_h"]) > 0.45:
			for v: Vector3 in (geo["pts"] as PackedVector3Array):
				var w := (geo["xf"] as Transform3D) * v
				if w.y - lib.h_at(w.x, w.z) > 0.2 and reachable(rm, Vector2(w.x, w.z)):
					collide = true
					break
		node.set_meta("bp_collide", collide)
		if collide:
			var sb := StaticBody3D.new()
			sb.name = "Body"
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			var shape := ConvexPolygonShape3D.new()
			shape.points = geo["pts"]
			cs.shape = shape
			sb.add_child(cs)
			node.add_child(sb)
			st["collide"] += 1
		rocks_n.add_child(node)
		st["debris" if deb else "rocks"] += 1
		st["tris"] += int(geo["ntri"])
	var roots_n := Node3D.new()
	roots_n.name = "Roots"
	holder.add_child(roots_n)
	for rt: Dictionary in roots:
		var h := Node3D.new()
		h.name = "Root_%d" % int(st["roots"])
		roots_n.add_child(h)
		var c := Vector2(float(rt["x"]), float(rt["z"]))
		var yaw := float(rt["yaw"])
		for k in 2:
			var a := yaw + (float(k) - 0.5) * 2.0 * float(rt["spread"])
			var start: Vector2 = c + Vector2(sin(a), cos(a)) * float(rt["r"]) * 0.8
			props._root_run(h, start, a, float(rt["len"]) * (1.0 if k == 0 else 0.8), float(rt["thick"]) * (1.0 if k == 0 else 0.8), int(rt["seed"]) + k * 7)
		# 給管子穩定的名字（不交給生成器的 _sanitize：它的流水號是全場景共用的，S01 多幾個節點會讓之後各場景的自動名位移）
		var ci := 0
		for ch in h.get_children():
			ch.name = "Tube_%d" % ci
			ci += 1
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).visibility_range_end = 60.0
				(ch as GeometryInstance3D).visibility_range_end_margin = 8.0
				(ch as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		st["roots"] += 1
	return {"node": holder, "stats": st}
