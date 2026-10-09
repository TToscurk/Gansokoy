extends RefCounted
## P10 R5b Water Logic Pilot（使用者 2026-10-09 D5／D10）。overlay `WaterLifeP10`（gen/water_life_p10.scn，root、GroundPilotP10 之後）。
## D5：三座水車分別定義功能；沒有舀水機構不得宣稱揚水；不合理的 3.30 m 高架輸水道要移除或重新設計；精米小屋不自動新增。
##   現況（MASTER AUDIT R5b-01）：P5 水車＝下掛け葉板輪（無柄杓），P8 卻以三座水車頂的受け樋頭（樋底 3.30 m）為田的水源；
##   田面（約 +0.3 m）比水渠水面（−1.13～−1.63）高 1.4–1.9 m → 田一定要揚水，問題在水車資產沒有揚水機構。
##   Pilot（只做水車 2，代表性一座）＝「重新設計成真正的揚水水車」：
##     ROUND 2（使用者 R5b NEEDS REVISION：西側 2/5、白い縦材が浮く）→ 安並水車式：
##     · 柄杓（水受け箱）16：葉板と葉板の真ん中で輪縁に載り、葉板先端より 0.34 m 外へ張り出す暗い木箱（輪と同じ V2_Wood・頂点色）
##       ＝東西どちらから見ても輪の輪郭に歯のように出る；runtime 掛到 Hero/Wheel 下隨輪轉
##     · 落水：輪頂を越えた柄杓の注ぎ口 → 受け樋（白い水の帯）、上り側の柄杓からのこぼれ水（輪郭の外を水面まで）、水面の泡
##     · 受け樋：輪頂の東側（輪面の外）、P8 樋頭の枕木に載り、東へ 50 mm 下がって P8 落とし樋頭に接続
##     · 樋頭架台：2 柱＋頭貫＋腰貫＋筋交い（暗い木）、P8 枕木を下から支える（元は 3.30 m の樋頭の下に支えなし）
##   水車 1／3 的功能定義與後續做法列在 docs（需裁定：水車 1 改動力要動 P8 取水），本 Pilot 不動。
## D10：主河一艘小舟＋一處繫泊／卸貨點：P7 主河唯一的親水石段（雁木，RB_16_-4 step_0–4）下端，
##   川舟 7.2 × 1.5 m（吃水 0.12）、繫船杭 1、舫い綱、石段頂「届いた荷」（street_kit st_kago_tsumi 重用）。
## 不改任何封存檔（P5 水車、P7 河岸、P8 田、R2 street_kit）；enabled=false 全部撤回（柄杓從輪上拿下、其餘隱藏）。

