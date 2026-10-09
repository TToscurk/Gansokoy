extends RefCounted
## P10 R6b Shrine Approach Pilot（使用者 2026-10-09 D6 端景 Pilot／D7 石段＝視覺石段＋斜坡碰撞）。
## overlay `ShrineApproachP10`（gen/shrine_approach_p10.scn，root、WaterLifeP10 之後）。
## 根因（MASTER AUDIT R6b-01／03）：參道＝5 m secondary 道路 ribbon（車轍參數），s 37–100 m 約 30° 連續土坡，無踏面／蹴上；
##   主街第 5 段（(280,−80)→(300,−130)）的軸心盡頭是普通町家 MXC_018，沒有「往神社」的視覺終點。
## Pilot：
##   · 一の鳥居：sando_torii（P5 Hero 重用，扁額「龍神社」）立在參道起點 s 7 m（主街軸心盡頭的左前方、丘腳街路緣外），
##     讓主街終點＝神社入口；MXC_018 不動不刪。
##   · 石段：沿參道（平滑中心線）在坡度 > 16° 的段落鋪石段：蹴上 0.12–0.20、踏面依坡度 0.25–0.45、寬 3.0 m＋兩側袖石；
##     緩坡段（< 16°）＝順坡石疊（無蹴上）。踏面頂＝該段後緣的地形高＋0.02（石段整段在 P1 地形斜坡之上，地形不會蓋住踏面）。
##   · 碰撞＝平順斜坡（D7）：新的一條斜坡碰撞帶通過每段踏面中點（腳底與踏面差 ≤ 半個蹴上），起終點接回 P1 地形；
##     參道 ribbon 在石段範圍內挖掉中央（ground pilot shader 的 cut_s／cut_hw），兩側路肩保留。
##   · 石燈籠（garden_kit gk_toro_kasuga 重用）：石段沿線每 ≈ 20 m 一對（節奏點）。
## 不改封存（P1 地形、P3 道路、P5 鳥居資產、P9 R4-2 鎮守之森）；enabled=false 隱藏全部、停用碰撞。

const NODE_NAME := "ShrineApproachP10"
const OUTPUT := "res://maps/village_v2/gen/shrine_approach_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/shrine_approach.gd"
const ART_REVISION := "P10 R6b ROUND 2 r8（ROUND 2 最終）：袖石を低く細く（踏面＋2–7 cm・幅 0.16–0.24・20 % 欠け）＝背の高い縁石に見えない、上面は苔、鼻先の面取りを石ごとに 2.5–6 cm（摩耗）、15 % の石にひび（細い暗線）；r7：法線修正後は明るすぎ（黄緑・白っぽい）→ 石材 0.64＝風化した灰（参考写真の暗い灰の石段）、袖石の苔は灰緑寄り、鼻先は石ごとに 0–3.7 cm 張り出し・左右で傾き（不揃いの鼻先線）、袖石は前の石の高さに続ける・欠け 8 %；r6：踏石の色を灰中心（暖灰は控えめ＝踏面の茶色い帯を消す）、1 段＝1 枚石が多く 2 枚は継ぎ目の位置を不揃いに（ジグザグの目地をやめる）、袖石＝1–3 段の短い石・高さ／幅不揃い・15 % 欠け・黄緑の苔（参考写真）、踊り場＝大きめの敷石＋前縁の框石、石段の両脇の參道 ribbon を全幅で隠す（茶色い土の帯）；r5：根因修正——石段の法線が裏向き（Godot の表＝時計回りと逆）で踏面に日光が当たらず暗い青に見えていた（r1–r4 共通、下り視点 2/5 の主因）→ 法線を表向きに；r4：下り視点 2/5 の整改——30° 一定坂の 170 段を踊り場 3（盛土・前縁 ≤ 1.2 m）＋丘の肩の長い踏面で 5 つの流れに分け、幅 3.0→2.4 m、踏石 2–3 枚の不揃い・面取りした鼻先（摩耗）・目地・色差（暖灰／青灰／緑灰）・袖石の苔と欠け、踊り場は石畳、踏面 UV を水平投影に（石の質感が出る）、石材 0.80／立面 0.82（暗い一様面を減らす）／r3b（技術修正：一の鳥居の柱台に乗り上げ防止ガード）／r3：踏面明／立面暗（RISER_TONE 0.70）で段のリズム、石材 0.72；r2：石段色調（每段明暗差＋袖石苔味）、石材提亮（R6a 校正相當）、燈籠坐在坂に据えた水平基壇（ART_REVIEW）"
const TORII_SCN := "res://assets/village_v2/sando_torii/sando_torii.scn"
const LANTERN := "res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga.res"
const LANTERN_L1 := "res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga_l1.res"
const STONE := "res://assets/village_v2/_matlib/V2_Stone.tres"

