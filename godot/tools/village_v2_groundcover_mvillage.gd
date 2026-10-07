extends RefCounted
## 人間之里 V2 P9 R5 Macro Expansion — Village Ground Integration（全村 Macro 地面構圖）。
##   Macro Pilot（A 村內大型空地・B 農田→村落交界＝合格、C 住宅背面＝ground foundation）の語彙を全村へ。主役は 3–15 m 級の地面構圖、3D は縁と近景だけ。
##   ・空地は「街區」（路網・建物・水・田で区切られた開けた地面の連結成分）単位で語意分類：常走／半荒／村邊草地／臨時作業／未使用留白。
##     建物から ~6 m の帯は住宅後場（牆腳の 3 帯・背戸前の作業地面・踏み跡・角と路地からの草侵入）。生活 props は P10。
##   ・農田外緣（P8 不改・外だけ）：田の縁 → 草溝 → 農路／裸土（途切れる）→ 疎らな草・乾草 → 後場 → 建物。幅は建物までの余地・坡度・道路で変わる。
##   ・路肩：路面の外だけ（路面に草は描かない）。十字路・T 字・巷口・轉角で踏み跡と裸土が広がる、排水側は濕った帯。
##   ・林緣（forest-floor-first）・溪岸（substrate-first）は全村 r5 の林緣／溪岸類別が担う（VL.memb で交叉淡化）。
##   ・Pilot r10f 4 區・Macro Pilot A/B/C は凍結（VL.pilot_k で譲る）。封存 Hero 區は外周の銜接だけ（blocked_v の sealed）。
##   ・可見最上面ルール（正式 build rule）：地被の地面・3D は地形・路面・P4 院子地面（Districts/*/Yards・AuxYards）の最上面に載せる。

const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const SEED_MV := 7501
const STEP := 0.33
const Y_OFF := 0.016
const NB8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
## 空地の語意（街區の内部＝建物から 6 m 超）
const CLS_NAMES := ["walk", "wild", "meadow", "work", "blank"]
const CLS_JA := ["常走空地", "半荒空地", "村邊草地", "臨時作業空地", "未使用留白"]
## Macro Pilot m9（A/B/C、2026-10-04 ART 判定：A・B 合格、C 部分合格）の規劃・地面 digest：擴張後もこれと一致しなければ FAIL
const M9_PLAN_SHA := "8970f376f036c24284897b290e0df4e8c335655b2a0cd01e57dfb27ba98e9dd4"
const M9_GROUND_SHA := "3197fc9c200b9ffed53eed492253a8f85f0621b0d456b9de82ea9e54f0288425"
## ── P9 R5 限定解封（2026-10-05 使用者授權、P10 R1b Market West r3）：路地 1（中橫街 → 市集西通り）の歩く芯から地被の 3D instance を外す。
##   入口の視線軸の中央に全村 Macro の「未使用留白」の高い草（0.53–0.70 m）が叢になり、入口を荒れて見せていた。
##   規劃（Pilot r10f・m9 の digest、gate・反向）は一切変えない——烘焙の複製から、下の矩形の中の instance を除くだけ。
##   壁際（RSW_002／RSW_003・S1／S2 の壁から ~0.6 m）の牆腳の草は残す（縁の質感）。地面網格（Ground/*）は変えない。
const P10_CLEAR := [Rect2(207.6, -42.7, 2.6, 19.9)]


## 烘焙用の複製から P10_CLEAR の中の地被 instance（kind "mm"）を除く。除いた數を Pc["p10_cleared"] に（段ごと：pilot／village／macro／mv）
static func p10_clear(P: Dictionary) -> Dictionary:
	var Pc := P.duplicate()
	var keep: Array = []
	var cut := {"pilot": 0, "village": 0, "macro": 0, "mv": 0}
	var src: Array = P["items"]
	var np := int(P.get("n_pilot_items", 0))
	var nv := int(P.get("n_village_items", 0))
	var nm := int(P.get("n_macro_items", 0))
	for i in src.size():
		var it: Dictionary = src[i]
		if String(it.get("kind", "")) == "mm" and P10_CLEAR.any(func(r: Rect2) -> bool: return r.has_point(it["p"])):
			var st := "pilot" if i < np else ("village" if i < nv else ("macro" if i < nm else "mv"))
			cut[st] = int(cut[st]) + 1
			continue
		keep.append(it)
	Pc["items"] = keep
	Pc["p10_cleared"] = cut
	return Pc


## 烘焙済み overlay（非 headless）の MultiMesh instance のうち P10_CLEAR の中にあるもの（世界座標の原點で判定）
static func p10_audit(root: Node) -> int:
	var n := 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		var gx := (mmi as Node3D).global_transform if (mmi as Node3D).is_inside_tree() else _local_xf(mmi as Node3D)
		for k in mm.instance_count:
			var o := gx * mm.get_instance_transform(k).origin
			if P10_CLEAR.any(func(r: Rect2) -> bool: return r.has_point(Vector2(o.x, o.z))):
				n += 1
	return n


static func _local_xf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t



class Bucket:
	var cs := 4.0
	var cell := {}

	func add(obj: Variant, r: Rect2) -> void:
		for i in range(floori(r.position.x / cs), floori(r.end.x / cs) + 1):
			for j in range(floori(r.position.y / cs), floori(r.end.y / cs) + 1):
				var k := Vector2i(i, j)
				if not cell.has(k):
					cell[k] = []
				(cell[k] as Array).append(obj)

	func at(p: Vector2) -> Array:
		return cell.get(Vector2i(floori(p.x / cs), floori(p.y / cs)), [])

	func near(p: Vector2, r: float) -> Array:
		var out: Array = []
		var n := int(ceil(r / cs))
		var k0 := Vector2i(floori(p.x / cs), floori(p.y / cs))
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				out.append_array(cell.get(k0 + Vector2i(dx, dz), []))
		return out


# ─────────────────────────── 文脈 ───────────────────────────

