extends RefCounted
## P10 R5a Ground Pilot（使用者 2026-10-09 D3／D4）：道路外緣＋田格外溢的「可重現 pilot」。
## 根因（MASTER AUDIT R5a-01／02）：
##   ① P3 道路＝等寬直邊 ribbon（`gen_village_v2.gd _ribbon`），外緣是一條幾何直線＋材質斷層。
##   ② P7 `ground.gdshader` 93–104 行在 farm 權重 > 0.001 處畫 24×16 m 程序田格＝P7 時期替 P8 打的底色；
##      P8 每塊田都有自己的 WetMudBottom／畦網格（farm 權重 0），所以這張格只會在 P8 田外（路肩、田間、羽化帶）露出。
## Pilot 做法（不改任何封存檔、不重生 base）：
##   · shader：讀封存的 `ground.gdshader`（雜湊鎖定），以「文字補丁」產生 `shaders_p10/ground_p10_pilot.gdshader`：
##       a 田格段 → 不畫規則格；farm 權重只給不規則「田邊耕土」斑（farm_soil 強度，可調）
##       b 道路帶（mode 1）加外緣侵蝕：沿路低頻寬度起伏＋中頻草侵入，在路面高度畫成草（2026-10-18 起不再 discard；edge_* 可調，預設 0＝舊行為）
##       c 田埂道中央草帶改成斷續（center_patch 可調，0＝舊的連續草帶）
##   · overlay `GroundPilotP10`（gen/ground_pilot_p10.scn，root 掛 AlbedoPilotP10 之後）＝帶 script 的節點：_ready 時把
##     Terrain 4 段（田格修正）與 Pilot 道路（外緣侵蝕）的 material_override 換成 pilot shader 的複本；enabled=false 還原。
## ART_APPROVED 後：補丁併入 tools/build_village_v2_textures.py 的 ground shader 模板＋gen_village_v2.gd 的道路參數，
##   重生 ground.gdshader → _matlib Asset Gate／registry → 依實際影響 limited reseal（P9 R4／R4-2／R4-3／R5 依賴雜湊）。本 Pilot 不做。

const NODE_NAME := "GroundPilotP10"
const OUTPUT := "res://maps/village_v2/gen/ground_pilot_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/ground_pilot.gd"
const SRC_SHADER := "res://assets/village_v2/_matlib/ground/ground.gdshader"
const SRC_SHA256 := "SET_BY_GATE"
const OUT_SHADER := "res://maps/village_v2/shaders_p10/ground_p10_pilot.gdshader"
const ART_REVISION := "P10 R5a ground pilot ROUND 2 r4：再生道（UV2.y）の区間別の使われ方の段を追加（轍＝草なしの土の帯）、田埂道 1／4 の center_patch 1.0→0.35（梯子状の中央草）；r3：草舌沿路拉長＋切口內 0.4 m 混草（r2 近距缺口像印章、土草一刀切）；R6b 參道石段挖洞參數 cut_s／cut_hw（預設關）（ART_REVIEW）"

const TERRAIN := ["Terrain/MainTerrain", "Terrain/NorthHill", "Terrain/FarmlandTerrain", "Terrain/RiverTerrain"]
## 田邊耕土強度（farm 權重 × farm_soil → 踏み土＋少量泥，斑塊化；0＝farm 權重完全不影響地面）
const FARM_SOIL := 0.32
## Pilot 道路：町→田 的南橫街、田埂道 1／4（中央草帶裂縫）、河岸小徑（水岸）
## edge_w＝外緣侵蝕帶寬（m，0.25–1.20）、edge_irreg＝沿路寬度起伏（m，0.08–0.45）、center_patch＝中央草帶斷續化（0–1）
const ROADS := {
	"Roads/SecondaryRoads/CrossStreetSouth": {"edge_w": 0.55, "edge_irreg": 0.30, "center_patch": 0.0, "use": "town→farm"},
	"Roads/FarmPaths/FarmPath_1": {"edge_w": 0.40, "edge_irreg": 0.26, "center_patch": 0.35, "use": "farm"},   # ROUND 2：1.0 → 0.35（沿路 7 m 周期の中央草の途切れが梯子状に見えた）
	"Roads/FarmPaths/FarmPath_4": {"edge_w": 0.40, "edge_irreg": 0.26, "center_patch": 0.35, "use": "farm"},
	"Roads/SecondaryRoads/RiversidePath": {"edge_w": 0.60, "edge_irreg": 0.32, "center_patch": 0.0, "use": "waterfront"},
}
const EDGE_W_RANGE := [0.25, 1.20]
const EDGE_IRREG_RANGE := [0.08, 0.45]
## 路面核心不得被侵蝕：侵蝕深度上限＝半寬 × CORE_KEEP
const CORE_KEEP := 0.35

