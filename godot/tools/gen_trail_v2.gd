extends SceneTree
## 獸道 v2 —— 依使用者規格重做（2026-09-04）。
##
##   Godot --headless --path godot --script tools/gen_trail_v2.gd
##
## 產出 maps/trail/trail.tscn（整張覆蓋；舊版在 git 8ed502f 可救回）。
##
## ══ 定調 ══
## 「這條路原本是人走的，但走得越深，越不像是為人類準備的路。」
## 線性：人里(南) → 界碑 → 普通森林 → 縮窄 → 地藏 → 密林 → 小溪/木橋
##       → 大空地(古樹) → 密林 → 妖怪痕跡 → 夜雀屋台 → 更深(北，神社傳送點)
## 使用者裁決：完全線性，竹林/太陽花田連線先不管。
##
## ══ 座標約定 ══
## 南 = +z（人里入口），北 = -z（深處）。深度參數 t∈[0,1] 沿主脊由南到北。
## 路寬 2.8 m → 1.3 m 隨 t 縮窄；蛇行由三層正弦疊加，振幅隨 t 放大。
##
## ⚠ 2026-09-07 使用者裁定：緣一跑步（7 m/s）單程 40 s 內到下一張圖。
##   實測機器人繞樹路徑 ≈ 主脊 ×1.28 → 主脊 220 m，圖 240×240（原 640 / 680）。
##   沿長度分布的東西（樹、地被、碎石、苔石叢、磷光菌）數量跟著減半，
##   保持每公尺密度不變；蛇行振幅也減半，彎的角度才不會變成兩倍尖。
##   **局部地物尺寸不縮**：路寬、空地半徑、溪谷寬、地藏/屋台/木橋照舊。
##   小溪與大空地在 t 軸上拉開到 0.41 / 0.58（相距 37 m；空地 R17 + 溪谷帶 14 = 31 m 是硬下限）。
##
## ══ 資產 ══
## 自然層 Quaternius nature/（BASE 原點，公尺單位，實測 probe_trail_assets.gd）
##   樹 6 種：CommonTree(闊葉)、Pine(松)、DeadTree(枯)、TwistedTree(歪/老) 各多變體
##   地表：Fern、Grass×4、Bush×2、Plant、Clover、Mushroom×2、Flower、Rock_Medium×3、Pebble
## 遠景山 gobkit（公分單位，各件實測後單獨算縮放）
## 人工物 lowpoly_scene/：StoneLantern、Fence_Wood、Log_Cluster、Barrel、CeremicPot、Basket_S
## 缺件（走 Meshy）留 Marker3D 佔位：界碑×2、警告牌、地藏×N、古樹 Hero、屋台 Hero、木橋
##
## ══ 個別節點 vs LOD ══
## 使用者要每棵樹可個別選取。路沿 NEAR_BAND 內全個別節點（原尺寸網格）；
## 外圍仍是個別節點但共用 _lod 低面數網格（若 _lod 沒有就直接用原網格——
## 先求正確，效能實測後再壓）。

## ══ 2026-09-15 r3：路線重排 + 樹全面換 Tripo GLB ══
## 使用者裁定（三選一皆取第一項）：
##   1. 主脊走向、分段順序/長度、關鍵點位置全部重來。
##   2. 全部樹（路沿＋外圍＋空地古樹）換 assets/landscape/ 的 GLB，
##      Quaternius nature/ 只留地表草／灌木／石頭。
##   3. 獸道另訂樹種配比：杉／針葉為骨幹，深處加枯木與楓，入口段較明亮。
##
## 路線改用**控制點 + Catmull-Rom**，不再是三層正弦。正弦版的問題是整條路
## 看起來都一樣（同一組頻率從頭鋪到尾），玩家沒有「這裡轉了個彎」的記憶點。
## 控制點版每個彎都是為某個地物存在的：西偏繞岩壁 → 隘口收窄 → 東折下切溪谷
## → 過橋爬升 → 西折進空地 → 出空地急轉北 → 屋台平台 → 收窄直行入深處。
##
## 新節奏（南 t=0 → 北 t=1）：
##   農田柵欄 / 界碑疏林 / 雜木林 / **岩壁隘口**(新) / 地藏舊路標 /
##   杉林 / 溪谷木橋 / 濕林 / 大空地古樹 / 密林妖怪痕跡 / 屋台平台 / 更深

const Lib := preload("res://tools/gen_lib.gd")
const OUT := "res://maps/trail/"
const NAT := "res://assets/nature/"
const LP := "res://assets/lowpoly_scene/"
const GOB := "res://assets/_incoming/gobkit_nature/"
const LS := "res://assets/landscape/"

const HALF := 120.0                 # 240×240，跟登錄表一致（原 680 → 340 → 240）
const SPINE_Z0 := 110.0             # 南端（人里入口）
const SPINE_Z1 := -110.0            # 北端（神社傳送點）—— 全長 220 m（使用者裁定：緣一跑步單程 40 s）
const NEAR_BAND := 30.0             # 路沿個別高模帶
const SEED := 20260904

# ── 場景節奏（沿 t 的關鍵段落）──
# r3 重排：密→疏的交替更明確，並新增「岩壁隘口」這個最窄最壓迫的段落。
const BEATS := [
	{ "t0": 0.00, "t1": 0.05, "dens": 0.15, "tag": "農田/柵欄" },
	{ "t0": 0.05, "t1": 0.11, "dens": 0.40, "tag": "界碑・疏林" },
	{ "t0": 0.11, "t1": 0.18, "dens": 0.72, "tag": "雜木林" },
	{ "t0": 0.18, "t1": 0.24, "dens": 0.95, "tag": "岩壁隘口（最窄）" },
	{ "t0": 0.24, "t1": 0.34, "dens": 0.38, "tag": "疏・地藏舊路標" },
	{ "t0": 0.34, "t1": 0.42, "dens": 0.92, "tag": "杉林" },
	{ "t0": 0.42, "t1": 0.50, "dens": 0.28, "tag": "溪谷・木橋" },
	{ "t0": 0.50, "t1": 0.58, "dens": 0.70, "tag": "濕林" },
	{ "t0": 0.58, "t1": 0.70, "dens": 0.05, "tag": "大空地・古樹" },
	{ "t0": 0.70, "t1": 0.79, "dens": 0.98, "tag": "密林・妖怪痕跡" },
	{ "t0": 0.79, "t1": 0.88, "dens": 0.33, "tag": "夜雀屋台平台" },
	{ "t0": 0.88, "t1": 1.00, "dens": 1.00, "tag": "更深的妖怪領域" },
]
const T_ENTRANCE := 0.06
const T_GATE := 0.21                # 岩壁隘口（新節點）
const T_JIZO := 0.29
const T_CREEK := 0.46               # 與空地中心相距 0.17 = 38 m（空地 R17 + 溪谷帶 14 = 31 m 是硬下限）
const T_CLEARING := 0.63
const T_STALL := 0.84
const CLEARING_R := 17.0            # 直徑 ~34 m（規格 20-30，放寬以展現開闊感）
## 路面壓平帶：路緣外多少公尺內地形貼著路心高度、再漸回自然起伏。
## 6 m 時（減半版格距 1.7 m 畫得出細節）路兩側土坡貼著路面像走溝，
## 使用者要更寬 → 12 m。
const ROAD_FLAT_BAND := 12.0
## 泥潭（杉林段裡兩處）：[沿主脊 t, 側向偏移 m]。height_at 與 mask_at 共用，
## 不可各寫一份。t 要離溪心（T_CREEK）至少 0.05 = 11 m，溪谷抹平帶才不會蓋掉它。
const MUD_SPECS := [[0.36, Vector2(-9.0, 3.0)], [0.55, Vector2(11.0, -2.0)]]

## ── 主脊控制點（南 +z → 北 -z）──
## 每個彎都為一個地物服務，不是為了蛇行而蛇行。
## z 必須單調遞減（線性前進、不回頭）；x 幅度控制在 ±20 m 內，
## 否則彎太急、玩家用跑的會一直撞樹。
const SPINE_PTS := [
	Vector2(  2.0,  110.0),   # 南端：人里入口，直
	Vector2(  1.0,   95.0),   # 界碑
	Vector2( -6.0,   77.0),   # 開始往西偏（繞開岩壁）
	Vector2(-16.0,   58.0),   # 岩壁隘口，最窄
	Vector2(-13.0,   40.0),   # 出隘口
	Vector2(  2.0,   25.0),   # 東折 —— 地藏三尊在這個彎的外側
	Vector2(  9.0,    8.0),   # 下切溪谷
	Vector2(  6.0,   -6.0),   # 過橋後爬升
	Vector2( -8.0,  -20.0),   # 西折進空地
	Vector2(-17.0,  -34.0),   # 空地（路從中央偏西穿過）
	Vector2( -6.0,  -50.0),   # 出空地，急轉北
	Vector2(  4.0,  -66.0),   # 最暗的密林
	Vector2(  1.0,  -82.0),   # 屋台平台
	Vector2( -3.0,  -97.0),
	Vector2( -2.0, -110.0),   # 北端：神社傳送點
]


var lib: Lib
var _nh: FastNoiseLite       # 地形起伏
var _nd: FastNoiseLite       # 密度擾動（讓節奏內部也不均勻）
var _nm: FastNoiseLite       # 蛇行擾動
var _spine: PackedVector2Array   # 主脊取樣點（南→北）
var _spine_t: PackedFloat32Array
var _branches: Array = []        # 岔路：每條是 PackedVector2Array
var _meshes := {}                # path → Mesh（tree/grass 快取）
var _placed_trunks: PackedVector2Array
var _trunk_log: Array = []      # [中心 xz, 樹冠水平半徑] — 走廊自檢用
## 地藏位置。地表植被要讓開，否則 1 m 高的芒草會把地藏整個埋掉。
## ⚠ 必須在 _build_ground_cover() **之前**填好——地藏本身是在
##   _build_human_traces()（更後面）才生成的，所以位置要先預算。
var _jizo_sites: Array = []

## 地藏配置：[沿主脊 t, 幾尊, 側向(+1 左 / -1 右)]
## 這份表同時被 _plan_jizo_sites()（植被讓位）與 _build_human_traces()
## （實際擺放）使用，兩邊不可各寫一份。
const JIZO_SPECS := [
	[0.06, 1, 1.0],           # 入口（＝T_ENTRANCE）
	[0.16, 1, -1.0],          # 雜木林起點
	[T_JIZO, 3, 1.0],         # 疏段三尊，落在東折彎的外側（規格的「地藏／舊路標」節點）
	[0.40, 1, -1.0],          # 杉林段；離溪心 0.06 = 13 m，避開溪岸抹平帶（14 m 帶邊緣）
	[0.76, 1, 1.0],           # 密林妖怪痕跡段
]


# ══════════════════════════════════════════════════════════════════
# 主脊：由南到北的蛇行折線
# ══════════════════════════════════════════════════════════════════
## Catmull-Rom 取一段（p1→p2）
func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


## 主脊：控制點 Catmull-Rom → 依**弧長**等距重取樣。
##
## ⚠ 一定要按弧長重取樣。t 在這支腳本裡被當成「沿路走了多遠」使用
## （節奏 BEATS、地藏、溪、空地全部吃 t）；若 t 只是控制點索引，
## 彎多的段落會在 t 軸上被壓縮，節奏長度就對不上實際公尺數。
func _build_spine() -> void:
	# 1. 密取樣（每段 60 點）
	var raw := PackedVector2Array()
	var n_ctrl := SPINE_PTS.size()
	for i in n_ctrl - 1:
		var p0: Vector2 = SPINE_PTS[maxi(i - 1, 0)]
		var p1: Vector2 = SPINE_PTS[i]
		var p2: Vector2 = SPINE_PTS[i + 1]
		var p3: Vector2 = SPINE_PTS[mini(i + 2, n_ctrl - 1)]
		for k in 60:
			raw.append(_cr(p0, p1, p2, p3, float(k) / 60.0))
	raw.append(SPINE_PTS[n_ctrl - 1])
	# 2. 微幅噪聲讓曲線不要太「設計感」（±0.9 m，不改變大方向）
	for i in range(1, raw.size() - 1):
		var f := float(i) / float(raw.size() - 1)
		raw[i] += Vector2(_nm.get_noise_1d(f * 620.0), 0.0) * 0.9
	# 3. 累積弧長
	var acc := PackedFloat32Array()
	acc.resize(raw.size())
	acc[0] = 0.0
	for i in range(1, raw.size()):
		acc[i] = acc[i - 1] + raw[i].distance_to(raw[i - 1])
	var total: float = acc[raw.size() - 1]
	# 4. 等弧長重取樣成 400 點
	var n := 400
	_spine.resize(n)
	_spine_t.resize(n)
	var cur := 0
	for i in n:
		var t := float(i) / float(n - 1)
		var want := t * total
		while cur < raw.size() - 2 and acc[cur + 1] < want:
			cur += 1
		var seg: float = maxf(acc[cur + 1] - acc[cur], 0.0001)
		var u: float = clampf((want - acc[cur]) / seg, 0.0, 1.0)
		_spine[i] = raw[cur].lerp(raw[cur + 1], u)
		_spine_t[i] = t
	_spine_len = total
	print("[TRAIL] 主脊弧長 %.1f m（控制點 %d）" % [total, n_ctrl])


var _spine_len := 0.0



