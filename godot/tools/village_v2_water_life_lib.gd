extends RefCounted
## P10 R5b Water Logic Pilot（使用者 2026-10-09 D5／D10）。overlay `WaterLifeP10`（gen/water_life_p10.scn，root、GroundPilotP10 之後）。
## D5：三座水車分別定義功能；沒有舀水機構不得宣稱揚水；不合理的 3.30 m 高架輸水道要移除或重新設計；精米小屋不自動新增。
##   現況（MASTER AUDIT R5b-01）：P5 水車＝下掛け葉板輪（無柄杓），P8 卻以三座水車頂的受け樋頭（樋底 3.30 m）為田的水源；
##   田面（約 +0.3 m）比水渠水面（−1.13～−1.63）高 1.4–1.9 m → 田一定要揚水，問題在水車資產沒有揚水機構。
##   Pilot（只做水車 2，代表性一座）＝「重新設計成真正的揚水水車」（朝倉三連水車式）：
##     · 柄杓（汲桶）16 個，固定在輪東面（輪面 x 2.22 與東軸承柱 x 2.40 之間的 0.18 m 間隙內），隨輪轉（runtime 掛到 Hero/Wheel 下）
##     · 受け樋：輪頂內側（柄杓迴轉圈內）承水，沿軸向往東接 P8 落とし樋頭（P8 幾何不動）
##     · 樋頭架台：2 柱＋貫＋筋交い，立在水渠裡、柄杓迴轉圈外，承 P8 樋頭的枕木（原本 3.30 m 樋頭底下沒有支撐）
##   水車 1／3 的功能定義與後續做法列在 docs（需裁定：水車 1 改動力要動 P8 取水），本 Pilot 不動。
## D10：主河一艘小舟＋一處繫泊／卸貨點：P7 主河唯一的親水石段（雁木，RB_16_-4 step_0–4）下端，
##   川舟 7.2 × 1.5 m（吃水 0.12）、繫船杭 1、舫い綱、石段頂「届いた荷」（street_kit st_kago_tsumi 重用）。
## 不改任何封存檔（P5 水車、P7 河岸、P8 田、R2 street_kit）；enabled=false 全部撤回（柄杓從輪上拿下、其餘隱藏）。

const NODE_NAME := "WaterLifeP10"
const OUTPUT := "res://maps/village_v2/gen/water_life_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/water_life.gd"
const ART_REVISION := "P10 R5b water pilot r3（最終輪）：柄杓／受け樋／架台＝新しい檜色（舊輪と明度差）、傾水を太く白く、舟＝吃水線の白波・米俵 3（梁と棹を避ける）・舫い綱を明るく太く；r2：新木部材色（柄杓／受け樋／架台／舟＝較新的木，從舊輪分出來）、輪頂傾水的水流、舟首反り＋舷弧、舫い綱加粗、舟內俵 2（ART_REVIEW）"
const FV := preload("res://tools/village_v2_farmland_visual.gd")
const WOOD := "res://assets/village_v2/_matlib/V2_Wood.tres"
const STONE := "res://assets/village_v2/_matlib/V2_Stone.tres"

## ── 水車 2 ──（Hero 局部座標：+x＝水渠中心、+z＝水流、輪心 (1.6, 2.65, 0)、半徑 3.0、輪面 x 0.98–2.22、東軸承柱 x 2.40–2.70）
const WHEEL := "Landmarks/LANDMARK_WATERWHEEL_2/Hero"
const ROTOR := "Landmarks/LANDMARK_WATERWHEEL_2/Hero/Wheel"
const HUB := Vector3(1.6, 2.65, 0.0)
const WHEEL_FACE_X := 2.22
const EAST_POST_X := 2.40
const P8_HEAD_LOCAL := Vector3(3.252, 4.821, -0.368)   # P8 樋頭（樋底）＝village_v2_farmland_zone.gd HEAD_LOCAL
const BUCKETS := 16
const BUCKET_GAP := 0.016          # 柄杓與輪面、與東軸承柱的淨距
const BUCKET_R := [2.60, 2.92]     # 柄杓徑向範圍（輪緣帶）
const BUCKET_TAN := 0.40           # 沿圓周長
const BUCKET_TILT_DEG := 20.0      # 口朝「前進方向」再往外 20°：在輪頂越過後才傾倒入樋
const TROUGH_X := [2.245, 3.245]   # 受け樋（局部 x 範圍；東端與 P8 樋頭對接）
const TROUGH_W := 0.34
const TROUGH_WALL := 0.14
const TROUGH_BOT := [4.885, 4.835] # 樋底（西端→東端，往樋頭流）
const BENT_X := [2.85, 3.30]       # 樋頭架台柱（局部 x）：東軸承柱外、柄杓迴轉圈外、P8 樋頭枕木下
const BENT_Z := -0.30
const POST := 0.14

