extends RefCounted
## P10 R6a 材質亮度基準 Pilot（使用者 2026-10-09 D8：DO NOW, PILOT FIRST——先以色卡與代表建築驗證，不一次改全村；P13 天光另案）。
## 根因：_matlib 建物材質 albedo_k 0.42（P1 為 Compatibility 地表校正的係數）沿用到 Forward+ → 日照下白漆喰暗於 18 % 灰卡。
## Pilot：只對兩個代表區（入口〜南大鳥居〜主街南段／西巷住宅）的建物，以「逐材質」校正值（非等比提亮）覆寫表面材質。
##   做法：overlay `AlbedoPilotP10`（gen/albedo_pilot_p10.scn，掛 root、EdgeClosureP10 之後）＝一個帶 script 的節點，
##   內嵌校正材質，_ready 時對名單內建物的 MeshInstance3D 做 surface override；`enabled=false` 即還原。
##   _matlib 原檔、P6 kit、village_v2 的建物節點都不改。
## 町家 Kit atlas（V2_MachiyaKit）：LOD1/2 的 l_* 網格把屋根（swatch 灰 0.42）、漆喰（0.87）、木（0.20）都畫在同一張 atlas 上，
##   r1–r3 用單一 k 0.80 → 遠景屋根跟著變淺（高視角審圖「屋面淺灰」）。r4 改成「依 atlas 色階分類」的 shader：
##   暗（木）→ k 0.75（＝V2_Wood）、中（屋根灰／暖簾）→ k 0.42（不變＝V2_Kawara）、亮（漆喰／障子）→ k 0.70（＝V2_Plaster），
##   LOD0 與 LOD1/2 同一套對應 → 屋根不變淺、牆在 40 m LOD 切換時不跳亮度。
## 全村套用（ART_APPROVED 後）＝改 matlib.json albedo_k＋.tres／kit atlas → Asset Gate → registry；本 Pilot 不做。

