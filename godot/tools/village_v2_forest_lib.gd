extends RefCounted
## 人間之里 V2 P9 R2 Forest Belts：林帶規劃（環境決定、非均勻散佈）＋烘焙（MultiMesh 分塊＋樹幹碰撞）＋天際線量測。
##
## 取代 P0 六塊林冠 placeholder（layout_v2.json forests；poly／circle 為凍結林帶範圍，本檔只在範圍內種樹）。
## ART-FIRST 順序：取代 placeholder → skyline → forest edge → canopy depth → understory → gaps。
##
## 規劃（plan）：
##   1. 2 m 格的林地遮罩＝林帶內 且 不在建成區（外框 +4 m）／農田（+3 m）／道路（半寬 +3 m）／主河（半寬 +7 m）／
##      水渠與溪（半寬 +3 m）／地標整平區（+6 m）／鳥居與龍神像（12 m）。到遮罩邊的距離 d_edge 用 BFS（林緣＝道路、建成區、農田、水邊都算）。
##   2. 環境場：海拔、坡度、離水距離、林緣距離、北丘位置（主峰／西肩／東次峰）、低頻雜訊（人工杉林斑塊、疏密、林隙）。
##   3. 林冠層：變半徑 dart throwing（候選＝2 m 格抖動、固定種子打亂）；樹種由環境權重決定（不是均勻亂數），
##      間距＝冠幅 × 疏密場；林隙場 > 門檻的內部不放林冠（光隙）；林緣 0–12 m 冠層矮化、變疏、外傾。
##   4. 檜（hinoki_a／b）＝secondary vegetation（使用者 2026-10-01 裁定）：只在林緣 ≥ 18 m 的中後層、不在北丘稜線上緣，
##      各林帶針葉內佔約 5–15 %。
##   5. 天際線：主峰（社殿四周）放高杉、東次峰換低闊葉／赤松並壓縮比例，讓東次峰約主峰 70–80 %（75 % 只是參考）。
##   6. 視線：主要村道 1.7 m 眼高望山頂社殿與參道鳥居的視線上，林冠會擋的樹拿掉（灌木留著）。
##   7. 下層：林緣 mantle（灌木、幼樹密）、林隙（幼樹／灌木多）、林下（少）；少量枯立木與倒木。
##
## 烘焙（bake）：32 m 分塊 × (樹種, 色彩變體) × LOD → MultiMeshInstance3D（每個實例在 shader 內各自用 MODEL_MATRIX×lod_ref
##   算換檔距離；已用探針驗證 Forward+／Compatibility 都是逐實例）。樹幹碰撞＝每分塊一個 StaticBody3D、每棵一個圓柱。
##   色彩變體走 instance uniform（leaf_tint／leaf_sat，R1 封存的 shader 不改），所以依低頻場分組＝成片的色調，不是逐棵雜訊。

const TreeLib := preload("res://tools/village_v2_veg_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const KIT := "res://assets/village_v2/veg_kit"
const MODULES := KIT + "/src/modules_blender.json"
const OUTPUT := "res://maps/village_v2/gen/forest_p9.scn"
const NODE_NAME := "ForestP9"
const PLACEHOLDERS := ["Forest_SouthW", "Forest_SouthE", "Forest_West", "Forest_NorthW", "Forest_NorthE", "Forest_HillCrown"]

const CELL := 2.0
## 近／遠分工（r2）：veg shader 的 LOD 換檔是逐像素 discard——MultiMesh 塊內每棵樹都會把「節點可見範圍涵蓋到的所有級」
##   完整跑 vertex＋光柵再丟掉。塊越大、級越近（面數越高）越浪費（r1 實測：高處俯瞰林帶多畫 10 M primitives）。
##   → 近級（LOD0／LOD1）每棵樹自己的節點（可見範圍＝prefab 的逐級範圍，零浪費；也可單獨選取）；
##     遠級（LOD2／LOD3）才進 MultiMesh 分塊（面數低、換檔遠，塊內浪費小）。
## 色彩變體按「64 m 林分 × 樹種」決定（一個林分一個色調，近／遠一致，不會換檔變色）。
## instance uniform 每個節點佔 16 格（vec4）：project.godot rendering/limits/global_shader_variables/buffer_size 需 ≥ 節點數 × 16。
const CHUNK := 64.0
const NEAR_LODS := 2
const CHUNK_BY_LOD := [0.0, 0.0, 48.0, 128.0, 128.0]
const MAX_NODES := 26000
const UNIFORM_BUFFER := 524288
const SEED := 9201
const EMBED := 0.08

## 排除距離（m）
const M_BUILT := 4.0
const M_FARM := 3.0
const M_ROAD := 3.0
const M_RIVER := 7.0
const M_CHANNEL := 3.0
const M_PAD := 6.0
const M_MARK := 12.0

## 北丘層級（r3：視角輪廓，取代 r2 的距離包絡——r2 每離丘心 1 m 樹梢上限降 1–1.6 m，比地形還陡，山腹整片種不下樹＝禿丘）。
## 由村內兩個南望機位（主街、入口）量：樹梢仰角 ≤ 目標輪廓 × 主峰目標仰角，且至少比地形稜線高 HIER_MIN_OVER_TERRAIN 度
## （稜線一定留得下一層樹，不會變禿）。目標輪廓（主峰＝1）：主峰 ±HIER_FLAT° 平頂、西凹／西肩／東鞍／東次峰，兩端 HIER_TAIL° 外遞減到
## HIER_TAIL_RATIO 後不再限制。主峰目標仰角＝丘心地面 + HIER_PEAK_TREE 的仰角。
const HIER_CAMS := [[Vector3(241, 2.91, 44), Vector3(276, 4.32, -70)], [Vector3(229, 2.7, 132), Vector3(240, 3.66, 40)],
	[Vector3(420, 2.1, 70), Vector3(300, 9.8, -150)]]   # r8：加農田望北丘（東次峰／西肩不得與主峰齊平）
const HIER_PEAK_TREE := 28.0
const HIER_RATIO := {"西凹": 0.58, "西肩": 0.70, "東鞍": 0.62, "東次峰": 0.75}
const HIER_FLAT := 2.2
const HIER_TAIL := 24.0
const HIER_TAIL_RATIO := 0.35
const HIER_MIN_OVER_TERRAIN := 0.8

## 林分結構（r3）：草地（林帶內大片開闊）、林緣灣（林緣大幅後退）、林帶外坡地植被
const STAND_OPEN := 0.30          # 林分場 < 此值＝林內草地（北丘鎮守林除外）
const STAND_THIN := 0.08          # 草地門檻 + 此值以內＝草地邊的疏林帶
## 西林是一整條長帶（120 m × 400 m）：草地比例拉高，讓它斷成幾個林分
const STAND_OPEN_BY := {"Forest_West": 0.38, "Forest_SouthW": 0.33}
const OPEN_BELTS := ["Forest_West", "Forest_SouthW", "Forest_SouthE", "Forest_NorthW", "Forest_NorthE"]
const SLOPE_MIN_DEG := 7.0        # 林帶外：坡度 ≥ 此值才當坡地植被候選（平地只在林帶外緣 SLOPE_FEATHER m 內）
const SLOPE_FEATHER := 22.0
const SLOPE_NEAR_VILLAGE := 28.0  # 離建成區 < 此值＝近村坡面（只放灌木、幼樹、小闊葉，疏）
const PORTAL_CLEAR := 10.0
## 西林橫斷草地（r4）：西林 120 m × 400 m 一整條 → 3 條橫切全寬的草地／灣，把它分成幾個林分（[z 中心, 半寬]；邊緣用雜訊抖）
const WEST_CUTS := [[-150.0, 20.0], [-30.0, 17.0], [80.0, 22.0]]
## 參道並木（r4）：HillApproach 兩側 PATH_ROW m 內允許林冠貼路（杉並木＋椎欅），不走林緣退縮
const PATH_ROW := 9.0
## 山頂鎮守の森背景（r4）：社殿 pad 北側（背對村子）的御神木杉群
const SUMMIT_HERO_N := 6
## 社殿背景天窗（r6）：從這些機位看社殿，社殿正後方 ±BACK_WIN° 內的樹梢不得高過社殿屋頂（屋頂剪影對天空）；
## 御神木杉排在天窗兩側 BACK_WIN–BACK_FLANK° 夾住社殿（主峰最高的杉冠＝社殿兩側）
const BACK_CAMS := [Vector3(241, 2.91, 44), Vector3(229, 2.7, 132), Vector3(296, 3.23, -150), Vector3(250, 2.4, -150)]
const BACK_WIN := 3.0
const BACK_FLANK := 16.0
## 樹梢上限抖動（r6）：碰到層級上限的樹不再全部剛好縮到上限（那會長成平頂樹籬／梳齒），改取上限 × U(CAP_JITTER, 1)
const CAP_JITTER := 0.74

## 檜規則
const HINOKI := ["hinoki_a", "hinoki_b"]
const HINOKI_MIN_EDGE := 18.0
const CONIFERS := ["sugi_a", "sugi_b", "sugi_c", "hinoki_a", "hinoki_b", "akamatsu_a", "akamatsu_b", "kuromatsu_a"]

## 林帶性格：林冠層樹種基本權重（環境再乘倍率）
const BELT_MIX := {
	# 北丘＝鎮守の森：杉主體、檜少量混在中後層、椎／欅老闊葉、稜線赤松、上坡零星山櫻
	"Forest_HillCrown": {"sugi_a": 30, "sugi_c": 16, "sugi_b": 6, "hinoki_a": 9, "hinoki_b": 7, "shii_a": 12, "keyaki_a": 6,
		"akamatsu_a": 6, "akamatsu_b": 5, "sakura_yama": 4, "momiji_b": 3, "konara_a": 5},
	# 北山林：針闊混交、赤松稜線、杉人工林斑塊
	"Forest_NorthW": {"sugi_a": 18, "sugi_c": 14, "hinoki_a": 5, "hinoki_b": 4, "akamatsu_a": 9, "akamatsu_b": 8, "konara_a": 14,
		"konara_b": 8, "shii_a": 9, "keyaki_a": 5, "enoki_a": 4, "sakura_yama": 5, "momiji_b": 4, "momiji_a": 2},
	"Forest_NorthE": {"sugi_a": 14, "sugi_c": 12, "hinoki_a": 4, "hinoki_b": 3, "akamatsu_a": 10, "akamatsu_b": 9, "konara_a": 15,
		"konara_b": 9, "shii_a": 8, "keyaki_a": 6, "enoki_a": 6, "sakura_yama": 5, "momiji_b": 4, "momiji_c": 2},
	# 西林：里山雑木林（R3 會把一部分改竹林）；杉植林斑塊
	"Forest_West": {"konara_a": 22, "konara_b": 12, "enoki_a": 10, "shii_a": 11, "keyaki_a": 7, "momiji_b": 6, "momiji_c": 3,
		"sakura_yama": 5, "sugi_c": 12, "sugi_a": 6, "akamatsu_a": 3, "hinoki_a": 3, "hinoki_b": 2},
	# 南林：入口與河邊的明亮雑木林
	"Forest_SouthW": {"konara_a": 18, "konara_b": 10, "keyaki_a": 12, "enoki_a": 12, "shii_a": 8, "sakura_yama": 7, "momiji_b": 6,
		"momiji_c": 3, "sugi_a": 8, "sugi_c": 10, "akamatsu_a": 3, "hinoki_a": 2, "hinoki_b": 3},
	"Forest_SouthE": {"konara_a": 18, "konara_b": 10, "keyaki_a": 11, "enoki_a": 13, "shii_a": 8, "sakura_yama": 6, "momiji_b": 6,
		"sugi_a": 8, "sugi_c": 10, "akamatsu_a": 3, "hinoki_a": 3, "hinoki_b": 2, "yanagi_a": 3},
}
## 林緣（0–12 m）偏好：小中型闊葉、楓、山櫻、幼樹；杉少（避免林緣杉牆）
const EDGE_MIX := {"konara_b": 14, "momiji_b": 9, "momiji_a": 6, "momiji_c": 6, "sakura_yama": 7, "enoki_a": 8, "young_broad_a": 14,
	"young_broad_b": 12, "young_sugi": 6, "konara_a": 8, "sugi_c": 4, "akamatsu_b": 3}
## 次林層（林冠下、樹冠間隙：中後景深度）
const SUB_MIX := {"momiji_b": 10, "momiji_a": 7, "momiji_c": 7, "konara_b": 12, "young_broad_a": 12, "young_broad_b": 10,
	"young_sugi": 8, "sakura_yama": 3, "enoki_a": 3}
## 林帶外坡地（里山的雑木と赤松；陡坡、稜線赤松；不放檜）
const SLOPE_MIX := {"konara_a": 16, "konara_b": 14, "akamatsu_a": 7, "akamatsu_b": 7, "sakura_yama": 6, "momiji_b": 6, "enoki_a": 5,
	"young_broad_a": 10, "young_broad_b": 8, "young_sugi": 4, "sugi_c": 3, "keyaki_a": 4, "shii_a": 4}
## 近村坡面：灌木、幼樹、小闊葉
const VILLAGE_SLOPE_MIX := {"young_broad_a": 16, "young_broad_b": 14, "momiji_a": 8, "momiji_c": 6, "sakura_yama": 4, "konara_b": 6,
	"young_sugi": 3}
## 下層
const UNDER_MIX := {"shrub_a": 30, "tsutsuji_a": 14, "sasa_a": 18, "fern_a": 16, "young_broad_a": 8, "young_broad_b": 6, "young_sugi": 8}
const SHADE_MIX := {"fern_a": 30, "sasa_a": 22, "shrub_a": 14, "young_sugi": 8, "young_broad_b": 6}
const NO_SHADOW := ["shrub_a", "tsutsuji_a", "sasa_a", "fern_a"]
const UNDER_IDS := ["shrub_a", "tsutsuji_a", "sasa_a", "fern_a"]
const YOUNG_IDS := ["young_sugi", "young_broad_a", "young_broad_b"]

## 色彩變體分組（低頻場決定，成片色調）
const PRESET_BY_GROUP := {
	"conifer": ["mature", "deep", "shade", "young"],
	"broad": ["mature", "young", "deep", "yellow"],
	"matsu": ["mature", "deep", "young"],
	"sakura": ["muted", "mature"],
	"momiji": ["muted", "mature", "deep"],
	"yanagi": ["mature", "young"],
	"young": ["young", "mature"],
	"under": ["mature", "deep", "young"],
	"dead": ["mature"],
}


# ─────────────────────────── 基礎 ───────────────────────────

static func modules() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODULES))
	return (m as Dictionary)["trees"] if m is Dictionary else {}