func _spine_pos(t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * float(_spine.size() - 1)
	var i := int(floor(f))
	var j := mini(i + 1, _spine.size() - 1)
	return _spine[i].lerp(_spine[j], f - float(i))


func _spine_dir(t: float) -> Vector2:
	return (_spine_pos(t + 0.004) - _spine_pos(t - 0.004)).normalized()


func _stall_pos() -> Vector2:
	var c := _spine_pos(T_STALL)
	var d := _spine_dir(T_STALL)
	var perp := Vector2(-d.y, d.x)
	return c + perp * (_half_w(T_STALL) + 3.2)


## 路寬（半寬）隨深度縮窄：2.8 m → 1.3 m，並在空地/屋台附近略放寬
func _half_w(t: float) -> float:
	var w := lerpf(2.8, 1.3, smoothstep(0.1, 0.95, t))
	w += 0.6 * exp(-pow((t - T_CLEARING) / 0.03, 2.0))
	w += 0.4 * exp(-pow((t - T_STALL) / 0.02, 2.0))
	w += 0.4 * (1.0 - smoothstep(0.0, 0.08, t))     # 入口段還是人走的土路
	# 岩壁隘口：路被兩側岩體夾窄。
	# ⚠ 不能窄到 1.5 m。緣一跑步 7 m/s，1.5 m 寬的通道在那個速度下等於
	#   一路刮牆；下限取全寬 2.2 m（半寬 1.1），壓迫感靠兩側 6.5 m 岩脊給，
	#   不靠把路收到過不去。
	#   ⚠ maxf 夾的是**全寬** w，不是半寬——return 才乘 0.5。
	w -= 1.1 * exp(-pow((t - T_GATE) / 0.022, 2.0))
	return maxf(w, 2.2) * 0.5



## ══ 玩家可動範圍（走廊）══
## 2026-09-15 使用者裁定：
##   「兩側做碰撞牆；不要把全部樹木做碰撞，只做玩家可動範圍兩側的樹木；
##     超過的部分加上高碰撞牆包圍。」
##
## 可動半寬沿主脊變化：基本 20 m，大空地要整個含進來（R17 + 角度擾動最大
## 1.4× ≈ 23.8 m）所以那一段鼓到 27 m；屋台在路側 4.4 m 處，22 m 夠用。
## 隘口段**不收窄**——牆若跟著岩壁一起夾進來，玩家會卡在岩石與牆之間。
const PLAY_HALF_BASE := 20.0
const PLAY_WALL_H := 14.0        # 牆高：樹冠 26 m，但玩家跳不了那麼高；14 m 足夠且省
const PLAY_WALL_STEP := 4.0      # 每段牆的長度（沿主脊取樣間距）

func play_half(t: float) -> float:
	var w := PLAY_HALF_BASE
	# 大空地：牆要在空地外圈，否則玩家走到空地邊就撞牆
	w = maxf(w, 27.0 * exp(-pow((t - T_CLEARING) / 0.075, 2.0)))
	# 屋台平台略放寬
	w = maxf(w, 23.0 * exp(-pow((t - T_STALL) / 0.03, 2.0)))
	return w


## ══ 傳送點淨空 ══
## 傳送點座標**從 data/trail.meta.json 讀**，不在這裡再寫一份——
## main.gd 生成傳送區用的是那一份，兩邊各寫一份遲早會對不上。
##
## ⚠ 為什麼要淨空：雜草地毯把傳送點埋了。實測北傳送點 1.3 m 外有一叢
##   草頂到 y=9.64，而傳送門的光環在 y=8.81、門面下緣 8.34 —— 草直接
##   蓋住整個下半部，玩家看到的只有樹葉縫裡一段藍色弧線。
const PORTAL_CLEAR_R := 4.5      # 這個半徑內不長草、不長樹

var _portals: Array = []         # [Vector2]

func _load_portals() -> void:
	_portals.clear()
	var f := FileAccess.open("res://data/trail.meta.json", FileAccess.READ)
	if f == null:
		push_warning("讀不到 trail.meta.json —— 傳送點淨空不會生效")
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	if typeof(j) != TYPE_DICTIONARY:
		return
	for p in (j as Dictionary).get("portals", []):
		_portals.append(Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))))
	print("[TRAIL] 傳送點淨空：%d 處，半徑 %.1f m" % [_portals.size(), PORTAL_CLEAR_R])


## 這個點是否落在傳送點淨空圈內
func _in_portal_clear(p: Vector2, extra: float = 0.0) -> bool:
	for q in _portals:
		if p.distance_to(q) < PORTAL_CLEAR_R + extra:
			return true
	return false


## 主脊每個取樣點的路半寬（與 _spine 同索引），烘進場景 meta 供體檢使用
func _half_w_table() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_spine.size())
	for i in _spine.size():
		out[i] = _half_w(_spine_t[i])
	return out


## 可動範圍半寬表（同索引），一併烘進 meta 供體檢／導航使用
func _play_half_table() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_spine.size())
	for i in _spine.size():
		out[i] = play_half(_spine_t[i])
	return out


## 到主脊距離、最近 t
func _spine_info(p: Vector2) -> Array:
	var best := INF
	var bt := 0.0
	for i in _spine.size() - 1:
		var a := _spine[i]
		var b := _spine[i + 1]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * u)
		if d < best:
			best = d
			bt = lerpf(_spine_t[i], _spine_t[i + 1], u)
	return [best, bt]


# ══════════════════════════════════════════════════════════════════
# 岔路：從主脊分出去、逐漸消失的窄徑
# ══════════════════════════════════════════════════════════════════
func _build_branches() -> void:
	var specs := [
		# t 起點、方向(左右)、長度、是否消失
		# r3：岔路重排到新節奏的「疏」段與空地、屋台附近——密林段本來就看不到
		# 岔路，開在那裡等於白開。
		[0.13, 1, 40.0, true], [0.27, -1, 34.0, true],
		[0.31, 1, 22.0, true], [0.38, -1, 44.0, true],
		[T_CLEARING + 0.01, 1, 38.0, true],      # 空地側隱藏獸徑（規格 §7）
		[0.72, -1, 50.0, true], [0.80, 1, 26.0, true],
		[0.90, -1, 66.0, true], [0.95, 1, 38.0, true],
	]
	for s in specs:
		var t0: float = s[0]
		var side: float = float(s[1])
		var len: float = s[2]
		var pts := PackedVector2Array()
		var p := _spine_pos(t0)
		var d := _spine_dir(t0)
		var perp := Vector2(-d.y, d.x) * side
		var dir := (perp * 0.8 + d * lib.rr(-0.3, 0.3)).normalized()
		var steps := int(len / 2.0)
		for k in steps + 1:
			pts.append(p)
			var turn := _nm.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.9
			dir = dir.rotated(turn * 0.35).normalized()
			p += dir * 2.0
		_branches.append(pts)


## 到任一岔路的距離、沿岔路的衰減(0=起點 1=盡頭)
func _branch_info(p: Vector2) -> Array:
	var best := INF
	var fade := 0.0
	for br in _branches:
		var pts: PackedVector2Array = br
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * u)
			if d < best:
				best = d
				fade = (float(i) + u) / float(pts.size() - 1)
	return [best, fade]


# ══════════════════════════════════════════════════════════════════
# 地形
# ══════════════════════════════════════════════════════════════════
## 小溪：橫穿主脊於 T_CREEK，走向大致東西、帶一點蛇行
##
## ⚠ 溪心的 z 是「x 的函數」（帶蛇行），所以主脊在 T_CREEK 的點**不等於**
##   實際的路／溪交會點。r3 之前直接拿 _spine_pos(T_CREEK) 當橋位，
##   結果橋離真正的過水點 7 m（實測 spine z=7.05、溪心 z=14.4）。
##   現在改成：溪的基準 z 用「主脊在 T_CREEK 的 z 扣掉該處的蛇行量」，
##   使溪心恰好通過主脊那一點；橋位另外用 _creek_crossing() 解出來。
var _creek_z0 := 0.0

func _creek_wiggle(x: float) -> float:
	return sin(x * 0.045 + 1.3) * 6.0 + _nm.get_noise_1d(x * 2.0) * 3.0


func _creek_dist(p: Vector2) -> float:
	return absf(p.y - (_creek_z0 + _creek_wiggle(p.x)))


## 路與溪真正的交會點（沿主脊掃最小距離）
func _creek_crossing() -> Array:
	var bt := T_CREEK
	var best := INF
	for i in 400:
		var t := float(i) / 399.0
		var d := _creek_dist(_spine_pos(t))
		if d < best:
			best = d
			bt = t
	return [bt, _spine_pos(bt), best]



func _clearing_dist(p: Vector2) -> float:
	var c := _spine_pos(T_CLEARING)
	# 不規則：半徑隨角度擾動
	var ang := atan2(p.y - c.y, p.x - c.x)
	var r := CLEARING_R * (1.0 + 0.25 * sin(ang * 3.0 + 0.6) + 0.15 * sin(ang * 5.0 + 2.2))
	return p.distance_to(c) - r


func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var info := _spine_info(p)
	var ed: float = maxf(0.0, info[0] - _half_w(info[1]))
	var t: float = info[1]
	# 基底：緩坡+土丘+淺谷
	var h := _nh.get_noise_2d(x, z) * 4.5 \
		+ _nh.get_noise_2d(x * 0.3 + 100.0, z * 0.3) * 6.0 \
		+ sin(x * 0.018 + 0.4) * 1.4 + sin(z * 0.014 + 1.1) * 1.6
	# 整體往北緩升 — 「深處」有高度感
	h += t * 9.0
	# 路面壓平：路上取路心高度的平滑版；路外漸回自然起伏
	var flat := smoothstep(0.0, ROAD_FLAT_BAND, ed)
	var road_h := sin(z * 0.03) * 0.8 + t * 9.0 + _nh.get_noise_2d(x * 0.15, z * 0.15) * 1.2
	h = lerpf(road_h, h, flat)
	# 路面本身的細碎起伏（樹根/石頭感）
	h += (1.0 - flat) * _nm.get_noise_2d(x * 4.0, z * 4.0) * 0.08
	# 小溪：谷要夠深夠寬，否則地形網格（格距 3.4 m）根本表現不出它。
	# ⚠ 前一版切 0.9 m、寬 5 m：一個網格格子跨掉半條溪，谷底被抹平，
	#   水面不管怎麼算都有一半埋在土裡（check_map 連報三次 29→35→49%）。
	# ⚠ 谷深必須壓過地形噪聲的振幅。基底噪聲是 ±4.5 + ±6.0 = 最大 10.5 m，
	#   谷只切 2.2 m 的話，噪聲一個起伏就把谷填平 → 水面沿途斷成好幾截
	#   （v14_小溪俯角.png）。這裡改成**先把溪帶的地形壓平再挖**：
	#   谷心 12 m 內先抹掉八成起伏，再切 2.6 m 深的 V 形谷。
	var cd := _creek_dist(p)
	var creek_zone := 1.0 - smoothstep(4.0, 14.0, cd)
	if creek_zone > 0.0:
		# 沿溪的縱向基準面：只保留大尺度坡度，抹掉橫向亂流
		var base := t * 9.0 + sin(x * 0.012) * 2.2 + _nh.get_noise_2d(x * 0.25, 0.0) * 1.8
		h = lerpf(h, base, creek_zone * 0.8)
	h -= 2.6 * (1.0 - smoothstep(0.0, 9.0, cd))
	# 大空地：壓平
	var cl := _clearing_dist(p)
	var in_cl := 1.0 - smoothstep(-2.0, 4.0, cl)
	var cl_h := _spine_pos(T_CLEARING).y * 0.03
	h = lerpf(h, T_CLEARING * 9.0 + sin(cl_h) * 0.8 + 0.1, in_cl)
	# 小水潭：同樣要夠深夠寬才畫得進 3.4 m 格距的網格（0.5 m / 4 m 太淺）
	var pond := _spine_pos(T_CLEARING) + Vector2(6.0, -7.0)
	h -= 1.4 * (1.0 - smoothstep(0.0, 6.0, p.distance_to(pond)))
	# 泥潭：密林 2 裡兩處
	for m in _mud_sites():
		h -= 0.35 * (1.0 - smoothstep(2.0, 5.5, p.distance_to(m)))
	# 岩壁隘口：路兩側各一道岩脊，路心不動。
	# ⚠ 不能整片抬高，否則路也跟著升上去看不出「夾」。這裡用「離路心距離」
	#   當作抬升量：路緣 3 m 外開始升，9 m 處到頂 6.5 m，再往外回落。
	var gp := _spine_pos(T_GATE)
	var gate_along := 1.0 - smoothstep(6.0, 22.0, p.distance_to(gp))
	if gate_along > 0.0:
		var gi := _spine_info(p)
		var gd: float = gi[0]
		var ridge := smoothstep(2.6, 9.0, gd) * (1.0 - smoothstep(9.0, 20.0, gd))
		h += 6.5 * ridge * gate_along
	return h


func _mud_sites() -> Array:
	var out := []
	for s in MUD_SPECS:
		out.append(_spine_pos(s[0]) + (s[1] as Vector2))
	return out


## 地表混合遮罩：R=路面、G=林床(腐葉土)、B=巨觀變化、(A=泥/濕)
func mask_at(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var info := _spine_info(p)
	var hw := _half_w(info[1])
	var d: float = info[0]
	# 路心保持結實踩踏感，路緣自然漸變
	var road := 1.0 - smoothstep(hw * 0.85, hw + 0.8, d)
	# 邊緣不整齊：噪聲只微咬路邊，不侵蝕路心
	road *= clampf(1.0 - (_nm.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5) * smoothstep(hw * 0.6, hw + 0.8, d) * 0.8, 0.0, 1.0)
	# 岔路：越往盡頭越淡
	var bi := _branch_info(p)
	var broad := (1.0 - smoothstep(0.4, 1.4, bi[0])) * (1.0 - smoothstep(0.35, 1.0, bi[1])) * 0.65
	road = maxf(road, broad)
	# 入口段舊道路痕跡（比路面寬、很淡）
	var t: float = info[1]
	if t < 0.12:
		road = maxf(road, (1.0 - smoothstep(hw + 0.8, hw + 4.5, d)) * 0.35 * (1.0 - t / 0.12))
	# 林床：從路緣外側開始增長，路面內壓制腐葉土
	var dens := _density_at(t)
	var forest := clampf(smoothstep(hw * 0.7, hw + 4.5, d) * (0.65 + dens * 0.35), 0.0, 1.0)
	# ⚠ terrain_pbr 的混色順序是 grass → forest(m.g) → path(m.r)，但 forest
	# 那一層是無條件 mix 的，只要 m.g 有值就會把已經畫好的路面蓋掉一部分。
	# 入口段實拍完全看不出路（v8_入口.png）就是這樣來的。
	# 這裡直接讓林床扣掉路面權重，兩層不再互相打架。
	forest *= 1.0 - road
	var cl := _clearing_dist(p)
	forest *= smoothstep(-1.0, 3.0, cl)      # 空地內是草
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	# 濕/泥：溪邊、泥潭、水潭
	var wet := 1.0 - smoothstep(2.5, 7.0, _creek_dist(p))
	for m in _mud_sites() + [_spine_pos(T_CLEARING) + Vector2(6.0, -7.0)]:
		wet = maxf(wet, 1.0 - smoothstep(2.0, 6.0, p.distance_to(m)))
	# ⚠ A 通道（dirt 層）才是路面真正畫得出來的地方。
	#
	# 原本路面走 m.r → shader 的 path_diff，而我傳的 path_set 是
	# "terrain_path"（土徑貼圖）—— 它跟旁邊的草地/林床顏色幾乎一樣，
	# 於是實拍每一張圖都看不出路在哪（v10 入口/深處都是一片黃褐）。
	# dirt 層有 dirt_tint 可以獨立調色、還會被 shader 拉向灰階，
	# 正好是「踏實的泥土獸徑」該有的樣子。
	# 濕氣併進同一通道（溪邊本來就該是深色濕泥）。
	return Color(road, forest, macro, maxf(road, wet * 0.7))


func _density_at(t: float) -> float:
	for b in BEATS:
		if t >= b.t0 and t < b.t1:
			# 段內平滑到相鄰段（避免硬切）
			return b.dens
	return 1.0


func _density_smooth(t: float) -> float:
	var d := _density_at(t)
	var d0 := _density_at(t - 0.03)
	var d1 := _density_at(t + 0.03)
	return (d * 2.0 + d0 + d1) / 4.0


# ══════════════════════════════════════════════════════════════════
# 進入點
# ══════════════════════════════════════════════════════════════════
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "gen"))
	_nh = FastNoiseLite.new(); _nh.frequency = 0.011; _nh.fractal_octaves = 3; _nh.seed = 240
	_nd = FastNoiseLite.new(); _nd.frequency = 0.03; _nd.seed = 77
	_nm = FastNoiseLite.new(); _nm.frequency = 0.05; _nm.seed = 31

	var root := Node3D.new()
	root.name = "Trail"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, SEED)
	_build_spine()
	_build_branches()
	_load_portals()
	# 溪心基準：讓溪恰好通過主脊在 T_CREEK 的那一點
	var _cp := _spine_pos(T_CREEK)
	_creek_z0 = _cp.y - _creek_wiggle(_cp.x)
	var _cx := _creek_crossing()
	print("[TRAIL] 溪／路交會：t=%.3f 位置 %s 殘差 %.2f m" % [_cx[0], _cx[1], _cx[2]])

	print("[TRAIL] 主脊 %d 點，南 %s → 北 %s" % [_spine.size(), _spine_pos(0.0), _spine_pos(1.0)])
	print("[TRAIL] 關鍵點：入口 %s 隘口 %s 地藏 %s 小溪 %s 空地 %s 屋台 %s" % [
		_spine_pos(T_ENTRANCE), _spine_pos(T_GATE), _spine_pos(T_JIZO), _spine_pos(T_CREEK), _spine_pos(T_CLEARING), _spine_pos(T_STALL)])

	# 地形：路面走土徑貼圖、第四層「濕泥」——沒有專屬泥貼圖，先用林床貼圖
	# 疊深色 tint 當濕土；Meshy/貼圖到位後換 dirt_set 即可
	# dirt_amount 由 gen_lib 依 dirt_set 是否給定而開；tint 是踏實的深褐濕土，
	# 與旁邊的黃綠草地、紅褐林床拉開色差，路才看得出來。
	var terrain := lib.terrain(OUT, HALF, 201, height_at, mask_at, "terrain_path",
		Color(0.58, 0.62, 0.46), "terrain_forest", Color(0.30, 0.24, 0.18), 0.0)
	lib.boundary(HALF - 2.0)
	_index_terrain(terrain)
	_build_creek_water()
	_build_forest()
	_plan_jizo_sites()          # 先定位置，讓地表植被知道要讓開哪裡
	_build_ground_cover()
	_build_weed_carpet()
	_build_play_walls()
	_build_rocks_and_logs()
	_build_gate()
	_build_human_traces()
	_build_clearing()
	_build_stall_site()
	_build_youkai_traces()
	_build_vista()
	_build_sky()
	_build_markers()
	_attach_interactions(root)

	var packed := PackedScene.new()
	# 把主脊折線烘進場景 meta：體檢腳本要能量「離路心多遠」，
	# 而它拿不到產生器的 _spine。沒有這份資料的話只能用群中心之類的
	# 近似，第一版就是這樣量出 x=-0.14（實際隘口在 x=-14.8）的假結果。
	lib.root.set_meta("spine", _spine)
	lib.root.set_meta("spine_half_w", _half_w_table())
	lib.root.set_meta("play_half", _play_half_table())
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT + "trail.tscn")
	print("[TRAIL] saved trail.tscn err=%d  節點 %d" % [err, _count(root)])
	quit(0)