## ── 主河小舟 ──
const STAIR_TOP := Vector3(524.31, 0.08, -99.58)   # P7 RB_16_-4 step_0（collision 中心）
const STAIR_BOT := Vector3(526.30, -0.85, -101.95)  # P7 RB_16_-4 step_4
const RIVER_WATER := -0.80
const FLOW := Vector2(0.992, 0.126)                  # 主河此段流向（layout MainRiver (520,−117)→(539.8,−114.5)）
const BOAT_L := 7.2
const BOAT_B := 1.5
const BOAT_H := 0.42
const BOAT_DRAFT := 0.12
const BOAT_OFF := 2.2           # 船中心離最下段石段（往河心）：石段碰撞盒延伸到水下，1.35 m 會撞
const KAGO_MESH := "res://assets/village_v2/street_kit/mesh/st_kago_tsumi.res"
const BALES := [-1.04, -0.48, 0.08]   # 米俵 3 の z（船体局部）：梁 z −1.44／+0.58 の間
const BALE_R := 0.27
const BALE_HL := 0.36
const BALE_X := -0.12                  # 棹（x 0.28→0.40）を避ける
const FOAM_W := 0.22


## ─────────────────────────── 網格小工具 ───────────────────────────
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, both := false) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)
	if both:
		for v in [a, c, b, a, d, c]:
			st.set_normal(-n)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)


## 實心方塊：中心 c、半尺寸 h、基底 B（列＝局部軸）
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, B := Basis()) -> void:
	var p := func(sx: float, sy: float, sz: float) -> Vector3: return c + B.x * h.x * sx + B.y * h.y * sy + B.z * h.z * sz
	var P: Callable = p
	_quad(st, P.call(-1, -1, 1), P.call(1, -1, 1), P.call(1, 1, 1), P.call(-1, 1, 1))
	_quad(st, P.call(1, -1, -1), P.call(-1, -1, -1), P.call(-1, 1, -1), P.call(1, 1, -1))
	_quad(st, P.call(1, -1, 1), P.call(1, -1, -1), P.call(1, 1, -1), P.call(1, 1, 1))
	_quad(st, P.call(-1, -1, -1), P.call(-1, -1, 1), P.call(-1, 1, 1), P.call(-1, 1, -1))
	_quad(st, P.call(-1, 1, 1), P.call(1, 1, 1), P.call(1, 1, -1), P.call(-1, 1, -1))
	_quad(st, P.call(-1, -1, -1), P.call(1, -1, -1), P.call(1, -1, 1), P.call(-1, -1, 1))


## 兩點間方柱（截面 w×w）
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var L := d.length()
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_box(st, (a + b) * 0.5, Vector3(w * 0.5, L * 0.5, w * 0.5), Basis(x, y, z))


## 開口箱（柄杓）：中心 c、口朝 n（局部 +Y）、寬 w（沿 t）、深 d（沿 n）、厚 a（沿 ax）；雙面
static func _bucket(st: SurfaceTool, c: Vector3, n: Vector3, t: Vector3, ax: Vector3, w: float, d: float, a: float) -> void:
	var P := func(sx: float, sy: float, sz: float) -> Vector3: return c + t * w * 0.5 * sx + n * d * 0.5 * sy + ax * a * 0.5 * sz
	var Q: Callable = P
	_quad(st, Q.call(-1, -1, -1), Q.call(1, -1, -1), Q.call(1, -1, 1), Q.call(-1, -1, 1), true)   # 底
	_quad(st, Q.call(-1, -1, 1), Q.call(1, -1, 1), Q.call(1, 1, 1), Q.call(-1, 1, 1), true)       # 外側板
	_quad(st, Q.call(1, -1, -1), Q.call(-1, -1, -1), Q.call(-1, 1, -1), Q.call(1, 1, -1), true)   # 輪面側板
	_quad(st, Q.call(1, -1, 1), Q.call(1, -1, -1), Q.call(1, 1, -1), Q.call(1, 1, 1), true)       # 端板
	_quad(st, Q.call(-1, -1, -1), Q.call(-1, -1, 1), Q.call(-1, 1, 1), Q.call(-1, 1, -1), true)   # 端板


