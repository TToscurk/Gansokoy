extends RefCounted
## P13 W9 Round 2：建築外形サンプル（主街 6＋住宅巷 4）＋2.1 追加 6＋Phase 2 の新建築タイプ 3 の仕様表。
##   生成器 source of truth＝assets/blender/village_v2/build_w9r2_arch.py（メッシュ）＋ このファイル（どの Kit 構件を隠すか）。
##   overlay（ArchW9R2P13）は該当建築の Kit の構件を『カテゴリ単位』で非表示にし、同じ局部座標に新メッシュを重ねる。
##   footprint・入口位置・碰撞（Shape）・Frontage（地面の過渡）には触れない。enabled=false で Kit を完全に還す。
const NODE_NAME := "ArchW9R2P13"
const OUTPUT := "res://maps/village_v2/gen/arch_w9r2_p13.scn"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER := "EnrichW9P13"
const MESH_DIR := "res://assets/village_v2/w9r2_arch/mesh/"
const SCRIPT := "res://maps/village_v2/scripts_p13/arch_w9r2.gd"
const META := "res://assets/village_v2/w9r2_arch/src/modules_blender.json"
const POST_PAD := 0.03        # 庇柱の碰撞は柱（w）より半径 +0.03 m 太い箱（見た目の柱に触れたら当たる）。礎石（±0.12）より細くはしない
const LOD_RANGES := [0.0, 40.0, 600.0]
const LOD_MARGIN := 4.0

## Kit LOD0 の構件名の接頭辞（カテゴリ）。『前面を置換』＝front＋eave を隠す。『屋根を置換』＝roof。
const CAT0 := {
	"front": ["f1_", "fb_", "fp_", "u_", "nr_", "sf_", "rt_", "rtu", "kbr_", "kbs_", "kiri", "iy_"],
	"eave": ["hisx_", "his_", "hisw_", "ud_"],
	"roof": ["rf_", "rg_", "gbh_", "gyo", "oni", "vg_", "kemu", "dmg", "dmr_", "udh_", "udk"],
}
## Kit LOD1／LOD2 の構件名の接頭辞
const CAT12 := {
	"front": [],
	"eave": ["l_slab"],
	"roof": ["l_rh", "rg_u", "rg_l", "kemu", "dmg", "dmr", "udh_", "udk"],
}