## 劇情互動點：把 trail_interactions.tscn 掛回場景。
##
## ⚠ 這個節點**不是**產生器造的，是手工場景，但它必須每次重建都掛回去。
##   r3 重跑產生器時整組掉了 → verify_story_slice 一次 FAIL 20 項
##   （醒來獨白、妖怪氣息、毛玉、受傷妖怪全部沒觸發，任務鏈卡在 MQ00）。
##   同樣的坑 gen_village_trees.gd 對櫻花樹群也踩過，做法一致：
##   產生器負責重新掛回，不靠人記得。
func _attach_interactions(root: Node3D) -> void:
	var ps := load("res://maps/trail/trail_interactions.tscn") as PackedScene
	if ps == null:
		push_error("找不到 trail_interactions.tscn —— 劇情事件會整組消失")
		return
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	inst.owner = root
	inst.name = "獸道互動點"
	var n := 0
	for c in inst.get_children():
		n += 1
	print("[TRAIL] 劇情互動點已掛回：%d 個事件節點" % n)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ══════════════════════════════════════════════════════════════════
# 小溪水面：沿溪心取樣一條帶狀網格，用 slice 的 water 材質
# ══════════════════════════════════════════════════════════════════
## 地形網格的高度查表。
##
## ⚠ 水面**不能**用 height_at() 定高度。地形是 201×201 的網格（格距 3.4 m），
## 解析函式的細節在取樣時被抹平；實測兩者在溪谷附近差到 0.65 m，而溪谷
## 本身只切 0.9 m —— 於是水面有 35% 埋進土裡（check_map 抓到兩次）。
## 這裡把實際存進場景的那份網格建成規則格點表，水面照它取值。
var _tg: PackedFloat32Array      # (res × res) 高度
var _tg_res := 0
var _tg_half := 0.0

func _index_terrain(mi: MeshInstance3D) -> void:
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	_tg_res = int(round(sqrt(float(vs.size()))))
	_tg_half = HALF
	_tg = PackedFloat32Array()
	_tg.resize(vs.size())
	for i in vs.size():
		_tg[i] = vs[i].y
	print("[TRAIL] 地形索引：%d×%d 格，格距 %.2f m" % [_tg_res, _tg_res, 2.0 * HALF / float(_tg_res - 1)])


