extends SceneTree
## 人間之里 V2：P4 Greybox gate（headless）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_greybox.gd
##
## 輸入：P3 已核准的 maps/village_v2/gen/parcels.json（不重算地塊）＋ P4 maps/village_v2/gen/greybox.json ＋ 場景。
## 使用者裁示（2026-09-24）：
##   - 正式町家地塊（machiya）一塊一棟主屋；
##   - aux 不強制放建築：只有 use「倉／小屋」可放一棟小附屬棟，「庭院／後院／空地」不得有建築；
##   - 鈴奈庵／鯢吞亭壓主街由 P4 解：灰盒壓路幅面積必須 0，且 P0 凍結的 landmarks 不動（freeze gate 另管）。
## 檢查：
##   1 greybox.json 與目前 layout＋parcels 重算一致；場景節點與檔案一一對應（位置 ≤ 0.02 m）。
##   2 町家：每塊正好 1 棟、aux 依 use、地標 3 棟；建築 footprint 完整在自己的地塊內（容差 0.02 m）。
##   3 建築（牆體 footprint）不壓任何道路／巷道路幅（含 front_gap 以外的路緣：離路緣 ≥ 0）；建築之間不重疊。
##   4 屋簷／庇的水平投影不伸進任何路幅（簷口離路緣 ≥ 0）。
##   5 尺寸：町家面寬 ≥ MIN_W、縱深 main_depth；簷高依類型、屋脊 > 簷高；町家簷高 2.9–5.4 m、屋脊 ≤ RIDGE_MAX。
##   6 接地：台基頂 ＝ footprint 最高地面＋plinth（±0.02）；基礎底低於 footprint 最低地面（不浮空）；
##     基礎埋深 ≤ EMBED_MAX＋relief（不是整棟埋進地裡）。
##   7 入口：正面朝自己的道路（front_dir 與地塊一致），入口前（正面外 0.6 m）地面與台基頂高差 ≤ ENTRY_STEP_MAX。
##   8 地標：鈴奈庵／鯢吞亭／霧雨店 灰盒壓主街路幅 0 m²、正面平行主街（夾角 ≤ 1°）、完整在固定地塊內；
##     P0 線框已由灰盒取代（地標節點下沒有 Wire）。
##   9 主街 D/H：主街兩側建築正面間距 ÷ 簷高（同段兩側的平均），每 4 m 取樣，報中位數與範圍（INFO＋上限檢查）。
## 每項一行 [GB] PASS/FAIL；結尾 quit(失敗項數)。

const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const GLib := preload("res://tools/village_v2_greybox_lib.gd")
const TOL := 0.02
const MIN_W := 4.0
const EAVE_BAND := [2.9, 5.4]
const RIDGE_MAX := 9.0
const EMBED_MAX := 0.35
const ENTRY_STEP_MAX := 0.75
const LM_ROAD := ["LANDMARK_SUZUNAAN", "LANDMARK_GEIDONTEI", "LANDMARK_KIRISAME"]

var fails := 0
var L: Dictionary
var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[GB] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _ground(p: Vector2) -> float:
	var ex: Array[RID] = []
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.y), Vector3(p.x, -80.0, p.y))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if hit["rid"] == terrain_rid:
			return float(hit["position"].y)
		ex.append(hit["rid"])
	return NAN