const NODE_NAME := "AlbedoPilotP10"
const OUTPUT := "res://maps/village_v2/gen/albedo_pilot_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/albedo_pilot.gd"
const ART_REVISION := "P10 R6a albedo pilot r5：＋街區調色盤（A 商業＝暖白漆喰＋紅殻／飴色木、B 住宅＝灰味漆喰＋風化灰木；每棟決定性挑選、鄰棟不同）（ART_REVIEW）"
## 校正值（albedo_color sRGB 灰階）：依色卡實測（日照下垂直面 luma）選定——
##   白漆喰 0.70→0.718（目標 0.70–0.85；r1 0.75 高視角偏新、偏均一）、木 0.75→0.413（0.35–0.50）、
##   瓦＝不校正（維持 0.42：r1 0.58／r2 0.50 高視角屋面都讀成淺灰）、基石 0.65→0.522（0.50–0.60）。現況全部 0.42。
const CAL := {
	"res://assets/village_v2/_matlib/V2_Plaster.tres": 0.70,
	"res://assets/village_v2/_matlib/V2_Wood.tres": 0.75,
	"res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres": 0.65,
}
const KIT_SRC := "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
## atlas 色階分類（texel×頂點色的 sRGB luma）：< dark 帶＝木、> light 帶＝漆喰／障子、中間＝屋根灰／暖簾等（不變）
const KIT_CLASS := {"k_dark": 0.75, "k_mid": 0.42, "k_light": 0.70, "band_dark": [0.26, 0.34], "band_light": [0.55, 0.70]}
## 每類對應的色卡材質（gate 用色卡實測檢 luma 帶）
const KIT_CLASS_CARD := {"k_dark": "V2_Wood", "k_light": "V2_Plaster"}
const KIT_SHADER := "res://maps/village_v2/shaders_p10/kit_cal_p10.gdshader"
const KIT_SHADER_CODE := """// P10 R6a albedo pilot：V2_MachiyaKit（StandardMaterial3D）的等價 shader＋依 atlas 色階分類的 albedo 係數。
// 由 tools/village_v2_albedo_pilot_lib.gd 產生，勿手改。原材質：albedo_color 0.42 灰、albedo_texture＝machiya_kit_atlas、
// vertex_color_use_as_albedo、roughness 0.9、emission（白）× emission_texture × 0.4（MULTIPLY）、cull back、linear mipmap。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D emit_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float k_dark = 0.75;
uniform float k_mid = 0.42;
uniform float k_light = 0.70;
uniform vec2 band_dark = vec2(0.26, 0.34);
uniform vec2 band_light = vec2(0.55, 0.70);
uniform float roughness_v = 0.9;
uniform float emission_energy = 0.4;

float s2l(float c) {
	return c < 0.04045 ? c * (1.0 / 12.92) : pow((c + 0.055) * (1.0 / 1.055), 2.4);
}

float l2s(float c) {
	return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * COLOR.rgb;   // 線性（source_color 已轉線性；頂點色＝線性）
	float l = l2s(dot(base, vec3(0.2126, 0.7152, 0.0722)));
	float k = mix(k_dark, k_mid, smoothstep(band_dark.x, band_dark.y, l));
	k = mix(k, k_light, smoothstep(band_light.x, band_light.y, l));
	ALBEDO = base * s2l(k);
	ROUGHNESS = roughness_v;
	EMISSION = texture(emit_tex, UV).rgb * emission_energy;
}
"""
const TARGET_LUMA := {"V2_Plaster": [0.70, 0.85], "V2_Wood": [0.35, 0.50], "V2_Kawara": [0.25, 0.40], "V2_KitStoneTri": [0.50, 0.60]}
## R6a 街區調色盤（建築差異 Pilot，同兩區）：albedo_color（sRGB）變體——飽和度上限 0.22、亮度留在色卡目標帶；
##   A 商業（主街南段・入口）：漆喰偏暖白／生成り、木＝飴色・紅殻（弁柄）・素木；B 住宅（西巷）：漆喰帶灰／土色、木＝風化灰・煤色
##   每棟依節點名雜湊挑一組，14 m 內相鄰兩棟不得同組（gate 驗）。
const PALETTE := {
	"A_gate_main_south": {
		"V2_Plaster": [Color(0.73, 0.71, 0.66), Color(0.71, 0.70, 0.67), Color(0.74, 0.70, 0.63), Color(0.70, 0.69, 0.66)],
		"V2_Wood": [Color(0.79, 0.74, 0.69), Color(0.80, 0.70, 0.63), Color(0.75, 0.74, 0.72)]},
	"B_west_alley": {
		"V2_Plaster": [Color(0.71, 0.69, 0.65), Color(0.73, 0.70, 0.64), Color(0.70, 0.70, 0.68), Color(0.72, 0.68, 0.61)],
		"V2_Wood": [Color(0.71, 0.71, 0.71), Color(0.75, 0.72, 0.67), Color(0.68, 0.67, 0.66)]},
}
const PALETTE_SRC := {"V2_Plaster": "res://assets/village_v2/_matlib/V2_Plaster.tres", "V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres"}
const PALETTE_MAX_SAT := 0.22
const NEIGHBOR_M := 14.0


## Pilot 區（世界 xz 矩形）：A 入口〜南大鳥居〜主街南段、B 西巷住宅
const AREAS := {"A_gate_main_south": Rect2(205.0, 40.0, 57.0, 92.0), "B_west_alley": Rect2(178.0, -78.0, 48.0, 62.0)}


static func targets(v: Node3D) -> Array:
	var out := []
	for n in v.get_node("Districts").find_children("B_*", "", true, false):
		if not (n is Node3D):
			continue
		var kit := (n as Node).get_node_or_null("Kit")
		if kit == null:
			continue
		var p := (n as Node3D).global_position
		for k in AREAS:
			if (AREAS[k] as Rect2).has_point(Vector2(p.x, p.z)):
				out.append({"path": String(v.get_path_to(n)), "area": k, "pos": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]})
				break
	out.sort_custom(func(a, b): return String(a["path"]) < String(b["path"]))
	return out


static func write_kit_shader() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(KIT_SHADER.get_base_dir()))
	if FileAccess.file_exists(KIT_SHADER) and FileAccess.get_file_as_string(KIT_SHADER) == KIT_SHADER_CODE:
		return
	var f := FileAccess.open(KIT_SHADER, FileAccess.WRITE)
	f.store_string(KIT_SHADER_CODE)
	f.close()