## 雙線性內插地形網格高度（與存進場景的幾何一致）
func terrain_y(x: float, z: float) -> float:
	if _tg_res == 0:
		return height_at(x, z)
	var step := 2.0 * _tg_half / float(_tg_res - 1)
	var fi := clampf((x + _tg_half) / step, 0.0, float(_tg_res - 1))
	var fj := clampf((z + _tg_half) / step, 0.0, float(_tg_res - 1))
	var i0 := int(floor(fi)); var j0 := int(floor(fj))
	var i1 := mini(i0 + 1, _tg_res - 1); var j1 := mini(j0 + 1, _tg_res - 1)
	var tx := fi - float(i0); var tz := fj - float(j0)
	var h00 := _tg[j0 * _tg_res + i0]
	var h10 := _tg[j0 * _tg_res + i1]
	var h01 := _tg[j1 * _tg_res + i0]
	var h11 := _tg[j1 * _tg_res + i1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 一個圓範圍內地形網格的最低點——水面要壓在它之下才不會露出邊緣
func terrain_min_in(cx: float, cz: float, r: float) -> float:
	var lo := INF
	var step := 2.0 * _tg_half / float(_tg_res - 1)
	var n := int(ceil(r / step)) + 1
	for dj in range(-n, n + 1):
		for di in range(-n, n + 1):
			var x := cx + float(di) * step
			var z := cz + float(dj) * step
			if Vector2(x - cx, z - cz).length() > r:
				continue
			lo = minf(lo, terrain_y(x, z))
	return lo if lo != INF else terrain_y(cx, cz)


func _build_creek_water() -> void:
	# ⚠ 水面**由地形決定**，而且必須是連續網格。
	#
	# 走過的死路（六輪）：
	#   1-4. 造獨立水帶 + 算水位 → 頂點與地形格點不對齊，29→52% 埋在地下
	#   5.   逐格挑「低於水位」的格子 → 不埋了，但每格一個平面、格間有
	#        高度階梯，畫面上是一層藍灰地磚（v10/v11_小溪.png）
	#
	# 正解：沿溪心建**連續**的帶狀網格，但每個頂點的 xz 落在地形格點上、
	# y 取自同一條平滑的水位剖面。頂點共用 → 沒有階梯；xz 對齊 → 不埋地。
	#
	# 頂點色照 water.gdshader 契約（assets/shaders/water.gdshader:59）：
	#   COLOR.r  = bank，1=岸邊 0=中央（岸邊變淡、bank≥0.9 才有泡沫）
	#   COLOR.gb = 流向，編碼為 (dir + 1) / 2
	var c := _spine_pos(T_CREEK)
	var step := 2.0 * HALF / float(_tg_res - 1)

	# ── 1. 水位剖面：沿 x 掃，每站取溪心附近地形最低點，再平滑 ──
	var n := 81
	# ⚠ 溪帶不得超出地形：圖縮到 240 後 ±130 m 會伸出圖緣，terrain_y 在圖外
	#   回傳夾住的邊界值 → check_map 報 11% 埋地（最深 1.24 m @ x=73）。
	# ⚠ 溪帶長度：以**交會點**為中心 ±58 m，不是整張圖寬。
	#
	#   原本是 ±130 m（幾乎全圖 234 m）。但這條溪跟著地形往北爬升，
	#   實測水面從 y=0.34 一路升到 y=5.05 —— 站在木橋上（相機 y=6.2）
	#   往西看，100 m 外的水面幾乎跟眼睛同高，於是在畫面上三分之一
	#   拉出一條橫貫全寬的深色波紋帶，看起來像一片浮空的錯位平面。
	#   （視覺複檢兩輪都抓到這片，是真缺陷。）
	#   縮到 ±58 m 後水面高差降到約 1 m 級，兩端沒入林子裡。
	var ccx := _creek_crossing()
	var cx_at: Vector2 = ccx[1]
	var x0 := maxf(cx_at.x - 58.0, -HALF + 3.0)
	var x1 := minf(cx_at.x + 58.0, HALF - 3.0)
	var zc_of := func(x: float) -> float:
		return _creek_z0 + _creek_wiggle(x)
	var bed := PackedFloat32Array()
	bed.resize(n)
	# ⚠ 每站的水面中心要用**地形網格實際谷底**，不是解析式 zc。
	#   兩者差最多半格（1.2 m 格距 → 0.6 m），而 240 m 版東段谷壁每格升 1.4 m，
	#   從 zc 往兩側找寬度時第一步就撞牆，水面 9 條全擠在坡上
	#   （check_map 13% 埋地，最深 1.29 m @ x=67）。
	var trough := PackedFloat32Array()
	trough.resize(n)
	for i in n:
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		var zc: float = zc_of.call(x)
		# 溪心橫斷面最低點（±4 m，0.25 m 步長，涵蓋谷底）
		var lo := INF
		var lo_z := zc
		for k in 33:
			var zz := zc - 4.0 + float(k) * 0.25
			var yy := terrain_y(x, zz)
			if yy < lo:
				lo = yy
				lo_z = zz
		bed[i] = lo
		trough[i] = lo_z
	# 平滑水位：只抹掉河床的小坑，不能跨越溪的縱向坡度。
	# ⚠ ±4 站 = 26 m 範圍，而這條溪全長 260 m 落差 5.3 m（約 2%）——
	#   26 m 窗口會把上下游差 0.5 m 的高度混在一起，東端因此埋進土裡 3 m。
	#   改成 ±1 站（6.5 m）並且**不得高於本站河床 + 0.35 m**。
	var level := PackedFloat32Array()
	level.resize(n)
	for i in n:
		var acc := 0.0
		var cnt := 0
		for d in range(-1, 2):
			var k: int = clampi(i + d, 0, n - 1)
			acc += bed[k]
			cnt += 1
		level[i] = minf(acc / float(cnt) + 0.22, bed[i] + 0.35)

	# ── 2. 帶狀網格：橫向 9 條，寬度隨谷寬 ──
	var lanes := 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := []
	for i in n:
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		var zc: float = trough[i]          # 實測谷底，不是解析式溪心
		var y: float = level[i]
		# 這一站水面實際能鋪多寬：往兩側找到地形升過水位的地方。
		# ⚠ 步長要細，且**兩側各自算**——溪谷斷面不對稱，用單一半寬會讓
		#   較陡的那側頂點落在坡上（實測 16% 埋地，最深 1.43 m @ x=-46）。
		var w_neg := 0.4
		for k in range(1, 41):
			var w := float(k) * 0.25
			if terrain_y(x, zc - w) > y:
				break
			w_neg = w
		var w_pos := 0.4
		for k in range(1, 41):
			var w := float(k) * 0.25
			if terrain_y(x, zc + w) > y:
				break
			w_pos = w
		# 再各退 15 cm，避開內插誤差
		w_neg = maxf(w_neg - 0.15, 0.2)
		w_pos = maxf(w_pos - 0.15, 0.2)
		var row := []
		for l in lanes:
			var f := float(l) / float(lanes - 1)          # 0..1
			var zz := zc + lerpf(-w_neg, w_pos, f)
			# bank：中央 0、兩緣 1（water.gdshader 用它做淺灘與泡沫）
			var bank := absf(f * 2.0 - 1.0)
			row.append([Vector3(x, y, zz), bank])
		rows.append(row)
	# 流向：沿 +x（溪由西往東）
	var flow := Vector2(1.0, 0.0)
	var gcol := (flow.x + 1.0) * 0.5
	var bcol := (flow.y + 1.0) * 0.5
	var idx := 0
	for i in n:
		for l in lanes:
			var e: Array = rows[i][l]
			var v: Vector3 = e[0]
			var bank: float = e[1]
			st.set_uv(Vector2(float(i) * 0.35, float(l) / float(lanes - 1)))
			st.set_color(Color(bank, gcol, bcol))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	for i in n - 1:
		for l in lanes - 1:
			var a := i * lanes + l
			var b := a + 1
			var cc2 := a + lanes
			var d2 := cc2 + 1
			st.add_index(a); st.add_index(cc2); st.add_index(b)
			st.add_index(b); st.add_index(cc2); st.add_index(d2)
	var mesh := st.commit()
	# 繞向自檢：法線該朝上
	var arrs: Array = mesh.surface_get_arrays(0)
	var nrm: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	if nrm.size() > 0 and nrm[0].y < 0.0:
		push_error("小溪水面繞向反了（法線朝下）")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = load("res://assets/materials/east_river_water.tres")
	lib.add(lib.root, mi, "小溪水面")
	print("[TRAIL] 小溪水面：%d×%d 連續網格，水位 %.2f→%.2f" % [n, lanes, level[0], level[n - 1]])


# ══════════════════════════════════════════════════════════════════
# 森林：個別節點；路沿高模、外圍 LOD（若有）
# ══════════════════════════════════════════════════════════════════
## ══ 樹種表（r3：全面改用 assets/landscape/ 的 Tripo GLB）══
## 實測（tools/probe_trail_glb.gd）：12 件全部 min.y = 0（BASE）、本地高 0.96–0.99 m、
## 3.1k–4.9k 面／棵、單一材質 → 目標高 ÷ 本地高 ≈ 目標高，縮放直接是公尺數。
##
## 獸道配比（使用者裁定：另訂一套，不延用村緣）：
##   骨幹 = 杉／針葉（大衫、2大衫、針葉樹1/2、針葉林樹3/4）約 72%
##   點綴 = 普通樹（雜木）、楓樹（深處妖異暖色）、鎮守之杜（老樹、面數最低當遠景）
##   入口段另外強制混入較多普通樹，才有「還算明亮的人間邊界」感。
##
## ⚠ landscape/ 沒有枯樹。深處的枯木是使用者明確要的節奏元素，
##   這裡是全場唯一保留 Quaternius 的樹（DeadTree_*，見 DEAD_TREES）；
##   有 GLB 枯木之後直接換掉這一張表即可。
const TREES := {
	# 名稱 → [GLB 檔名清單, 目標高度範圍 m, 權重]
	"大杉":   [["大衫", "2大衫"], [17.0, 24.0], 0.30],
	"針葉":   [["針葉樹1", "針葉樹2glb"], [11.0, 16.0], 0.26],
	"針葉林": [["針葉林樹3", "針葉林樹4"], [13.0, 18.0], 0.16],
	"雜木":   [["普通樹"], [8.5, 13.0], 0.16],
	"老樹":   [["鎮守之杜"], [12.0, 17.0], 0.07],
	"楓":     [["楓樹"], [9.0, 13.0], 0.05],
}
## 枯樹（唯一保留的 Quaternius 樹，路徑走 NAT 而非 LS）
const DEAD_TREES := ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"]



func _mesh_h(ps: PackedScene) -> float:
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	for m in _mesh_nodes(inst):
		var a := (m as MeshInstance3D).get_aabb()
		var b := _rel(m, inst) * a
		box = b if box == null else (box as AABB).merge(b)
	inst.free()
	return (box as AABB).size.y if box != null else 1.0



## 綠葉版歪樹：自建 MeshInstance3D（不是 GLB 實例），這樣 mesh 與材質
## 都是節點自己的屬性，pack() 存得下來。同一 variant 共用一份 mesh。
var _green_cache := {}
func _green_twisted(variant: String) -> Node3D:
	if not _green_cache.has(variant):
		var src := (_ps(NAT + variant + ".gltf")).instantiate() as Node3D
		var found: ArrayMesh = null
		for mn in _mesh_nodes(src):
			found = (mn as MeshInstance3D).mesh as ArrayMesh
			break
		var dup := found.duplicate() as ArrayMesh
		var leaf := StandardMaterial3D.new()
		leaf.albedo_texture = load("res://assets/nature/Leaves_NormalTree_C.png")
		leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		leaf.alpha_scissor_threshold = 0.5
		leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.roughness = 0.95
		dup.surface_set_material(1, leaf)
		ResourceSaver.save(dup, OUT + "gen/twisted_green_%s.res" % variant)
		dup.take_over_path(OUT + "gen/twisted_green_%s.res" % variant)
		_green_cache[variant] = dup
		src.free()
	var mi := MeshInstance3D.new()
	mi.mesh = _green_cache[variant]
	return mi

func _mesh_nodes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


var _scene_cache := {}
var _h_cache := {}        # 本地高
var _w_cache := {} # 本地最大水平邊
## ⚠ 地表植被不能只用高度定縮放。Plant_7_Big 本地高 0.25 m 但寬 1.9 m，
## 用高度算出 5.9× 之後變成 11 m 寬的藍紫巨葉蓋在路上（v1 實拍）。
## 地表層一律用「最大邊」定尺寸；只有樹用高度。
func _ps(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
		var box := _aabb_of(_scene_cache[path])
		_h_cache[path] = box.size.y
		_w_cache[path] = maxf(box.size.x, box.size.z)
	return _scene_cache[path]


## 樹的資產路徑：枯樹走 Quaternius（.gltf），其餘全是 landscape 的 .glb
func _tree_path(kind: String, variant: String) -> String:
	return NAT + variant + ".gltf" if kind == "枯" else LS + variant + ".glb"


func _pick_tree() -> Array:
	var r := lib.rand()
	var acc := 0.0
	for k in TREES:
		acc += TREES[k][2]
		if r <= acc:
			var vars: Array = TREES[k][0]
			return [k, vars[int(lib.rand() * vars.size()) % vars.size()], TREES[k][1]]
	var kk: String = TREES.keys()[0]
	return [kk, TREES[kk][0][0], TREES[kk][1]]


func _build_forest() -> void:
	var forest := lib.add(lib.root, Node3D.new(), "森林") as Node3D
	var near := lib.add(forest, Node3D.new(), "路沿") as Node3D
	var far := lib.add(forest, Node3D.new(), "外圍") as Node3D
	var groups := {}
	var count := [0, 0]
	var tries := 0
	# ⚠ 棵數必須隨資產面數重算。Quaternius 樹約 0.4k 面／棵，2400 棵 ≈ 96 萬面；
	#   換成 Tripo GLB（3.1k–4.9k 面／棵）同樣 2400 棵會是 1,080 萬面，只有樹。
	#   村緣林（gen_village_trees）258 棵 ≈ 60 萬面是已驗收的量級 →
	#   這裡取 1500 棵 ≈ 650 萬面，並把外圍帶限縮成最低面數的兩種樹。
	var target := 1500
	var made := 0
	_placed_trunks = PackedVector2Array()
	# 用格子加速樹幹間距檢查
	var grid := {}
	var cell := 6.0
	while made < target and tries < 500000:
		tries += 1
		var x := 0.0
		var z := 0.0
		if made < 1150:
			# 重兵集中在路沿 3.2m ~ 55m 帶狀區，形成林蔭穹頂與密林壓迫感
			var t_sample := lib.rr(0.01, 0.99)
			var sp_pos := _spine_pos(t_sample)
			var sp_dir := _spine_dir(t_sample)
			var sp_perp := Vector2(-sp_dir.y, sp_dir.x)
			var side := 1.0 if lib.rand() < 0.5 else -1.0
			var d_offset := lib.rr(3.2, 55.0)
			var pt := sp_pos + sp_perp * (d_offset * side) + Vector2(lib.rr(-3.5, 3.5), lib.rr(-3.5, 3.5))
			x = clampf(pt.x, -HALF + 4.0, HALF - 4.0)
			z = clampf(pt.y, -HALF + 4.0, HALF - 4.0)
		else:
			# 外圍全域填充視距背景
			x = lib.rr(-HALF + 4.0, HALF - 4.0)
			z = lib.rr(-HALF + 4.0, HALF - 4.0)
		var p := Vector2(x, z)
		var info := _spine_info(p)
		var t: float = info[1]
		var ed: float = maxf(0.0, info[0] - _half_w(t))
		var dc: float = info[0]                     # 離路心
		# ⚠ 淨空要用「離路心」而不是「離路緣」。
		# v3 用 ed<3.0，但深處路半寬只有 0.65 m，樹幹離路心才 3.65 m；
		# 而路沿樹被 ed<25 那條規則強制拉到 15 m 高、樹冠半徑約 7 m，
		# 於是樹冠在路面上空完全閉合 —— 實拍整張全黑（v3_密林1.png）。
		# 走廊要能站人、看得到天光漏下來：樹幹離路心至少 5.5 m。
		if dc < 5.5:
			continue
		if t < 0.09 and dc < 8.0:
			continue
		if _clearing_dist(p) < 4.5:
			continue
		if _creek_dist(p) < 3.5:
			continue
		if p.distance_to(_stall_pos()) < 9.0:
			continue
		# 傳送點淨空：門是玩家的出口，不能被樹擋住
		if _in_portal_clear(p, 1.5):
			continue
		var bi := _branch_info(p)
		if bi[0] < 0.9 and bi[1] < 0.8:
			continue
		# 密度：節奏 × 噪聲
		var dens := _density_smooth(t)
		dens = 0.20 + dens * 0.80                       # 底線：連疏段也不是空的
		dens *= 0.75 + 0.25 * (_nd.get_noise_2d(x, z) * 0.5 + 0.5)
		if ed < 20.0:
			dens *= 1.25                               # 路邊高密林冠
		# 空地周圍一圈包圍感
		var cl := _clearing_dist(p)
		if cl > 4.5 and cl < 16.0:
			dens = maxf(dens, 0.80)
		if lib.rand() > dens:
			continue
		# 樹幹間距
		var ok := true
		var gx := int(floor(x / cell)); var gz := int(floor(z / cell))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := "%d_%d" % [gx + dx, gz + dz]
				if grid.has(key):
					for q in grid[key]:
						if p.distance_to(q) < 2.5:
							ok = false
							break
				if not ok: break
			if not ok: break
		if not ok:
			continue
		var pick := _pick_tree()
		var kind: String = pick[0]
		var variant: String = pick[1]
		var hr: Array = pick[2]
		# 入口段（t < 0.12）：人間邊界要明亮，雜木（普通樹）比例拉高、大杉退場
		if t < 0.12 and kind == "大杉" and lib.rand() < 0.6:
			kind = "雜木"; variant = "普通樹"; hr = TREES["雜木"][1]
		# 外圍背景帶（離路緣 45 m 外）一律用面數最低的鎮守之杜（3.1k vs 4.9k），
		# 玩家根本走不到那裡，省下來的面數留給路沿。
		if ed >= 45.0:
			kind = "老樹"; variant = "鎮守之杜"; hr = TREES["老樹"][1]
		# 深處 (t > 0.70)：加入枯木與楓 —— 使用者裁定的「深處陰森」訊號。
		# 枯木是全場唯一的 Quaternius 樹（landscape/ 沒有枯樹資產）。
		if t > 0.70 and kind in ["大杉", "針葉", "針葉林"] and lib.rand() < (t - 0.70) * 1.1:
			if lib.rand() < 0.65:
				kind = "枯"; variant = DEAD_TREES[int(lib.rand() * 5) % 5]; hr = [9.0, 14.0]
			else:
				kind = "楓"; variant = "楓樹"; hr = TREES["楓"][1]
		var path := _tree_path(kind, variant)
		var ps := _ps(path)
		var local_h: float = _h_cache[path]
		var target_h := lib.rr(hr[0], hr[1])
		# 林冠遮光：讓「路兩側稍遠」的樹高一點，形成拱頂而不是把路封死。
		# 拱頂只能由「離路心 14 m 以外」的樹撐起——樹冠水平半徑約高度 ×0.45，
		# 12 m 樹 = 5.4 m 冠幅，從 8 m 外伸過來仍蓋住路心（自檢 25/41 三重覆蓋）。
		if dc > 14.0 and dc < 30.0 and kind in ["大杉", "針葉", "針葉林", "老樹"]:
			target_h = maxf(target_h, 13.0)
		# ⚠ 走廊旁那一圈**不能靠矮化**來讓出視線。
		# 樹冠佔全高的比例是固定的，矮化 = 冠也跟著縮小，
		# 結果中景變成一整片光禿樹幹的柱林（v7_屋台.png）。
		# 正確做法是保持樹高、改用「抬高樹冠」——把整棵往下沉，讓樹冠
		# 位置相對上移，視線從樹幹之間穿過去，天際線仍然有葉子。
		var trunk_lift := 0.0
		if dc < 10.0:
			target_h = maxf(target_h, 11.0)          # 別讓近處出現小樹
			trunk_lift = lerpf(2.6, 0.0, (dc - 5.5) / 4.5)
		var s := target_h / maxf(local_h, 0.1)
		var inst := ps.instantiate() as Node3D
		var y := height_at(x, z)
		inst.position = Vector3(x, y - 0.05 - trunk_lift, z)
		inst.rotation.y = lib.rand() * TAU
		# 歪斜（規格：歪斜樹木）— 深處更歪；枯木最歪
		var lean := lib.rr(0.0, 0.05 + t * 0.10) if kind == "枯" else lib.rr(0.0, 0.03)
		inst.rotation.x = lean * (1.0 if lib.rand() < 0.5 else -1.0)
		inst.scale = Vector3(s, s * lib.rr(0.92, 1.1), s)
		var band := 0 if ed < 45.0 else 1
		var parent: Node3D = near if band == 0 else far
		var gname := "%s_%s" % [kind, "近" if band == 0 else "遠"]
		if not groups.has(gname):
			groups[gname] = lib.add(parent, Node3D.new(), gname)
		lib.add(groups[gname], inst, "%s_%04d" % [variant, made])
		if band == 1:
			# 外圍：關投影（規格黑暗來自樹冠，但外圍 300 m 的樹投影玩家看不到）
			for mn in _mesh_nodes(inst):
				(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trunk_log.append([p, target_h * 0.45])     # 樹冠水平半徑約高度的 0.45
		var key2 := "%d_%d" % [gx, gz]
		if not grid.has(key2):
			grid[key2] = PackedVector2Array()
		grid[key2].append(p)
		count[band] += 1
		# ⚠ 樹幹碰撞**只給玩家走得到的樹**（使用者裁定：不要全部樹木做碰撞）。
		#   判準是「在走廊牆以內」，不是固定的 14 m —— 牆在大空地鼓到 27 m，
		#   用 14 m 的話空地外圈那一圈樹會變成可以穿過去的幽靈樹。
		#   牆外的樹一律不給碰撞：玩家根本到不了，碰撞體純浪費。
		#   留 1.2 m 餘裕，站在牆邊也不會看到手伸進樹裡。
		if dc < play_half(t) + 1.2:
			_placed_trunks.append(p)
		made += 1
	# 走廊內樹幹碰撞
	var body := StaticBody3D.new()
	lib.add(lib.root, body, "樹幹碰撞")
	for q in _placed_trunks:
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.38; c.height = 5.0
		sh.shape = c
		sh.position = Vector3(q.x, height_at(q.x, q.y) + 2.5, q.y)
		body.add_child(sh)
		sh.owner = lib.root
	print("[TRAIL] 森林：路沿 %d / 外圍 %d（共 %d 棵，走廊內 %d 根樹幹碰撞，牆外 %d 棵無碰撞）"
		% [count[0], count[1], made, _placed_trunks.size(), made - _placed_trunks.size()])
	_audit_corridor(_trunk_log)


## 走廊自檢：沿主脊取樣，量最近樹幹距離與「樹冠是否蓋住路心」。
##
## v3 的教訓：路沿樹被拔高到 15 m、樹幹離路心 3.6 m，樹冠在路面上空
## 完全閉合，實拍是一張純黑圖。用眼睛看截圖才發現，太慢也太不可靠——
## 產生器每次跑完就自己報告，走廊被封死時直接 push_error。
func _audit_corridor(logs: Array) -> void:
	var worst_gap := INF
	var worst_t := 0.0
	var blocked := 0
	var samples := 41
	for i in samples:
		var t := float(i) / float(samples - 1)
		var p := _spine_pos(t)
		var gap := INF
		var cover := 0
		for e in logs:
			var q: Vector2 = e[0]
			var r: float = e[1]        # 樹冠水平半徑
			var d := p.distance_to(q)
			gap = minf(gap, d)
			if d < r:
				cover += 1
		if gap < worst_gap:
			worst_gap = gap
			worst_t = t
		if cover >= 3:
			blocked += 1
	print("[TRAIL] 走廊自檢：最窄樹幹間隙 %.2f m（t=%.2f）；樹冠三重覆蓋的取樣點 %d/%d"
		% [worst_gap, worst_t, blocked, samples])
	if worst_gap < 4.0:
		push_error("走廊被樹幹擠死：最近 %.2f m < 4.0 m" % worst_gap)
	# ⚠ 三重覆蓋本身不是錯——規格 §9 明文要「樹冠遮光、斑駁陽光」。
	# 真正的失敗是「連樹幹之間都看不穿」，那才是 v3 的全黑。
	# 覆蓋率只當資訊；門檻放寬到「幾乎每個取樣點都被 6 層以上蓋住」。
	if blocked > samples * 9 / 10:
		push_error("樹冠可能過密：%d/%d 取樣點三重覆蓋，拍圖確認是否全黑" % [blocked, samples])


# ══════════════════════════════════════════════════════════════════
# 走廊碰撞牆：沿主脊兩側各一道連續牆 + 南北兩端封口
# ══════════════════════════════════════════════════════════════════
## 使用者裁定：可動範圍兩側做碰撞牆，超出的部分用高牆包圍。
##
## 做法：沿主脊每 PLAY_WALL_STEP 公尺取一段，兩側各放一個 BoxShape3D，
## 盒子**沿路的切線方向**擺（不是軸對齊），所以彎道處牆也跟著彎。
##
## ⚠ 相鄰兩段之間會有縫（外側轉彎處弧長比中心線長）。盒長要比取樣間距
##   長一點（×1.35）讓相鄰段重疊，否則玩家貼著牆走會從縫裡鑽出去。
##   這是實際會發生的：主脊 254 m、最大曲率半徑約 18 m，
##   外側 20 m 處一段 4 m 的直線盒子兩端各短少約 0.5 m。
##
## ⚠ 牆**不給網格**。視覺是樹與岩壁的事，牆只負責擋人；
##   給了網格反而會在林子裡看到一片灰板。
func _build_play_walls() -> void:
	var g := lib.add(lib.root, Node3D.new(), "走廊碰撞牆") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "牆體")
	var n := 0
	var steps := int(ceil(_spine_len / PLAY_WALL_STEP))
	var lo := INF
	var hi := -INF
	for i in steps + 1:
		var t := float(i) / float(steps)
		var c := _spine_pos(t)
		var d := _spine_dir(t)
		var perp := Vector2(-d.y, d.x)
		var ph := play_half(t)
		lo = minf(lo, ph)
		hi = maxf(hi, ph)
		for side in [-1.0, 1.0]:
			var p: Vector2 = c + perp * float(side) * ph
			var sh := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			# x = 厚度、z = 沿路長度（盒子自己的座標系，靠 rotation.y 轉到切線方向）
			bx.size = Vector3(1.0, PLAY_WALL_H, PLAY_WALL_STEP * 1.35)
			sh.shape = bx
			# 牆腳埋進地形 2 m，地形起伏時不會出現可以鑽過去的縫
			sh.position = Vector3(p.x, height_at(p.x, p.y) - 2.0 + PLAY_WALL_H * 0.5, p.y)
			sh.rotation.y = atan2(d.x, d.y)
			body.add_child(sh)
			sh.owner = lib.root
			n += 1
	# 南北兩端封口：擋在傳送點**外側**，玩家走得到傳送點但走不出圖。
	# ⚠ 方向要算對。_spine_dir 一律指向北（−z），所以
	#     南端（t=0）圖外是 −dir 方向、北端（t=1）圖外是 +dir 方向。
	#   兩端都用 +dir 的話，南端封口會落在傳送點**內側** 2.5 m，
	#   玩家永遠走不到南傳送點（實際座標：牆 z=107.5 vs 傳送點 z=108.8）。
	for e in [[0.0, -1.0], [1.0, 1.0]]:
		var t: float = e[0]
		var outward: float = e[1]
		var c := _spine_pos(t)
		var d := _spine_dir(t)
		var ph := play_half(t)
		var p: Vector2 = c + d * outward * 4.0
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(ph * 2.0 + 2.0, PLAY_WALL_H, 1.0)
		sh.shape = bx
		sh.position = Vector3(p.x, height_at(p.x, p.y) - 2.0 + PLAY_WALL_H * 0.5, p.y)
		sh.rotation.y = atan2(d.x, d.y)
		body.add_child(sh)
		sh.owner = lib.root
		n += 1
		print("[TRAIL] 端封口 t=%.0f 位置 (%.1f, %.1f)" % [t, p.x, p.y])
	print("[TRAIL] 走廊碰撞牆：%d 段（每側 %d），可動半寬 %.0f–%.0f m，牆高 %.0f m"
		% [n, steps + 1, lo, hi, PLAY_WALL_H])


# ══════════════════════════════════════════════════════════════════
# 地表植被：蕨/芒草/灌木/菇/苔/花 —— 大量侵入路緣
# ══════════════════════════════════════════════════════════════════
## ══ 地表植被 ══
## [名, 變體, 目標**最大邊** m 範圍, 數量, 路緣偏好(0-1), 林床偏好, 濕地偏好, 只在深處?]
##
## 2026-09-15 使用者裁定：「地上增加許多雜草」。
##   雜草層（矮草／芒草／蕨）數量大幅提高，並新增一層「亂雜草」把林床鋪滿。
##   面數帳：Quaternius 草 155–622 面／株，+3600 株 ≈ +110 萬面，
##   相對場景 766 萬可接受；樹不動。
##   ⚠ 只加在「玩家看得到的帶」內（見 _build_ground_cover 的 ed > COVER_BAND），
##     外圍交給林床貼圖，否則面數翻倍卻看不到。
const COVER := [
	["蕨", ["Fern_1"], [0.6, 1.1], 760, 0.85, 0.7, 0.9, false],
	["芒草", ["Grass_Wispy_Tall", "Grass_Common_Tall"], [0.6, 1.0], 900, 0.9, 0.3, 0.5, false],
	["矮草", ["Grass_Common_Short", "Grass_Wispy_Short"], [0.35, 0.65], 1500, 0.8, 0.5, 0.6, false],
	# 亂雜草：貼著地面的細碎草叢，鋪中距離林床（近距離交給 _build_weed_carpet）
	["雜草", ["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short"], [0.25, 0.55], 900, 0.95, 0.85, 0.7, false],
	["灌木", ["Bush_Common", "Bush_Common_Flowers"], [1.0, 1.8], 220, 0.6, 0.5, 0.3, false],
	["矮竹", ["Plant_7", "Plant_7_Big", "Plant_1_Big"], [0.6, 1.2], 180, 0.5, 0.6, 0.2, false],
	["苔", ["Clover_1", "Clover_2"], [0.15, 0.3], 430, 0.3, 0.9, 0.9, false],
	["菇", ["Mushroom_Common"], [0.2, 0.4], 130, 0.2, 0.9, 0.8, false],
	["靈芝", ["Mushroom_Laetiporus"], [0.3, 0.55], 31, 0.1, 0.9, 0.6, true],
	["野花", ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single"], [0.25, 0.4], 150, 0.7, 0.1, 0.2, false],
]
## 地表植被只長在離路緣多少公尺內（外圍交給貼圖）
const COVER_BAND := 46.0



func _build_ground_cover() -> void:
	var cover := lib.add(lib.root, Node3D.new(), "地表植被") as Node3D
	var total := 0
	for spec in COVER:
		var name: String = spec[0]
		var vars: Array = spec[1]
		var hr: Array = spec[2]
		var n: int = spec[3]
		var edge_pref: float = spec[4]
		var floor_pref: float = spec[5]
		var wet_pref: float = spec[6]
		var deep_only: bool = spec[7]
		var g := lib.add(cover, Node3D.new(), name) as Node3D
		var made := 0
		var tries := 0
		while made < n and tries < n * 40:
			tries += 1
			var x := lib.rr(-HALF + 4.0, HALF - 4.0)
			var z := lib.rr(-HALF + 4.0, HALF - 4.0)
			var p := Vector2(x, z)
			var info := _spine_info(p)
			var t: float = info[1]
			var hw := _half_w(t)
			var d: float = info[0]
			var ed := maxf(0.0, d - hw)
			if deep_only and t < 0.5:
				continue
			# 只在玩家看得到的帶內（路沿 COVER_BAND），外圍交給林床貼圖
			if ed > COVER_BAND:
				continue
			# 路面與路緣淨空：
			# 1. 任何草木不得侵入路心（d < hw * 0.95 禁入）
			if d < hw * 0.95:
				continue
			# 2. 高草/蕨/矮竹/灌木退到路緣外側 (hw * 1.15)，讓路面完全露出來
			if name in ["芒草", "蕨", "矮竹", "灌木"] and d < hw * 1.15:
				continue
			# 3. 入口拍照點與空地視角周邊保護（避免極近前景大草貼鏡頭）
			if z > SPINE_Z0 - 55.0 and d < hw + 1.5:
				continue
			# 屋台區完全淨空，避免穿模桌椅與阻擋視野
			if p.distance_to(_stall_pos()) < 7.0:
				continue
			# 傳送點淨空：草會把傳送門的光環整個埋掉
			if _in_portal_clear(p):
				continue
			# 地藏周圍淨空 —— 不然 1 m 高的芒草會把 1.1 m 的地藏整個埋掉
			# （使用者回報：「地藏我根本看不到在哪裡」）
			var near_jizo := false
			for jq in _jizo_sites:
				if p.distance_to(jq) < 1.7:
					near_jizo = true
					break
			if near_jizo:
				continue
			# 空地範圍完全禁止高草、大灌木、大葉植栽（Plant）侵入，只留零星短草地被
			if _clearing_dist(p) < 2.0:
				if name in ["矮竹", "灌木", "芒草", "蕨"]:
					continue
				# 空地內只留貼地的草（雜草／矮草／苔），其餘退到空地外
				if _clearing_dist(p) < -2.0 and name not in ["矮草", "苔", "雜草"]:
					continue
			var m := mask_at(x, z)
			var w := 0.0
			if d < hw + 2.5:
				w = edge_pref                     # 路緣
			else:
				w = floor_pref * (0.4 + m.g * 0.6)
			w = maxf(w, wet_pref * m.a)
			if _clearing_dist(p) < 0.0:
				w *= 0.3 if name in ["矮草", "野花", "苔", "雜草"] else 0.05
			if lib.rand() > w:
				continue
			var variant: String = vars[int(lib.rand() * vars.size()) % vars.size()]
			var path := NAT + variant + ".gltf"
			var ps := _ps(path)
			var s := lib.rr(hr[0], hr[1]) / maxf(_w_cache[path], 0.05)
			var inst := ps.instantiate() as Node3D
			# 雜草壓扁一點、傾角隨機 —— 同一份網格重複 1700 次，
			# 不做形變會整片看起來是同一株複製貼上。
			var sy := s * (lib.rr(0.7, 1.25) if name == "雜草" else 1.0)
			inst.position = Vector3(x, height_at(x, z) - 0.02, z)
			inst.rotation.y = lib.rand() * TAU
			if name == "雜草":
				inst.rotation.x = lib.rr(-0.14, 0.14)
				inst.rotation.z = lib.rr(-0.14, 0.14)
			inst.scale = Vector3(s, sy, s)
			for mn in _mesh_nodes(inst):
				(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lib.add(g, inst, "%s_%04d" % [variant, made])
			made += 1
		total += made
		print("[TRAIL] 地表 %-4s %5d" % [name, made])
	print("[TRAIL] 地表植被共 %d" % total)


## ══════════════════════════════════════════════════════════════════
## 雜草地毯：路兩側近距離的密集草皮
## ══════════════════════════════════════════════════════════════════
## 使用者要「地上增加許多雜草」。第一次只把 COVER 的數量調高沒有用——
## 那些草平均散在路緣外 46 m 的帶子裡（≈23,000 m²），6000 株算下來
## 每 4 m² 才一叢，實拍還是「大片裸露泥土」（視覺複檢原話）。
##
## 密度要看得出來只能靠**近距離**：這一層專攻路緣外 0–18 m，
## 沿主脊等距鋪點而不是全圖亂撒，命中率高、面數花在玩家看得到的地方。
##
## 面數：Grass_Common_Short 只有 155 面／株（全場最便宜的網格），
## Grass_Wispy_Short 494。取 8:2 混合 ≈ 223 面／株。
##
## ⚠ 密度不能只看「幾叢/m²」，要看**覆蓋率**＝叢數 × 單叢佔地。
##   第一版 6000 叢 / ±18 m 帶 = 0.66 叢/m²，聽起來很密，但每叢只有
##   0.22–0.5 m 寬（佔地 ≈0.09 m²）→ 覆蓋率僅 6%，實拍仍是「大片裸露泥土」。
##   這一版把帶寬收到 ±14 m、叢放大到 0.35–0.85 m，
##   1.27 叢/m² × 0.3 m²/叢 ≈ 38% 覆蓋，才讀得出是草地。
const WEED_BAND := 14.0
const WEED_COUNT := 9000
const WEED_SIZE := [0.35, 0.85]

func _build_weed_carpet() -> void:
	var g := lib.add(lib.root, Node3D.new(), "雜草地毯") as Node3D
	var made := 0
	var tries := 0
	while made < WEED_COUNT and tries < WEED_COUNT * 12:
		tries += 1
		# 沿主脊取點 + 側向偏移：直接生在走廊帶上，不用全圖亂撒再篩
		var t := lib.rr(0.002, 0.998)
		var sp := _spine_pos(t)
		var d := _spine_dir(t)
		var perp := Vector2(-d.y, d.x)
		var side := 1.0 if lib.rand() < 0.5 else -1.0
		var hw := _half_w(t)
		# 偏移分佈偏向路緣（sqrt 讓靠近路的密一點）
		var off := hw + 0.35 + sqrt(lib.rand()) * WEED_BAND
		var p := sp + perp * side * off + Vector2(lib.rr(-1.0, 1.0), lib.rr(-1.0, 1.0))
		if absf(p.x) > HALF - 3.0 or absf(p.y) > HALF - 3.0:
			continue
		# 路面淨空：草不進路心，也不貼著路緣擋路
		var info := _spine_info(p)
		if info[0] < _half_w(info[1]) * 1.05:
			continue
		# 溪、屋台、地藏讓位（與 _build_ground_cover 同一套規則）
		if _creek_dist(p) < 1.2:
			continue
		if p.distance_to(_stall_pos()) < 6.0:
			continue
		# 傳送點淨空（與 _build_ground_cover 同一套規則）
		if _in_portal_clear(p):
			continue
		var near_jizo := false
		for jq in _jizo_sites:
			if p.distance_to(jq) < 1.6:
				near_jizo = true
				break
		if near_jizo:
			continue
		var variant := "Grass_Common_Short" if lib.rand() < 0.8 else "Grass_Wispy_Short"
		var path := NAT + variant + ".gltf"
		var ps := _ps(path)
		var s: float = lib.rr(WEED_SIZE[0], WEED_SIZE[1]) / maxf(float(_w_cache[path]), 0.05)
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(p.x, height_at(p.x, p.y) - 0.03, p.y)
		inst.rotation = Vector3(lib.rr(-0.12, 0.12), lib.rand() * TAU, lib.rr(-0.12, 0.12))
		inst.scale = Vector3(s, s * lib.rr(0.7, 1.3), s)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, inst, "雜草_%04d" % made)
		made += 1
	var area := _spine_len * WEED_BAND * 2.0
	# 覆蓋率估算：叢數 × 單叢佔地（平均邊長的平方 × 0.7 圓形係數）／帶面積
	var avg: float = (WEED_SIZE[0] + WEED_SIZE[1]) * 0.5
	var cover := float(made) * avg * avg * 0.7 / maxf(area, 1.0)
	print("[TRAIL] 雜草地毯：%d 叢，帶寬 ±%.0f m，密度 %.2f 叢/m²，估覆蓋率 %.0f%%"
		% [made, WEED_BAND, float(made) / maxf(area, 1.0), cover * 100.0])


# ══════════════════════════════════════════════════════════════════
# 岩石與倒木
# ══════════════════════════════════════════════════════════════════
func _build_rocks_and_logs() -> void:
	var g := lib.add(lib.root, Node3D.new(), "岩石與倒木") as Node3D
	var rocks := lib.add(g, Node3D.new(), "苔石") as Node3D
	var pebbles := lib.add(g, Node3D.new(), "碎石") as Node3D
	var logs := lib.add(g, Node3D.new(), "倒木_佔位") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "岩石碰撞")
	# 苔石：半埋、成叢不均勻
	var made := 0
	var tries := 0
	var clusters := []
	for i in 10:                     # 220 m 版
		var t := lib.rr(0.05, 0.98)
		var side := 1.0 if lib.rand() < 0.5 else -1.0
		var c := _spine_pos(t) + Vector2(-_spine_dir(t).y, _spine_dir(t).x) * side * lib.rr(2.5, 18.0)
		clusters.append(c)
	for c in clusters:
		var n := 2 + int(lib.rand() * 4)
		for k in n:
			var p: Vector2 = c + Vector2(lib.rr(-4.0, 4.0), lib.rr(-4.0, 4.0))
			if _clearing_dist(p) < -8.0 or _creek_dist(p) < 1.0:
				continue
			var v := "Rock_Medium_%d" % (1 + int(lib.rand() * 3) % 3)
			var path := NAT + v + ".gltf"
			var ps := _ps(path)
			var target_h := lib.rr(0.5, 1.6)
			var s := target_h / maxf(_h_cache[path], 0.1)
			# ⚠ 苔石叢是「路旁」的，不是路上的。cluster 中心撒在離路心
			#   2.5 m 起，再 ±4 m 抖動 → 石頭中心可能落在路心上；
			#   體檢實測有 6 顆淨空為負（最深 −0.54 m）。
			#   用石頭自己的水平半徑 + 走廊淨空判斷，不夠就丟掉這顆。
			var ri := _spine_info(p)
			var rrad: float = 0.5 * float(_w_cache[path]) * s * 1.3
			if ri[0] - rrad < maxf(1.5, _half_w(ri[1]) + 0.4):
				continue
			var inst := ps.instantiate() as Node3D
			var bury := lib.rr(0.15, 0.45)           # 半埋
			inst.position = Vector3(p.x, height_at(p.x, p.y) - target_h * bury, p.y)
			inst.rotation = Vector3(lib.rr(-0.25, 0.25), lib.rand() * TAU, lib.rr(-0.25, 0.25))
			inst.scale = Vector3(s * lib.rr(0.8, 1.3), s, s * lib.rr(0.8, 1.3))
			lib.add(rocks, inst, "%s_%03d" % [v, made])
			if target_h > 0.7:
				var sh := CollisionShape3D.new()
				var sp := SphereShape3D.new()
				sp.radius = target_h * 0.55
				sh.shape = sp
				sh.position = inst.position + Vector3(0, target_h * 0.3, 0)
				body.add_child(sh); sh.owner = lib.root
			made += 1
	# 路面碎石（規格：路面有碎石）
	var pm := 0
	for i in 310:                    # 220 m 版
		var t := lib.rr(0.0, 1.0)
		var d := _spine_dir(t)
		var hw := _half_w(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(-hw * 1.3, hw * 1.3)
		var v: String = ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_2", "Pebble_Square_5"][int(lib.rand() * 4) % 4]
		var path: String = NAT + v + ".gltf"
		var ps := _ps(path)
		var s := lib.rr(0.12, 0.3) / maxf(_w_cache[path], 0.05)
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(p.x, height_at(p.x, p.y) - 0.02, p.y)
		inst.rotation.y = lib.rand() * TAU
		inst.scale = Vector3(s, s, s)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(pebbles, inst, "%s_%03d" % [v, pm])
		pm += 1
	# 倒木：Meshy 缺件 → 用 Log_Cluster 暫代 + 佔位標記；規格：部分倒木橫跨小路
	var lm := 0
	for spec in [[0.16, true], [0.30, false], [0.39, true], [0.55, false], [0.74, true], [0.86, false], [0.93, true]]:
		var t: float = spec[0]
		var across: bool = spec[1]
		var d := _spine_dir(t)
		var c := _spine_pos(t)
		var p: Vector2 = c if across else c + Vector2(-d.y, d.x) * lib.rr(4.0, 9.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var mk := Marker3D.new()
		mk.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		mk.rotation.y = atan2(d.x, d.y) + (PI * 0.5 if across else lib.rr(-0.6, 0.6))
		mk.set_meta("meshy", "倒木/腐木 2-3 種，長 4-7 m，%s" % ("橫跨小路" if across else "路旁"))
		lib.add(logs, mk, "倒木_%02d%s" % [lm, "_橫跨" if across else ""])
		# 暫代倒木：一根**圓柱**橫躺。
		# ⚠ 不能用 Log_Cluster 拉長。那是「一捆短柴薪」，端面有淺色年輪，
		#   非等比拉 4.5× 之後年輪變成螺旋紋 —— 使用者的原話是「肉桂捲蛋糕」。
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.30
		cyl.bottom_radius = 0.38          # 一頭粗一頭細，像真的樹幹
		cyl.height = lib.rr(4.5, 7.0)
		cyl.radial_segments = 10
		trunk.mesh = cyl
		trunk.material_override = lib.pbr("fallen_log", "bark_cedar", 0.6, Color(0.52, 0.47, 0.40))
		trunk.position = mk.position + Vector3(0, 0.32, 0)
		# 躺平：繞 Z 轉 90° 讓圓柱軸由縱轉橫，再依 mk 的朝向擺
		trunk.rotation = Vector3(0.0, mk.rotation.y, PI * 0.5)
		lib.add(logs, trunk, "暫代倒木_%02d" % lm)
		if across:
			var sh := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(5.0, 0.9, 1.2)
			sh.shape = bx
			sh.position = mk.position + Vector3(0, 0.45, 0)
			sh.rotation.y = mk.rotation.y
			body.add_child(sh); sh.owner = lib.root
		lm += 1
	print("[TRAIL] 苔石 %d、碎石 %d、倒木 %d（%d 橫跨）" % [made, pm, lm, 4])


# ══════════════════════════════════════════════════════════════════
# 岩壁隘口（r3 新節點）：路被兩道岩脊夾到 1.5 m 寬
# ══════════════════════════════════════════════════════════════════
## 地形已經在 height_at() 把兩側抬成岩脊；這裡在脊面上實鋪岩塊，
## 讓它讀起來是「岩壁」而不是「土坡」。
##
## ⚠ r3 第一版把岩塊撒在「離路心 3.2 m 起」，但隘口的路半寬只有 0.82 m，
##   而近路那批岩塊目標高 3.4 m、水平半徑同量級（≈1.7 m）再乘隨機 1.3×
##   → 岩體邊緣壓到離路心 1.0 m，比路緣還內側，路被整個堵死。
##   這裡改成**用岩塊自己的水平半徑反推擺放距離**：
##       離路心 = 需要的淨空(CLEAR) + 這顆岩塊的水平半徑
##   淨空由路半寬決定，不是寫死的常數，改路寬時不會又撞回來。
const GATE_CLEAR := 1.9          # 路心兩側保證淨空（玩家膠囊 0.4 + 體檢門檻 1.5 + 餘裕）

func _build_gate() -> void:
	var g := lib.add(lib.root, Node3D.new(), "岩壁隘口") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "岩壁碰撞")
	var n := 0
	var closest := INF
	for i in 46:
		# 沿主脊 T_GATE ± 0.05 撒點
		var t := T_GATE + lib.rr(-0.05, 0.05)
		var d := _spine_dir(t)
		var perp := Vector2(-d.y, d.x)
		var side := 1.0 if i % 2 == 0 else -1.0
		var v := "Rock_Medium_%d" % (1 + i % 3)
		var path := NAT + v + ".gltf"
		var ps := _ps(path)
		# 先決定大小：外層小、內層大，由 rank 決定（0 = 貼著路的那一圈）
		var rank := lib.rand()
		var th := lerpf(3.2, 1.0, rank) * lib.rr(0.85, 1.2)
		var s := th / maxf(_h_cache[path], 0.1)
		var sx := s * lib.rr(0.85, 1.3)
		var sz := s * lib.rr(0.85, 1.3)
		var sy := s * lib.rr(0.9, 1.4)
		var yaw := lib.rand() * TAU
		var tilt_x := lib.rr(-0.3, 0.3)
		var tilt_z := lib.rr(-0.3, 0.3)
		# ⚠ 半徑要用**旋轉後的實際 AABB**算，不是本地寬 × 縮放。
		#   第一版用 0.5 * w_cache * scale * 1.05 估，忽略了 yaw 讓對角線
		#   伸出去、以及岩塊原點不在 AABB 中心 → 仍有 12 顆侵入走廊
		#   （體檢實測最小淨空 −0.20 m）。這裡直接把實際 basis 套上去量。
		var basis := Basis.from_euler(Vector3(tilt_x, yaw, tilt_z)).scaled(Vector3(sx, sy, sz))
		var wb: AABB = Transform3D(basis, Vector3.ZERO) * _aabb_of(ps)
		# 岩塊原點不一定在 AABB 中心 → 取「原點到 AABB 最遠邊」
		var rad := maxf(
			maxf(absf(wb.position.x), absf(wb.position.x + wb.size.x)),
			maxf(absf(wb.position.z), absf(wb.position.z + wb.size.z)))
		# 擺放距離 = 保證淨空 + 路半寬 + 自己的半徑 + 隨機外推
		var off := maxf(GATE_CLEAR, _half_w(t)) + rad + lib.rr(0.0, 5.0) * rank
		var p := _spine_pos(t) + perp * side * off
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(p.x, height_at(p.x, p.y) - th * lib.rr(0.1, 0.3), p.y)
		inst.rotation = Vector3(tilt_x, yaw, tilt_z)
		inst.scale = Vector3(sx, sy, sz)
		lib.add(g, inst, "隘口岩_%02d" % n)
		closest = minf(closest, off - rad)
		if off - rad < 4.0:
			var sh := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = rad
			sh.shape = sp
			sh.position = inst.position + Vector3(0, th * 0.35, 0)
			body.add_child(sh); sh.owner = lib.root
		n += 1
	print("[TRAIL] 岩壁隘口：t=%.2f 位置 %s，岩塊 %d，路半寬 %.2f m，岩體最近邊緣離路心 %.2f m"
		% [T_GATE, _spine_pos(T_GATE), n, _half_w(T_GATE), closest])
	if closest < GATE_CLEAR - 0.01:
		push_error("隘口被岩塊堵死：岩體邊緣離路心 %.2f m < %.2f m" % [closest, GATE_CLEAR])


# ══════════════════════════════════════════════════════════════════
# 人類文明遺跡：越靠人里越多
# ══════════════════════════════════════════════════════════════════
func _build_human_traces() -> void:
	var g := lib.add(lib.root, Node3D.new(), "人類遺跡") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "遺跡碰撞")
	# 入口：兩塊界碑（Meshy 佔位）+ 警告牌 + 夜雀屋台小木牌 + 柵欄 + 地藏 + 燈籠
	var te := T_ENTRANCE
	var c := _spine_pos(te)
	var d := _spine_dir(te)
	var perp := Vector2(-d.y, d.x)
	var hw := _half_w(te)
	var ent := lib.add(g, Node3D.new(), "獸道入口") as Node3D
	for side in [-1.0, 1.0]:
		var p: Vector2 = c + perp * side * (hw + 1.2)
		var mk := Marker3D.new()
		mk.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		mk.rotation.y = atan2(d.x, d.y)
		mk.set_meta("meshy", "石製界碑，高 1.2-1.5 m，風化長苔，「人間之里文明區域結束」")
		lib.add(ent, mk, "界碑_%s" % ("左" if side < 0 else "右"))
		var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(0.6, 1.4, 0.5)
		sh.shape = bx; sh.position = mk.position + Vector3(0, 0.7, 0); body.add_child(sh); sh.owner = lib.root
	var wp := c + perp * (hw + 2.6) + d * 1.5
	var wm := Marker3D.new()
	wm.position = Vector3(wp.x, height_at(wp.x, wp.y), wp.y)
	wm.rotation.y = atan2(d.x, d.y) + 0.3
	wm.set_meta("meshy", "木製警告牌，高 1.8 m，歪斜：「妖怪出沒，夜間通行注意」")
	lib.add(ent, wm, "警告牌")
	var sp := c - perp * (hw + 2.2) - d * 2.0
	var sm := Marker3D.new()
	sm.position = Vector3(sp.x, height_at(sp.x, sp.y), sp.y)
	sm.rotation.y = atan2(d.x, d.y) - 0.5
	sm.set_meta("meshy", "隨意小木牌，高 1.1 m，手寫：「夜雀屋台 →」")
	lib.add(ent, sm, "小木牌_夜雀屋台")
	# 柵欄：入口兩側往外延伸，越遠越破
	var fence_ps := _ps(LP + "Fence_Wood.gltf")
	var fn := 0
	for side in [-1.0, 1.0]:
		for k in 5:
			if k >= 3 and lib.rand() < 0.5:
				continue          # 破損缺段
			var p: Vector2 = c + perp * side * (hw + 2.0 + 4.0 * k + 2.0) - d * lib.rr(0.0, 1.0)
			var inst := fence_ps.instantiate() as Node3D
			inst.position = Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y)
			inst.rotation.y = atan2(perp.x, perp.y) + lib.rr(-0.08, 0.08)
			inst.rotation.z = lib.rr(-0.06, 0.06) * float(k)      # 越遠越歪
			inst.scale = Vector3(1.0, lib.rr(0.85, 1.0), 1.0)
			lib.add(ent, inst, "木柵欄_%s%d" % ["左" if side < 0 else "右", k])
			fn += 1
	# 燈籠與地藏（入口一組）
	_lantern(ent, c - perp * (hw + 1.0) + d * 6.0, true, body)
	# 入口地藏由 JIZO_SPECS[0]（t=0.07）統一負責，這裡不再另放
	# 沿路：地藏/舊路標/燈籠 —— 越深越少，且越破
	var along := lib.add(g, Node3D.new(), "沿路遺跡") as Node3D
	# 沿路遺跡：燈籠與路標（地藏另外走 JIZO_SPECS，位置要與植被讓位一致）
	var specs := [
		[0.13, "燈籠", true], [T_JIZO + 0.02, "路標", 0],
		[0.35, "燈籠", false], [0.47, "路標", 0], [0.62, "燈籠", false],
		[0.88, "路標", 0],
	]
	# 地藏：座標由 JIZO_SPECS + _jizo_base() 決定，與 _plan_jizo_sites() 同源
	for js in JIZO_SPECS:
		_jizo(along, _jizo_base(js[0], js[2]), js[1], body)
	for s in specs:
		var t: float = s[0]
		var kind: String = s[1]
		var dd := _spine_dir(t)
		var pp := _spine_pos(t) + Vector2(-dd.y, dd.x) * (_half_w(t) + lib.rr(0.8, 2.2)) * (1.0 if lib.rand() < 0.5 else -1.0)
		match kind:
			"燈籠": _lantern(along, pp, s[2], body)
			"路標":
				var mk := Marker3D.new()
				mk.position = Vector3(pp.x, height_at(pp.x, pp.y), pp.y)
				mk.rotation.y = atan2(dd.x, dd.y) + lib.rr(-0.4, 0.4)
				mk.rotation.z = lib.rr(-0.15, 0.15)
				mk.set_meta("meshy", "木製路標，高 1.6 m，字跡模糊，歪斜")
				lib.add(along, mk, "舊路標_t%02d" % int(t * 100))
	# 小溪木橋（Meshy 佔位 + 暫代木板）
	# ⚠ 橋面高度要讀**兩岸的實際地形**，不能用 height_at(溪心)+固定值。
	#   舊公式 +0.9 是溪谷還只切 0.9 m 時寫的；谷加深到 2.2 m 之後，
	#   橋整個浮在旱地上、離水面老遠（v10_小溪.png）。
	# 橋位：用實際解出的路／溪交會點，不是 _spine_pos(T_CREEK)
	var cx := _creek_crossing()
	var cc: Vector2 = cx[1]
	var creek_z: float = _creek_z0 + _creek_wiggle(cc.x)
	# 橋跨在溪上：取南北兩岸（各離溪心 4 m）地形的較高者當橋面
	var bank_n := terrain_y(cc.x, creek_z - 4.5)
	var bank_s := terrain_y(cc.x, creek_z + 4.5)
	var deck_y := maxf(bank_n, bank_s) + 0.15
	var bm := Marker3D.new()
	bm.position = Vector3(cc.x, deck_y, creek_z)
	# 橋要橫跨溪流（溪東西向 → 橋南北向），不是順著主脊方向
	bm.rotation.y = 0.0
	bm.set_meta("meshy", "小木橋，長 9 m 寬 1.8 m，木板腐朽長苔，無欄杆或半截欄杆")
	lib.add(g, bm, "小木橋_佔位")
	var plank := MeshInstance3D.new()
	var bx := BoxMesh.new(); bx.size = Vector3(1.8, 0.12, 10.0)
	plank.mesh = bx
	# 腐朽木板：dark_wood 貼圖本身是鮮紅褐（實拍像新漆的紅橋），
	# 換 planks 並壓成灰褐 —— 規格 §4 要「風化、長苔、不可看起來像新建造」
	plank.material_override = lib.pbr("plank_rotten", "planks", 0.5, Color(0.46, 0.44, 0.38))
	plank.position = bm.position + Vector3(0, 0.06, 0)
	plank.rotation.y = bm.rotation.y
	lib.add(g, plank, "暫代木橋")
	var sh := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(1.8, 0.12, 10.0)
	sh.shape = bs; sh.position = plank.position; sh.rotation.y = plank.rotation.y
	body.add_child(sh); sh.owner = lib.root
	print("[TRAIL] 木橋：橋面 y=%.2f（北岸 %.2f 南岸 %.2f），溪心 z=%.1f" % [deck_y, bank_n, bank_s, creek_z])
	print("[TRAIL] 人類遺跡：柵欄 %d 段、沿路 %d 組、木橋 1" % [fn, specs.size()])


func _lantern(parent: Node3D, p: Vector2, intact: bool, body: StaticBody3D) -> void:
	var ps := _ps(LP + "StoneLantern.gltf")
	# ⚠ 燈籠底座半徑約 0.5 m，呼叫端只給「路緣 + 0.8~2.2 m」的中心距離，
	#   窄路段（隘口半寬 1.1 m）會讓燈體壓進走廊（體檢實測 1.04 m < 1.5）。
	#   這裡統一把燈籠往路外推到走廊之外，不改呼叫端的意圖。
	var li := _spine_info(p)
	var need: float = maxf(1.5, _half_w(li[1]) + 0.4) + 0.55
	if li[0] < need:
		var dir := (p - _spine_pos(li[1])).normalized()
		if dir.length() < 0.01:
			var sd := _spine_dir(li[1])
			dir = Vector2(-sd.y, sd.x)
		p = _spine_pos(li[1]) + dir * need
	var inst := ps.instantiate() as Node3D
	inst.position = Vector3(p.x, height_at(p.x, p.y) - (0.0 if intact else 0.25), p.y)
	inst.rotation.y = lib.rand() * TAU
	if not intact:
		inst.rotation.z = lib.rr(0.2, 0.5)       # 倒塌/歪斜
		inst.rotation.x = lib.rr(-0.2, 0.2)
	lib.add(parent, inst, "石燈籠_%s_%d" % ["完整" if intact else "破損", parent.get_child_count()])
	var mk := Marker3D.new()
	mk.position = inst.position
	mk.set_meta("meshy", "小型石燈籠 %s，高 1.6 m，長苔" % ("完整" if intact else "破損/倒塌"))
	lib.add(parent, mk, "燈籠佔位_%d" % parent.get_child_count())
	var sh := CollisionShape3D.new(); var c := CylinderShape3D.new(); c.radius = 0.35; c.height = 1.6
	sh.shape = c; sh.position = inst.position + Vector3(0, 0.8, 0); body.add_child(sh); sh.owner = lib.root


## 地藏位置用的獨立 RNG：種子由該組的基準座標決定。
##
## ⚠ 一定要獨立於 lib 的主亂數序列。_plan_jizo_sites() 得在植被生成前
##   算出座標、_jizo() 在更後面才真正擺放，兩者必須得到同一組數字；
##   若共用主序列，預算會偷走亂數讓後面所有散佈位移。
func _jizo_rng(p: Vector2) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(round(p.x * 100.0)), int(round(p.y * 100.0)))) ^ SEED
	return rng


