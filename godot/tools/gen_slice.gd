# PHASE 1.5 —— 人間之里 Vertical Slice（art benchmark）
#
#   godot --headless --path godot --script tools/gen_slice.gd
#   xvfb-run -a godot --rendering-driver opengl3 --path godot -- --map=slice \
#     --shots=res://tools/shots/slice.json --shotdir=<dir>
#
# ══════════════════════════════════════════════════════════════════════
# 這是什麼、不是什麼
# ══════════════════════════════════════════════════════════════════════
# **是**：一段 8 棟建築的街，用來回答「整體畫面能不能脫離 procedural demo」。
#         獨立的 map（`maps/slice/`），可以來回重生成、重審圖，不動 village。
# **不是**：整村重做。169 棟、六座地標、河流、稗田邸一律沒碰。
#
# ── PHASE 1.6：legacy quarantine ──
# 這個 slice 裡**沒有任何 legacy blockout 建築**。原本用來製造變化的三棟
# （machiya_f_b / b_a / e_a）全部移出：它們是白盒子、屋頂只有一片斜面、
# 高度搶戲但細節不足，站在有軸組有瓦的新版旁邊會直接綁架審圖。
# ⚠ **資產一個都沒刪**，village 的 169 棟照樣在用它們 —— 這裡只是不放。
# 代價寫在報告裡：全場同一份 mesh，天際線因此是平的。那正是 Phase 2
# （Architecture Kit）要解的問題，本輪明令不做。
#
# 為什麼要獨立場景而不是在 village 上改：village 的佈局是 `_block()` 的明表
# （169 棟的 frontage 座標），改一格就要重跑全圖 + 五道閘門，一輪 6 分鐘。
# 這裡 46m 見方、8 棟，一輪 25 秒 —— 審圖要能**反覆**才有意義。
#
# ── 街道構圖的規矩：planned irregularity，不是 random scatter ──
# 所有的變化都寫在 `LOTS` 明表裡，每一筆都有理由（見表上的註解）。
# 沒有一個 `randf()` 決定建築的位置、朝向或退縮 —— 亂數只出現在
# 「同一種雜草的角度」這種層級。
extends SceneTree

const OUT_DIR := "res://maps/slice/"
const MAP_ID := "slice"
const HALF := 46.0
const SEED := 20260807

# 街：沿 x 走，路心 z = 0，路寬 6.0（夯土）。側街沿 z 走，x = +21。
const ROAD_W := 7.2
const SIDE_X := 21.0

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _mods := {}
var _nh: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _audit: Array[String] = []


# ══════════════════════════════════════════════════════════════════════
# 街廓：8 個地塊。**每一筆的偏移都有理由**
# ══════════════════════════════════════════════════════════════════════
#
# 欄位：kind / x / 退縮 setback（離路緣多遠）/ side（+1 北側、−1 南側）/
#       yaw 微轉（弧度）/ role（決定掛什麼道具）/ why（為什麼這樣擺）
#
# 北側的正面朝 +z（模組正面朝 +z，見 town_modules 的 gbox），所以 yaw=0；
# 南側要轉 PI。「微轉」是 ±0.03 rad（約 1.7°）—— 大到看得出不是尺規排的，
# 小到不會讓相鄰的簷口打架。真實町並みの不整齊就是這個量級：
# 地界是幾百年前分的，房子照地界蓋，所以歪的是**地界**不是房子。
# ── PHASE 2：Architecture Kit を入れ替え ──
# Phase 1.6/1.7 は 10 棟すべてが machiya_f_a だった。構図と材質はそれで
# 通ったが、審図の結論はずっと同じ：「立面が逐格同じ・天際線が平ら」。
# ここで 6 種の**別々に生成された**モジュールに差し替える。
#
# ⚠ 配分は意図的に偏らせてある：f_a×3・f_o×2・f_n×2・f_s/t_a/w_a 各 1。
#   「一戸ずつ全部違う」は町並みではなく見本市になる。**同じ家が何軒か
#   ある**ことこそが「同一文化」の証拠 —— 標準形 f_a が三軒あって、
#   その間に金持ち・職人・新築・仕舞屋が挟まる、という比率が現実。
#
# 間隔は隣棟の**実際の屋根幅**（manifest の fw、出簷込み）から決めている。
# W だけで測ると足りない —— f_a は W7.6 でも屋根は 9.56 あるので、
# 最初 W 基準で並べたら隣同士の軒が 0.5m 食い込んでいた（俯視で発覚）。
# 軒先どうしのすき間：通常 0.2~0.4m（町家は軒を寄せて建てる）、
# 巷口 3.2m、側巷 2.0m。後列は前列の軒から 2m 以上あける。
const LOTS := [
	# ── 北側（正面朝街）──
	{"kind": "machiya_f_a", "x": -20.0, "back": 3.4, "side": 1, "yaw": 0.0,
	 "role": "shop", "biz": "yaoya", "why": "街西端。標準形＝基準。W7.6"},
	{"kind": "machiya_f_s", "x": -11.3, "back": 3.0, "side": 1, "yaw": 0.028,
	 "role": "house", "why": "仕舞屋 W5.2。両隣より低く狭い —— 間口の落差が"
		+ "町並みのリズム。退縮も 0.4m 少ない（店ではないのに前に出る家）"},
	# ⚠ 這裡是**巷口**：下一棟往東讓開 4.4m
	{"kind": "machiya_t_a", "x": -0.5, "back": 3.7, "side": 1, "yaw": -0.021,
	 "role": "house", "why": "**妻入り** W6.4。主街に破風と懸魚が正面を向く"
		+ "一軒 —— 軒の連なりに縦の切れ目が入る。退縮も一番深い"},
	{"kind": "machiya_f_o", "x": 9.7, "back": 3.1, "side": 1, "yaw": 0.016,
	 "role": "shop", "biz": "sakaya", "why": "大店 W9.8・卯建あり。街で一番高い民家。"
		+ "東の辻に近いほど地価が高い＝一番いい家が角に近い"},
	# ── 南側（正面朝街，yaw=PI）──
	{"kind": "machiya_f_n", "x": -15.6, "back": 3.3, "side": -1, "yaw": 0.0,
	 "role": "house", "why": "二階建て W8.0。対岸の一番西 —— 北側の f_a と"
		+ "向かい合って、同じ位置に違う高さが立つ"},
	{"kind": "machiya_w_a", "x": -5.6, "back": 3.5, "side": -1, "yaw": -0.024,
	 "role": "shop", "biz": "konya", "why": "工房 W7.2・煙出しあり。板戸張りで格子がない —— "
		+ "街から見て「ここは店ではない」が一目でわかる立面"},
	{"kind": "machiya_f_a", "x": 6.0, "back": 3.2, "side": -1, "yaw": 0.019,
	 "role": "house", "why": "標準形の二軒目。工房との間に 2.2m の側巷"},
	# ── 轉角：正面朝側街 ──
	{"kind": "machiya_f_a", "x": 21.6, "back": -5.4, "side": 1, "yaw": -PI * 0.5,
	 "role": "corner", "why": "轉角棟：正面朝側街（−x）、主街には妻側を見せる"},
	# ── 後排：只供天際線的第二層 ──
	{"kind": "machiya_f_o", "x": -6.5, "back": 17.8, "side": -1, "yaw": PI * 0.5 + 0.04,
	 "role": "back", "why": "後排。棟が街と直交＝前列の屋根の上に妻が重なる"},
	{"kind": "machiya_f_n", "x": 5.4, "back": 18.9, "side": -1, "yaw": PI * 0.5 - 0.03,
	 "role": "back", "why": "後排第二棟。6.42m で天際線の一番奥を持ち上げる"},
]