static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	return n


static func _n01(n: FastNoiseLite, x: float, z: float) -> float:
	return clampf(n.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)


## 折線最近點：回傳 Vector3(距離, 段索引, 段內 t)
static func _near(pts: PackedVector2Array, p: Vector2) -> Vector3:
	var best := Vector3(INF, 0, 0)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			best = Vector3(d, i, t)
	return best


static func _pick(rng: RandomNumberGenerator, w: Dictionary) -> String:
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	if tot <= 0.0:
		return ""
	var r := rng.randf() * tot
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return String(w.keys()[-1])


# ─────────────────────────── 林地遮罩 ───────────────────────────

class Ctx:
	var L: Dictionary
	var S: RLib.TriSampler
	var belts: Array[String] = []
	var belt_poly := {}
	var outlines: Array
	var farm: PackedVector2Array
	var roads: Array = []        # [pts, hw]
	var river: PackedVector2Array
	var river_hw: PackedFloat32Array
	var channels: Array = []     # [pts, hw]
	var pads: Array = []         # [Vector2, r]
	var marks: Array = []        # Vector2
	var x0 := 0.0
	var z0 := 0.0
	var nx := 0
	var nz := 0
	var belt_of := PackedInt32Array()    # 每格所屬林帶索引（-1＝非林地）
	var edge := PackedFloat32Array()     # 到林地外的距離（m）
	var hgt := PackedFloat32Array()      # 地面高（NAN＝無地形）
	var hill_c := Vector2.ZERO
	var lobes := {}
	var peak_y := 0.0
	var lobe_y := {}
	var portals: Array = []      # Vector2
	var hier: Array = []         # 視角層級輪廓（見 HIER_*）
	var dbelt := PackedFloat32Array()   # 林帶外：到最近林帶格的距離（m）


static func context(v: Node3D, L: Dictionary) -> Ctx:
	var C := Ctx.new()
	C.L = L
	C.S = RLib.terrain_sampler(v)
	var F: Dictionary = L["forests"]
	for k in F:
		if typeof(F[k]) == TYPE_DICTIONARY:
			C.belts.append(String(k))
			if (F[k] as Dictionary).has("poly"):
				C.belt_poly[k] = TLib.pts(F[k]["poly"])
	C.outlines = TLib.built_outlines(L)
	C.farm = TLib.pts(L["districts"]["Farmland"]["poly"])
	var VW: Dictionary = L.get("variants", {}).get("main_street_width", {})
	for r: Dictionary in L["roads"]:
		var hw := float(r["half_w"])
		if not VW.is_empty() and String(r["name"]) == String(VW["road"]):
			hw = float(VW["options"][String(VW["selected"])]["half_w"])
		C.roads.append([TLib.pts(r["pts"]), hw])
	var W: Dictionary = L["water"]
	C.river = TLib.pts(W["MainRiver"]["pts"])
	C.river_hw = PackedFloat32Array(W["MainRiver"]["half_w"])
	C.channels.append([TLib.pts(W["Canal"]["pts"]), float(W["Canal"]["half_w"])])
	for s: Dictionary in W["Streams"]:
		C.channels.append([TLib.pts(s["pts"]), float(s["half_w"])])
	for pd: Array in TLib.pads(L):
		C.pads.append([pd[0], float(pd[1])])
	for lm: Dictionary in L["landmarks"]:
		if String(lm["type"]) in ["torii", "dragon"]:
			C.marks.append(Vector2(float(lm["at"][0]), float(lm["at"][1])))
	for pt: Dictionary in L.get("portals", []):
		C.portals.append(Vector2(float(pt["at"][0]), float(pt["at"][1])))
	if L.has("spawn"):
		C.portals.append(Vector2(float(L["spawn"]["at"][0]), float(L["spawn"]["at"][1])))
	var H: Dictionary = L["hill"]
	C.hill_c = Vector2(float(H["center"][0]), float(H["center"][1]))
	for lb: Dictionary in H.get("lobes", []):
		C.lobes[String(lb["label"])] = Vector3(float(lb["center"][0]), float(lb["center"][1]), float(lb["radius"]))
	C.peak_y = C.S.h(C.hill_c.x, C.hill_c.y)
	for k in C.lobes:
		var lc: Vector3 = C.lobes[k]
		C.lobe_y[k] = C.S.h(lc.x, lc.y)
	var FR: Dictionary = L["frame"]
	C.x0 = float(FR["x0"])
	C.z0 = float(FR["z0"])
	C.nx = int((float(FR["x1"]) - C.x0) / CELL)
	C.nz = int((float(FR["z1"]) - C.z0) / CELL)
	_mask(C)
	_hier(C)
	return C