const NODE_NAME := "WaterLifeP10"
const OUTPUT := "res://maps/village_v2/gen/water_life_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/water_life.gd"
const ART_REVISION := "P10 R5b ROUND 2 水車 2 r15（ROUND 2 最終）：樋の流れ（受け樋・落とし樋）は透明度 0.75・散乱光 0.05（明るい縦の帯＝柱に見えない）；r14：根因修正——手作り四角の巻き順が Godot の規約（時計回り＝表）と逆で、方塊が裏返し（外側の面が間引かれ内側が外向き法線で照らされる）→ 巻き順を修正（柄杓・受け樋・架台・杭・舟の端板）；r13：樋頭架台の柱が日向で青灰の縦材（sRGB 輝度約 75、輪の日陰 20–45）に見えた（WaterFX／架台／P5 LOD0 の表示切替で架台と特定）→ 頂点色 0.32、水面＋0.5 m より下は濡れ色 0.24；r11：注ぎ＝東へ落ちる扇（0.12→0.30、縁ほつれ・筋状、透明度 0.75）＋飛沫幕＋受け樋の跳ね（大）；r10：注ぎ＝細い 3 筋（0.05–0.08）＋飛沫（途切れた水滴の幕）——白い板＝柱に見えないように；r9：注ぎを柄杓の口から受け樋へ東へ落ちる弧（幅 0.16→0.34 の扇、縁がほつれる）に——まっすぐな白い板＝柱に見えないように；r8：P8 落とし樋の木部（頂点色なし＝輪の 1.6 倍明るい「白い縦材」）を runtime で輪と同じ明度へ（P8 ファイル不変）；r7：滴りを途切れ途切れの水滴に（棒に見えない）・水面近くの 2 本だけ、柄杓の木目スケール ×2.5；r6：注ぎ 0.30 幅・不透明の芯・受け樋の跳ね、樋の流れ 0.95、上り側の滴り 3 本（細）、輪の下の泡は控えめ、水に少し散乱光；r5：柄杓を輪縁に差し込み（內端 r 2.6）＋東面の添え板で輪に留める、上り側の柄杓の中に水（口が上を向く間だけ見える）、注ぎ 0.20 幅＋受け樋の中の跳ね、受け樋・落とし樋の水面に白い流れ、こぼれ水は 1 本の細い滴り；r4：安並水車式の揚水輪——柄杓＝葉板の間で輪縁に載り輪郭の外へ 0.34 m 張り出す暗い木箱（輪と同じ V2_Wood・頂点色）、輪頂の注ぎ・上り側のこぼれ水・水面の泡（落水 shader）、受け樋 0.40 幅、架台＝暗い木＋頭貫・腰貫・筋交い（ART_REVIEW）；r3 以前：柄杓は輪面と東軸承柱の 0.18 m 隙間（西から見えない）、新しい檜色（白く浮いた）"
const FV := preload("res://tools/village_v2_farmland_visual.gd")
const WOOD := "res://assets/village_v2/_matlib/V2_Wood.tres"
const STONE := "res://assets/village_v2/_matlib/V2_Stone.tres"
const FALL_SH := "res://maps/village_v2/shaders_p10/falling_water_p10.gdshader"