## 預先算出所有地藏的世界座標（供地表植被讓位）。
## 位置公式必須與 _build_human_traces() 裡的呼叫端**完全一致**。
func _plan_jizo_sites() -> void:
	_jizo_sites.clear()
	for spec in JIZO_SPECS:
		var t: float = spec[0]
		var cnt: int = spec[1]
		var base: Vector2 = _jizo_base(t, spec[2])
		var rng := _jizo_rng(base)
		for i in cnt:
			_jizo_sites.append(base + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.5, 0.5)) * float(i))
	print("[TRAIL] 地藏預定 %d 尊（植被讓開 1.7 m）" % _jizo_sites.size())


## 沿主脊 t 的地藏基準座標（側向 side：+1 左 / -1 右）
func _jizo_base(t: float, side: float) -> Vector2:
	var d := _spine_dir(t)
	return _spine_pos(t) + Vector2(-d.y, d.x) * side * (_half_w(t) + 2.3)


func _jizo(parent: Node3D, p: Vector2, n: int, body: StaticBody3D) -> void:
	# 暫代地藏：底座 + 身 + 頭 + 紅頭巾。
	#
	# ⚠ 舊版是一根 0.8 m 高、半徑 0.18 m 的膠囊，站在 1 m 高的芒草叢裡
	#   完全看不到（使用者：「地藏我根本看不到在哪裡」）。
	#   地藏是玩家的路標，必須讀得出來：加寬底座、頭與身分開、紅頭巾當
	#   色彩訊號 —— 紅色在整片綠褐森林裡是唯一的暖色。
	#
	# 位置用**獨立 RNG**（種子由座標決定），不碰 lib 的主亂數序列 ——
	# _plan_jizo_sites() 要能在植被之前算出同一組座標，若這裡偷走亂數，
	# 後面所有散佈都會位移。
	var stone := lib.pbr("jizo_stone", "stone_wall", 0.3, Color(0.72, 0.72, 0.68))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.68, 0.13, 0.11)
	cloth.roughness = 0.95
	var rng := _jizo_rng(p)
	for i in n:
		var q := p + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.5, 0.5)) * float(i)
		var gy := height_at(q.x, q.y)
		var lean := rng.randf_range(-0.10, 0.10)
		var yaw := rng.randf() * TAU
		var mk := Marker3D.new()
		mk.position = Vector3(q.x, gy, q.y)
		mk.rotation = Vector3(0.0, yaw, lean)
		mk.set_meta("meshy", "風化地藏，總高 1.0-1.2 m（含底座），長苔，局部破損，紅頭巾與圍兜")
		lib.add(parent, mk, "地藏_%02d_%d" % [parent.get_child_count(), i])
		var g := Node3D.new()
		g.position = mk.position
		g.rotation = mk.rotation
		lib.add(parent, g, "暫代地藏_%02d_%d" % [parent.get_child_count(), i])
		# 底座（方石）
		var base := MeshInstance3D.new()
		var bm2 := BoxMesh.new(); bm2.size = Vector3(0.52, 0.20, 0.46)
		base.mesh = bm2
		base.material_override = stone
		base.position = Vector3(0, 0.10, 0)
		lib.add(g, base, "底座")
		# 身（圓柱，比膠囊粗）
		var torso := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.19; tc.bottom_radius = 0.24; tc.height = 0.56; tc.radial_segments = 10
		torso.mesh = tc
		torso.material_override = stone
		torso.position = Vector3(0, 0.20 + 0.28, 0)
		lib.add(g, torso, "身")
		# 頭（球）
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new(); hs.radius = 0.17; hs.height = 0.32; hs.radial_segments = 12; hs.rings = 7
		head.mesh = hs
		head.material_override = stone
		head.position = Vector3(0, 0.20 + 0.56 + 0.15, 0)
		lib.add(g, head, "頭")
		# 紅頭巾（扁圓錐蓋在頭上）—— 森林裡唯一的暖色，遠遠就認得出
		var cap := MeshInstance3D.new()
		var cc4 := CylinderMesh.new()
		cc4.top_radius = 0.02; cc4.bottom_radius = 0.21; cc4.height = 0.16; cc4.radial_segments = 12
		cap.mesh = cc4
		cap.material_override = cloth
		cap.position = Vector3(0, 0.20 + 0.56 + 0.26, 0)
		lib.add(g, cap, "紅頭巾")
		# 圍兜
		var bib := MeshInstance3D.new()
		var bb := BoxMesh.new(); bb.size = Vector3(0.30, 0.26, 0.03)
		bib.mesh = bb
		bib.material_override = cloth
		bib.position = Vector3(0, 0.20 + 0.44, 0.20)
		lib.add(g, bib, "圍兜")
		var sh := CollisionShape3D.new(); var c := CylinderShape3D.new(); c.radius = 0.28; c.height = 1.1
		sh.shape = c; sh.position = mk.position + Vector3(0, 0.55, 0); body.add_child(sh); sh.owner = lib.root
		_jizo_sites.append(q)