const SANDO := [Vector2(300, -130), Vector2(292, -160), Vector2(280, -190), Vector2(266, -208), Vector2(258, -222)]
const SANDO_HW := 2.5
const TORII1_S := 7.0
const TORII1_SCALE := 1.0
const GUARD_R := 0.52       # 柱台 0.72 角の外接円（半対角 0.509）
const GUARD_H := 2.0
const HILL_TORII := Vector2(289.6, -166.0)
const STEP_W := 2.4                # ROUND 2：3.0 → 2.4（大型の記念階段に見えない、古い社の参道幅）
const CURB_W := 0.24
const CURB_UP := 0.10              # 袖石高出踏面（段ごとに 0.07–0.14 で揺らす）
const RISER := [0.12, 0.20]
const TREAD := [0.25, 0.45]
const RISER_TARGET := 0.18
const SLOPE_MIN_DEG := 16.0        # 坡度 > 16° 鋪石段；之間的緩坡＝順坡石疊
## ROUND 2：リズム（下り視点で 170 段が一本の帯に見えない）
const LANDINGS := [[50.0, 1.5], [62.6, 1.6], [75.6, 1.5]]   # 30° 一定坂の踊り場 [前縁 s m, 奥行 m]；62.6＝參道が 16° 曲がる所（33° の瘤があるので 1.6）
const LANDING_D := [1.2, 2.0]
const LANDING_FILL_MAX := 1.2      # 踊り場前縁の盛土（踏面 − 地形）上限：手前の段を少し急にして上がる
const GENTLE_DEG := 22.0           # 1 m 窓の勾配がこれ未満＝丘の肩（自然の緩斜面）＝踏面の長い段
const LONG_TREAD := [0.45, 1.20]
const LONG_RISER_TARGET := 0.14
const FLIGHT_MAX := 60             # 休み（踊り場・長い段）なしで続く段数の上限
const STONE_ALBEDO := Color(0.64, 0.635, 0.62)  # 風化した灰の石（r5 の法線修正で踏面に日が当たる → 0.80 は白っぽい、参考写真＝暗い灰）
const LANTERN_EVERY := 20.0
const LANTERN_OFF := STEP_W * 0.5 + CURB_W + 0.55
const PLINTH := 0.9          # 燈籠基壇（坂に据える水平の石台）邊長
const PLINTH_UP := 0.06
const RISER_TONE := 0.82     # 立面の明度（踏面＝1）：r3 0.70 → 暗い一様面を減らす（下端だけ目地の汚れで暗く）
const OTHER_ROADS := {"HillFootStreet": [[200, -148], [250, -150], [300, -130], [342, -128], [372, -128]], "MainStreet": [[262, -20], [280, -80], [300, -130]]}
const OTHER_HW := {"HillFootStreet": 3.0, "MainStreet": 3.6}
const RIBBON := "Roads/SecondaryRoads/HillApproach"
const RIBBON_MESH := "res://maps/village_v2/gen/road_hillapproach.res"
const RIBBON_EDGE := {"edge_w": 0.35, "edge_irreg": 0.15, "edge_core": 0.35, "center_patch": 0.0}


## 平滑中心線（Chaikin 4 次，端點固定）→ 每 0.05 m 重新取樣
static func centerline() -> PackedVector2Array:
	var pts := PackedVector2Array(SANDO)
	for it in 4:
		var q := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			q.append(pts[i].lerp(pts[i + 1], 0.25))
			q.append(pts[i].lerp(pts[i + 1], 0.75))
		q.append(pts[pts.size() - 1])
		pts = q
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var t := 0.05 - acc
		while t <= L:
			out.append(a.lerp(b, t / L))
			t += 0.05
		acc = L - (t - 0.05)
	return out


static func s_at(cl: PackedVector2Array, k: int) -> float:
	return k * 0.05


static func tangent(cl: PackedVector2Array, k: int) -> Vector2:
	var a := cl[maxi(k - 6, 0)]
	var b := cl[mini(k + 6, cl.size() - 1)]
	return (b - a).normalized()


## 地形斜坡高度（只認 TerrainCollision；P1 碰撞＝玩家實際走的面）
static func ramp_profile(v: Node3D, cl: PackedVector2Array) -> PackedFloat32Array:
	var sp := v.get_world_3d().direct_space_state
	var out := PackedFloat32Array()
	out.resize(cl.size())
	for k in cl.size():
		var p := cl[k]
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
		var ex: Array[RID] = []
		var y := NAN
		for t in 12:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				y = float(h["position"].y)
				break
			ex.append(h["rid"])
		out[k] = y
	return out


static func _slope_deg(H: PackedFloat32Array, k: int, w: int) -> float:
	var n := H.size()
	var a := maxi(k - w, 0)
	var b := mini(k + w, n - 1)
	return rad_to_deg(atan2(H[b] - H[a], maxf((b - a) * 0.05, 0.05)))


static func _hmax(H: PackedFloat32Array, k0: int, k1: int) -> float:
	var hm := -INF
	for j in range(k0, k1 + 1):
		hm = maxf(hm, H[j])
	return hm