## ── 水車 2 ──（Hero 局部座標：+x＝東（水渠中心→東岸）、+z＝水流（下流）、輪心 (1.6, 2.65, 0)；P5 實測：輪 x 0.98–2.22、
##   輪縁外徑 2.75、葉板 16 枚（Wheel 局部 0°＋22.5° ごと）先端 3.00、東軸承柱 可視 x 2.36–2.74／碰撞 2.30–2.80（z ±0.25）、
##   礎石 x 2.32–2.78・y −1.6〜−0.95・z ±0.23、輪の頂点色平均 0.607（V2_Wood 0.42）、水渠水面 局部 y≈0.0（世界 −1.52））
const WHEEL := "Landmarks/LANDMARK_WATERWHEEL_2/Hero"
const ROTOR := "Landmarks/LANDMARK_WATERWHEEL_2/Hero/Wheel"
const HUB := Vector3(1.6, 2.65, 0.0)
const WHEEL_FACE_X := 2.22
const P8_HEAD_LOCAL := Vector3(3.252, 4.821, -0.368)   # P8 樋頭（樋底）＝village_v2_farmland_zone.gd HEAD_LOCAL
const P8_BEARER_TOP := 4.821      # P8 HeadBearer（樋頭の枕木）頂＝樋頭底
const RIM_R := 2.75
const PADDLE_R := 3.0
const PADDLE_STEP_DEG := 22.5
const POST_COL_X := 2.30          # 東軸承柱 碰撞箱の西面
const POST_VIS_EAST := 2.74       # 東軸承柱 可視の東面
const FOOT_Z := 0.23              # 礎石 z 半幅
const BUCKETS := 16
const BUCKET_TH0_DEG := 11.25     # 柄杓＝葉板と葉板の真ん中（葉板と干渉しない）
const BUCKET_R := [2.64, 3.34]    # 內端は輪縁の帯（2.4–2.75）に差し込み、外端は葉板先端（3.00）より外へ張り出す＝輪の輪郭の外に見える
const BUCKET_X := [1.80, 2.28]    # 輪の東半分〜輪面の 6 cm 外（東の受け樋へ注ぐ側）；東軸承柱 碰撞 2.30 より内
const BUCKET_TAN := 0.44
const BUCKET_TILT_DEG := 15.0     # 口＝進行方向から外へ 15°（下で汲み、上りで上向き、輪頂を越えて注ぐ）
const BOARD := 0.035
const WOOD_VC := 0.60             # 輪（P5）の頂点色平均 0.607 に合わせる（材質一致）
const TROUGH_X := [2.235, 3.245]  # 受け樋（局部 x；東端＝P8 樋頭に接続）
const TROUGH_W := 0.40
const TROUGH_WALL := 0.16
const TROUGH_FLOOR := 0.045
const TROUGH_BOT := [4.885, 4.835] # 樋底（西端→東端、樋頭へ 50 mm 下がる）
const BENT_X := [2.90, 3.32]      # 樋頭架台柱（東軸承柱・礎石の外、柄杓の回転範囲の外、P8 枕木の下）
const BENT_Z := -0.34
const BENT_VC := 0.32             # 樋頭架台：日陰の輪（P5 頂点色 0.4–0.6 だが自己遮蔽で暗い）に合わせて暗めの古い木（日向でも淡灰の縦材に見えない）
const BENT_WET_VC := 0.24         # 水面＋0.5 m より下（水しぶきで濡れた脚）
const POST := 0.16
const POUR_TOP := Vector3(2.27, 5.50, -0.56)   # 輪頂を越えた柄杓の注ぎ口（東側の切り欠き）
const POUR_MID := Vector3(2.36, 5.22, -0.50)   # 東へ弧を描いて落ちる
const POUR_BOT := Vector3(2.45, 4.93, -0.42)   # 受け樋の中（西端から 0.2 m）
const POUR_W := [0.12, 0.22, 0.30]            # 扇に広がる
const SPILL_TH_DEG := [101.25, 123.75]        # 水から出たばかりの柄杓の滴り（上り側 +z、輪郭の外 r ≥ 3.2 を水面まで、途切れた水滴）
const SPILL_X := 2.08
const SPILL_R := 3.26
const BRACKET_R := [2.40, 2.66]   # 東面の添え板（輪縁 → 柄杓の內端）
const P8_SUPPLY := "Districts/FarmlandEast/FarmlandP8/FieldDetails/WaterSupply"   # P8 落とし樋（封存・ファイル不変、木部の明度だけ runtime override）
const P8_TONE := 0.62             # 輪の頂点色 0.607 と同じ明度（P8 木部は頂点色なし＝1.0）
const P8_CHUTE := [Vector3(332.45, 3.30, 0.4), Vector3(336.3, 1.62, 2.75), Vector3(338.55, 0.47, 4.72)]   # village_v2_farmland_lib.gd CHUTE（世界、樋底）
const P8_CHUTE_W := 0.40

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
static var _vc := Color(1, 1, 1)   # 頂点色（V2_Wood は vertex_color_use_as_albedo：輪と同じ明度にそろえる）
static var _uvs := 1.0             # UV 倍率（小さい部材は木目を細かく）


## n＝(b−a)×(c−a) の側が表（見える面）。Godot は時計回りが表（ArrayMesh の規約）なので頂点は a, c, b の順に出す。
## ROUND 2 修正：r1–r12 は a, b, c の順＝表が −n 側 → 方塊（柄杓・受け樋・架台・杭）は外側の面が裏で間引かれ、
##   奥の内側の面が「外向き法線」で照らされていた（柱が空の色で淡灰に見える・柄杓が平たく見える原因）。
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, both := false) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b, a, d, c]:
		st.set_color(_vc)
		st.set_normal(n)
		st.set_uv(Vector2(v.x + v.z, v.y) * _uvs)
		st.add_vertex(v)
	if both:
		for v in [a, b, c, a, c, d]:
			st.set_color(_vc)
			st.set_normal(-n)
			st.set_uv(Vector2(v.x + v.z, v.y) * _uvs)
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


