extends "res://tools/p13/w6/w6_base.gd"
## 丘腳林地（TASK E FINAL，使用者 2026-10-18：丘腳社寺取消→自然林）：撤去＋林地の検証・TPS 撮影・効能（唯讀・場景ファイルは書かない）。
## **必須有顯示（不得 --headless）**：MultiMesh（草株）実例の行列は headless では全 0。
##   godot --path godot --resolution 1600x900 --script res://tools/p13/w9/e2/verify_hf_precinct.gd -- <outdir/> HFW
## 正式 main.tscn → village_v2、実際の玩家・TPS 相機・10:00・Forward+。E2 版（社寺境內の検査）は git 履歴 b9000b7。
## 検査（門檻固定）：
##   W1 社寺不在     LANDMARK_HILLFOOT_TEMPLE に子 0・metadata/cancelled あり；runtime の全節点に hillfoot_temple.scn 由来 0；village_v2.tscn の依存に無い；
##                   原社寺 footprint（P0 18×12 m＋1 m）に Landmarks 配下の CollisionObject 0（灰盒 Block の再出現なし）。
##   W2 隱形碰撞     原社寺＋境內範囲（216–240 × −182…−152）を 0.5 m 格子・球 r0.3・地面＋0.5／1.2／1.9 m で照会：当たった碰撞体はすべて
##                   『可視の持ち主』を持つ（DistrictHF の item は自分の可視網格、EnvironmentP9/Collision の <名>_c は同名の可視節点）。持ち主が不可視／不明＝FAIL。
##   W3 垣の抑制     E082 四目垣斷片 7 件 visible=false・碰撞 5 disabled（林の中に旧社寺の垣を戻さない）。
##   W4 草株復帰     overlay は MultiMesh を一切差し替えていない（trimmed 0）・原境內の MeadowP9／GroundcoverP9 実例は全部可視（行列式 > 1e-7）・全場景零矩陣 0。
##   W5 可逆         enabled=false → DistrictHF 不可視＋碰撞全停用・E082 可見＋碰撞啟用；true で戻る；PRE_SAVE で還原／POST_SAVE で再抑制。
##   W6 道路不擋     丘腳街中心線 x 204–250 を 0.25 m 毎・膠囊 r0.35（離地 0.15–1.85）・中心と ±2.0 m：DistrictHF の碰撞に当たる 0；
##                   item の樹幹から路肩までの距離 ≥ HF_design.road_clear（大樹 4.2／若木 3.0／下層 1.4）。
##   W7 自然さ       樹（tree＋young）の最近傍距離の変動係數 ≥ 0.25（等間隔植えでない）・樹高（可視 AABB 頂）幅 ≥ 6 m・
##                   資産は植物と林床景石（gk_kei_*）のみ（踏石・燈籠・鳥居・垣 0）。
## 撮影（TPS・実際の SpringArm）：tps_1_street_approach／tps_2_former_site／tps_3_elevated_overview（丘の西肩 (214,−197)・相機 y≈11.8＝跡地より約 10 m 上・pitch −0.55；林の中の TPS は樹冠に半分遮られる＝probe3 で 15 候補を比較した最良）
##   probe3（第 3 引数）：俯瞰候補を撮るだけ。
## 診斷（自由相機・非美術證據）：diag_oblique_site／diag_top_site。
## 効能：同じ 3 視点で、現況（林）／林 off／林 off＋社寺 Hero を記憶内に仮置き（＝撤去前相当・保存しない）の primitives・draw calls・frame ms。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const DESIGN := "res://data/district/HF_design.json"
const MANIFEST := "res://data/district/HF.json"
const NODE_NAME := "HillfootPrecinctE2"
const DISTRICT_NODE := "DistrictHF"
const ANCHOR := "Landmarks/LANDMARK_HILLFOOT_TEMPLE"
const SHRINE_SCN := "res://assets/village_v2/hillfoot_temple/hillfoot_temple.scn"
const STREET := [Vector2(204.0, -148.2), Vector2(228.0, -149.1), Vector2(250.0, -150.0)]
const STREET_HW := 3.0
## 原境內（E2 の草株抑制多邊形の外接矩形）
const OLD_SITE := Rect2(218.8, -178.6, 18.6, 26.4)

var _res: Array = []
var _fail := 0
var _data := {}


func _chk(id: String, ok: bool, msg: String) -> void:
	_res.append({"id": id, "ok": ok, "msg": msg})
	if not ok:
		_fail += 1
	print("[HFW] %s %s — %s" % ["PASS" if ok else "FAIL", id, msg])