## 新しい木部材（柄杓・受け樋・架台・舟）：V2_Wood と同じ貼圖、色だけ明るめ（古い輪との区別、R6a 校正値 0.75 寄り）
static func new_wood() -> StandardMaterial3D:
	var m := (load(WOOD) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.68, 0.66, 0.62)
	m.resource_name = "P10_WoodNew"
	return m


## 新しく足した水車部材（柄杓・受け樋・架台）：新しい檜色——黒い古輪と明度差をつけて、仕組みを遠くから読めるように（r3）
static func fresh_wood() -> StandardMaterial3D:
	var m := (load(WOOD) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.95, 0.86, 0.70)
	m.resource_name = "P10_WoodFresh"
	return m


static func _mi(name: String, st: SurfaceTool, mat: Material, vr_end := 0.0) -> MeshInstance3D:
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	if vr_end > 0.0:
		mi.visibility_range_end = vr_end
		mi.visibility_range_end_margin = 6.0
	return mi


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## ─────────────────────────── 水車 2：柄杓 ───────────────────────────
## 柄杓 i 在 Wheel 局部（輪心＝原點、繞 x 轉）：角 θ（0＝正上）、輪轉 dir −1 → 運動方向 m＝(0, sin θ, −cos θ)
static func bucket_specs(x1_over := -1.0) -> Array:
	var out := []
	var x0 := WHEEL_FACE_X - HUB.x + BUCKET_GAP
	var x1 := EAST_POST_X - HUB.x - BUCKET_GAP if x1_over < 0.0 else x1_over
	var a := x1 - x0
	var rc := (BUCKET_R[0] + BUCKET_R[1]) * 0.5
	var al := deg_to_rad(BUCKET_TILT_DEG)
	for i in BUCKETS:
		var th := TAU * (float(i) + 0.5) / BUCKETS
		var r := Vector3(0, cos(th), sin(th))
		var m := Vector3(0, sin(th), -cos(th))
		var n := (m * cos(al) + r * sin(al)).normalized()
		var t := Vector3(1, 0, 0).cross(n).normalized()
		out.append({"c": Vector3((x0 + x1) * 0.5, 0, 0) + r * rc, "n": n, "t": t, "ax": Vector3(1, 0, 0), "a": a, "th": th})
	return out


static func _buckets_mesh() -> MeshInstance3D:
	var st := _new_st()
	var dep := BUCKET_R[1] - BUCKET_R[0]
	for b in bucket_specs():
		_bucket(st, b["c"], b["n"], b["t"], b["ax"], BUCKET_TAN, dep, float(b["a"]))
	var mi := _mi("LiftBuckets", st, fresh_wood(), 140.0)
	mi.set_meta("phase", "P10 R5b pilot")
	return mi


## ─────────────────────────── 水車 2：受け樋＋樋頭架台（Hero 局部） ───────────────────────────
static func trough_specs() -> Dictionary:
	return {"x": TROUGH_X, "z": P8_HEAD_LOCAL.z, "w": TROUGH_W, "wall": TROUGH_WALL, "bot": TROUGH_BOT}