## 石段：回傳 [{k0, k1, y0, y1, kind}]（k＝中心線索引 0.05 m）
##   step：普通の段（踏面 0.25–0.45、水平）／landing：踊り場（奥行 1.2–2.0、水平、前縁は盛土）／
##   long：丘の肩の緩斜面の長い踏面（0.45–1.2）／slab：< 16° の順坡石疊
##   踊り場までの段＝「最後の蹴上で踊り場に上がる」計画（地形 30° より少し急、踏面は常に地形の上）；それ以外＝地形に沿う貪欲法。
static func steps(cl: PackedVector2Array, H: PackedFloat32Array, landings: Array = LANDINGS) -> Array:
	var out := []
	var n := cl.size()
	var k := 0
	while k < n - 1 and absf(_slope_deg(H, k, 10)) < SLOPE_MIN_DEG:
		k += 1
	var k_start := k
	var k_end := n - 1
	while k_end > k_start and absf(_slope_deg(H, k_end, 10)) < SLOPE_MIN_DEG:
		k_end -= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 61021
	# 丘の肩：最後の踊り場より 1 m 以上上で、1 m 窓の勾配 < GENTLE_DEG が 2 m 以上続く最初の区間
	var after := k_start
	for L in landings:
		after = maxi(after, int(round((float(L[0]) + float(L[1])) / 0.05)))
	var kg0 := -1
	var kg1 := -1
	var kk := after + 20
	while kk < k_end:
		if _slope_deg(H, kk, 20) < GENTLE_DEG:
			var j := kk
			while j < k_end and _slope_deg(H, j, 20) < GENTLE_DEG + 2.0:
				j += 1
			if (j - kk) * 0.05 >= 2.0:
				kg0 = kk
				kg1 = j
				break
			kk = j
		kk += 1
	var y := H[k_start]
	k = k_start
	for L in landings:
		var ka := int(round(float(L[0]) / 0.05))
		var kb := ka + int(round(float(L[1]) / 0.05))
		if ka <= k + 20 or kb >= k_end:
			continue
		var yl := _hmax(H, ka, kb) + 0.02
		var r := _planned_flight(out, H, k, y, ka, yl, rng)
		out.append({"k0": int(r[0]), "k1": kb, "y0": yl, "y1": yl, "kind": "landing"})
		k = kb
		y = yl
	if kg0 > k:
		var r2 := _terrain_flight(out, H, k, y, kg0, TREAD, RISER_TARGET, "step", rng)
		var r3 := _terrain_flight(out, H, int(r2[0]), float(r2[1]), kg1, LONG_TREAD, LONG_RISER_TARGET, "long", rng)
		k = int(r3[0])
		y = float(r3[1])
	_terrain_flight(out, H, k, y, k_end, TREAD, RISER_TARGET, "step", rng)
	return out


## 踊り場へ上がる flight：残り蹴上 N（最後の 1 本で踊り場 yl へ）・残り踏面 N−1 枚で [k, ka] を割る（毎段 再計画、±7 % の揺らぎ）
static func _planned_flight(out: Array, H: PackedFloat32Array, k: int, y: float, ka: int, yl: float, rng: RandomNumberGenerator) -> Array:
	var t_min := int(round(TREAD[0] / 0.05))
	var guard := 0
	while k < ka and guard < 400:
		guard += 1
		var run := (ka - k) * 0.05
		var rise := yl - y
		var n_lo := maxi(2, int(ceil(rise / 0.185)))
		var n_hi := maxi(n_lo, int(floor(rise / 0.13)))
		var best_n := -1
		var best_sc := INF
		for N in range(n_lo, n_hi + 1):
			var tr := run / (N - 1)
			if tr < TREAD[0] or tr > TREAD[1]:
				continue
			var sc := absf(rise / N - RISER_TARGET) + absf(tr - 0.30) * 0.5
			if sc < best_sc:
				best_sc = sc
				best_n = N
		if best_n == -1:
			best_n = maxi(2, int(round(run / 0.30)) + 1)
		var tr2 := run / (best_n - 1)
		var rs := rise / best_n
		if best_n > 3:
			tr2 *= rng.randf_range(0.93, 1.07)
			rs *= rng.randf_range(0.95, 1.05)
		var kn := k + int(round(tr2 / 0.05))
		if best_n == 2 or ka - kn < t_min:
			kn = ka
		kn = clampi(kn, k + 1, ka)
		var yn := y + rs
		var hm := _hmax(H, k, kn) + 0.02
		if yn < hm:
			yn = hm
		out.append({"k0": k, "k1": kn, "y0": yn, "y1": yn, "kind": "step"})
		k = kn
		y = yn
	return [k, y]


## 地形に沿う貪欲法：踏面 tread_rng 中で「蹴上が r_target（±7 % 揺らぎ）に最も近い」長さ；踏面頂＝段內地形最高＋0.02
static func _terrain_flight(out: Array, H: PackedFloat32Array, k: int, y_prev: float, k_stop: int, tread_rng: Array, r_target: float, kind: String, rng: RandomNumberGenerator) -> Array:
	var t0 := int(round(float(tread_rng[0]) / 0.05))
	var t1 := int(round(float(tread_rng[1]) / 0.05))
	while k < k_stop:
		var rt := r_target * rng.randf_range(0.93, 1.07)
		var best := {}
		for tk in range(t0, t1 + 1):
			var kn := k + tk
			if kn > k_stop:
				break
			var yv := _hmax(H, k, kn) + 0.02
			var r := yv - y_prev
			var sc := absf(r - rt) + (0.0 if r <= RISER[1] else 1.0)
			if best.is_empty() or sc < float(best["sc"]):
				best = {"kn": kn, "y": yv, "r": r, "sc": sc}
		if best.is_empty():
			break
		if float(best["r"]) < RISER[0]:
			# 緩坡：順坡石疊，延伸到坡度回到 16° 以上（或到 k_stop）
			var kn2 := mini(k + t1, k_stop)
			while kn2 < k_stop and absf(_slope_deg(H, kn2, 10)) < SLOPE_MIN_DEG:
				kn2 += 1
			var y0 := maxf(y_prev, H[k] + 0.03)
			var y1 := H[kn2] + 0.03
			var deficit := 0.0
			for j in range(k, kn2 + 1):
				var yl := lerpf(y0, y1, float(j - k) / float(maxi(kn2 - k, 1)))
				deficit = maxf(deficit, H[j] + 0.02 - yl)
			out.append({"k0": k, "k1": kn2, "y0": y0 + deficit, "y1": y1 + deficit, "kind": "slab"})
			y_prev = y1 + deficit
			k = kn2
			continue
		out.append({"k0": k, "k1": int(best["kn"]), "y0": float(best["y"]), "y1": float(best["y"]), "kind": kind})
		y_prev = float(best["y"])
		k = int(best["kn"])
	return [k, y_prev]