# 道具佈局：靠牆、簷下、不對稱。也是明表。
# kind: 掛在建物上的（暖簾／招牌／提灯）用 lot 的 facade 錨點；
#       地面的直接給座標（相對 lot 原點的本地偏移）。
const SHOP_PROPS := [
	{"m": "prop_crate", "dx": -2.9, "dz": 1.35, "yaw": 0.22, "s": 1.0},
	{"m": "prop_crate", "dx": -2.55, "dz": 1.05, "yaw": -0.35, "s": 0.86},
	{"m": "prop_basket", "dx": -3.5, "dz": 1.15, "yaw": 0.9, "s": 1.0},
	{"m": "prop_taru", "dx": 3.2, "dz": 1.25, "yaw": 0.0, "s": 1.0},
	{"m": "prop_taru", "dx": 3.62, "dz": 0.95, "yaw": 0.5, "s": 0.9},
]
const HOUSE_PROPS := [
	{"m": "prop_taru", "dx": 3.05, "dz": 1.05, "yaw": 0.3, "s": 0.78},
	{"m": "prop_basket", "dx": -3.2, "dz": 0.95, "yaw": -0.6, "s": 0.82},
]

# ══════════════════════════════════════════════════════════════════════
# PHASE 2.5：店先と暮らしの構図（三軒の hero building）
# ══════════════════════════════════════════════════════════════════════
#
# 上の SHOP_PROPS / HOUSE_PROPS は「どの店にも同じ荷物」を置く汎用表 ——
# 建築が良くなった今、それが「きれいな建築模型」に見える最後の理由になった。
# ここは**一軒ずつ、業を決めて**置く。
#
# ── 構図の原則（散らすのではなく、業を語る）────────────────────────
#   店   ：商品が**街を向いて**並ぶ。客の動線の上に置く。整っているほど格が高い
#   住   ：物は**壁際に寄せて**しまう。街に出さない
#   工房 ：物は**仕事のまわり**に置く。戸口と水場から手の届く範囲。整えない
# 同じ樽でも、積み方と置き場所で「売り物」と「道具」に分かれる。
#
# 座標は lot ローカル：dx = 間口方向（facade の右手が +）、dz = 街へ向かう向き、
# dy = 追加の高さ。⚠ hero の dx は**実際の間口に合わせて手で置いてある**ので、
# 汎用表と違って `lat`（間口比）の伸縮はかけない。
const BIZ := {
	# ── 八百屋・乾物屋：間口 7.6・出格子ひとつ・大戸口ひとつの標準形 ──
	# 一番普通の店。だから一番わかりやすく「商品が街に出ている」で語る。
	# 見世棚を出格子の下に出し、その上に竹籠、戸口の反対側に俵を積む。
	# 角度は少しずつ振ってある（毎日出し入れするものは尺で置かない）。
	"yaoya": {
		"why": "標準形＝一番ふつうの店。商品が街に出ていることだけで語る",
		# PHASE 2.6：構図が地面の高さに集中していた。簾（虫籠窓の前）と
		# 干し柿（軒下の橙の点列）で 店先 → 庇 → 上段 を縦につなぐ。
		# up = アンカーより上に伸びる分／drop = 下に垂れる分（天井との判定用）
		# dy = 天井からさらに下げる分。絶対高さはもう書かない
		"hang": [
			{"m": "prop_noren_kaki", "dx": 0.95, "dz": 0.84, "drop": 0.55},
			{"m": "prop_kanban", "dx": -1.60, "dz": 0.62, "drop": 0.85},
			{"m": "prop_chochin", "dx": -0.50, "dz": 0.62, "up": 0.16, "drop": 0.52},
			{"m": "prop_chochin", "dx": 2.40, "dz": 0.62, "up": 0.16, "drop": 0.52},
			{"m": "prop_sudare", "dx": -0.95, "dz": 0.26, "up": 0.08, "drop": 0.82,
			 "upper": true, "dy": 0.06},
			{"m": "prop_hoshigaki", "dx": -3.35, "dz": 0.58, "drop": 0.86},
			{"m": "prop_hoshigaki", "dx": 3.35, "dz": 0.58, "drop": 0.86},
		],
		"ground": [
			{"m": "prop_misedai", "dx": -2.85, "dz": 1.16, "yaw": 0.03, "s": 1.0},
			# 竹籠は棚の**上**（dy 0.44 = 平台の高さ）。地面に置いたら在庫、
			# 棚に載せたら商品 —— 同じ資産で意味が変わる
			# ⚠ 一回目は prop_basket を 0.6 倍に縮めて載せたら「金色の椀」に
			# 読めた。深い籠を縮めても浅い笊にはならない —— 専用の
			# prop_zaru（浅い・口が広い・暗い竹色・商品を盛ってある）に交換
			{"m": "prop_zaru", "dx": -3.30, "dz": 1.08, "yaw": 0.5, "s": 1.0, "dy": 0.44},
			{"m": "prop_zaru", "dx": -2.66, "dz": 1.14, "yaw": -0.9, "s": 0.92, "dy": 0.44},
			{"m": "prop_zaru", "dx": -2.06, "dz": 1.06, "yaw": 1.7, "s": 0.86, "dy": 0.44},
			{"m": "prop_tawara", "dx": 2.55, "dz": 1.02, "yaw": 0.08, "s": 1.0},
			{"m": "prop_tawara", "dx": 3.15, "dz": 1.08, "yaw": -0.05, "s": 1.0},
			{"m": "prop_tawara", "dx": 2.86, "dz": 1.05, "yaw": 0.03, "s": 1.0, "dy": 0.42},
			{"m": "prop_crate", "dx": 1.55, "dz": 1.38, "yaw": 0.22, "s": 0.82},
			{"m": "prop_kago", "dx": -1.05, "dz": 1.30, "yaw": -0.4, "s": 1.0},
		],
		"hand": [
			{"k": "broom", "dx": -3.72, "dz": 0.52},
			{"k": "bucket", "dx": 3.62, "dz": 0.88},
		],
	},
	# ── 酒屋：間口 9.8・出格子ふたつ・広い大戸口・卯建 ──
	# 金持ちの店。派手にするのではなく**整える**ことで格を出す ——
	# 樽はきちんと三角に積み、縁台は正面と平行、荷物の角度もほぼ揃える。
	# 杉玉は字の読めない客にも通じる、町で一番強い商標。
	"sakaya": {
		"why": "大店＝整っていることで格を出す。散らかっていたら金持ちに見えない",
		# PHASE 2.6：簾二枚を上段（虫籠窓の前）に。杉玉 → 暖簾 → 簾で
		# 立面が三段になる。数は増やさない —— 大店は整っているのが格
		"hang": [
			{"m": "prop_sugidama", "dx": -2.60, "dz": 0.52, "drop": 0.77},
			{"m": "prop_noren_ai", "dx": 0.00, "dz": 0.84, "drop": 0.62},
			{"m": "prop_kanban", "dx": 3.40, "dz": 0.62, "drop": 0.85},
			{"m": "prop_chochin", "dx": -1.75, "dz": 0.62, "up": 0.16, "drop": 0.52},
			{"m": "prop_chochin", "dx": 1.75, "dz": 0.62, "up": 0.16, "drop": 0.52},
			{"m": "prop_sudare", "dx": -1.90, "dz": 0.24, "up": 0.08, "drop": 0.82,
			 "upper": true, "dy": 0.34},
			{"m": "prop_sudare", "dx": 1.90, "dz": 0.24, "up": 0.08, "drop": 0.82,
			 "upper": true, "dy": 0.34},
		],
		"ground": [
			# 菰樽の三角積み：下三つ・上ふたつ。**角度を振らない**のが肝
			{"m": "prop_taru", "dx": -4.32, "dz": 1.12, "yaw": 0.0, "s": 1.0},
			{"m": "prop_taru", "dx": -3.70, "dz": 1.12, "yaw": 0.0, "s": 1.0},
			{"m": "prop_taru", "dx": -3.08, "dz": 1.12, "yaw": 0.0, "s": 1.0},
			{"m": "prop_taru", "dx": -4.01, "dz": 1.12, "yaw": 0.0, "s": 1.0, "dy": 0.76},
			{"m": "prop_taru", "dx": -3.39, "dz": 1.12, "yaw": 0.0, "s": 1.0, "dy": 0.76},
			{"m": "prop_kanban_tate", "dx": 2.35, "dz": 1.26, "yaw": -0.06, "s": 1.0},
			{"m": "prop_bench", "dx": 4.05, "dz": 1.05, "yaw": 0.01, "s": 1.0},
			{"m": "prop_taru", "dx": 3.05, "dz": 1.48, "yaw": 0.0, "s": 0.70},
			{"m": "prop_crate", "dx": -1.30, "dz": 1.46, "yaw": 0.05, "s": 0.90},
		],
		"hand": [
			{"k": "bucket", "dx": 4.72, "dz": 0.78},
			{"k": "planter", "dx": -4.74, "dz": 0.96},
		],
	},
	# ── 紺屋（藍染屋）：間口 7.2・板戸張り・広い大戸口・屋根に煙出し ──
	# 売る店ではない。だから暖簾を掛けない —— 代わりに藍甕と物干しで語る。
	# 煙出し（屋根）と薪（地面）が「火を使う家」の対、井戸が近いのは水を使うから。
	# 配置は整えない：全部が戸口から手の届く円の中にある、という置き方。
	"konya": {
		"why": "工房＝売り場ではない。暖簾を掛けず、道具の配置で仕事を語る",
		# PHASE 2.6：染め上げた反物を**高く**干す（軒下から 1.9m 垂れる）。
		# 地面の藍甕 → 中段の物干し → 上段の反物 → 屋根の煙出し、と
		# 「染めの仕事」が立面を縦に貫く
		# ⚠ 染め布は**庇の下**に吊る。庇と主屋根のあいだは約 1.09m しか
		# なく、1.26m の反物は物理的に入らない（Phase 2.6 はここを無視して
		# 庇を突き抜けていた）。戸口を塞がないよう両脇の板戸の前へ。
		"hang": [
			{"m": "prop_chochin", "dx": 1.30, "dz": 0.62, "up": 0.16, "drop": 0.52},
			{"m": "prop_somenuno", "dx": -2.55, "dz": 0.78, "drop": 1.30},
			{"m": "prop_somenuno", "dx": 2.62, "dz": 0.74, "drop": 1.30},
		],
		"ground": [
			# 藍甕は地面に埋めて使う（藍は温度が命）。戸口の前に一列 ——
			# 屋根の煙出しと直接つながる情報
			{"m": "prop_aigame", "dx": -1.32, "dz": 0.58, "yaw": 0.2, "s": 1.0},
			{"m": "prop_aigame", "dx": -0.44, "dz": 0.55, "yaw": -0.5, "s": 1.0},
			{"m": "prop_aigame", "dx": 0.44, "dz": 0.57, "yaw": 0.9, "s": 1.0},
			{"m": "prop_aigame", "dx": 1.32, "dz": 0.54, "yaw": -0.3, "s": 1.0},
			# 物干し：染めた反物。街から見える一番強い看板
			{"m": "prop_monohoshi", "dx": -2.75, "dz": 1.62, "yaw": 0.26, "s": 1.0},
			{"m": "prop_takigi", "dx": 2.95, "dz": 0.92, "yaw": 0.07, "s": 1.0},
			{"m": "prop_kanban_tate", "dx": -3.28, "dz": 0.82, "yaw": 0.12, "s": 0.88},
			{"m": "prop_taru", "dx": 1.95, "dz": 1.36, "yaw": 0.4, "s": 0.86},
			{"m": "prop_taru", "dx": 2.44, "dz": 1.52, "yaw": -0.7, "s": 0.74},
			{"m": "prop_crate", "dx": -2.30, "dz": 0.86, "yaw": -0.18, "s": 0.84},
		],
		"hand": [
			{"k": "bucket", "dx": 1.05, "dz": 1.24},
			{"k": "bucket", "dx": 1.48, "dz": 1.52},
			{"k": "broom", "dx": 3.44, "dz": 0.58},
		],
	},
}