## id → {path: village 直下からの body パス, hide: [カテゴリ]}
const SPECS := {
	"B_P_MKT_008": {"path": "Districts/Market/Buildings/B_P_MKT_008", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_009": {"path": "Districts/Market/Buildings/B_P_MKT_009", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_010": {"path": "Districts/Market/Buildings/B_P_MKT_010", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_011": {"path": "Districts/Market/Buildings/B_P_MKT_011", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_012": {"path": "Districts/Market/Buildings/B_P_MKT_012", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_013": {"path": "Districts/Market/Buildings/B_P_MKT_013", "hide": ["front", "eave"]},
	"B_P_RSW_047": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_047", "hide": ["front", "eave"]},
	"B_P_RSW_048": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_048", "hide": ["front", "eave", "roof"]},
	"B_P_RSW_061": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_061", "hide": ["front", "eave", "roof"]},
	"B_P_RSW_062": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_062", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_025": {"path": "Districts/Market/Buildings/B_P_MKT_025", "hide": ["all"]},      # 平屋へ低くするので Kit の壁・柱・屋根を（base 以外）全て隠し自前で閉じる
	"B_P_MKT_027": {"path": "Districts/Market/Buildings/B_P_MKT_027", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_026": {"path": "Districts/Market/Buildings/B_P_MKT_026", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_024": {"path": "Districts/Market/Buildings/B_P_MKT_024", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_006": {"path": "Districts/Market/Buildings/B_P_MKT_006", "hide": ["front", "eave", "roof"]},
	"B_P_MKT_020": {"path": "Districts/Market/Buildings/B_P_MKT_020", "hide": ["front", "eave", "roof"]},
	# ── Phase 2：新しい建築タイプ 3 棟（Kit の壁・屋根・庇を base 以外全て隠して自前で組む）──
	"B_P_RSW_074": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_074", "hide": ["all"]},      # 板葺き簡陋民宅
	"B_P_MKT_029": {"path": "Districts/Market/Buildings/B_P_MKT_029", "hide": ["all"]},                # 土蔵の商家
	"B_P_RSW_014": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_014", "hide": ["all"]},      # 作業場付きの工匠宅
	# ── Phase 3 A：主街 北ブロック（西側）の屋形の差異化 5 棟（全隠して自前で組む。入口位置・footprint・body 碰撞は不変）──
	"B_P_MKT_030": {"path": "Districts/Market/Buildings/B_P_MKT_030", "hide": ["all"]},                # 瀬戸物屋＝棟の低い板葺き平屋
	"B_P_MKT_031": {"path": "Districts/Market/Buildings/B_P_MKT_031", "hide": ["all"]},                # 菓子屋大店＝高い棟＋二階の出桁造り＋千鳥破風
	"B_P_MXC_005": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_005", "hide": ["all"]},      # 質屋＝店＋脇蔵（妻入の白い二階建て）
	"B_P_MXC_006": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_006", "hide": ["all"]},      # 菓子屋＝寄棟の二階＋全幅の縁
	"B_P_MXC_007": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_007", "hide": ["all"]},      # 八百屋＝深い下屋の吹き放ちの土間店
	# ── Phase 3 B：住宅巷（MidLane）の家 3 棟 ──
	"B_P_RSW_075": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_075", "hide": ["all"]},      # 瓦葺き妻入の小綺麗な家＋縁側
	"B_P_RSW_076": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_076", "hide": ["all"]},      # 母屋＋板蔵（倉房）
	"B_P_RSW_071": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_071", "hide": ["all"]},      # 板葺き平入＋前の下屋の柴棚

	# ── Phase 4 R1：主街の輪郭差異化 5 棟（用途は各棟の門前の P10 商いに合わせた。全隠して自前で組む。入口位置・footprint・body 碰撞は不変）──
	"B_P_MKT_005": {"path": "Districts/Market/Buildings/B_P_MKT_005", "hide": ["all"]},                # 雑貨の大店＝入母屋＋二階の出格子の通し
	"B_P_MKT_015": {"path": "Districts/Market/Buildings/B_P_MKT_015", "hide": ["all"]},                # 八百屋・青物問屋＝二重屋根（四方下屋＋退縮した二階の寄棟）
	"B_P_MXC_001": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_001", "hide": ["all"]},      # 旅籠＝高い棟＋玄関の唐破風
	"B_P_MXC_002": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_002", "hide": ["all"]},      # 団子・菓子屋＝低い石置き板葺き（谷）＋深い板庇
	"B_P_MXC_004": {"path": "Districts/MixedCommercial/Buildings/B_P_MXC_004", "hide": ["all"]},      # 仕舞屋・門構え＝寄棟の翼＋隆起した妻入の門棟
	"B_P_MKT_001": {"path": "Districts/Market/Buildings/B_P_MKT_001", "hide": ["all"]},                # 秤屋＝南入口の右手・低い瓦の寄棟の中二階
	"B_P_MKT_004": {"path": "Districts/Market/Buildings/B_P_MKT_004", "hide": ["all"]},                # 瀬戸物屋＝低い石置き板葺き（北隣 MKT_005 の入母屋の南端を見せる）
	# ── Phase 4 B：西巷（WestAlley）の 4 棟 ──
	"B_P_RSW_024": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_024", "hide": ["all"]},      # 名主の家＝横に広い入母屋の平屋＋唐破風の玄関
	"B_P_RSW_025": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_025", "hide": ["all"]},      # 板葺きの低い家（東列で一番低い）
	"B_P_RSW_026": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_026", "hide": ["all"]},      # 仕立て屋＝細長く高い妻入のせり出し二階
	"B_P_RSW_012": {"path": "Districts/ResidentialWest/Buildings/B_P_RSW_012", "hide": ["all"]},      # 越屋根の寄棟の農家
	# ── Phase 5：主街中段 2 棟（全隠して自前で組む。入口位置・footprint・body 碰撞は不変）──
	"B_P_MKT_023": {"path": "Districts/Market/Buildings/B_P_MKT_023", "hide": ["all"]},                # 市の角の米屋＝総二階の入母屋（南の妻を中橫街へ）＋角を回る庇
	"B_P_MKT_028": {"path": "Districts/Market/Buildings/B_P_MKT_028", "hide": ["all"]},                # 隠居の仕舞屋＝妻入の平屋（木連格子の妻）
}


static func hide_prefixes(id: String, lod: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cats: Array = SPECS[id]["hide"]
	if cats.has("all"):
		return PackedStringArray(["*"])      # base 以外の Kit 構件を全部（overlay 側で解釈）
	var tab: Dictionary = CAT0 if lod == 0 else CAT12
	for c: String in cats:
		var cc := c
		if lod != 0 and c == "front":
			cc = "eave" if cats.has("eave") else "front"
		for p: String in tab.get(cc, []):
			out.append(p)
	return out