## 斜坡碰撞帶的中心線點：[s 索引, y]——起點＝第一段前緣地形、每段踏面中點（step）／兩端（slab）、終點＝最後一段後緣地形
static func ramp_points(st: Array, H: PackedFloat32Array) -> Array:
	var out := []
	if st.is_empty():
		return out
	var k0 := int(st[0]["k0"])
	var kl0 := maxi(k0 - 6, 0)   # 0.3 m 引き込み：第一段の蹴上前から斜坡を上げ始める
	out.append([kl0, H[kl0] + 0.02])
	var prev: Dictionary = {}
	for a: Dictionary in st:
		if String(a["kind"]) == "landing":
			out.append([int(a["k0"]) + 3, float(a["y0"])])
			out.append([int(a["k1"]) - 3, float(a["y0"])])
			prev = a
			continue
		if String(a["kind"]) in ["step", "long"]:
			# 緩坡石疊の直後の段：斜坡を 0.3 m 手前から上げ始める（蹴上の前で足が段に埋まらない）
			if not prev.is_empty() and String(prev["kind"]) == "slab":
				var kb := int(a["k0"]) - 6
				var ka := int(prev["k0"])
				if kb > ka:
					var t := float(kb - ka) / float(maxi(int(prev["k1"]) - ka, 1))
					out[out.size() - 1] = [kb, lerpf(float(prev["y0"]), float(prev["y1"]), t)]
			out.append([(int(a["k0"]) + int(a["k1"])) / 2, float(a["y0"])])
		else:
			if int(out[out.size() - 1][0]) != int(a["k0"]):
				out.append([int(a["k0"]), float(a["y0"])])
			out.append([int(a["k1"]), float(a["y1"])])
		prev = a
	var kl := int(st[st.size() - 1]["k1"])
	out.append([kl, H[kl] + 0.02])
	return out


## 一の鳥居：參道 s＝TORII1_S 的點；+z（扁額面）朝參道下行（往村子）
static func torii1_xf(cl: PackedVector2Array, H: PackedFloat32Array, s_at_m := TORII1_S) -> Transform3D:
	var k := int(round(s_at_m / 0.05))
	var p := cl[k]
	var t := tangent(cl, k)
	var face := -t
	var yaw := atan2(face.x, face.y)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * TORII1_SCALE), Vector3(p.x, H[k], p.y))


static func lantern_specs(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, sp: PhysicsDirectSpaceState3D = null) -> Array:
	var out := []
	if st.is_empty():
		return out
	var s0 := float(st[0]["k0"]) * 0.05
	var s1 := float(st[st.size() - 1]["k1"]) * 0.05
	var s := s0 + 6.0
	while s < s1 - 3.0:
		# 坂の横の地面が一番平らな位置へ ±1.5 m だけずらす（基壇を低く）
		var best_s := s
		if sp != null:
			var best := INF
			for ds in [0.0, 0.75, -0.75, 1.5, -1.5]:
				var k2 := int(round((s + ds) / 0.05))
				var t2 := tangent(cl, k2)
				var n2 := Vector2(-t2.y, t2.x)
				var worst := 0.0
				for sd: float in [-1.0, 1.0]:
					var g := lantern_ground(sp, cl[k2] + n2 * sd * LANTERN_OFF)
					worst = maxf(worst, float(g[1]) - float(g[0]))
				if worst < best - 0.02:
					best = worst
					best_s = s + ds
		var k := int(round(best_s / 0.05))
		var t := tangent(cl, k)
		var nrm := Vector2(-t.y, t.x)
		for sd: float in [-1.0, 1.0]:
			var p: Vector2 = cl[k] + nrm * sd * LANTERN_OFF
			out.append({"p": p, "yaw": atan2(-nrm.x * sd, -nrm.y * sd), "s": best_s})
		s += LANTERN_EVERY
	return out


## 石段首尾 → ribbon 的沿路 s（UV.y）；ribbon 頂點每 2 m 一對，取最近頂點再線性內插
static func ribbon_cut_s(cl: PackedVector2Array, st: Array) -> Vector2:
	var m := load(RIBBON_MESH) as ArrayMesh
	var arr := m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var res := Vector2()
	for e in 2:
		var p: Vector2 = cl[int(st[0]["k0"])] if e == 0 else cl[int(st[st.size() - 1]["k1"])]
		var best := INF
		var bs := 0.0
		for i in vs.size():
			var d := Vector2(vs[i].x, vs[i].z).distance_to(p)
			# 只看中心線附近（左右頂點的中點）：用 |UV.x|·hw 估側距
			if d < best:
				best = d
				bs = uv[i].y
		res[e] = bs
	return Vector2(res.x - 0.6, res.y + 0.6)


static var _vc := Color(1, 1, 1)


## 燈籠基壇的四角地面：[最低, 最高]
static func lantern_ground(sp: PhysicsDirectSpaceState3D, p: Vector2) -> Array:
	var lo := INF
	var hi := -INF
	var hp := PLINTH * 0.5
	for c2 in [Vector2(0, 0), Vector2(hp, hp), Vector2(-hp, hp), Vector2(hp, -hp), Vector2(-hp, -hp)]:
		# 只認 P1 地形（TerrainCollision）：不要打到樹幹、已掛的本 overlay（舊燈籠／斜坡碰撞）
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x + c2.x, 80.0, p.y + c2.y), Vector3(p.x + c2.x, -20.0, p.y + c2.y))
		var ex: Array[RID] = []
		for t in 16:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				lo = minf(lo, float(h["position"].y))
				hi = maxf(hi, float(h["position"].y))
				break
			ex.append(h["rid"])
	return [lo, hi]


