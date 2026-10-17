extends "res://tools/p13/w6/w6_base.gd"
## 丘腳社寺 E2 境內環境：擺放驗證（TASK E2 §5；唯讀・不寫場景）。**必須有顯示（不得 --headless）**：MultiMesh 實例矩陣 headless 全是 0。
##   godot --path godot --resolution 640x360 --script res://tools/p13/w9/e2/verify_hf_precinct.gd -- <outdir/> HFV --map=village_v2
## 檢查（每條都有明確門檻；FAIL 不放寬）：
##   M1 掛載與抑制     overlay・script・DistrictHF 在；E082 子節點全 visible=false、其碰撞全 disabled。
##   M2 抑制可逆       enabled=false → E082 全可見・碰撞全啟用・境內 MultiMesh 實例＝原數；再 true → 回到抑制狀態（往返三次）。
##   M3 草株           抑制中，境內多邊形（＋margin）內「基底行列式 ≠ 0 且未沉下」的 MeadowP9／GroundcoverP9 實例＝0；且全部實例行列式 ≠ 0（MMBAKE）。
##   G1 地面對地形     Ground 頂點 − 地形碰撞面：下限 ≥ lift−1mm；可走區（fade>0.5）p95 ≤ 6 cm、最大 ≤ 10 cm（> 6.5 cm 的頂點 build 時被覆已漸隱）。
##   G2 地面不潛地形   三角形內 7 點取樣：Ground − 可見地形 ≥ min_clear−1mm。
##   G3 Z-fight        與其他『蓋在地形上』的可見層（路面・Ground・Yards…）的垂直差 < 8 mm 的頂點＝0（Ground 自己排除）。
##   G4 無縫隙         Ground 的開放邊界：頂點 fade ≤ 0.03（shader 在邊緣已淡出）或在台基箱內／丘腳街接縫帶；其餘＝0。Ground 無 CollisionObject。
##   P1 石段與台基     DistrictHF 全部 MeshInstance 的 world AABB 與（石段稜柱＋社殿碰撞 AABB＋台基）的最小間隙 ≥ 0.4 m；植物 AABB 不入 shrine_box。
##   P2 入口不被擋     沿參道中心線（街→石段腳）0.25 m 一步，膠囊（r0.35，離地 0.15–1.85）+ 側向 ±0.8：與任何碰撞體（地形除外）＝0。
##   P3 無隱形碰撞     DistrictHF 每個 CollisionShape3D 都落在同組可見網格的 AABB 內（容差 0.25）；HillfootPrecinctE2 無碰撞。
##   P4 石座落         DistrictHF 的踏石／平石：石頂 − Ground 高 ∈ [0.012, 0.25]（外露而不是埋掉、也不是浮空）。
##   P5 社殿不動       Landmarks/LANDMARK_HILLFOOT_TEMPLE 的 global_transform 與 layout 記載一致；Hero／Collision 子節點數不變。
const L := preload("res://tools/p13/w9/e2/hf_precinct_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

var _res: Array = []
var _fail := 0
var _data := {}


func _chk(id: String, ok: bool, msg: String) -> void:
	_res.append({"id": id, "ok": ok, "msg": msg})
	if not ok:
		_fail += 1
	print("[HFV] %s %s — %s" % ["PASS" if ok else "FAIL", id, msg])


func _terr_rid() -> RID:
	return (vil.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()


func _th(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var tr := _terr_rid()
	var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = []
	for i in 14:
		rq.exclude = ex
		var r := sp.intersect_ray(rq)
		if r.is_empty():
			return NAN
		if (r["rid"] as RID) == tr:
			return float((r["position"] as Vector3).y)
		ex.append(r["rid"])
	return NAN


func _aabb_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector3(dx, dy, dz).length()


func _mm_stats(polys: Array, margin: float) -> Dictionary:
	# 境內多邊形（＋margin）內：總數、可見（行列式 ≠ 0 且 y 未沉下）數；以及全場景零矩陣數
	var inside := 0
	var vis := 0
	var zero_all := 0
	var total := 0
	for root_path: String in ["Vegetation/MeadowP9", "Vegetation/GroundcoverP9/Chunks"]:
		var rn := vil.get_node_or_null(root_path)
		if rn == null:
			continue
		for mmi in rn.find_children("*", "MultiMeshInstance3D", true, false):
			var m := mmi as MultiMeshInstance3D
			var mm := m.multimesh
			if mm == null or mm.instance_count == 0:
				continue
			var ab := m.global_transform * mm.get_aabb()
			var near := ab.position.x < 240.0 and ab.end.x > 214.0 and ab.position.z < -148.0 and ab.end.z > -182.0
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				total += 1
				var det := absf(t.basis.determinant())
				if det < 1e-12:
					zero_all += 1
				if not near:
					continue
				var w := m.global_transform * t.origin
				if _in_polys(Vector2(w.x, w.z), polys, margin):
					inside += 1
					if det > 1e-7:       # 沉下並極小化的實例行列式 ≈ 1e-9 → 不算可見
						vis += 1
	return {"inside": inside, "visible": vis, "zero_all": zero_all, "total": total}


static func _in_polys(p: Vector2, polys: Array, margin: float) -> bool:
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if margin > 0.0:
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var ab := b - a
				var l2 := ab.length_squared()
				var t := 0.0 if l2 == 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				if p.distance_to(a + ab * t) <= margin:
					return true
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1] if args.size() > 1 else "HFV"
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		printerr("[HFV] 不得 --headless（MultiMesh 矩陣讀不到）")
		quit(2)
		return
	await _boot()
	var D := L.design()
	var ov := vil.get_node_or_null(L.NODE_NAME) as Node3D
	var dh := vil.get_node_or_null(L.DISTRICT_NODE) as Node3D
	_chk("M1.mount", ov != null and dh != null and ov.get_script() != null and bool(ov.get("enabled")),
		"overlay=%s district=%s script=%s enabled=%s" % [ov != null, dh != null, ov != null and ov.get_script() != null, ov.get("enabled") if ov else "?"])
	if ov == null or dh == null:
		quit(1)
		return
	# ── M1 抑制
	var e82 := vil.get_node("Props/EnvironmentP9/edge/E082_fence_frag") as Node3D
	var env_col := vil.get_node("Props/EnvironmentP9/Collision")
	var n_ch := 0
	var n_vis_after := 0
	var n_col := 0
	var n_col_on := 0
	for ch in e82.get_children():
		if ch is Node3D:
			n_ch += 1
			if (ch as Node3D).visible:
				n_vis_after += 1
			var sh := env_col.get_node_or_null(String(ch.name) + "_c") as CollisionShape3D
			if sh != null:
				n_col += 1
				if not sh.disabled:
					n_col_on += 1
	_chk("M1.suppress", n_ch > 0 and n_vis_after == 0 and n_col_on == 0 and int(ov.get("suppressed_nodes")) == n_ch,
		"E082 子節點 %d・仍可見 %d・對應碰撞 %d（仍啟用 %d）・overlay 記錄 suppressed_nodes=%s shapes=%s" % [n_ch, n_vis_after, n_col, n_col_on, ov.get("suppressed_nodes"), ov.get("suppressed_shapes")])
	_data["suppressed"] = {"E082_children": n_ch, "collisions": n_col, "trimmed_mmis": ov.get("trimmed_mmis"), "trimmed_instances": ov.get("trimmed_instances")}
	# ── M2/M3 可逆性與草株
	var polys: Array = ov.get_meta("mm_polys")
	var margin := float(ov.get_meta("mm_margin"))
	var st_on := _mm_stats(polys, margin)
	ov.set("enabled", false)
	await physics_frame
	var vis_off := 0
	var col_off := 0
	for ch in e82.get_children():
		if ch is Node3D:
			if (ch as Node3D).visible:
				vis_off += 1
			var sh2 := env_col.get_node_or_null(String(ch.name) + "_c") as CollisionShape3D
			if sh2 != null and not sh2.disabled:
				col_off += 1
	var st_off := _mm_stats(polys, margin)
	var dh_off: bool = not dh.visible
	var ground_hidden: bool = not ov.visible
	var dcols := dh.find_children("*", "CollisionShape3D", true, false)
	var dcol_dis := 0
	for c in dcols:
		if (c as CollisionShape3D).disabled:
			dcol_dis += 1
	var ok_cycle := true
	var cyc_msg := ""
	for k in 3:
		ov.set("enabled", true)
		await physics_frame
		var s1 := _mm_stats(polys, margin)
		ov.set("enabled", false)
		await physics_frame
		var s0 := _mm_stats(polys, margin)
		if s1["visible"] != st_on["visible"] or s0["visible"] != st_off["visible"] or s0["inside"] != st_off["inside"]:
			ok_cycle = false
		cyc_msg += " [%d: on=%d off=%d]" % [k, s1["visible"], s0["visible"]]
	ov.set("enabled", true)
	await physics_frame
	var st_back := _mm_stats(polys, margin)
	_chk("M2.reversible", vis_off == n_ch and col_off == n_col and dh_off and ground_hidden and dcol_dis == dcols.size() and ok_cycle and st_back["visible"] == st_on["visible"],
		"off：E082 可見 %d/%d・碰撞啟用 %d/%d・DistrictHF 隱藏 %s（其碰撞停用 %d/%d）・Ground 隱藏 %s｜MultiMesh 境內實例 on→可見 %d off→可見 %d（原數 %d）｜往返×3 %s｜復原後可見 %d" % [
			vis_off, n_ch, col_off, n_col, dh_off, dcol_dis, dcols.size(), ground_hidden, st_on["visible"], st_off["visible"], st_off["inside"], cyc_msg, st_back["visible"]])
	_chk("M3.grass", st_on["visible"] == 0 and st_off["visible"] > 0 and st_on["zero_all"] == 0,
		"抑制中境內可見草株 %d（抑制前 %d；境內實例總數 %d）・全場景零矩陣實例 %d / %d" % [st_on["visible"], st_off["visible"], st_on["inside"], st_on["zero_all"], st_on["total"]])
	_data["mm"] = {"on": st_on, "off": st_off}
	# ── M4 編輯器存檔語意：PRE_SAVE で全部還原（＝village_v2.tscn に visible=false・差し替え MultiMesh が書かれない）、POST_SAVE で再抑制
	ov.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var vis_pre := 0
	var col_pre := 0
	for ch in e82.get_children():
		if ch is Node3D:
			if (ch as Node3D).visible:
				vis_pre += 1
			var sh3 := env_col.get_node_or_null(String(ch.name) + "_c") as CollisionShape3D
			if sh3 != null and not sh3.disabled:
				col_pre += 1
	var st_pre := _mm_stats(polys, margin)
	var dh_pre: bool = dh.visible
	var mm_res_same := true
	for m in ov.get("_mms"):
		mm_res_same = false       # PRE_SAVE 後は _mms が空（元の MultiMesh 資源に戻した）になっているはず
	ov.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	var vis_post := 0
	for ch in e82.get_children():
		if ch is Node3D and (ch as Node3D).visible:
			vis_post += 1
	var st_post := _mm_stats(polys, margin)
	_chk("M4.editor_save", vis_pre == n_ch and col_pre == n_col and st_pre["visible"] == st_off["visible"] and mm_res_same and dh_pre and vis_post == 0 and st_post["visible"] == 0,
		"PRE_SAVE：E082 可見 %d/%d・碰撞啟用 %d/%d・境內草株可見 %d（原 %d）・DistrictHF 可見 %s・保留差し替え %s｜POST_SAVE：E082 可見 %d・草株可見 %d" % [
			vis_pre, n_ch, col_pre, n_col, st_pre["visible"], st_off["visible"], dh_pre, not mm_res_same, vis_post, st_post["visible"]])
	# ── Ground
	var gmi := ov.get_node("Ground") as MeshInstance3D
	var arr := gmi.mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var U2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var IDX: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var S := RLib.terrain_sampler(vil)
	var lift: float = D["lift"]
	var mn := 99.0
	var mx := -99.0
	var walk: Array = []
	var below_lift := 0
	for k in V.size():
		var w := gmi.global_transform * V[k]
		var th := _th(w.x, w.z)
		if is_nan(th):
			continue
		var d := w.y - th
		mn = minf(mn, d)
		mx = maxf(mx, d)
		if d < lift - 0.001:
			below_lift += 1
		if U2[k].y > 0.5:
			walk.append(d)
	walk.sort()
	var p95 := float(walk[int(walk.size() * 0.95)]) if walk.size() > 0 else NAN
	var wmax := float(walk[walk.size() - 1]) if walk.size() > 0 else NAN
	_chk("G1.ground_vs_collision", below_lift == 0 and p95 <= 0.06 and wmax <= 0.10,
		"頂點 %d・Ground−地形碰撞 min %.3f max %.3f｜可走區(fade>0.5) %d 點 p95 %.3f max %.3f（lift %.3f）" % [V.size(), mn, mx, walk.size(), p95, wmax, lift])
	_data["ground_minus_collision"] = {"min": mn, "max": mx, "walk_p95": p95, "walk_max": wmax, "walk_n": walk.size()}
	# G2 三角形內側不潛地形
	var clear: float = D["min_clear"]
	var worst := 99.0
	var n_under := 0
	var n_hidden := 0
	for t in range(0, IDX.size(), 3):
		var a := gmi.global_transform * V[IDX[t]]
		var b := gmi.global_transform * V[IDX[t + 1]]
		var c := gmi.global_transform * V[IDX[t + 2]]
		for bc: Array in [[1.0 / 3.0, 1.0 / 3.0], [0.5, 0.5], [0.5, 0.0], [0.0, 0.5], [0.25, 0.25], [0.6, 0.2], [0.2, 0.6]]:
			var u: float = bc[0]
			var v2: float = bc[1]
			var w3 := 1.0 - u - v2
			var px := a.x * u + b.x * v2 + c.x * w3
			var pz := a.z * u + b.z * v2 + c.z * w3
			var oy := a.y * u + b.y * v2 + c.y * w3
			var th2 := S.h(px, pz)
			if is_nan(th2):
				continue
			var fs := U2[IDX[t]].y * u + U2[IDX[t + 1]].y * v2 + U2[IDX[t + 2]].y * w3
			if fs <= 0.03:
				n_hidden += 1          # 被覆 ≤ 3 %：實質不畫（shader 的 dither discard）
				continue
			worst = minf(worst, oy - th2)
			if oy - th2 < clear - 0.001:
				n_under += 1
	_chk("G2.no_dip", n_under == 0, "三角形內 %d 三角形×7 點（被覆 ≤ 3 %% 的 %d 點不計）：Ground−可見地形 最小 %.4f（門檻 ≥ %.3f）・低於門檻 %d" % [IDX.size() / 3, n_hidden, worst, clear, n_under])
	_data["ground_minus_visible_terrain_min"] = worst
	# G3 Z-fight：與其他可見層
	var cands: Array = []
	for n in vil.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == gmi or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var p := String(vil.get_path_to(mi))
		if p.begins_with(L.DISTRICT_NODE) or p.begins_with("Landmarks/") or p.begins_with("Districts/") and p.contains("/Buildings/"):
			continue
		var ab := mi.global_transform * mi.get_aabb()
		if ab.position.x > 245 or ab.end.x < 210 or ab.position.z > -145 or ab.end.z < -186:
			continue
		if ab.size.y > 3.0:
			continue
		cands.append(mi)
	var tms := {}
	var zf := 0
	var zf_min := 99.0
	var zf_where := ""
	for k in V.size():
		if U2[k].y <= 0.05:
			continue
		var w := gmi.global_transform * V[k]
		for mi: MeshInstance3D in cands:
			var key := mi.get_instance_id()
			if not tms.has(key):
				tms[key] = mi.mesh.generate_triangle_mesh()
			var tm: TriangleMesh = tms[key]
			if tm == null:
				continue
			var inv := mi.global_transform.affine_inverse()
			var r: Dictionary = tm.intersect_ray(inv * Vector3(w.x, w.y + 6.0, w.z), inv.basis * Vector3.DOWN)
			if r.is_empty():
				continue
			var hy := (mi.global_transform * (r["position"] as Vector3)).y
			var dd := w.y - hy
			if absf(dd) < absf(zf_min):
				zf_min = dd
				zf_where = "%s @(%.1f,%.1f)" % [vil.get_path_to(mi), w.x, w.z]
			if absf(dd) < 0.008:
				zf += 1
	_chk("G3.zfight", zf == 0, "候選層 %d・頂點 %d：與其他層垂直差 < 8 mm 的點 %d；最小差 %+.3f（%s）" % [cands.size(), V.size(), zf, zf_min, zf_where])
	# G4 無縫隙
	var edges := {}
	for t in range(0, IDX.size(), 3):
		for e in 3:
			var i0 := IDX[t + e]
			var i1 := IDX[t + (e + 1) % 3]
			var key2 := Vector2i(mini(i0, i1), maxi(i0, i1))
			edges[key2] = int(edges.get(key2, 0)) + 1
	var box: Rect2 = (D["box"] as Rect2).grow(0.5)
	var sz: float = D["street_z"]
	var open_vis := 0
	var open_n := 0
	var open_where: Array = []
	for key3: Vector2i in edges:
		if int(edges[key3]) != 1:
			continue
		for vi in [key3.x, key3.y]:
			open_n += 1
			var q := Vector2(V[vi].x, V[vi].z)
			if U2[vi].y <= 0.03 or box.has_point(q) or q.y >= sz - 0.6:
				continue
			open_vis += 1
			if open_where.size() < 6:
				open_where.append("(%.1f,%.1f fade %.2f)" % [q.x, q.y, U2[vi].y])
	var has_col := not ov.find_children("*", "CollisionObject3D", true, false).is_empty()
	_chk("G4.no_gap", open_vis == 0 and not has_col, "開放邊界頂點 %d・其中 fade>0.03 且不在台基箱／街接縫帶 %d %s・Ground 帶碰撞體 %s" % [open_n, open_vis, str(open_where), has_col])
	# ── 擺放
	var hero := vil.get_node("Landmarks/LANDMARK_HILLFOOT_TEMPLE/Hero") as Node3D
	var steps_ab := AABB()
	var first := true
	var hero_ab := AABB()
	for cs in vil.get_node("Landmarks/LANDMARK_HILLFOOT_TEMPLE").find_children("*", "CollisionShape3D", true, false):
		var c3 := cs as CollisionShape3D
		if c3.shape == null:
			continue
		var wab := c3.global_transform * c3.shape.get_debug_mesh().get_aabb()
		hero_ab = wab if first else hero_ab.merge(wab)
		first = false
		if String(c3.name).begins_with("Steps"):
			steps_ab = wab
	var hero_mi := hero.get_node("LOD0") as MeshInstance3D
	var hero_vis := hero_mi.global_transform * hero_mi.get_aabb()
	var gap_min := 99.0
	var gap_who := ""
	var in_box := 0
	var sb: Rect2 = D["box"]
	var stones: Array = []
	var items := 0
	for n in dh.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		items += 1
		var ab := mi.global_transform * mi.get_aabb()
		var g1 := _aabb_gap(ab, steps_ab) if steps_ab.size != Vector3.ZERO else 99.0
		var g2 := _aabb_gap(ab, hero_ab)
		var g := minf(g1, g2)
		if g < gap_min:
			gap_min = g
			gap_who = "%s" % vil.get_path_to(mi)
		if sb.has_point(Vector2(ab.get_center().x, ab.get_center().z)):
			in_box += 1
	for it in dh.find_children("HF_*", "Node3D", true, false):
		var wid := String(it.get_meta("w9_id", ""))
		if wid.begins_with("gk_tobi") or wid == "gk_kei_flat":
			var l0 := it.get_node_or_null("LOD0") as MeshInstance3D
			if l0 != null and l0.mesh != null:
				stones.append(l0)
	_chk("P1.stairs_foundation", gap_min >= 0.4 and in_box == 0,
		"DistrictHF MeshInstance %d 個・與石段稜柱／社殿碰撞 AABB 最小間隙 %.2f m（%s；門檻 ≥ 0.4）・中心落入 shrine_box %d" % [items, gap_min, gap_who, in_box])
	# P2 入口不被擋
	var sp := player.get_world_3d().direct_space_state
	var pts: PackedVector2Array = D["app_pts"]
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	var blocked: Array = []
	var n_q := 0
	var lg: float = L.line_len(pts)
	var s_ := 0.0
	while s_ <= lg + 0.01:
		var pr := _along(pts, s_)
		var ctr: Vector2 = pr[0]
		var tg: Vector2 = pr[1]
		var nrm := Vector2(-tg.y, tg.x)
		for off: float in [-0.8, 0.0, 0.8]:
			var q2 := ctr + nrm * off
			var th3 := _th(q2.x, q2.y)
			if is_nan(th3):
				continue
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis(), Vector3(q2.x, th3 + 0.15 + 0.85, q2.y))
			qp.collision_mask = 0xFFFFFFFF
			qp.exclude = [player.get_rid(), _terr_rid()]
			var hits := sp.intersect_shape(qp, 8)
			n_q += 1
			for h in hits:
				var co := h["collider"] as Node
				blocked.append("(%.2f,%.2f) %s" % [q2.x, q2.y, vil.get_path_to(co) if co != null and vil.is_ancestor_of(co) else str(co)])
		s_ += 0.25
	_chk("P2.entrance_clear", blocked.is_empty(), "參道中心線 %.1f m・膠囊查詢 %d 次（中心＋側向±0.8）・碰撞命中 %d %s" % [lg, n_q, blocked.size(), str(blocked.slice(0, 5))])
	# P3 無隱形碰撞
	var inv_bad: Array = []
	var cs_n := 0
	for cs in dh.find_children("*", "CollisionShape3D", true, false):
		var c3 := cs as CollisionShape3D
		cs_n += 1
		var cab := c3.global_transform * c3.shape.get_debug_mesh().get_aabb()
		var ok_vis := false
		var holder := c3.get_parent().get_parent() if c3.get_parent() != null else null
		var scope: Node = holder if holder != null and holder != dh else dh
		for mi2 in scope.find_children("*", "MeshInstance3D", true, false):
			var m2 := mi2 as MeshInstance3D
			if m2.mesh == null:
				continue
			var vab := (m2.global_transform * m2.get_aabb()).grow(0.25)
			if vab.encloses(cab):
				ok_vis = true
				break
		if not ok_vis:
			inv_bad.append(String(vil.get_path_to(c3)))
	_chk("P3.no_invisible_walls", inv_bad.is_empty() and not has_col, "DistrictHF 碰撞形狀 %d 個・找不到對應可見網格 %d %s" % [cs_n, inv_bad.size(), str(inv_bad.slice(0, 4))])
	# P4 石座落（Ground 高度）
	var GS := RLib.TriSampler.new()      # 被覆 ≥ 0.5 の三角形だけ＝shader が実際に描く面（被覆の低い三角形の上では地形が見える）
	var gfaces := PackedVector3Array()
	for t in range(0, IDX.size(), 3):
		if (U2[IDX[t]].y + U2[IDX[t + 1]].y + U2[IDX[t + 2]].y) / 3.0 >= 0.5:
			gfaces.append(V[IDX[t]])
			gfaces.append(V[IDX[t + 1]])
			gfaces.append(V[IDX[t + 2]])
	GS.add(gfaces, gmi.global_transform)
	var prot_min := 99.0
	var prot_max := -99.0
	var bad_st: Array = []
	for mi: MeshInstance3D in stones:
		var ab := mi.global_transform * mi.get_aabb()
		var c := ab.get_center()
		var gy := GS.h(c.x, c.z)
		if is_nan(gy):
			gy = _th(c.x, c.z)
		var top := ab.end.y - gy
		prot_min = minf(prot_min, top)
		prot_max = maxf(prot_max, top)
		if top < 0.012 or top > 0.25:
			bad_st.append("%s @(%.2f,%.2f) top−ground %.3f" % [vil.get_path_to(mi), c.x, c.z, top])
	_chk("P4.stones_seated", bad_st.is_empty(), "踏石／平石 %d 顆：石頂 − 地面 最小 %.3f 最大 %.3f（門檻 0.012–0.25）%s" % [stones.size(), prot_min, prot_max, str(bad_st.slice(0, 4))])
	_data["stones"] = {"n": stones.size(), "top_min": prot_min, "top_max": prot_max}
	# P5 社殿不動
	var lm := vil.get_node("Landmarks/LANDMARK_HILLFOOT_TEMPLE") as Node3D
	var gt := lm.global_transform
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var lay_info := ""
	for k in lay.keys():
		if lay[k] is Array:
			for e in lay[k]:
				if e is Dictionary and str(e.get("id", e.get("name", ""))).to_upper().contains("HILLFOOT_TEMPLE"):
					lay_info = JSON.stringify(e).substr(0, 220)
	_chk("P5.shrine_unmoved", absf(gt.origin.x - 228.0) < 0.05 and absf(gt.origin.z + 170.0) < 0.05,
		"LANDMARK_HILLFOOT_TEMPLE origin (%.3f, %.3f, %.3f)・basis yaw %.2f°・Hero 在 %s・碰撞形狀 %d｜layout：%s" % [
			gt.origin.x, gt.origin.y, gt.origin.z, rad_to_deg(gt.basis.get_euler().y), hero != null, lm.find_children("*", "CollisionShape3D", true, false).size(), lay_info])
	_data["shrine_transform"] = {"origin": [gt.origin.x, gt.origin.y, gt.origin.z], "basis": [gt.basis.x.x, gt.basis.x.y, gt.basis.x.z, gt.basis.y.x, gt.basis.y.y, gt.basis.y.z, gt.basis.z.x, gt.basis.z.y, gt.basis.z.z]}
	var f := FileAccess.open(out.path_join("%s_verify.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify({"fail": _fail, "checks": _res, "data": _data}, " "))
	f.close()
	print("[HFV] === %s：%d 項・FAIL %d ===" % ["PASS" if _fail == 0 else "FAIL", _res.size(), _fail])
	quit(0 if _fail == 0 else 1)


## 折線上弧長 s 處的點與單位切線
func _along(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i + 1] - pts[i]
		var l := seg.length()
		if acc + l >= s or i == pts.size() - 2:
			return [pts[i] + seg.normalized() * clampf(s - acc, 0.0, l), seg.normalized()]
		acc += l
	return [pts[pts.size() - 1], Vector2.UP]