func _init() -> void:
	var f := FileAccess.open("res://data/town_modules.json", FileAccess.READ)
	_mods = JSON.parse_string(f.get_as_text())["modules"]
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_nh = FastNoiseLite.new()
	_nh.frequency = 0.05
	_nh.seed = 500
	_rng.seed = SEED

	_root = Node3D.new()
	_root.name = "Slice"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)

	# ⚠ PHASE 1.7（material readability）：夯土在街景裡讀成**碎石場**。
	# 兩個原因，兩個修法：
	#   1. tint 太亮太白（0.78/0.70/0.58）→ 貼圖裡的白石粒直接曝出來。
	#      壓到 0.56/0.48/0.39：暗、暖、偏土色，白石粒退成暗紋。
	#   2. dirt_tile 預設 2.6（石粒約 10cm，一顆一顆數得出來）→ 拉到 5.4，
	#      石粒縮到 5cm 以下，變成「土裡的顆粒」而不是「地上的石頭」。
	# 「細石可以存在，但不能主導畫面」—— 就是這兩個數字。
	var terr := lib.terrain(OUT_DIR, HALF, 181, height_at, mask_at, "stone_flag",
		Color(0.62, 0.88, 0.55), "terrain_path", Color(0.56, 0.48, 0.39))
	var tmat: ShaderMaterial = terr.material_override
	tmat.set_shader_parameter("dirt_tile", 5.4)
	tmat.set_shader_parameter("path_tile", 2.2)
	lib.boundary(HALF - 2.0)
	_build_ground()
	_build_buildings()
	_build_props()
	_build_node()
	_build_planting()
	_build_people()
	_build_env()

	for line in _audit:
		print(line)
	var packed := PackedScene.new()
	packed.pack(_root)
	print("saved %s.tscn err=%d  節點 %d"
		% [MAP_ID, ResourceSaver.save(packed, OUT_DIR + MAP_ID + ".tscn"),
			_count(_root)])
	_write_meta()
	quit(0)