static func _az(cam: Vector3, base: float, q: Vector2) -> float:
	var rel := q - Vector2(cam.x, cam.z)
	return -rad_to_deg(wrapf(atan2(rel.y, rel.x) - base, -PI, PI))


## 視角層級輪廓：每個機位一份（地形稜線仰角＋目標輪廓節點）
static func _hier(C: Ctx) -> void:
	C.hier.clear()
	if not (C.lobes.has("西肩") and C.lobes.has("東次峰")):
		return
	for hc: Array in HIER_CAMS:
		var cam: Vector3 = hc[0]
		var prof := skyline(C, [], cam, hc[1], 75.0, 0.25)
		var base: float = prof["base"]
		# 相對主峰的方位 u（東次峰那側為正；_az 右轉為負，所以要依實際方位定號）
		var ap := _az(cam, base, C.hill_c)
		var sg := signf(_az(cam, base, Vector2(C.lobes["東次峰"].x, C.lobes["東次峰"].y)) - ap)
		var uw := (_az(cam, base, Vector2(C.lobes["西肩"].x, C.lobes["西肩"].y)) - ap) * sg
		var ue := (_az(cam, base, Vector2(C.lobes["東次峰"].x, C.lobes["東次峰"].y)) - ap) * sg
		var kn: Array = [Vector2(uw - HIER_TAIL, HIER_TAIL_RATIO), Vector2(uw, HIER_RATIO["西肩"]),
			Vector2((uw - HIER_FLAT) * 0.5, HIER_RATIO["西凹"]), Vector2(-HIER_FLAT, 1.0), Vector2(HIER_FLAT, 1.0),
			Vector2((HIER_FLAT + ue) * 0.5, HIER_RATIO["東鞍"]), Vector2(ue, HIER_RATIO["東次峰"]),
			Vector2(ue + HIER_TAIL, HIER_TAIL_RATIO)]
		var mono: Array = [kn[0]]
		for k in range(1, kn.size()):
			if (kn[k] as Vector2).x > (mono[-1] as Vector2).x + 0.05:
				mono.append(kn[k])
		var dp := Vector2(cam.x, cam.z).distance_to(C.hill_c)
		C.hier.append({"cam": cam, "base": base, "ap": ap, "sg": sg, "knots": mono, "ter": prof["terrain"], "az0": -75.0, "step": 0.25,
			"e_peak": rad_to_deg(atan2(C.peak_y + HIER_PEAK_TREE - cam.y, dp))})


## 視角層級：該點樹梢允許的絕對高度（不在任何機位的北丘方位窗內＝INF）
static func hier_cap(C: Ctx, p: Vector2) -> float:
	var cap := INF
	for H: Dictionary in C.hier:
		var cam: Vector3 = H["cam"]
		var dist := p.distance_to(Vector2(cam.x, cam.z))
		if dist < 30.0:
			continue
		var a := _az(cam, float(H["base"]), p)
		var u := (a - float(H["ap"])) * float(H["sg"])
		var kn: Array = H["knots"]
		if u <= (kn[0] as Vector2).x or u >= (kn[-1] as Vector2).x:
			continue
		var r := HIER_TAIL_RATIO
		for k in kn.size() - 1:
			var k0: Vector2 = kn[k]
			var k1: Vector2 = kn[k + 1]
			if u >= k0.x and u <= k1.x:
				r = lerpf(k0.y, k1.y, (u - k0.x) / maxf(k1.x - k0.x, 1e-4))
				break
		var ter: PackedFloat32Array = H["ter"]
		var ki := clampi(int(round((a - float(H["az0"])) / float(H["step"]))), 0, ter.size() - 1)
		var deg := maxf(r * float(H["e_peak"]), ter[ki] + HIER_MIN_OVER_TERRAIN)
		cap = minf(cap, cam.y + tan(deg_to_rad(deg)) * dist)
	return cap


static func in_belt(C: Ctx, name: String, p: Vector2) -> bool:
	var d: Dictionary = C.L["forests"][name]
	if d.has("circle"):
		var c: Array = d["circle"]
		return p.distance_to(Vector2(float(c[0]), float(c[1]))) < float(c[2])
	return Geometry2D.is_point_in_polygon(p, C.belt_poly[name])


## 林地准入（與 gen_village_v2.gd _forest_ok 同一組禁區，距離改為植樹用的淨距）。回傳空字串＝可種；否則為擋住的原因。
static func blocked(C: Ctx, p: Vector2) -> String:
	if TLib.outline_sd(C.outlines, p) > -M_BUILT:
		return "built"
	if Geometry2D.is_point_in_polygon(p, C.farm) or _poly_d(C.farm, p) < M_FARM:
		return "farm"
	for r: Array in C.roads:
		if TLib.polyline_d(r[0], p) < float(r[1]) + M_ROAD:
			return "road"
	var rr := _near(C.river, p)
	var i := int(rr.y)
	var hw := lerpf(C.river_hw[i], C.river_hw[mini(i + 1, C.river_hw.size() - 1)], rr.z)
	if rr.x < hw + M_RIVER:
		return "river"
	for ch: Array in C.channels:
		if TLib.polyline_d(ch[0], p) < float(ch[1]) + M_CHANNEL:
			return "channel"
	for pd: Array in C.pads:
		if p.distance_to(pd[0]) < float(pd[1]) + M_PAD:
			return "pad"
	for m: Vector2 in C.marks:
		if p.distance_to(m) < M_MARK:
			return "landmark"
	for m: Vector2 in C.portals:
		if p.distance_to(m) < PORTAL_CLEAR:
			return "portal"
	return ""