static var _uvo := Vector2.ZERO    # 石ごとの UV ずらし（同じ模様の繰り返しを避ける）


## UV：水平面＝(x, z) 投影（r3 以前は (x+0.7z, y)＝踏面で y 一定 → 1 次元に伸びた縞＝石の質感が出なかった）、縦面＝(x+z, y)
static func _uv(v: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.6:
		return Vector2(v.x, v.z) * 0.9 + _uvo
	return Vector2(v.x + v.z, v.y) * 0.9 + _uvo


## 法線＝見える面（Godot の表＝時計回り）の向き：(c−a)×(b−a)。
## ROUND 2 修正：r1–r3 は (b−a)×(c−a)＝裏向きの法線 → 踏面が「下向き」として照らされ日光が当たらない（空の環境光だけ＝暗い青）。
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_color(_vc)
		st.set_normal(n)
		st.set_uv(_uv(v, n))
		st.add_vertex(v)


## 頂点ごとの色（立面の明暗グラデーション）
static func _quad_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	var vs := [a, b, c, a, c, d]
	var cs := [ca, cb, cc, ca, cc, cd]
	for i in 6:
		st.set_color(cs[i])
		st.set_normal(n)
		st.set_uv(_uv(vs[i], n))
		st.add_vertex(vs[i])


static func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


## 踏石 1 枚：中心線 [ka, kb]、横 [u0, u1]、頂 ya（前）／yb（奥）、底 ybot；front＝段の最前列（鼻先の面取り＋立面）
##   色：base（石ごと）、立面＝下（前の段の踏面より下）暗 0.5／見える蹴上は 0.62 → RISER_TONE、面取り＝摩耗で明るい
static func _stone(st: SurfaceTool, cl: PackedVector2Array, ka: int, kb: int, u0: float, u1: float, ya: float, yb: float, ybot: float, front: bool, rise: float, base: Color, joint := 0.0, nose := Vector2.ZERO, chamfer := 0.03) -> void:
	var ta := tangent(cl, ka)
	var tb := tangent(cl, kb)
	var na := Vector2(-ta.y, ta.x)
	var nb := Vector2(-tb.y, tb.x)
	var pa := cl[ka] + ta * joint
	var pb := cl[kb] + tb * 0.012   # 與下一段重疊 1.2 cm，不留縫
	# 鼻先の不揃い：石ごとに左端／右端を前後へ nose.x／nose.y（摩耗・据え直しで鼻先線が一直線でない）
	var FL := pa + na * u0 + ta * nose.x
	var FR := pa + na * u1 + ta * nose.y
	var BL := pb + nb * u0
	var BR := pb + nb * u1
	var T1 := Vector3(BL.x, yb, BL.y)
	var T2 := Vector3(BR.x, yb, BR.y)
	var B0 := Vector3(FL.x, ybot, FL.y)
	var B1 := Vector3(BL.x, ybot, BL.y)
	var B2 := Vector3(BR.x, ybot, BR.y)
	var B3 := Vector3(FR.x, ybot, FR.y)
	_vc = base
	if front:
		var ch := chamfer
		var T0 := Vector3(FL.x + ta.x * ch, ya, FL.y + ta.y * ch)
		var T3 := Vector3(FR.x + ta.x * ch, ya, FR.y + ta.y * ch)
		var C0 := Vector3(FL.x, ya - ch * 0.7, FL.y)
		var C3 := Vector3(FR.x, ya - ch * 0.7, FR.y)
		_quad(st, T0, T1, T2, T3)
		_vc = _mul(base, 1.1)                                  # 鼻先：足で磨かれて明るい
		_quad(st, C0, T0, T3, C3)
		var ys := maxf(ybot, ya - maxf(rise, 0.05))
		var S0 := Vector3(FL.x, ys, FL.y)
		var S3 := Vector3(FR.x, ys, FR.y)
		var dk := _mul(base, 0.5)
		_quad_c(st, B3, B0, S0, S3, dk, dk, dk, dk)
		var lo := _mul(base, 0.62)
		var hi := _mul(base, RISER_TONE)
		_quad_c(st, S3, S0, C0, C3, lo, lo, hi, hi)            # 見える蹴上：下端（目地の汚れ）暗 → 上明
		_vc = _mul(base, 0.72)
		_quad(st, B0, B1, T1, C0)
		_quad(st, B2, B3, C3, T2)
	else:
		var T0 := Vector3(FL.x, ya, FL.y)
		var T3 := Vector3(FR.x, ya, FR.y)
		_quad(st, T0, T1, T2, T3)
		_vc = _mul(base, 0.6)
		_quad(st, B3, B0, T0, T3)
		_vc = _mul(base, 0.72)
		_quad(st, B0, B1, T1, T0)
		_quad(st, B2, B3, T3, T2)
	_vc = _mul(base, 0.6)
	_quad(st, B1, B2, T2, T1)


## 石の色：暖灰／青灰／緑灰（苔）× 明度；端の石は苔寄り
static func _stone_tone(rng: RandomNumberGenerator, edge: bool) -> Color:
	# 灰が中心：やや暖 35 %／やや冷 40 %／苔むした緑灰 25 %（r5 の暖灰 0.90 は日向で茶色い帯に見えた）
	var v := rng.randf_range(0.72, 1.0)
	var hue := rng.randf()
	var c := Color(v, v * 0.985, v * 0.955) if hue < 0.35 else (Color(v * 0.96, v * 0.98, v) if hue < 0.75 else Color(v * 0.88, v * 0.95, v * 0.82))
	if edge:
		c = Color(c.r * 0.92, c.g * 0.97, c.b * 0.88)
	return c


## 方塊：底面四點（xz）＋底高 yb／頂高 yt（q[0],q[3]＝前緣、q[1],q[2]＝後緣；yt2＝後緣頂高，NAN＝水平）
static func _prism(st: SurfaceTool, q: Array, yb: float, yt: float, yt2 := NAN) -> void:
	var B := []
	var T := []
	var yb2 := yt if is_nan(yt2) else yt2
	for i in 4:
		var p: Vector2 = q[i]
		B.append(Vector3(p.x, yb, p.y))
		T.append(Vector3(p.x, yt if (i == 0 or i == 3) else yb2, p.y))
	_quad(st, T[0], T[1], T[2], T[3])
	# 立面（蹴上・側面）は踏面より暗く：目地の汚れ・日陰——遠くから「段」のリズムが読めるように（r3）
	var top_c := _vc
	_vc = Color(top_c.r * RISER_TONE, top_c.g * RISER_TONE, top_c.b * RISER_TONE)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, B[i], B[j], T[j], T[i])
	_vc = top_c