static func context_mv(P: Dictionary, v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var R: RLib.TriSampler = CV["R"]
	var BB: Rect2 = VL.BB
	var MV := {"YS": (P["M"] as Dictionary)["YS"]}
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_MV
	# ── 壁と背戸（全棟；ML.context_m と同じ判定：道路・frontage に面する面＝表、その反対＝背面）
	var WB := Bucket.new()
	var walls: Array = []
	var doors: Array = []
	for o: Dictionary in CV["obb"]:
		var hh: Vector2 = o["h"]
		var oc: Vector2 = o["o"]
		var bx: Vector2 = o["bx"]
		var bz: Vector2 = o["bz"]
		var nrm_list := [-bz, bx, bz, -bx]
		var half_list := [hh.y, hh.x, hh.y, hh.x]
		var front := -1
		for e in 4:
			var q: Vector2 = oc + (nrm_list[e] as Vector2) * (float(half_list[e]) + 1.8)
			if VL.road_sd(CV, q) < 1.0 or VL.blocked_v(CV, q, false, 0.35, true) == "frontage":
				front = e
		for e in 4:
			var c0: Vector2 = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][e]
			var c1: Vector2 = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)][e]
			var w := ML.Wall.new()
			w.a = oc + bx * c0.x * hh.x + bz * c0.y * hh.y
			w.b = oc + bx * c1.x * hh.x + bz * c1.y * hh.y
			w.n = nrm_list[e]
			w.bld = o["name"]
			var mid := (w.a + w.b) * 0.5 + w.n * 1.8
			if e == front or VL.blocked_v(CV, mid, false, 0.35, true) == "frontage" or VL.road_sd(CV, mid) < 1.0:
				continue
			w.back = front >= 0 and e == (front + 2) % 4
			walls.append(w)
			WB.add(w, Rect2(w.a, Vector2.ZERO).expand(w.b).grow(5.0))
			if w.back:
				var dp := (w.a + w.b) * 0.5 + w.n * 0.4
				var br := VL.blocked_v(CV, dp + w.n * 1.4)
				if not VL.in_pilot(dp) and (br == "" or br == "trunk" or br == "obstacle") and not sealed(CV, dp + w.n * 1.4):
					doors.append([dp, w.n, w.bld])
	MV["walls"] = walls
	MV["WB"] = WB
	MV["doors"] = doors
	var OH: VL.ObbHash = CV["OH"]
	var bg := GC.DGrid.new()
	bg.build(BB, 1.0, func(q: Vector2) -> bool: return OH.d(q) <= 0.3)
	MV["bgrid"] = bg
	# ── 農田（P8）までの距離場（VL の文脈で作った場を共用）
	MV["fgrid"] = CV["fgrid"]
	MV["frect"] = CV["frect"]
	# ── 路網（layout）：交差・T 字・巷口・轉角、路縁の点（小径の行き先）
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var net: Array = PLib.network(L)
	var xs: Array = []
	for a in net.size():
		var ra: Dictionary = net[a]
		var pa: PackedVector2Array = ra["pts"]
		for i in range(1, pa.size() - 1):
			var d0 := (pa[i] - pa[i - 1]).normalized()
			var d1 := (pa[i + 1] - pa[i]).normalized()
			if d0.dot(d1) < cos(deg_to_rad(28.0)):
				xs.append([pa[i], float(ra["hw"]) + 2.5, "corner"])
		for b in net.size():
			if b == a:
				continue
			var rb: Dictionary = net[b]
			var pb: PackedVector2Array = rb["pts"]
			for ep: Vector2 in [pa[0], pa[pa.size() - 1]]:
				for j in pb.size() - 1:
					if GC.seg_d(pb[j], pb[j + 1], ep) < float(rb["hw"]) + 1.5:
						var minor := bool(ra["lane"]) or String(ra["cls"]) in ["alley", "farm"]
						xs.append([ep, maxf(float(ra["hw"]), float(rb["hw"])) + 3.0, "mouth" if minor else "tee"])
						break
			if b > a:
				for i in pa.size() - 1:
					for j in pb.size() - 1:
						var x: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
						if x != null:
							xs.append([x, maxf(float(ra["hw"]), float(rb["hw"])) + 3.5, "cross"])
	var xm: Array = []
	for x: Array in xs:
		var dup := false
		for y: Array in xm:
			if (y[0] as Vector2).distance_to(x[0]) < 4.0:
				y[1] = maxf(float(y[1]), float(x[1]))
				dup = true
				break
		if not dup and BB.has_point(x[0]):
			xm.append(x)
	var XB := Bucket.new()
	for x: Array in xm:
		XB.add(x, Rect2(x[0], Vector2.ZERO).grow(float(x[1]) + 10.0))
	MV["xs"] = xm
	MV["XB"] = XB
	var RE := Bucket.new()
	RE.cs = 6.0
	for r: Dictionary in net:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var a2 := pts[i]
			var b2 := pts[i + 1]
			var ln := a2.distance_to(b2)
			if ln < 0.01:
				continue
			var dv := (b2 - a2) / ln
			var nv := Vector2(-dv.y, dv.x)
			var t := 0.0
			while t <= ln:
				for sg in [-1.0, 1.0]:
					for off in [0.6, 1.3]:
						var q: Vector2 = a2 + dv * t + nv * float(sg) * (float(r["hw"]) + float(off))
						if BB.has_point(q) and is_nan(R.h(q.x, q.y)) and VL.blocked_v(CV, q) == "":
							RE.add(q, Rect2(q, Vector2.ZERO))
							break
				t += 2.0
	MV["RE"] = RE
	# ── 街區（1 m 格子）：開けた地面の連結成分（路面・建物・水・田・封存・Pilot・林緣／溪岸帯で区切る）
	var nx := int(ceil(BB.size.x))
	var nz := int(ceil(BB.size.y))
	var openm := PackedByteArray()
	openm.resize(nx * nz)
	for j in nz:
		for i in nx:
			var c := BB.position + Vector2(i + 0.5, j + 0.5)
			var br := VL.blocked_v(CV, c)
			openm[j * nx + i] = 1 if (br == "" or br == "trunk" or br == "obstacle") and not sealed(CV, c) and VL.memb(CV, c).x > 0.25 else 0
	var bid := PackedInt32Array()
	bid.resize(nx * nz)
	bid.fill(-1)
	var blocks: Array = []
	for k0 in nx * nz:
		if openm[k0] == 0 or bid[k0] >= 0:
			continue
		var id := blocks.size()
		var stk := [k0]
		bid[k0] = id
		var cells := PackedInt32Array()
		while not stk.is_empty():
			var k: int = stk.pop_back()
			cells.append(k)
			var i := k % nx
			var j := k / nx
			for kk: int in [k - 1 if i > 0 else -1, k + 1 if i < nx - 1 else -1, k - nx if j > 0 else -1, k + nx if j < nz - 1 else -1]:
				if kk >= 0 and openm[kk] == 1 and bid[kk] < 0:
					bid[kk] = id
					stk.append(kk)
		blocks.append({"id": id, "cells": cells})
	# 大きな街區は warp した Voronoi で小區（約 600–1500 m²）に分け、小區ごとに語意分類（境は 4 m で交叉淡化）
	var seeds: Array = []
	var SKB := Bucket.new()
	SKB.cs = 16.0
	for B: Dictionary in blocks:
		var cells: PackedInt32Array = B["cells"]
		var order: Array = range(cells.size())
		GC._shuffle(order, rng)
		var mine: Array = []
		for oi: int in order:
			var k: int = cells[oi]
			var c := BB.position + Vector2(k % nx + 0.5, k / nx + 0.5)
			var ok := true
			for si: int in mine:
				if (seeds[si]["p"] as Vector2).distance_to(c) < 30.0:
					ok = false
					break
			if ok:
				mine.append(seeds.size())
				seeds.append({"p": c, "block": int(B["id"]), "n": 0, "n_int": 0, "g": 0.0, "road": 0, "edge": 0, "bld": 0})
			if mine.size() >= 1 and cells.size() < 900:
				break
		B["seeds"] = mine
		for si: int in mine:
			SKB.add(si, Rect2(seeds[si]["p"], Vector2.ZERO).grow(48.0))
	MV["seeds"] = seeds
	MV["SKB"] = SKB
	MV["blocks"] = blocks
	MV["nx"] = nx
	MV["bid"] = bid
	var core := BB.grow(-20.0)
	for B: Dictionary in blocks:
		for k: int in B["cells"]:
			var c := BB.position + Vector2(k % nx + 0.5, k / nx + 0.5)
			var si: int = sub_at(MV, c, int(B["id"]))[0]
			var sd: Dictionary = seeds[si]
			sd["n"] += 1
			var wd := VL.wall_d(CV, c)
			if wd > 6.0:
				sd["n_int"] += 1
				sd["g"] += maxf(GC.grass_w(CV, c), 0.0)
			if wd < 12.0:
				sd["bld"] += 1
			if VL.road_sd(CV, c) < 3.0:
				sd["road"] += 1
			if GC.seam_d(CV, c) > -14.0 or fdist(MV, c) < 8.0 or not core.has_point(c):
				sd["edge"] += 1
	for sd: Dictionary in seeds:
		var n: float = maxf(1.0, float(sd["n"]))
		var gm: float = float(sd["g"]) / maxf(1.0, float(sd["n_int"]))
		var rr: float = float(sd["road"]) / n
		var er: float = float(sd["edge"]) / n
		var bl: float = float(sd["bld"]) / n
		var cls := 1
		if int(sd["n_int"]) < 60:
			cls = 4
		elif gm < 0.38:
			cls = 3
		elif er >= 0.45:
			cls = 2
		elif rr >= 0.14 or (bl >= 0.45 and rr >= 0.06):
			cls = 0
		if (cls == 1 or cls == 2) and rng.randf() < 0.18:
			cls = 4
		sd["cls"] = cls
		sd["grass"] = gm
		sd["road_r"] = rr
		sd["edge_r"] = er
		sd["bld_r"] = bl
		sd["vo"] = Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0))
		sd["scl"] = rng.randf_range(0.8, 1.25)
		sd["thr"] = rng.randf_range(-0.04, 0.04)
	for B: Dictionary in blocks:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for k: int in B["cells"]:
			var c := BB.position + Vector2(k % nx + 0.5, k / nx + 0.5)
			mn = mn.min(c)
			mx = mx.max(c)
		B["n"] = (B["cells"] as PackedInt32Array).size()
		B["bb"] = Rect2(mn, Vector2.ZERO).expand(mx).grow(0.5)
		var best := -1
		for si: int in B["seeds"]:
			if best < 0 or int(seeds[si]["n"]) > int(seeds[best]["n"]):
				best = si
		B["cls"] = int(seeds[best]["cls"]) if best >= 0 else 4
		var ni := 0
		for si: int in B["seeds"]:
			ni += int(seeds[si]["n_int"])
		B["n_int"] = ni
	MV["nz"] = nz
	var dg := GC.DGrid.new()
	dg.nx = nx
	dg.nz = nz
	dg.st = 1.0
	MV["bed"] = dg._chamfer(openm, 0)
	# ── 小径（desire lines）：背戸 → 最寄りの路縁／既存の小径（障害物を横切らない直線＋緩い曲がり）
	var PB := Bucket.new()
	var PP := Bucket.new()
	PP.cs = 6.0
	var SB := Bucket.new()
	var paths: Array = []
	var spots: Array = []
	var dl: Array = []
	for d: Array in doors:
		dl.append([VL.road_sd(CV, d[0]), d])
	dl.sort_custom(func(a3: Array, b3: Array) -> bool: return float(a3[0]) < float(b3[0]))
	for e2: Array in dl:
		var d: Array = e2[1]
		var p0: Vector2 = d[0]
		var n0: Vector2 = d[1]
		var p1 := p0 + n0 * 1.4
		# 背戸前の作業地面（雨落ちの外 3.3 m）
		if rng.randf() < 0.95:
			var sc := p0 + n0 * 3.6
			var brs := VL.blocked_v(CV, sc)
			if (brs == "" or brs == "trunk" or brs == "obstacle") and not sealed(CV, sc) and VL.wall_d(CV, sc) > 1.6 and VL.road_sd(CV, sc) > 2.0:
				_add_spot(SB, spots, sc, rng.randf_range(2.6, 3.6), "work")
		if rng.randf() < 0.1:
			continue
		var cand: Array = []
		for q: Vector2 in RE.near(p1, 30.0):
			var dd := p1.distance_to(q)
			if dd <= 30.0:
				cand.append([dd, q, "road"])
		for q: Vector2 in PP.near(p1, 20.0):
			var dd := p1.distance_to(q)
			if dd <= 20.0:
				cand.append([dd * 0.8, q, "path"])
		cand.sort_custom(func(a3: Array, b3: Array) -> bool: return float(a3[0]) < float(b3[0]))
		var tries := 0
		for cd: Array in cand:
			if tries >= 14:
				break
			var q: Vector2 = cd[1]
			if p1.distance_to(q) < 2.5:
				break
			tries += 1
			var ln := p1.distance_to(q)
			var perp := (q - p1).normalized().orthogonal()
			var mid := p1.lerp(q, 0.5) + perp * rng.randf_range(-0.12, 0.12) * ln
			if not _clear(CV, p1, mid) or not _clear(CV, mid, q):
				continue
			var w := rng.randf_range(0.8, 1.1)
			_add_path(PB, PP, paths, [p0, p1, mid, q], w)
			if (cd[2] == "road" and rng.randf() < 0.45) or (cd[2] == "path" and rng.randf() < 0.6):
				_add_spot(SB, spots, q, rng.randf_range(1.3, 2.1), "trample")
			break
	# ── 常走空地を横切る踏み分け道（路縁の向かい合う 2 点を結ぶ）、半荒・村邊は 1/3 の街區だけ
	for B: Dictionary in blocks:
		var cls: int = B["cls"]
		for si: int in B["seeds"]:
			if int(seeds[si]["cls"]) == 0:
				cls = 0
		if int(B["n"]) < 400 or not (cls == 0 or (cls == 1 and rng.randf() < 0.35) or (cls == 2 and rng.randf() < 0.65)):
			continue
		var bb: Rect2 = B["bb"]
		var ep: Array = []
		for q: Vector2 in RE.near(bb.get_center(), maxf(bb.size.x, bb.size.y) * 0.5 + 2.0):
			if bb.has_point(q) and block_at(MV, q) == int(B["id"]):
				ep.append(q)
		GC._shuffle(ep, rng)
		ep = ep.slice(0, 60)
		var pairs: Array = []
		for i in ep.size():
			for j in range(i + 1, ep.size()):
				var a4: Vector2 = ep[i]
				var b4: Vector2 = ep[j]
				var dd := a4.distance_to(b4)
				if dd < 14.0 or dd > 60.0:
					continue
				if not _clear_in(CV, MV, a4, b4, int(B["id"])):
					continue
				pairs.append([dd + rng.randf() * 8.0, a4, b4])
		pairs.sort_custom(func(a3: Array, b3: Array) -> bool: return float(a3[0]) > float(b3[0]))
		var nl := 2 if (cls == 0 and int(B["n"]) >= 1600) else 1
		var used: Array = []
		for pr: Array in pairs:
			if used.size() >= nl:
				break
			var a4: Vector2 = pr[1]
			var b4: Vector2 = pr[2]
			var md := (a4 + b4) * 0.5
			var ok := true
			for u: Array in used:
				if md.distance_to(u[0]) < 10.0 or absf((b4 - a4).normalized().dot(u[1])) > 0.82:
					ok = false
			if not ok:
				continue
			var ln := a4.distance_to(b4)
			var mid := md + (b4 - a4).normalized().orthogonal() * rng.randf_range(-0.06, 0.06) * ln
			_add_path(PB, PP, paths, [a4, mid, b4], rng.randf_range(0.9, 1.3))
			used.append([md, (b4 - a4).normalized()])
			for ept: Vector2 in [a4, b4]:
				if rng.randf() < 0.5:
					_add_spot(SB, spots, ept, rng.randf_range(1.4, 2.2), "trample")
	# ── 臨時作業空地：小區の内部に 1–3 の大きな作業地面
	for si in seeds.size():
		var sd: Dictionary = seeds[si]
		if int(sd["cls"]) != 3:
			continue
		var want := mini(3, 1 + int(sd["n_int"]) / 400)
		for t2 in 60:
			if want <= 0:
				break
			var c: Vector2 = (sd["p"] as Vector2) + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
			if block_at(MV, c) != int(sd["block"]) or int(sub_at(MV, c, int(sd["block"]))[0]) != si:
				continue
			if VL.wall_d(CV, c) > 4.0 and VL.road_sd(CV, c) > 3.0:
				_add_spot(SB, spots, c, rng.randf_range(3.0, 4.8), "yardwork")
				want -= 1
	MV["PB"] = PB
	MV["PP"] = PP
	MV["SB"] = SB
	MV["paths"] = paths
	MV["spots"] = spots
	MV["ms_context"] = Time.get_ticks_msec() - t0
	return MV