func _terr_rid() -> RID:
	return (vil.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()


func _th(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var tr := _terr_rid()
	var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = []
	for i in 16:
		rq.exclude = ex
		var r := sp.intersect_ray(rq)
		if r.is_empty():
			return NAN
		if (r["rid"] as RID) == tr:
			return float((r["position"] as Vector3).y)
		ex.append(r["rid"])
	return NAN


func _street_d(p: Vector2) -> float:
	var best := INF
	for i in STREET.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, STREET[i], STREET[i + 1]).distance_to(p))
	return best - STREET_HW


## 碰撞体の『見える持ち主』：DistrictHF item → その item の可視網格；EnvironmentP9/Collision の <名>_c → 同名節点；それ以外 → 碰撞体の祖先で可視の MeshInstance を持つもの
func _owner_visible(co: Node, shape_idx: int) -> Array:
	var p := String(vil.get_path_to(co))
	var dh := vil.get_node(DISTRICT_NODE)
	if dh.is_ancestor_of(co):
		# DistrictHF/Collision の形状名＝<vid>_c／<vid>_c<n> → 同名 item の可視網格
		var so: Variant = (co as CollisionObject3D).shape_owner_get_owner((co as CollisionObject3D).shape_find_owner(shape_idx))
		var snm := String((so as Node).name) if so is Node else ""
		var vid := snm.substr(0, snm.rfind("_c")) if snm.rfind("_c") > 0 else snm
		var it := dh.find_child(vid, true, false)
		var vis := false
		if it != null and it != co:
			for mi in it.find_children("*", "MeshInstance3D", true, false):
				vis = vis or (mi as MeshInstance3D).is_visible_in_tree()
		return ["DistrictHF", vis, p + ":" + snm]
	if p.begins_with("Props/EnvironmentP9/Collision"):
		var owner_id: Variant = null
		if co is CollisionObject3D:
			owner_id = (co as CollisionObject3D).shape_owner_get_owner((co as CollisionObject3D).shape_find_owner(shape_idx))
		var nm := String((owner_id as Node).name) if owner_id is Node else ""
		var base := nm.trim_suffix("_c")
		var env := vil.get_node("Props/EnvironmentP9")
		var hits := env.find_children(base, "Node3D", true, false)
		for h in hits:
			if not (h as Node).get_path().get_concatenated_names().contains("Collision") and (h as Node3D).is_visible_in_tree():
				return ["EnvironmentP9", true, p + ":" + nm]
		return ["EnvironmentP9", false, p + ":" + nm]
	if p.begins_with(ANCHOR) or p.begins_with(NODE_NAME):
		return ["SHRINE", false, p]
	var n := co
	while n != null and n != vil:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).is_visible_in_tree():
				return ["other", true, p]
		n = n.get_parent()
	return ["other", false, p]


func _e82_state() -> Dictionary:
	var e82 := vil.get_node("Props/EnvironmentP9/edge/E082_fence_frag") as Node3D
	var col := vil.get_node("Props/EnvironmentP9/Collision")
	var s := {"n": 0, "vis": 0, "cols": 0, "col_on": 0}
	for ch in e82.get_children():
		if ch is Node3D:
			s["n"] += 1
			if (ch as Node3D).visible:
				s["vis"] += 1
			var sh := col.get_node_or_null(String(ch.name) + "_c") as CollisionShape3D
			if sh != null:
				s["cols"] += 1
				if not sh.disabled:
					s["col_on"] += 1
	return s


func _dh_state() -> Dictionary:
	var dh := vil.get_node(DISTRICT_NODE) as Node3D
	var cs := dh.find_children("*", "CollisionShape3D", true, false)
	var dis := 0
	for c in cs:
		if (c as CollisionShape3D).disabled:
			dis += 1
	return {"visible": dh.visible, "cols": cs.size(), "disabled": dis}


func _mm_site() -> Dictionary:
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
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				total += 1
				var det := absf(t.basis.determinant())
				if det < 1e-12:
					zero_all += 1
				var w := m.global_transform * t.origin
				if OLD_SITE.has_point(Vector2(w.x, w.z)):
					inside += 1
					if det > 1e-7:
						vis += 1
	return {"inside": inside, "visible": vis, "zero_all": zero_all, "total": total}