static func _poly_d(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func cell_p(C: Ctx, i: int, j: int) -> Vector2:
	return Vector2(C.x0 + (i + 0.5) * CELL, C.z0 + (j + 0.5) * CELL)


static func _mask(C: Ctx) -> void:
	var n := C.nx * C.nz
	C.belt_of.resize(n)
	C.belt_of.fill(-1)
	C.edge.resize(n)
	C.edge.fill(1e9)
	C.hgt.resize(n)
	C.hgt.fill(NAN)
	for j in C.nz:
		for i in C.nx:
			var p := cell_p(C, i, j)
			for b in C.belts.size():
				if in_belt(C, C.belts[b], p):
					if blocked(C, p) == "":
						var h := C.S.h(p.x, p.y)
						if not is_nan(h):
							C.belt_of[j * C.nx + i] = b
							C.hgt[j * C.nx + i] = h
					break
	# 林緣距離：兩趟 chamfer（3-4）近似歐氏距離
	for j in C.nz:
		for i in C.nx:
			if C.belt_of[j * C.nx + i] < 0:
				C.edge[j * C.nx + i] = 0.0
	for pass_i in 2:
		var jr: Array = range(C.nz) if pass_i == 0 else range(C.nz - 1, -1, -1)
		var ir: Array = range(C.nx) if pass_i == 0 else range(C.nx - 1, -1, -1)
		var s := -1 if pass_i == 0 else 1
		for j: int in jr:
			for i: int in ir:
				var k := j * C.nx + i
				var e := C.edge[k]
				if e == 0.0:
					continue
				for d: Array in [[s, 0, 1.0], [0, s, 1.0], [s, s, 1.4142], [-s, s, 1.4142]]:
					var ii: int = i + int(d[0])
					var jj: int = j + int(d[1])
					var en := 0.0 if (ii < 0 or jj < 0 or ii >= C.nx or jj >= C.nz) else C.edge[jj * C.nx + ii]
					e = minf(e, en + float(d[2]) * CELL)
				C.edge[k] = e
	# 林帶外：到最近林帶格的距離（同法，種子＝林帶格）
	C.dbelt.resize(n)
	C.dbelt.fill(1e9)
	for k in n:
		if C.belt_of[k] >= 0:
			C.dbelt[k] = 0.0
	for pass_i in 2:
		var jr: Array = range(C.nz) if pass_i == 0 else range(C.nz - 1, -1, -1)
		var ir: Array = range(C.nx) if pass_i == 0 else range(C.nx - 1, -1, -1)
		var s := -1 if pass_i == 0 else 1
		for j: int in jr:
			for i: int in ir:
				var k := j * C.nx + i
				var e := C.dbelt[k]
				if e == 0.0:
					continue
				for d: Array in [[s, 0, 1.0], [0, s, 1.0], [s, s, 1.4142], [-s, s, 1.4142]]:
					var ii: int = i + int(d[0])
					var jj: int = j + int(d[1])
					if ii < 0 or jj < 0 or ii >= C.nx or jj >= C.nz:
						continue
					e = minf(e, C.dbelt[jj * C.nx + ii] + float(d[2]) * CELL)
				C.dbelt[k] = e


static func edge_at(C: Ctx, p: Vector2) -> float:
	var i := int(floor((p.x - C.x0) / CELL))
	var j := int(floor((p.y - C.z0) / CELL))
	if i < 0 or j < 0 or i >= C.nx or j >= C.nz:
		return 0.0
	return C.edge[j * C.nx + i]


static func belt_at(C: Ctx, p: Vector2) -> int:
	var i := int(floor((p.x - C.x0) / CELL))
	var j := int(floor((p.y - C.z0) / CELL))
	if i < 0 or j < 0 or i >= C.nx or j >= C.nz:
		return -1
	return C.belt_of[j * C.nx + i]


## 接地：根盤環 8 點地面最低值（半徑夾在 0.15–1.0 m）－少量埋入
static func ground(C: Ctx, p: Vector2, rr: float) -> float:
	var y := C.S.h(p.x, p.y)
	if is_nan(y):
		return NAN
	for k in 8:
		var a := k * TAU / 8.0
		var h := C.S.h(p.x + cos(a) * rr, p.y + sin(a) * rr)
		if not is_nan(h):
			y = minf(y, h)
	return y - EMBED


static func slope_deg(C: Ctx, p: Vector2) -> float:
	var d := 1.5
	var hx := C.S.h(p.x + d, p.y) - C.S.h(p.x - d, p.y)
	var hz := C.S.h(p.x, p.y + d) - C.S.h(p.x, p.y - d)
	if is_nan(hx) or is_nan(hz):
		return 90.0
	return rad_to_deg(atan(Vector2(hx, hz).length() / (2.0 * d)))


# ─────────────────────────── 規劃 ───────────────────────────

## opts：{"targets": [[名稱, Vector3 目標點], ...], "stations": PackedVector3Array 視點,
##        "approach": PackedVector3Array 參道視點（只對第一個目標＝山頂社殿）}
static func plan(v: Node3D, L: Dictionary, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := context(v, L)
	var M := modules()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var n_plant := _noise(SEED + 1, 1.0 / 70.0)     # 杉植林斑塊
	var n_dens := _noise(SEED + 2, 1.0 / 60.0)      # 疏密（大片的密林／疏林）
	var n_gap := _noise(SEED + 3, 1.0 / 38.0)       # 林隙
	var n_tone := _noise(SEED + 4, 1.0 / 55.0)      # 色調
	var n_edge := _noise(SEED + 5, 1.0 / 18.0)      # 林緣起伏
	var n_age := _noise(SEED + 6, 1.0 / 30.0)       # 林齡（樹高）
	var n_clump := _noise(SEED + 7, 1.0 / 14.0)     # 樹叢（成群／稀疏）
	var n_stand := _noise(SEED + 8, 1.0 / 85.0)     # 林分（林內草地／疏林）
	var n_bay := _noise(SEED + 9, 1.0 / 48.0)       # 林緣灣（林緣大幅後退）
	var n_open := _noise(SEED + 10, 1.0 / 50.0)     # 林帶外坡地：草坡／雑木
	var n_sakura := _noise(SEED + 11, 1.0 / 40.0)   # 山櫻群落（小斑塊＝3–7 棵一叢）
	var n_cut := _noise(SEED + 12, 1.0 / 26.0)      # 橫斷草地邊緣抖動
	var shrine_t := Vector3.ZERO
	var tg0: Array = opts.get("targets", [])
	if not tg0.is_empty():
		shrine_t = tg0[0][1]
	var approach_pts := PackedVector2Array()
	for r: Dictionary in L["roads"]:
		if String(r["name"]) == "HillApproach":
			approach_pts = TLib.pts(r["pts"])
	var mask_ms := Time.get_ticks_msec() - t0
	# 各林帶海拔範圍（稜線判定用）
	var hmax := {}
	for k in C.nx * C.nz:
		var b := C.belt_of[k]
		if b >= 0:
			hmax[b] = maxf(float(hmax.get(b, -INF)), C.hgt[k])
	# 候選：每格一個抖動點，固定種子打亂
	var cand: Array = []
	for j in C.nz:
		for i in C.nx:
			if C.belt_of[j * C.nx + i] >= 0:
				cand.append(Vector2i(i, j))
	_shuffle(rng, cand)
	var items: Array = []
	var grid := {}          # Vector2i(8 m 格) → [item 索引]
	var dropped := {"sightline": 0, "slope": 0, "ground": 0, "sky": 0, "meadow": 0}
	var east: Vector3 = C.lobes.get("東次峰", Vector3(307, -241, 44))
	var westsh: Vector3 = C.lobes.get("西肩", Vector3(213, -280, 41))
	# ── 林冠層（含林內草地的零星孤立木）
	for c: Vector2i in cand:
		var p := cell_p(C, c.x, c.y) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		var b := belt_at(C, p)
		if b < 0:
			continue
		var belt := C.belts[b]
		var de := edge_at(C, p)
		var h := C.S.h(p.x, p.y)
		if is_nan(h):
			continue
		var summit := p.distance_to(C.hill_c) < 40.0
		var path_row := not approach_pts.is_empty() and TLib.polyline_d(approach_pts, p) < PATH_ROW + 2.5
		# 北丘：面村（南／西南）＝鎮守の森，不打林隙、不疏化；東側外圈（離丘心 > 46 m）＝里山 mosaic（有草地）
		var hdir := (p - C.hill_c).normalized()
		var hill_front := belt == "Forest_HillCrown" and hdir.y > 0.15
		var hill_east := belt == "Forest_HillCrown" and hdir.x > 0.35 and p.distance_to(C.hill_c) > 46.0
		# 林分：林內草地（北丘鎮守林除外）＝不放林冠，只留極少孤立木；草地邊疏林
		var stand := _n01(n_stand, p.x, p.y)
		var so := 0.30 if hill_east else _open_th(belt)
		var meadow := stand < so or _west_cut(belt, p, n_cut) > 0.0
		if meadow and rng.randf() > 0.05:
			dropped["meadow"] += 1
			continue
		if stand < so + STAND_THIN and not meadow and rng.randf() > 0.45:
			continue
		# 林緣起伏＋林緣灣：有效林緣 2–7 m（灣處最多再退 16 m）內不放林冠（mantle 灌木與幼樹接手）
		var bay := smoothstep(0.55, 0.85, _n01(n_bay, p.x, p.y)) if belt in OPEN_BELTS else 0.0
		var e_off := 2.0 + 5.0 * _n01(n_edge, p.x, p.y) + 16.0 * bay
		if path_row:
			e_off = 0.8                                     # 參道並木：貼著路肩
		if de < e_off and not meadow:
			continue
		# 林隙（內部光隙）
		var gap := _n01(n_gap, p.x, p.y)
		if de > 16.0 and gap > 0.74 and not summit and not hill_front:
			continue
		var sl := slope_deg(C, p)
		if sl > 48.0:
			dropped["slope"] += 1
			continue
		var w: Dictionary = (BELT_MIX[belt] as Dictionary).duplicate()
		var is_edge := (de < 12.0 or meadow) and not summit and not path_row
		if is_edge:
			w = EDGE_MIX.duplicate()
		var rel_h := h / maxf(float(hmax.get(b, 1.0)), 1.0)
		# 北丘：相對丘頂的海拔（0＝丘腳、1＝社殿）
		var hill_e := clampf(h / maxf(C.peak_y, 1.0), 0.0, 1.0) if belt == "Forest_HillCrown" else -1.0
		var hill_d := p.distance_to(C.hill_c)
		var on_east := Vector2(east.x, east.y).distance_to(p) < east.z * 0.9
		var on_west := Vector2(westsh.x, westsh.y).distance_to(p) < westsh.z * 0.8
		var near_water := _near(C.river, p).x < 30.0
		var plant := _n01(n_plant, p.x, p.y)
		var sakura_ok := _n01(n_sakura, p.x, p.y) > 0.75
		if path_row and not summit:
			w = {"sugi_a": 30, "sugi_b": 18, "shii_a": 10, "keyaki_a": 8, "sugi_c": 6, "momiji_b": 4}
		for k: String in w.keys():
			var f := 1.0
			if k.begins_with("sakura"):
				f *= 60.0 if sakura_ok else 0.0            # 山櫻：成叢（群落場內），不是灑在每個林分
			if k.begins_with("sugi") and plant > 0.58 and not is_edge:
				f *= 3.2                                  # 杉植林斑塊
			if k.begins_with("akamatsu") and (rel_h > 0.75 or sl > 30.0):
				f *= 2.5                                  # 稜線／陡坡赤松
			if (k == "yanagi_a" or k == "enoki_a") and near_water:
				f *= 2.5
			if k in HINOKI and plant > 0.58 and not is_edge:
				f *= 1.8                                  # 杉檜混植斑塊
			if k in HINOKI and (de < HINOKI_MIN_EDGE or h > float(hmax.get(b, 0.0)) - 5.0):
				f = 0.0                                   # 檜：只在中後層、不上稜線頂帶
			if on_east and k in HINOKI:
				f *= 0.15                                 # 東次峰：檜不上（secondary）
			if on_east and k.begins_with("sugi") and not path_row:
				f *= 1.6                                  # 東次峰＝參道鳥居稜：主街北望軸線正對這裡（主峰被屋頂擋住），要一叢杉冠收尾
			if hill_e >= 0.0 and hill_e < 0.45 and not path_row:
				# 丘腳：闊葉、楓、小楢為主（矮），杉少；上坡才是杉
				f *= 0.35 if (k.begins_with("sugi") or k in HINOKI) else 1.4
			if hill_d < 34.0:
				# 社殿背後的鎮守の森：老杉（sugi_a／b）成主峰冠頂，少量椎／欅老樹
				f *= 7.0 if k in ["sugi_a", "sugi_b"] else (0.6 if k in ["shii_a", "keyaki_a"] else 0.15)
			elif hill_d < 48.0 and k.begins_with("sugi") and not on_east:
				f *= 3.0                                  # 主峰社殿四周：高杉（鎮守の森）
			w[k] = float(w[k]) * f
		var allow := minf(hier_cap(C, p), back_cap(p, shrine_t)) - h
		if allow < 6.0:
			dropped["sky"] += 1
			continue
		for k: String in w.keys():
			if M.has(k) and float(M[k]["height"]) * 0.72 > allow:
				w[k] = 0.0
		var tid := _pick(rng, w)
		if tid == "" or not M.has(tid):
			continue
		var info: Dictionary = M[tid]
		# 樹高：林齡場＋個體差；林緣矮化；東次峰／西肩壓縮
		var age := _n01(n_age, p.x, p.y)
		var sc := lerpf(0.82, 1.1, age) * rng.randf_range(0.92, 1.08)
		if is_edge and not meadow:
			sc *= lerpf(0.72, 0.95, clampf((de - e_off) / 10.0, 0.0, 1.0))
		if hill_e >= 0.0 and not summit and not path_row:
			sc *= lerpf(0.70, 1.04, smoothstep(0.15, 0.85, hill_e))   # 林冠高度隨海拔遞增
		if on_west:
			sc *= 0.92
		elif hill_d < 34.0 and tid.begins_with("sugi"):
			sc = maxf(sc, 1.05) * 1.12
		elif hill_d < 48.0 and tid.begins_with("sugi"):
			sc = maxf(sc, 1.0) * 1.05
		if sc * float(info["height"]) > allow:
			sc = allow / float(info["height"]) * rng.randf_range(CAP_JITTER, 1.0)   # 不長成平頂樹籬
		if sc < 0.66:
			continue
		var d01 := _n01(n_dens, p.x, p.y)
		# 疏林區：只收一部分候選（密度場要真的有落差，不是全區一樣滿）
		if not summit and not meadow and not path_row and rng.randf() > lerpf(0.6 if hill_front else 0.1, 1.0, smoothstep(0.3, 0.6, d01)):
			continue
		var dens := lerpf(0.85, 1.35, 1.0 - d01)
		if is_edge:
			dens *= 1.2
		if meadow:
			dens *= 2.2                                   # 草地孤立木：彼此拉開
		var rad := float(info["crown_w"]) * sc * 0.5 * 0.82 * dens
		# 樹叢：成群處樹冠互相咬合（間距係數小），稀疏處拉開
		var kq := lerpf(0.66, 0.34, smoothstep(0.3, 0.75, _n01(n_clump, p.x, p.y)))
		if not _free(items, grid, p, rad, kq):
			continue
		if blocked(C, p) != "":
			continue
		var g := ground(C, p, clampf(float(info["dbh_m"]) * sc * 0.7, 0.15, 1.0))
		if is_nan(g):
			dropped["ground"] += 1
			continue
		var lean := deg_to_rad(rng.randf_range(0.0, 3.0))
		var lean_dir := rng.randf() * TAU
		if is_edge and not meadow:
			var gx := edge_at(C, p + Vector2(2, 0)) - edge_at(C, p - Vector2(2, 0))
			var gz := edge_at(C, p + Vector2(0, 2)) - edge_at(C, p - Vector2(0, 2))
			if Vector2(gx, gz).length() > 0.01:
				lean_dir = atan2(-gz, -gx)
				lean = deg_to_rad(rng.randf_range(2.0, 6.0))
		_add(items, grid, {"id": tid, "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc, "lean": lean, "lean_dir": lean_dir,
			"layer": "edge" if is_edge else "canopy", "belt": belt, "de": de, "rad": rad, "tone": _n01(n_tone, p.x, p.y)})
	# ── 山頂鎮守の森：社殿 pad 北側（背對村子）御神木杉群，讓主峰在村內南望有一叢最高、最深的杉冠（主峰層級＋社殿背景）
	var shrine_pad := C.hill_c
	for pd: Array in C.pads:
		if (pd[0] as Vector2).distance_to(C.hill_c) < 12.0:
			shrine_pad = pd[0]
	var placed_hero := 0
	for tries in 1500:
		if placed_hero >= SUMMIT_HERO_N:
			break
		var a := deg_to_rad(rng.randf_range(-170.0, -10.0))      # 北側半圓（-z）
		var rr := rng.randf_range(14.0, 34.0)
		var p := shrine_pad + Vector2(cos(a), sin(a)) * rr
		if blocked(C, p) != "" or belt_at(C, p) < 0 or (shrine_t != Vector3.ZERO and not flank_ok(p, shrine_t)):
			continue
		var h := C.S.h(p.x, p.y)
		var info: Dictionary = M["sugi_hero"]
		var sc := minf(rng.randf_range(0.95, 1.08), (minf(hier_cap(C, p), back_cap(p, shrine_t)) - h) / float(info["height"]))
		if sc < 0.8:
			continue
		var rad := float(info["crown_w"]) * sc * 0.5 * 0.7
		var clash := false
		for o: Dictionary in items:
			if String(o["id"]) == "sugi_hero" and (o["p"] as Vector2).distance_to(p) < 9.0:
				clash = true
				break
		if clash:
			continue
		# 御神木：把擋位的一般林冠讓出來
		var keep2: Array = []
		for o: Dictionary in items:
			if (o["p"] as Vector2).distance_to(p) < rad + float(o["rad"]) * 0.5 and String(o["id"]) != "sugi_hero":
				continue
			keep2.append(o)
		items = keep2
		grid.clear()
		for k in items.size():
			_grid_add(grid, items[k]["p"], k)
		var g := ground(C, p, 1.0)
		if is_nan(g):
			continue
		_add(items, grid, {"id": "sugi_hero", "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc, "lean": deg_to_rad(rng.randf_range(0, 2)),
			"lean_dir": rng.randf() * TAU, "layer": "canopy", "belt": "Forest_HillCrown", "de": edge_at(C, p), "rad": rad, "tone": 0.3})
		placed_hero += 1
	var n_canopy := items.size()
	# ── 次林層：林冠下樹冠間隙的小喬木（楓、小楢、幼樹）＝中後景深度；草地與林緣 8 m 內不放
	var n_sub := 0
	for c: Vector2i in cand:
		if rng.randf() > 0.16:
			continue
		var p := cell_p(C, c.x, c.y) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		var b := belt_at(C, p)
		if b < 0:
			continue
		var de := edge_at(C, p)
		if de < 8.0 or _n01(n_stand, p.x, p.y) < _open_th(C.belts[b]) + STAND_THIN or _west_cut(C.belts[b], p, n_cut) > -0.25:
			continue
		var h := C.S.h(p.x, p.y)
		if is_nan(h) or slope_deg(C, p) > 45.0:
			continue
		var allow := minf(hier_cap(C, p), back_cap(p, shrine_t)) - h
		var tid := _pick(rng, SUB_MIX)
		var info: Dictionary = M[tid]
		var sc := rng.randf_range(0.72, 0.95)
		sc = minf(sc, allow / float(info["height"]))
		if sc < 0.6:
			continue
		var rad := float(info["crown_w"]) * sc * 0.5 * 0.8
		if not _free(items, grid, p, rad, 0.42) or blocked(C, p) != "":
			continue
		var g := ground(C, p, clampf(float(info["dbh_m"]) * sc * 0.7, 0.15, 1.0))
		if is_nan(g):
			continue
		_add(items, grid, {"id": tid, "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc, "lean": deg_to_rad(rng.randf_range(0, 4)),
			"lean_dir": rng.randf() * TAU, "layer": "sub", "belt": C.belts[b], "de": de, "rad": rad, "tone": _n01(n_tone, p.x, p.y)})
		n_sub += 1
	# ── 林帶外坡地植被：禿坡補雑木／赤松／灌木，保留草坡；近村坡面只放低矮過渡；林帶外緣 SLOPE_FEATHER m 內平地也淡出
	var n_slope := 0
	var n_slope_shrub := 0
	var scand: Array = []
	for j in C.nz:
		for i in C.nx:
			var k := j * C.nx + i
			if C.belt_of[k] >= 0:
				continue
			scand.append(Vector2i(i, j))
	_shuffle(rng, scand)
	for c: Vector2i in scand:
		var p := cell_p(C, c.x, c.y) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		var db := C.dbelt[c.y * C.nx + c.x]
		var h := C.S.h(p.x, p.y)
		if is_nan(h):
			continue
		var sl := slope_deg(C, p)
		if sl < SLOPE_MIN_DEG and db > SLOPE_FEATHER:
			continue
		if sl > 50.0 or blocked(C, p) != "":
			continue
		var vb := -TLib.outline_sd(C.outlines, p)          # 離建成區（外側為正）
		var near_vil := vb < SLOPE_NEAR_VILLAGE
		var open := _n01(n_open, p.x, p.y)
		var feather := clampf(1.0 - db / SLOPE_FEATHER, 0.0, 1.0)  # 1＝貼著林帶
		# 草坡：保留約四成開闊（貼林帶處草坡門檻降低＝林緣延伸出去）
		var meadow := open < lerpf(0.52, 0.30, feather)
		var steep := smoothstep(SLOPE_MIN_DEG, 30.0, sl)
		# 坡地：雑木成叢（樹叢場高處＝雑木斑塊，低處＝灌木草坡），隨坡度變密；平地只在貼林帶處淡出
		var grove := smoothstep(0.42, 0.66, _n01(n_clump, p.x * 0.5, p.y * 0.5))
		var p_tree := 0.0 if meadow else ((lerpf(0.09, 0.32, steep) if sl >= SLOPE_MIN_DEG else 0.0) + 0.12 * feather) * lerpf(0.3, 1.0, grove)
		if near_vil:
			p_tree *= 0.35
		if meadow:
			p_tree = 0.012                                   # 草坡上零星孤立木
		var ridge := h - _ring_mean(C, p, 14.0)
		if rng.randf() < p_tree:
			var w: Dictionary = (VILLAGE_SLOPE_MIX if near_vil else SLOPE_MIX).duplicate()
			if w.has("sakura_yama") and _n01(n_sakura, p.x, p.y) <= 0.75:
				w["sakura_yama"] = 0.0
			if ridge > 1.0 and not near_vil:
				for k: String in ["akamatsu_a", "akamatsu_b"]:
					w[k] = float(w[k]) * 3.0                 # 稜線：少量赤松高木打斷輪廓
			var allow := minf(hier_cap(C, p), back_cap(p, shrine_t)) - h
			for k: String in w.keys():
				if float(M[k]["height"]) * 0.72 > allow:
					w[k] = 0.0
			var tid := _pick(rng, w)
			if tid != "":
				var info: Dictionary = M[tid]
				var sc := lerpf(0.74, 1.0, _n01(n_age, p.x, p.y)) * rng.randf_range(0.92, 1.08)
				sc = minf(sc, allow / float(info["height"]))
				var rad := float(info["crown_w"]) * sc * 0.5 * 0.85
				var kq := lerpf(1.05, 0.5, smoothstep(0.3, 0.75, _n01(n_clump, p.x, p.y)))
				if sc >= 0.6 and _free(items, grid, p, rad, kq):
					var g := ground(C, p, clampf(float(info["dbh_m"]) * sc * 0.7, 0.15, 1.0))
					if not is_nan(g):
						_add(items, grid, {"id": tid, "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc,
							"lean": deg_to_rad(rng.randf_range(0, 5)), "lean_dir": rng.randf() * TAU, "layer": "slope", "belt": "Slope",
							"de": db, "rad": rad, "tone": _n01(n_tone, p.x, p.y)})
						n_slope += 1
						continue
		# 灌木：貼林帶的 mantle 最密、坡地雑木間中等、草坡零星；近村坡面略多（植生過渡）
		var p_sh := 0.02 if meadow else 0.07 + 0.22 * feather * feather
		if near_vil and not meadow:
			p_sh += 0.05
		if rng.randf() < p_sh:
			var tid := _pick(rng, UNDER_MIX)
			var info: Dictionary = M[tid]
			var sc := rng.randf_range(0.75, 1.15)
			var rad := float(info["crown_w"]) * sc * 0.5 * (0.7 if tid in UNDER_IDS else 0.85)
			if _free_under(items, grid, p, rad, tid):
				var g := ground(C, p, 0.15)
				if not is_nan(g):
					_add(items, grid, {"id": tid, "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc, "lean": deg_to_rad(rng.randf_range(0, 4)),
						"lean_dir": rng.randf() * TAU, "layer": "under", "belt": "Slope", "de": db, "rad": rad, "tone": _n01(n_tone, p.x, p.y)})
					n_slope_shrub += 1
	# ── 視線淨空（全部樹木層）：主要村道望山頂社殿／參道鳥居、參道望社殿，會擋到的樹拿掉
	var targets: Array = opts.get("targets", [])
	var stations: PackedVector3Array = opts.get("stations", PackedVector3Array())
	var approach: PackedVector3Array = opts.get("approach", PackedVector3Array())
	if not targets.is_empty() and not stations.is_empty():
		# r5：視線上的樹不直接拿掉（拿掉＝丘南面整片禿），改成「降級」：先縮小、再換低矮樹種（楓／小楢／幼樹），
		# 都還擋才移除 → 視線走廊兩側林冠往下階梯式降低，看得到社殿又不禿
		var keep: Array = []
		var n_lowered := 0
		var blk := func(it: Dictionary) -> bool:
			return _blocks(it, M, targets, stations) or (not approach.is_empty() and _blocks(it, M, targets.slice(0, 2), approach))
		for it: Dictionary in items:
			if String(it["layer"]) in ["under", "dead"] or not blk.call(it):
				keep.append(it)
				continue
			var ok := false
			# 降級替代只用綠色小喬木（不用楓：橘紅色塊會停在社殿正前方搶焦點）
			for tid: String in [String(it["id"]), "konara_b", "young_broad_a", "young_broad_b"]:
				var sc0 := float(it["sc"]) if tid == String(it["id"]) else 1.0
				var sc := sc0
				while sc >= 0.6:
					var t2 := it.duplicate()
					t2["id"] = tid
					t2["sc"] = sc
					if not blk.call(t2):
						it["id"] = tid
						it["sc"] = sc
						it["rad"] = float(M[tid]["crown_w"]) * sc * 0.5 * 0.82
						ok = true
						break
					sc -= 0.08
				if ok:
					break
			if ok:
				n_lowered += 1
				keep.append(it)
			else:
				dropped["sightline"] += 1
		dropped["sight_lowered"] = n_lowered
		items = keep
		grid.clear()
		for k in items.size():
			_grid_add(grid, items[k]["p"], k)
	# ── 下層（林帶內）：林緣 mantle（密）、林內草地邊（密）、林隙（中）、林下（疏、耐陰）、草地中（零星）
	for c: Vector2i in cand:
		var p := cell_p(C, c.x, c.y) + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		var b := belt_at(C, p)
		if b < 0:
			continue
		var de := edge_at(C, p)
		var gap := _n01(n_gap, p.x, p.y)
		var stand := _n01(n_stand, p.x, p.y)
		var so := _open_th(C.belts[b])
		var shade := _under_canopy(items, grid, p)
		var prob := 0.0
		var mix: Dictionary = UNDER_MIX
		var cut := _west_cut(C.belts[b], p, n_cut)
		if cut > 0.0:
			prob = 0.03 if cut > 0.35 else 0.32            # 橫斷草地中零星；邊緣 mantle
		elif stand < so:
			prob = 0.035 if stand < so - 0.04 else 0.30   # 草地中零星；草地邊 mantle
		elif stand < so + STAND_THIN:
			prob = 0.20
		elif de < 9.0:
			prob = lerpf(0.42, 0.18, de / 9.0)
		elif de > 16.0 and gap > 0.74:
			prob = 0.22
		elif shade:
			prob = 0.035
			mix = SHADE_MIX
		else:
			prob = 0.10
		if rng.randf() > prob:
			continue
		var tid := _pick(rng, mix)
		var info: Dictionary = M[tid]
		var sc := rng.randf_range(0.75, 1.15)
		var rad := float(info["crown_w"]) * sc * 0.5 * (0.7 if tid in UNDER_IDS else 0.85)
		if not _free_under(items, grid, p, rad, tid):
			continue
		if blocked(C, p) != "":
			continue
		var g := ground(C, p, 0.15)
		if is_nan(g):
			continue
		var it := {"id": tid, "p": p, "y": g, "yaw": rng.randf() * TAU, "sc": sc, "lean": deg_to_rad(rng.randf_range(0, 4)),
			"lean_dir": rng.randf() * TAU, "layer": "under", "belt": C.belts[b], "de": de, "rad": rad,
			"tone": _n01(n_tone, p.x, p.y)}
		if not tid in UNDER_IDS:
			# 幼樹也不能擋視線
			if not targets.is_empty() and (_blocks(it, M, targets, stations) or (not approach.is_empty() and _blocks(it, M, targets.slice(0, 2), approach))):
				continue
		_add(items, grid, it)
	# ── 枯立木／倒木（林內，少量）
	for c: Vector2i in cand:
		if rng.randf() > 0.0016:
			continue
		var p := cell_p(C, c.x, c.y)
		var de := edge_at(C, p)
		if de < 14.0:
			continue
		var tid := "snag_a" if rng.randf() < 0.55 else "log_a"
		var info: Dictionary = M[tid]
		var rad := float(info["crown_w"]) * 0.5
		if not _free_under(items, grid, p, rad, tid) or blocked(C, p) != "":
			continue
		var g := ground(C, p, 0.4 if tid == "log_a" else 0.2)
		if is_nan(g):
			continue
		var it := {"id": tid, "p": p, "y": g - (0.12 if tid == "log_a" else 0.0), "yaw": rng.randf() * TAU,
			"sc": rng.randf_range(0.85, 1.1), "lean": 0.0, "lean_dir": 0.0, "layer": "dead", "belt": C.belts[belt_at(C, p)],
			"de": de, "rad": rad, "tone": 0.5}
		if tid == "snag_a" and not targets.is_empty() and _blocks(it, M, targets, stations):
			continue
		_add(items, grid, it)
	for it: Dictionary in items:
		var ck := chunk_key(it["p"])
		var cc := (Vector2(ck) + Vector2(0.5, 0.5)) * CHUNK
		# 林分色調：64 m 塊中心的色調場＋樹種雜湊（同一塊不同樹種不一定同色）
		var tone := fposmod(_n01(n_tone, cc.x, cc.y) + 0.37 * float(hash(String(it["id"])) % 7) / 7.0, 1.0)
		it["preset"] = _preset(String(M[it["id"]]["group"]), tone, String(it["id"]))
	return {"items": items, "ctx": C, "n_canopy": n_canopy, "n_sub": n_sub, "n_slope": n_slope, "n_slope_shrub": n_slope_shrub,
		"dropped": dropped, "ms": Time.get_ticks_msec() - t0, "mask_ms": mask_ms}


## 社殿背景天窗：p 點樹梢允許高（INF＝不在任何機位的社殿正後方窗內）
static func back_cap(p: Vector2, shrine: Vector3) -> float:
	if shrine == Vector3.ZERO:
		return INF
	var cap := INF
	for cam: Vector3 in BACK_CAMS:
		var c2 := Vector2(cam.x, cam.z)
		var s2 := Vector2(shrine.x, shrine.z)
		var ds := c2.distance_to(s2)
		var dp := c2.distance_to(p)
		if dp <= ds + 1.0:
			continue
		var da := rad_to_deg(absf(wrapf((p - c2).angle() - (s2 - c2).angle(), -PI, PI)))
		if da > BACK_WIN:
			continue
		var e := atan2(shrine.y - 0.6 - cam.y, ds)
		cap = minf(cap, cam.y + tan(e) * dp)
	return cap


## 社殿兩側（BACK_WIN–BACK_FLANK°、社殿後方）＝御神木杉位置
static func flank_ok(p: Vector2, shrine: Vector3) -> bool:
	var cam: Vector3 = BACK_CAMS[0]
	var c2 := Vector2(cam.x, cam.z)
	var s2 := Vector2(shrine.x, shrine.z)
	if c2.distance_to(p) <= c2.distance_to(s2) + 4.0:
		return false
	var da := rad_to_deg(absf(wrapf((p - c2).angle() - (s2 - c2).angle(), -PI, PI)))
	return da > BACK_WIN + 1.0 and da < BACK_FLANK


## 西林橫斷草地：> 0＝在草地內（0–1 越往中心越大）；< 0＝離草地邊多遠（半寬的倍數，負值）
static func _west_cut(belt: String, p: Vector2, n: FastNoiseLite) -> float:
	if belt != "Forest_West":
		return -9.0
	var best := -9.0
	for c: Array in WEST_CUTS:
		var hw := float(c[1]) * lerpf(0.55, 1.45, _n01(n, p.x, p.y))
		var zc := float(c[0]) + 10.0 * (_n01(n, p.x * 0.6 + 400.0, 0.0) - 0.5)
		best = maxf(best, 1.0 - absf(p.y - zc) / maxf(hw, 1.0))
	return best


static func _open_th(belt: String) -> float:
	if not belt in OPEN_BELTS:
		return -1.0
	return float(STAND_OPEN_BY.get(belt, STAND_OPEN))


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for k in range(arr.size() - 1, 0, -1):
		var r := rng.randi_range(0, k)
		var tmp: Variant = arr[k]
		arr[k] = arr[r]
		arr[r] = tmp


## 半徑 r 圓周 8 點地面平均（稜線判定：中心比四周高＝稜）
static func _ring_mean(C: Ctx, p: Vector2, r: float) -> float:
	var s := 0.0
	var n := 0
	for k in 8:
		var h := C.S.h(p.x + cos(k * TAU / 8.0) * r, p.y + sin(k * TAU / 8.0) * r)
		if not is_nan(h):
			s += h
			n += 1
	return s / n if n > 0 else C.S.h(p.x, p.y)


static func _preset(group: String, tone: float, tid: String) -> String:
	var g := group
	if tid in YOUNG_IDS:
		g = "young"
	elif tid in UNDER_IDS:
		g = "under"
	elif tid in ["snag_a", "log_a"]:
		g = "dead"
	elif tid.begins_with("sakura"):
		g = "sakura"
	elif tid.begins_with("momiji"):
		g = "momiji"
	elif tid.begins_with("yanagi"):
		g = "yanagi"
	elif tid.contains("matsu"):
		g = "matsu"
	var arr: Array = PRESET_BY_GROUP.get(g, ["mature"])
	return String(arr[clampi(int(tone * arr.size()), 0, arr.size() - 1)])


static func _grid_add(grid: Dictionary, p: Vector2, k: int) -> void:
	var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	if not grid.has(c):
		grid[c] = []
	(grid[c] as Array).append(k)


static func _add(items: Array, grid: Dictionary, it: Dictionary) -> void:
	items.append(it)
	_grid_add(grid, it["p"], items.size() - 1)


## 林冠彼此：中心距 ≥ (r_i + r_j) × k
static func _free(items: Array, grid: Dictionary, p: Vector2, r: float, k: float) -> bool:
	var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	for dj in range(-2, 3):
		for di in range(-2, 3):
			for idx: int in grid.get(c + Vector2i(di, dj), []):
				var o: Dictionary = items[idx]
				if String(o["layer"]) in ["under", "dead"]:
					continue
				if p.distance_to(o["p"]) < (r + float(o["rad"])) * k:
					return false
	return true


## 下層：不貼樹幹（≥ 1.0 m＋幹徑）、彼此間距
static func _free_under(items: Array, grid: Dictionary, p: Vector2, r: float, tid: String) -> bool:
	var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for idx: int in grid.get(c + Vector2i(di, dj), []):
				var o: Dictionary = items[idx]
				var d := p.distance_to(o["p"])
				if String(o["layer"]) in ["under", "dead"]:
					if d < (r + float(o["rad"])) * 0.8:
						return false
				elif d < 1.2 + (0.6 if not tid in UNDER_IDS else 0.0):
					return false
	return true


static func _under_canopy(items: Array, grid: Dictionary, p: Vector2) -> bool:
	var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for idx: int in grid.get(c + Vector2i(di, dj), []):
				var o: Dictionary = items[idx]
				if String(o["layer"]) == "canopy" and p.distance_to(o["p"]) < float(o["rad"]) * 1.1:
					return true
	return false


## 樹冠輪廓（世界）：回傳 [頂 y, 冠底 y, 冠半徑, 錐形?]
static func crown(it: Dictionary, M: Dictionary) -> Array:
	var info: Dictionary = M[it["id"]]
	var sc := float(it["sc"])
	var top := float(it["y"]) + float(info["height"]) * sc
	var cw := float(info["crown_w"]) * sc * 0.5
	var g := String(info["group"])
	var cone := g == "conifer" or String(it["id"]) == "young_sugi"
	var base := float(it["y"]) + float(info["height"]) * sc * (0.35 if cone else 0.4)
	return [top, base, cw, cone]


static func crown_h_at(cr: Array, d: float) -> float:
	## 中心水平距 d 處的冠頂高（超出冠幅＝-INF）
	var top: float = cr[0]
	var base: float = cr[1]
	var r: float = cr[2]
	if d > r:
		return -INF
	if bool(cr[3]):
		return top - (top - base) * (d / r)
	var mid := (top + base) * 0.5
	return mid + (top - mid) * sqrt(maxf(0.0, 1.0 - (d / r) * (d / r)))


static func _blocks(it: Dictionary, M: Dictionary, targets: Array, stations: PackedVector3Array) -> bool:
	var cr := crown(it, M)
	var p: Vector2 = it["p"]
	for t: Array in targets:
		var tp: Vector3 = t[1]
		for s: Vector3 in stations:
			var a := Vector2(s.x, s.z)
			var b := Vector2(tp.x, tp.z)
			var ab := b - a
			var L2 := ab.length_squared()
			if L2 < 1.0:
				continue
			var u := (p - a).dot(ab) / L2
			if u <= 0.02 or u >= 0.98:
				continue
			var d_perp := p.distance_to(a + ab * u)
			if d_perp > float(cr[2]):
				continue
			var y_line := lerpf(s.y, tp.y, u)
			if crown_h_at(cr, d_perp) > y_line:
				return true
	return false


# ─────────────────────────── 烘焙 ───────────────────────────

static func xf_of(it: Dictionary) -> Transform3D:
	var sc := float(it["sc"])
	var b := Basis(Vector3.UP, float(it["yaw"]))
	var ax := Vector3(cos(float(it["lean_dir"])), 0.0, sin(float(it["lean_dir"]))).cross(Vector3.UP).normalized()
	if float(it["lean"]) > 0.0:
		b = Basis(ax, float(it["lean"])) * b
	b = b.scaled(Vector3(sc, sc, sc))
	var p: Vector2 = it["p"]
	return Transform3D(b, Vector3(p.x, float(it["y"]), p.y))


static func chunk_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))


