extends SceneTree
## P13 Wave 7 TASK 5 — R6a 第一批 50 棟町家材質整合 builder。
##   godot --headless --path . --script res://tools/p13/w7/build_w7_batch1.gd [-- --dry]
## 出力：gen/albedo_batch1_p13.scn（root 直下 overlay `AlbedoBatch1P13`、script＝封存済み albedo_pilot.gd をそのまま再利用）
##        data/village_v2_p13w7_batch1.json（名簿・区・変体・用途の紀錄＝Gate が独立に検証する）
## 材質＝R6a ART_APPROVED（Pilot）で登記済みの 18 変体だけ（新しい材質ファイルなし）。割り当て規則＝Pilot と同じ assign()
## （名前雜湊で起点 → 14 m 内の同区・同組を避けて輪転）だが、Pilot 24 棟の既存割り当てを先に置いた上で続ける（Pilot 近傍との同組も避ける）。
## 区の対応（用途による合理性）：Market／MixedCommercial＝商業（A：暖白漆喰＋紅殻／飴色／素木）、ResidentialWest／ResidentialNE＝住宅（B：灰味漆喰＋風化灰／煤色）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const ALB := "res://tools/village_v2_albedo_pilot_lib.gd"
const KMAT := "res://tools/village_v2_kit_material_lib.gd"
const SCRIPT := "res://maps/village_v2/scripts_p13/albedo_batch.gd"
## LOD1／LOD2 の屋根（l_rh_*）は覆寫しない：K 版アトラスは暗部 ×0.75 で屋根瓦まで明るくし、LOD0 の Kawara 屋根・主街と食い違うため（albedo_batch.gd 冒頭）
const SKIP_PREFIXES := ["l_rh_"]
const OUT_SCENE := "res://maps/village_v2/gen/albedo_batch1_p13.scn"
const OUT_JSON := "res://data/village_v2_p13w7_batch1.json"
const NODE_NAME := "AlbedoBatch1P13"
const ART_REVISION := "P13 W7 R6a first batch r2（Pilot 登記済み 18 変体の再利用・50 棟・LOD1／2 の屋根は不覆寫）"

## 名簿の出所：docs/art_review/village_v2_p13/wave6/evidence/inventory_priority_batches.json の batch1
##（未校正・TPS で 3 張以上顕著、または神社高所から見える町家。W2 主街 39 棟・R6a Pilot 24 棟とは重ならない＝Gate が検証）
const IDS := [
	"B_P_MKT_032", "B_P_MKT_034", "B_P_MKT_035", "B_P_MKT_037", "B_P_MKT_038", "B_P_MKT_039", "B_P_MKT_040", "B_P_MKT_041", "B_P_MKT_042", "B_P_MKT_043",
	"B_P_MKT_049", "B_P_MKT_053", "B_P_MKT_055", "B_P_MKT_058", "B_P_MKT_059", "B_P_MKT_060",
	"B_P_MXC_009", "B_P_MXC_010", "B_P_MXC_013", "B_P_MXC_014", "B_P_MXC_015", "B_P_MXC_018", "B_P_MXC_019", "B_P_MXC_023",
	"B_P_RSW_007", "B_P_RSW_010", "B_P_RSW_017", "B_P_RSW_022", "B_P_RSW_023", "B_P_RSW_027", "B_P_RSW_029", "B_P_RSW_033", "B_P_RSW_034", "B_P_RSW_036",
	"B_P_RSW_045", "B_P_RSW_046", "B_P_RSW_048", "B_P_RSW_059", "B_P_RSW_071", "B_P_RSW_072", "B_P_RSW_073", "B_P_RSW_074", "B_P_RSW_075", "B_P_RSW_076", "B_P_RSW_077",
	"B_P_RNE_001", "B_P_RNE_002", "B_P_RNE_007", "B_P_RNE_010", "B_P_RNE_012",
]
const AREA_OF_DISTRICT := {
	"Market": "A_gate_main_south",
	"MixedCommercial": "A_gate_main_south",
	"ResidentialWest": "B_west_alley",
	"ResidentialNE": "B_west_alley",
}
const USE_OF_DISTRICT := {
	"Market": "商業（市集區の町家列）",
	"MixedCommercial": "商業・混在（丘脚通り）",
	"ResidentialWest": "住宅（西区）",
	"ResidentialNE": "住宅（北東区）",
}


func _init() -> void:
	_run.call_deferred()


func _find(v: Node3D, id: String) -> Node3D:
	for n in v.get_node("Districts").find_children(id, "", true, false):
		if n is Node3D and (n as Node).get_node_or_null("Kit") != null:
			return n as Node3D
	return null