static func _trough_node() -> Node3D:
	var g := Node3D.new()
	g.name = "UkeToi"
	var st := _new_st()
	var z := P8_HEAD_LOCAL.z
	var hw := TROUGH_W * 0.5
	var t := 0.035
	var xa: float = TROUGH_X[0]
	var xb: float = TROUGH_X[1]
	var ya: float = TROUGH_BOT[0]
	var yb: float = TROUGH_BOT[1]
	var B := Basis(Vector3(xb - xa, yb - ya, 0).normalized(), Vector3(-(yb - ya), xb - xa, 0).normalized(), Vector3(0, 0, 1))
	var L := Vector2(xb - xa, yb - ya).length()
	var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - t * 0.5, z)
	_box(st, mid, Vector3(L * 0.5, t * 0.5, hw + t), B)                                           # 底板
	for sd in [-1.0, 1.0]:
		_box(st, mid + B.y * (TROUGH_WALL * 0.5 + t * 0.5) + B.z * sd * (hw + t * 0.5), Vector3(L * 0.5, TROUGH_WALL * 0.5, t * 0.5), B)   # 側板
	_box(st, Vector3(xa - t * 0.5, ya + TROUGH_WALL * 0.5 - t * 0.5, z), Vector3(t * 0.5, TROUGH_WALL * 0.5 + t * 0.5, hw + t))           # 西端板
	g.add_child(_mi("Trough", st, fresh_wood(), 160.0))
	# 輪頂で柄杓から受け樋へ落ちる水（常時：輪は止まらない）——幅 0.12、柄杓の傾水點（z −0.55）→ 樋內
	var sf := _new_st()
	var px := (xa + 2.38) * 0.5
	for k in 3:
		var z0 := z - 0.08 - k * 0.07
		var top := 5.28 - k * 0.04
		_quad(sf, Vector3(px - 0.08, top, z0), Vector3(px + 0.08, top, z0), Vector3(px + 0.10, ya + 0.06, z0 + 0.03), Vector3(px - 0.10, ya + 0.06, z0 + 0.03), true)
	var fmi := MeshInstance3D.new()
	fmi.name = "Pour"
	fmi.mesh = sf.commit()
	fmi.material_override = FV._flow_mat(1.6, Color(0.80, 0.86, 0.88), 0.82)
	fmi.visibility_range_end = 90.0
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(fmi)
	# 槽內水面（P8 落とし樋同一 flow 材質）
	var sw := _new_st()
	var wy0 := ya + 0.05
	var wy1 := yb + 0.05
	_quad(sw, Vector3(xa, wy0, z + hw), Vector3(xb, wy1, z + hw), Vector3(xb, wy1, z - hw), Vector3(xa, wy0, z - hw))
	var wmi := MeshInstance3D.new()
	wmi.name = "Water"
	wmi.mesh = sw.commit()
	wmi.material_override = FV._flow_mat(0.8, Color(0.36, 0.36, 0.3), 0.7)
	wmi.visibility_range_end = 120.0
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(wmi)
	return g


## 架台：柱 2（水渠底 → 樋頭枕木下）＋貫 2＋筋交い 1；bed_y＝兩柱腳的水渠底高（Hero 局部）
static func _bent_node(bed_y: Array) -> Node3D:
	var g := Node3D.new()
	g.name = "HeadBent"
	var st := _new_st()
	var top := P8_HEAD_LOCAL.y - 0.14 - 0.01
	var ps: Array[Vector3] = []
	for i in 2:
		var x: float = BENT_X[i]
		var b: Vector3 = Vector3(x, float(bed_y[i]) - 0.30, BENT_Z)
		var t: Vector3 = Vector3(x, top, BENT_Z)
		_beam(st, b, t, POST)
		ps.append(t)
	_box(st, Vector3((BENT_X[0] + BENT_X[1]) * 0.5, top - 0.06, BENT_Z), Vector3((BENT_X[1] - BENT_X[0]) * 0.5 + 0.12, 0.06, 0.08))   # 頭貫（枕木下）
	var mid_y := lerpf(maxf(float(bed_y[0]), float(bed_y[1])) + 0.6, top, 0.45)
	_box(st, Vector3((BENT_X[0] + BENT_X[1]) * 0.5, mid_y, BENT_Z), Vector3((BENT_X[1] - BENT_X[0]) * 0.5 + 0.1, 0.05, 0.06))          # 腰貫
	_beam(st, Vector3(BENT_X[0], maxf(float(bed_y[0]), -0.9), BENT_Z + 0.09), Vector3(BENT_X[1], top - 0.15, BENT_Z + 0.09), 0.08)        # 筋交い
	g.add_child(_mi("Posts", st, fresh_wood(), 160.0))
	var body := StaticBody3D.new()
	body.name = "Collision"
	for i in 2:
		var cs := CollisionShape3D.new()
		cs.name = "Post_%d" % i
		var bs := BoxShape3D.new()
		var y0 := float(bed_y[i]) - 0.30
		bs.size = Vector3(POST, top - y0, POST)
		cs.shape = bs
		cs.position = Vector3(float(BENT_X[i]), (top + y0) * 0.5, BENT_Z)
		body.add_child(cs)
	g.add_child(body)
	return g


