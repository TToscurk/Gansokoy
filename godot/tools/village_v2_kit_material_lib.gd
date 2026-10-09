extends RefCounted
## P10 R6a ROUND 3 — 町家 Kit 專用亮度校正材質＋區域調色盤變體（使用者 ROUND 3 §4：方案 A APPROVED FOR IMPLEMENTATION）。
## 方案 A：Kit 專用校正材質＝新資產（assets/village_v2/machiya_kit_cal/），不改全村共用材質庫 _matlib、不改 P6 Kit 原檔、不放寬 Kit Gate。
##   - 數值＝第一輪已核准的 24 棟 Pilot（village_v2_albedo_pilot_lib.gd 的 CAL／KIT_CLASS／PALETTE，唯一來源；本檔不另寫數值）。
##   - 變體登記表 kit_material_variants.json：每個變體＝id、檔案、sha256、類別、基底材質、區域、albedo（sRGB）、飽和度、色卡 luma 帶、
##     「與基底只允許差異的屬性」＝albedo_color（Kit atlas 的校正 shader：只允許 k_* 係數）。
##   - 合法變體機制（verify_village_v2_kit_material.gd，tag KITM）：場景中町家 Kit 建物上的任何 override 都必須是登記表內的變體、
##     只出現在登記的 Pilot 建物上、檔案雜湊與登記一致、與基底只差允許的屬性 → 任意 override 仍然禁止（Kit Gate 原規則不變）。
##   - 位置：machiya_kit_cal/ 是 machiya_kit/ 的兄弟目錄（不在已封存的 P6 Kit 目錄裡加檔）。
##   - 本輪只有 AlbedoPilotP10 的 24 棟使用；不改 187 棟（全村套用＝ART_APPROVED 後，見 round3/r6a_kit_material/README.md）。
##   godot --headless --path godot --script res://tools/verify_village_v2_kit_material.gd -- --write   （寫材質＋登記表）
const AP := preload("res://tools/village_v2_albedo_pilot_lib.gd")
const DIR := "res://assets/village_v2/machiya_kit_cal/"
const REGISTRY := DIR + "kit_material_variants.json"
const SHADER := DIR + "kit_cal.gdshader"
const PHASE := "P10 R6a ROUND 3 Kit material Pilot（ART_REVIEW）"
const SAT_MAX := 0.22
## 色卡 luma 帶（日照垂直面、sRGB）＝AP.TARGET_LUMA；albedo_color 的允許帶（sRGB 灰階／明度）：校正值 ± 調色盤幅
const ALBEDO_BAND := {"V2_Plaster": [0.66, 0.76], "V2_Wood": [0.66, 0.82], "V2_KitStoneTri": [0.60, 0.70]}
const PROTECTED := [
	"res://assets/village_v2/_matlib/V2_Plaster.tres", "res://assets/village_v2/_matlib/V2_Wood.tres", "res://assets/village_v2/_matlib/V2_Kawara.tres",
	"res://assets/village_v2/_matlib/matlib.json", "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres", "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
	"res://assets/village_v2/machiya_kit/gate.json", "res://assets/village_v2/machiya_kit/machiya_kit_manifest.json",
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
		"rule": "町家 Kit 建物の override は本表の変体だけ・pilot_buildings の建物だけ・sha256 一致・基底との差は allowed_diff だけ（Kit Gate の任意 override 禁止は不変）",
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
