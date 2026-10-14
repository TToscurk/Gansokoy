extends SceneTree
## P13 Wave 7 gate：EarthBankToneP13（TASK 3）＋ FarmJunctionFixP13（TASK 2）＋ AlbedoBatch1P13（TASK 5・50 棟）。
##   godot --headless --path . --script res://tools/p13/w7/verify_w7_cleanup.gd [-- --negatives]
## TASK 1（RoadEdgeBlend の edge_w）は tools/p13/w6/verify_w6_cleanup.gd が独立に持つ（W7 で期待値を更新済み）。
## 区塊：
##   A mount     ：3 overlay が root 末尾（RoadEdgeBlendP13 の後）に 1 つずつ・順序・enabled・子ノード 0（雙份 geometry なし）。
##   B earthbank ：220 件が複製材質 1 個を共有・ground_k 0.21・他の shader 引数は元と同一・元の材質は 0.304 のまま 220 件専用・開閉で戻る。
##   C junction  ：地形 mesh は RoadBase の mesh と頂点位置／法線／UV／index 同一、COLOR.r／UV2.y が記録の 5 頂点でだけ変わる（独立に位置で引き当て）・開閉・位置不一致なら拒否。
##   D batch1    ：名簿 50＝W2 主街 39・Pilot 24 と重ならない・全て machiya_kit・区と用途の対応・登記変体だけ・LOD0／1／2 の全面が期待どおり・Kawara 不校正・LOD1／2 の屋根 l_rh_* は不覆寫・
##                 範囲外の建物は覆寫 0・14 m 内同区同組なし（Pilot ∪ batch）・変体の輝度／飽和帯・LOD0 と LOD1/2 の明度差・開閉。
##   E deps      ：3 overlay は碰撞／導航／MultiMesh を持たず、開閉で場景内の MeshInstance3D・碰撞物・導航領域の数が不変。
##   N negatives ：in-memory の壊れたデータで各検査が必ず FAIL する。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const MANIFEST := "res://data/village_v2_p13w7_batch1.json"
const MAINST := "res://data/village_v2_p13_mainstreet.json"
const REG := "res://maps/village_v2/kit_cal_p10/kit_material_variants.json"
const BANK_PATH := "Districts/FarmlandEast/FarmlandP8/EarthBanks"
const BANK_N := 220
const BANK_K_NEW := 0.21
const BANK_K_ORIG := 0.304
## 独立抄写（builder と別に持つ）：x, z, 新 r, 新 street
const JUNCTION := [[366.0, -34.0, 0.35, 0.55], [368.0, -34.0, 0.0, 1.0], [370.0, -34.0, 0.0, 1.0], [372.0, -34.0, 0.0, 1.0], [374.0, -34.0, 0.35, 0.55]]
const SRC_PLASTER := "res://assets/village_v2/_matlib/V2_Plaster.tres"
const SRC_WOOD := "res://assets/village_v2/_matlib/V2_Wood.tres"
const SRC_STONE := "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres"
const SRC_ATLAS := "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
const SRC_KAWARA := "res://assets/village_v2/_matlib/V2_Kawara.tres"
const AREA_OF := {"Market": "A_gate_main_south", "MixedCommercial": "A_gate_main_south", "ResidentialWest": "B_west_alley", "ResidentialNE": "B_west_alley"}
const NEIGHBOR_M := 14.0
const ROOF_HIP_PREFIX := "l_rh_"   # LOD1／LOD2 の屋根（アトラス）。K 版は屋根瓦まで明るくするので batch では覆寫しない
const SAT_MAX := 0.22
const LUMA_PLASTER := Vector2(0.66, 0.76)
const LUMA_WOOD := Vector2(0.66, 0.82)
const LOD_DELTA_PLASTER := 0.08
const LOD_DELTA_WOOD := 0.10

var v: Node3D
var fails := 0
var passes := 0
var quiet := false
var reg: Dictionary
var reg_by_id := {}
var reg_by_file := {}
var man: Dictionary
var w2_ids := {}
var pilot_set := {}      # path → true
var batch_set := {}      # path → true
var all_b: Array = []     # [Node3D …]（Kit 持ち）
var bad_detail: Array = []   # _check_building が見つけた不一致の説明（先頭だけ）


func _init() -> void:
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		if not quiet:
			print("[W7G] PASS ", msg)
	else:
		fails += 1
		if not quiet:
			print("[W7G] FAIL ", msg)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _sat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


func _load_data() -> void:
	reg = JSON.parse_string(FileAccess.get_file_as_string(REG))
	for e: Dictionary in reg["variants"]:
		reg_by_id[String(e["id"])] = e
		reg_by_file[String(e["file"])] = e
	man = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var ms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAINST))
	for b: Dictionary in ms["buildings"]:
		w2_ids[String(b["id"])] = true
	for p in reg["pilot_buildings"]:
		pilot_set[String(p)] = true
	for b: Dictionary in man["buildings"]:
		batch_set[String(b["path"])] = true