static func bake(items: Array) -> Node3D:
	var M := modules()
	var root := Node3D.new()
	root.name = NODE_NAME
	var protos := {}
	for it: Dictionary in items:
		var tid := String(it["id"])
		if not protos.has(tid):
			protos[tid] = (load(KIT + "/trees/%s.tscn" % tid) as PackedScene).instantiate()
	# 1) 近級：Near/C_<塊>/<編號>_<樹種>（Node3D＝擺放變換）→ LOD0、LOD1（prefab 同名節點的 mesh／可見範圍／lod 參數）
	var near := Node3D.new()
	near.name = "Near"
	root.add_child(near)
	var near_chunks := {}
	var n_near := 0
	for k in items.size():
		var it: Dictionary = items[k]
		var tid := String(it["id"])
		var ck := chunk_key(it["p"])
		if not near_chunks.has(ck):
			var cn := Node3D.new()
			cn.name = "C_%d_%d" % [ck.x, ck.y]
			near.add_child(cn)
			near_chunks[ck] = cn
		var t := Node3D.new()
		t.name = "%04d_%s" % [k, tid]
		t.transform = xf_of(it)
		t.set_meta("veg_id", tid)
		t.set_meta("layer", it["layer"])
		t.set_meta("preset", it["preset"])
		(near_chunks[ck] as Node).add_child(t)
		var pr: Array = TreeLib.COLOR_PRESETS.get(it["preset"], TreeLib.COLOR_PRESETS["mature"])
		for lod in mini(NEAR_LODS, (M[tid]["lods"] as Array).size()):
			var src := (protos[tid] as Node).get_node("LOD%d" % lod) as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = src.mesh
			for prop in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin",
					"visibility_range_end_margin", "visibility_range_fade_mode"]:
				mi.set(prop, src.get(prop))
			mi.set_instance_shader_parameter("lod_band", src.get_instance_shader_parameter("lod_band"))
			mi.set_instance_shader_parameter("lod_ref", src.get_instance_shader_parameter("lod_ref"))
			mi.set_instance_shader_parameter("leaf_tint", pr[0])
			mi.set_instance_shader_parameter("leaf_sat", pr[1])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tid in NO_SHADOW \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			t.add_child(mi)
			n_near += 1
	# 2) 遠級：Far/LODk/C_<塊>/<樹種_色調>（MultiMesh）
	var far := Node3D.new()
	far.name = "Far"
	root.add_child(far)
	var n_mmi := 0
	var n_inst := 0
	for lod in range(NEAR_LODS, 5):
		var cs: float = CHUNK_BY_LOD[lod]
		var groups := {}
		for it: Dictionary in items:
			var tid := String(it["id"])
			if lod >= (M[tid]["lods"] as Array).size():
				continue
			var p: Vector2 = it["p"]
			var gk := "%d_%d|%s|%s" % [floori(p.x / cs), floori(p.y / cs), tid, it["preset"]]
			if not groups.has(gk):
				groups[gk] = []
			(groups[gk] as Array).append(it)
		if groups.is_empty():
			continue
		var ln := Node3D.new()
		ln.name = "LOD%d" % lod
		far.add_child(ln)
		var gkeys := groups.keys()
		gkeys.sort()
		var chunk_nodes := {}
		for gk: String in gkeys:
			var parts := gk.split("|")
			var tid := parts[1]
			var src := (protos[tid] as Node).get_node("LOD%d" % lod) as MeshInstance3D
			var arr: Array = groups[gk]
			if not chunk_nodes.has(parts[0]):
				var cn := Node3D.new()
				cn.name = "C_" + parts[0]
				ln.add_child(cn)
				chunk_nodes[parts[0]] = cn
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = arr.size()
			var ab := AABB()
			for k in arr.size():
				var xf := xf_of(arr[k])
				mm.set_instance_transform(k, xf)
				var wb: AABB = xf * src.mesh.get_aabb()
				ab = wb if k == 0 else ab.merge(wb)
			mm.custom_aabb = ab
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [tid, parts[2]]
			mmi.multimesh = mm
			mmi.set_instance_shader_parameter("lod_band", src.get_instance_shader_parameter("lod_band"))
			mmi.set_instance_shader_parameter("lod_ref", src.get_instance_shader_parameter("lod_ref"))
			var pr: Array = TreeLib.COLOR_PRESETS.get(parts[2], TreeLib.COLOR_PRESETS["mature"])
			mmi.set_instance_shader_parameter("leaf_tint", pr[0])
			mmi.set_instance_shader_parameter("leaf_sat", pr[1])
			# 節點可見範圍以 AABB 中心量：塊內實例離中心最多約「實際 AABB 半對角」→ 前後各放寬它（逐實例換檔仍由 shader 決定）
			var hd := Vector2(ab.size.x, ab.size.z).length() * 0.5
			mmi.visibility_range_begin = maxf(0.0, src.visibility_range_begin - hd) if src.visibility_range_begin > 0.0 else 0.0
			mmi.visibility_range_end = src.visibility_range_end + hd if src.visibility_range_end > 0.0 else 0.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tid in NO_SHADOW \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.set_meta("veg_id", tid)
			mmi.set_meta("instances", arr.size())
			(chunk_nodes[parts[0]] as Node).add_child(mmi)
			n_mmi += 1
			n_inst += arr.size()
	# 3) 樹幹碰撞：每 64 m 塊一個 StaticBody3D、每棵一個圓柱
	var col_root := Node3D.new()
	col_root.name = "Collision"
	root.add_child(col_root)
	var bodies := {}
	var n_shape := 0
	for it: Dictionary in items:
		var col: Array = M[it["id"]].get("collision", [])
		if col.is_empty():
			continue
		var ck := chunk_key(it["p"])
		if not bodies.has(ck):
			var sb := StaticBody3D.new()
			sb.name = "C_%d_%d" % [ck.x, ck.y]
			col_root.add_child(sb)
			bodies[ck] = sb
		var xf := xf_of(it)
		for c: Dictionary in col:
			var pa := xf * TreeLib._v(c["a"])
			var pb := xf * TreeLib._v(c["b"])
			var cs := CollisionShape3D.new()
			cs.name = "T%d" % n_shape
			var sh := CylinderShape3D.new()
			sh.radius = float(c["r"]) * float(it["sc"])
			sh.height = pa.distance_to(pb)
			cs.shape = sh
			var up := (pb - pa).normalized()
			var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(up).normalized()
			cs.transform = Transform3D(Basis(x, up, z), (pa + pb) * 0.5)
			(bodies[ck] as Node).add_child(cs)
			n_shape += 1
	for tid in protos:
		(protos[tid] as Node).free()
	root.set_meta("trees", items.size())
	root.set_meta("near_mesh_nodes", n_near)
	root.set_meta("multimesh_nodes", n_mmi)
	root.set_meta("multimesh_instances", n_inst)
	root.set_meta("trunk_shapes", n_shape)
	root.set_meta("chunk_by_lod", CHUNK_BY_LOD)
	root.set_meta("art_revision", "P9 R2 Forest Belts r2：取代 P0 六塊林冠 placeholder；近級逐棵、遠級 MultiMesh（ART_REVIEW）")
	return root