static func build(v: Node3D, cl: PackedVector2Array, H: PackedFloat32Array) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P10 R6b pilot")
	var st := steps(cl, H)
	# 石段＋袖石（一個網格；無碰撞＝D7 斜坡碰撞）
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61007
	var hw := STEP_W * 0.5
	var prev_top := NAN
	for i in st.size():
		var a: Dictionary = st[i]
		var kind := String(a["kind"])
		var k0 := int(a["k0"])
		var k1 := int(a["k1"])
		var y0 := float(a["y0"])
		var y1 := float(a["y1"])
		var ybot := minf(H[k0], H[k1]) - 0.45
		var rise := (y0 - prev_top) if not is_nan(prev_top) else 0.15
		prev_top = y1
		# 奥行の行：step＝1 行、long／landing／slab＝0.45–0.7 m ごとの石畳
		var rows := 1
		if kind != "step":
			rows = maxi(1, int(round((k1 - k0) * 0.05 / rng.randf_range(0.45, 0.7))))
		var kr := [k0]
		for r in range(1, rows):
			kr.append(clampi(k0 + int(round((k1 - k0) * float(r) / rows + rng.randf_range(-1.5, 1.5))), int(kr[r - 1]) + 4, k1 - 4))
		kr.append(k1)
		for r in rows:
			var ka := int(kr[r])
			var kb := int(kr[r + 1])
			var ya := lerpf(y0, y1, float(ka - k0) / maxf(k1 - k0, 1))
			var yb := lerpf(y0, y1, float(kb - k0) / maxf(k1 - k0, 1))
			# 横の石：2–3 枚、幅不揃い（目地 1.2 cm）；少し沈んだ・傾いた石
			# 1 段＝1 枚石が多い（55 %）、2 枚（35 %）は継ぎ目 0.3–0.7 のどこか、3 枚（10 %）；踊り場は大きめの敷石を互い違い
			var rr := rng.randf()
			var ns := 1 if rr < 0.55 else (2 if rr < 0.9 else 3)
			if kind != "step":
				ns = 2 + (r % 2) + (1 if rng.randf() < 0.3 else 0)
			var cuts := [-hw]
			if ns == 2:
				cuts.append(-hw + STEP_W * rng.randf_range(0.3, 0.7))
			elif ns >= 3:
				var c1 := rng.randf_range(0.22, 0.42)
				cuts.append(-hw + STEP_W * c1)
				cuts.append(-hw + STEP_W * rng.randf_range(c1 + 0.2, 0.8))
			cuts.append(hw)
			for j in cuts.size() - 1:
				var u0 := float(cuts[j]) + (0.006 if j > 0 else 0.0)
				var u1 := float(cuts[j + 1]) - (0.006 if j < cuts.size() - 2 else 0.0)
				var edge := j == 0 or j == cuts.size() - 2
				var base := _stone_tone(rng, edge)
				if absf((u0 + u1) * 0.5) < 0.5:
					base = _mul(base, 1.05)                          # 真ん中＝人が踏む道筋（摩耗で明るい）
				var dy := rng.randf_range(-0.006, 0.006)
				var tilt := rng.randf_range(0.0, 0.009)              # 鼻先側が下がる（摩耗）
				_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
				var nose := Vector2.ZERO
				if r == 0:
					var nb0 := rng.randf_range(0.0, 0.025)   # 前へだけ（張り出し）：後ろへ引くと前の段との間に溝ができる
					nose = Vector2(maxf(0.0, nb0 + rng.randf_range(-0.012, 0.012)), maxf(0.0, nb0 + rng.randf_range(-0.012, 0.012)))
				_stone(sm, cl, ka, kb, u0, u1, ya + dy - tilt, yb + dy, ybot, r == 0, rise if r == 0 else 0.0, base, 0.0 if r == 0 else 0.012, nose, rng.randf_range(0.025, 0.06))
				# ひび：15 % の石に斜めの細い暗線（踏面＋1 mm）
				if rng.randf() < 0.15 and u1 - u0 > 0.4:
					var tc := tangent(cl, ka)
					var nc := Vector2(-tc.y, tc.x)
					var dep := (kb - ka) * 0.05
					var ua := lerpf(u0, u1, rng.randf_range(0.2, 0.8))
					var ub := ua + rng.randf_range(-0.25, 0.25)
					var pa2 := cl[ka] + tc * (0.06 if r == 0 else 0.02) + nc * ua
					var pb2 := cl[ka] + tc * (dep - 0.03) + nc * ub
					var side := (pb2 - pa2).normalized()
					var wv := Vector2(-side.y, side.x) * 0.005
					var yc := lerpf(ya, yb, 0.5) + dy + 0.001
					_vc = _mul(base, 0.35)
					_quad(sm, Vector3(pa2.x - wv.x, yc, pa2.y - wv.y), Vector3(pb2.x - wv.x, yc, pb2.y - wv.y), Vector3(pb2.x + wv.x, yc, pb2.y + wv.y), Vector3(pa2.x + wv.x, yc, pa2.y + wv.y))
			# 苔：端の踏石の外側に不揃いの帯（0.06–0.22 m、踏面＋2 mm）
			for sd: float in [-1.0, 1.0]:
				if rng.randf() < 0.6:
					var mw := rng.randf_range(0.05, 0.18)
					var ta2 := tangent(cl, ka)
					var tb2 := tangent(cl, kb)
					var na2 := Vector2(-ta2.y, ta2.x)
					var nb2 := Vector2(-tb2.y, tb2.x)
					var ua := hw * sd
					var ub := (hw - mw) * sd
					var f0 := cl[ka] + ta2 * (0.04 if r == 0 else 0.015)
					var f1 := cl[kb]
					var mq := [f0 + na2 * minf(ua, ub), f1 + nb2 * minf(ua, ub), f1 + nb2 * maxf(ua, ub), f0 + na2 * maxf(ua, ub)]
					var mt := rng.randf_range(0.8, 1.1)
					_vc = Color(mt * 0.36, mt * 0.46, mt * 0.22)   # 日陰の苔（緑、r5 の黄土色は日向で茶色に見えた）
					_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
					_quad(sm, Vector3(mq[0].x, ya + 0.002, mq[0].y), Vector3(mq[1].x, yb + 0.002, mq[1].y), Vector3(mq[2].x, yb + 0.002, mq[2].y), Vector3(mq[3].x, ya + 0.002, mq[3].y))
	# 袖石：1–3 段の短い石（段の鼻先に沿って傾く、踏面より 3–11 cm 上）、幅 0.18–0.30・横ずれ ±3 cm、15 % 欠け、上面は黄緑の苔（参考：上色見熊野座神社）
	var ci := 0
	var curb_up_prev := {}
	while ci < st.size():
		var a: Dictionary = st[ci]
		var cj := ci
		if String(a["kind"]) != "landing":
			cj = mini(ci + rng.randi_range(1, 3), st.size()) - 1
			for q in range(ci + 1, cj + 1):
				if String(st[q]["kind"]) == "landing":
					cj = q - 1
					break
		var b: Dictionary = st[cj]
		var ka2 := int(a["k0"])
		var kb2 := int(b["k1"])
		var run := maxf((kb2 - ka2) * 0.05, 0.05)
		for sd: float in [-1.0, 1.0]:
			if String(a["kind"]) != "landing" and rng.randf() < 0.20:
				continue
			var up := clampf(float(curb_up_prev.get(sd, 0.045)) + rng.randf_range(-0.02, 0.02), 0.02, 0.07)   # 低い袖石（前の石の高さに続ける）
			curb_up_prev[sd] = up
			var Y0 := float(a["y0"]) + up
			var slope := (float(b["y1"]) - float(a["y0"])) / run
			for q in range(ci + 1, cj + 1):
				var dq := (int(st[q]["k0"]) - ka2) * 0.05
				if dq > 0.01:
					slope = maxf(slope, (float(st[q]["y0"]) + 0.02 - Y0) / dq)
			var Y1 := maxf(Y0 + slope * run, float(b["y1"]) + 0.02)
			var yb2 := INF
			for k in range(ka2, kb2 + 1):
				yb2 = minf(yb2, H[k])
			yb2 -= 0.45
			var t0 := tangent(cl, ka2)
			var t1 := tangent(cl, kb2)
			var n0 := Vector2(-t0.y, t0.x)
			var n1 := Vector2(-t1.y, t1.x)
			var p0 := cl[ka2]
			var p1 := cl[kb2] + t1 * 0.012
			var jit := rng.randf_range(-0.03, 0.03)
			var ia: float = (hw + jit * 0.5) * sd
			var ib: float = (hw + jit + rng.randf_range(0.16, 0.24)) * sd
			var q := [p0 + n0 * minf(ia, ib), p1 + n1 * minf(ia, ib), p1 + n1 * maxf(ia, ib), p0 + n0 * maxf(ia, ib)]
			var mt := rng.randf_range(0.75, 1.0)
			_vc = Color(mt * 0.42, mt * 0.50, mt * 0.26) if rng.randf() < 0.6 else Color(mt * 0.62, mt * 0.65, mt * 0.56)   # 苔（暗い黄緑）／苔の薄い灰の石
			_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
			_prism(sm, q, yb2, Y0, Y1)
		ci = cj + 1
	_uvo = Vector2.ZERO
	sm.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "StoneSteps"
	mi.mesh = sm.commit()
	var stm := (load(STONE) as StandardMaterial3D).duplicate() as StandardMaterial3D
	stm.albedo_color = STONE_ALBEDO   # ROUND 2：風化した花崗岩 0.80（r3 0.72 は暗い一様面）；立面は RISER_TONE、下端は目地の汚れ
	stm.resource_name = "P10_SandoStone"
	mi.material_override = stm
	mi.visibility_range_end = 260.0
	mi.set_meta("steps", st.size())
	root.add_child(mi)
	# 斜坡碰撞帶（ConcavePolygonShape3D）：寬＝石段＋袖石
	var rp := ramp_points(st, H)
	var faces := PackedVector3Array()
	var half := STEP_W * 0.5 + CURB_W
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		var ta := tangent(cl, ka)
		var tb := tangent(cl, kb)
		var na := Vector2(-ta.y, ta.x) * half
		var nb := Vector2(-tb.y, tb.x) * half
		var ya := float(rp[i][1])
		var yb2 := float(rp[i + 1][1])
		var a0 := Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y)
		var a1 := Vector3(cl[ka].x + na.x, ya, cl[ka].y + na.y)
		var b0 := Vector3(cl[kb].x - nb.x, yb2, cl[kb].y - nb.y)
		var b1 := Vector3(cl[kb].x + nb.x, yb2, cl[kb].y + nb.y)
		faces.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	var shp := ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	shp.backface_collision = true
	var rb := StaticBody3D.new()
	rb.name = "RampCollision"
	var rcs := CollisionShape3D.new()
	rcs.name = "Ramp"
	rcs.shape = shp
	rb.add_child(rcs)
	root.add_child(rb)
	# 參道 ribbon 挖洞範圍（ribbon 自己的沿路 s＝UV.y）：石段首尾投影到 ribbon 頂點
	root.set("ribbon_path", NodePath(RIBBON))
	root.set("ribbon_params", RIBBON_EDGE)
	root.set("cut_s", ribbon_cut_s(cl, st))
	root.set("cut_hw", SANDO_HW + 0.1)   # ROUND 2：石段の範囲は參道 ribbon を全幅で隠す（幅 2.4 m の石段の両脇に土の帯が残らない）
	# 一の鳥居（P5 Hero 實例）
	var tor := (load(TORII_SCN) as PackedScene).instantiate() as Node3D
	tor.name = "IchiNoTorii"
	tor.transform = torii1_xf(cl, H)
	tor.set_meta("asset", "sando_torii（P5 Hero 重用）")
	root.add_child(tor)
	# 柱台ガード：P5 鳥居の柱台碰撞（0.72 角・高 0.58）は膠囊が乗り上げられる → 斜めに歩くと柱台の縁に 0.5 m 浮いて引っかかる
	# （19-point walk で實測 dy 0.50–0.58）。資產は觸らず、柱台を包む円柱（r 0.52・地面〜1.55 m）を overlay 側に足して乗れなくする。
	var gd := StaticBody3D.new()
	gd.name = "IchiNoToriiGuard"
	gd.transform = tor.transform
	for sd: float in [-1.0, 1.0]:
		var gcs := CollisionShape3D.new()
		gcs.name = "Guard_%s" % ("L" if sd < 0.0 else "R")
		var cyl := CylinderShape3D.new()
		cyl.radius = GUARD_R
		cyl.height = GUARD_H
		gcs.shape = cyl
		gcs.position = Vector3(2.25 * sd, -0.45 + GUARD_H * 0.5, 0.0)
		gd.add_child(gcs)
	root.add_child(gd)
	# 石燈籠
	var lg := Node3D.new()
	lg.name = "Lanterns"
	root.add_child(lg)
	var sp := v.get_world_3d().direct_space_state
	var li := 0
	for ls in lantern_specs(cl, H, st, sp):
		var p: Vector2 = ls["p"]
		var g2 := lantern_ground(sp, p)
		var gy := float(g2[1]) + PLINTH_UP   # 基壇頂（水平）＝四角最高＋0.06
		# 基壇：0.9 × 0.9 石、底＝四角最低 −0.15（斜面に据える：坂側は埋まり、谷側は見える）
		var pst := SurfaceTool.new()
		pst.begin(Mesh.PRIMITIVE_TRIANGLES)
		_vc = Color(0.86, 0.86, 0.82)
		var hp := PLINTH * 0.5
		_prism(pst, [p + Vector2(-hp, -hp), p + Vector2(-hp, hp), p + Vector2(hp, hp), p + Vector2(hp, -hp)], float(g2[0]) - 0.15, gy)
		pst.generate_tangents()
		var pmi := MeshInstance3D.new()
		pmi.name = "Plinth_%02d" % li
		pmi.mesh = pst.commit()
		pmi.material_override = stm
		pmi.visibility_range_end = 160.0
		lg.add_child(pmi)
		var ln := Node3D.new()
		ln.name = "Toro_%02d" % li
		li += 1
		ln.transform = Transform3D(Basis(Vector3.UP, float(ls["yaw"])), Vector3(p.x, gy, p.y))   # 坐在基壇頂
		for lod in 2:
			var m := MeshInstance3D.new()
			m.name = "LOD%d" % lod
			m.mesh = load(LANTERN if lod == 0 else LANTERN_L1)
			m.visibility_range_begin = 0.0 if lod == 0 else 45.0
			m.visibility_range_end = 45.0 if lod == 0 else 160.0
			ln.add_child(m)
		var body := StaticBody3D.new()
		body.name = "Collision"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.62, 1.9, 0.62)
		cs.shape = bs
		cs.position = Vector3(0, 0.95, 0)
		body.add_child(cs)
		ln.add_child(body)
		ln.set_meta("s", ls["s"])
		lg.add_child(ln)
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