static func _add_path(PB: Bucket, PP: Bucket, paths: Array, pts: Array, w: float) -> void:
	var id := paths.size()
	paths.append([pts, w])
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		PB.add([a, b, w], Rect2(a, Vector2.ZERO).expand(b).grow(3.5))
		var ln := a.distance_to(b)
		var t := 0.0
		while t < ln:
			var q := a.lerp(b, t / maxf(ln, 1e-6))
			PP.add(q, Rect2(q, Vector2.ZERO))
			t += 1.5


static func _add_spot(SB: Bucket, spots: Array, c: Vector2, r: float, kind: String) -> void:
	var s := [c, r, kind]
	spots.append(s)
	SB.add(s, Rect2(c, Vector2.ZERO).grow(r * 1.3))


## 直線 a→b が建物・水・田・封存・Pilot／Macro Pilot 區・路面を横切らない（壁から 0.5 m 以上）
static func _clear(CV: Dictionary, a: Vector2, b: Vector2) -> bool:
	var ln := a.distance_to(b)
	var n := maxi(2, int(ln / 0.5))
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		var br := VL.blocked_v(CV, q)
		if not ((br == "" or br == "trunk" or br == "obstacle") and not sealed(CV, q)) or VL.wall_d(CV, q) < 0.5:
			return false
	return true


static func _clear_in(CV: Dictionary, MV: Dictionary, a: Vector2, b: Vector2, id: int) -> bool:
	var ln := a.distance_to(b)
	var n := maxi(2, int(ln))
	var inb := 0
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		var br := VL.blocked_v(CV, q)
		if not ((br == "" or br == "trunk" or br == "obstacle") and not sealed(CV, q)) or VL.wall_d(CV, q) < 1.5:
			return false
		if block_at(MV, q) == id:
			inb += 1
	return inb >= int(0.95 * (n - 1))


# ─────────────────────────── 問い合わせ ───────────────────────────

## 封存 rect（R4 Hero 構圖・竹林）の中か（blocked_v は trunk／obstacle を先に返すので別に見る）
static func sealed(CV: Dictionary, p: Vector2) -> bool:
	return (CV["SH"] as VL.RectHash).hit(p) != ""


static func block_at(MV: Dictionary, p: Vector2) -> int:
	var i := floori(p.x - VL.BB.position.x)
	var j := floori(p.y - VL.BB.position.y)
	if i < 0 or j < 0 or i >= int(MV["nx"]) or j >= int(MV["nz"]):
		return -1
	return (MV["bid"] as PackedInt32Array)[j * int(MV["nx"]) + i]


## 小區（warp した Voronoi）：[最寄りの小區, 次の小區, 最寄りの重み 0.5–1]
static func sub_at(MV: Dictionary, p: Vector2, blk: int) -> Array:
	var wp := p + Vector2(GC._n(p * 0.05, 1.0, 301.0) - 0.5, GC._n(p * 0.05, 1.0, 307.0) - 0.5) * 14.0
	var b1 := -1
	var d1 := 1e9
	var b2 := -1
	var d2 := 1e9
	var seeds: Array = MV["seeds"]
	for si: int in (MV["SKB"] as Bucket).at(p):
		if int(seeds[si]["block"]) != blk:
			continue
		var d := wp.distance_to(seeds[si]["p"])
		if d < d1:
			b2 = b1
			d2 = d1
			b1 = si
			d1 = d
		elif d < d2:
			b2 = si
			d2 = d
	if b1 < 0:
		# バケット外（巨大な街區の端）：街區の全小區から探す
		for si in seeds.size():
			if int(seeds[si]["block"]) == blk:
				var d := wp.distance_to(seeds[si]["p"])
				if d < d1:
					b1 = si
					d1 = d
	if b2 < 0:
		return [b1, b1, 1.0]
	return [b1, b2, 0.5 + 0.5 * smoothstep(0.0, 4.0, d2 - d1)]


static func eff_cls(P: Dictionary, sd: Dictionary) -> int:
	return 1 if P.has("_neg_mv_uniform") else int(sd["cls"])


## 街區の縁までの距離（1 m 格子、開けた地面の外から）
static func bed_at(MV: Dictionary, p: Vector2) -> float:
	var i := floori(p.x - VL.BB.position.x)
	var j := floori(p.y - VL.BB.position.y)
	if i < 0 or j < 0 or i >= int(MV["nx"]) or j >= int(MV["nz"]):
		return 0.0
	return (MV["bed"] as PackedFloat32Array)[j * int(MV["nx"]) + i]


## 建物までの距離（遠距離まで有効；近傍は VL.wall_d と同じ OBB 距離）
static func bdist(CV: Dictionary, MV: Dictionary, p: Vector2) -> float:
	var d := VL.wall_d(CV, p)
	if d < 98.0:
		return d
	return maxf((MV["bgrid"] as GC.DGrid).at(p), 0.0)


static func fdist(MV: Dictionary, p: Vector2) -> float:
	if not (MV["frect"] as Rect2).has_point(p):
		return 99.0
	return (MV["fgrid"] as GC.DGrid).at(p)