## 原 shader 中要被替換的兩段（逐字；找不到＝來源已變 → gate FAIL，不在變過的來源上打補丁）
const OLD_GRID := """		if (b.g > 0.001) {
			// 田（P7 底色；水面／稻作屬 P8）：田面＝草（秧苗綠）＋泥（高度混合落在低處），畦＝踏み固め土。
			// 畦寬 = bund_w（P2 灰模頂點色以 2 m 網格取樣，實際讀成約 2 m 寬帶）→ 這裡加寬 0.6 m、
			// 並讓畦幾乎全是土（草不再從畦中長出），俯視網格與灰模同等可讀（r3 俯視審圖：網格變弱）。
			vec2 q = mod(p - paddy.xy, paddy.zw);
			float bd = min(min(q.x, paddy.z - q.x), min(q.y, paddy.w - q.y));
			float bh = bund_w * 0.5 + 0.3;
			float bund = 1.0 - smoothstep(bh - 0.12, bh + 0.12, bd + (nf - 0.5) * 0.14);
			w[4] += b.g * (1.0 - bund) * 0.35;
			w[2] += b.g * bund * 1.6;
			wet = max(wet, b.g * (1.0 - bund) * 0.12);
		}"""
const NEW_GRID := """		if (b.g > 0.001) {
			// P10 R5a pilot：田格屬 P8（每塊田有自己的 WetMudBottom／畦）。地形 farm 權重只給不規則「田邊耕土」斑，
			// 不畫規則格（舊 24×16 m 程序田格在 P8 田外的路肩／田間／羽化帶露出＝第二套田格）。
			float fpatch = smoothstep(0.40, 0.72, nb.g * 0.65 + nm.r * 0.35);
			float fs = b.g * farm_soil;
			w[2] += fs * (0.35 + 0.65 * fpatch);
			w[4] += fs * 0.30 * fpatch * smoothstep(0.45, 0.8, nf);
			wet = max(wet, fs * 0.10 * fpatch);
		}"""
const OLD_ROAD_HEAD := """		float ax = abs(UV.x);
		float hw = max(UV2.x, 0.5);
		float xm = ax * hw;"""
const NEW_ROAD_HEAD := """		float ax = abs(UV.x);
		float hw = max(UV2.x, 0.5);
		float xm = ax * hw;
		// P10 R5a pilot：外緣侵蝕——沿路低頻寬度起伏（edge_irreg）＋沿路拉長的草舌（edge_w，取樣座標＝沿路 m／離緣 m）
		// ＋細鋸齒；深度上限＝半寬×edge_core；切口內 0.4 m 先混草（edge_soft），不是一刀從土切到草。
		if (cut_s.y > cut_s.x && UV.y > cut_s.x && UV.y < cut_s.y && xm < cut_hw) {
			discard;
		}
		// 2026-10-18 道路接觸修正：草舌不再 discard（discard 讓可見地面掉到下方 6–10 cm 的地形、與道路碰撞不符），
		// 改成在路面高度直接畫草（bite_in → 只剩草層）。外形、位置、雜訊與原本相同；cut_s 參道石段仍 discard（碰撞另行扣除）。
		bool bite_in = false;
		float edge_soft = 0.0;
		if (edge_w > 0.0 || edge_irreg > 0.0) {
			float from_edge = hw - xm;
			float n_lo = texture(noise_tex, p / 11.0 + vec2(0.13, 0.57)).r;
			float n_mid = texture(noise_tex, vec2(UV.y / 4.3, from_edge / 1.3) + vec2(0.71, 0.29 + sign(UV.x) * 0.37)).g;
			float bite = edge_irreg * smoothstep(0.30, 0.75, n_lo) + edge_w * (smoothstep(0.35, 0.80, n_mid) * 0.7 + (nf - 0.5) * 0.6);
			float cut = min(max(bite, 0.0), hw * edge_core);
			bite_in = from_edge < cut;
			edge_soft = bite_in ? 1.0 : 1.0 - smoothstep(0.0, 0.40, from_edge - cut);
		}"""