func _run() -> void:
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var recs: Array = PJ["parcels"]
	var byid := {}
	for r in recs:
		byid[String(r["id"])] = r
	if not FileAccess.file_exists(GREYBOX):
		check("greybox.json 存在", false)
		quit(fails)
		return
	var GJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GREYBOX))
	var bl: Array = GJ["buildings"]
	check("greybox.json 版本 %s ＝ layout %s" % [GJ["layout_version"], L["version"]], GJ["layout_version"] == L["version"])
	var net := PLib.network(L)
	# 1 重算一致（地面高取 Terrain 碰撞）
	var re: Dictionary = GLib.plan(L, recs, net, _ground)
	var want := {}
	for b in re["buildings"]:
		want[String(b["id"])] = b
	var diff := 0
	var diff_ex := ""
	for b in bl:
		var id := String(b["id"])
		if not want.has(id):
			diff += 1
			diff_ex = id
			continue
		var w: Dictionary = want[id]
		var fp := TLib.pts(b["footprint"])
		var dmax := 0.0
		for k in 4:
			dmax = maxf(dmax, fp[k].distance_to((w["poly"] as PackedVector2Array)[k]))
		if dmax > TOL or absf(float(b["base_h"]) - float(w["base"])) > 0.05 or String(b["type"]) != String(w["type"]):
			diff += 1
			diff_ex = "%s（角點差 %.2f m、base %.2f vs %.2f）" % [id, dmax, float(b["base_h"]), float(w["base"])]
	check("greybox.json 與目前 layout＋parcels 重算一致（%d 棟 vs 重算 %d 棟，不一致 %d%s）" % [bl.size(), want.size(), diff,
		("，例 " + diff_ex) if diff > 0 else ""], diff == 0 and want.size() == bl.size())
	# 場景節點
	var nodes := {}
	for d in v.get_node("Districts").get_children():
		var bg := d.get_node_or_null("Buildings")
		if bg != null:
			for n in bg.get_children():
				nodes[String(n.name)] = n
	for lid in LM_ROAD:
		var n := v.get_node_or_null("Landmarks/%s/Greybox" % lid)
		if n != null:
			nodes["B_P_LM_" + lid.substr(9)] = n
	var miss := 0
	var moved := 0
	for b in bl:
		var id := String(b["id"])
		if not nodes.has(id):
			miss += 1
			continue
		var n: Node3D = nodes[id]
		var fp := TLib.pts(b["footprint"])
		var c := (fp[0] + fp[1] + fp[2] + fp[3]) * 0.25
		var gp := n.global_position
		if Vector2(gp.x, gp.z).distance_to(c) > TOL or absf(gp.y - float(b["base_h"])) > TOL:
			moved += 1
	check("場景建築節點 %d 個 ＝ 檔案 %d 棟（缺 %d、位置不符 %d）" % [nodes.size(), bl.size(), miss, moved],
		miss == 0 and moved == 0 and nodes.size() == bl.size())
	# 2 一塊一棟、aux 依 use
	var per := {}
	for b in bl:
		per[String(b["parcel"])] = int(per.get(String(b["parcel"]), 0)) + 1
	var n_m := 0
	var bad_m: Array = []
	var bad_a: Array = []
	var aux_use := {}
	var aux_built := 0
	for r in recs:
		var id := String(r["id"])
		var cnt := int(per.get(id, 0))
		if r["kind"] == "machiya":
			n_m += 1
			if cnt != 1:
				bad_m.append("%s×%d" % [id, cnt])
		elif r["kind"] == "aux":
			var use := String(r.get("use", ""))
			aux_use[use] = int(aux_use.get(use, 0)) + 1
			aux_built += cnt
			if cnt > (1 if use == String(L["greybox"]["aux"]["use_build"]) else 0):
				bad_a.append("%s（%s）×%d" % [id, use, cnt])
	check("正式町家 %d 塊，每塊正好 1 棟主屋：違規 %d%s" % [n_m, bad_m.size(), ("：" + "、".join(bad_m.slice(0, 5))) if bad_m else ""],
		bad_m.is_empty() and n_m > 0)
	check("aux %d 塊不強制建築（use %s）；只有「倉／小屋」可放 1 棟，實放 %d 棟；庭院／後院／空地有建築 %d 塊%s" % [
		aux_use.values().reduce(func(a, x): return a + x, 0), aux_use, aux_built, bad_a.size(),
		("：" + "、".join(bad_a)) if bad_a else ""], bad_a.is_empty())
	# 2b footprint 在自己的地塊內
	var outside: Array = []
	for b in bl:
		var pr: Dictionary = byid.get(String(b["parcel"]), {})
		if pr.is_empty():
			outside.append(String(b["id"]) + "（找不到地塊）")
			continue
		var pp := TLib.pts(pr["footprint"])
		var g := Geometry2D.offset_polygon(pp, TOL, Geometry2D.JOIN_MITER)
		var gpp: PackedVector2Array = g[0] if not g.is_empty() else pp
		for p in TLib.pts(b["footprint"]):
			if not Geometry2D.is_point_in_polygon(p, gpp):
				outside.append(String(b["id"]))
				break
	check("建築 footprint 完整在自己的地塊內（容差 %.2f m）：超出 %d%s" % [TOL, outside.size(),
		("：" + "、".join(outside.slice(0, 5))) if outside else ""], outside.is_empty())
	# 3 不壓路幅、互不重疊；4 簷／庇投影不伸進路幅
	var worst_wall := INF
	var worst_wall_id := ""
	var worst_roof := INF
	var worst_roof_id := ""
	var polys: Array = []
	for b in bl:
		var fp := TLib.pts(b["footprint"])
		polys.append(fp)
		var dirv := Vector2(float(b["front_dir"][0]), float(b["front_dir"][1]))
		var tt := Vector2(-dirv.y, dirv.x)
		var hira: bool = b["roof"] == "hira"
		var ov_e := float(b["ov_eave_m"])
		var ov_g := float(b["ov_gable_m"])
		var of := maxf(ov_e if hira else ov_g, float(b["hisashi_depth_m"]))   # 正面：簷（平入）或山牆（妻入），庇取大
		var ob := ov_e if hira else ov_g                                       # 背面
		var os := ov_g if hira else ov_e                                       # 兩側
		var rp := PackedVector2Array([fp[0] + dirv * of - tt * os, fp[1] + dirv * of + tt * os,
			fp[2] - dirv * ob + tt * os, fp[3] - dirv * ob - tt * os])
		for r in net:
			var dw := PLib.poly_line_d(fp, r["pts"]) - float(r["hw"])
			if dw < worst_wall:
				worst_wall = dw
				worst_wall_id = "%s×%s" % [b["id"], r["name"]]
			var dr := PLib.poly_line_d(rp, r["pts"]) - float(r["hw"])
			if dr < worst_roof:
				worst_roof = dr
				worst_roof_id = "%s×%s" % [b["id"], r["name"]]
	check("建築牆體離最近路緣最小 %.2f m（%s；下限 0）" % [worst_wall, worst_wall_id], worst_wall >= -0.01)
	check("屋簷／庇水平投影離最近路緣最小 %.2f m（%s；下限 0，不伸進路幅）" % [worst_roof, worst_roof_id], worst_roof >= -0.01)
	var ov := 0
	var ov_ex := ""
	for i in polys.size():
		var bbi := _bbox(polys[i])
		for j in range(i + 1, polys.size()):
			if not bbi.intersects(_bbox(polys[j])):
				continue
			var a := PLib.overlap_area(polys[i], polys[j])
			if a > 0.05:
				ov += 1
				ov_ex = "%s×%s %.2f m²" % [bl[i]["id"], bl[j]["id"], a]
	check("建築之間重疊 %d 對%s" % [ov, ("：" + ov_ex) if ov > 0 else ""], ov == 0)
	# 5 尺寸
	var G: Dictionary = L["greybox"]
	var md: Array = G["main_depth"]
	var bad_s: Array = []
	var eave_lo := INF
	var eave_hi := -INF
	var ridge_hi := -INF
	var wmin := INF
	var dmin := INF
	var dmax_ := -INF
	var types := {}
	for b in bl:
		var e := float(b["eave_m"])
		var rg := float(b["ridge_m"])
		if rg <= e:
			bad_s.append("%s 屋脊 %.2f ≤ 簷 %.2f" % [b["id"], rg, e])
		if b["kind"] == "machiya":
			types[b["type"]] = int(types.get(b["type"], 0)) + 1
			eave_lo = minf(eave_lo, e)
			eave_hi = maxf(eave_hi, e)
			ridge_hi = maxf(ridge_hi, rg)
			wmin = minf(wmin, float(b["width_m"]))
			dmin = minf(dmin, float(b["depth_m"]))
			dmax_ = maxf(dmax_, float(b["depth_m"]))
			if float(b["width_m"]) < MIN_W or float(b["depth_m"]) < float(md[0]) - TOL or float(b["depth_m"]) > float(md[1]) + TOL:
				bad_s.append("%s %.2f×%.2f" % [b["id"], float(b["width_m"]), float(b["depth_m"])])
			if e < EAVE_BAND[0] - TOL or e > EAVE_BAND[1] + TOL or rg > RIDGE_MAX:
				bad_s.append("%s 簷 %.2f 脊 %.2f" % [b["id"], e, rg])
	check("町家量體：面寬 ≥ %.1f（實測 ≥ %.2f）、縱深 %.2f–%.2f（實測 %.2f–%.2f）、簷高 %.1f–%.1f（實測 %.2f–%.2f）、屋脊 ≤ %.1f（實測 ≤ %.2f）m；類型 %s：違規 %d%s" % [
		MIN_W, wmin, float(md[0]), float(md[1]), dmin, dmax_, EAVE_BAND[0], EAVE_BAND[1], eave_lo, eave_hi, RIDGE_MAX, ridge_hi,
		types, bad_s.size(), ("：" + "、".join(bad_s.slice(0, 5))) if bad_s else ""], bad_s.is_empty())
	# 6 接地；7 入口
	var bad_g: Array = []
	var bad_e: Array = []
	var emb_hi := 0.0
	var step_hi := 0.0
	var step_id := ""
	for b in bl:
		var fp := TLib.pts(b["footprint"])
		var lo := INF
		var hi := -INF
		var u := fp[1] - fp[0]
		var w := fp[3] - fp[0]
		var nu := maxi(1, int(ceil(u.length())))
		var nw := maxi(1, int(ceil(w.length())))
		for i in nu + 1:
			for j in nw + 1:
				var h := _ground(fp[0] + u * (float(i) / nu) + w * (float(j) / nw))
				if is_nan(h):
					continue
				lo = minf(lo, h)
				hi = maxf(hi, h)
		var n: Node3D = nodes.get(String(b["id"]))
		if n == null:
			continue
		var f := n.get_node("Foundation") as MeshInstance3D
		var fab: AABB = f.global_transform * f.mesh.get_aabb()
		var top := fab.end.y
		var bot := fab.position.y
		if absf(top - (hi + float(b["plinth_m"]))) > 0.05 or bot > lo - 0.01:
			bad_g.append("%s 台基頂 %.2f（應 %.2f）、底 %.2f（地面最低 %.2f）" % [b["id"], top, hi + float(b["plinth_m"]), bot, lo])
		emb_hi = maxf(emb_hi, lo - bot)
		if lo - bot > EMBED_MAX + (hi - lo) + 0.05:
			bad_g.append("%s 埋深 %.2f" % [b["id"], lo - bot])
		var dirv := Vector2(float(b["front_dir"][0]), float(b["front_dir"][1]))
		var fm := (fp[0] + fp[1]) * 0.5
		var eg := _ground(fm + dirv * 0.6)
		var step := top - eg
		if step > step_hi:
			step_hi = step
			step_id = String(b["id"])
		if step > ENTRY_STEP_MAX or step < 0.0:
			bad_e.append("%s 入口段差 %.2f" % [b["id"], step])
		var pr: Dictionary = byid.get(String(b["parcel"]), {})
		if not pr.is_empty() and pr.has("front_dir") and b["kind"] != "landmark":
			# 地塊 front_dir 只存到 0.01 → 正規化後比；容差 1°
			var pd := Vector2(float(pr["front_dir"][0]), float(pr["front_dir"][1])).normalized()
			if pd.dot(dirv) < cos(deg_to_rad(1.0)):
				bad_e.append("%s 正面不朝地塊道路（%.1f°）" % [b["id"], rad_to_deg(acos(clampf(pd.dot(dirv), -1.0, 1.0)))])
	check("接地：台基頂＝footprint 最高地面＋plinth、基礎底低於最低地面、埋深 ≤ %.2f＋地塊高低差（實測最大 %.2f m）：違規 %d%s" % [
		EMBED_MAX, emb_hi, bad_g.size(), ("：" + "、".join(bad_g.slice(0, 3))) if bad_g else ""], bad_g.is_empty())
	check("入口：正面朝自己的道路、入口前地面到台基頂段差 0–%.2f m（實測最大 %.2f m @ %s）：違規 %d%s" % [
		ENTRY_STEP_MAX, step_hi, step_id, bad_e.size(), ("：" + "、".join(bad_e.slice(0, 3))) if bad_e else ""], bad_e.is_empty())
	# 8 地標
	var ms: Dictionary = {}
	for r in net:
		if r["name"] == "MainStreet":
			ms = r
	var road_poly: PackedVector2Array = Geometry2D.offset_polyline(ms["pts"], float(ms["hw"]), Geometry2D.JOIN_ROUND,
		Geometry2D.END_ROUND)[0]
	for lid in LM_ROAD:
		var b: Dictionary = {}
		for e in bl:
			if String(e.get("landmark", "")) == lid:
				b = e
		if b.is_empty():
			check("%s 有 P4 灰盒" % lid, false)
			continue
		var fp := TLib.pts(b["footprint"])
		var enc := 0.0
		for hp in Geometry2D.intersect_polygons(fp, road_poly):
			enc += PLib.area(hp)
		var p0 := PLib.landmark_rect(_lm(lid))
		var enc0 := 0.0
		for hp in Geometry2D.intersect_polygons(p0, road_poly):
			enc0 += PLib.area(hp)
		var dirv := Vector2(float(b["front_dir"][0]), float(b["front_dir"][1]))
		var pts: PackedVector2Array = ms["pts"]
		var c := (fp[0] + fp[1] + fp[2] + fp[3]) * 0.25
		var bd := INF
		var t := Vector2.ZERO
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(c, pts[k], pts[k + 1])
			if q.distance_to(c) < bd:
				bd = q.distance_to(c)
				t = (pts[k + 1] - pts[k]).normalized()
		var ang := rad_to_deg(asin(clampf(absf(dirv.dot(t)), 0.0, 1.0)))
		var front_d := PLib.poly_line_d(fp, pts) - float(ms["hw"])
		var wire := v.get_node_or_null("Landmarks/%s/Wire" % lid)
		check("%s（%s）灰盒 %.2f×%.2f m、簷 %.1f／脊 %.2f m：壓主街路幅 %.2f m²（P0 box %.2f m²）、正面離路緣 %.2f m、正面與主街夾角 %.1f°、沿街平移 %.1f m、P0 線框 %s" % [
			lid, b["type"], float(b["width_m"]), float(b["depth_m"]), float(b["eave_m"]), float(b["ridge_m"]), enc, enc0,
			front_d, ang, float(b["shift_m"]), "已取代" if wire == null else "仍在"],
			enc < 0.001 and ang <= 1.0 and wire == null and front_d >= 0.5)
	# 9 主街 D/H：沿主街每 4 m，垂直主街兩側各找最近建築正面
	var dh: Array = []
	var s := 0.0
	var pts2: PackedVector2Array = ms["pts"]
	var fronts: Array = []   # [PackedVector2Array 正面線段, eave]
	for b in bl:
		if not ["MainStreet"].has(String(b["road"])):
			continue
		var fp := TLib.pts(b["footprint"])
		fronts.append([fp[0], fp[1], float(b["eave_m"])])
	for k in pts2.size() - 1:
		var a := pts2[k]
		var bb := pts2[k + 1]
		var t := (bb - a).normalized()
		var nn := Vector2(-t.y, t.x)
		var seg := a.distance_to(bb)
		var u := 2.0
		while u < seg:
			var p := a + t * u
			var side := [INF, INF]
			var eav := [0.0, 0.0]
			for f in fronts:
				for si in 2:
					var dirn: Vector2 = nn if si == 0 else -nn
					var hit = Geometry2D.segment_intersects_segment(p, p + dirn * 20.0, f[0], f[1])
					if hit != null:
						var dd := p.distance_to(hit)
						if dd < side[si]:
							side[si] = dd
							eav[si] = f[2]
			if side[0] < 20.0 and side[1] < 20.0:
				dh.append((side[0] + side[1]) / ((eav[0] + eav[1]) * 0.5))
			u += 4.0
	dh.sort()
	if dh.is_empty():
		check("主街 D/H 取樣", false)
	else:
		# INFO（不設門檻）：沒有使用者核可的 D/H 數字。參考值＝docs/village-concept-reference.md「概念圖 1:1～1.5、slice 1:2～1:3」。
		# 主街全寬 7.20 m（W80 凍結）＋兩側 front_gap 0.5 m → 正面間距 8.2 m；總二階簷高 5.4 m 時 D/H 最低 1.52。
		print("[GB] INFO 主街 D/H（兩側建築正面間距 ÷ 平均簷高，兩側都有建築的測站 %d 個）：中位 %.2f、範圍 %.2f–%.2f（參考：概念圖 1.0–1.5、V1 slice 2–3）" % [
			dh.size(), dh[dh.size() / 2], dh[0], dh[dh.size() - 1]])
	_full_sightlines(net)
	print("[GB] 結果：%d 項失敗" % fails)
	quit(fails)