## 可見最上面：地形・路面・P4 院子地面（Yards／AuxYards）の最上面
static func top_h(P: Dictionary, p: Vector2) -> float:
	var CV: Dictionary = P["CV"]
	var h := (CV["S"] as RLib.TriSampler).h(p.x, p.y)
	var rh := (CV["R"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(rh):
		h = maxf(h, rh)
	var yh := ((P["M"] as Dictionary)["YS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(yh):
		h = maxf(h, yh)
	return h


## 小径までの距離（縁は沿線 ±25 % 揺らぐ）：Vector2(d − 半幅, 幅)
static func path_d(MV: Dictionary, p: Vector2) -> Vector2:
	var best := 99.0
	var bw := 1.0
	for sgm: Array in (MV["PB"] as Bucket).at(p):
		var a: Vector2 = sgm[0]
		var b: Vector2 = sgm[1]
		var q := ML._closest(a, b, p)
		var wv := float(sgm[2]) * (0.8 + 0.45 * GC._n(q * 0.25, 1.0, 13.0))
		var d := p.distance_to(q) - wv * 0.5
		if d < best:
			best = d
			bw = wv
	return Vector2(best, bw)


static func spot_k(MV: Dictionary, p: Vector2) -> Array:
	var best := 0.0
	var kind := ""
	for s: Array in (MV["SB"] as Bucket).at(p):
		var c: Vector2 = s[0]
		var d := p - c
		var ang := atan2(d.y, d.x)
		var rr: float = float(s[1]) * (0.75 + 0.5 * GC._n(Vector2(cos(ang), sin(ang)) * 2.2 + c * 0.1, 1.0, 17.0))
		var k := 1.0 - smoothstep(rr * 0.65, rr, d.length())
		if k > best:
			best = k
			kind = s[2]
	return [best, kind]


## 背面・側面の壁：[距離, 壁, 壁沿いの座標]
static func wall_near(MV: Dictionary, p: Vector2) -> Array:
	var best := 99.0
	var bw: ML.Wall = null
	var bt := 0.0
	for w: ML.Wall in (MV["WB"] as Bucket).at(p):
		var ab := w.b - w.a
		var t := clampf((p - w.a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var q := w.a + ab * t
		if (p - q).dot(w.n) < -0.05:
			continue
		var d := p.distance_to(q)
		if d < best:
			best = d
			bw = w
			bt = t * ab.length()
	return [best, bw, bt]


## 路地（向かい合う 2 棟の壁の間）の度合い
static func alley_k(MV: Dictionary, p: Vector2, w: ML.Wall) -> float:
	var other := 99.0
	for w2: ML.Wall in (MV["WB"] as Bucket).at(p):
		if w2.bld != w.bld and w.n.dot(w2.n) < -0.5 and (p - ML._closest(w2.a, w2.b, p)).dot(w2.n) > 0.0:
			other = minf(other, ML._closest(w2.a, w2.b, p).distance_to(p))
	return 1.0 - smoothstep(2.5, 4.5, other)


## 路口の扇（交差・T 字・巷口・轉角の外側に広がる踏み固め面、半径 r＋1.5–5 m の葉状）：[扇, 外の踏まれた草の暈]
static func apron_k(MV: Dictionary, p: Vector2) -> Vector2:
	var ak := 0.0
	var hk := 0.0
	for x: Array in (MV["XB"] as Bucket).at(p):
		var c: Vector2 = x[0]
		var d := p - c
		var dl := d.length()
		var dir := d / maxf(dl, 1e-4)
		var rr: float = float(x[1]) + 1.5 + 3.5 * GC._n(dir * 1.7 + c * 0.13, 1.0, 293.0)
		ak = maxf(ak, 1.0 - smoothstep(rr * 0.72, rr, dl))
		hk = maxf(hk, 1.0 - smoothstep(rr, rr + 3.0, dl))
	return Vector2(ak, hk)


## 交差・T 字・巷口・轉角の近さ（0–1）
static func inter_k(MV: Dictionary, p: Vector2) -> float:
	var k := 0.0
	for x: Array in (MV["XB"] as Bucket).at(p):
		var r: float = x[1]
		k = maxf(k, 1.0 - smoothstep(r * 0.55, r + 1.5, p.distance_to(x[0])))
	return k


static func slope(CV: Dictionary, p: Vector2) -> float:
	var S: RLib.TriSampler = CV["S"]
	var dx := S.h(p.x + 0.6, p.y) - S.h(p.x - 0.6, p.y)
	var dz := S.h(p.x, p.y + 0.6) - S.h(p.x, p.y - 0.6)
	if is_nan(dx) or is_nan(dz):
		return 0.0
	return Vector2(dx, dz).length() / 1.2


# ─────────────────────────── 地面 ───────────────────────────

## 地面重み：[Color(碎石, 濃草, 踏土, 落葉/木屑), Vector2(濕潤, 淡出), Vector2(泥, 卵石), Vector2(枯草, 踏まれた草)] または null
static func ground_mv(P: Dictionary, p: Vector2) -> Variant:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var BB: Rect2 = VL.BB
	var mk := VL.memb(CV, p).x
	if mk < 0.002:
		return null
	var fade := (1.0 - VL.pilot_k(p)) * smoothstep(0.0, 4.0, minf(minf(p.x - BB.position.x, BB.end.x - p.x), minf(p.y - BB.position.y, BB.end.y - p.y)))
	if fade < 0.002:
		return null
	var gv := 0.0
	var lu := 0.0
	var so := 0.0
	var li := 0.0
	var md := 0.0
	var pe := 0.0
	var dry := 0.0
	var worn := 0.0
	var wet := 0.0
	var st := 0.0
	var gw := GC.grass_w(CV, p)
	var on_g := smoothstep(0.38, 0.58, gw)
	var on_dirt := 1.0 - smoothstep(0.35, 0.55, gw)
	var rsd := VL.road_sd(CV, p)
	var dw_any := VL.wall_d(CV, p)
	# ① 小径：踏み固めた土（芯）＋踏まれて色の抜けた草の縁
	var pd := path_d(MV, p)
	var en := 0.55 * (GC._n(p * 1.3, 1.0, 31.0) - 0.5) + 0.35 * (GC._n(p * 3.1, 1.0, 37.0) - 0.5)
	var core := 1.0 - smoothstep(-0.25, 0.3, pd.x + en)
	so = maxf(so, 0.95 * core)
	gv = maxf(gv, 0.25 * core * (1.0 - on_dirt) * smoothstep(0.55, 0.75, GC._n(p * 0.9, 1.0, 41.0)))
	var halo_w := 0.7 + 0.4 * GC._n(p * 0.25, 1.0, 43.0)
	worn = maxf(worn, 0.45 * (1.0 - smoothstep(halo_w * 0.45, halo_w, pd.x)) * (1.0 - core) * on_g)
	# ② 作業地面（土＋木屑＋砂利）／踏み荒らし（雨落ちの帯には効かせない）
	var wn := wall_near(MV, p)
	var dw: float = wn[0]
	var sk := spot_k(MV, p)
	var k: float = float(sk[0]) * smoothstep(1.5, 2.3, dw)
	if k > 0.0:
		if sk[1] == "work" or sk[1] == "yardwork":
			var sub := ML.patch(p, 3.2, 47.0)
			so = maxf(so, 0.9 * k)
			li = maxf(li, 0.95 * k * smoothstep(0.4, 0.5, sub))
			gv = maxf(gv, 0.6 * k * (1.0 - smoothstep(0.22, 0.3, sub)))
			wet = minf(wet, -0.18 * k * (1.0 - smoothstep(0.36, 0.46, sub)))
		else:
			so = maxf(so, 0.75 * k * smoothstep(0.3, 0.5, ML.patch(p, 1.6, 59.0)))
			worn = maxf(worn, 0.9 * k)
	# ③ 背面・側面の壁：軒下の乾いた土 → 雨落ちの濡れた砂利 → 跳ね返りの濕った土（Macro Pilot m9 と同式）
	if dw < 2.2:
		var w: ML.Wall = wn[1]
		var along: float = wn[2]
		var seg := smoothstep(0.3, 0.42, GC._n(Vector2(along * 0.3, float(w.bld.hash() % 97)), 1.0, 61.0))
		var wl := w.a.distance_to(w.b)
		seg *= smoothstep(0.5, 1.3, minf(along, wl - along))
		var backk := 1.0 if w.back else 0.7
		if P.has("_neg_mv_ring"):
			seg = 1.0
			backk = 1.0
		backk *= 1.0 - core
		var eave := (1.0 - smoothstep(0.66, 0.8, dw)) * seg * backk
		so = maxf(so, 0.9 * eave)
		wet = minf(wet, -0.7 * eave)
		var seg_d := 1.0 if w.back else smoothstep(0.06, 0.16, GC._n(Vector2(along * 0.16, float(w.bld.hash() % 89)), 1.0, 63.0))
		var drip := smoothstep(0.74, 0.84, dw) * (1.0 - smoothstep(1.22, 1.34, dw)) * seg_d
		pe = maxf(pe, 1.0 * drip * backk)
		wet = maxf(wet, 1.0 * drip * backk)
		var splash := smoothstep(1.24, 1.36, dw) * (1.0 - smoothstep(1.75, 2.1, dw + 0.3 * (GC._n(Vector2(along * 0.9, 5.0), 1.0, 69.0) - 0.5))) * seg_d
		md = maxf(md, 0.5 * splash * backk)
		lu = maxf(lu, 0.35 * splash * backk)
		wet = maxf(wet, 0.5 * splash * backk)
	# ④ 農田交界（P8 の外だけ）：(a) 田の縁が開けた地面に直接接する所 (b) 水渠が田と村の間にある所
	var ft := farm_trans(P, p, rsd, dw_any, on_g, en)
	gv = maxf(gv, ft[0])
	lu = maxf(lu, ft[1])
	so = maxf(so, ft[2])
	md = maxf(md, ft[4])
	dry = maxf(dry, ft[6])
	worn = maxf(worn, ft[7])
	wet = maxf(wet, ft[8])
	var farm_t: float = ft[9]
	# ⑤ 路肩（路面の外だけ草系；路面の縁 0.6 m までは土・砂利だけ）
	if rsd > -0.7 and rsd < 5.0:
		var xk := inter_k(MV, p)
		var shw := 0.7 + 1.6 * GC._n(p * 0.16, 1.0, 241.0) + 3.0 * xk
		var fing := 0.6 * (GC._n(p * 0.9, 1.0, 243.0) - 0.5)
		# 路の色の踏み広げ：路縁から外へ葉状に 0.3–2.3 m、交差・T 字・巷口・轉角の角で +2.5 m（路縁の直線を外から崩す）
		var lobe := ML.patch(p, 3.0, 281.0)
		var spw := 0.3 + 2.0 * smoothstep(0.35, 0.75, lobe) + 2.5 * xk
		if rsd >= 0.0:
			var spk := (1.0 - smoothstep(spw * 0.55, spw, rsd + 0.4 * (GC._n(p * 1.4, 1.0, 283.0) - 0.5))) * (1.0 - farm_t * 0.6)
			st = maxf(st, 0.85 * spk)
		else:
			# 路面の縁を内側から崩す：暗い踏み土・泥の噛み込み（草は描かない）
			var bite := smoothstep(-0.6, -0.12, rsd) * smoothstep(0.5, 0.66, ML.patch(p, 2.2, 285.0))
			so = maxf(so, 0.7 * bite)
			md = maxf(md, 0.35 * bite * smoothstep(0.5, 0.68, GC._n(p * 1.1, 1.0, 287.0)))
		if rsd >= 0.0:
			# 路口の扇：踏み固めた土＋路の色、路縁近くは砂利のこぼれ、外は踏まれた草の暈（穴は大きな斑で抜く）
			var ap := apron_k(MV, p)
			if ap.y > 0.0:
				var hole := smoothstep(0.24, 0.4, ML.patch(p, 2.6, 295.0))
				so = maxf(so, 0.8 * ap.x * hole)
				st = maxf(st, 0.55 * ap.x * (1.0 - smoothstep(1.0, 3.5, rsd)))
				gv = maxf(gv, 0.4 * ap.x * (1.0 - smoothstep(0.4, 1.6, rsd)) * smoothstep(0.45, 0.6, GC._n(p * 0.9, 1.0, 297.0)))
				worn = maxf(worn, 0.6 * (ap.y - ap.x) * on_g)
		if rsd >= 0.0:
			var sk2 := (1.0 - smoothstep(shw * 0.45, shw, rsd + fing)) * (1.0 - farm_t * 0.6)
			worn = maxf(worn, 0.5 * sk2 * on_g)
			so = maxf(so, (0.4 * on_dirt + 0.3 * xk) * sk2)
			so = maxf(so, 0.75 * xk * smoothstep(0.44, 0.6, ML.patch(p, 3.0, 247.0)) * (1.0 - smoothstep(shw * 0.6, shw + 0.5, rsd)))
			# 排水：路から地形が下る側の路肩に濕った帯（斷續）
			var gd := Vector2(VL.road_sd(CV, p + Vector2(0.5, 0.0)) - VL.road_sd(CV, p - Vector2(0.5, 0.0)), VL.road_sd(CV, p + Vector2(0.0, 0.5)) - VL.road_sd(CV, p - Vector2(0.0, 0.5)))
			if gd.length() > 0.01:
				var S: RLib.TriSampler = CV["S"]
				var q := p + gd.normalized() * 0.8
				var dh := S.h(q.x, q.y) - S.h(p.x, p.y)
				if dh < -0.02:
					var dk := smoothstep(0.1, 0.3, rsd) * (1.0 - smoothstep(0.9, 1.4, rsd)) * smoothstep(0.46, 0.6, ML.patch(p, 4.0, 257.0)) * smoothstep(0.02, 0.06, -dh)
					md = maxf(md, 0.35 * dk)
					wet = maxf(wet, 0.55 * dk)
		else:
			var ek := smoothstep(-0.6, -0.1, rsd) * smoothstep(0.42, 0.58, GC._n(p * 0.7, 1.0, 249.0))
			so = maxf(so, 0.4 * ek)
			gv = maxf(gv, 0.35 * ek * smoothstep(0.5, 0.65, GC._n(p * 1.6, 1.0, 251.0)))
		gv = maxf(gv, 0.45 * (1.0 - smoothstep(0.1, 0.8, absf(rsd))) * smoothstep(0.55, 0.68, ML.patch(p, 2.4, 253.0)))
	# ⑥ 小區の内部：語意ごとの 2–3 言語（主の留白＋次の斑＋縁の侵入）、小區の境は 4 m で交叉淡化
	var bi := block_at(MV, p)
	var yard := 1.0 - smoothstep(4.5, 7.5, dw_any + 2.0 * (GC._n(p * 0.2, 1.0, 259.0) - 0.5))
	if bi >= 0:
		var sa := sub_at(MV, p, bi)
		var ctx := [pd.x, core, k, yard, farm_t, bed_at(MV, p), on_g, maxf(1.0 - smoothstep(2.0, 9.0, GC.wdist(CV, p) - GC.RB_CORE), smoothstep(-16.0, -6.0, GC.seam_d(CV, p))), dw_any]
		var l1 := lang(P, (MV["seeds"] as Array)[int(sa[0])], p, ctx)
		var t: float = sa[2]
		if int(sa[1]) != int(sa[0]) and t < 0.999:
			var l2 := lang(P, (MV["seeds"] as Array)[int(sa[1])], p, ctx)
			for ii in 8:
				l1[ii] = l1[ii] * t + l2[ii] * (1.0 - t)
		gv = maxf(gv, l1[0])
		lu = maxf(lu, l1[1])
		so = maxf(so, l1[2])
		li = maxf(li, l1[3])
		md = maxf(md, l1[4])
		pe = maxf(pe, l1[5])
		dry = maxf(dry, l1[6])
		worn = maxf(worn, l1[7])
	# ⑦' 住宅後場の土埃：壁 2.2 m より外の土の上に 4–7 m の明るく乾いた踏み固めの斑（作業面・小径とは別の大きな形）
	if yard > 0.0 and gw < 0.5 and dw > 2.2:
		var dk := smoothstep(0.5, 0.62, ML.patch(p, 5.5, 299.0)) * yard * (1.0 - maxf(core, k))
		so = maxf(so, 0.55 * dk)
		wet = minf(wet, -0.5 * dk)
	# ⑦ 住宅後場（土）：角・路地・草縁から草の侵入斑
	if yard > 0.0 and gw < 0.5 and dw < 99.0:
		var low := smoothstep(1.2, 3.0, pd.x) * (1.0 - k)
		var w: ML.Wall = wn[1]
		var corner_src := 0.0
		if w != null:
			var along: float = wn[2]
			var wl := w.a.distance_to(w.b)
			corner_src = maxf(1.0 - smoothstep(1.2, 3.5, minf(along, wl - along)), alley_k(MV, p, w))
		var src := maxf(corner_src * (1.0 - smoothstep(1.0, 5.0, dw + 3.0 * (GC._n(p * 0.35, 1.0, 105.0) - 0.5))), 1.0 - smoothstep(1.0, 4.0, GC.gdist(CV, p)))
		var ik := smoothstep(0.52, 0.64, ML.patch(p, 5.5, 107.0)) * low * src * yard
		lu = maxf(lu, 0.5 * ik * smoothstep(0.3, 0.5, ML.patch(p, 3.5, 113.0)))
	# 路面の中（0.6 m 超）には描かない；路面の縁は土・砂利だけ
	if rsd < 0.0 and not P.has("_neg_mv_road"):
		lu = 0.0
		dry = 0.0
		worn = 0.0
		li = 0.0
		pe = 0.0
		st = 0.0
		wet = minf(wet, 0.0)
	if P.has("_neg_mv_road") and rsd < -0.6:
		lu = 0.7
	if P.has("_neg_mv_speckle"):
		var ck := (int(floor(p.x * 2.0)) + int(floor(p.y * 2.0))) % 2
		dry = 0.6 * float(ck)
		lu = 0.5 * float(1 - ck)
	var tot := gv + lu + so + li + md + pe + dry + worn + st
	if tot > 1.0:
		gv /= tot
		lu /= tot
		so /= tot
		li /= tot
		md /= tot
		pe /= tot
		dry /= tot
		worn /= tot
		st /= tot
		tot = 1.0
	if tot * mk < 0.02:
		return null
	return [Color(gv, lu, so, li) * mk, Vector2(clampf(wet * mk, -1.0, 1.0), fade), Vector2(md, pe) * mk, Vector2(dry, worn) * mk, st * mk]


## 小區の語意ごとの地面言語：[gv, lu, so, li, md, pe, dry, worn]
##   ctx＝[小径距離, 小径芯, 作業地面, 後場帯, 農田外緣, 街區の縁距離, 草の上, 濕り（水・林寄り）, 壁距離]
static func lang(P: Dictionary, sd: Dictionary, p: Vector2, ctx: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var cls := eff_cls(P, sd)
	var vo: Vector2 = Vector2.ZERO if P.has("_neg_mv_uniform") else sd["vo"]
	var sc: float = 1.0 if P.has("_neg_mv_uniform") else float(sd["scl"])
	var th: float = 0.0 if P.has("_neg_mv_uniform") else float(sd["thr"])
	var q := p + vo
	var pdx: float = ctx[0]
	var core: float = ctx[1]
	var k: float = ctx[2]
	var yard: float = ctx[3]
	var farm_t: float = ctx[4]
	var bed: float = ctx[5]
	var on_g: float = ctx[6]
	var damp: float = ctx[7]
	var dw_any: float = ctx[8]
	var busy := maxf(core, k)
	var inner := (1.0 - yard) * (1.0 - busy) * (1.0 - farm_t)
	match cls:
		0:
			# 常走：踏み分け道の周りが広く踏まれる（1–3 m）、合流の裸土、乾いた斑は少し
			out[7] = 0.5 * (1.0 - smoothstep(1.0, 3.2, pdx)) * (1.0 - core) * on_g * (1.0 - 0.5 * yard)
			out[6] = 0.55 * smoothstep(0.6 + th, 0.72 + th, ML.patch(q, 12.0 * sc, 97.0)) * inner * on_g * (1.0 - damp)
			out[2] = 0.5 * smoothstep(0.64 + th, 0.74 + th, ML.patch(q, 5.0 * sc, 261.0)) * inner
		1:
			# 半荒：大きな乾いた草の斑（10–15 m）、濕った所は濃い草
			var dk2 := smoothstep(0.5 + th, 0.66 + th, ML.patch(q, 13.0 * sc, 97.0)) * inner * on_g * (1.0 - damp)
			out[6] = dk2 * (0.5 + 0.35 * smoothstep(0.3, 0.65, ML.patch(q, 3.0, 103.0)))
			out[1] = 0.45 * smoothstep(0.56 + th, 0.68 + th, ML.patch(q, 8.0 * sc, 101.0)) * inner * (1.0 - dk2) * maxf(on_g, damp)
		2:
			# 村邊草地：濃い草と乾いた草の大きなモザイク
			var lk := smoothstep(0.52 + th, 0.64 + th, ML.patch(q, 10.0 * sc, 263.0)) * inner * on_g
			out[1] = 0.5 * lk * (0.6 + 0.4 * damp)
			out[6] = 0.65 * smoothstep(0.55 + th, 0.68 + th, ML.patch(q, 15.0 * sc, 97.0)) * inner * on_g * (1.0 - lk) * (1.0 - 0.7 * damp)
		3:
			# 臨時作業：裸土の大きな斑＋砂利の斑、縁から草が侵入
			var bare := smoothstep(0.42 + th, 0.54 + th, ML.patch(q, 5.0 * sc, 265.0)) * (1.0 - yard * 0.5) * (1.0 - farm_t)
			out[2] = 0.8 * bare
			out[0] = 0.5 * bare * smoothstep(0.58, 0.68, ML.patch(q, 3.0, 267.0))
			out[1] = 0.45 * (1.0 - smoothstep(0.8, 2.4, bed)) * smoothstep(0.48, 0.6, ML.patch(q, 4.0, 269.0)) * (1.0 - bare)
		4:
			# 未使用留白：縁の侵入だけ
			out[1] = 0.4 * (1.0 - smoothstep(0.8, 2.2, bed)) * smoothstep(0.5, 0.62, ML.patch(q, 4.0, 269.0)) * smoothstep(1.5, 3.0, dw_any)
	return out


## 農田交界：[gv, lu, so, li, md, pe, dry, worn, wet, farm_t, type(0 なし／1 直接／2 渠越し), 農路の中心距離]
##   (a) 直接：田の縁 → 草溝（0.2–3 m × 余地）→ 農路／裸土（途切れる）→ 疎らな草・乾草 → 後場（建物 70 m 以内）
##   (b) 渠越し：渠の上の濕った濃い草 → 渠沿いの農路（途切れる）→ 疎らな草・乾草 → 後場（田が渠の向こう 40 m 以内、建物 50 m 以内）
##   幅は建物までの余地・坡度・道路で変わる（固定幅の帯にしない）
static func farm_trans(P: Dictionary, p: Vector2, rsd: float, dw_any: float, on_g: float, en: float) -> PackedFloat32Array:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var o := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if P.has("_neg_mv_noditch"):
		return o
	var fixed := P.has("_neg_mv_fixedband")
	var fd := fdist(MV, p)
	if fd <= 0.0 or fd > 40.0:
		return o
	var steep := smoothstep(0.16, 0.32, slope(CV, p))
	var rk := smoothstep(0.4, 2.4, rsd)
	var wd := GC.wdist(CV, p)
	dw_any = bdist(CV, MV, p)
	if fd > wd + 2.0 and wd - GC.RB_CORE < 14.0:
		# (b) 渠越し
		var e := wd - GC.RB_CORE
		var vil := 1.0 - smoothstep(30.0, 50.0, dw_any)
		var s := clampf((e + dw_any) / 14.0, 0.7, 1.3) * (1.0 - 0.3 * steep)
		var vn := 0.0 if fixed else 1.2 * (GC._n(p * 0.4, 1.0, 71.0) - 0.5)
		var vk := smoothstep(-GC.RB_FADE, 0.2, e) * (1.0 - smoothstep(2.4, 4.0, e + vn))
		o[1] = 0.45 * vk * (1.0 if fixed else smoothstep(0.42, 0.62, ML.patch(p, 5.5, 73.0)))
		o[4] = 0.5 * vk * (1.0 - smoothstep(0.4, 1.4, e)) * smoothstep(0.45, 0.6, ML.patch(p, 2.0, 79.0))
		o[8] = 0.45 * vk * (1.0 - smoothstep(0.2, 2.0, e))
		var tc := (3.2 + 2.4 * GC._n(p * 0.09, 1.0, 271.0)) * s
		var tw := 0.9 + 0.6 * GC._n(p * 0.3, 1.0, 227.0)
		var brk := smoothstep(0.34, 0.5, ML.patch(p, 7.0, 273.0))
		if fixed:
			tc = 3.4
			tw = 1.2
			brk = 1.0
		var tk := (1.0 - smoothstep(tw * 0.35, tw * 0.6 + 0.15, absf(e - tc) + 0.3 * en)) * vil * rk * brk * (1.0 - steep) * smoothstep(1.4, 3.2, dw_any)
		o[2] = 0.9 * tk
		o[0] = 0.22 * tk * smoothstep(0.55, 0.7, GC._n(p * 0.8, 1.0, 229.0))
		o[7] = 0.4 * (1.0 - smoothstep(tw * 0.6, tw * 0.6 + 1.0, absf(e - tc))) * (1.0 - tk) * on_g * vil * rk
		var far := smoothstep(tc + tw * 0.5, tc + tw * 0.5 + 1.0, e) * (1.0 - smoothstep(tc + 5.0 * s + 1.0, tc + 8.0 * s + 3.0, e))
		o[6] = 0.6 * far * smoothstep(0.48, 0.64, ML.patch(p, 6.0, 233.0)) * on_g * vil
		o[7] = maxf(o[7], 0.35 * far * smoothstep(0.6, 0.72, ML.patch(p, 4.0, 235.0)) * on_g * vil)
		o[9] = maxf(vk, (1.0 - smoothstep(tc + 5.0 * s + 1.0, tc + 8.0 * s + 3.0, e)) * vil)
		o[10] = 2.0
		o[11] = tc
		return o
	if fd > 18.0:
		return o
	# (a) 直接
	var vil2 := 1.0 - smoothstep(40.0, 70.0, dw_any)
	var s2 := 1.0
	if dw_any < 24.0:
		s2 = clampf((fd + dw_any) / 12.0, 0.4, 1.15)
	s2 *= 1.0 - 0.4 * steep
	var dch := (1.4 + 1.8 * GC._n(p * 0.11, 1.0, 211.0)) * s2
	var tc2 := dch + (0.9 + 1.8 * GC._n(p * 0.23, 1.0, 223.0)) * s2
	var tw2 := 0.9 + 0.6 * GC._n(p * 0.3, 1.0, 227.0)
	var brk2 := smoothstep(0.36, 0.52, ML.patch(p, 7.0, 239.0))
	if fixed:
		dch = 2.0
		tc2 = 3.4
		tw2 = 1.2
		brk2 = 1.0
	var fk := smoothstep(0.0, 0.3, fd) * (1.0 - smoothstep(dch * 0.75, dch, fd + (0.0 if fixed else 0.6 * (GC._n(p * 0.5, 1.0, 83.0) - 0.5))))
	o[1] = 0.75 * fk
	o[4] = 0.45 * fk * (1.0 - smoothstep(0.3, 1.2, fd)) * smoothstep(0.35, 0.55, ML.patch(p, 1.6, 89.0))
	o[8] = 0.5 * fk * (1.0 - smoothstep(0.3, 1.6, fd))
	var tk2 := (1.0 - smoothstep(tw2 * 0.35, tw2 * 0.6 + 0.15, absf(fd - tc2) + 0.3 * en)) * vil2 * (1.0 - steep) * rk * brk2 * smoothstep(1.4, 3.2, dw_any)
	o[2] = 0.9 * tk2
	o[0] = 0.22 * tk2 * smoothstep(0.55, 0.7, GC._n(p * 0.8, 1.0, 229.0))
	o[7] = 0.4 * (1.0 - smoothstep(tw2 * 0.6, tw2 * 0.6 + 1.0, absf(fd - tc2))) * (1.0 - tk2) * on_g * vil2 * rk
	var far2 := smoothstep(tc2 + tw2 * 0.5, tc2 + tw2 * 0.5 + 1.0, fd) * (1.0 - smoothstep(tc2 + 4.0 * s2 + 2.0, tc2 + 7.0 * s2 + 4.0, fd))
	o[6] = 0.5 * far2 * smoothstep(0.55, 0.68, ML.patch(p, 4.5, 233.0)) * on_g * (0.5 + 0.5 * vil2)
	o[7] = maxf(o[7], 0.35 * far2 * smoothstep(0.6, 0.72, ML.patch(p, 4.0, 235.0)) * on_g * vil2)
	o[9] = maxf(fk, (1.0 - smoothstep(tc2 + 4.0 * s2 + 2.0, tc2 + 7.0 * s2 + 4.0, fd)) * (0.5 + 0.5 * vil2))
	o[10] = 1.0
	o[11] = tc2
	return o


## 地面頂點を置いてよいか（建物・frontage・封存・P7 構件・水・農田・路面の 0.6 m より奥には描かない；P7 核心は外緣 0.5 m まで；Pilot・Macro Pilot 區は緣 4 m の交叉淡化帯だけ）
static func vertex_ok_mv(P: Dictionary, p: Vector2) -> bool:
	var CV: Dictionary = P["CV"]
	var road_in := 3.0 if P.has("_neg_mv_road") else 0.6
	if VL.road_sd(CV, p) < -road_in or sealed(CV, p):
		return false
	var br := VL.blocked_v(CV, p, true, road_in)
	if br == "pilot":
		if VL.pilot_k(p) >= 0.999:
			return false
		if GC.zone_of(p) != "":
			return true
		br = VL.blocked_v(CV, p, true, road_in, true)
	if br == "riverbank":
		return GC.wdist(CV, p) >= GC.RB_CORE - GC.RB_FADE and not VL.p7_covered(CV, p) and not sealed(CV, p)
	return (br == "" or br == "obstacle" or br == "trunk") and not sealed(CV, p)


## 24 m 區塊の Macro 地面網格（全村共通の格子位相＝區塊の境で頂點が一致；縁は BFS で 1 m 淡出）
static func ground_chunk_mv(P: Dictionary, ck: Vector2i) -> ArrayMesh:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var BB: Rect2 = VL.BB
	var gs := STEP
	var cr := Rect2(ck.x * GC.CHUNK, ck.y * GC.CHUNK, GC.CHUNK, GC.CHUNK)
	var MG := 5
	var i0 := floori((cr.position.x - BB.position.x) / gs) - MG
	var i1 := ceili((cr.end.x - BB.position.x) / gs) + MG
	var j0 := floori((cr.position.y - BB.position.y) / gs) - MG
	var j1 := ceili((cr.end.y - BB.position.y) / gs) + MG
	var WG := {}
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := BB.position + Vector2(i * gs, j * gs)
			if not BB.has_point(p) or not vertex_ok_mv(P, p):
				continue
			var w: Variant = ground_mv(P, p)
			if w != null:
				WG[Vector2i(i, j)] = w
	if WG.is_empty():
		return null
	var nw := {}
	for g: Vector2i in WG:
		var acc := [(WG[g][0] as Color) * 4.0, (WG[g][1] as Vector2) * 4.0, (WG[g][2] as Vector2) * 4.0, (WG[g][3] as Vector2) * 4.0, float(WG[g][4]) * 4.0]
		var ws := 4.0
		for d: Vector2i in NB8:
			if WG.has(g + d):
				var wt := 1.0 if (d.x != 0 and d.y != 0) else 2.0
				acc[0] += (WG[g + d][0] as Color) * wt
				acc[1] += (WG[g + d][1] as Vector2) * wt
				acc[2] += (WG[g + d][2] as Vector2) * wt
				acc[3] += (WG[g + d][3] as Vector2) * wt
				acc[4] += float(WG[g + d][4]) * wt
				ws += wt
		nw[g] = [acc[0] / ws, acc[1] / ws, acc[2] / ws, acc[3] / ws, float(acc[4]) / ws]
	var dist := {}
	var front: Array = []
	for g: Vector2i in nw:
		for d: Vector2i in NB8:
			var q: Vector2i = g + d
			if q.x < i0 or q.x > i1 or q.y < j0 or q.y > j1:
				continue
			if not nw.has(q):
				dist[g] = 0
				front.append(g)
				break
	var nf := 3
	while not front.is_empty():
		var nxt: Array = []
		for g: Vector2i in front:
			if int(dist[g]) >= nf:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if nw.has(g + d) and not dist.has(g + d):
					dist[g + d] = int(dist[g]) + 1
					nxt.append(g + d)
		front = nxt
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U1 := PackedVector2Array()
	var U2 := PackedVector2Array()
	var CU := PackedFloat32Array()
	var idx := PackedInt32Array()
	var vid := {}
	var ci0 := floori((cr.position.x - BB.position.x) / gs)
	var ci1 := ceili((cr.end.x - BB.position.x) / gs)
	var cj0 := floori((cr.position.y - BB.position.y) / gs)
	var cj1 := ceili((cr.end.y - BB.position.y) / gs)
	for j in range(cj0, cj1 + 1):
		for i in range(ci0, ci1 + 1):
			var g := Vector2i(i, j)
			if not nw.has(g):
				continue
			var p := BB.position + Vector2(i * gs, j * gs)
			var h := Y_OFF + (top_h(P, p) if not P.has("_neg_nolift") else maxf(S.h(p.x, p.y), _rh(CV, p)))
			var dd := 0.4
			var nrm := Vector3(S.h(p.x - dd, p.y) - S.h(p.x + dd, p.y), 2.0 * dd, S.h(p.x, p.y - dd) - S.h(p.x, p.y + dd))
			var u2: Vector2 = nw[g][1]
			if dist.has(g):
				u2.y *= smoothstep(0.0, float(nf), float(dist[g]))
			vid[g] = V.size()
			V.append(Vector3(p.x, h, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append(nw[g][0])
			U2.append(u2)
			U1.append(nw[g][2])
			var c4: Vector2 = nw[g][3]
			CU.append_array([c4.x, c4.y, float(nw[g][4]), 0.0])
	for j in range(cj0, cj1):
		for i in range(ci0, ci1):
			var px := BB.position.x + i * gs
			var pz := BB.position.y + j * gs
			if px < cr.position.x - 1e-4 or px >= cr.end.x - 1e-4 or pz < cr.position.y - 1e-4 or pz >= cr.end.y - 1e-4:
				continue
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	if idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV] = U1
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_CUSTOM0] = CU
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	am.resource_name = "gcmv_%d_%d" % [ck.x, ck.y]
	return am


static func _rh(CV: Dictionary, p: Vector2) -> float:
	var rh := (CV["R"] as RLib.TriSampler).h(p.x, p.y)
	return -1e9 if is_nan(rh) else rh


static func chunk_keys_mv(P: Dictionary) -> Array:
	var CV: Dictionary = P["CV"]
	var BB: Rect2 = VL.BB
	var ks := {}
	var x := BB.position.x + 1.0
	while x < BB.end.x:
		var z := BB.position.y + 1.0
		while z < BB.end.y:
			var p := Vector2(x, z)
			z += 2.0
			if VL.memb(CV, p).x < 0.002 or VL.pilot_k(p) >= 0.999 or not vertex_ok_mv(P, p):
				continue
			for dx in [-2.0, 0.0, 2.0]:
				for dz in [-2.0, 0.0, 2.0]:
					ks[Vector2i(floori((p.x + dx) / GC.CHUNK), floori((p.y + dz) / GC.CHUNK))] = true
		x += 2.0
	var out := ks.keys()
	out.sort()
	return out


# ─────────────────────────── 3D（縁の丈草の房・路地の草・田の外緣・近景の點綴） ───────────────────────────

static func edge_k_mv(P: Dictionary, p: Vector2) -> float:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var k := 0.0
	var fd := fdist(MV, p)
	if fd < 6.0:
		var reach := 2.2 + 2.4 * GC._n(p * 0.12, 1.0, 139.0)
		k = maxf(k, smoothstep(0.3, 0.6, fd) * (1.0 - smoothstep(reach - 0.8, reach, fd)))
	var e := GC.wdist(CV, p) - GC.RB_CORE
	if e < 4.0:
		k = maxf(k, 0.85 * smoothstep(0.4, 0.9, e) * (1.0 - smoothstep(2.2, 3.4, e)))
	var wn := wall_near(MV, p)
	var dw: float = wn[0]
	if dw < 3.0 and wn[1] != null:
		var w: ML.Wall = wn[1]
		var wl := w.a.distance_to(w.b)
		var along: float = wn[2]
		var corner := 1.0 - smoothstep(1.2, 2.6, minf(along, wl - along))
		k = maxf(k, alley_k(MV, p, w) * smoothstep(0.35, 0.7, dw) * (1.0 - smoothstep(1.8, 3.0, dw)) * (0.6 + 0.4 * corner))
	var bi := block_at(MV, p)
	if bi >= 0:
		var cls := eff_cls(P, (MV["seeds"] as Array)[int(sub_at(MV, p, bi)[0])])
		if cls == 1 or cls == 2:
			var bed := bed_at(MV, p)
			k = maxf(k, (1.0 - smoothstep(1.2, 3.0, bed)) * smoothstep(1.5, 3.0, VL.road_sd(CV, p)) * smoothstep(2.4, 3.5, dw) * (0.85 if cls == 1 else 0.5))
	return k * VL.memb(CV, p).x


static func extend(P: Dictionary, v: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	P["n_macro_items"] = (P["items"] as Array).size()
	var MV := context_mv(P, v)
	P["MV"] = MV
	var BB: Rect2 = VL.BB
	var nx: int = MV["nx"]
	var bid: PackedInt32Array = MV["bid"]
	var items: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_MV + 1
	for k in bid.size():
		var bi := bid[k]
		if bi < 0:
			continue
		var c := BB.position + Vector2(k % nx + 0.5, k / nx + 0.5)
		var cls := eff_cls(P, (MV["seeds"] as Array)[int(sub_at(MV, c, bi)[0])])
		var tag0: String = "mv_" + String(CLS_NAMES[cls])
		var ek_c := edge_k_mv(P, c)
		var pd_c := path_d(MV, c).x
		var dw_c: float = wall_near(MV, c)[0]
		var meadow := cls == 2 and bed_at(MV, c) > 3.0 and VL.wall_d(CV, c) > 6.0
		var yard_dirt := VL.wall_d(CV, c) < 4.5 and GC.grass_w(CV, c) < 0.5
		var roadside := VL.road_sd(CV, c) < 2.2
		if ek_c < 0.03 and pd_c > 1.6 and not (dw_c > 0.6 and dw_c < 1.5) and not meadow and not yard_dirt and not roadside:
			continue
		for sub in 9:
			var q := c + Vector2((sub % 3) / 3.0 - 0.5 + rng.randf_range(0.0, 0.33), (sub / 3) / 3.0 - 0.5 + rng.randf_range(0.0, 0.33))
			var br := VL.blocked_v(CV, q)
			if not ((br == "" or br == "trunk" or br == "obstacle") and not sealed(CV, q)) or VL.p7_covered(CV, q):
				continue
			var fz := (1.0 - VL.pilot_k(q)) * VL.memb(CV, q).x
			if fz < 0.05:
				continue
			var pd := path_d(MV, q)
			if pd.x < 0.3:
				continue
			var sk: Array = spot_k(MV, q)
			if float(sk[0]) > 0.5:
				continue
			# ① 縁の丈草の房（帯にしない：低周波の斑で途切れる）
			var cl := ML.patch(q, 7.0, 131.0)
			var clk := smoothstep(0.55, 0.66, cl)
			var fdq := fdist(MV, q)
			if fdq > 0.3 and fdq < 4.6:
				clk = maxf(clk, smoothstep(0.6, 0.72, ML.patch(q, 9.0, 137.0)))
			var ek := edge_k_mv(P, q) * clk * smoothstep(0.3, 1.2, pd.x) * (1.0 - VL.pilot_k(q))
			if ek > 0.05 and rng.randf() < ek * (0.45 + 0.5 * maxf(smoothstep(0.62, 0.75, cl), clk - 0.35)):
				var kk := GC.K_STEM if rng.randf() < 0.32 else GC.K_FINE
				var hgt := minf(lerpf(0.34, 0.7, ek) * rng.randf_range(0.8, 1.12), 0.7)
				items.append(_gi(P, kk, q, hgt, rng.randf_range(1.0, 1.4), rng.randf() * TAU, GC.grass_col(rng, 0.2 + 0.35 * GC._n(q * 0.3, 1.0, 137.0)), tag0, "rough", rng))
				continue
			var gw := GC.grass_w(CV, q)
			# ② 小径の縁の踏まれた短い草（近景）
			if pd.x > 0.3 and pd.x < 1.1 and gw >= 0.4 and rng.randf() < 0.035 * fz:
				items.append(_gi(P, GC.K_SHORT, q, rng.randf_range(0.1, 0.17), 1.1, rng.randf() * TAU, GC.grass_col(rng, 0.35), tag0, "pathedge", rng))
				continue
			var wn := wall_near(MV, q)
			var dwq: float = wn[0]
			# ③ 雨落ちの線に小石
			if dwq > 0.82 and dwq < 1.25 and wn[1] != null and rng.randf() < 0.05 * fz:
				items.append(_gi(P, GC.K_PEBBLE, q, rng.randf_range(0.5, 0.9), 1.0, rng.randf() * TAU, Color(0.9, 0.9, 0.9), tag0, "drip", rng))
				continue
			# ④ 後場（土）の角・路地の低い草
			if yard_dirt and gw < 0.5 and wn[1] != null and dwq > 0.5 and dwq < 3.0:
				var w: ML.Wall = wn[1]
				var along: float = wn[2]
				var wl := w.a.distance_to(w.b)
				var src := maxf(1.0 - smoothstep(1.2, 3.5, minf(along, wl - along)), alley_k(MV, q, w))
				var ik := smoothstep(0.52, 0.64, ML.patch(q, 5.5, 107.0)) * smoothstep(1.2, 3.0, pd.x) * src * fz
				if ik > 0.05 and rng.randf() < 0.1 * ik:
					var ky := GC.K_SHORT if rng.randf() < 0.65 else GC.K_FINE
					items.append(_gi(P, ky, q, rng.randf_range(0.12, 0.25), rng.randf_range(1.0, 1.3), rng.randf() * TAU, GC.grass_col(rng, 0.3), tag0, "invade", rng))
					continue
			# ④' 路縁の外の草侵入（踏み広げの切れ目、草の地形の上だけ）
			var rq := VL.road_sd(CV, q)
			if roadside and rq > 0.35 and rq < 1.6 and gw >= 0.45 and ML.patch(q, 3.0, 281.0) < 0.4 and rng.randf() < 0.07 * fz:
				var kr := GC.K_SHORT if rng.randf() < 0.55 else GC.K_FINE
				items.append(_gi(P, kr, q, rng.randf_range(0.14, 0.26), rng.randf_range(1.0, 1.3), rng.randf() * TAU, GC.grass_col(rng, 0.3), tag0, "roadedge", rng))
				continue
			# ⑤ 村邊草地の野花（近景の點綴、3–5 輪の小さな群れ）
			if meadow and gw >= 0.5 and rng.randf() < 0.0035 * fz:
				var fk := GC.K_FLOWER_Y if rng.randf() < 0.55 else GC.K_FLOWER_V
				for f in rng.randi_range(3, 5):
					var fq := q + Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45))
					var brf := VL.blocked_v(CV, fq)
					if (brf == "" or brf == "trunk" or brf == "obstacle") and not sealed(CV, fq):
						items.append(_gi(P, fk, fq, rng.randf_range(0.22, 0.34), 1.0, rng.randf() * TAU, Color(1, 1, 1), tag0, "flower", rng))
	(P["items"] as Array).append_array(items)
	var stats: Dictionary = P["stats"]
	for it: Dictionary in items:
		var key := "%s/%s" % [it["zone"], it["tag"]]
		stats[key] = int(stats.get(key, 0)) + 1
	P["ms_mv"] = Time.get_ticks_msec() - t0


## 可見最上面に載せた草叢（GC.gi は地形基準なので差分だけ持ち上げる）
static func _gi(P: Dictionary, kind: int, q: Vector2, h: float, w: float, yaw: float, col: Color, zone: String, tag: String, _rng: RandomNumberGenerator) -> Dictionary:
	var S: RLib.TriSampler = (P["CV"] as Dictionary)["S"]
	var it := GC.gi(S, kind, q, h, w, yaw, col, zone, tag)
	it["y"] = float(it["y"]) + (top_h(P, q) - S.h(q.x, q.y))
	return it


# ─────────────────────────── 可見最上面ルール（全 overlay 共通の build rule） ───────────────────────────

## 烘焙用の P：Pilot＋全村 r5 の items／nodes を可見最上面へ持ち上げた複製（規劃と digest は地形基準のまま）。
##   Macro Pilot・全村 Macro の items は既に持ち上げ済み。
static func surface_copy(P: Dictionary) -> Dictionary:
	var Pb := P.duplicate()
	var S: RLib.TriSampler = (P["CV"] as Dictionary)["S"]
	var nv := int(P["n_village_items"])
	var items: Array = []
	var src: Array = P["items"]
	for i in src.size():
		var it: Dictionary = src[i]
		if i < nv and not P.has("_neg_nolift"):
			it = it.duplicate()
			var q: Vector2 = it["p"]
			it["y"] = float(it["y"]) + maxf(top_h(P, q) - S.h(q.x, q.y), 0.0)
		elif i >= nv and P.has("_neg_nolift"):
			it = it.duplicate()
			var q: Vector2 = it["p"]
			it["y"] = float(it["y"]) - maxf(top_h(P, q) - S.h(q.x, q.y), 0.0)
		items.append(it)
	var nodes: Array = []
	for n: Dictionary in P["nodes"]:
		var n2 := n
		if not P.has("_neg_nolift"):
			n2 = n.duplicate()
			var q: Vector2 = n2["p"]
			n2["y"] = float(n2["y"]) + maxf(top_h(P, q) - S.h(q.x, q.y), 0.0)
		nodes.append(n2)
	Pb["items"] = items
	Pb["nodes"] = nodes
	return Pb


## Pilot（Ground_*）と全村 r5（Ground/Village）の地面網格を可見最上面へ（地形・路面基準の offset を保つ）
static func lift_ground(P: Dictionary, root: Node3D) -> int:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var gnode := root.get_node("Ground")
	var targets: Array = []
	for ch in gnode.get_children():
		if ch is MeshInstance3D and String(ch.name).begins_with("Ground_"):
			targets.append(ch)
	var vg := gnode.get_node_or_null("Village")
	if vg != null:
		targets.append_array(vg.find_children("G_*", "MeshInstance3D", true, false))
	var n_lift := 0
	for mi: MeshInstance3D in targets:
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		var arr := am.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ch2 := 0
		for i in V.size():
			var q := Vector2(V[i].x, V[i].z)
			var base := maxf(S.h(q.x, q.y), _rh(CV, q))
			var top := top_h(P, q)
			if top > base + 0.002:
				V[i].y += top - base
				ch2 += 1
		if ch2 == 0:
			continue
		arr[Mesh.ARRAY_VERTEX] = V
		var m2 := ArrayMesh.new()
		m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m2.surface_set_material(0, am.surface_get_material(0))
		m2.resource_name = am.resource_name
		mi.mesh = m2
		n_lift += ch2
	root.set_meta("surface_lifted_verts", n_lift)
	return n_lift


static func bake_mv(P: Dictionary, root: Node3D) -> int:
	var gnode := root.get_node("Ground")
	var mg := Node3D.new()
	mg.name = "MacroVillage"
	gnode.add_child(mg)
	var mat := ML.material_m()
	mat.resource_name = "GC_MacroVillage"
	var nv := 0
	var nc := 0
	for ck: Vector2i in chunk_keys_mv(P):
		var m := ground_chunk_mv(P, ck)
		if m == null:
			continue
		m.surface_set_material(0, mat)
		var g := MeshInstance3D.new()
		g.name = "MV_%d_%d" % [ck.x, ck.y]
		g.mesh = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 140.0
		g.visibility_range_end_margin = 10.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mg.add_child(g)
		nv += m.surface_get_array_len(0)
		nc += 1
	root.set_meta("mv_ground_chunks", nc)
	root.set_meta("mv_ground_verts", nv)
	return nv


# ─────────────────────────── Macro Pilot m9 凍結 ───────────────────────────

## Macro Pilot（A/B/C）の規劃 items と地面網格の sha256
static func m9_digest(P: Dictionary, with_ground := true) -> Array:
	var s := ""
	var items: Array = P["items"]
	for i in range(int(P["n_village_items"]), int(P["n_macro_items"])):
		var it: Dictionary = items[i]
		var p: Vector2 = it["p"]
		var c: Color = it["col"]
		s += "%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%s|%s\n" % [int(it["k"]), p.x, p.y, float(it["y"]), float(it["h"]), float(it["w"]), float(it["yaw"]), c.r, c.g, c.b, it["zone"], it["tag"]]
	var g := ""
	if with_ground:
		for zn: String in VL.MACRO_ZONES:
			var m := ML.ground_mesh_m(P, zn)
			var arr := m.surface_get_arrays(0)
			var hs := HashingContext.new()
			hs.start(HashingContext.HASH_SHA256)
			for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX]:
				hs.update(arr[a].to_byte_array())
			g += hs.finish().hex_encode()
		g = g.sha256_text()
	return [s.sha256_text(), g]