# ══════════════════════════════════════════════════════════════════
# 大空地：古樹 Hero、地藏、倒塌燈籠、水潭、紅布、酒瓶、螢火蟲
# ══════════════════════════════════════════════════════════════════
func _build_clearing() -> void:
	var g := lib.add(lib.root, Node3D.new(), "獸道大空地") as Node3D
	var c := _spine_pos(T_CLEARING)
	var body := StaticBody3D.new()
	lib.add(g, body, "空地碰撞")
	# 古樹 Hero 佔位 + 暫代：古老神木（使用闊葉巨木，蒼翠深綠），置於空地偏西北側
	# 古樹是這張圖的視覺錨點，要在空地正中央附近——偏太多的話從路上走進來
	# 看不到它。前一版偏 6 m，俯瞰圖裡整棵消失在邊緣。
	var tp := c + Vector2(-1.5, 1.0)
	var mk := Marker3D.new()
	mk.position = Vector3(tp.x, height_at(tp.x, tp.y), tp.y)
	mk.set_meta("meshy", "Hero：巨大古老神木，高 20-22 m，樹冠直徑 18 m，樹洞，樹根隆起，掛舊紅布")
	lib.add(g, mk, "古樹_Hero佔位")
	var path := LS + "鎮守之杜.glb"
	var ps := _ps(path)
	var inst := ps.instantiate() as Node3D
	var s := 21.0 / maxf(_h_cache[path], 1.0)
	inst.position = mk.position - Vector3(0, 0.2, 0)
	inst.scale = Vector3(s * 1.05, s, s * 1.05)
	inst.rotation.y = 0.8
	lib.add(g, inst, "暫代古樹")
	var sh := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 1.6; cy.height = 8.0
	sh.shape = cy; sh.position = mk.position + Vector3(0, 4.0, 0); body.add_child(sh); sh.owner = lib.root
	# 3–5 尊地藏、一座倒塌燈籠
	_jizo(g, c + Vector2(6.5, 4.0), 4, body)
	_lantern(g, c + Vector2(-7.0, -4.5), false, body)
	# 水潭（小）—— 同小溪：連續放射網格，不用逐格挑或圓盤。
	# 圓盤試過 2.6/1.9/1.4 都埋地；逐格挑不埋了但邊界成方塊。
	var pond := c + Vector2(6.0, -7.0)
	# 水位：潭心周圍地形最低點 + 15 cm
	var p_lo := INF
	for k in 13:
		var a0 := float(k) / 13.0 * TAU
		p_lo = minf(p_lo, terrain_y(pond.x + cos(a0) * 1.2, pond.y + sin(a0) * 1.2))
	p_lo = minf(p_lo, terrain_y(pond.x, pond.y))
	var p_level := p_lo + 0.15
	var rings := 5
	var segs := 20
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每個方位各自找「地形升過水位」的半徑 → 潭緣貼著實際窪地，不是正圓
	var radii := PackedFloat32Array()
	radii.resize(segs)
	for sgi in segs:
		var ang := float(sgi) / float(segs) * TAU
		var rr := 0.6
		for k in range(1, 16):
			var r2 := float(k) * 0.35
			if terrain_y(pond.x + cos(ang) * r2, pond.y + sin(ang) * r2) > p_level:
				break
			rr = r2
		radii[sgi] = rr
	for ri in rings + 1:
		var rf := float(ri) / float(rings)
		for sgi in segs:
			var ang := float(sgi) / float(segs) * TAU
			var r2: float = radii[sgi] * rf
			pst.set_uv(Vector2(cos(ang) * rf * 0.5 + 0.5, sin(ang) * rf * 0.5 + 0.5))
			# bank：中心 0、外緣 1（water.gdshader 契約）
			pst.set_color(Color(rf, 1.0, 0.5))
			pst.set_normal(Vector3.UP)
			pst.add_vertex(Vector3(pond.x + cos(ang) * r2, p_level, pond.y + sin(ang) * r2))
	for ri in rings:
		for sgi in segs:
			var s2 := (sgi + 1) % segs
			var a := ri * segs + sgi
			var b := ri * segs + s2
			var cc3 := (ri + 1) * segs + sgi
			var d3 := (ri + 1) * segs + s2
			pst.add_index(a); pst.add_index(cc3); pst.add_index(b)
			pst.add_index(b); pst.add_index(cc3); pst.add_index(d3)
	var pm := MeshInstance3D.new()
	pm.mesh = pst.commit()
	pm.material_override = load("res://assets/materials/east_river_water.tres")
	lib.add(g, pm, "小水潭")
	print("[TRAIL] 小水潭：%d×%d 放射網格，水位 %.2f" % [rings, segs, p_level])
	# 苔石、倒木（空地邊緣）
	for i in 6:
		var a := lib.rr(0.0, TAU)
		var r := CLEARING_R * lib.rr(0.6, 0.95)
		var p := c + Vector2(cos(a), sin(a)) * r
		var v := "Rock_Medium_%d" % (1 + i % 3)
		var rp := NAT + v + ".gltf"
		var rps := _ps(rp)
		var th := lib.rr(0.5, 1.2)
		var rs := th / maxf(_h_cache[rp], 0.1)
		var ri := rps.instantiate() as Node3D
		ri.position = Vector3(p.x, height_at(p.x, p.y) - th * 0.3, p.y)
		ri.rotation.y = lib.rand() * TAU
		ri.scale = Vector3(rs, rs, rs)
		lib.add(g, ri, "空地苔石_%d" % i)
	# 妖怪留下的酒瓶與碗（lowpoly 暫代）
	var yk := lib.add(g, Node3D.new(), "妖怪遺留物") as Node3D
	for i in 5:
		var p := tp + Vector2(lib.rr(-4.0, 4.0), lib.rr(2.0, 6.0))
		var v: String = ["CeremicPot", "Basket_S", "CeremicPot", "Barrel", "CeremicPot"][i]
		var ps2 := _ps(LP + v + ".gltf")
		var it := ps2.instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		if v == "CeremicPot" and lib.rand() < 0.5:
			it.rotation.z = 1.4       # 倒著的
		it.scale = Vector3(0.6, 0.6, 0.6) if v == "Barrel" else Vector3.ONE
		lib.add(yk, it, "%s_%d" % [v, i])
	# 紅布（掛樹枝）：細長的薄板，紅色
	for i in 3:
		var a := lib.rr(0.0, TAU)
		var bm := MeshInstance3D.new()
		var bx := BoxMesh.new(); bx.size = Vector3(0.12, 1.4, 0.01)
		bm.mesh = bx
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.10, 0.08)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material_override = mat
		bm.position = mk.position + Vector3(cos(a) * lib.rr(3.0, 6.0), lib.rr(5.0, 9.0), sin(a) * lib.rr(3.0, 6.0))
		bm.rotation = Vector3(lib.rr(-0.2, 0.2), a, lib.rr(-0.3, 0.3))
		lib.add(g, bm, "舊紅布_%d" % i)
	# 螢火蟲：GPUParticles3D，預設白天關閉，夜間才發光；光點微縮為柔和螢光
	var ff := GPUParticles3D.new()
	ff.amount = 45
	ff.lifetime = 4.0
	ff.preprocess = 1.0
	ff.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 6, 30))
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm2.emission_box_extents = Vector3(10.0, 1.2, 10.0)
	pm2.gravity = Vector3.ZERO
	pm2.initial_velocity_min = 0.1; pm2.initial_velocity_max = 0.4
	pm2.turbulence_enabled = true
	pm2.turbulence_noise_strength = 0.8
	pm2.turbulence_noise_scale = 2.0
	pm2.scale_min = 0.02; pm2.scale_max = 0.05
	pm2.color = Color(0.65, 1.0, 0.45, 0.8)
	ff.process_material = pm2
	var qm := QuadMesh.new(); qm.size = Vector2(0.12, 0.12)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(0.65, 1.0, 0.45, 0.8)
	fm.emission_enabled = true
	fm.emission = Color(0.5, 1.0, 0.3)
	fm.emission_energy_multiplier = 2.0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = fm
	ff.draw_pass_1 = qm
	ff.position = Vector3(c.x, height_at(c.x, c.y) + 1.2, c.y)
	ff.emitting = false      # 白天關閉！夜間由夜間燈光系統開啟
	lib.add(g, ff, "螢火蟲")
	print("[TRAIL] 大空地：中心 %s 半徑 %.0f m" % [c, CLEARING_R])