func _perf(n := 90) -> Dictionary:
	await _frames(30)
	var t0 := Time.get_ticks_usec()
	var prim := 0
	var dc := 0
	for i in n:
		await RenderingServer.frame_post_draw
		prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	return {"frame_ms": (Time.get_ticks_usec() - t0) / 1000.0 / n, "primitives": prim / n, "draw_calls": dc / n}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1] if args.size() > 1 else "HFW"
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		printerr("[HFW] 不得 --headless（MultiMesh 矩陣讀不到）")
		quit(2)
		return
	await _boot()
	if args.size() > 2 and args[2] == "probe3":
		# 俯瞰視点の候補を撮るだけ（検査なし）：x,z,fx,fz,pitch
		for c in [[214.0, -197.0, 0.46, 0.89, -0.55], [216.0, -200.5, 0.4, 0.9, -0.6], [211.0, -194.0, 0.6, 0.8, -0.5], [218.5, -202.5, 0.3, 0.95, -0.6]]:
			await _tpw(Vector2(c[0], c[1]), Vector2(c[2], c[3]).normalized())
			adapter.set("_target_pitch", c[4])
			adapter.set("_current_pitch", c[4])
			await _frames(30)
			await _shot("probe3_%d_%d" % [int(c[0]), int(-c[1])])
			print("[HFW] probe3 %s player %s cam %s" % [str(c), str(player.global_position), str(cam_record())])
		quit(0)
		return
	var DS: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	var MF: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var ov := vil.get_node_or_null(NODE_NAME) as Node3D
	var dh := vil.get_node_or_null(DISTRICT_NODE) as Node3D
	if ov == null or dh == null:
		_chk("W0.mount", false, "overlay=%s district=%s" % [ov != null, dh != null])
		quit(1)
		return
	# ── W1 社寺不在
	var lm := vil.get_node_or_null(ANCHOR) as Node3D
	var from_scn := 0
	for n in vil.find_children("*", "", true, false):
		if String(n.scene_file_path).contains("hillfoot_temple"):
			from_scn += 1
	var deps := ResourceLoader.get_dependencies("res://maps/village_v2/village_v2.tscn")
	var dep_hit := 0
	for d in deps:
		if String(d).contains("hillfoot_temple"):
			dep_hit += 1
	var lm_cols := 0
	var box := Rect2(228.0 - 10.0, -170.0 - 7.0, 20.0, 14.0)
	for co in vil.get_node("Landmarks").find_children("*", "CollisionObject3D", true, false):
		var gp := (co as Node3D).global_position
		if box.has_point(Vector2(gp.x, gp.z)):
			lm_cols += 1
	_chk("W1.shrine_absent", lm != null and lm.get_child_count() == 0 and lm.has_meta("cancelled") and from_scn == 0 and dep_hit == 0 and lm_cols == 0,
		"anchor 子 %d・cancelled meta %s・hillfoot_temple.scn 由来の節点 %d・village_v2.tscn 依存に %d・原 footprint 内の Landmarks 碰撞体 %d（灰盒 Block 再出現なし）" % [
			lm.get_child_count() if lm else -1, lm.has_meta("cancelled") if lm else false, from_scn, dep_hit, lm_cols])
	# ── W2 隱形碰撞
	var sp := player.get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.exclude = [_terr_rid(), player.get_rid()]
	var cats := {}
	var bad: Array = []
	var nq := 0
	var x := 216.0
	while x <= 240.0:
		var z := -182.0
		while z <= -152.0:
			var g := _th(x, z)
			if not is_nan(g):
				for hh in [0.5, 1.2, 1.9]:
					q.transform = Transform3D(Basis(), Vector3(x, g + float(hh), z))
					nq += 1
					for r in sp.intersect_shape(q, 8):
						var co := r["collider"] as Node
						if co == null:
							continue
						var info := _owner_visible(co, int(r["shape"]))
						var key := "%s|%s" % [info[0], info[2]]
						cats[key] = bool(info[1])
						if not bool(info[1]) and not bad.has(info[2]):
							bad.append(info[2])
			z += 0.5
		x += 0.5
	var by_cat := {}
	for k: String in cats:
		var c := k.split("|")[0]
		by_cat[c] = int(by_cat.get(c, 0)) + 1
	_data["w2_colliders"] = cats
	_chk("W2.no_hidden_collision", bad.is_empty(), "球照会 %d 回：当たった碰撞体 %d 種 %s・可視の持ち主が無い %d %s" % [nq, cats.size(), str(by_cat), bad.size(), str(bad.slice(0, 6))])
	# ── W3 垣の抑制
	var e_on := _e82_state()
	_chk("W3.fence_suppressed", e_on["n"] == 7 and e_on["vis"] == 0 and e_on["cols"] == 5 and e_on["col_on"] == 0,
		"E082 子 %d・可見 %d・碰撞 %d（啟用 %d）" % [e_on["n"], e_on["vis"], e_on["cols"], e_on["col_on"]])
	# ── W4 草株
	var mm_on := _mm_site()
	_chk("W4.grass_restored", int(ov.get("trimmed_mmis")) == 0 and int(ov.get("trimmed_instances")) == 0 and mm_on["inside"] > 0 and mm_on["visible"] == mm_on["inside"] and mm_on["zero_all"] == 0,
		"overlay trimmed %s／%s・原境內の草株 %d 中可視 %d・全場景零矩陣 %d／%d" % [ov.get("trimmed_mmis"), ov.get("trimmed_instances"), mm_on["inside"], mm_on["visible"], mm_on["zero_all"], mm_on["total"]])
	_data["mm"] = mm_on
	# ── W5 可逆
	var d_on := _dh_state()
	ov.set("enabled", false)
	await physics_frame
	var e_off := _e82_state()
	var d_off := _dh_state()
	ov.set("enabled", true)
	await physics_frame
	var e_back := _e82_state()
	var d_back := _dh_state()
	ov.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var e_pre := _e82_state()
	ov.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	var e_post := _e82_state()
	_chk("W5.reversible", d_on["visible"] and d_on["disabled"] == 0 and not d_off["visible"] and d_off["disabled"] == d_off["cols"] and e_off["vis"] == 7 and e_off["col_on"] == 5
		and e_back == e_on and d_back == d_on and e_pre["vis"] == 7 and e_post == e_on,
		"on %s／off：林 visible %s 碰撞停用 %d/%d・E082 可見 %d 碰撞啟用 %d｜back 一致 %s｜PRE_SAVE E082 可見 %d・POST_SAVE 一致 %s" % [
			str(d_on), d_off["visible"], d_off["disabled"], d_off["cols"], e_off["vis"], e_off["col_on"], e_back == e_on and d_back == d_on, e_pre["vis"], e_post == e_on])
	# ── W6 道路不擋
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	var qc := PhysicsShapeQueryParameters3D.new()
	qc.shape = cap
	var dh_rids: Array[RID] = []
	for co in dh.find_children("*", "CollisionObject3D", true, false):
		dh_rids.append((co as CollisionObject3D).get_rid())
	var road_hits: Array = []
	var nc := 0
	for i in STREET.size() - 1:
		var a: Vector2 = STREET[i]
		var b: Vector2 = STREET[i + 1]
		var L := a.distance_to(b)
		var tdir := (b - a) / L
		var nrm := Vector2(-tdir.y, tdir.x)
		var s := 0.0
		while s <= L:
			for lat in [-2.0, 0.0, 2.0]:
				var p: Vector2 = a + tdir * s + nrm * float(lat)
				var g := _th(p.x, p.y)
				if is_nan(g):
					continue
				qc.transform = Transform3D(Basis(), Vector3(p.x, g + 0.15 + 0.85, p.y))
				nc += 1
				for r in sp.intersect_shape(qc, 8):
					if dh_rids.has(r["rid"]):
						road_hits.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
			s += 0.25
	var clr: Dictionary = DS["road_clear"]
	var clr_bad: Array = []
	var min_d := {"tree": INF, "young": INF, "under": INF}
	for it: Dictionary in MF["items"]:
		var a := String(it["asset"])
		var t := "tree" if a in ["keyaki_a", "shii_a", "konara_a", "konara_b", "akamatsu_a", "kuromatsu_a", "enoki_a"] else ("young" if a.begins_with("young") else "under")
		var dd := _street_d(Vector2(float(it["pos"][0]), float(it["pos"][2])))
		min_d[t] = minf(float(min_d[t]), dd)
		if dd < float(clr[t]) - 0.01:
			clr_bad.append("%s(%s) %.2f" % [it["vid"], a, dd])
	_chk("W6.road_clear", road_hits.is_empty() and clr_bad.is_empty(),
		"丘腳街 膠囊 %d 回・林の碰撞に当たる %d %s｜樹幹→路肩 最小：大樹 %.2f／若木 %.2f／下層 %.2f m（門檻 %s）・不足 %s" % [
			nc, road_hits.size(), str(road_hits.slice(0, 4)), min_d["tree"], min_d["young"], min_d["under"], str(clr), str(clr_bad)])
	# ── W7 自然さ
	var trees: Array = []
	var tops: Array = []
	var bad_assets: Array = []
	for it: Dictionary in MF["items"]:
		var a := String(it["asset"])
		if not (a.begins_with("gk_kei") or a in ["fern_a", "sasa_a", "shrub_a", "tsutsuji_a", "keyaki_a", "shii_a", "konara_a", "konara_b", "akamatsu_a", "kuromatsu_a", "enoki_a", "young_sugi", "young_broad_a", "young_broad_b"]):
			bad_assets.append(a)
		if a.begins_with("young") or a in ["keyaki_a", "shii_a", "konara_a", "konara_b", "akamatsu_a", "kuromatsu_a", "enoki_a"]:
			trees.append(Vector2(float(it["pos"][0]), float(it["pos"][2])))
			tops.append(float(it["aabb_v"][4]) - float(it["pos"][1]))
	var nn: Array = []
	for i in trees.size():
		var best := INF
		for j in trees.size():
			if i != j:
				best = minf(best, (trees[i] as Vector2).distance_to(trees[j]))
		nn.append(best)
	var mean := 0.0
	for v in nn:
		mean += v
	mean /= maxf(1.0, nn.size())
	var var_ := 0.0
	for v in nn:
		var_ += (v - mean) * (v - mean)
	var cv := sqrt(var_ / maxf(1.0, nn.size())) / maxf(mean, 1e-6)
	var h_rng: float = (float(tops.max()) - float(tops.min())) if not tops.is_empty() else 0.0
	_chk("W7.natural", cv >= 0.25 and h_rng >= 6.0 and bad_assets.is_empty() and trees.size() >= 12,
		"樹 %d 本（大樹＋若木）・最近傍 平均 %.2f m CV %.2f（≥ 0.25）・樹高 %.1f–%.1f m（幅 %.1f ≥ 6）・社寺系／踏石の資産 %s" % [
			trees.size(), mean, cv, tops.min(), tops.max(), h_rng, str(bad_assets)])
	_data["trees_nn"] = {"mean": mean, "cv": cv, "heights": tops}
	# ── 撮影＋効能
	var views := [
		["tps_1_street_approach", Vector2(223.5, -146.0), Vector2(0.15, -1.0)],
		["tps_2_former_site", Vector2(226.9, -162.6), Vector2(0.15, -1.0)],
		["tps_3_elevated_overview", Vector2(214.0, -197.0), Vector2(0.46, 0.89)],
	]
	var perf := {}
	for v in views:
		await _tpw(v[1], (v[2] as Vector2).normalized())
		if String(v[0]).begins_with("tps_3"):
			# 俯瞰：実際の CameraAdapter の pitch を下げる（玩家が右スティック／マウスで下を向いた状態と同じ・相機コードは触らない）
			adapter.set("_target_pitch", -0.55)
			adapter.set("_current_pitch", -0.55)
			await _frames(30)
		_data["cam_" + String(v[0])] = cam_record()
		_data["player_" + String(v[0])] = [player.global_position.x, player.global_position.y, player.global_position.z]
		await _shot(String(v[0]))
		var pa := await _perf()
		ov.set("enabled", false)
		var pb := await _perf()
		var hero := (load(SHRINE_SCN) as PackedScene).instantiate() as Node3D
		hero.name = "PerfBeforeShrine"
		vil.get_node(ANCHOR).add_child(hero)
		var pc := await _perf()
		hero.get_parent().remove_child(hero)
		hero.free()
		ov.set("enabled", true)
		await physics_frame
		perf[v[0]] = {"woodland": pa, "nothing": pb, "shrine_in_memory": pc}
		print("[HFW] perf %s：林 %s｜林 off %s｜林 off＋社寺（記憶內）%s" % [v[0], str(pa), str(pb), str(pc)])
	_data["perf"] = perf
	# 診斷（非 TPS・非美術證據）：自由相機の斜め俯瞰。樹冠越しに跡地全体の分布を見るため（TPS は林の中で樹冠に遮られる）
	_free_begin()
	await _free("diag_oblique_site", Vector3(214.0, 34.0, -128.0), Vector3(228.0, 1.5, -170.0), 50.0)
	await _free("diag_top_site", Vector3(228.0, 70.0, -169.9), Vector3(228.0, 1.0, -170.0), 40.0)
	_free_end()
	var e_end := _e82_state()
	var lm_end := vil.get_node(ANCHOR).get_child_count()
	_chk("W8.state_restored", e_end == e_on and lm_end == 0 and bool(ov.get("enabled")), "撮影・効能のあと E082 %s・anchor 子 %d・enabled %s" % [str(e_end), lm_end, ov.get("enabled")])
	var f := FileAccess.open(out.path_join("%s_verify.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify({"fail": _fail, "checks": _res, "data": _data}, " "))
	f.close()
	print("[HFW] === %s：%d 項・FAIL %d ===" % ["PASS" if _fail == 0 else "FAIL", _res.size(), _fail])
	quit(0 if _fail == 0 else 1)