const OLD_GRAVEL := """		w[3] += edge_gravel * smoothstep(0.5, 0.95, ax) * smoothstep(0.45, 0.75, nf);"""
const NEW_GRAVEL := """		w[3] += edge_gravel * smoothstep(0.5, 0.95, ax) * smoothstep(0.45, 0.75, nf);
		w[0] += edge_soft * 0.9;"""
const OLD_CENTER := """		w[0] += center_grass * (1.0 - smoothstep(0.22, 0.42, xm + (nf - 0.5) * 0.2));"""
const NEW_CENTER := """		float cpat = mix(1.0, smoothstep(0.42, 0.66, texture(noise_tex, vec2(UV.y / 7.0, 0.37 + UV.x * 0.02)).b), center_patch);
		w[0] += center_grass * cpat * (1.0 - smoothstep(0.16 + 0.12 * cpat, 0.30 + 0.16 * cpat, xm + (nf - 0.5) * 0.2));"""
## P10 R5a ROUND 2：RoadBaseP10 が再生した道（UV2.y ≥ 1）だけ、区間ごとの使われ方 traffic＝UV2.y − 1 で轍・中央草・路肩の草・砂利を変える。
## 旧網格（全村の道）は UV2.y＝0 → この段は何もしない（見た目不変）。
const OLD_WEAR := """		rut += wear_center * (1.0 - smoothstep(0.25, 0.55, ax + (nm.b - 0.5) * 0.2)) * 0.5;"""
const NEW_WEAR := """		rut += wear_center * (1.0 - smoothstep(0.25, 0.55, ax + (nm.b - 0.5) * 0.2)) * 0.5;
		// P10 R5a ROUND 2：再生した道（RoadBaseP10、UV2.y ≥ 1）＝区間ごとの使われ方 traffic＝UV2.y − 1（0 田の奥 … 1 村の出入口）。
		// 旧網格は UV2.y＝0 → 何も変わらない。
		if (UV2.y > 0.5) {
			float traffic = clamp(UV2.y - 1.0, 0.0, 1.0);
			float rx = xm - hw * 0.45;
			float rk = exp(-rx * rx / 0.03);
			rut += traffic * 0.6 * rk;
			w[0] *= 1.0 - clamp(traffic * 1.5 * rk, 0.0, 0.9);
			w[0] += (1.0 - traffic) * 0.6 * (1.0 - smoothstep(0.10, 0.30 + 0.15 * (1.0 - traffic), xm + (nf - 0.5) * 0.25));
			w[0] += (1.0 - traffic) * 0.55 * smoothstep(0.55, 0.95, ax + (nm.g - 0.5) * 0.45);
			w[3] += traffic * 0.35 * smoothstep(0.6, 0.95, ax) * smoothstep(0.4, 0.7, nf);
		}"""
const OLD_UNIFORM := """uniform float bund_w = 1.2;"""
const NEW_UNIFORM := """uniform float bund_w = 1.2;
// P10 R5a pilot 參數（預設值＝不改變舊行為，除 farm_soil 外）
uniform float farm_soil = 0.32;
uniform float edge_w = 0.0;
uniform float edge_irreg = 0.0;
uniform float edge_core = 0.35;
uniform float center_patch = 0.0;
// P10 R6b：參道石段範圍挖掉 ribbon 中央（沿路 s 範圍＋半寬）；預設關閉
uniform vec2 cut_s = vec2(0.0);
uniform float cut_hw = 0.0;"""
const OLD_MODE_END := """	} else {
		vec4 a = use_vertex_weights ? COLOR : fix_a;"""