## 新しい木部材（柄杓・受け樋・架台・舟）：V2_Wood と同じ貼圖、色だけ明るめ（古い輪との区別、R6a 校正値 0.75 寄り）
static func new_wood() -> StandardMaterial3D:
	var m := (load(WOOD) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color(0.68, 0.66, 0.62)
	m.resource_name = "P10_WoodNew"
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
## 柄杓 i（Wheel 局部、輪心＝原點、x 軸まわりに回る）：角 θ（0＝真上）、輪の回転方向 → 進行方向 m＝(0, sin θ, −cos θ)
##   箱の基底：f＝口の向き（m を外へ BUCKET_TILT_DEG 倒す）、u＝x×f（≈ 半径外向き）、x＝軸方向。h＝(f, u, x) 方向の半寸法。
static func bucket_specs(x1_over := -1.0, th_off_deg := 0.0, r_over: Array = []) -> Array:
	var out := []
	var x0: float = float(BUCKET_X[0]) - HUB.x
	var x1: float = (float(BUCKET_X[1]) if x1_over < 0.0 else x1_over) - HUB.x
	var rr: Array = BUCKET_R if r_over.is_empty() else r_over
	var rc := (float(rr[0]) + float(rr[1])) * 0.5
	var hu := (float(rr[1]) - float(rr[0])) * 0.5
	var al := deg_to_rad(BUCKET_TILT_DEG)
	for i in BUCKETS:
		var th := deg_to_rad(BUCKET_TH0_DEG + th_off_deg + PADDLE_STEP_DEG * i)
		var r := Vector3(0, cos(th), sin(th))
		var m := Vector3(0, sin(th), -cos(th))
		var f := (m * cos(al) + r * sin(al)).normalized()
		var u := Vector3(1, 0, 0).cross(f).normalized()
		out.append({"c": Vector3((x0 + x1) * 0.5, 0, 0) + r * rc, "f": f, "u": u, "x": Vector3(1, 0, 0),
			"h": Vector3(BUCKET_TAN * 0.5, hu, (x1 - x0) * 0.5), "th": th})
	return out


## 柄杓の 8 隅（Wheel 局部）
static func bucket_corners(b: Dictionary) -> Array:
	var out := []
	var h: Vector3 = b["h"]
	for sf: float in [-1.0, 1.0]:
		for su: float in [-1.0, 1.0]:
			for sx: float in [-1.0, 1.0]:
				out.append((b["c"] as Vector3) + (b["f"] as Vector3) * h.x * sf + (b["u"] as Vector3) * h.y * su + (b["x"] as Vector3) * h.z * sx)
	return out


static func _buckets_mesh() -> MeshInstance3D:
	var st := _new_st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 52011
	var t := BOARD * 0.5
	_uvs = 2.5
	for b in bucket_specs():
		var c: Vector3 = b["c"]
		var f: Vector3 = b["f"]
		var u: Vector3 = b["u"]
		var x: Vector3 = b["x"]
		var h: Vector3 = b["h"]
		var B := Basis(f, u, x)
		var tone := WOOD_VC * rng.randf_range(0.93, 1.06)
		_vc = Color(tone * 0.7, tone * 0.7, tone * 0.7)          # 底板：口から見える内側（暗い）
		_box(st, c - f * (h.x - t), Vector3(t, h.y, h.z), B)
		_vc = Color(tone, tone, tone)
		_box(st, c - u * (h.y - t), Vector3(h.x, t, h.z), B)       # 輪側の板（輪縁に載る）
		_box(st, c + u * (h.y - t), Vector3(h.x, t, h.z), B)       # 外側の板（輪郭の外に見える）
		_box(st, c - x * (h.z - t), Vector3(h.x, h.y, t), B)       # 西の側板
		_box(st, c + x * (h.z - t) - f * h.x * 0.3, Vector3(h.x * 0.7, h.y, t), B)   # 東の側板：口の側 3 割を切り欠き＝注ぎ口（輪頂で東の受け樋へ）
		# 東面の添え板：輪面（x 2.22）に沿って輪縁から柄杓の內端まで（柄杓を輪に留める）
		var rr := Vector3(0, cos(float(b["th"])), sin(float(b["th"])))
		var tg := Vector3(0, sin(float(b["th"])), -cos(float(b["th"])))
		var rb := (float(BRACKET_R[0]) + float(BRACKET_R[1])) * 0.5
		_vc = Color(tone * 0.9, tone * 0.9, tone * 0.9)
		_box(st, Vector3(WHEEL_FACE_X - HUB.x + 0.016, 0, 0) + rr * rb, Vector3(0.016, (float(BRACKET_R[1]) - float(BRACKET_R[0])) * 0.5, 0.07), Basis(Vector3(1, 0, 0), rr, tg))
	_vc = Color(1, 1, 1)
	_uvs = 1.0
	var mi := _mi("LiftBuckets", st, load(WOOD), 140.0)
	mi.set_meta("phase", "P10 R5b ROUND 2")
	# 柄杓の中の水（底板から 0.15 m、口の向き f を法線にした 1 枚；shader mode 2＝口が上を向いている間だけ見える）
	var sw := _new_st()
	for b in bucket_specs():
		var c: Vector3 = b["c"]
		var f: Vector3 = b["f"]
		var u: Vector3 = b["u"]
		var x: Vector3 = b["x"]
		var h: Vector3 = b["h"]
		var wc := c - f * (h.x - BOARD - 0.15)
		var hu := h.y - BOARD - 0.005
		var hx := h.z - BOARD - 0.005
		var vs: Array[Vector3] = [wc - u * hu - x * hx, wc + u * hu - x * hx, wc + u * hu + x * hx, wc - u * hu + x * hx]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var n := (vs[1] - vs[0]).cross(vs[3] - vs[0]).normalized()
		if n.dot(f) < 0.0:
			vs = [vs[0], vs[3], vs[2], vs[1]]
			uvs = [uvs[0], uvs[3], uvs[2], uvs[1]]
		for i in [0, 1, 2, 0, 2, 3]:
			sw.set_normal(f)
			sw.set_uv(uvs[i])
			sw.add_vertex(vs[i])
	var wmi := _fx_mi("BucketWater", sw, _fall_mat(0.9, 2), 90.0)
	mi.add_child(wmi)
	return mi


## ─────────────────────────── 水車 2：受け樋＋樋頭架台＋落水（Hero 局部） ───────────────────────────
static func trough_specs() -> Dictionary:
	return {"x": TROUGH_X, "z": P8_HEAD_LOCAL.z, "w": TROUGH_W, "wall": TROUGH_WALL, "bot": TROUGH_BOT}


static func _trough_node(water_y: float) -> Node3D:
	var g := Node3D.new()
	g.name = "UkeToi"
	var st := _new_st()
	var z := P8_HEAD_LOCAL.z
	var hw := TROUGH_W * 0.5
	var t := 0.04
	var xa: float = TROUGH_X[0]
	var xb: float = TROUGH_X[1]
	var ya: float = TROUGH_BOT[0]
	var yb: float = TROUGH_BOT[1]
	var B := Basis(Vector3(xb - xa, yb - ya, 0).normalized(), Vector3(-(yb - ya), xb - xa, 0).normalized(), Vector3(0, 0, 1))
	var L := Vector2(xb - xa, yb - ya).length()
	var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - TROUGH_FLOOR * 0.5, z)
	_vc = Color(WOOD_VC * 0.95, WOOD_VC * 0.95, WOOD_VC * 0.95)
	_box(st, mid, Vector3(L * 0.5, TROUGH_FLOOR * 0.5, hw + t), B)                                     # 底板（P8 枕木の上に載る）
	_vc = Color(WOOD_VC, WOOD_VC, WOOD_VC)
	for sd: float in [-1.0, 1.0]:
		_box(st, mid + B.y * (TROUGH_FLOOR * 0.5 + TROUGH_WALL * 0.5) + B.z * sd * (hw + t * 0.5), Vector3(L * 0.5, TROUGH_WALL * 0.5, t * 0.5), B)   # 側板
	_box(st, Vector3(xa + t * 0.5, ya + TROUGH_WALL * 0.5, z), Vector3(t * 0.5, TROUGH_WALL * 0.5, hw + t))   # 西端板（輪面より東）
	_vc = Color(1, 1, 1)
	g.add_child(_mi("Trough", st, load(WOOD), 160.0))
	# 槽內水面（P8 落とし樋同一 flow 材質）
	var sw := _new_st()
	var wy0 := ya + 0.05
	var wy1 := yb + 0.05
	_flow_quad(sw, Vector3(xa + t, wy0, z), Vector3(xb, wy1, z), Vector3(0, 0, 1), hw - 0.01)
	var wmi := MeshInstance3D.new()
	wmi.name = "Water"
	wmi.mesh = sw.commit()
	wmi.material_override = _fall_mat(0.8, 3)
	wmi.visibility_range_end = 120.0
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(wmi)
	return g