static func kit_material() -> ShaderMaterial:
	var src := load(KIT_SRC) as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = load(KIT_SHADER)
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("emit_tex", src.emission_texture)
	m.set_shader_parameter("roughness_v", src.roughness)
	m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	for k in ["k_dark", "k_mid", "k_light"]:
		m.set_shader_parameter(k, float(KIT_CLASS[k]))
	m.set_shader_parameter("band_dark", Vector2(KIT_CLASS["band_dark"][0], KIT_CLASS["band_dark"][1]))
	m.set_shader_parameter("band_light", Vector2(KIT_CLASS["band_light"][0], KIT_CLASS["band_light"][1]))
	m.resource_name = "V2_MachiyaKit_cal"
	return m


static func cal_materials() -> Array:
	var src := PackedStringArray()
	var mats: Array[Material] = []
	var keys := CAL.keys()
	keys.sort()
	for p in keys:
		var m := (load(p) as StandardMaterial3D).duplicate() as StandardMaterial3D
		var k := float(CAL[p])
		m.albedo_color = Color(k, k, k, 1.0)
		m.resource_name = String(p).get_file().get_basename() + "_cal"
		src.append(p)
		mats.append(m)
	src.append(KIT_SRC)
	mats.append(kit_material())
	return [src, mats]


## 調色盤變體材質：回傳 [mats, index]，index[area][mat_name][i] → mats 索引
static func palette_materials() -> Array:
	var mats: Array[Material] = []
	var index := {}
	var areas := PALETTE.keys()
	areas.sort()
	for a in areas:
		index[a] = {}
		for mn in ["V2_Plaster", "V2_Wood"]:
			index[a][mn] = []
			for c: Color in PALETTE[a][mn]:
				var m := (load(PALETTE_SRC[mn]) as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.albedo_color = Color(c.r, c.g, c.b, 1.0)
				m.resource_name = "%s_%s_v%d" % [mn, String(a).substr(0, 1), (index[a][mn] as Array).size()]
				index[a][mn].append(mats.size())
				mats.append(m)
	return [mats, index]


## 每棟挑 (plaster i, wood j)：起點＝名稱雜湊，與 14 m 內已指派鄰棟同組就往下輪
static func assign(v: Node3D, tg: Array) -> Array:
	var out := []
	var placed := []   # [pos, area, combo]
	for it in tg:
		var b := v.get_node(NodePath(String(it["path"]))) as Node3D
		var p := Vector2(b.global_position.x, b.global_position.z)
		var a := String(it["area"])
		var np: int = (PALETTE[a]["V2_Plaster"] as Array).size()
		var nw: int = (PALETTE[a]["V2_Wood"] as Array).size()
		var h := absi(String(it["path"]).get_file().hash())
		var combo := Vector2i(h % np, (h / 7) % nw)
		for tries in np * nw:
			var clash := false
			for q in placed:
				if String(q[1]) == a and (q[0] as Vector2).distance_to(p) < NEIGHBOR_M and q[2] == combo:
					clash = true
					break
			if not clash:
				break
			var flat := (combo.x * nw + combo.y + 1) % (np * nw)
			combo = Vector2i(flat / nw, flat % nw)
		placed.append([p, a, combo])
		out.append({"path": it["path"], "area": a, "plaster": combo.x, "wood": combo.y})
	return out


static func build(v: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = NODE_NAME
	n.set_script(load(SCRIPT))
	var t := targets(v)
	var paths := PackedStringArray()
	for it in t:
		paths.append(String(it["path"]))
	var cm := cal_materials()
	n.set("targets", paths)
	n.set("src_paths", cm[0])
	n.set("cal_mats", cm[1])
	var pm := palette_materials()
	n.set("variant_mats", pm[0])
	var tv := []
	for asg in assign(v, t):
		var idx: Dictionary = pm[1][asg["area"]]
		tv.append({PALETTE_SRC["V2_Plaster"]: int(idx["V2_Plaster"][int(asg["plaster"])]), PALETTE_SRC["V2_Wood"]: int(idx["V2_Wood"][int(asg["wood"])])})
	n.set("target_variants", tv)
	n.set_meta("art_revision", ART_REVISION)
	n.set_meta("phase", "P10 R6a pilot")
	n.set_meta("areas", JSON.stringify(AREAS.keys()))
	return n