func _collect_buildings() -> void:
	all_b.clear()
	for n in v.get_node("Districts").find_children("B_*", "", true, false):
		if n is Node3D and (n as Node).get_node_or_null("Kit") != null:
			all_b.append(n)


func _count(cls: String) -> int:
	return v.find_children("*", cls, true, false).size()


func _run() -> void:
	var neg := OS.get_cmdline_user_args().has("--negatives")
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	# P13 W8：LodCalBatch1P13 は W7 の K 版の上から LOD1／LOD2 を差し替える。W7 gate は W7 の状態（K 版・屋根は覆寫なし）だけを見るので W8 を閉じてから検査する
	# （W8 の LOD 材質は tools/p13/w8/verify_w8_lod.gd が独立に検査し、開閉で W7 の状態へ完全還原されることもそちらで確かめる）
	var w8cal := v.get_node_or_null("LodCalBatch1P13")
	if w8cal != null:
		w8cal.set("enabled", false)
	_load_data()
	_collect_buildings()
	_a_mount()
	_b_earthbank()
	_c_junction()
	_d_batch()
	await _e_deps()
	if neg:
		await _negatives()
	print("[W7G] ", "PASS %d" % passes, "  FAIL %d" % fails)
	print("[W7G] 結果：%d 項失敗" % fails)
	quit(1 if fails > 0 else 0)


# ─────────────────────────── A mount ───────────────────────────
func _a_mount() -> void:
	var names := ["RoadEdgeBlendP13", "EarthBankToneP13", "FarmJunctionFixP13", "AlbedoBatch1P13"]
	var idx := []
	for nm in names:
		var found := v.find_children(nm, "", false, false)
		ok(found.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [nm, found.size()])
		idx.append(found[0].get_index() if found.size() == 1 else -1)
	ok(idx[0] >= 0 and idx[1] == idx[0] + 1 and idx[2] == idx[1] + 1 and idx[3] == idx[2] + 1, "順序：RoadEdgeBlendP13 → EarthBankToneP13 → FarmJunctionFixP13 → AlbedoBatch1P13（index %s）" % str(idx))
	for nm in names.slice(1):
		var n := v.get_node_or_null(nm)
		if n == null:
			continue
		ok(bool(n.get("enabled")), "%s enabled" % nm)
		ok(n.get_child_count() == 0, "%s は子ノード 0（雙份 geometry なし）" % nm)
	var eb := v.get_node_or_null("EarthBankToneP13")
	var jf := v.get_node_or_null("FarmJunctionFixP13")
	var ab := v.get_node_or_null("AlbedoBatch1P13")
	ok(eb != null and int(eb.get("applied")) == BANK_N, "EarthBankToneP13.applied＝%d（期待 %d）" % [int(eb.get("applied")) if eb else -1, BANK_N])
	ok(jf != null and int(jf.get("applied")) == JUNCTION.size(), "FarmJunctionFixP13.applied＝%d（期待 %d）" % [int(jf.get("applied")) if jf else -1, JUNCTION.size()])
	ok(ab != null and int(ab.get("applied_surfaces")) > 0, "AlbedoBatch1P13.applied_surfaces＝%d" % [int(ab.get("applied_surfaces")) if ab else -1])