## ─────────────────────────── 主河：川舟 ───────────────────────────
## 船體局部：+z＝船首、y＝0 船底、x＝橫向。站 u∈[0,1]（船尾→船首）
static func _hull_half(u: float) -> Vector2:
	# (舷側半寬, 船底半寬)：船首 1.7 m 收尖、船尾方形
	var tip := smoothstep(0.62, 1.0, u)
	var hw := lerpf(BOAT_B * 0.5, 0.06, tip) * lerpf(0.94, 1.0, smoothstep(0.0, 0.12, u))
	var hb := lerpf(BOAT_B * 0.5 - 0.22, 0.02, smoothstep(0.66, 0.96, u))
	return Vector2(hw, hb)


static func _hull_top(u: float) -> float:
	return BOAT_H + 0.55 * pow(smoothstep(0.60, 1.0, u), 1.7) + 0.08 * (1.0 - smoothstep(0.0, 0.14, u)) + 0.04 * sin(u * PI)


static func _hull_bot(u: float) -> float:
	return 0.30 * pow(smoothstep(0.72, 1.0, u), 1.4)


static func _boat_mesh() -> MeshInstance3D:
	var st := _new_st()
	var N := 22
	var prev := []
	for i in N + 1:
		var u := float(i) / N
		var z := (u - 0.5) * BOAT_L
		var hh := _hull_half(u)
		var yt := _hull_top(u)
		var yb := _hull_bot(u)
		var cur := [Vector3(-hh.x, yt, z), Vector3(-hh.y, yb, z), Vector3(hh.y, yb, z), Vector3(hh.x, yt, z)]
		if i > 0:
			for k in 3:
				_quad(st, prev[k], cur[k], cur[k + 1], prev[k + 1], true)
		prev = cur
	# 船尾板（戸立）
	var h0 := _hull_half(0.0)
	_quad(st, Vector3(-h0.x, _hull_top(0.0), -BOAT_L * 0.5), Vector3(h0.x, _hull_top(0.0), -BOAT_L * 0.5), Vector3(h0.y, _hull_bot(0.0), -BOAT_L * 0.5), Vector3(-h0.y, _hull_bot(0.0), -BOAT_L * 0.5), true)
	# 舷縁（ガンネル）・梁 2・床板・棹
	for i in N:
		var u0 := float(i) / N
		var u1 := float(i + 1) / N
		for sd in [-1.0, 1.0]:
			var a := Vector3(sd * _hull_half(u0).x, _hull_top(u0) + 0.02, (u0 - 0.5) * BOAT_L)
			var b := Vector3(sd * _hull_half(u1).x, _hull_top(u1) + 0.02, (u1 - 0.5) * BOAT_L)
			_beam(st, a, b, 0.05)
	for u in [0.30, 0.58]:
		var hh := _hull_half(u)
		_box(st, Vector3(0, _hull_top(u) - 0.10, (u - 0.5) * BOAT_L), Vector3(hh.x - 0.03, 0.025, 0.11))
	_box(st, Vector3(0, 0.035, -0.6), Vector3(BOAT_B * 0.5 - 0.30, 0.012, 2.2))
	_beam(st, Vector3(0.28, 0.08, -2.9), Vector3(0.40, 0.46, 2.6), 0.045)   # 棹（船内に寝かせる）
	var hm := new_wood()
	hm.albedo_color = Color(0.80, 0.75, 0.68)
	hm.resource_name = "P10_BoatWood"
	var mi := _mi("Hull", st, hm, 220.0)
	# 積荷：米俵 3（これから陸揚げ）——梁 2（z −1.44／+0.58）の間、棹（x ≈ +0.3）を避けて x 中心 −0.12
	var tw := _new_st()
	for i in BALES.size():
		var cz: float = BALES[i]
		var n := 12
		var r := BALE_R
		var x0 := BALE_X - BALE_HL
		var x1 := BALE_X + BALE_HL
		var yc := 0.05 + r
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			_quad(tw, Vector3(x0, yc + r * cos(a0), cz + r * sin(a0)), Vector3(x1, yc + r * cos(a0), cz + r * sin(a0)), Vector3(x1, yc + r * cos(a1), cz + r * sin(a1)), Vector3(x0, yc + r * cos(a1), cz + r * sin(a1)), true)
			for sx in [x0, x1]:
				_quad(tw, Vector3(sx, yc, cz), Vector3(sx, yc + 0.85 * r * cos(a0), cz + 0.85 * r * sin(a0)), Vector3(sx, yc + 0.85 * r * cos(a1), cz + 0.85 * r * sin(a1)), Vector3(sx, yc, cz), true)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.84, 0.75, 0.52)
	straw.roughness = 1.0
	straw.resource_name = "P10_Tawara"
	var tmi := _mi("Tawara", tw, straw, 120.0)
	mi.add_child(tmi)
	# 吃水線の白波（舷側に沿う幅 0.22 の帯、水面＋0.006）：浮いている／沈んでいるの判別を遠くからつける
	var fw := _new_st()
	var wl := BOAT_DRAFT
	var ring_prev := []
	var M := 22
	for i in M + 1:
		var u := float(i) / M
		var yb := _hull_bot(u)
		var yt := _hull_top(u)
		if yb >= wl:
			ring_prev = []
			continue
		var hh := _hull_half(u)
		var hx := lerpf(hh.y, hh.x, (wl - yb) / maxf(yt - yb, 0.01))
		var z := (u - 0.5) * BOAT_L
		var cur := [Vector3(-hx - FOAM_W, wl + 0.006, z), Vector3(-hx + 0.01, wl + 0.006, z), Vector3(hx - 0.01, wl + 0.006, z), Vector3(hx + FOAM_W, wl + 0.006, z)]
		if not ring_prev.is_empty():
			_quad(fw, ring_prev[0], cur[0], cur[1], ring_prev[1], true)
			_quad(fw, ring_prev[2], cur[2], cur[3], ring_prev[3], true)
		ring_prev = cur
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color(0.92, 0.95, 0.95, 0.42)
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.roughness = 1.0
	foam.cull_mode = BaseMaterial3D.CULL_DISABLED
	foam.resource_name = "P10_BoatFoam"
	var fmi2 := _mi("WaterlineFoam", fw, foam, 120.0)
	fmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(fmi2)
	return mi