## INFO（不設門檻）：永久 sightline gate 只把 Landmarks／QuestAnchors／Portals 當擋物（P1 定義）。
## P4 起町家也會擋，這裡把 Districts/*/Buildings＋地標灰盒全部算進去，報「看得到」的測站，供使用者裁示。
func _full_sightlines(net: Array) -> void:
	var occ: Array = []
	var groups: Array = []
	for g in ["Landmarks", "QuestAnchors", "Portals"]:
		groups.append_array(v.get_node(g).get_children())
	for d in v.get_node("Districts").get_children():
		var bg := d.get_node_or_null("Buildings")
		if bg != null:
			groups.append_array(bg.get_children())
	for n in groups:
		var faces := PackedVector3Array()
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null:
				continue
			var ab: AABB = (mi as MeshInstance3D).global_transform * m.get_aabb()
			if ab.size.y <= 0.3:
				continue
			var mf := m.get_faces()
			if mf.is_empty():
				continue
			for p in mf:
				faces.append((mi as MeshInstance3D).global_transform * p)
			box = ab if first else box.merge(ab)
			first = false
		if not faces.is_empty():
			occ.append([String(n.name), box, faces])
	var tg := {"龍神像": ["LANDMARK_DRAGON", _top("Landmarks/LANDMARK_DRAGON")],
		"山頂社殿": ["LANDMARK_NORTH_HILL", _top("Landmarks/LANDMARK_NORTH_HILL")],
		"南大鳥居": ["LANDMARK_SOUTH_GATE", _top("Landmarks/LANDMARK_SOUTH_GATE")]}
	var routes := {"MainStreet": [], "HillFootStreet": [], "RiverNorthPath": [], "DragonBridgeRoad": []}
	for r in net:
		if routes.has(r["name"]):
			routes[r["name"]] = r["pts"]
	for rn in routes:
		var pts: PackedVector2Array = routes[rn]
		var st: Array = []
		var s := 0.0
		var cum := 0.0
		for k in pts.size() - 1:
			var seg := pts[k].distance_to(pts[k + 1])
			while s <= cum + seg:
				var p := pts[k].lerp(pts[k + 1], (s - cum) / seg)
				st.append([p, _ground(p), s])
				s += 4.0
			cum += seg
		for k in tg:
			if rn != "MainStreet" and k != "龍神像":
				continue
			var vis: Array = []
			var who := {}
			for e in st:
				if is_nan(float(e[1])):
					continue
				var a: Vector2 = e[0]
				var hit := _occ_hits(occ, Vector3(a.x, float(e[1]) + 1.7, a.y), tg[k][1], String(tg[k][0]))
				if hit.is_empty():
					vis.append(int(e[2]))
				for h in hit:
					who[h] = int(who.get(h, 0)) + 1
			var ks := who.keys()
			ks.sort_custom(func(x, y): return who[x] > who[y])
			var top: Array = []
			for kk in ks.slice(0, 4):
				top.append("%s×%d" % [kk, who[kk]])
			print("[GB] INFO 全建築視線 眼高 1.7 m %s（%d 站）望%s：看得到 %d 站 %s；主要擋物 %s" % [
				rn, st.size(), k, vis.size(), str(vis) if vis.size() <= 20 else "(%d…%d m)" % [vis[0], vis[-1]], "、".join(top)])


func _top(path: String) -> Vector3:
	var n := v.get_node_or_null(path)
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = ab if first else box.merge(ab)
		first = false
	return Vector3(box.get_center().x, box.end.y - 0.3, box.get_center().z)


func _occ_hits(occ: Array, from: Vector3, to: Vector3, skip: String) -> Array:
	var out: Array = []
	for o in occ:
		if o[0] == skip or not (o[1] as AABB).grow(0.05).intersects_segment(from, to):
			continue
		var f: PackedVector3Array = o[2]
		for t in range(0, f.size(), 3):
			if Geometry3D.segment_intersects_triangle(from, to, f[t], f[t + 1], f[t + 2]) != null:
				out.append(o[0])
				break
	return out


func _lm(id: String) -> Dictionary:
	for e in L["landmarks"]:
		if String(e["id"]) == id:
			return e
	return {}


func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