func _count(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _count(c)
	return t


# ══════════════════════════════════════════════════════════════════════
# 地形：**不是一塊平板**
# ══════════════════════════════════════════════════════════════════════
#
# 規格說「不要讓房子像模型直接放在平面上」。所以地面要有三件事：
#   1. 路是**壓實下陷**的（比兩側低 6~9cm）—— 幾百年走出來的
#   2. 路面有**車轍**：兩條沿 x 的淺溝，離路心 ±1.15m（板車的輪距）
#   3. 建物腳下有**微微墊高**：土在牆邊堆起來，不是切齊
func height_at(x: float, z: float) -> float:
	var h := _nh.get_noise_2d(x * 0.35, z * 0.35) * 0.13
	# 主街：路心下陷
	var dz: float = absf(z) - ROAD_W * 0.5
	var on_road: float = 1.0 - smoothstep(0.0, 2.6, maxf(dz, 0.0))
	# 側街
	var dx2: float = absf(x - SIDE_X) - 2.2
	on_road = maxf(on_road, (1.0 - smoothstep(0.0, 2.2, maxf(dx2, 0.0)))
		* clampf(1.0 - absf(z) / 26.0, 0.0, 1.0))
	h -= on_road * 0.075
	# 車轍：兩條淺溝。⚠ 深度只給 25mm —— 再深就變成排水溝而不是輪痕，
	# 而且玩家走過去會有「踩進坑」的觸感（膠囊會頓一下）。
	for rut in [-1.15, 1.15]:
		var d := absf(z - rut)
		h -= on_road * 0.025 * (1.0 - smoothstep(0.0, 0.34, d))
	# 建物腳下微微墊高：土堆在牆邊（**牆身**的 footprint，不是屋根の出）
	for L in LOTS:
		var b := _lot_box(L)
		var ctr: Vector2 = b[0]
		var hwv: Vector2 = b[2]
		var lx: float = absf(x - ctr.x) - hwv.x
		var lz: float = absf(z - ctr.y) - hwv.y
		h += 0.055 * (1.0 - smoothstep(0.0, 1.7, maxf(maxf(lx, lz), 0.0)))
	return h


func mask_at(x: float, z: float) -> Color:
	# R = 石板　G = 田（不用）　B = 巨觀明暗　A = 夯土
	#
	# ⚠ 規格：「目前大片亮色石板路太搶戲」。所以這裡**反過來**：
	# 主街整條是**夯土**，石板只出現在店門口那幾塊（人真的會踩的地方）。
	# village 的做法是「有店就有石板」鋪成一整片；這裡是「店**門口**才有」。
	var dz: float = absf(z) - ROAD_W * 0.5
	var road: float = 1.0 - smoothstep(0.0, 2.2, maxf(dz, 0.0))
	var dx2: float = absf(x - SIDE_X) - 2.2
	road = maxf(road, (1.0 - smoothstep(0.0, 1.8, maxf(dx2, 0.0)))
		* clampf(1.0 - absf(z) / 26.0, 0.0, 1.0))
	var dirt := road
	# 店門口的敷石：只在 shop 的**門前** 2.4m 見方
	# ⚠ PHASE 2 で直した：`fz = c.y − side*4.9` は建物の**中**を指していた
	#   （原點が正面の面なので、そこから 4.9m 奥＝土間の真ん中）。
	#   だから敷石は Phase 1.5 からずっと床下に敷かれていて、街には
	#   一度も出ていない。門前は `c` から正面方向へ 0.9m。
	var stone := 0.0
	for L in LOTS:
		if String(L.role) != "shop":
			continue
		var c := _lot_center(L)
		var m: Dictionary = _mods[String(L.kind)]
		var yaw := _lot_yaw(L)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var rgt := Vector2(cos(yaw), -sin(yaw))
		var dx: float = float(m.get("facade", {}).get("door_x", 0.0))
		var dp := c + rgt * dx + fwd * 0.95
		var dd: float = (Vector2(x, z) - dp).length()
		# ⚠ 上限 0.55。門前の敷石が街に出た**初めてのラウンド**で判ったこと：
		# 1.0 まで振ると、暗い夯土の中に真っ白な板が浮いて「貼り付けた
		# テクスチャ」に読める。0.55 なら踏み固められた土の下から石が
		# 覗いている、という混ざり方になる。石は「ある」より「透ける」
		stone = maxf(stone, 0.55 * (1.0 - smoothstep(0.9, 1.8, dd)))
	# 井邊也鋪石（打水的地方一定是硬鋪面）
	if Vector2(x - 17.6, z - 0.4).length() < 3.4:
		stone = maxf(stone, 1.0 - smoothstep(2.2, 3.4, Vector2(x - 17.6, z - 0.4).length()))
	dirt = maxf(dirt * (1.0 - stone), 0.0)
	# 屋邊的踏み固め：牆腳一圈也是土（沒有草會長在天天走的地方）
	for L in LOTS:
		# ⚠ 第一版只鋪到牆外 1.5m，實測房子腳下還看得到亮綠草地 —— 房子讀成
		# 「放在草皮上的模型」，正是規格要解的那件事。加寬到 3.4m，而且
		# **貼牆那一圈給滿**（0.95）：天天有人走的地方不會有草。
		# PHASE 2：決め打ちの 5.4/5.2 をやめて実際の屋根 footprint から取る。
		var b2 := _lot_box(L)
		var ctr2: Vector2 = b2[0]
		var hrv: Vector2 = b2[1]
		var lx: float = absf(x - ctr2.x) - hrv.x
		var lz: float = absf(z - ctr2.y) - hrv.y
		var od: float = maxf(maxf(lx, lz), 0.0)
		dirt = maxf(dirt, 0.95 * (1.0 - smoothstep(0.0, 3.4, od)))
	var macro := clampf(_nh.get_noise_2d(x * 0.22, z * 0.22) * 0.5 + 0.5, 0.0, 1.0)
	return Color(stone, 0.0, macro, clampf(dirt, 0.0, 1.0))


func _lot_center(L: Dictionary) -> Vector2:
	## 地塊原點：模組的正面在原點、量體往背面長。
	## side=+1（北側）→ 正面朝 +z，原點在 z = −back。
	if String(L.role) == "corner":
		return Vector2(float(L.x), float(L.back))
	return Vector2(float(L.x), -float(L.side) * float(L.back))


func _lot_yaw(L: Dictionary) -> float:
	return float(L.yaw) + (PI if int(L.side) < 0
		and String(L.role) != "corner" else 0.0)


# ══════════════════════════════════════════════════════════════════════
# PHASE 2.6b：吊り物の天井 —— 屋根面から高さを**計算する**
# ══════════════════════════════════════════════════════════════════════
#
# Phase 2.6 は暖簾・簾・染め布の高さを手で決めた。結果、庇の前桁が暖簾の
# 上帯を貫き、染め布が庇を突き抜けた。原因は配置側が屋根面の高さを
# 知らなかったこと —— 目分量で 2.08 や +1.18 と書いていた。
# manifest（make_machiya が書く）に庇と軒の面が入ったので、ここは全部
# 計算にする。手で決めるのは「どの天井の下か」と「どれだけ内側か」だけ。
const HANG_GAP := 0.035        # 天井とのすき間（cm 単位の余裕）

## 庇の下端（lot ローカル・地面から）。dz = 壁面からの張り出し。
func _hisashi_bottom(m: Dictionary, dz: float) -> float:
	var h: Dictionary = m.get("facade", {}).get("hisashi", {})
	if h.is_empty():
		return 2.05
	var d: float = clampf(dz, 0.0, float(h.proj))
	return float(h.z) - d * tan(deg_to_rad(float(h.slope))) - float(h.thick)

## 庇の上端（上段に吊る物の「床」）
func _hisashi_top(m: Dictionary, dz: float) -> float:
	return _hisashi_bottom(m, dz) + float(m.get("facade", {})
		.get("hisashi", {}).get("thick", 0.055)) + 0.024

## 主屋根の軒裏（上段の天井）。⚠ 妻入りは軒の向きが 90° 違うので使わない。
func _roof_soffit(m: Dictionary, dz: float) -> float:
	var e: Dictionary = m.get("facade", {}).get("eave", {})
	if e.is_empty():
		return 3.40
	return float(e.z_wall) - dz * tan(deg_to_rad(float(e.pitch))) - float(e.thick)

## 吊り物の張り出しを「前桁より内側」に丸める。
## 前桁は先端から beam_back の帯を占めるので、そこへ吊ると布が桁に刺さる。
func _hang_dz(m: Dictionary, dz: float) -> float:
	var h: Dictionary = m.get("facade", {}).get("hisashi", {})
	if h.is_empty():
		return dz
	return minf(dz, float(h.proj) - float(h.get("beam_back", 0.15)))

## 吊り物のアンカー高さ。`up` = アンカーより上に伸びる分（提灯の紐など）、
## `drop` = 下に垂れる分。回傳が天井にぶつからない最大の高さ。
func _hang_y(m: Dictionary, dz: float, up: float, drop: float,
		under_roof: bool) -> float:
	if under_roof:
		var top := _roof_soffit(m, dz) - HANG_GAP - up
		# 上段の物は庇の**上**にも乗ってはいけない
		var floor_y := _hisashi_top(m, dz) + HANG_GAP + drop
		return maxf(top, floor_y) if floor_y <= top else top
	return _hisashi_bottom(m, dz) - HANG_GAP - up


## 地塊の**実際の**footprint。回傳 [量體中心, 屋根まで含む半徑, 壁の半徑]。
##
## ⚠ PHASE 2 で足した。Phase 1.5~1.7 は地面の処理が全部
##   「原點から半徑 5.0~5.4」の決め打ちで、二つ壊れていた：
##     1. 原點は**正面の面**であって中心ではない（`_lot_center` の docstring
##        にそう書いてあるのに、使う側が中心のつもりで使っていた）。
##        だから牆腳の土帶も踏石も、半分は道路に、半分は建物の中に落ちていた
##        —— Phase 1.7 で「白石が街に散っている」と直したのは症状のほうで、
##        原因はこれ。
##     2. 6 種類の面寬・進深がバラバラになった今、決め打ちの 5.0 は
##        f_s（5.2×6.8）には大きすぎ f_o（9.8×8.6）には小さすぎる。
##   yaw で回った地塊（角地・後列）は W と D が入れ替わるので、
##   軸平行の半徑は |cos|/|sin| で混ぜて出す。
func _lot_box(L: Dictionary) -> Array:
	var c := _lot_center(L)
	var m: Dictionary = _mods[String(L.kind)]
	var yaw := _lot_yaw(L)
	var fwd := Vector2(sin(yaw), cos(yaw))          # 模組正面朝這個方向
	var ca := absf(cos(yaw))
	var sa := absf(sin(yaw))
	var rw: float = float(m.fw) * 0.5               # 含出簷
	var rd: float = float(m.fd) * 0.5
	var ww: float = float(m.w) * 0.5                # 牆身 footprint
	var wd: float = float(m.d) * 0.5
	return [c - fwd * wd,
		Vector2(rw * ca + rd * sa, rw * sa + rd * ca),
		Vector2(ww * ca + wd * sa, ww * sa + wd * ca)]


# ══════════════════════════════════════════════════════════════════════
# 地面層：石溝・路邊石・踏石・牆腳碎石
# ══════════════════════════════════════════════════════════════════════
func _build_ground() -> void:
	var g := lib.add(_root, Node3D.new(), "地面層") as Node3D
	# PHASE 1.7：石材整組降亮度。夯土壓暗之後，原本的亮灰石在深色土路上
	# 變成一顆一顆的白斑 —— 石頭本身沒變大，是**對比**讓它搶了主街。
	# 街上的石頭是被踩了幾百年的，不會是新採的亮面
	var stone := lib.pbr("slice_kerb", "stone_wall", 0.32, Color(0.62, 0.60, 0.56))
	var dark := lib.pbr("slice_gutter", "stone_wall", 0.36, Color(0.44, 0.44, 0.43))
	var flag := lib.pbr("slice_flag", "stone_flag", 0.30, Color(0.64, 0.62, 0.57))
	# ── 石溝：路兩側各一條。町家的雨水從簷口落下就進這條溝 ──
	var gut: Array[Transform3D] = []
	var gm := BoxMesh.new()
	gm.size = Vector3(1.0, 0.26, 0.34)
	gm.material = dark
	var krb: Array[Transform3D] = []
	var km := BoxMesh.new()
	km.size = Vector3(1.0, 0.22, 0.16)
	km.material = stone
	var x := -HALF + 8.0
	while x < HALF - 8.0:
		for sd in [-1.0, 1.0]:
			var zz: float = sd * (ROAD_W * 0.5 + 0.30)
			var y := height_at(x, zz)
			gut.append(Transform3D(Basis(), Vector3(x, y - 0.05, zz)))
			krb.append(Transform3D(Basis(), Vector3(x, y + 0.02, zz + sd * 0.26)))
		x += 1.0
	_mm(g, "MM_石溝", gm, gut)
	_mm(g, "MM_路邊石", km, krb)
	# ── 踏石：只在幾個「人會踏」的點，不鋪成路 ──
	# ⚠ 這是跟 village 最大的差別。village 是整條街鋪石板；這裡是夯土為主，
	# 石頭只出現在門口、井邊、跨溝的地方 —— 石頭少了，土才讀得出來是土。
	var step: Array[Transform3D] = []
	var sm := BoxMesh.new()
	sm.size = Vector3(0.72, 0.11, 0.62)
	sm.material = flag
	for L in LOTS:
		if String(L.role) == "corner" or String(L.role) == "back":
			continue
		# 跨石溝的踏石（從**門口**踏出來到街上）
		# ⚠ PHASE 2：これも `− side*4.9` で建物の中に置かれていた。門は
		#   manifest の facade.door_x にある —— そこから正面方向へ並べる。
		var c := _lot_center(L)
		var m: Dictionary = _mods[String(L.kind)]
		var yaw := _lot_yaw(L)
		var fwd := Vector2(sin(yaw), cos(yaw))
		var rgt := Vector2(cos(yaw), -sin(yaw))
		var dx: float = float(m.get("facade", {}).get("door_x", 0.0))
		for k in 3:
			var p := c + rgt * (dx - 1.1 + float(k) * 1.1) \
				+ fwd * (0.62 + float(k % 2) * 0.24)
			step.append(Transform3D(
				Basis(Vector3.UP, yaw + _rng.randf_range(-0.09, 0.09)),
				Vector3(p.x, height_at(p.x, p.y) + 0.03, p.y)))
	_mm(g, "MM_踏石", sm, step)
	# ── 牆腳碎石（犬走り的簡版）+ 排水點 ──
	# ⚠ PHASE 1.7：這一叢是「碎石場」觀感的真兇，不是地形貼圖。
	#   ・尺寸 0.10–0.20（實測 20–40cm）→ 0.06–0.11，回到「碎」石的量級
	#   ・每棟 26 顆 → 15 顆
	#   ・材質從 rock_mat_dry（albedo 1.14 亮白，village 共用）換成本場景專用的
	#     暗土色。不動 rock_mat_dry 是因為 village 的河石在用它
	# ⚠ PHASE 2：位置の根本を直した。Phase 1.7 は「半徑 5.4 → 5.05」で
	#   街に散るのを抑えたが、そもそも中心が**正面の面**だったので、
	#   円の半分は道路、半分は建物の中だった。実際の壁 footprint に沿った
	#   楕円に置き換える —— 名前どおり「**牆腳**碎石」になる。
	var peb: Array[Transform3D] = []
	var pm: Mesh = lib.blob_mesh(41, 0.5, 0.22)
	for L in LOTS:
		var b := _lot_box(L)
		var ctr: Vector2 = b[0]
		var hwv: Vector2 = b[2]
		for k in 15:
			var a := TAU * float(k) / 15.0
			var jit := _rng.randf_range(0.0, 0.30)
			var px: float = ctr.x + cos(a) * (hwv.x + 0.30 + jit)
			var pz: float = ctr.y + sin(a) * (hwv.y + 0.30 + jit)
			var s := _rng.randf_range(0.06, 0.11)
			peb.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					* Basis.from_scale(Vector3(s, s * 0.55, s)),
				Vector3(px, height_at(px, pz) + 0.015, pz)))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = lib.make_multimesh(pm, peb, [], OUT_DIR + "gen/mm_pebble.res")
	pmi.material_override = lib.pbr("slice_pebble", "stone_wall", 1.4,
		Color(0.56, 0.52, 0.46))
	lib.add(g, pmi, "MM_牆腳碎石")
	_audit.append("地面層：石溝 %d 節・路邊石 %d・踏石 %d・牆腳碎石 %d"
		% [gut.size(), krb.size(), step.size(), peb.size()])