static func boat_xf(off := BOAT_OFF) -> Transform3D:
	var down := Vector2(STAIR_BOT.x - STAIR_TOP.x, STAIR_BOT.z - STAIR_TOP.z).normalized()
	# 河心方向＝流向的法線中，與石段下行方向同側者
	var nrm := Vector2(-FLOW.y, FLOW.x)
	if nrm.dot(down) < 0.0:
		nrm = -nrm
	var c := Vector2(STAIR_BOT.x, STAIR_BOT.z) + nrm * off + FLOW * 0.6
	var fwd := Vector3(-FLOW.x, 0, -FLOW.y)   # 船首朝上游（繫泊時船首迎流）
	var x := Vector3.UP.cross(fwd).normalized()
	return Transform3D(Basis(x, Vector3.UP, fwd), Vector3(c.x, RIVER_WATER - BOAT_DRAFT, c.y))


## 「届いた荷」候補：石段頂から陸側 2.0–3.6 m、横 ±1.2 m（build／gate は四角の地面起伏が最小のものを使う）
static func kago_candidates() -> Array:
	var down := Vector2(STAIR_BOT.x - STAIR_TOP.x, STAIR_BOT.z - STAIR_TOP.z).normalized()
	var side := Vector2(-down.y, down.x)
	var out := []
	for a in [2.0, 2.4, 2.8, 3.2, 3.6]:
		for b in [-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2]:
			out.append(Vector2(STAIR_TOP.x, STAIR_TOP.z) - down * float(a) + side * float(b))
	return out


## 「届いた荷」的四角（st_kago_tsumi 1.30 × 0.80，yaw 同 build）
static func kago_corners(c: Vector2, down: Vector2) -> Array:
	var yaw := atan2(down.x, down.y) + PI * 0.5
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	var out := [c]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(c + ax * 0.65 * sx + az * 0.40 * sz)
	return out