## instance uniform 使用節點數（不建節點）：近級逐棵逐級＋遠級分組
static func node_count(items: Array) -> int:
	var M := modules()
	var n := 0
	for it: Dictionary in items:
		n += mini(NEAR_LODS, (M[it["id"]]["lods"] as Array).size())
	for lod in range(NEAR_LODS, 5):
		var cs: float = CHUNK_BY_LOD[lod]
		var g := {}
		for it: Dictionary in items:
			if lod >= (M[it["id"]]["lods"] as Array).size():
				continue
			var p: Vector2 = it["p"]
			g["%d_%d|%s|%s" % [floori(p.x / cs), floori(p.y / cs), it["id"], it["preset"]]] = true
		n += g.size()
	return n


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		own(c, owner)


# ─────────────────────────── 天際線 ───────────────────────────

## 人眼視角天際線（仰角，度）：地形以射線步進（2 m）取樣碰撞面高度、樹冠用錐／橢球輪廓。
## 回傳 {"az": PackedFloat32Array 方位（度，相對視線方向，右為正）, "terrain": [...], "all": [...]}
static func skyline(C: Ctx, items: Array, cam: Vector3, look: Vector3, half_fov := 52.0, step_deg := 0.25) -> Dictionary:
	var M := modules()
	var fwd := Vector2(look.x - cam.x, look.z - cam.z).normalized()
	var base := atan2(fwd.y, fwd.x)
	var n := int(half_fov * 2.0 / step_deg) + 1
	var az := PackedFloat32Array()
	var ter := PackedFloat32Array()
	var allv := PackedFloat32Array()
	az.resize(n)
	ter.resize(n)
	ter.fill(-90.0)
	for k in n:
		var a := -half_fov + k * step_deg
		az[k] = a
		# 畫面右＝順時針（俯視 x 東、z 南：右轉＝角度減）
		var th := base - deg_to_rad(a)
		var dir := Vector2(cos(th), sin(th))
		var best := -90.0
		var d := 8.0
		while d < 800.0:
			var q := Vector2(cam.x, cam.z) + dir * d
			var h := C.S.h(q.x, q.y)
			if not is_nan(h):
				best = maxf(best, rad_to_deg(atan2(h - cam.y, d)))
			d += 2.0 if d < 200.0 else 4.0
		ter[k] = best
	allv = ter.duplicate()
	for it: Dictionary in items:
		if String(it["layer"]) in ["under", "dead"]:
			continue
		var p: Vector2 = it["p"]
		var rel := p - Vector2(cam.x, cam.z)
		var dist := rel.length()
		if dist < 8.0:
			continue
		var cr := crown(it, M)
		var a_c := -rad_to_deg(wrapf(atan2(rel.y, rel.x) - base, -PI, PI))
		var a_w := rad_to_deg(atan(float(cr[2]) / dist))
		var k0 := int(floor((a_c - a_w + half_fov) / step_deg))
		var k1 := int(ceil((a_c + a_w + half_fov) / step_deg))
		for k in range(maxi(k0, 0), mini(k1, n - 1) + 1):
			var da := deg_to_rad(az[k] - a_c)
			var dp := absf(dist * sin(da))
			var hh := crown_h_at(cr, dp)
			if hh == -INF:
				continue
			var e := rad_to_deg(atan2(hh - cam.y, dist * cos(da)))
			if e > allv[k]:
				allv[k] = e
	return {"az": az, "terrain": ter, "all": allv, "base": base}