const NEW_MODE_END := """		if (bite_in) {
			for (int bi = 1; bi < 7; bi++) {
				w[bi] = 0.0;
			}
			w[0] = 1.0;
			rut = 0.0;
		}
	} else {
		vec4 a = use_vertex_weights ? COLOR : fix_a;"""
const OLD_HEADER := """// 人間之里 V2 P7 地面材質（Ground Material / Transition）。"""
const NEW_HEADER := """// 人間之里 V2 P10 R5a GROUND PILOT（由 tools/village_v2_ground_pilot_lib.gd 從封存 ground.gdshader 文字補丁產生，勿手改）。
// 補丁：田格段→田邊耕土斑、道路帶外緣侵蝕、田埂道中央草帶斷續化、ROUND 2 再生道（UV2.y ≥ 1）の区間別の使われ方。其餘逐字＝ground.gdshader。
// 人間之里 V2 P7 地面材質（Ground Material / Transition）。"""

const PATCHES := [[OLD_HEADER, NEW_HEADER], [OLD_UNIFORM, NEW_UNIFORM], [OLD_GRID, NEW_GRID], [OLD_ROAD_HEAD, NEW_ROAD_HEAD], [OLD_GRAVEL, NEW_GRAVEL], [OLD_CENTER, NEW_CENTER], [OLD_WEAR, NEW_WEAR], [OLD_MODE_END, NEW_MODE_END]]


## 回傳 [code, missing]：missing＝找不到的補丁段（非空＝來源已變）
static func make_shader_code(src: String) -> Array:
	var code := src
	var missing := []
	for pt in PATCHES:
		if code.count(pt[0]) != 1:
			missing.append(String(pt[0]).substr(0, 40))
			continue
		code = code.replace(pt[0], pt[1])
	return [code, missing]


static func write_shader() -> Dictionary:
	var src := FileAccess.get_file_as_string(SRC_SHADER)
	var r := make_shader_code(src)
	if not (r[1] as Array).is_empty():
		return {"ok": false, "missing": r[1]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_SHADER.get_base_dir()))
	var f := FileAccess.open(OUT_SHADER, FileAccess.WRITE)
	f.store_string(r[0])
	f.close()
	return {"ok": true, "src_sha256": FileAccess.get_sha256(SRC_SHADER), "out_sha256": FileAccess.get_sha256(OUT_SHADER)}


## CPU 版侵蝕深度（與 shader 同式，但雜訊改用 FastNoiseLite 近似）——只給 gate 估外緣統計用
static func bite_cpu(p: Vector2, hw: float, prm: Dictionary, n_lo: FastNoiseLite, n_mid: FastNoiseLite) -> float:
	var lo := 0.5 + 0.5 * n_lo.get_noise_2d(p.x, p.y)
	var mid := 0.5 + 0.5 * n_mid.get_noise_2d(p.x, p.y)
	var bite := float(prm["edge_irreg"]) * smoothstep(0.30, 0.75, lo) + float(prm["edge_w"]) * smoothstep(0.35, 0.80, mid) * 0.8
	return minf(maxf(bite, 0.0), hw * CORE_KEEP)


static func build() -> Node3D:
	var n := Node3D.new()
	n.name = NODE_NAME
	n.set_script(load(SCRIPT))
	n.set("pilot_shader", load(OUT_SHADER))
	n.set("terrain_paths", PackedStringArray(TERRAIN))
	n.set("farm_soil", FARM_SOIL)
	var rp := PackedStringArray()
	var prms: Array[Dictionary] = []
	var keys := ROADS.keys()
	keys.sort()
	for k in keys:
		rp.append(k)
		var d: Dictionary = ROADS[k]
		prms.append({"edge_w": d["edge_w"], "edge_irreg": d["edge_irreg"], "edge_core": CORE_KEEP, "center_patch": d["center_patch"]})
	n.set("road_paths", rp)
	n.set("road_params", prms)
	n.set_meta("art_revision", ART_REVISION)
	n.set_meta("phase", "P10 R5a pilot")
	return n