static func _fall_mat(alpha: float, mode := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(FALL_SH)
	m.set_shader_parameter("alpha_max", alpha)
	m.set_shader_parameter("mode", mode)
	if mode == 3:
		m.set_shader_parameter("glow", 0.05)   # 樋の流れ：光らせない（明るい縦の帯＝柱に見えないように）
	return m


## 樋の流れ面：a（上流）→ b（下流）の中心線、横方向 side、半幅 hw；UV.x＝横 0..1、UV.y＝流下距離（m）
static func _flow_quad(st: SurfaceTool, a: Vector3, b: Vector3, side: Vector3, hw: float) -> void:
	var L := a.distance_to(b)
	var vs: Array[Vector3] = [a - side * hw, a + side * hw, b + side * hw, b - side * hw]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, L), Vector2(0, L)]
	var n := (vs[1] - vs[0]).cross(vs[3] - vs[0]).normalized()
	if n.y < 0.0:
		n = -n
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(vs[i])


## 落水の帯：a（上）→ b（下）、幅 w、交差 2 枚（東西・南北どちらからも見える）；UV.x 横、UV.y 上 0 → 下 1
static func _stream(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := (b - a).normalized()
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var s := (side - d * side.dot(d)).normalized() * w * 0.5
		var vs: Array[Vector3] = [a - s, a + s, b + s * 1.25, b - s * 1.25]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var n := (vs[1] - vs[0]).cross(vs[3] - vs[0]).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.add_vertex(vs[i])


## 弧の落水：pts（上→下）を通る帯、幅 ws（各点）、交差 2 枚；UV.y＝0（上）→ 1（下）
static func _arc_stream(st: SurfaceTool, pts: Array, ws: Array) -> void:
	var n := pts.size()
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var L: Array[Vector3] = []
		var R: Array[Vector3] = []
		for i in n:
			var d: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var s := (side - d * side.dot(d)).normalized() * float(ws[i]) * 0.5
			L.append((pts[i] as Vector3) - s)
			R.append((pts[i] as Vector3) + s)
		for i in n - 1:
			var v0 := float(i) / (n - 1)
			var v1 := float(i + 1) / (n - 1)
			var vs: Array[Vector3] = [L[i], R[i], R[i + 1], L[i + 1]]
			var uvs: Array[Vector2] = [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
			var nn := (vs[1] - vs[0]).cross(vs[3] - vs[0]).normalized()
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nn)
				st.set_uv(uvs[k])
				st.add_vertex(vs[k])


## 水面の泡（楕円の扇）
static func _foam(st: SurfaceTool, c: Vector3, rx: float, rz: float) -> void:
	var N := 14
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var p0 := c + Vector3(cos(a0) * rx, 0, sin(a0) * rz)
		var p1 := c + Vector3(cos(a1) * rx, 0, sin(a1) * rz)
		var tri := [[c, Vector2(0.5, 0.5)], [p0, Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)], [p1, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)]]
		for e in tri:
			st.set_normal(Vector3.UP)
			st.set_uv(e[1])
			st.add_vertex(e[0])