## 北丘三點（西肩／主峰／東次峰）在天際線上的值：方位窗 ±win 度內的最大仰角，正規化到主峰。
static func hill_ratios(C: Ctx, prof: Dictionary, cam: Vector3, key: String, win := 2.5) -> Dictionary:
	var out := {}
	var pts := {"主峰": C.hill_c}
	for k in C.lobes:
		if String(k) in ["西肩", "東次峰"]:
			pts[k] = Vector2(C.lobes[k].x, C.lobes[k].y)
	var base: float = prof["base"]
	for nm: String in pts:
		var rel: Vector2 = pts[nm] - Vector2(cam.x, cam.z)
		var a_c := -rad_to_deg(wrapf(atan2(rel.y, rel.x) - base, -PI, PI))
		var best := -90.0
		var arr: PackedFloat32Array = prof[key]
		# 主峰＝社殿兩側御神木杉群（社殿正後方留天窗，所以主峰窗涵蓋到兩側夾杉 BACK_FLANK°）
		var w := (BACK_FLANK - 1.0) if nm == "主峰" else win
		for k in arr.size():
			if absf(float(prof["az"][k]) - a_c) <= w:
				best = maxf(best, arr[k])
		out[nm] = best
	var m := float(out["主峰"])
	var r := {}
	for nm: String in out:
		r[nm] = float(out[nm]) / m if m > 0.0 else 0.0
	return {"deg": out, "ratio": r}