# ─────────────────────────── B earthbank ───────────────────────────
func _b_earthbank() -> void:
	var bank := v.get_node_or_null(BANK_PATH)
	ok(bank != null and bank.get_child_count() == BANK_N, "EarthBanks 子 %d 件（期待 %d）" % [bank.get_child_count() if bank else -1, BANK_N])
	if bank == null:
		return
	var eb := v.get_node("EarthBankToneP13")
	var new_mats := {}
	var bad_k := 0
	var non_mi := 0
	for c in bank.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.material_override == null:
			non_mi += 1
			continue
		new_mats[mi.material_override] = true
		if absf(float((mi.material_override as ShaderMaterial).get_shader_parameter("ground_k")) - BANK_K_NEW) > 1e-4:
			bad_k += 1
	ok(non_mi == 0 and new_mats.size() == 1 and bad_k == 0, "220 件が複製材質 1 個を共有・ground_k＝%.3f（MeshInstance 以外 %d・材質種 %d・k 違い %d）" % [BANK_K_NEW, non_mi, new_mats.size(), bad_k])
	var dup: ShaderMaterial = new_mats.keys()[0] if new_mats.size() >= 1 else null
	# 全 MeshInstance3D を走査：複製材質を使うのは EarthBanks の 220 件だけ
	var users := 0
	var outside := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == dup and dup != null:
			users += 1
			if not bank.is_ancestor_of(mi):
				outside += 1
	ok(users == BANK_N and outside == 0, "複製材質の使用者＝%d（期待 %d）・EarthBanks 外 %d" % [users, BANK_N, outside])
	# 開 → 元の材質へ
	eb.set("enabled", false)
	var origs := {}
	var back_k_bad := 0
	for c in bank.get_children():
		var m := (c as MeshInstance3D).material_override as ShaderMaterial
		origs[m] = true
		if absf(float(m.get_shader_parameter("ground_k")) - BANK_K_ORIG) > 1e-4:
			back_k_bad += 1
	ok(origs.size() == 1 and back_k_bad == 0 and not origs.has(dup), "enabled=false → 元の共用材質 1 個・ground_k＝%.3f（元の材質は書き換わっていない）" % BANK_K_ORIG)
	var orig: ShaderMaterial = origs.keys()[0] if origs.size() >= 1 else null
	# 元の材質を使う節点も全村走査（共用範囲）
	var orig_users := 0
	var orig_outside := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == orig and orig != null:
			orig_users += 1
			if not bank.is_ancestor_of(mi):
				orig_outside += 1
	ok(orig_users == BANK_N and orig_outside == 0, "元の共用材質の使用者＝%d（EarthBanks 外 %d）：共用による他区域への波及なし" % [orig_users, orig_outside])
	# 他の shader 引数は元と同一
	var diff := []
	if orig != null and dup != null and orig.shader == dup.shader:
		for u in orig.shader.get_shader_uniform_list():
			var nm := String(u["name"])
			if nm == "ground_k":
				continue
			if orig.get_shader_parameter(nm) != dup.get_shader_parameter(nm):
				diff.append(nm)
	ok(orig != null and dup != null and orig.shader == dup.shader and diff.is_empty(), "複製材質＝元の材質と同じ shader・ground_k 以外の引数が同一（差 %s）" % str(diff))
	eb.set("enabled", true)
	ok(int(eb.get("applied")) == BANK_N, "enabled=true → 再套用 %d" % int(eb.get("applied")))


# ─────────────────────────── C junction ───────────────────────────
func _find_idx(vs: PackedVector3Array, xf: Transform3D, x: float, z: float) -> int:
	var hit := -1
	var n := 0
	for i in vs.size():
		var w := xf * vs[i]
		if absf(w.x - x) < 0.01 and absf(w.z - z) < 0.01:
			hit = i
			n += 1
	return hit if n == 1 else -1


func _junction_check(tmesh: ArrayMesh, rmesh: ArrayMesh, xf: Transform3D, table: Array, tag := "") -> void:
	var a := tmesh.surface_get_arrays(0)
	var b := rmesh.surface_get_arrays(0)
	var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
	ok(tmesh.get_surface_count() == 1 and av.size() == bv.size(), "%s頂点数 %d＝RoadBase の地形 %d、surface 1" % [tag, av.size(), bv.size()])
	if av.size() != bv.size():
		return
	var exp_idx := {}
	for row: Array in table:
		var i := _find_idx(bv, xf, float(row[0]), float(row[1]))
		ok(i >= 0, "%s記録の頂点 (%.0f, %.0f) が RoadBase 地形で一意に引き当たる（idx %d）" % [tag, row[0], row[1], i])
		if i >= 0:
			exp_idx[i] = row
	# 位置・index は逐一同じ、法線は量子化誤差内
	var pos_bad := 0
	for i in av.size():
		if not av[i].is_equal_approx(bv[i]):
			pos_bad += 1
	ok(pos_bad == 0, "%s頂点位置が RoadBase 地形と全て同一（差 %d）" % [tag, pos_bad])
	var ia: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var ib: PackedInt32Array = b[Mesh.ARRAY_INDEX]
	ok(ia == ib, "%sindex（三角形の並び）が同一（%d 本）" % [tag, ia.size() / 3])
	var na: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var nb: PackedVector3Array = b[Mesh.ARRAY_NORMAL]
	var nrm_bad := 0
	for i in na.size():
		if (na[i] - nb[i]).length() > 0.001:
			nrm_bad += 1
	ok(nrm_bad == 0, "%s法線が同一（量子化誤差 0.001 内・差 %d）" % [tag, nrm_bad])
	var ua: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var ub: PackedVector2Array = b[Mesh.ARRAY_TEX_UV]
	var u2a: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var u2b: PackedVector2Array = b[Mesh.ARRAY_TEX_UV2]
	var uv_bad := 0
	var u2x_bad := 0
	var u2y_bad := 0
	var ca: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var cb: PackedColorArray = b[Mesh.ARRAY_COLOR]
	var gba_bad := 0
	var r_bad := 0
	var changed := 0
	for i in av.size():
		if not ua[i].is_equal_approx(ub[i]):
			uv_bad += 1
		if absf(u2a[i].x - u2b[i].x) > 1e-4:
			u2x_bad += 1
		if absf(ca[i].g - cb[i].g) > 0.005 or absf(ca[i].b - cb[i].b) > 0.005 or absf(ca[i].a - cb[i].a) > 0.005:
			gba_bad += 1
		if exp_idx.has(i):
			var row: Array = exp_idx[i]
			if absf(ca[i].r - float(row[2])) > 0.006:
				r_bad += 1
			if absf(u2a[i].y - float(row[3])) > 0.004:
				u2y_bad += 1
			changed += 1
		else:
			if absf(ca[i].r - cb[i].r) > 0.004:
				r_bad += 1
			if absf(u2a[i].y - u2b[i].y) > 1e-4:
				u2y_bad += 1
	ok(uv_bad == 0 and u2x_bad == 0 and gba_bad == 0, "%sUV／UV2.x／COLOR.gba が全頂点で不変（差 %d／%d／%d）" % [tag, uv_bad, u2x_bad, gba_bad])
	ok(r_bad == 0 and u2y_bad == 0 and changed == table.size(), "%sCOLOR.r／UV2.y は記録の %d 頂点だけ新値、他の全頂点は RoadBase のまま（r 違い %d、street 違い %d）" % [tag, changed, r_bad, u2y_bad])