# ══════════════════════════════════════════════════════════════════
# 夜雀屋台：Hero 佔位 + 暫代桌椅 + 暖色燈
# ══════════════════════════════════════════════════════════════════
func _build_stall_site() -> void:
	var g := lib.add(lib.root, Node3D.new(), "夜雀屋台區") as Node3D
	var c := _spine_pos(T_STALL)
	var d := _spine_dir(T_STALL)
	var perp := Vector2(-d.y, d.x)
	var sp := _stall_pos()
	var mk := Marker3D.new()
	mk.position = Vector3(sp.x, height_at(sp.x, sp.y), sp.y)
	mk.rotation.y = atan2(-perp.x, -perp.y)      # 面向路
	mk.set_meta("meshy", "Hero：小型移動式日式屋台，木造 2.5-3 m 寬，布簾、紙燈籠、炭火、碗、酒瓶、食材箱、木牌")
	lib.add(g, mk, "夜雀屋台_Hero佔位")
	var body := StaticBody3D.new()
	lib.add(g, body, "屋台碰撞")
	# 暫代：市集屋台（Meshy 現成）縮到 2.8 m
	var ps := load("res://assets/market/屋台陶瓷攤.glb") as PackedScene
	if ps != null:
		var inst := ps.instantiate() as Node3D
		var h := _mesh_h(ps)
		var box := _aabb_of(ps)
		var s := 2.8 / maxf(box.size.x, 0.5)
		inst.position = mk.position - Vector3(0, box.position.y * s, 0)   # Meshy 原點居中 → 抬到底
		inst.rotation.y = mk.rotation.y
		inst.scale = Vector3(s, s, s)
		lib.add(g, inst, "暫代屋台")
	var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(3.0, 2.4, 1.6)
	sh.shape = bx; sh.position = mk.position + Vector3(0, 1.2, 0); sh.rotation.y = mk.rotation.y
	body.add_child(sh); sh.owner = lib.root
	# 桌椅
	for i in 2:
		var tp := sp - perp * (2.6 + float(i) * 0.2) + d * (float(i) * 2.4 - 1.2)
		var t := _ps(LP + "Table_Circular.gltf").instantiate() as Node3D
		t.position = Vector3(tp.x, height_at(tp.x, tp.y), tp.y)
		lib.add(g, t, "小桌_%d" % i)
		for k in 2:
			var cp := tp + Vector2(lib.rr(-0.9, 0.9), lib.rr(-0.9, 0.9)).normalized() * 0.85
			var ch := _ps(LP + "Chair.gltf").instantiate() as Node3D
			ch.position = Vector3(cp.x, height_at(cp.x, cp.y), cp.y)
			ch.rotation.y = atan2(tp.x - cp.x, tp.y - cp.y)
			lib.add(g, ch, "小椅_%d_%d" % [i, k])
	# 雜物：碗、酒瓶、食材箱
	for i in 4:
		var p := sp + perp * lib.rr(-1.6, 1.6) + d * lib.rr(1.8, 2.6)
		var v: String = ["CeremicPot", "WoodenBox", "Basket_S", "Barrel"][i]
		var it := _ps(LP + v + ".gltf").instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		it.scale = Vector3(0.7, 0.7, 0.7) if v == "Barrel" else Vector3.ONE
		lib.add(g, it, "%s_%d" % [v, i])
	# 暖色紙燈籠光（夜間為視覺焦點）：兩盞 OmniLight3D
	for i in 2:
		var lp := sp + d * (float(i) * 2.0 - 1.0)
		var ol := OmniLight3D.new()
		ol.position = Vector3(lp.x, height_at(lp.x, lp.y) + 2.2, lp.y)
		ol.light_color = Color(1.0, 0.72, 0.42)
		ol.light_energy = 2.2
		ol.omni_range = 9.0
		ol.omni_attenuation = 1.4
		ol.shadow_enabled = i == 0
		lib.add(g, ol, "紙燈籠光_%d" % i)
	# 炭火：小的橘紅點光 + 位置標記
	var fire := OmniLight3D.new()
	fire.position = mk.position + Vector3(0, 0.6, 0)
	fire.light_color = Color(1.0, 0.45, 0.15)
	fire.light_energy = 1.2
	fire.omni_range = 3.5
	lib.add(g, fire, "炭火光")
	print("[TRAIL] 夜雀屋台：%s" % sp)