static func mooring_specs(top_ground_y: float) -> Dictionary:
	var down := Vector2(STAIR_BOT.x - STAIR_TOP.x, STAIR_BOT.z - STAIR_TOP.z).normalized()
	var side := Vector2(-down.y, down.x)
	var bxf := boat_xf()
	var bow := bxf * Vector3(0, BOAT_H + 0.2, BOAT_L * 0.5 - 0.35)
	# 杭：石段頂の脇（石段から横へ 1.3 m、頂から 0.6 m 下）
	var p := Vector2(STAIR_TOP.x, STAIR_TOP.z) + side * (1.3 if side.dot(Vector2(bow.x - STAIR_TOP.x, bow.z - STAIR_TOP.z)) > 0.0 else -1.3) + down * 0.6
	var kago := Vector2(STAIR_TOP.x, STAIR_TOP.z) - down * 2.4 - side * 0.4
	return {"post": p, "bow": bow, "kago": kago, "down": down}


static func _rope_mesh(a: Vector3, b: Vector3) -> MeshInstance3D:
	var st := _new_st()
	var n := 12
	var sag := clampf(a.distance_to(b) * 0.06, 0.08, 0.5)
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		_beam(st, prev, p, 0.045)
		prev = p
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.78, 0.58)
	m.roughness = 1.0
	m.resource_name = "P10_Rope"
	return _mi("Rope", st, m, 90.0)


## ─────────────────────────── 組裝 ───────────────────────────
## heights：{"bent_bed": [y0, y1]（Hero 局部）, "post_ground": y, "kago_ground": y}
static func build(v: Node3D, heights: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R5b pilot")
	# 水車 2
	var hero := v.get_node(WHEEL) as Node3D
	var ww := Node3D.new()
	ww.name = "WW2_Lift"
	ww.transform = hero.global_transform
	root.add_child(ww)
	ww.add_child(_trough_node())
	ww.add_child(_bent_node(heights["bent_bed"]))
	var bk := _buckets_mesh()
	bk.transform = Transform3D(Basis(), HUB)   # 停放位置＝輪心（runtime 掛到 Rotor 下時改成 identity）
	ww.add_child(bk)
	root.set("rotor_path", NodePath(ROTOR))
	root.set("buckets_path", NodePath("WW2_Lift/LiftBuckets"))
	# 主河小舟
	var bp := Node3D.new()
	bp.name = "BoatLanding"
	root.add_child(bp)
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.transform = boat_xf()
	boat.add_child(_boat_mesh())
	var bb := StaticBody3D.new()
	bb.name = "Collision"
	var bcs := CollisionShape3D.new()
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(BOAT_B - 0.1, BOAT_H, BOAT_L - 0.6)
	bcs.shape = bsh
	bcs.position = Vector3(0, BOAT_H * 0.5, -0.2)
	bb.add_child(bcs)
	boat.add_child(bb)
	bp.add_child(boat)
	var ms := mooring_specs(float(heights["post_ground"]))
	var pp: Vector2 = ms["post"]
	var pg := float(heights["post_ground"])
	var post := Node3D.new()
	post.name = "MooringPost"
	post.position = Vector3(pp.x, pg, pp.y)
	var pst := _new_st()
	_beam(pst, Vector3(0, -0.35, 0), Vector3(0, 0.95, 0), 0.13)
	post.add_child(_mi("Post", pst, load(WOOD), 120.0))
	var pb := StaticBody3D.new()
	pb.name = "Collision"
	var pcs := CollisionShape3D.new()
	var psh := BoxShape3D.new()
	psh.size = Vector3(0.13, 1.3, 0.13)
	pcs.shape = psh
	pcs.position = Vector3(0, 0.3, 0)
	pb.add_child(pcs)
	post.add_child(pb)
	bp.add_child(post)
	var tie := Vector3(pp.x, pg + 0.78, pp.y)
	bp.add_child(_rope_mesh(ms["bow"], tie))
	var kg: Vector2 = heights.get("kago_p", ms["kago"])
	var kago := MeshInstance3D.new()
	kago.name = "Kago_Arrived"
	kago.mesh = load(KAGO_MESH)
	var kd: Vector2 = ms["down"]
	kago.transform = Transform3D(Basis(Vector3.UP, atan2(kd.x, kd.y) + PI * 0.5), Vector3(kg.x, float(heights["kago_ground"]) - 0.02, kg.y))
	kago.visibility_range_end = 90.0
	kago.set_meta("asset", "street_kit/st_kago_tsumi（重用）")
	bp.add_child(kago)
	return root