func _c_junction() -> void:
	var jf := v.get_node("FarmJunctionFixP13")
	var rb := v.get_node("RoadBaseP10")
	var tmi := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	ok(String(tmi.mesh.resource_name) == "FarmJunctionFix_FarmlandTerrain", "FarmlandTerrain.mesh＝FarmJunctionFix_FarmlandTerrain（実 %s）" % tmi.mesh.resource_name)
	var rpaths: PackedStringArray = rb.get("road_paths")
	var ti := rpaths.find("Terrain/FarmlandTerrain")
	ok(ti >= 0, "RoadBaseP10.road_paths に Terrain/FarmlandTerrain がある（index %d）" % ti)
	var rmesh: ArrayMesh = (rb.get("road_meshes") as Array)[ti]
	_junction_check(tmi.mesh as ArrayMesh, rmesh, tmi.global_transform, JUNCTION, "")
	# overlay が持つ頂点番号は、位置から独立に引いた番号と一致
	var vs: PackedVector3Array = rmesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var want := []
	for row: Array in JUNCTION:
		want.append(_find_idx(vs, tmi.global_transform, float(row[0]), float(row[1])))
	var have := []
	for i in (jf.get("vidx") as PackedInt32Array):
		have.append(i)
	ok(want == have, "overlay の頂点番号 %s＝位置から独立に引いた番号 %s" % [str(have), str(want)])
	ok(tmi.mesh.custom_aabb == rmesh.custom_aabb, "custom_aabb 不変")
	# 開閉
	jf.set("enabled", false)
	ok(tmi.mesh == rmesh, "enabled=false → FarmlandTerrain.mesh は RoadBase の mesh そのもの")
	jf.set("enabled", true)
	ok(String(tmi.mesh.resource_name) == "FarmJunctionFix_FarmlandTerrain" and int(jf.get("applied")) == JUNCTION.size(), "enabled=true → 再套用")
	# 元の mesh が変わった（位置不一致）なら拒否
	var bad := Node3D.new()
	bad.set_script(jf.get_script())
	bad.set("terrain_path", jf.get("terrain_path"))
	bad.set("vidx", jf.get("vidx"))
	var vxs := PackedFloat32Array()
	for x in (jf.get("vx") as PackedFloat32Array):
		vxs.append(x + 0.5)
	bad.set("vx", vxs)
	bad.set("vz", jf.get("vz"))
	bad.set("new_r", jf.get("new_r"))
	bad.set("new_street", jf.get("new_street"))
	bad.set("enabled", false)
	v.add_child(bad)
	var before_mesh := tmi.mesh
	bad.call("apply", true)
	ok(int(bad.get("applied")) == 0 and tmi.mesh == before_mesh, "記録と位置が違う頂点表は拒否（applied 0・mesh 不変）")
	bad.queue_free()


# ─────────────────────────── D batch1 ───────────────────────────
func _eff(mi: MeshInstance3D, si: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var ov := mi.get_surface_override_material(si)
	return ov if ov != null else mi.mesh.surface_get_material(si)


func _variant_file(id: String) -> String:
	return String(reg_by_id[id]["file"]) if reg_by_id.has(id) else ""


## 1 棟 1 LOD の期待：{base path: 期待する実効材質 file}。Kawara は期待なし（不変）
func _expected_for(b: Dictionary) -> Dictionary:
	return {
		SRC_PLASTER: _variant_file(String(b["plaster"])),
		SRC_WOOD: _variant_file(String(b["wood"])),
		SRC_STONE: _variant_file("V2_KitStoneTri_K"),
		SRC_ATLAS: _variant_file("V2_MachiyaKit_K"),
	}


func _check_building(b: Dictionary, node: Node3D, tag := "") -> int:
	## 返り値＝不一致の面数（0 が合格）。建物ノード全体（Kit の LOD0／1／2 全面＋Frontage など Kit 外の子）を見る
	var bad := 0
	var expd := _expected_for(b)
	var kit := node.get_node("Kit")
	for lod in ["LOD0", "LOD1", "LOD2"]:
		if kit.get_node_or_null(lod) == null:
			bad += 1
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		if m.material_override != null and reg_by_file.has(m.material_override.resource_path):
			bad += 1   # 登記変体を material_override に入れるのは不可（surface override だけ）。P4 灰盒の子 Foundation／Building_Main／Roof／Hisashi／Door の既存 override は対象外
			if bad_detail.size() < 12:
				bad_detail.append("%s/%s: material_override に登記変体" % [node.name, m.name])
		for si in m.mesh.get_surface_count():
			var base := m.mesh.surface_get_material(si)
			var bp := base.resource_path if base != null else ""
			var ov := m.get_surface_override_material(si)
			var why := ""
			if bp == SRC_KAWARA:
				if ov != null:
					why = "Kawara に覆寫"
			elif bp == SRC_ATLAS and String(m.name).begins_with(ROOF_HIP_PREFIX):
				if ov != null:
					why = "屋根 l_rh_* に覆寫"   # LOD1／LOD2 の屋根は未校正アトラスのまま
			elif expd.has(bp):
				if ov == null or ov.resource_path != String(expd[bp]):
					why = "期待 %s／実 %s" % [String(expd[bp]).get_file(), ov.resource_path.get_file() if ov != null else "なし"]
			elif ov != null and reg_by_file.has(ov.resource_path):
				why = "想定外の基底 %s に登記変体 %s" % [bp.get_file(), ov.resource_path.get_file()]
			if why != "":
				bad += 1
				if bad_detail.size() < 12:
					bad_detail.append("%s/%s[%d]: %s" % [node.name, v.get_path_to(m).get_concatenated_names().get_slice("/", 5) if false else String(m.get_parent().name) + "/" + String(m.name), si, why])
	return bad


## 名簿 50 棟の全 LOD で、『覆寫されるはずの面』と『屋根（l_rh_*）のため覆寫されない面』を独立に数える
func _expected_counts(rows: Array, node_by_path: Dictionary) -> Vector2i:
	var applied := 0
	var skipped := 0
	for b: Dictionary in rows:
		var n := node_by_path.get(String(b["path"])) as Node3D
		if n == null:
			continue
		var expd := _expected_for(b)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var base := m.mesh.surface_get_material(si)
				var bp := base.resource_path if base != null else ""
				if not expd.has(bp):
					continue
				if bp == SRC_ATLAS and String(m.name).begins_with(ROOF_HIP_PREFIX):
					skipped += 1
				else:
					applied += 1
	return Vector2i(applied, skipped)


func _d_batch() -> void:
	var rows: Array = man["buildings"]
	ok(rows.size() == 50 and int(man["count"]) == 50, "名簿 50 棟（manifest %d）" % rows.size())
	var ids := {}
	for b: Dictionary in rows:
		ids[String(b["id"])] = true
	ok(ids.size() == 50, "ID 重複なし")
	var in_w2 := []
	var in_pilot := []
	for b: Dictionary in rows:
		if w2_ids.has(String(b["id"])):
			in_w2.append(b["id"])
		if pilot_set.has(String(b["path"])):
			in_pilot.append(b["id"])
	ok(in_w2.is_empty(), "W2 主街 39 棟と重ならない（重複 %s）" % str(in_w2))
	ok(in_pilot.is_empty(), "R6a Pilot 24 棟と重ならない（重複 %s）" % str(in_pilot))
	var node_by_path := {}
	for n in all_b:
		node_by_path[String(v.get_path_to(n))] = n
	var miss := 0
	var kit_bad := 0
	var area_bad := 0
	var var_bad := 0
	for b: Dictionary in rows:
		if not node_by_path.has(String(b["path"])):
			miss += 1
			continue
		var n: Node3D = node_by_path[String(b["path"])]
		if String(n.get_meta("kit_asset", "")) != "machiya_kit":
			kit_bad += 1
		if AREA_OF.get(String(b["district"]), "") != String(b["area"]):
			area_bad += 1
		for key in ["plaster", "wood"]:
			var e: Dictionary = reg_by_id.get(String(b[key]), {})
			var want_base := SRC_PLASTER if key == "plaster" else SRC_WOOD
			if e.is_empty() or String(e["kind"]) != "palette" or String(e["area"]) != String(b["area"]) or String(e["base"]) != want_base:
				var_bad += 1
	ok(miss == 0, "名簿の建物がすべて場景に存在（欠落 %d）" % miss)
	ok(kit_bad == 0, "50 棟すべて machiya_kit の町家 Kit（違い %d）" % kit_bad)
	ok(area_bad == 0, "区と用途の対応：Market／MixedCommercial＝商業 A・Residential＝住宅 B（違い %d）" % area_bad)
	ok(var_bad == 0, "割り当てた変体はすべて R6a 登記の palette 変体で、区・基底材質が一致（違い %d）" % var_bad)
	# overlay の内容＝名簿
	var ab := v.get_node("AlbedoBatch1P13")
	var tg: PackedStringArray = ab.get("targets")
	var same_order := tg.size() == rows.size()
	if same_order:
		for i in rows.size():
			if String(tg[i]) != String(rows[i]["path"]):
				same_order = false
	ok(same_order, "overlay.targets＝名簿（50・同順）")
	var cal_mats: Array = ab.get("cal_mats")
	var cal_ok := cal_mats.size() == 4
	for m in cal_mats:
		if not reg_by_file.has((m as Material).resource_path):
			cal_ok = false
	ok(cal_ok, "overlay の校正材質 4 はすべて R6a 登記ファイルの外部參照")
	var cnt := _expected_counts(rows, node_by_path)
	ok(int(ab.get("applied_surfaces")) == cnt.x and int(ab.get("skipped_surfaces")) == cnt.y and cnt.y > 0, "overlay の覆寫 %d 面・屋根（l_rh_*）不覆寫 %d 面＝名簿から独立に数えた値（%d／%d）" % [int(ab.get("applied_surfaces")), int(ab.get("skipped_surfaces")), cnt.x, cnt.y])
	var skp: PackedStringArray = ab.get("skip_prefixes")
	ok(skp.size() == 1 and String(skp[0]) == ROOF_HIP_PREFIX, "overlay.skip_prefixes＝[%s]（実 %s）" % [ROOF_HIP_PREFIX, str(skp)])
	# 材質回読：LOD0／1／2 全面
	var bad_total := 0
	var per_bad := []
	for b: Dictionary in rows:
		if not node_by_path.has(String(b["path"])):
			continue
		var bb := _check_building(b, node_by_path[String(b["path"])])
		bad_total += bb
		if bb > 0:
			per_bad.append("%s:%d" % [b["id"], bb])
	ok(bad_total == 0, "50 棟 × 建物ノード全体（Kit の LOD0／1／2 全面＋Frontage 等 Kit 外の子）：期待どおりの登記変体、Kawara 不校正、LOD1／2 の屋根 l_rh_* は未校正アトラスのまま、material_override なし（不一致 %d %s %s）" % [bad_total, str(per_bad.slice(0, 4)), str(bad_detail.slice(0, 4))])
	# 範囲外の建物は覆寫なし（W2 主街 36 棟は Pilot 3 棟を除いて不変）
	var allowed := {}
	for p in pilot_set:
		allowed[p] = true
	for p in batch_set:
		allowed[p] = true
	var out_bad := 0
	var out_ex := []
	var w2_bad := 0
	for n in all_b:
		var np := String(v.get_path_to(n))
		if allowed.has(np):
			continue
		for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var ov := m.get_surface_override_material(si)
				if ov != null and reg_by_file.has(ov.resource_path):
					out_bad += 1
					if out_ex.size() < 3:
						out_ex.append(np.get_file())
					if w2_ids.has(np.get_file()):
						w2_bad += 1
	ok(out_bad == 0 and w2_bad == 0, "範囲外（Pilot 24＋batch 50 以外）の町家に登記変体の覆寫 0（実 %d %s、うち W2 主街 %d）" % [out_bad, str(out_ex), w2_bad])
	# 14 m 内同区同組なし（Pilot ∪ batch）
	var combos := []   # [pos, area, plaster id, wood id, name]
	var pal := v.get_node("AlbedoPilotP10")
	var pt: PackedStringArray = pal.get("targets")
	var ptv: Array = pal.get("target_variants")
	var pvm: Array = pal.get("variant_mats")
	for i in pt.size():
		var n := v.get_node_or_null(NodePath(String(pt[i]))) as Node3D
		if n == null:
			continue
		var pid := ""
		var wid := ""
		for sp in (ptv[i] as Dictionary):
			var f: String = (pvm[int(ptv[i][sp])] as Material).resource_path
			var e: Dictionary = reg_by_file.get(f, {})
			if String(sp) == SRC_PLASTER:
				pid = String(e.get("id", ""))
			elif String(sp) == SRC_WOOD:
				wid = String(e.get("id", ""))
		combos.append([Vector2(n.global_position.x, n.global_position.z), String(reg_by_id.get(pid, {}).get("area", "")), pid, wid, n.name])
	for b: Dictionary in rows:
		var n2 := node_by_path.get(String(b["path"])) as Node3D
		if n2 != null:
			combos.append([Vector2(n2.global_position.x, n2.global_position.z), String(b["area"]), String(b["plaster"]), String(b["wood"]), n2.name])
	var clash := []
	for i in combos.size():
		for j in range(i + 1, combos.size()):
			if String(combos[i][1]) == String(combos[j][1]) and (combos[i][0] as Vector2).distance_to(combos[j][0]) < NEIGHBOR_M and combos[i][2] == combos[j][2] and combos[i][3] == combos[j][3]:
				clash.append("%s/%s" % [combos[i][4], combos[j][4]])
	ok(clash.is_empty(), "14 m 内の同区・同組なし（Pilot %d ＋ batch %d 棟の全対。衝突 %s）" % [pt.size(), rows.size(), str(clash.slice(0, 4))])
	# 変体の輝度／飽和帯
	var used := {}
	for b: Dictionary in rows:
		used[String(b["plaster"])] = true
		used[String(b["wood"])] = true
	var band_bad := []
	for id in used:
		var m := load(_variant_file(String(id))) as StandardMaterial3D
		var c := m.albedo_color
		var lm := _luma(c)
		var band := LUMA_PLASTER if String(id).begins_with("V2_Plaster") else LUMA_WOOD
		if lm < band.x - 0.001 or lm > band.y + 0.001 or _sat(c) > SAT_MAX + 0.001:
			band_bad.append("%s luma %.2f sat %.2f" % [id, lm, _sat(c)])
	ok(band_bad.is_empty(), "使用した変体 %d 種の輝度帯（漆喰 0.66–0.76／木 0.66–0.82）と飽和 ≤ %.2f（違反 %s）" % [used.size(), SAT_MAX, str(band_bad)])
	# LOD0 と LOD1/2 の明度差（LOD1/2 は atlas の k_light 0.70／k_dark 0.75）
	var atlas := load(_variant_file("V2_MachiyaKit_K")) as ShaderMaterial
	var k_light := float(atlas.get_shader_parameter("k_light"))
	var k_dark := float(atlas.get_shader_parameter("k_dark"))
	var lod_bad := []
	var max_dp := 0.0
	var max_dw := 0.0
	for b: Dictionary in rows:
		var mp := load(_variant_file(String(b["plaster"]))) as StandardMaterial3D
		var mw := load(_variant_file(String(b["wood"]))) as StandardMaterial3D
		var dp := absf(_luma(mp.albedo_color) - k_light)
		var dw := absf(_luma(mw.albedo_color) - k_dark)
		max_dp = maxf(max_dp, dp)
		max_dw = maxf(max_dw, dw)
		if dp > LOD_DELTA_PLASTER or dw > LOD_DELTA_WOOD:
			lod_bad.append(String(b["id"]))
	ok(lod_bad.is_empty(), "LOD0 → LOD1/2 の明度差：漆喰 ≤ %.2f（最大 %.3f）・木 ≤ %.2f（最大 %.3f）＝遠景で灰に戻らない（違反 %s）" % [LOD_DELTA_PLASTER, max_dp, LOD_DELTA_WOOD, max_dw, str(lod_bad)])
	# 開閉
	ab.set("enabled", false)
	var left := 0
	for b: Dictionary in rows:
		var n3 := node_by_path.get(String(b["path"])) as Node3D
		if n3 == null:
			continue
		for mi in n3.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.material_override != null and reg_by_file.has(m3.material_override.resource_path):
				left += 1
			if m3.mesh != null:
				for si in m3.mesh.get_surface_count():
					var ov3 := m3.get_surface_override_material(si)
					if ov3 != null and reg_by_file.has(ov3.resource_path):
						left += 1   # 登記変体の覆寫だけ数える（Frontage などの既存の覆寫は元からある）
	ok(left == 0 and int(ab.get("applied_surfaces")) == 0, "enabled=false → 50 棟の覆寫 0（残 %d）" % left)
	ab.set("enabled", true)
	ok(int(ab.get("applied_surfaces")) > 0, "enabled=true → 再套用（%d 面）" % int(ab.get("applied_surfaces")))


# ─────────────────────────── E deps ───────────────────────────
func _e_deps() -> void:
	var names := ["EarthBankToneP13", "FarmJunctionFixP13", "AlbedoBatch1P13"]
	var own := 0
	for nm in names:
		var n := v.get_node(nm)
		own += n.find_children("*", "CollisionObject3D", true, false).size() + n.find_children("*", "NavigationRegion3D", true, false).size() + n.find_children("*", "MultiMeshInstance3D", true, false).size()
	ok(own == 0, "3 overlay は碰撞／導航／MultiMesh を持たない（%d）" % own)
	var c0 := [_count("MeshInstance3D"), _count("CollisionObject3D"), _count("NavigationRegion3D"), _count("MultiMeshInstance3D")]
	for nm in names:
		v.get_node(nm).set("enabled", false)
	await process_frame
	var c1 := [_count("MeshInstance3D"), _count("CollisionObject3D"), _count("NavigationRegion3D"), _count("MultiMeshInstance3D")]
	for nm in names:
		v.get_node(nm).set("enabled", true)
	await process_frame
	ok(c0 == c1, "3 overlay の開閉で MeshInstance3D／碰撞物／導航領域／MultiMesh の数が不変 %s" % str(c0))


# ─────────────────────────── N negatives ───────────────────────────
func _negatives() -> void:
	var fails0 := fails
	var passes0 := passes
	var cases := 0
	var tripped := 0
	# N1: batch に W2 主街の建物を混ぜる
	quiet = true
	var f1 := fails
	var in_w2 := []
	var fake := String(w2_ids.keys()[0])
	if w2_ids.has(fake):
		in_w2.append(fake)
	ok(in_w2.is_empty(), "N1")
	cases += 1
	tripped += 1 if fails > f1 else 0
	# N2: 期待を取り違えた変体（漆喰の変体を木の欄に）
	var rows: Array = man["buildings"]
	var b2: Dictionary = rows[0].duplicate()
	var tmp: String = b2["plaster"]
	b2["plaster"] = b2["wood"]
	b2["wood"] = tmp
	var node0 := v.get_node(NodePath(String(rows[0]["path"]))) as Node3D
	var f2 := fails
	ok(_check_building(b2, node0) == 0, "N2")
	cases += 1
	tripped += 1 if fails > f2 else 0
	# N3: LOD2 の覆寫を外す
	var f3 := fails
	var removed_mi: MeshInstance3D = null
	for mi in node0.get_node("Kit/LOD2").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			if m.get_surface_override_material(si) != null:
				m.set_surface_override_material(si, null)
				removed_mi = m
				break
		if removed_mi != null:
			break
	ok(_check_building(rows[0], node0) == 0, "N3")
	cases += 1
	tripped += 1 if fails > f3 else 0
	v.get_node("AlbedoBatch1P13").call("apply", true)   # 戻す
	# N4: EarthBank の k を違う値に
	var bank := v.get_node(BANK_PATH)
	var f4 := fails
	var mat0 := (bank.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	var old_k = mat0.get_shader_parameter("ground_k")
	mat0.set_shader_parameter("ground_k", 0.30)
	ok(absf(float(mat0.get_shader_parameter("ground_k")) - BANK_K_NEW) < 1e-4, "N4")
	mat0.set_shader_parameter("ground_k", old_k)
	cases += 1
	tripped += 1 if fails > f4 else 0
	# N5: 記録の r を 1 頂点だけ変えた表で junction 検査
	var jf := v.get_node("FarmJunctionFixP13")
	var rb := v.get_node("RoadBaseP10")
	var tmi := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	var tbl: Array = []
	for row in JUNCTION:
		tbl.append((row as Array).duplicate())
	tbl[2][2] = 0.5
	var f5 := fails
	_junction_check(tmi.mesh as ArrayMesh, (rb.get("road_meshes") as Array)[(rb.get("road_paths") as PackedStringArray).find("Terrain/FarmlandTerrain")], tmi.global_transform, tbl)
	cases += 1
	tripped += 1 if fails > f5 else 0
	# N6: 記録外の頂点（1 つ多い）が変わっている想定＝記録表から 1 点を落とす
	var tbl2: Array = []
	for k in JUNCTION.size() - 1:
		tbl2.append((JUNCTION[k] as Array).duplicate())
	var f6 := fails
	_junction_check(tmi.mesh as ArrayMesh, (rb.get("road_meshes") as Array)[(rb.get("road_paths") as PackedStringArray).find("Terrain/FarmlandTerrain")], tmi.global_transform, tbl2)
	cases += 1
	tripped += 1 if fails > f6 else 0
	# N7: Pilot 建物に batch の期待を当てる（範囲外検査の発火）
	var pb := v.get_node_or_null(NodePath(String(reg["pilot_buildings"][0]))) as Node3D
	var f7 := fails
	var fake_row: Dictionary = rows[0].duplicate()
	ok(_check_building(fake_row, pb) == 0, "N7")
	cases += 1
	tripped += 1 if fails > f7 else 0
	# N8: LOD1 の屋根（l_rh_*）に K 版アトラスを覆寫すると不一致になる
	var f8 := fails
	var roof_mi: MeshInstance3D = null
	for mi in node0.get_node("Kit/LOD1").find_children("l_rh_*", "MeshInstance3D", true, false):
		roof_mi = mi as MeshInstance3D
		break
	if roof_mi != null:
		roof_mi.set_surface_override_material(0, load(_variant_file("V2_MachiyaKit_K")) as Material)
	ok(roof_mi != null and _check_building(rows[0], node0) == 0, "N8")
	cases += 1
	tripped += 1 if fails > f8 else 0
	v.get_node("AlbedoBatch1P13").call("apply", true)   # 戻す
	quiet = false
	fails = fails0
	passes = passes0
	print("[W7G]   反向 %d/%d が正しく FAIL" % [tripped, cases])
	ok(tripped == cases, "反向 %d/%d" % [tripped, cases])