func _aabb_of(ps: PackedScene) -> AABB:
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	for m in _mesh_nodes(inst):
		var b := _rel(m, inst) * (m as MeshInstance3D).get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	inst.free()
	return box if box != null else AABB(Vector3.ZERO, Vector3.ONE)


# ══════════════════════════════════════════════════════════════════
# 妖怪存在感：紅布條、酒瓶、碗、祭物、遠處燈光 —— 越深越多
# ══════════════════════════════════════════════════════════════════
func _build_youkai_traces() -> void:
	var g := lib.add(lib.root, Node3D.new(), "妖怪痕跡") as Node3D
	var n := 0
	# 紅布條綁在路邊樹上（用近路樹幹座標）
	var cloth := lib.add(g, Node3D.new(), "紅布條") as Node3D
	for q in _placed_trunks:
		var info := _spine_info(q)
		var t: float = info[1]
		if t < 0.5 or lib.rand() > (t - 0.5) * 0.12:
			continue
		var bm := MeshInstance3D.new()
		var bx := BoxMesh.new(); bx.size = Vector3(0.10, 0.9, 0.01)
		bm.mesh = bx
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.58, 0.09, 0.07)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material_override = mat
		var a := lib.rr(0.0, TAU)
		bm.position = Vector3(q.x + cos(a) * 0.45, height_at(q.x, q.y) + lib.rr(1.4, 2.2), q.y + sin(a) * 0.45)
		bm.rotation.y = a
		lib.add(cloth, bm, "紅布_%03d" % n)
		n += 1
	# 小型祭物（碗、酒瓶、石堆）
	var off := lib.add(g, Node3D.new(), "祭物") as Node3D
	var on := 0
	for i in 14:
		var t := lib.rr(0.55, 0.98)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * (_half_w(t) + lib.rr(0.5, 2.5)) * (1.0 if lib.rand() < 0.5 else -1.0)
		var v: String = ["CeremicPot", "Basket_S", "CeremicPot"][i % 3]
		var it := _ps(LP + v + ".gltf").instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		it.scale = Vector3(0.8, 0.8, 0.8)
		lib.add(off, it, "%s_%02d" % [v, on])
		# 旁邊三顆小石
		for k in 3:
			var rp := p + Vector2(lib.rr(-0.5, 0.5), lib.rr(-0.5, 0.5))
			var pv := "Pebble_Round_%d" % (1 + k)
			var pp := NAT + pv + ".gltf"
			var ps := _ps(pp)
			var s := 0.18 / maxf(_w_cache[pp], 0.05)
			var pi := ps.instantiate() as Node3D
			pi.position = Vector3(rp.x, height_at(rp.x, rp.y), rp.y)
			pi.scale = Vector3(s, s, s)
			lib.add(off, pi, "祭石_%02d_%d" % [on, k])
		on += 1
	# 遠處妖怪燈光：深處林中幾點冷色微光（夜間才有意義）
	var lights := lib.add(g, Node3D.new(), "遠處妖火") as Node3D
	for i in 6:
		var t := lib.rr(0.62, 0.99)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(22.0, 45.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var ol := OmniLight3D.new()
		ol.position = Vector3(p.x, height_at(p.x, p.y) + lib.rr(1.0, 3.0), p.y)
		ol.light_color = [Color(0.45, 0.75, 1.0), Color(0.7, 0.4, 1.0), Color(0.4, 1.0, 0.6)][i % 3]
		ol.light_energy = 1.6
		ol.omni_range = 7.0
		ol.omni_attenuation = 1.8
		lib.add(lights, ol, "妖火_%d" % i)
	# 磷光菌類：深處林床，發光材質
	var glow := lib.add(g, Node3D.new(), "磷光菌") as Node3D
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.9, 0.7)
	gm.emission_enabled = true
	gm.emission = Color(0.35, 0.9, 0.55)
	gm.emission_energy_multiplier = 1.6
	var gn := 0
	for i in 40:                     # 220 m 版
		var t := lib.rr(0.58, 0.99)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(_half_w(t) + 0.5, 14.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var pp := NAT + "Mushroom_Common.gltf"
		var ps := _ps(pp)
		var s := lib.rr(0.2, 0.4) / maxf(_w_cache[pp], 0.05)
		var mi := ps.instantiate() as Node3D
		mi.position = Vector3(p.x, height_at(p.x, p.y) - 0.02, p.y)
		mi.rotation.y = lib.rand() * TAU
		mi.scale = Vector3(s, s, s)
		for mn in _mesh_nodes(mi):
			(mn as MeshInstance3D).material_override = gm
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(glow, mi, "磷光菌_%03d" % gn)
		gn += 1
	print("[TRAIL] 妖怪痕跡：紅布 %d、祭物 %d、妖火 6、磷光菌 %d" % [n, on, gn])


# ══════════════════════════════════════════════════════════════════
# 遠景：gobkit 山（混用裁決）+ lib.vista 地平線
# ══════════════════════════════════════════════════════════════════
func _build_vista() -> void:
	lib.vista(OUT, HALF, 1000.0, height_at, [
		{ "x": -620.0, "z": -620.0, "h": 120.0, "r": 240.0 },
		{ "x": 520.0, "z": -560.0, "h": 60.0, "r": 200.0 },
	], "res://assets/models/tree_round_far.glb", 260)
	var g := lib.add(lib.root, Node3D.new(), "遠景山_gobkit") as Node3D
	# [檔名, 目標高 m, x, z, yaw]
	var specs := [
		["Mountain001", 240.0, -700.0, -720.0, 0.4],      # 西北 妖怪之山
		["MountainFar001", 300.0, -950.0, -600.0, 1.2],
		["Mountain002", 130.0, 620.0, -650.0, 2.6],       # 東北 神社東山
		["Hill001", 55.0, 720.0, -300.0, 0.0],
		["Hill002", 48.0, -750.0, 200.0, 1.0],
	]
	for s in specs:
		var path: String = GOB + String(s[0]) + ".glb"
		var ps := _ps(path)
		var sc: float = s[1] / maxf(_h_cache[path], 1.0)
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(s[2], -8.0, s[3])
		inst.rotation.y = s[4]
		inst.scale = Vector3(sc, sc, sc)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, inst, s[0])
	print("[TRAIL] 遠景山 %d 座" % specs.size())


# ══════════════════════════════════════════════════════════════════
# 天象系統：跟 slice 同一支腳本，森林用較濃霧、較暗環境光
# ══════════════════════════════════════════════════════════════════
func _build_sky() -> void:
	var sky := Node3D.new()
	sky.set_script(load("res://scripts/sky_system.gd"))
	lib.add(lib.root, sky, "天象系統")
	sky.set("時刻", 15.7)
	sky.set("一日長度分鐘", 20.0)
	sky.set("方位角", -26.0)
	sky.set("星星密度", 0.35)
	sky.set("銀河強度", 0.5)
	sky.set("陰影距離", 120.0)
	sky.set("體積霧", true)
	# 天象腳本會自建 WorldEnvironment/太陽；這裡再補一個森林霧覆蓋層
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.72, 0.66)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.028
	env.volumetric_fog_albedo = Color(0.75, 0.80, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42     # 樹冠遮光
	env.ssao_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	we.environment = env
	lib.add(lib.root, we, "森林環境")


# ══════════════════════════════════════════════════════════════════
# 出生點與傳送點標記 + Meshy 佔位總表
# ══════════════════════════════════════════════════════════════════
func _build_markers() -> void:
	var g := lib.add(lib.root, Node3D.new(), "標記") as Node3D
	var s := _spine_pos(0.02)
	var sm := Marker3D.new()
	sm.position = Vector3(s.x, height_at(s.x, s.y) + 1.0, s.y)
	sm.rotation.y = PI   # 面北
	lib.add(g, sm, "出生點_南入口")
	var n := _spine_pos(0.99)
	var nm := Marker3D.new()
	nm.position = Vector3(n.x, height_at(n.x, n.y) + 1.0, n.y)
	nm.set_meta("portal", "shrine")
	lib.add(g, nm, "傳送點_北_神社")
	var v := _spine_pos(0.0)
	var vm := Marker3D.new()
	vm.position = Vector3(v.x, height_at(v.x, v.y) + 1.0, v.y)
	vm.set_meta("portal", "village")
	lib.add(g, vm, "傳送點_南_人里")
	print("[TRAIL] 出生點 %s；傳送 北 %s 南 %s" % [sm.position, nm.position, vm.position])
