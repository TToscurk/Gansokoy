extends SceneTree
## P8 local gate / pilot builder. --build saves only the standalone overlay,
## never rewrites the approved village scene. --negative proves the water check fires.
## r3（不規則 7 田）：同一組檢查改對新結構——田數、田埂碰撞、內渠開口、水位與灌排高差、農路淨距；門檻不放寬。
## r4：秧苗／埂草是 MultiMesh，--build 必須非 headless（dummy RenderingServer 不存實例資料）：
##   Godot --path . --script res://tools/verify_village_v2_farmland.gd -- --build（檢查與 --negative 可 headless）
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const OUTPUT := "res://maps/village_v2/gen/farmland_p8.scn"   # r6：單一二進位（全區 2900+ 網格外存成 .res 時 load 2.3 s，超 terrain gate 3 s）
const FIELD_COUNT := 7
var failures := 0

func _init() -> void:
	if "--seal" in OS.get_cmdline_user_args():
		_seal()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[FARM] layout parse failed")
		quit(2)
		return
	var layout: Dictionary = parsed
	var t0 := Time.get_ticks_msec()
	var pilot := FLib.build(layout)
	print("[FARM] build %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var bad := "--negative" in OS.get_cmdline_user_args()
	if bad:
		(pilot.get_node("Plots/Plot_W1/PaddyWater") as Node3D).position.y += 0.5
	var P := FLib.plan()
	# r6：Plots＝pilot 7 田＋全區田（全區田 meta zone_block）；pilot 田數門檻不變
	var pilot_n := 0
	for plot: Node3D in pilot.get_node("Plots").get_children():
		if not plot.has_meta("zone_block"):
			pilot_n += 1
	check("plot count pilot %d + zone %d" % [pilot_n, P["fields"].size() - FIELD_COUNT], pilot_n == FIELD_COUNT and pilot.get_node("Plots").get_child_count() == P["fields"].size())
	# 非網格：渠兩側內埂接土唇的 z 互相錯開 ≥ 3 m（沒有十字路口）
	var min_stagger := INF
	for a: String in ["InnerA", "InnerB"]:
		for b: String in ["InnerC", "InnerD", "InnerE"]:
			var za: float = (P["bunds"][a]["raw"] as PackedVector2Array)[-1].y
			var zb: float = (P["bunds"][b]["raw"] as PackedVector2Array)[0].y
			min_stagger = minf(min_stagger, absf(za - zb))
	check("staggered inner bunds, no cross: %.2fm >= 3" % min_stagger, min_stagger >= 3.0)
	var areas: Array = []
	for plot: Node3D in pilot.get_node("Plots").get_children():
		areas.append(float(plot.get_meta("area_m2")))
	areas.sort()
	check("unequal field areas %.0f–%.0f m2 (max/min >= 1.5)" % [areas[0], areas[-1]], areas[-1] / areas[0] >= 1.5)
	var bunds := pilot.get_node("Bunds")
	check("bund count %d" % bunds.get_child_count(), bunds.get_child_count() == P["bunds"].size() and pilot.get_node("EarthBanks").get_child_count() == bunds.get_child_count())
	var min_shapes := 999
	for body: StaticBody3D in bunds.get_children():
		min_shapes = mini(min_shapes, body.get_child_count())
	check("every bund has collision (min %d shapes)" % min_shapes, min_shapes >= 1)
	for plot: Node3D in pilot.get_node("Plots").get_children():
		var art: Node3D = plot.get_node("FieldArt")
		check("%s mud/water/seedlings (%d hills)" % [plot.name, int(art.get_meta("rice_hills", 0))], art.has_node("WetMudBottom") and art.has_node("ShallowWater") and int(art.get_meta("rice_hills", 0)) > 1000 and not plot.get_node("PaddyWater").visible)
		var mud_mesh: Mesh = (art.get_node("WetMudBottom") as MeshInstance3D).mesh
		check("%s vertex-weighted mud" % plot.name, mud_mesh.get_surface_count() == 1 and (mud_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0)
	# 內渠：兩土唇碰撞之間的開口 > 0.3 m；渠水低於土唇頂 0.1 m 以上
	var lip_cls: Dictionary = FLib.BUND_CLASS["lip"]
	# 實測：沿渠每 2 m 取兩唇最近碰撞盒內緣距離（碰撞盒寬含 ws 變化）；門檻沿用 r2＝0.85 m，渠水可見寬需小於開口
	var opening := _lip_opening(pilot, P)
	check("lateral crosses bunds: opening min %.3fm >= 0.85, water %.2fm < opening" % [opening, FLib.CH_WATER_HALF], opening >= 0.85 - 0.002 and FLib.CH_WATER_HALF < opening)
	var ch_top := maxf(FLib.CH_WATER_S, FLib.CH_WATER_N)
	check("lateral water below lip crest by > 0.1m", ch_top < float(lip_cls["h"]) * 0.85 - 0.1)
	# 灌排高差：渠水 > 水口缺口底 > 田水 > 落水口缺口底
	var hyd := true
	for n: String in FLib.FIELD_LIFT:
		var fl: float = FLib.FIELD_LIFT[n]
		var ch := FLib.CH_WATER_S if FLib.INLET_Z[n] < FLib.CHECK_WEIR_Z else FLib.CH_WATER_N
		hyd = hyd and ch > FLib.INLET_CREST and FLib.INLET_CREST > fl and fl > FLib.OUTLET_CREST
	# 全區田：本田渠水（支渠上／下游段）> 水口缺口底 > 田水 > 落水口缺口底（同一門檻）
	for fd: Dictionary in P["fields"]:
		if fd.get("zone", false):
			hyd = hyd and float(fd["ch_water"]) > FLib.INLET_CREST and FLib.INLET_CREST > float(fd["lift"]) and float(fd["lift"]) > FLib.OUTLET_CREST
	check("gravity feed: lateral > inlet crest > field water > outlet crest (pilot + %d zone)" % (P["fields"].size() - FIELD_COUNT), hyd)
	# 逐階水路：上游水位 > 下游水位；跨路名稱依水理（下游水位 > 管頂＝伏越し，否則暗渠／涵洞）；排水口水位 > 主河
	var Z: Dictionary = P["zone"]
	var link_ok := true
	for ln: Dictionary in Z["links"]:
		link_ok = link_ok and float(ln["up_w"]) > float(ln["dn_w"])
		if ln["kind"] == "road":
			link_ok = link_ok and ((ln["hyd"] == "伏越し") == (float(ln["dn_w"]) > float(ln["pipe_top"])))
	for of: Dictionary in Z["outfalls"]:
		link_ok = link_ok and float(of["w"]) > ZLib.RIVER_WATER
	check("zone links gravity + hydraulic naming (%d links, %d outfalls)" % [Z["links"].size(), Z["outfalls"].size()], link_ok)
	# P11 R2D：竜骨車 → N0／T0 支線（水面は下流へ非増加、末端 ≥ 田区主渠水面、水面−地面 0.03–0.35）；水車 1／3 の高架 feeder 0
	var br_bad: Array = ZLib.branch_problems(Z, Z["blocks"])
	check("P11 R2D branches N0/T0 from ryukotsu: %d branches, legacy feeders %d, problems %d %s" % [(Z.get("branches", []) as Array).size(), Z["feeders"].size(), br_bad.size(), str(br_bad.slice(0, 4))],
		br_bad.is_empty() and Z["feeders"].is_empty())
	# 撤去の確認：水車 1／3 の高架樋（Feeders 以下の構件）と碰撞（Chute_*／Post_*／DropBox_*／Trough_*〔旧 feeder 名〕）が 0、支線の構件と碰撞は有る
	var zi := pilot.get_node_or_null("ZoneWorks/ZoneIrrigation")
	var feeders_left := 0 if zi == null or zi.get_node_or_null("Feeders") == null else zi.get_node("Feeders").get_child_count()
	var zw := pilot.get_node_or_null("Irrigation/ZoneWater")
	var old_coll := 0
	var br_coll := 0
	if zw:
		for c in zw.get_children():
			var nm := String(c.name)
			if nm.begins_with("Chute_") or nm.begins_with("Post_T0") or nm.begins_with("Post_N0") or nm.begins_with("DropBox_") or nm.begins_with("Trough_T0") or nm.begins_with("Trough_N0"):
				old_coll += 1
			if nm.begins_with("Br"):
				br_coll += 1
	var br_nodes := 0 if zi == null or zi.get_node_or_null("Branches") == null else zi.get_node("Branches").find_children("*", "MeshInstance3D", true, false).size()
	check("P11 R2D legacy WW1/WW3 elevated flumes removed (Feeders children %d, old collision %d); branch meshes %d, branch collision %d" % [feeders_left, old_coll, br_nodes, br_coll],
		feeders_left == 0 and old_coll == 0 and br_nodes > 0 and br_coll > 0)
	if "--negative-branch" in OS.get_cmdline_user_args():
		var neg: Dictionary = Z.duplicate(true)
		var nw: PackedFloat32Array = neg["branches"][0]["runs"][0]["w"]
		nw[1] += 0.2
		neg["branches"][0]["runs"][0]["w"] = nw     # packed array は値渡し：書き戻す
		check("NEGATIVE branch reverse slope must be detected", not ZLib.branch_problems(neg, Z["blocks"]).is_empty())
	var max_water_error := 0.0
	var spread_lo := INF
	var spread_hi := -INF
	for plot: Node3D in pilot.get_node("Plots").get_children():
		var y: float = plot.get_meta("terrace_y")
		var water: MeshInstance3D = plot.get_node("PaddyWater")
		var lift := water.position.y - y
		max_water_error = maxf(max_water_error, absf(lift - FLib.WATER_LIFT))
		spread_lo = minf(spread_lo, lift)
		spread_hi = maxf(spread_hi, lift)
		var vis: MeshInstance3D = plot.get_node("FieldArt/ShallowWater")
		var ab := vis.mesh.get_aabb()
		max_water_error = maxf(max_water_error, absf(ab.position.y + ab.size.y * 0.5 - water.position.y))
	check("water +%.3fm on frozen terrace (max err %.4f < 0.002)" % [FLib.WATER_LIFT, max_water_error], max_water_error < 0.002)
	# 農路淨距：所有田埂腳（含埋入延伸）到凍結農路邊
	var min_gap := INF
	var probe := PackedVector2Array()
	for bn: String in P["bunds"]:
		var cls: Dictionary = FLib.BUND_CLASS[P["bunds"][bn]["cls"]]
		for poly: PackedVector2Array in Geometry2D.offset_polyline(P["bunds"][bn]["pts"], float(cls["base_half"]) * 1.4, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			probe.append_array(poly)
	for road: Dictionary in layout["roads"]:
		if String(road["class"]) != "farm":
			continue
		var pts := TLib.pts(road["pts"])
		for j in pts.size() - 1:
			for p in probe:
				min_gap = minf(min_gap, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])) - float(road["half_w"]))
	check("frozen farm path clearance %.2fm" % min_gap, min_gap > 0.5)
	if bad:
		check("negative detects raised water", failures == 1)
		print("[FARM] negative_expected_fail=%d" % failures)
		pilot.free()
		quit(0 if failures == 1 else 3)
		return
	var tris := 0
	for mi: Node in pilot.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m is ArrayMesh:
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var ix: Variant = arr[Mesh.ARRAY_INDEX]
				tris += ((ix as PackedInt32Array).size() if ix != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	print("[FARM] triangles (ArrayMesh, all ranges) = %d" % tris)
	if failures == 0 and "--build" in OS.get_cmdline_user_args():
		_set_owner(pilot, pilot)
		# r6：網格／MultiMesh 全部內嵌進單一壓縮 .scn（不再外存 gen/farmland_p8/*.res）；
		# --headless 的 dummy RenderingServer 存檔不寫 MultiMesh 實例資料 → 必須非 headless 建置
		if DisplayServer.get_name() == "headless":
			check("multimesh build needs a rendering display (run --build without --headless)", false)
		var ps := PackedScene.new()
		check("pack", ps.pack(pilot) == OK)
		if failures == 0:
			check("save overlay", ResourceSaver.save(ps, OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
			print("[FARM] overlay %s %.1f MB" % [OUTPUT, FileAccess.get_file_as_bytes(OUTPUT).size() / 1048576.0])
	pilot.free()
	print("[FARM] result: %d failed; pilot=%d + zone=%d fields; water err=%.4fm spread=%.3f–%.3f, path clearance=%.3fm" % [failures, FIELD_COUNT, P["fields"].size() - FIELD_COUNT, max_water_error, spread_lo, spread_hi, min_gap])
	quit(0 if failures == 0 else 1)

## 兩土唇碰撞盒在水平面上的最小淨距（沿內渠 z 每 2 m 取樣，只取水口缺口以外）。
## r4：內渠有偏折，改量「垂直於土唇段」的距離（盒座標 x 軸）＝真實淨開口，比沿世界 x 量更嚴。
func _lip_opening(pilot: Node, P: Dictionary) -> float:
	var best := INF
	var z := 8.0
	while z < FLib.N_JOIN - 2.0:
		var cx := FLib.x_at(P["channel"], z)
		var inner := {}
		for side: String in ["LipW", "LipE"]:
			var edge := INF
			for shape: CollisionShape3D in pilot.get_node("Bunds/Bund_%s" % side).get_children():
				var box := shape.shape as BoxShape3D
				var xf := shape.transform
				var local := xf.affine_inverse() * Vector3(cx, xf.origin.y, z)
				if absf(local.z) > box.size.z * 0.5:
					continue
				edge = minf(edge, absf(local.x) - box.size.x * 0.5)
			inner[side] = edge
		if inner["LipW"] < INF and inner["LipE"] < INF:
			best = minf(best, inner["LipW"] + inner["LipE"])
		z += 2.0
	return best

## --seal（P8 ART_APPROVED 2026-10-01 封存）：凍結來源／overlay／ART_REVIEW 圖片／證據檔的 sha256 必須與 SEAL 一致；
## 另在記憶體裡竄改一筆期望雜湊，確認比對會 FAIL（永久反向案例）。任何封存檔改變 → exit 1；只有真正 regression 才重開 P8。
const SEAL := "res://data/village_v2_p8_seal.json"

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var docs := (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p8_farmland/").simplify_path() + "/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = ("res://" + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad

func _seal() -> void:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	var bad := _seal_mismatch(seal)
	check("P8 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var neg := seal.duplicate(true)
	var k0: String = neg["frozen"].keys()[0]
	neg["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[FARM] 結果：%d 項失敗（seal）" % failures)
	quit(0 if failures == 0 else 1)

func check(name: String, passed: bool) -> void:
	print("[FARM] %s %s" % ["PASS" if passed else "FAIL", name])
	if not passed:
		failures += 1

func _set_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owner(child, scene_root)
