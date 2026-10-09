extends RefCounted
## P10 R5b Water Logic Pilot（使用者 2026-10-09 D5／D10）。overlay `WaterLifeP10`（gen/water_life_p10.scn，root、GroundPilotP10 之後）。
## ROUND 3（使用者 FINAL ART DIRECTION：R5b NOT ART_APPROVED → 揚水案を止め、水車 2＝純動力水車）：
##   · ROUND 1／2 で足した揚水部材（柄杓・受け樋・樋頭架台・注ぎ／こぼれ水・柄杓の中の水・樋の流れ）を全部撤去。
##   · 水車 2＝下掛け（undershot）の動力水車：水渠の流れ（Hero +z＝下流）が水面下の葉板を押す → 輪の下端は下流へ動く
##     （P5 RotorAnim の回転向きを gate で実測）；葉板の浸かり 0.15–0.8 m；葉板が水から出る下流側に白い泡。
##   · P8 の「水車 2 から 3.30 m の高架落とし樋」（Chute_0／Chute_1／ChuteJoint／HeadBearer／Support_00／01 と碰撞 Post_00／Post_01／Chute_1）は
##     水源のない高架渠道になるので runtime で非表示・碰撞停止（P8 ファイル不変、enabled=false で元どおり）＝P8 limited correction の Pilot。
##     DropBox 以下（上段土渠・伏越し・地面木槽・田）は触らない。ROUND 2 の P8 木部の runtime 調暗は不要になったので撤去。
##   · 実測：P8 の田の水面 +0.05（Pilot 7 枚）は、近くのどの既存水系（水渠 −1.13〜−1.63、主河 −0.80）より高い
##     → 既存水系からの自流は不可（最も近い高い水＝西の細渠 WestStream、x 68–180、村の反対側）。灌漑の水源は使用者裁定の案として報告。
##   · 精米・機械用途は提案のみ（建物を足さない）。水車 1／3 は不動。
## D10：主河一艘小舟＋一處繫泊／卸貨點（ROUND 1 のまま）：P7 主河唯一的親水石段（雁木，RB_16_-4 step_0–4）下端，
##   川舟 7.2 × 1.5 m（吃水 0.12）、繫船杭 1、舫い綱、石段頂「届いた荷」（street_kit st_kago_tsumi 重用）。
## 不改任何封存檔（P5 水車、P7 河岸、P8 田、R2 street_kit）；enabled=false 全部撤回。

const NODE_NAME := "WaterLifeP10"
const OUTPUT := "res://maps/village_v2/gen/water_life_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/water_life.gd"
const ART_REVISION := "P10 R5b ROUND 3 水車 2 r16：純動力水車（揚水部材を全撤去、葉板が水渠の流れを受ける下掛け、下流側の泡）、P8 の水車 2 落とし樋（高架 3.30 m）を runtime 非表示＝P8 limited correction Pilot；ROUND 2 r15 までの揚水案（柄杓・受け樋・架台・注ぎ・樋の流れ）は使用者裁定で撤去（ART_REVIEW）"
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
## P8 取水（farmland_p8.scn）：R5b.1（2026-10-10）で高架落とし樋を P8 生成器側で撤去し竜骨車へ置き換えた。
##   本 overlay は P8 のノードを一切隠さない／止めない（ROUND 3 の runtime 非表示は撤去）。gate はその状態を確認するだけ。
const P8_SUPPLY := "Districts/FarmlandEast/FarmlandP8/FieldDetails/WaterSupply"
const P8_COL := "Districts/FarmlandEast/FarmlandP8/Irrigation/WaterSupply"
const P8_PUMP := "Ryukotsu"
const P8_KEEP := ["DropBox", "SiphonBox_0", "SiphonBox_1", "GroundTrough", "Crossing_trough_385", "Crossing_trough_397", "Crossing_upper_354"]
const IMMERSE := [0.15, 0.80]     # 葉板先端の浸かり（下掛け：浅すぎると流れを受けない、深すぎると輪が水を掻き上げる）
const LIFT_PARTS := ["LiftBuckets", "UkeToi", "HeadBent", "Pour", "Spill", "Splash", "Spray", "ChuteFlow", "BucketWater"]

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


## ─────────────────────────── 水車 2：動力水車の水（Hero 局部） ───────────────────────────
static func _fall_mat(alpha: float, mode := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(FALL_SH)
	m.set_shader_parameter("alpha_max", alpha)
	m.set_shader_parameter("mode", mode)
	return m


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


## 泡：[0]＝葉板が水から出る下流側（主）、[1]＝葉板が水に入る上流側（小）、[2]＝下流の引き波（細長）
static func foam_specs(water_y: float) -> Array:
	return [{"c": Vector3(1.62, water_y + 0.015, 2.05), "rx": 0.55, "rz": 0.85},
		{"c": Vector3(1.62, water_y + 0.015, -2.25), "rx": 0.35, "rz": 0.40},
		{"c": Vector3(1.55, water_y + 0.012, 3.60), "rx": 0.38, "rz": 1.10}]


static func _power_fx(water_y: float) -> Node3D:
	var g := Node3D.new()
	g.name = "WaterFX"
	var sf := _new_st()
	for fd: Dictionary in foam_specs(water_y):
		_foam(sf, fd["c"], float(fd["rx"]), float(fd["rz"]))
	g.add_child(_fx_mi("Foam", sf, _fall_mat(0.5, 1), 90.0))
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
## heights：{"water_y"（Hero 局部）, "post_ground": y, "kago_ground": y, "kago_p": Vector2}
static func build(v: Node3D, heights: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R5b pilot")
	# 水車 2（純動力）：泡だけ（揚水部材なし）；P8 の高架落とし樋は runtime で隠す
	var hero := v.get_node(WHEEL) as Node3D
	var ww := Node3D.new()
	ww.name = "WW2_Power"
	ww.transform = hero.global_transform
	root.add_child(ww)
	ww.add_child(_power_fx(float(heights.get("water_y", 0.0))))
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