func _run() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var AP = load(ALB)
	var KM = load(KMAT)
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	# 他の overlay の影響を受けない素の Kit を見る（assign は位置・名前だけを使う）
	var pilot_t: Array = AP.targets(v)
	var pilot_asg: Array = AP.assign(v, pilot_t)
	var placed := []   # [Vector2 pos, area, Vector2i combo]
	for k in pilot_asg.size():
		var b := v.get_node(NodePath(String(pilot_asg[k]["path"]))) as Node3D
		placed.append([Vector2(b.global_position.x, b.global_position.z), String(pilot_asg[k]["area"]), Vector2i(int(pilot_asg[k]["plaster"]), int(pilot_asg[k]["wood"]))])
	var pm: Array = KM.pilot_palette()
	var cm: Array = KM.pilot_cal()
	if pm.is_empty() or cm.is_empty():
		push_error("登記済み材質が読めない（KM.pilot_cal／pilot_palette が空）")
		quit(1)
		return
	var rows := []
	var paths := PackedStringArray()
	var tv := []
	var ids := IDS.duplicate()
	ids.sort()
	var palette: Dictionary = AP.PALETTE
	for id: String in ids:
		var b := _find(v, id)
		if b == null:
			push_error("建物が見つからない：" + id)
			quit(1)
			return
		var path := String(v.get_path_to(b))
		var district := path.split("/")[1]
		var area: String = AREA_OF_DISTRICT[district]
		var p := Vector2(b.global_position.x, b.global_position.z)
		var np: int = (palette[area]["V2_Plaster"] as Array).size()
		var nw: int = (palette[area]["V2_Wood"] as Array).size()
		var h := absi(path.get_file().hash())
		var combo := Vector2i(h % np, (h / 7) % nw)
		for tries in np * nw:
			var clash := false
			for q in placed:
				if String(q[1]) == area and (q[0] as Vector2).distance_to(p) < float(AP.NEIGHBOR_M) and q[2] == combo:
					clash = true
					break
			if not clash:
				break
			var flat := (combo.x * nw + combo.y + 1) % (np * nw)
			combo = Vector2i(flat / nw, flat % nw)
		placed.append([p, area, combo])
		var idx: Dictionary = pm[1][area]
		paths.append(path)
		tv.append({AP.PALETTE_SRC["V2_Plaster"]: int(idx["V2_Plaster"][combo.x]), AP.PALETTE_SRC["V2_Wood"]: int(idx["V2_Wood"][combo.y])})
		var meta := {}
		for key in ["type", "type_label", "road", "roof", "kit_asset"]:
			meta[key] = String(b.get_meta(key)) if b.has_meta(key) else ""
		rows.append({
			"id": id, "path": path, "district": district, "use": USE_OF_DISTRICT[district], "area": area,
			"type": meta["type"], "type_label": meta["type_label"], "road": meta["road"], "roof": meta["roof"], "kit_asset": meta["kit_asset"],
			"pos": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)],
			"plaster": "V2_Plaster_K_%s%d" % [area.substr(0, 1), combo.x], "wood": "V2_Wood_K_%s%d" % [area.substr(0, 1), combo.y],
		})
	print("[W7A] 50 棟の割り当て：区 ", {"A": rows.filter(func(r): return String(r["area"]).begins_with("A")).size(), "B": rows.filter(func(r): return String(r["area"]).begins_with("B")).size()})
	if dry:
		for r in rows:
			print("[W7A]   %s  %s  %s %s" % [r["id"], r["area"].substr(0, 1), r["plaster"], r["wood"]])
		quit(0)
		return
	var node := Node3D.new()
	node.name = NODE_NAME
	node.set_script(load(SCRIPT))
	node.set("targets", paths)
	node.set("src_paths", cm[0])
	node.set("cal_mats", cm[1])
	node.set("variant_mats", pm[0])
	node.set("target_variants", tv)
	node.set("skip_prefixes", PackedStringArray(SKIP_PREFIXES))
	node.set_meta("art_revision", ART_REVISION)
	node.set_meta("phase", "P13 W7 R6a first batch")
	var ps := PackedScene.new()
	ps.pack(node)
	var err := ResourceSaver.save(ps, OUT_SCENE)
	print("[W7A] saved ", OUT_SCENE, " err=", err, " targets=", paths.size())
	var man := {
		"schema": 1,
		"phase": "P13 W7 TASK 5 — R6a First Batch 50 町家",
		"approved_by": "user（P13 WAVE 7 TASK 5 批准第一批 50 棟正式材質整合・2026-10-14）",
		"source": "docs/art_review/village_v2_p13/wave6/evidence/inventory_priority_batches.json batch1",
		"rule": "R6a 登記済み 18 変体の再利用だけ（新材質なし）。AlbedoBatch1P13 は albedo_pilot.gd と同じ仕組みの scripts_p13/albedo_batch.gd（封存済みの albedo_pilot.gd は複製・無変更）。Pilot 24・W2 主街 39 と重ならない。Kawara は不校正。LOD1／LOD2 の屋根（部品名 l_rh_*）は覆寫しない（K 版アトラスが屋根瓦を明るくし、LOD0 の屋根・主街と食い違うため）。",
		"overlay": OUT_SCENE, "node": NODE_NAME, "count": rows.size(),
		"buildings": rows,
	}
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(man, "\t") + "\n")
	f.close()
	print("[W7A] saved ", OUT_JSON)
	quit(0)