func _mm(g: Node3D, name: String, mesh: Mesh, list: Array[Transform3D]) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = lib.make_multimesh(mesh, list, [],
		OUT_DIR + "gen/mm_%s.res" % name.trim_prefix("MM_"))
	lib.add(g, mmi, name)


# ══════════════════════════════════════════════════════════════════════
# 建築
# ══════════════════════════════════════════════════════════════════════
func _build_buildings() -> void:
	var g := lib.add(_root, Node3D.new(), "建築") as Node3D
	var body := StaticBody3D.new()
	body.name = "建築碰撞"
	_root.add_child(body)
	body.owner = _root
	var batch := {}
	for i in LOTS.size():
		var L: Dictionary = LOTS[i]
		var c := _lot_center(L)
		var yaw: float = float(L.yaw) + (PI if int(L.side) < 0
			and String(L.role) != "corner" else 0.0)
		var m: Dictionary = _mods[String(L.kind)]
		var y := height_at(c.x, c.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.y))
		if not batch.has(String(L.kind)):
			batch[String(L.kind)] = [] as Array[Transform3D]
		batch[String(L.kind)].append(xf)
		# 碰撞：牆身 footprint（不含出簷），跟 village 同一條規矩
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(m.w), float(m.h), float(m.d))
		sh.shape = bx
		sh.transform = Transform3D(Basis(Vector3.UP, yaw),
			Vector3(c.x, y + float(m.h) * 0.5, c.y)
			+ Vector3(sin(yaw), 0, cos(yaw)) * (-float(m.d) * 0.5))
		body.add_child(sh)
		sh.owner = _root
	var names: Array = batch.keys()
	names.sort()
	for k in names:
		# ⚠ 語意材質模組（新版 machiya_f_a）要走 semantic_mesh，
		# legacy 的單 surface 模組走 prop_mesh —— 判斷依據是 surface 數，
		# 跟 gen_town._emit_batches 同一條規則。
		var probe: Array = lib.semantic_mesh(String(_mods[k]["glb"]))
		var mesh: Mesh = probe[0]
		if mesh.get_surface_count() <= 1:
			mesh = lib.prop_mesh(String(_mods[k]["glb"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, batch[k], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		# PHASE 1.7：distance simplification。glTF importer 的 generate_lods 已經
		# 幫每個 surface 生了 LOD 鏈，但預設 lod_bias=1.0 要退到很遠才切 ——
		# 屋頂那 31 條桟在俯視距離全部保留，就是遠景摩爾紋的幾何成因。
		# 0.5 = 提早一倍距離降級；牆身輪廓在那個距離只剩幾十像素，看不出差別
		mmi.lod_bias = 0.5
		lib.add(g, mmi, "MM_%s" % k)
	# PHASE 2：production kit は 6 種。legacy blockout は slice には一棟もない
	# （Phase 1.6 の隔離を維持）—— 内訳を種類ごとに出して、審図のときに
	# 「何がどれだけ立っているか」が絵と突き合わせられるようにする。
	var breakdown: Array[String] = []
	for k in names:
		breakdown.append("%s×%d" % [String(k).trim_prefix("machiya_"),
			batch[k].size()])
	var legacy := 0
	for k in names:
		if int(_mods[k].get("faces", 0)) < 1000:      # blockout は数百面
			legacy += batch[k].size()
	_audit.append("建築 %d 棟 / %d 種 production 模組（%s）・legacy blockout %d 棟"
		% [LOTS.size(), names.size(), ", ".join(breakdown), legacy])


# ══════════════════════════════════════════════════════════════════════
# 生活道具層
# ══════════════════════════════════════════════════════════════════════
#
# 規格：「不要一次做幾百種 props，重點是讓街道開始有『有人生活』的感覺」。
# 所以只用**既有的** glb（barrel / crate / basket / bench / noren / chochin /
# kanban），缺的幾件（水桶・掃帚・柴堆・盆栽・晾衣・地藏）直接在這裡用
# lib.box/cyl 疊出來 —— 不開新 glb、不開新材質。
func _build_props() -> void:
	var g := lib.add(_root, Node3D.new(), "道具") as Node3D
	var batch := {}
	var put := func(m: String, t: Transform3D) -> void:
		if not batch.has(m):
			batch[m] = [] as Array[Transform3D]
		batch[m].append(t)
	var n_hang := 0
	var n_biz := 0
	for L in LOTS:
		var c := _lot_center(L)
		var role := String(L.role)
		var m: Dictionary = _mods[String(L.kind)]
		var sd: float = float(L.side) if role != "corner" else 1.0
		var yaw := _lot_yaw(L)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))       # 模組正面朝這個方向
		var rgt := Vector3(cos(yaw), 0, -sin(yaw))
		var base := Vector3(c.x, 0, c.y)
		# ⚠ PHASE 2：道具の横方向オフセットは W=7.6（半幅 3.8）を前提に
		# 手で置いた値。間口が 5.2~9.8 に散った今、そのままだと仕舞屋の
		# 荷物が隣の家の前に置かれる。半幅の比で伸縮させる。
		var lat: float = float(m.w) * 0.5 / 3.8
		var fz: float = float(m.get("facade", {}).get("beam_z", 1.95))
		# ── PHASE 2.5：hero building は業ごとの構図表を使う ──
		# 汎用表（SHOP_PROPS / HOUSE_PROPS）は「どの店にも同じ荷物」なので、
		# 建築が良くなった今それ自体が「模型」に見える理由になっている。
		# biz が付いている lot は汎用表を**通さず**、一軒ぶんの構図で置く。
		if L.has("biz"):
			var spec: Dictionary = BIZ[String(L.biz)]
			for h in spec["hang"]:
				# PHASE 2.6b：dz は前桁より内側へ丸め、高さは天井から逆算。
				# `dy` は**天井からどれだけ下げるか**（＋で下がる）に意味が
				# 変わった —— 絶対高さを手で書くのをやめたので
				var hz := _hang_dz(m, float(h.dz))
				var hp: Vector3 = base + rgt * float(h.dx) + fwd * hz
				hp.y = height_at(hp.x, hp.z) + _hang_y(m, hz,
					float(h.get("up", 0.0)), float(h.get("drop", 0.0)),
					bool(h.get("upper", false))) - float(h.get("dy", 0.0))
				put.call(String(h.m), Transform3D(Basis(Vector3.UP, yaw), hp))
				n_hang += 1
			for gp in spec["ground"]:
				var q: Vector3 = base + rgt * float(gp.dx) + fwd * float(gp.dz)
				q.y = height_at(q.x, q.z) + float(gp.get("dy", 0.0))
				var sc := float(gp.get("s", 1.0))
				put.call(String(gp.m), Transform3D(
					Basis(Vector3.UP, yaw + float(gp.get("yaw", 0.0)))
						* Basis.from_scale(Vector3(sc, sc, sc)), q))
			for hd in spec["hand"]:
				var hq: Vector3 = base + rgt * float(hd.dx) + fwd * float(hd.dz)
				match String(hd.k):
					"bucket": _bucket(g, hq, yaw)
					"broom": _broom(g, hq, yaw)
					"planter": _planter(g, hq, yaw)
					"firewood": _firewood(g, hq, yaw)
			n_biz += 1
			continue
		# ── 掛的：暖簾（店）／招牌（店）／提灯（店，兩盞）──
		if role == "shop":
			# PHASE 2.6：布 v2（村は旧 prop_noren_a/b のまま。slice だけ参照替え）
			var nk := "prop_noren_ai" if int(L.x) % 2 == 0 else "prop_noren_kaki"
			var dx: float = float(m.get("facade", {}).get("door_x", 0.0))
			# PHASE 2.6b：hero と同じく庇の面から逆算する
			var nz := _hang_dz(m, 0.84)
			var p := base + rgt * dx + fwd * nz
			p.y = height_at(p.x, p.z) + _hang_y(m, nz, 0.0, 0.62, false)
			put.call(nk, Transform3D(Basis(Vector3.UP, yaw), p))
			n_hang += 1
			var kz := _hang_dz(m, 0.62)
			var kp := base + rgt * (dx - 2.5 * lat) + fwd * kz
			kp.y = height_at(kp.x, kp.z) + _hang_y(m, kz, 0.0, 0.85, false)
			put.call("prop_kanban", Transform3D(Basis(Vector3.UP, yaw), kp))
			n_hang += 1
			for s2 in [-1.0, 1.0]:
				var cz := _hang_dz(m, 0.62)
				var cp: Vector3 = base + rgt * (dx + s2 * 1.55 * lat) + fwd * cz
				cp.y = height_at(cp.x, cp.z) + _hang_y(m, cz, 0.16, 0.52, false)
				put.call("prop_chochin", Transform3D(Basis(Vector3.UP, yaw), cp))
				n_hang += 1
		# ── 地上的：靠牆、簷下 ──
		var table: Array = SHOP_PROPS if role == "shop" else HOUSE_PROPS
		for pr in table:
			var p2 := base + rgt * (float(pr.dx) * lat) + fwd * float(pr.dz)
			p2.y = height_at(p2.x, p2.z)
			var s3 := float(pr.s)
			put.call(String(pr.m), Transform3D(
				Basis(Vector3.UP, yaw + float(pr.yaw)) * Basis.from_scale(Vector3(s3, s3, s3)),
				p2))
		# ── 手工的小件（不開新 glb）──
		if role == "house":
			_bucket(g, base + rgt * (-3.6 * lat) + fwd * 1.1, yaw)
			_broom(g, base + rgt * (3.4 * lat) + fwd * 0.55, yaw)
			_firewood(g, base + rgt * (-4.5 * lat) + fwd * -1.2, yaw + 0.1)
			_planter(g, base + rgt * (2.4 * lat) + fwd * 1.15, yaw)
			_laundry(g, base + rgt * (0.4 * lat) + fwd * -6.2, yaw)
		elif role == "shop":
			_planter(g, base + rgt * (-4.2 * lat) + fwd * 1.0, yaw)
			_bucket(g, base + rgt * (4.0 * lat) + fwd * 0.9, yaw)
	var mods: Array = batch.keys()
	mods.sort()
	var total := 0
	for k in mods:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(
			lib.prop_mesh("res://assets/models/%s.glb" % k), batch[k], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		lib.add(g, mmi, "MM_%s" % k)
		total += batch[k].size()
	_audit.append("道具：%d 件 / %d 種模組（吊掛 %d）+ 手工小件・業別構圖 %d 軒"
		% [total, mods.size(), n_hang, n_biz])


## ── 手工小件：用既有材質疊出來，不開新 glb ──
func _bucket(g: Node3D, p: Vector3, yaw: float) -> void:
	var w := lib.pbr("slice_wood", "planks", 0.55, Color(0.66, 0.58, 0.48))
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var y := height_at(p.x, p.z)
	lib.cyl(g, "水桶", 0.16, 0.14, 0.30, w, Vector3(p.x, y + 0.15, p.z), 10)
	lib.cyl(g, "桶箍", 0.165, 0.165, 0.03, d, Vector3(p.x, y + 0.26, p.z), 10)
	var h := lib.cyl(g, "桶提手", 0.012, 0.012, 0.34, d, Vector3(p.x, y + 0.32, p.z), 5)
	h.rotation = Vector3(0, yaw, PI * 0.5)


func _broom(g: Node3D, p: Vector3, yaw: float) -> void:
	## 掃帚**靠著牆**站 —— 立在空地上會像插在地裡的棍子
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	# ⚠ PHASE 2.5：uv 0.5（tile 2m）だと 0.2m の穂は貼図の一点しか拾わず
	# 均一色になり、明るいティントと合わさって**白いカプセル**に読めていた。
	# 街のどのカットにも写り込む位置にあったので影響が大きい。
	var st := lib.pbr("slice_straw", "roof_thatch", 2.6, Color(0.46, 0.40, 0.26))
	var y := height_at(p.x, p.z)
	var pole := lib.cyl(g, "掃帚柄", 0.018, 0.020, 1.35, d, Vector3(p.x, y + 0.66, p.z), 6)
	pole.rotation = Vector3(0.16 * cos(yaw), 0, -0.16 * sin(yaw))
	lib.cyl(g, "掃帚穗", 0.10, 0.05, 0.34, st,
		Vector3(p.x + sin(yaw) * 0.10, y + 0.17, p.z + cos(yaw) * 0.10), 7)


func _firewood(g: Node3D, p: Vector3, yaw: float) -> void:
	## 柴堆：疊三層，每層 4~5 根，上層錯開
	var d := lib.pbr("slice_log", "dark_wood", 0.42, Color(0.48, 0.44, 0.40))
	var y := height_at(p.x, p.z)
	for row in 3:
		var n := 5 - row
		for k in n:
			var off := (float(k) - float(n - 1) * 0.5) * 0.17
			var lg := lib.cyl(g, "柴_%d_%d" % [row, k], 0.075, 0.080, 1.05, d,
				Vector3(p.x + cos(yaw) * off, y + 0.085 + float(row) * 0.16,
					p.z - sin(yaw) * off), 6)
			lg.rotation = Vector3(0, yaw, PI * 0.5)


func _planter(g: Node3D, p: Vector3, _yaw: float) -> void:
	var st := lib.pbr("slice_pot", "arakabe", 0.42, Color(0.60, 0.46, 0.38))
	var y := height_at(p.x, p.z)
	lib.cyl(g, "盆", 0.19, 0.15, 0.24, st, Vector3(p.x, y + 0.12, p.z), 9)
	var leaf := MeshInstance3D.new()
	leaf.mesh = lib.tuft_mesh(9, 0.42, 0.26, Color(0.14, 0.28, 0.12), Color(0.30, 0.50, 0.20))
	leaf.material_override = lib.foliage_vc_mat()
	leaf.position = Vector3(p.x, y + 0.24, p.z)
	lib.add(g, leaf, "盆栽")


func _laundry(g: Node3D, p: Vector3, yaw: float) -> void:
	## 晾衣：兩根竿 + 三塊布。⚠ 掛在**後院**（fwd 的反方向 6.2m），
	## 不是掛在店面上 —— 商業立面上晾衣服是住宅的語彙，位置錯了就穿幫。
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var cloth := [lib.pbr("slice_cloth_a", "shoji", 0.30, Color(0.72, 0.76, 0.86)),
		lib.pbr("slice_cloth_b", "shoji", 0.30, Color(0.86, 0.78, 0.66)),
		lib.pbr("slice_cloth_c", "shoji", 0.30, Color(0.66, 0.70, 0.64))]
	var y := height_at(p.x, p.z)
	var rgt := Vector3(cos(yaw), 0, -sin(yaw))
	for s in [-1.0, 1.0]:
		var q: Vector3 = p + rgt * (s * 1.75)
		lib.cyl(g, "衣竿柱_%d" % int(s + 1.0), 0.035, 0.040, 1.75, d,
			Vector3(q.x, y + 0.87, q.z), 6)
	var bar := lib.cyl(g, "衣竿", 0.028, 0.028, 3.5, d, Vector3(p.x, y + 1.70, p.z), 6)
	bar.rotation = Vector3(0, yaw, PI * 0.5)
	for k in 3:
		var off := (float(k) - 1.0) * 0.95
		var q2 := p + rgt * off
		lib.box(g, "衣_%d" % k, Vector3(0.62, 0.72, 0.03), cloth[k],
			Vector3(q2.x, y + 1.32, q2.z)).rotation.y = yaw


# ══════════════════════════════════════════════════════════════════════
# 小型節點：井戶 + 地藏（幻想鄉提示的那 10%）
# ══════════════════════════════════════════════════════════════════════
func _build_node() -> void:
	var g := lib.add(_root, Node3D.new(), "節點") as Node3D
	var stone := lib.pbr("slice_kerb", "stone_wall", 0.32, Color(0.80, 0.80, 0.78))
	var d := lib.pbr("slice_dark", "dark_wood", 0.45, Color(0.40, 0.42, 0.40))
	var kaw := lib.pbr("slice_kawara", "roof_kawara", 0.22, Color(0.78, 0.84, 0.98))
	# ── 井戶 ──
	var wx := 17.6
	var wz := 0.4
	var wy := height_at(wx, wz)
	for k in 12:
		var a := TAU * float(k) / 12.0
		lib.box(g, "井筒_%d" % k, Vector3(0.30, 0.62, 0.22), stone,
			Vector3(wx + cos(a) * 0.72, wy + 0.31, wz + sin(a) * 0.72)).rotation.y = -a
	lib.cyl(g, "井口", 0.60, 0.60, 0.06, d, Vector3(wx, wy + 0.63, wz), 12)
	for s in [-1.0, 1.0]:
		lib.box(g, "井桁柱_%d" % int(s + 1.0), Vector3(0.10, 1.85, 0.10), d,
			Vector3(wx + s * 0.78, wy + 0.92, wz))
	lib.box(g, "井桁梁", Vector3(1.86, 0.11, 0.11), d, Vector3(wx, wy + 1.80, wz))
	for s2 in [-1.0, 1.0]:
		var r := lib.box(g, "井屋根_%d" % int(s2 + 1.0), Vector3(2.20, 0.09, 0.86), kaw,
			Vector3(wx, wy + 2.02, wz + s2 * 0.36))
		r.rotation.x = s2 * -0.44
	var rope := lib.cyl(g, "釣瓶繩", 0.012, 0.012, 1.0, d, Vector3(wx, wy + 1.26, wz), 5)
	rope.rotation = Vector3(0, 0, 0)
	_bucket(g, Vector3(wx + 1.15, 0, wz - 0.9), 0.6)
	# ── 地藏（路口的小神龕）+ 護符 + 一株不尋常的植物 ──
	# 規格：90% 傳統聚落 / 10% 幻想鄉提示。所以只有**這一組**，而且藏在
	# 路口的角落，不放在街心 —— 幻想鄉的怪東西是路過才注意到的，不是展示品。
	var jx := 20.6
	var jz := -6.2
	var jy := height_at(jx, jz)
	lib.box(g, "地藏台座", Vector3(0.72, 0.26, 0.62), stone, Vector3(jx, jy + 0.13, jz))
	lib.cyl(g, "地藏身", 0.17, 0.20, 0.58, stone, Vector3(jx, jy + 0.55, jz), 10)
	lib.cyl(g, "地藏頭", 0.155, 0.155, 0.26, stone, Vector3(jx, jy + 0.95, jz), 10)
	# 前掛（紅圍兜）—— 地藏一眼認得出來就是靠這塊布
	lib.box(g, "地藏前掛", Vector3(0.32, 0.30, 0.04),
		lib.pbr("slice_bib", "shoji", 0.30, Color(0.86, 0.34, 0.30)),
		Vector3(jx, jy + 0.62, jz - 0.19))
	for s3 in [-1.0, 1.0]:
		var rf := lib.box(g, "祠屋根_%d" % int(s3 + 1.0), Vector3(1.05, 0.07, 0.52), kaw,
			Vector3(jx, jy + 1.30, jz + s3 * 0.21))
		rf.rotation.x = s3 * -0.50
	for s4 in [-1.0, 1.0]:
		lib.box(g, "祠柱_%d" % int(s4 + 1.0), Vector3(0.08, 1.22, 0.08), d,
			Vector3(jx + s4 * 0.44, jy + 0.61, jz + 0.20))
	# 護符：貼在祠柱上的一張紙
	lib.box(g, "護符", Vector3(0.09, 0.24, 0.012),
		lib.pbr("slice_ofuda", "shoji", 0.30, Color(0.98, 0.96, 0.88)),
		Vector3(jx - 0.44, jy + 0.92, jz + 0.145))
	# 奇怪的告示（村的公告板 —— 上面寫什麼看不清，但它就是有）
	var bx := 15.4
	var bz := -4.6
	var by := height_at(bx, bz)
	for s5 in [-1.0, 1.0]:
		lib.box(g, "高札柱_%d" % int(s5 + 1.0), Vector3(0.09, 1.55, 0.09), d,
			Vector3(bx + s5 * 0.52, by + 0.78, bz))
	lib.box(g, "高札板", Vector3(1.26, 0.72, 0.05),
		lib.pbr("slice_board", "planks", 0.5, Color(0.70, 0.62, 0.50)),
		Vector3(bx, by + 1.18, bz))
	lib.box(g, "高札屋根", Vector3(1.44, 0.06, 0.30), kaw, Vector3(bx, by + 1.60, bz))
	_audit.append("節點：井戶（井桁＋屋根＋釣瓶）・地藏祠（前掛＋護符）・高札")


func _build_planting() -> void:
	var g := lib.add(_root, Node3D.new(), "植栽") as Node3D
	# 牆腳的草與雜草：**只長在人不走的地方**（建物之間的縫、牆角、溝邊）
	var tuft := lib.tuft_mesh(7, 0.30, 0.22, Color(0.16, 0.30, 0.12), Color(0.34, 0.54, 0.22))
	var weed := lib.tuft_mesh(5, 0.44, 0.16, Color(0.20, 0.28, 0.12), Color(0.44, 0.52, 0.24))
	var a: Array[Transform3D] = []
	var b: Array[Transform3D] = []
	var tries := 0
	while (a.size() + b.size()) < 260 and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-HALF + 6.0, HALF - 6.0)
		var z := _rng.randf_range(-24.0, 24.0)
		var m := mask_at(x, z)
		if m.a > 0.25 or m.r > 0.15:            # 踩實的土／石板上不長草
			continue
		var near := false
		for L in LOTS:
			var c := _lot_center(L)
			if absf(x - c.x) < 4.4 and absf(z - c.y) < 4.2:
				near = true
				break
		if near:
			continue
		var s := _rng.randf_range(0.7, 1.3)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(s, s, s)), Vector3(x, height_at(x, z), z))
		if _rng.randf() < 0.3:
			b.append(t)
		else:
			a.append(t)
	for pair in [["MM_草", tuft, a], ["MM_雜草", weed, b]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(pair[1], pair[2], [],
			OUT_DIR + "gen/mm_%s.res" % String(pair[0]).trim_prefix("MM_"))
		mmi.material_override = lib.foliage_vc_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		lib.add(g, mmi, String(pair[0]))
	# 兩棵樹：一棵在井邊（提供樹蔭與垂直線）、一棵在巷底
	for spec in [[16.2, 4.6, "tree_round_a", 0.9], [-4.2, -13.5, "tree_round_c", 0.72]]:
		var t2 := MeshInstance3D.new()
		t2.mesh = lib.tree_mesh("res://assets/models/%s.glb" % String(spec[2]))
		t2.position = Vector3(float(spec[0]), height_at(float(spec[0]), float(spec[1])),
			float(spec[1]))
		t2.scale = Vector3.ONE * float(spec[3])
		t2.rotation.y = _rng.randf_range(0.0, TAU)
		lib.add(g, t2, "樹_%s" % String(spec[2]))
	_audit.append("植栽：草 %d・雜草 %d・樹 2（只長在沒踩實的地方）" % [a.size(), b.size()])


func _build_people() -> void:
	## 三個村民 —— 驗收問題 5：「放東方角色進去是否自然」。
	## 尺度參考也靠他們：房子好不好看很主觀，但「門比人高多少」是客觀的。
	##
	## ⚠ PHASE 2.5：**slice からは外した**（資産は消していない）。
	## legacy の villager は白いカプセルで、店先を作り込むほど画面の中で
	## 一番目立つ未完成物になる —— Phase 1.6 で白盒子の建築を slice から
	## 出したのとまったく同じ判断。人物は別ラウンドの仕事。
	## 尺度の基準は失うので、審図では「内法高 1.85m の戸口」を物差しにする。
	var g := lib.add(_root, Node3D.new(), "村民") as Node3D
	for spec in []:
		var x := float(spec[0])
		var z := float(spec[1])
		var v := MeshInstance3D.new()
		v.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec[2]))
		v.position = Vector3(x, height_at(x, z), z)
		v.rotation.y = float(spec[3])
		lib.add(g, v, String(spec[2]))
	_audit.append("村民 0 人（PHASE 2.5：白いカプセルを slice から隔離。資産は保持）")