static func _fx_mi(name: String, st: SurfaceTool, mat: Material, vr_end := 110.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.visibility_range_end = vr_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 落水の幾何（Hero 局部）：gate と build が同じ値を使う
static func spill_specs(water_y: float) -> Array:
	var out := []
	for k in SPILL_TH_DEG.size():
		var th := deg_to_rad(float(SPILL_TH_DEG[k]))
		var top := Vector3(SPILL_X, HUB.y + SPILL_R * cos(th), HUB.z + SPILL_R * sin(th))
		out.append({"top": top, "bot": Vector3(SPILL_X, water_y + 0.02, top.z + 0.08), "w": 0.05})
	return out


static func foam_specs(water_y: float) -> Array:
	return [{"c": Vector3(1.75, water_y + 0.015, 1.65), "rx": 0.62, "rz": 0.95}, {"c": Vector3(1.70, water_y + 0.015, -1.55), "rx": 0.55, "rz": 0.75}]


static func _water_fx(water_y: float) -> Node3D:
	var g := Node3D.new()
	g.name = "WaterFX"
	var sp := _new_st()
	_arc_stream(sp, [POUR_TOP, POUR_MID, POUR_BOT], POUR_W)
	g.add_child(_fx_mi("Pour", sp, _fall_mat(0.75)))
	var sy := _new_st()
	_arc_stream(sy, [POUR_TOP + Vector3(0, 0.03, 0), POUR_MID, POUR_BOT + Vector3(0.02, 0, 0)], [0.2, 0.34, 0.42])
	g.add_child(_fx_mi("Spray", sy, _fall_mat(0.45, 4)))
	var ss := _new_st()
	for sd: Dictionary in spill_specs(water_y):
		_stream(ss, sd["top"], sd["bot"], float(sd["w"]))
	g.add_child(_fx_mi("Spill", ss, _fall_mat(0.75, 4)))
	var sf := _new_st()
	for fd: Dictionary in foam_specs(water_y):
		_foam(sf, fd["c"], float(fd["rx"]), float(fd["rz"]))
	g.add_child(_fx_mi("Foam", sf, _fall_mat(0.45, 1), 90.0))
	var sk := _new_st()
	_foam(sk, POUR_BOT + Vector3(0.05, 0.012, 0.0), 0.22, 0.17)   # 受け樋の中の跳ね（樋幅 0.40 の中）
	g.add_child(_fx_mi("Splash", sk, _fall_mat(0.9, 1), 90.0))
	return g


## P8 落とし樋の水面に白い流れ（世界座標；P8 の水面＝樋底＋0.085、その 1 cm 上）——P8 の幾何・材質は不動
static func _chute_flow() -> Node3D:
	var g := Node3D.new()
	g.name = "ChuteFlow"
	var st := _new_st()
	for i in P8_CHUTE.size() - 1:
		var a: Vector3 = P8_CHUTE[i]
		var b: Vector3 = P8_CHUTE[i + 1]
		var d := Vector2(b.x - a.x, b.z - a.z)
		var L := d.length()
		var basis := Basis(Vector3.UP, atan2(d.x, d.y)) * Basis(Vector3.RIGHT, atan2(a.y - b.y, L))
		var up := basis.y
		_flow_quad(st, a + up * 0.095, b + up * 0.095, basis.x, P8_CHUTE_W * 0.5 - 0.05)
	g.add_child(_fx_mi("Flow", st, _fall_mat(0.75, 3), 140.0))
	return g


## 架台：柱 2（水渠底 → P8 枕木下）＋頭貫＋腰貫＋筋交い（輪と同じ暗い木）；bed_y＝兩柱腳的水渠底高（Hero 局部）
static func _bent_node(bed_y: Array, water_y := 0.0) -> Node3D:
	var g := Node3D.new()
	g.name = "HeadBent"
	var st := _new_st()
	var top := P8_BEARER_TOP - 0.14 - 0.01
	for i in 2:
		var x: float = BENT_X[i]
		var wet := water_y + 0.5
		_vc = Color(BENT_WET_VC, BENT_WET_VC, BENT_WET_VC)                  # 水しぶきで濡れた脚（暗い）
		_beam(st, Vector3(x, float(bed_y[i]) - 0.30, BENT_Z), Vector3(x, wet, BENT_Z), POST)
		_vc = Color(BENT_VC, BENT_VC, BENT_VC)                              # P5 軸受け架構と同じ古い木
		_beam(st, Vector3(x, wet, BENT_Z), Vector3(x, top, BENT_Z), POST)
	_vc = Color(BENT_VC * 1.05, BENT_VC * 1.05, BENT_VC * 1.05)
	_box(st, Vector3((BENT_X[0] + BENT_X[1]) * 0.5, top - 0.07, BENT_Z), Vector3((BENT_X[1] - BENT_X[0]) * 0.5 + 0.14, 0.07, 0.09))   # 頭貫（枕木下）
	var mid_y := lerpf(maxf(float(bed_y[0]), float(bed_y[1])) + 0.6, top, 0.45)
	_box(st, Vector3((BENT_X[0] + BENT_X[1]) * 0.5, mid_y, BENT_Z), Vector3((BENT_X[1] - BENT_X[0]) * 0.5 + 0.12, 0.06, 0.07))          # 腰貫
	_beam(st, Vector3(BENT_X[0], maxf(float(bed_y[0]), -0.9), BENT_Z + 0.11), Vector3(BENT_X[1], top - 0.15, BENT_Z + 0.11), 0.09)        # 筋交い
	_vc = Color(1, 1, 1)
	g.add_child(_mi("Posts", st, load(WOOD), 160.0))
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
	ww.add_child(_trough_node(float(heights.get("water_y", 0.0))))
	ww.add_child(_bent_node(heights["bent_bed"], float(heights.get("water_y", 0.0))))
	ww.add_child(_water_fx(float(heights.get("water_y", 0.0))))
	root.add_child(_chute_flow())
	var bk := _buckets_mesh()
	bk.transform = Transform3D(Basis(), HUB)   # 停放位置＝輪心（runtime 掛到 Rotor 下時改成 identity）
	ww.add_child(bk)
	root.set("rotor_path", NodePath(ROTOR))
	root.set("buckets_path", NodePath("WW2_Lift/LiftBuckets"))
	root.set("p8_supply_path", NodePath(P8_SUPPLY))
	root.set("p8_tone", P8_TONE)
	var hb := (P8_CHUTE[0] as Vector3) - Vector3(0.9, 0, 0)   # HeadBearer（樋頭の枕木、輪側へ 0.45 + 半長）まで含める
	root.set("p8_near", PackedVector3Array([hb] + P8_CHUTE))
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


## ROUND 2：手作り網格の表裏（Godot の表＝時計回り：三角形 (v0,v1,v2) の表向き法線＝(v2−v0)×(v1−v0)）と明示法線が逆の三角形を数える
## （r1–r12／r1–r4 の不具合：方塊が裏返し・踏面が下向き法線＝日光が当たらない）。FX（ShaderMaterial）は両面なので対象外。
static func winding_bad(root_node: Node) -> Array:
	var bad := 0
	var tot := 0
	var list := root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		list.append(root_node)
	for mi in list:
		var m := mi as MeshInstance3D
		if m.mesh == null or m.material_override is ShaderMaterial or not (m.mesh is ArrayMesh):
			continue
		# 外部の資產（kit .res／glTF）は対象外：この overlay が作った埋め込み網格（パスなし、または scn::）だけ
		if m.mesh.resource_path != "" and not m.mesh.resource_path.contains("::"):
			continue
		for s in m.mesh.get_surface_count():
			var arr := (m.mesh as ArrayMesh).surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			var n_tri: int = (int(idx.size()) if idx != null else vs.size()) / 3
			for t in n_tri:
				var i0: int = idx[t * 3] if idx != null else t * 3
				var i1: int = idx[t * 3 + 1] if idx != null else t * 3 + 1
				var i2: int = idx[t * 3 + 2] if idx != null else t * 3 + 2
				var fn := (vs[i2] - vs[i0]).cross(vs[i1] - vs[i0])
				if fn.length_squared() < 1e-12:
					continue
				tot += 1
				if fn.dot(ns[i0] + ns[i1] + ns[i2]) < 0.0:
					bad += 1
	return [bad, tot]


## 反向用：r1–r12 の巻き順（a, b, c）＋法線 (b−a)×(c−a) の四角 1 枚
static func old_winding_quad() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-1, 0, 0)
	var b := Vector3(-1, 0, 1)
	var c := Vector3(1, 0, 1)
	var d := Vector3(1, 0, 0)
	var n := (b - a).cross(c - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi
