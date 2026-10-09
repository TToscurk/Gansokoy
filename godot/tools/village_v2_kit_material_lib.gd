extends RefCounted
## P10 R6a 町家 Kit 專用亮度校正材質＋區域調色盤變體（使用者 ROUND 3 §4：方案 A；2026-10-09 ROUND 3 FINAL：R6a Kit Material 24 Buildings Pilot＝ART_APPROVED）。
## 方案 A：Kit 專用校正材質＝新資產（maps/village_v2/kit_cal_p10/），不改全村共用材質庫 _matlib、不改 Kit 原檔（V2_MachiyaKit／V2_KitStoneTri）。
##   - 數值＝第一輪已核准的 24 棟 Pilot（village_v2_albedo_pilot_lib.gd 的 CAL／KIT_CLASS／PALETTE，唯一來源；本檔不另寫數值）。
##   - 變體登記表 cal/kit_material_variants.json：每個變體＝id、檔案、sha256、類別、基底材質、區域、albedo（sRGB）、飽和度、色卡 luma 帶、
##     「與基底只允許差異的屬性」＝albedo_color（Kit atlas 的校正 shader：只允許 k_* 係數）、Pilot 建物 24。
##   - 正式整合（ROUND 3 FINAL）：合法変体機制＝登記表（各檔 sha256）＋封存 data/village_v2_p10r6a_seal.json（登記表と全変体の sha を凍結）；
##     P6 Kit Gate の「4 材質」は「override は登記変体だけ・登記の Pilot 建物だけ・基底一致・登記表と変体の sha＝封存」だけ合法
##     （未登記・Pilot 外・基底違い・material_override は従来どおり FAIL）；KITM＝本機制の詳細 gate。
##   - 置き場所：maps/village_v2/kit_cal_p10/（village_v2 overlay の生成物と同じ許可前綴；R4c の gen/r4c と同じ扱い）。
##     ROUND 3 Pilot では assets/village_v2/machiya_kit_cal/（未登記の資產目錄＝P5 白名單違規 +19）だった。
##     machiya_kit/cal＋Kit manifest への登記も試したが、manifest が変わると Kit Asset Gate 11 項の再実行が必要で、その render 項 f5_f6 が
##     P10 R2 StreetP10 の店先の台（高 0.52 m）で FAIL（Kit と無関係の跨層衝突）→ registry から machiya_kit が外れるため不採用・裁定待ち
##     （docs/art_review/village_v2_p10_rehab_impl/integration/r6a/manifest_route_attempt/）。
##   godot --headless --path godot --script res://tools/verify_village_v2_kit_material.gd -- --write      （寫材質＋登記表）
const AP := preload("res://tools/village_v2_albedo_pilot_lib.gd")
const DIR := "res://maps/village_v2/kit_cal_p10/"
const SEAL := "res://data/village_v2_p10r6a_seal.json"
const REGISTRY := DIR + "kit_material_variants.json"
const SHADER := DIR + "kit_cal.gdshader"
const PHASE := "P10 R6a Kit material 24 Buildings Pilot（ART_APPROVED 使用者 2026-10-09 ROUND 3 FINAL）"
const SAT_MAX := 0.22
## 色卡 luma 帶（日照垂直面、sRGB）＝AP.TARGET_LUMA；albedo_color 的允許帶（sRGB 灰階／明度）：校正值 ± 調色盤幅
const ALBEDO_BAND := {"V2_Plaster": [0.66, 0.76], "V2_Wood": [0.66, 0.82], "V2_KitStoneTri": [0.60, 0.70]}
const PROTECTED := [
	"res://assets/village_v2/_matlib/V2_Plaster.tres", "res://assets/village_v2/_matlib/V2_Wood.tres", "res://assets/village_v2/_matlib/V2_Kawara.tres",
	"res://assets/village_v2/_matlib/matlib.json", "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres", "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
]


static func base_name(src: String) -> String:
	return src.get_file().get_basename()


## 書き出す変体の一覧（値は AP の定数から）：[{id, kind, base, area, file, color|k}]
static func plan() -> Array:
	var out := []
	var keys := AP.CAL.keys()
	keys.sort()
	for p in keys:
		var bn := base_name(p)
		var k := float(AP.CAL[p])
		out.append({"id": bn + "_K", "kind": "cal", "base": p, "area": "", "file": DIR + bn + "_K.tres", "color": Color(k, k, k, 1.0)})
	out.append({"id": "V2_MachiyaKit_K", "kind": "kit_atlas_cal", "base": AP.KIT_SRC, "area": "", "file": DIR + "V2_MachiyaKit_K.tres",
		"k": {"k_dark": float(AP.KIT_CLASS["k_dark"]), "k_mid": float(AP.KIT_CLASS["k_mid"]), "k_light": float(AP.KIT_CLASS["k_light"])}})
	var areas := AP.PALETTE.keys()
	areas.sort()
	for a in areas:
		for mn in ["V2_Plaster", "V2_Wood"]:
			var cols: Array = AP.PALETTE[a][mn]
			for i in cols.size():
				var c: Color = cols[i]
				var id := "%s_K_%s%d" % [mn, String(a).substr(0, 1), i]
				out.append({"id": id, "kind": "palette", "base": AP.PALETTE_SRC[mn], "area": a, "file": DIR + id + ".tres", "color": Color(c.r, c.g, c.b, 1.0)})
	return out


static func _sat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


static func make_material(e: Dictionary) -> Material:
	if String(e["kind"]) == "kit_atlas_cal":
		var src := load(AP.KIT_SRC) as StandardMaterial3D
		var m := ShaderMaterial.new()
		m.shader = load(SHADER)
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("emit_tex", src.emission_texture)
		m.set_shader_parameter("roughness_v", src.roughness)
		m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
		for k in ["k_dark", "k_mid", "k_light"]:
			m.set_shader_parameter(k, float(e["k"][k]))
		m.set_shader_parameter("band_dark", Vector2(AP.KIT_CLASS["band_dark"][0], AP.KIT_CLASS["band_dark"][1]))
		m.set_shader_parameter("band_light", Vector2(AP.KIT_CLASS["band_light"][0], AP.KIT_CLASS["band_light"][1]))
		m.resource_name = String(e["id"])
		return m
	var b := (load(String(e["base"])) as StandardMaterial3D).duplicate() as StandardMaterial3D
	b.albedo_color = e["color"]
	b.resource_name = String(e["id"])
	return b


## 材質＋shader＋登記表を書き出す
static func write_all() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var code := AP.KIT_SHADER_CODE.replace("// P10 R6a albedo pilot：", "// P10 R6a Kit 專用校正（machiya_kit_cal、登記表 kit_material_variants.json）：")
	var f := FileAccess.open(SHADER, FileAccess.WRITE)
	f.store_string(code)
	f.close()
	var reg := {"phase": PHASE, "sat_max": SAT_MAX, "card_luma": AP.TARGET_LUMA, "albedo_band": ALBEDO_BAND,
		"source_of_values": "res://tools/village_v2_albedo_pilot_lib.gd（CAL／KIT_CLASS／PALETTE＝第一輪核准 24 棟 Pilot）",
		"shader": {"file": SHADER, "sha256": FileAccess.get_sha256(SHADER)},
		"rule": "町家 Kit 建物の override は本表の変体だけ・pilot_buildings の建物だけ・sha256 一致（本表と各変体の sha は data/village_v2_p10r6a_seal.json に凍結）・基底との差は allowed_diff だけ（Kit Gate の任意 override 禁止は不変；P6 Kit Gate「4 材質」が本表を読む）",
		"pilot_buildings": [], "protected": {}, "variants": []}
	for p in PROTECTED:
		reg["protected"][p] = FileAccess.get_sha256(p)
	for e in plan():
		var m := make_material(e)
		var err := ResourceSaver.save(m, String(e["file"]))
		if err != OK:
			push_error("save %s %d" % [e["file"], err])
		var ent := {"id": e["id"], "kind": e["kind"], "base": e["base"], "area": e["area"], "file": e["file"], "sha256": FileAccess.get_sha256(String(e["file"]))}
		if e.has("color"):
			var c: Color = e["color"]
			ent["albedo_srgb"] = [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]
			ent["saturation"] = snappedf(_sat(c), 0.001)
			ent["allowed_diff"] = ["albedo_color"]
			ent["albedo_band"] = ALBEDO_BAND[base_name(String(e["base"]))]
			ent["card_luma"] = AP.TARGET_LUMA[base_name(String(e["base"]))]
		else:
			ent["k"] = e["k"]
			ent["allowed_diff"] = ["k_dark", "k_mid", "k_light"]
		reg["variants"].append(ent)
	return reg


static func write_registry(reg: Dictionary) -> void:
	var f := FileAccess.open(REGISTRY, FileAccess.WRITE)
	f.store_string(JSON.stringify(reg, " ", false) + "\n")
	f.close()


static func registry() -> Dictionary:
	if not FileAccess.file_exists(REGISTRY):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))


## AlbedoPilotP10 用：登記表の変体を読み込み（cal＝[src_paths, mats]、palette＝[mats, index]）。登記表がなければ null。
static func pilot_cal() -> Array:
	var reg := registry()
	if reg.is_empty():
		return []
	var src := PackedStringArray()
	var mats: Array[Material] = []
	var cal := {}
	for e in reg["variants"]:
		if String(e["kind"]) in ["cal", "kit_atlas_cal"]:
			cal[String(e["base"])] = String(e["file"])
	var keys := AP.CAL.keys()
	keys.sort()
	for p in keys:
		src.append(p)
		mats.append(load(cal[p]))
	src.append(AP.KIT_SRC)
	mats.append(load(cal[AP.KIT_SRC]))
	return [src, mats]


static func pilot_palette() -> Array:
	var reg := registry()
	if reg.is_empty():
		return []
	var by_id := {}
	for e in reg["variants"]:
		by_id[String(e["id"])] = String(e["file"])
	var mats: Array[Material] = []
	var index := {}
	var areas := AP.PALETTE.keys()
	areas.sort()
	for a in areas:
		index[a] = {}
		for mn in ["V2_Plaster", "V2_Wood"]:
			index[a][mn] = []
			for i in (AP.PALETTE[a][mn] as Array).size():
				index[a][mn].append(mats.size())
				mats.append(load(by_id["%s_K_%s%d" % [mn, String(a).substr(0, 1), i]]))
	return [mats, index]