func _build_env() -> void:
	## 簡單自然日光。⚠ 規格明令：不要用 cinematic lighting／霧／DOF 掩蓋問題。
	## 所以這裡**沒有**霧、沒有 glow、沒有 SSAO 以外的後製。
	var e := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.42, 0.55, 0.76)
	pm.sky_horizon_color = Color(0.72, 0.76, 0.80)
	pm.ground_bottom_color = Color(0.32, 0.32, 0.30)
	pm.ground_horizon_color = Color(0.62, 0.62, 0.58)
	# ⚠ PHASE 2.5：8.0° は**太陽の円盤が 8 度角**ということ（実際の太陽は 0.5°）。
	# 地平線に白いカプセルが浮いて見え、Phase 1.5 以降ほぼ全カットに写り込んで
	# いた。店先を作り込むまで「村民か提灯の未完成物」だと誤診し続け、
	# 村民を隔離し・箒を暗くし・立て看板を作り直しても消えなかった —— 探して
	# いた場所（シーングラフ）に**最初から無かった**から。影を落とさない・
	# 常に地平線上にある・どの probe にも引っかからない、の三点が答えだった。
	pm.sun_angle_max = 1.5
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.0
	e.environment = env
	lib.add(_root, e, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-126.0), 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	lib.add(_root, sun, "Sun")


func _write_meta() -> void:
	var meta := {
		"id": MAP_ID,
		"note": "PHASE 1.5 vertical slice（art benchmark）。8 棟建築、一條主街、"
			+ "兩條巷、一個井戶節點。獨立於 village，改這裡不影響 169 棟。",
		"playSize": [HALF * 2.0, HALF * 2.0],
		"safe": true,
		"colliders": [],
		"connections": [],
		"portals": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " ", false))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)
