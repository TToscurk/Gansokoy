extends RefCounted
## P13 Wave 4 — 神社參道 代表区間の石段 試作（overlay `SandoPilotW4P13`）。使用者 2026-10-13「P13 WAVE 4」。
## 診断（tools/p13/diag_w4_*.gd、r8＝正式 ShrineApproachP10、evidence/diag_r8_*.log）：
##   · 蹴上 平均 18.0 cm・標準偏差 0.7 cm（変動係数 3.8 %）、98 % の段が平均の ±10 % 以内＝節拍器
##     （地形に沿う貪欲法が「蹴上が 0.18 に最も近い踏面長」を毎段選ぶため）。
##   · 踏面は全段 水平の長方形の「板」・55 % が幅 2.4 m の一枚石・両端は常に ±1.2 m の直線・袖石は規格の押し出し形。
##   · 踏面頂が地形より高い（墊高）：中心 平均 0.39 m・踊り場の手前で最大 1.0 m。端の外側面の露出 ≤ 0.30 m は 71 段、0.30–0.60 m は 63 段、
##     > 0.60 m は 51 段（全 185 段）＝垂直の石塊の側面が外に露出し「坡面に置いた帯」に見える（視覚審査も同じ指摘）。
##   · 浮空なし（石の底は全 1,110 点で地形より 17.5–64.3 cm 下）／地形が踏面を突き破る点が右端で 3–8 %（最大 +9 cm）。
## 方針（visual-only・碰撞不変）：
##   ① 踏面：段数・蹴上・踏面長に実際の幅を持たせ（斜坡碰撞の許容帯の中で）、各段を 2–4 枚の不規則な石（継ぎ目が段をまたいで通らない・
##      石ごとに前縁位置／回転／高さ／傾きが違う）に。r8 の風化の細部〔継ぎ目の苔・踏面奥の落葉・端の苔〕は引き継ぐ。
##   ② 側面：袖石を規格品でなく不規則な笠石に、露出が大きい所は笠石の下へ小さめの石垣（乱積み・段ごとに少し張り出す）を地形まで降ろす。
##   ③ 接地：石垣の根元に土の裾（W4Soil）。地形シェーダーと同じ材質〔world XZ 投影〕・周囲の地形と同じウェイト〔trodden 0.85〕で硬い接地線を消す。
##   試作区間＝最初の段〜2 つ目の踊り場（下から 2 flight＋踊り場 2）。区間外は r8 のまま。斜坡碰撞・ライト・鳥居は触れない。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const NODE_NAME := "SandoPilotW4P13"
const OUTPUT := "res://maps/village_v2/gen/sando_pilot_w4_p13.scn"
const SCRIPT := "res://maps/village_v2/scripts_p13/sando_pilot_w4.gd"
const ART_REVISION := "P13 W4 r10"
const SEED := 130401
# 踏面長（k＝0.05 m 単位）0.20–0.35 m とその重み。r8 は 0.25–0.45 で「蹴上 0.18 に最も近い長さ」だけを選んでいた。
# 0.40 m の踏面は不可：斜坡碰撞（r8 の短い踏面から作られた折れ線）より 15 cm 以上高くなり、足が石に沈む（r8 実測 最大 11.7 cm → 試作 r8版 17.9 cm）
const D_K := [4, 5, 6, 7]
const D_W := [0.12, 0.28, 0.36, 0.24]
const R_MIN := 0.11
const R_MAX := 0.25
const R_FIRST_MIN := 0.05
const DEV_PAD := 0.02                         # 斜坡碰撞と踏面頂の差 ≤ 半蹴上 + これ（既存 SWALK W1 は +0.03。見える面の細部〔傾き・高さのゆらぎ〕の分を残すため 1 cm 厳しく）
const DEV_CAP := 0.12                         # 差の絶対上限（r8 の実測 最大 11.3 cm〔計画〕／11.7 cm〔見える面〕と同じ水準）
const E_SIGMA := 0.010
const EDGE_LO := 1.02                          # 踏面端の |u|（r8 は 1.2 一定）。笠石を厚くした分だけ石段の幅を 2.0–2.3 m に（斜坡碰撞 ±1.44 m は不変）
const EDGE_HI := 1.16
const W_TOP := [0.24, 0.34]                    # 笠石の幅（r8 の袖石 0.16–0.24 は規格のレールに見えた）
const BATTER := 0.03                           # 石垣の段ごとの張り出し
const COURSE := 0.30                           # 石垣 1 段の目安の高さ
const BURY := 0.28
const U_TERR := 1.5                            # 外側地形を測る横位置
const U_FAR := 1.95                            # もう一点（土の裾の外縁まで）

static var _vc := Color.WHITE
static var _uvo := Vector2.ZERO
static var uv_k := 0.9
## 検証用：build が置いた笠石／石垣ブロックの記録 {k, sd, u, p, ybot, top, off}（verify_w4_pilot.gd が地形と突き合わせる）
static var diag: Array = []
static var soil_n := 0
static var _cur_base := false      # 今置くブロックが地面に接する最下段か（diag の浮空判定は最下段だけ）


# ───────────────────────────── 区間・斜坡 ─────────────────────────────

## 試作区間＝最初の要素〜2 つ目の踊り場（st の index 範囲、両端含む）
static func pilot_indices(st: Array) -> Vector2i:
	var lands := []
	for i in st.size():
		if String(st[i]["kind"]) == "landing":
			lands.append(i)
	return Vector2i(0, int(lands[1]))


static func pilot_k_range(st: Array) -> Vector2i:
	var r := pilot_indices(st)
	return Vector2i(int(st[r.x]["k0"]), int(st[r.y]["k1"]))


## 斜坡碰撞の中心線高さを k ごとに展開（SA.ramp_points の折れ線）
static func ramp_dense(rp: Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(NAN)
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		for k in range(maxi(ka, 0), mini(kb, n - 1) + 1):
			out[k] = lerpf(float(rp[i][1]), float(rp[i + 1][1]), float(k - ka) / float(kb - ka))
	return out


# ───────────────────────────── 計画 ─────────────────────────────

static func _sample_len(rng: RandomNumberGenerator, allowed: Array, prev: int) -> int:
	var ws := []
	var tot := 0.0
	for l in allowed:
		var idx := D_K.find(int(l))
		var w: float = float(D_W[idx])
		if prev > 0:
			w *= 1.0 + 0.9 * exp(-pow(float(int(l) - prev), 2.0) / 1.5)    # 前の段に似た長さへ少し引かれる＝局所的なまとまり
		ws.append(w)
		tot += w
	var x := rng.randf() * tot
	for i in allowed.size():
		x -= float(ws[i])
		if x <= 0.0:
			return int(allowed[i])
	return int(allowed[allowed.size() - 1])


## 斜坡碰撞と踏面頂の差の許容（蹴上 riser に対して）。計画（plan_flight）と gate（verify_w4_pilot）の共通の定義
static func dev_limit(riser: float) -> float:
	return minf(0.5 * riser + DEV_PAD, DEV_CAP)


## 1 つの flight（ka〜kb、入口の高さ y_in、出口＝踊り場の高さ y_out）を、変化のある踏面列に計画し直す。失敗時は []
static func plan_flight(H: PackedFloat32Array, rd: PackedFloat32Array, ka: int, kb: int, y_in: float, y_out: float, first: bool, rng: RandomNumberGenerator) -> Array:
	for attempt in 300:
		var cells := []
		var k := ka
		var y_prev := y_in
		var e_prev := 0.0
		var prev_l := 0
		var fail := false
		while k < kb:
			var rem := kb - k
			var allowed := []
			for l in D_K:
				if rem - int(l) == 0 or rem - int(l) >= int(D_K[0]):
					allowed.append(int(l))
			if allowed.is_empty():
				fail = true
				break
			var best := {}
			var best_score := INF
			for trial in 14:
				var l := _sample_len(rng, allowed, prev_l)
				var km := k + l / 2
				var yc := SA._hmax(H, k, k + l) + 0.02
				var w := rd[km]
				if is_nan(w):
					w = yc + 0.09
				var e := 0.35 * e_prev + rng.randfn(0.0, E_SIGMA)
				var roll := rng.randf()
				if roll < 0.07:
					e += rng.randf_range(0.025, 0.045)       # 大きな石（高い）
				elif roll < 0.13:
					e -= rng.randf_range(0.02, 0.035)        # 沈んだ・磨り減った石（低い）
				e = clampf(e, -0.06, 0.06)
				var rmin := R_FIRST_MIN if (first and cells.is_empty()) else R_MIN
				var y := clampf(maxf(w + e, yc), y_prev + rmin, y_prev + R_MAX)
				var score := 0.0
				if y < yc - 1e-4:
					score += 1.0 + (yc - y)
				var dev := 0.0
				for kk in range(k, k + l + 1):
					var rw := rd[kk]
					if not is_nan(rw):
						dev = maxf(dev, absf(rw - y))
				score += maxf(dev - dev_limit(y - y_prev), 0.0)
				if rem - l == 0:
					var re := y_out - y
					if re < R_MIN:
						score += 0.5 + (R_MIN - re)
					elif re > R_MAX:
						score += 0.5 + (re - R_MAX)
				if score < best_score:
					best_score = score
					best = {"l": l, "y": y, "e": e}
				if score <= 0.0:
					break
			if best_score > 0.0:
				fail = true
				break
			var bl := int(best["l"])
			var by := snappedf(float(best["y"]), 0.001)
			cells.append({"k0": k, "k1": k + bl, "y0": by, "y1": by, "kind": "step"})
			e_prev = float(best["e"])
			prev_l = bl
			y_prev = by
			k += bl
		if not fail:
			return cells
	return []


## 試作区間の新しい計画：[ {k0,k1,y0,y1,kind,flight} ]（踊り場は r8 のまま）
static func replan(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, rp: Array, seed := SEED) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rd := ramp_dense(rp, cl.size())
	var rg := pilot_indices(st)
	var out := []
	var i := rg.x
	var fl := 0
	while i <= rg.y:
		var a: Dictionary = st[i]
		if String(a["kind"]) != "step":
			var b: Dictionary = a.duplicate()
			b["flight"] = -1
			out.append(b)
			i += 1
			continue
		var j := i
		while j + 1 <= rg.y and String(st[j + 1]["kind"]) == "step":
			j += 1
		var y_in := H[int(a["k0"])] if i == rg.x else float(st[i - 1]["y1"])
		var y_out := float(st[j + 1]["y0"])
		var cells := plan_flight(H, rd, int(a["k0"]), int(st[j]["k1"]), y_in, y_out, i == rg.x, rng)
		if cells.is_empty():
			push_warning("W4 plan_flight 失敗：flight %d は r8 の計画を使う" % fl)
			for q in range(i, j + 1):
				var b2: Dictionary = (st[q] as Dictionary).duplicate()
				b2["flight"] = fl
				out.append(b2)
		else:
			for c: Dictionary in cells:
				c["flight"] = fl
				out.append(c)
		fl += 1
		i = j + 1
	return out


# ───────────────────────────── メッシュ基本 ─────────────────────────────

static func _uv(v: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.6:
		return Vector2(v.x, v.z) * uv_k + _uvo
	return Vector2(v.x + v.z, v.y) * uv_k + _uvo


static func _mul(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


## 外向き（center から離れる側）が表になる三角形。Godot の表＝時計回り＝法線 (c−a)×(b−a)。ca／cb／cc 省略時は _vc
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, ca := Color(), cb := Color(), cc := Color()) -> void:
	var n := (c - a).cross(b - a)
	if n.length() < 1e-10:
		return
	var use_c := ca != Color()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		n = -n
	n = n.normalized()
	var vs := [a, b, c]
	var cs := [ca, cb, cc]
	for i in 3:
		st.set_color(cs[i] if use_c else _vc)
		st.set_normal(n)
		st.set_uv(_uv(vs[i], n))
		st.add_vertex(vs[i])


static func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var vs := [a, b, c]
	if (c - a).cross(b - a).y < 0.0:
		vs = [a, c, b]
	var n: Vector3 = (vs[2] - vs[0]).cross(vs[1] - vs[0])
	if n.length() < 1e-10:
		return
	n = n.normalized()
	for v: Vector3 in vs:
		st.set_color(_vc)
		st.set_normal(n)
		st.set_uv(_uv(v, n))
		st.add_vertex(v)


static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3, ca := Color(), cb := Color(), cc := Color(), cd := Color()) -> void:
	_tri_out(st, a, b, c, center, ca, cb, cc)
	_tri_out(st, a, c, d, center, ca, cc, cd)


## 平らな装飾面（苔・落葉・目地）：4 隅の高さは top_fn（uv→高さ）+ lift。r8 と同じく踏面の +数 mm に貼る
static func _decal(st: SurfaceTool, W: Callable, top_fn: Callable, q4: Array, col: Color, lift: float) -> void:
	var p3: Array = []
	for q: Vector2 in q4:
		var w2: Vector2 = W.call(q)
		p3.append(Vector3(w2.x, float(top_fn.call(q)) + lift, w2.y))
	_vc = col
	_tri_up(st, p3[0], p3[1], p3[2])
	_tri_up(st, p3[0], p3[2], p3[3])


## 不規則な石 1 個。P＝plan 外形（xz）、ht＝外形の各点の頂面高さ、hc＝頂の中心高、ybot＝底、r＝面取り幅、base＝基調色、
## fronts＝前縁の辺の数（P[0] から始まる連続 fronts 辺は鼻先の明るい面取り）。
## 側面の色：面取り下端 0.82 → 0.28 m 下で 0.66 → 底 0.45（r8 の「目地の汚れ」程度。以前の 0.40 まで全高グラデーションは真っ黒になった）
static func stone(st: SurfaceTool, P: Array, ht: Array, hc: float, ybot: float, r: float, base: Color, fronts := 0, top_col := Color(-1.0, 0.0, 0.0, 1.0)) -> void:
	var n := P.size()
	var c := Vector2.ZERO
	for p: Vector2 in P:
		c += p
	c /= float(n)
	var cen3 := Vector3(c.x, hc, c.y)
	var low := Vector3(c.x, ybot - 0.5, c.y)
	var Pin: Array = []
	var Pe: Array = []
	var Pm: Array = []
	var Pb: Array = []
	for i in n:
		var d: Vector2 = c - (P[i] as Vector2)
		var dl := maxf(d.length(), 1e-5)
		var inset := minf(r, dl * 0.45)
		var pin: Vector2 = (P[i] as Vector2) + d / dl * inset
		var pb: Vector2 = (P[i] as Vector2) + d / dl * 0.03
		var ye := float(ht[i]) - inset * 0.75
		var ym := maxf(ybot + 0.01, ye - 0.28)
		var t := clampf((ye - ym) / maxf(ye - ybot, 1e-4), 0.0, 1.0)
		var pm: Vector2 = (P[i] as Vector2).lerp(pb, t)
		Pin.append(Vector3(pin.x, float(ht[i]), pin.y))
		Pe.append(Vector3((P[i] as Vector2).x, ye, (P[i] as Vector2).y))
		Pm.append(Vector3(pm.x, ym, pm.y))
		Pb.append(Vector3(pb.x, ybot, pb.y))
	var topc := base if top_col.r < 0.0 else top_col       # 苔色は上面〔と面取り〕だけ。側面は石の色
	_vc = topc
	for i in n:
		_tri_up(st, cen3, Pin[i], Pin[(i + 1) % n])
	for i in n:
		var j := (i + 1) % n
		var k := 1.10 if i < fronts else 0.97
		var cb := _mul(topc, k)
		var cw := _mul(base, 0.82)
		_quad_out(st, Pin[i], Pin[j], Pe[j], Pe[i], low, cb, cb, cw, cw)
		var cw0 := _mul(base, 0.82 if i >= fronts else 0.88)
		var cm := _mul(base, 0.66)
		var cd := _mul(base, 0.45)
		_quad_out(st, Pe[i], Pe[j], Pm[j], Pm[i], low, cw0, cw0, cm, cm)
		_quad_out(st, Pm[i], Pm[j], Pb[j], Pb[i], low, cm, cm, cd, cd)
	# 底（地中だが、側面から覗く隙間に備えて閉じる）
	var cb3 := Vector3(c.x, ybot, c.y)
	_vc = _mul(base, 0.35)
	for i in n:
		_tri_out(st, cb3, Pb[i], Pb[(i + 1) % n], Vector3(c.x, ybot + 5.0, c.y))


# ───────────────────────────── 踏石の列 ─────────────────────────────

static func _cuts(rng: RandomNumberGenerator, uL: float, uR: float, prev: Array) -> Array:
	for attempt in 40:
		var rr := rng.randf()
		var n := 2 if rr < 0.30 else (3 if rr < 0.78 else 4)
		var cuts := [uL]
		var u := uL
		var ok := true
		for j in range(1, n):
			var left := n - j
			var w_min := 0.45
			var lo := u + w_min
			var hi := uR - w_min * float(left)
			if hi < lo:
				ok = false
				break
			var mean := u + (uR - u) / float(left + 1)
			u = clampf(mean + rng.randf_range(-0.28, 0.28), lo, minf(hi, u + 1.3))
			cuts.append(u)
		if not ok:
			continue
		cuts.append(uR)
		if float(cuts[cuts.size() - 1]) - float(cuts[cuts.size() - 2]) > 1.3 or float(cuts[1]) - float(cuts[0]) > 1.3:
			continue
		var clash := false
		for c in range(1, cuts.size() - 1):
			for pc in prev:
				if absf(float(cuts[c]) - float(pc)) < 0.17:   # 前の段の継ぎ目と重ならない（目地の通りを作らない）
					clash = true
		if clash:
			continue
		return cuts
	return [uL, (uL + uR) * 0.5, uR]


static func _tone(rng: RandomNumberGenerator, edge: bool) -> Color:
	return SA._stone_tone(rng, edge)


## 踏面 1 段：継ぎ目の通らない 2–4 枚の不規則な石＋土の床＋風化の細部。state＝{uL,uR,cuts}（区間連続のゆらぎ）。a に eL／eR（踏面端 |u|）を書き戻す
static func tread(sm: SurfaceTool, cl: PackedVector2Array, a: Dictionary, y_prev: float, H: PackedFloat32Array, state: Dictionary, rng: RandomNumberGenerator) -> void:
	var k0 := int(a["k0"])
	var k1 := int(a["k1"])
	var y := float(a["y0"])
	var d := (k1 - k0) * 0.05
	var km := (k0 + k1) / 2
	var tg := SA.tangent(cl, km)
	var P0 := cl[k0]
	var uL := clampf(float(state["uL"]) + rng.randf_range(-0.05, 0.05), -EDGE_HI, -EDGE_LO)
	var uR := clampf(float(state["uR"]) + rng.randf_range(-0.05, 0.05), EDGE_LO, EDGE_HI)
	state["uL"] = uL
	state["uR"] = uR
	a["eL"] = -uL
	a["eR"] = uR
	var cuts := _cuts(rng, uL, uR, state["cuts"])
	state["cuts"] = cuts.slice(1, cuts.size() - 1)
	var nose := float(a.get("nose", 0.0))
	var v_end := d - 0.01                                # 落葉・苔はこの手前まで（その先は次の段の石の下になりうる）
	var hmin := INF
	for k in range(k0, k1 + 1):
		hmin = minf(hmin, H[k])
	var ybot := minf(y_prev - 0.15, hmin - 0.30)
	var yaw := rng.randf_range(-0.02, 0.02)       # 段全体の傾き（rad）：石が据え直されて平行でない
	var tgr := tg.rotated(yaw)
	var nrr := Vector2(-tgr.y, tgr.x)
	var back := d + 0.10 + rng.randf_range(0.0, 0.02)     # 次の段の石の下へ 10 cm 潜る（前縁が奥へ下がっても隙間を作らない）
	var W := func(uv: Vector2) -> Vector2:
		return P0 + tgr * uv.y + nrr * uv.x
	var min_top := INF       # この段の石の頂の最低〔土の床はその 1 cm 下に置く＝目地の底が浅く、石を覆わない〕
	var infos: Array = []
	var bow := rng.randf_range(0.02, 0.05) if rng.randf() < 0.4 else 0.0      # 段の前縁が弧を描く（中央が前、端が後ろ。全幅の平均が 0 になるよう 0.667 bow を差し引く）
	var half_w := maxf(absf(uL), absf(uR))
	for j in cuts.size() - 1:
		var u0 := float(cuts[j])
		var u1 := float(cuts[j + 1])
		var bow0 := bow * (1.0 - pow(u0 / half_w, 2.0))
		var bow1 := bow * (1.0 - pow(u1 / half_w, 2.0))
		var nj := nose + rng.randf_range(-0.025, 0.03)        # 石ごとに前縁が前後する（蹴上の線が波打つ。平均 +0.25 cm）
		var gap := rng.randf_range(0.0015, 0.003)       # 目地＝面取りの浅い V 溝だけ（隙間を影が溜まる幅にしない）
		var raw := [Vector2(u0, -nj - (bow0 - 0.667 * bow) - rng.randf_range(-0.01, 0.01)), Vector2(u1, -nj - (bow1 - 0.667 * bow) - rng.randf_range(-0.01, 0.01)), Vector2(u1, back + rng.randf_range(-0.01, 0.015)), Vector2(u0, back + rng.randf_range(-0.01, 0.015))]
		var c2 := Vector2.ZERO
		for q: Vector2 in raw:
			c2 += q
		c2 /= 4.0
		var yaw_j := rng.randf_range(-0.06, 0.06)             # 石ごとの回転
		var P2 := []
		for q: Vector2 in raw:
			P2.append(c2 + ((q - c2) - (q - c2).normalized() * gap).rotated(yaw_j))
		# 不整形の足し頂点：前縁の中ほどが前へ膨らむ（丸みのある鼻先）／側面が外へ膨らむ／前の角の欠け（r8 の「鼻先の角の欠け」を形そのものに）
		var pf0: Vector2 = P2[0]
		var pf1: Vector2 = P2[1]
		var pb1: Vector2 = P2[2]
		var pb0: Vector2 = P2[3]
		var fl_start := pf0
		var fr_end := pf1
		var tail: Array = []
		var fr_side: Array = []
		if rng.randf() < 0.28 and (pf1 - pf0).length() > 0.5:
			var cs0 := rng.randf_range(0.04, 0.10)
			fl_start = pf0 + (pf1 - pf0).normalized() * cs0
			tail.append(pf0 + (pb0 - pf0).normalized() * cs0)
		if rng.randf() < 0.28 and (pf1 - pf0).length() > 0.5:
			var cs1 := rng.randf_range(0.04, 0.10)
			fr_end = pf1 - (pf1 - pf0).normalized() * cs1
			fr_side.append(pf1 + (pb1 - pf1).normalized() * cs1)
		var poly: Array = [fl_start]
		var fronts := 1
		if rng.randf() < 0.55:
			poly.append((fl_start + fr_end) * 0.5 + Vector2(0.0, -rng.randf_range(0.008, 0.03)))
			fronts = 2
		poly.append(fr_end)
		for q in fr_side:
			poly.append(q)
		var right_start: Vector2 = fr_side[0] if not fr_side.is_empty() else pf1
		if rng.randf() < 0.35:
			poly.append((right_start + pb1) * 0.5 + Vector2(rng.randf_range(0.0, 0.03), 0.0))
		poly.append(pb1)
		poly.append(pb0)
		var left_end: Vector2 = tail[0] if not tail.is_empty() else pf0
		if rng.randf() < 0.35:
			poly.append((pb0 + left_end) * 0.5 + Vector2(-rng.randf_range(0.0, 0.03), 0.0))
		for q in tail:
			poly.append(q)
		var dy := clampf(rng.randfn(0.0, 0.006), -0.012, 0.012)
		var tilt_f := rng.randf_range(0.015, 0.04)        # 前下がり（摩耗）
		var tilt_u := rng.randf_range(-0.02, 0.02)
		var uc := (u0 + u1) * 0.5
		var top_fn := func(q: Vector2) -> float:
			return y + dy - tilt_f * (d - clampf(q.y, 0.0, d)) + tilt_u * (q.x - uc)
		var P: Array = []
		var ht: Array = []
		var s_ht := 0.0
		for q: Vector2 in poly:
			P.append(W.call(q))
			var hh: float = float(top_fn.call(q)) + rng.randf_range(-0.003, 0.003)
			ht.append(hh)
			s_ht += hh
			min_top = minf(min_top, hh)
		var hc := s_ht / float(poly.size()) + rng.randf_range(0.003, 0.010)
		var base := _tone(rng, j == 0 or j == cuts.size() - 2)
		if absf(uc) < 0.5:
			base = _mul(base, 1.05)                      # 人が踏む筋
		_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		stone(sm, P, ht, hc, ybot, rng.randf_range(0.022, 0.04), base, fronts)
		infos.append({"u0": u0, "u1": u1, "top": top_fn, "nj": nj})
	# 土の床（目地・欠けから覗く面）：最も低い石の頂 −1 cm
	_vc = Color(0.34, 0.28, 0.20)
	var bp := [W.call(Vector2(uL, 0.03)), W.call(Vector2(uR, 0.03)), W.call(Vector2(uR, back)), W.call(Vector2(uL, back))]
	var bed: Array = []
	for q: Vector2 in bp:
		bed.append(Vector3(q.x, min_top - 0.01, q.y))
	_tri_up(sm, bed[0], bed[1], bed[2])
	_tri_up(sm, bed[0], bed[2], bed[3])
	# 風化の細部（r8 ROUND 3 の語彙を継ぐ）：踏面奥の落葉・土、継ぎ目の苔、端の苔。石の上面の +数 mm に貼る
	_uvo = Vector2.ZERO
	for j in infos.size():
		var info: Dictionary = infos[j]
		var tf: Callable = info["top"]
		var u0 := float(info["u0"]) + 0.05
		var u1 := float(info["u1"]) - 0.05
		if u1 - u0 > 0.15 and rng.randf() < 0.9:
			var w0 := rng.randf_range(0.03, 0.085)
			var w1 := rng.randf_range(0.03, 0.085)
			var ve := v_end - 0.006
			var lt := rng.randf_range(0.85, 1.1)
			_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
			_decal(sm, W, tf, [Vector2(u0, ve - w0), Vector2(u1, ve - w1), Vector2(u1, ve), Vector2(u0, ve)], Color(0.46 * lt, 0.41 * lt, 0.33 * lt), 0.0035)
		if j == 0 and rng.randf() < 0.6 or j == infos.size() - 1 and rng.randf() < 0.6:
			var sgn := -1.0 if j == 0 else 1.0
			var mw := rng.randf_range(0.05, 0.16)
			var ue := (uL if j == 0 else uR)
			var ua := ue - sgn * 0.045
			var ub := ue - sgn * (0.045 + mw)
			var v0 := 0.02 - float(info["nj"])
			var v1 := v_end - 0.03
			var mt := rng.randf_range(0.8, 1.1)
			_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
			_decal(sm, W, tf, [Vector2(minf(ua, ub), v0), Vector2(maxf(ua, ub), v0), Vector2(maxf(ua, ub), v1), Vector2(minf(ua, ub), v1)], Color(mt * 0.36, mt * 0.46, mt * 0.22), 0.004)
	for j in range(1, infos.size()):
		if rng.randf() < 0.8:
			var cu := float(infos[j]["u0"])
			var jw := rng.randf_range(0.011, 0.016)
			var mt := rng.randf_range(0.8, 1.1)
			var tfl: Callable = infos[j - 1]["top"]
			var tfr: Callable = infos[j]["top"]
			var jfn := func(q: Vector2) -> float:
				return minf(float(tfl.call(q)), float(tfr.call(q))) - 0.016
			var v0 := 0.04 - float(infos[j]["nj"])
			var v1 := v_end - 0.02
			_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
			_decal(sm, W, jfn, [Vector2(cu - jw, v0), Vector2(cu + jw, v0), Vector2(cu + jw, v1), Vector2(cu - jw, v1)],
				Color(0.34 * mt, 0.44 * mt, 0.22 * mt) if rng.randf() < 0.55 else Color(0.30, 0.25, 0.19), 0.0)
	_uvo = Vector2.ZERO


## 踊り場：厚い框石（前縁）＋不規則な敷石（ずらした格子を縮めた多角形）＋土の床。奥行は r8 の計画どおり、幅は袖まで
static func landing(sm: SurfaceTool, cl: PackedVector2Array, a: Dictionary, y_prev: float, H: PackedFloat32Array, state: Dictionary, rng: RandomNumberGenerator) -> void:
	var k0 := int(a["k0"])
	var k1 := int(a["k1"])
	var y := float(a["y0"])
	var d := (k1 - k0) * 0.05
	var tg := SA.tangent(cl, (k0 + k1) / 2)
	var nr := Vector2(-tg.y, tg.x)
	var P0 := cl[k0]
	var uL := clampf(float(state["uL"]) - 0.04, -1.2, -1.08)
	var uR := clampf(float(state["uR"]) + 0.04, 1.08, 1.2)
	a["eL"] = -uL
	a["eR"] = uR
	var hmin := INF
	for k in range(k0, k1 + 1):
		hmin = minf(hmin, H[k])
	var ybot := minf(y_prev - 0.2, hmin - 0.3)
	var W := func(uv: Vector2) -> Vector2:
		return P0 + tg * uv.y + nr * uv.x
	var min_top := y - 0.04
	# 框石：2–3 枚（幅不揃い）、厚み（奥行 v）0.30–0.38、鼻先の丸み大
	var nk := 2 if rng.randf() < 0.45 else 3
	var kc := [uL]
	for j in range(1, nk):
		kc.append(lerpf(uL, uR, float(j) / nk + rng.randf_range(-0.09, 0.09)))
	kc.append(uR)
	var kdepth := rng.randf_range(0.30, 0.38)
	for j in nk:
		var u0 := float(kc[j]) + (0.002 if j > 0 else 0.0)
		var u1 := float(kc[j + 1]) - (0.002 if j < nk - 1 else 0.0)
		var nose := rng.randf_range(0.02, 0.05)
		var f0 := Vector2(u0 + rng.randf_range(-0.02, 0.02) * (0.0 if j == 0 else 1.0), -nose - rng.randf_range(0.0, 0.02))
		var f1 := Vector2(u1 + rng.randf_range(-0.02, 0.02) * (0.0 if j == nk - 1 else 1.0), -nose - rng.randf_range(0.0, 0.02))
		var b1 := Vector2(u1 + rng.randf_range(-0.02, 0.02) * (0.0 if j == nk - 1 else 1.0), kdepth + rng.randf_range(-0.03, 0.03))
		var b0 := Vector2(u0 + rng.randf_range(-0.02, 0.02) * (0.0 if j == 0 else 1.0), kdepth + rng.randf_range(-0.03, 0.03))
		var P := [W.call(f0), W.call(f1), W.call(b1), W.call(b0)]
		var yk := y + rng.randf_range(0.004, 0.016)
		var ht := [yk - 0.01, yk - 0.01, yk, yk]
		min_top = minf(min_top, yk - 0.01)
		_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		stone(sm, P, ht, yk + 0.006, ybot, rng.randf_range(0.03, 0.05), _mul(_tone(rng, false), 0.97), 1)
	# 敷石：框石の奥から終端（次の段の蹴上の下へ 3.5 cm 潜る）まで、列 1–2×幅 3–4 枚、共有する角を ±0.06 m ずらした格子を縮めた多角形
	var v0 := kdepth + 0.03
	var v1 := d + 0.035
	var rows := maxi(1, int(round((v1 - v0) / rng.randf_range(0.62, 0.85))))
	var cols := 3 if rng.randf() < 0.5 else 4
	var grid := []
	for r in rows + 1:
		var rowp := []
		for c in cols + 1:
			var u := lerpf(uL + 0.05, uR - 0.05, float(c) / cols)
			var v := lerpf(v0, v1, float(r) / rows)
			var jit := Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.06, 0.06))
			if c == 0 or c == cols:
				jit.x *= 0.3
			if r == rows:
				jit.y = 0.0
			rowp.append(Vector2(u, v) + jit)
		grid.append(rowp)
	for r in rows:
		for c in cols:
			var q4 := [grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]]
			var cc := Vector2.ZERO
			for q: Vector2 in q4:
				cc += q
			cc /= 4.0
			var gap := rng.randf_range(0.002, 0.004)
			var P: Array = []
			var ht: Array = []
			var yy := y + rng.randf_range(-0.012, 0.006)
			var tilt_u := rng.randf_range(-0.015, 0.015)
			for q: Vector2 in q4:
				var qq: Vector2 = q + (cc - q).normalized() * gap
				P.append(W.call(qq))
				var hh2 := yy + tilt_u * qq.x + rng.randf_range(-0.003, 0.003)
				ht.append(hh2)
				min_top = minf(min_top, hh2)
			_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
			stone(sm, P, ht, yy + rng.randf_range(0.003, 0.009), ybot, rng.randf_range(0.007, 0.013), _tone(rng, c == 0 or c == cols - 1))
	# 土の床：最も低い石の頂 −1 cm（目地の底を浅く）
	_vc = Color(0.34, 0.28, 0.20)
	var bp := [W.call(Vector2(uL, 0.02)), W.call(Vector2(uR, 0.02)), W.call(Vector2(uR, d + 0.04)), W.call(Vector2(uL, d + 0.04))]
	var bed: Array = []
	for q: Vector2 in bp:
		bed.append(Vector3(q.x, min_top - 0.01, q.y))
	_tri_up(sm, bed[0], bed[1], bed[2])
	_tri_up(sm, bed[0], bed[2], bed[3])
	_uvo = Vector2.ZERO


# ───────────────────────────── 側面：笠石・石垣・土の裾 ─────────────────────────────

## 側 sd の外側地形高を k ごとに測る（P1 TerrainCollision だけ＝可視地形と同じ三角形）。範囲外は NAN
static func outer_profile(sp: PhysicsDirectSpaceState3D, cl: PackedVector2Array, kr: Vector2i, sd: float, u := U_TERR) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(cl.size())
	out.fill(NAN)
	for k in range(maxi(kr.x - 4, 0), mini(kr.y + 4, cl.size() - 1) + 1):
		var t := SA.tangent(cl, k)
		var p := cl[k] + Vector2(-t.y, t.x) * sd * u
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
		var ex: Array[RID] = []
		for tt in 12:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
				out[k] = float(h["position"].y)
				break
			ex.append(h["rid"])
	return out


static func _line(k: int, ka: int, kb: int, ta: float, tb: float) -> float:
	return lerpf(ta, tb, clampf(float(k - ka) / float(maxi(kb - ka, 1)), 0.0, 1.0))


## 長さ ka〜kb を lo〜hi m の石に分ける境界の列（端数が小さければ前の石へ足す）
static func _splits(rng: RandomNumberGenerator, ka: int, kb: int, lo: float, hi: float) -> Array:
	var out := [ka]
	var k := ka
	var min_k := int(round(lo * 0.6 / 0.05))
	while true:
		var l := int(round(rng.randf_range(lo, hi) / 0.05))
		if kb - (k + l) < min_k:
			out.append(kb)
			break
		k += l
		out.append(k)
	return out


## 石垣／笠石の 1 ブロック（k_s〜k_e、内側 u_in〜外面 u_face〔いずれも側 sd の向きで正〕）。頂＝line(k) − off、底＝ybot
static func _block(sm: SurfaceTool, cl: PackedVector2Array, k_s: int, k_e: int, sd: float, u_in: float, u_face: float, run: Array, off: float, ybot: float, base: Color, r: float, rng: RandomNumberGenerator, top_col := Color(-1.0, 0.0, 0.0, 1.0)) -> void:
	var ts := SA.tangent(cl, k_s)
	var te := SA.tangent(cl, k_e)
	var ns := Vector2(-ts.y, ts.x) * sd
	var ne := Vector2(-te.y, te.x) * sd
	var e0 := 0.004      # 前後の目地
	var j := func() -> float:
		return rng.randf_range(-0.014, 0.014)
	var fi: Vector2 = cl[k_s] + ts * e0 + ns * (u_in + j.call())
	var fo: Vector2 = cl[k_s] + ts * e0 + ns * (u_face + j.call())
	var bo: Vector2 = cl[k_e] - te * e0 + ne * (u_face + j.call())
	var bi: Vector2 = cl[k_e] - te * e0 + ne * (u_in + j.call())
	var pts: Array = [fi, fo]
	var ks: Array = [k_s, k_s]
	if k_e - k_s >= 7 and rng.randf() < 0.65:
		var km := (k_s + k_e) / 2
		var tm := SA.tangent(cl, km)
		var nm := Vector2(-tm.y, tm.x) * sd
		pts.append(cl[km] + nm * (u_face + rng.randf_range(0.0, 0.035)))     # 外面の中ほどが少し膨らむ（荒い割り肌）
		ks.append(km)
	pts.append(bo)
	ks.append(k_e)
	pts.append(bi)
	ks.append(k_e)
	var P: Array = []
	var ht: Array = []
	var s_ht := 0.0
	var tilt := rng.randf_range(-0.03, 0.03) if off > 0.01 else rng.randf_range(-0.015, 0.015)
	var jit_h := 0.02 if off > 0.01 else 0.006
	for i in pts.size():
		P.append(pts[i])
		var hh := _line(int(ks[i]), int(run[0]), int(run[1]), float(run[2]), float(run[3])) - off + tilt * (1.0 if i % 2 == 0 else -1.0) + rng.randf_range(-jit_h, jit_h)
		ht.append(hh)
		s_ht += hh
	_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
	var kmid := (k_s + k_e) / 2
	var tmid := SA.tangent(cl, kmid)
	var fmid: Vector2 = cl[kmid] + Vector2(-tmid.y, tmid.x) * sd * u_face
	diag.append({"k": kmid, "sd": sd, "u": u_face, "p": fmid, "ybot": ybot, "top": s_ht / float(pts.size()), "off": off, "base": _cur_base})
	uv_k = 1.5
	stone(sm, P, ht, s_ht / float(pts.size()) + rng.randf_range(0.002, 0.007), ybot, r, base, 0, top_col)
	uv_k = 0.9


static func _soil_tri(hm: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, wa: Array, wb: Array, wc: Array) -> void:
	var n := (c - a).cross(b - a)
	if n.length() < 1e-9:
		return
	n = n.normalized()
	if n.y < 0.0:
		var t := b
		b = c
		c = t
		var tw := wb
		wb = wc
		wc = tw
		n = -n
	var vs := [a, b, c]
	var ws := [wa, wb, wc]
	for i in 3:
		var w: Array = ws[i]
		hm.set_color(w[0])
		hm.set_uv(w[1])
		hm.set_uv2(w[2])
		hm.set_normal(n)
		hm.add_vertex(vs[i])
	soil_n += 1


## 石垣の根元に盛る土の裾。外縁は地形の −3 cm に潜り（接地線が出ない）、内縁は石垣の面に当たる。盛り高さ・幅は露出と連続ノイズで変わり、所々で消える。
## ウェイト〔地形シェーダー mode 0〕：周囲の地形（参道脇 ≤ 2.6 m）の実測 trodden 0.83–0.85・rock 0.05 に合わせ、内縁だけ少し湿った土〔mud・forest〕
static func _heap(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, ka: int, kb: int, sd: float, u_low: float, ta: float, tb: float, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array, rng: RandomNumberGenerator) -> void:
	var w0 := rng.randf_range(0.40, 0.65)
	var ph1 := rng.randf_range(0.0, TAU)
	var ph2 := rng.randf_range(0.0, TAU)
	var rows: Array = []
	for k in range(ka, kb + 2, 2):
		var kk := mini(k, kb)
		var t_k := tout[kk]
		var t_f := tfar[kk]
		if is_nan(t_k) or is_nan(t_f):
			rows.append(null)
			continue
		var slope := (t_f - t_k) / (U_FAR - U_TERR)
		var uf := u_low - 0.02
		var tf_in := t_k + slope * (uf - U_TERR)
		var ex := _line(kk, ka, kb, ta, tb) - tf_in
		var amt := clampf(0.55 + 0.55 * sin(float(kk) * 0.11 + ph1) + 0.35 * sin(float(kk) * 0.27 + ph2) - 0.15, 0.0, 1.0)
		amt *= smoothstep(0.10, 0.30, ex)
		for ls in lanterns:                                            # 燈籠の足元は避ける
			if absf(float(kk) * 0.05 - float(ls)) < 1.1:
				amt = 0.0
		if amt < 0.04:
			rows.append(null)
			continue
		var h := clampf(0.55 * ex, 0.08, 0.28) * amt
		var w := w0 * (0.45 + 0.55 * amt)
		var t := SA.tangent(cl, kk)
		var nn := Vector2(-t.y, t.x) * sd
		var p_in: Vector2 = cl[kk] + nn * uf
		var p_m: Vector2 = cl[kk] + nn * (uf + 0.5 * w)
		var p_o: Vector2 = cl[kk] + nn * (uf + w)
		rows.append([Vector3(p_in.x, tf_in + h, p_in.y),
			Vector3(p_m.x, t_k + slope * (uf + 0.5 * w - U_TERR) + h * 0.45, p_m.y),
			Vector3(p_o.x, t_k + slope * (uf + w - U_TERR) - 0.03, p_o.y)])
	var w_in := [Color(0.80, 0.0, 0.32, 0.04), Vector2(0.55, 0.0), Vector2(0.10, 0.0)]
	var w_mid := [Color(0.85, 0.0, 0.14, 0.04), Vector2(0.30, 0.0), Vector2(0.03, 0.0)]
	var w_out := [Color(0.85, 0.0, 0.0, 0.04), Vector2(0.06, 0.0), Vector2(0.0, 0.0)]
	for r in rows.size() - 1:
		if rows[r] == null or rows[r + 1] == null:
			continue
		var a: Array = rows[r]
		var b: Array = rows[r + 1]
		_soil_tri(hm, a[0], b[0], b[1], w_in, w_in, w_mid)
		_soil_tri(hm, a[0], b[1], a[1], w_in, w_mid, w_mid)
		_soil_tri(hm, a[1], b[1], b[2], w_mid, w_mid, w_out)
		_soil_tri(hm, a[1], b[2], a[2], w_mid, w_out, w_out)
		# 落石・小石：裾の上に所々（石垣から転げた石の語彙）。接地は裾の面に +数 cm 潜る
		if rng.randf() < 0.5:
			var np := 1 + int(rng.randf() < 0.45)
			for pq in np:
				var tq := rng.randf_range(-0.2, 0.9)
				var pm: Vector3 = (a[1] as Vector3).lerp(a[2], tq) if tq > 0.0 else (a[0] as Vector3).lerp(a[1], 1.0 + tq)
				var rad := rng.randf_range(0.05, 0.12)
				var n_v := 5 + int(rng.randf() < 0.5)
				var P: Array = []
				var ht: Array = []
				var a0 := rng.randf_range(0.0, TAU)
				for vi in n_v:
					var an := a0 + TAU * float(vi) / float(n_v)
					var rr := rad * rng.randf_range(0.75, 1.15)
					P.append(Vector2(pm.x + cos(an) * rr, pm.z + sin(an) * rr * 0.8))
					ht.append(pm.y + rad * rng.randf_range(0.55, 0.9))
				_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
				stone(sm, P, ht, pm.y + rad * 1.0, pm.y - 0.06, 0.02, _mul(_tone(rng, true), rng.randf_range(0.85, 1.0)), 0)
		_uvo = Vector2.ZERO


## 側 sd の 1 run（plan[i..j]）：笠石の頂線 line(k) を引き、露出に応じて 1〜5 段の石垣を地形まで降ろし、根元に土の裾を盛る
static func _wall_run(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, plan: Array, i: int, j: int, sd: float, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array, rng: RandomNumberGenerator) -> void:
	var ka := int(plan[i]["k0"])
	var kb := int(plan[j]["k1"])
	var key := "eR" if sd > 0.0 else "eL"
	var edge := 0.0
	for q in range(i, j + 1):
		edge = maxf(edge, float(plan[q][key]))
	var ta := float(plan[i]["y0"]) + rng.randf_range(0.025, 0.07)
	var tb := float(plan[j]["y1"]) + rng.randf_range(0.025, 0.07)
	for q in range(i, j + 1):          # 各踏面の前縁で 頂線 ≥ 踏面頂 + 2 cm
		var kq := int(plan[q]["k0"])
		var deficit := float(plan[q]["y0"]) + 0.02 - _line(kq, ka, kb, ta, tb)
		if deficit > 0.0:
			ta += deficit
			tb += deficit
	var line_min := minf(ta, tb)
	var t_min := INF
	var e_max := -INF
	for k in range(ka, kb + 1, 2):
		var tv := tout[k]
		if is_nan(tv):
			continue
		t_min = minf(t_min, tv)
		e_max = maxf(e_max, _line(k, ka, kb, ta, tb) - tv)
	if is_inf(t_min):
		t_min = line_min - 0.3
		e_max = 0.2
	var y_bot := t_min - BURY
	var vis := maxf(e_max + 0.04, 0.10)
	var n_c := clampi(int(ceil(vis / COURSE)), 1, 5)
	var rows := []
	var tot_r := 0.0
	for c in n_c:
		var rr := rng.randf_range(0.8, 1.2)
		rows.append(rr)
		tot_r += rr
	var offs := [0.0]
	for c in n_c:
		offs.append(float(offs[c]) + vis * float(rows[c]) / tot_r)
	var w_top := rng.randf_range(float(W_TOP[0]), float(W_TOP[1]))
	var u_in := edge - 0.03
	for c in n_c:
		var u_face := edge + w_top + BATTER * float(c)
		var off := float(offs[c])
		var ybot_c := y_bot
		if c < n_c - 1:
			ybot_c = minf(line_min - float(offs[c + 1]) - 0.03, y_bot + 10.0)
		ybot_c = minf(ybot_c, line_min - off - 0.10)
		var cuts := _splits(rng, ka, kb, 0.30 if c == 0 else 0.28, 0.65 if c == 0 else 0.62)
		for b in cuts.size() - 1:
			var kk0 := int(cuts[b])
			var kk1 := int(cuts[b + 1])
			var big := c == 0 and rng.randf() < 0.12 and kk1 - kk0 <= 10       # 笠石に時々 大きく高い石（規則的なレールにしない）
			if c == 0 and n_c == 1 and e_max < 0.12 and rng.randf() < 0.12:
				continue                                                     # 笠石が欠けた所（土がこぼれる）
			var tone := _tone(rng, true)
			var top_col := Color(-1.0, 0.0, 0.0, 1.0)
			if c == 0:
				tone = _mul(_tone(rng, false), rng.randf_range(0.95, 1.08))
				if rng.randf() < 0.45:
					var mt := rng.randf_range(0.8, 1.05)
					top_col = Color(mt * 0.42, mt * 0.50, mt * 0.26)          # 笠石の上面だけ苔（暗い黄緑、r8 と同じ語彙）。側面は石の色
			else:
				tone = _mul(tone, clampf(0.92 - 0.05 * float(c), 0.6, 0.95) * rng.randf_range(0.92, 1.05))
			var cap_j := 0.05 if String(plan[i]["kind"]) == "landing" else 0.03
			var off_b := off + (rng.randf_range(-cap_j, cap_j) if c == 0 else rng.randf_range(-0.05, 0.05)) - (0.05 if big else 0.0)
			var uf := u_face + (0.03 if big else 0.0) + rng.randf_range(-0.02, 0.02)
			var s_blk := float(kk0 + kk1) * 0.025
			for ls in lanterns:                                                # 燈籠の足元（内縁 1.61 m）には食い込ませない
				if absf(s_blk - float(ls)) < 1.1:
					uf = minf(uf, 1.56)
			var row_h := float(offs[c + 1]) - off
			if c >= 1 and kk1 - kk0 >= 6 and row_h > 0.22 and rng.randf() < 0.32:
				# 乱積み：この段の石を縦に二つ積む（水平の目地が通らない）。上の石は少し引っ込み、下の石は少し出る
				var split := rng.randf_range(0.42, 0.6)
				var yb_up := line_min - (off_b + row_h * split) - 0.03
				_cur_base = false
				_block(sm, cl, kk0, kk1, sd, u_in, uf - 0.015, [ka, kb, ta, tb], off_b, yb_up, tone, rng.randf_range(0.02, 0.035), rng)
				_cur_base = c == n_c - 1
				_block(sm, cl, kk0, kk1, sd, u_in, uf + 0.015, [ka, kb, ta, tb], off_b + row_h * split, ybot_c, _mul(tone, rng.randf_range(0.9, 1.05)), rng.randf_range(0.02, 0.035), rng)
			else:
				_cur_base = c == n_c - 1
				_block(sm, cl, kk0, kk1, sd, u_in, uf, [ka, kb, ta, tb], off_b, ybot_c, tone, rng.randf_range(0.03, 0.05), rng, top_col)
	if e_max > 0.12:
		_heap(sm, hm, cl, ka, kb, sd, edge + w_top + BATTER * float(n_c - 1), ta, tb, tout, tfar, lanterns, rng)


## 全 run の側面：run＝1–3 段（踊り場は単独）
static func build_sides(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, plan: Array, touts: Array, tfars: Array, lanterns: Array, rng: RandomNumberGenerator) -> void:
	var sides := [-1.0, 1.0]
	for si in 2:
		var sd: float = sides[si]
		var i := 0
		while i < plan.size():
			var a: Dictionary = plan[i]
			var j := i
			if String(a["kind"]) == "step":
				var rr := rng.randf()
				var cnt := 1 if rr < 0.30 else (2 if rr < 0.75 else 3)
				j = mini(i + cnt, plan.size()) - 1
				for q in range(i + 1, j + 1):
					if String(plan[q]["kind"]) != "step":
						j = q - 1
						break
			_wall_run(sm, hm, cl, plan, i, j, sd, touts[si], tfars[si], lanterns, rng)
			i = j + 1


# ───────────────────────────── 組み立て ─────────────────────────────

## 石の mesh と土の裾の mesh。lanterns＝区間内の燈籠の s〔m〕（その近くには土を盛らない）
static func build_meshes(cl: PackedVector2Array, H: PackedFloat32Array, plan: Array, touts: Array, tfars: Array, lanterns: Array) -> Dictionary:
	diag.clear()
	soil_n = 0
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hm := SurfaceTool.new()
	hm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	# 前処理：各段の鼻先（次の段の蹴上までの見える奥行きを決める）
	var rp := RandomNumberGenerator.new()
	rp.seed = SEED + 3
	for a: Dictionary in plan:
		a["nose"] = rp.randf_range(-0.01, 0.02)      # 段ごとの前縁の前後（平均 +0.5 cm＝ほぼ零均値。突出は斜坡碰撞に対して石が早く立ち上がる〔足が沈む〕原因になる）
	var state := {"uL": -1.09, "uR": 1.09, "cuts": []}
	var y_prev := NAN
	for a: Dictionary in plan:
		if is_nan(y_prev):
			y_prev = H[int(a["k0"])]
		if String(a["kind"]) == "landing":
			landing(sm, cl, a, y_prev, H, state, rng)
		else:
			tread(sm, cl, a, y_prev, H, state, rng)
		y_prev = float(a["y1"])
	build_sides(sm, hm, cl, plan, touts, tfars, lanterns, rng)
	sm.generate_tangents()
	var out := {"steps": sm.commit()}
	out["soil"] = hm.commit() if soil_n > 0 else null
	return out


static func make_material() -> StandardMaterial3D:
	var m := (load(SA.STONE) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = SA.STONE_ALBEDO
	m.resource_name = "P13_SandoPilotStone"
	return m


## 試作 overlay ノード（無碰撞）。plan＝replan() の戻り、touts／tfars＝[左, 右] の外側地形高〔u=1.5／1.95〕、rest＝r8 の StoneSteps から区間を除いた mesh
static func build(cl: PackedVector2Array, H: PackedFloat32Array, plan: Array, touts: Array, tfars: Array, lanterns: Array, rest: Mesh) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(SCRIPT))
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("phase", "P13 W4 pilot")
	root.set("rest_mesh", rest)
	var ms := build_meshes(cl, H, plan, touts, tfars, lanterns)
	var mi := MeshInstance3D.new()
	mi.name = "W4Steps"
	mi.mesh = ms["steps"]
	mi.material_override = make_material()
	mi.visibility_range_end = 260.0
	mi.set_meta("cells", plan.size())
	root.add_child(mi)
	mi.owner = root
	if ms["soil"] != null:
		var so := MeshInstance3D.new()
		so.name = "W4Soil"
		so.mesh = ms["soil"]
		so.visibility_range_end = 200.0
		so.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(so)
		so.owner = root
	return root


## r8 の StoneSteps から試作区間（k 範囲 kr、中心線から 3 m 以内）の三角形を除いた mesh（区間外は r8 のまま）。
## 端は境界面（その点の接線に直交）で厳密に切る：隣の段の面取り・潜り込みを巻き込まない
static func r8_without_range(mesh: ArrayMesh, cl: PackedVector2Array, kr: Vector2i) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tri_n := idx.size() / 3 if idx.size() > 0 else vs.size() / 3
	# 区間の外接矩形（xz）＋3.5 m
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in range(kr.x, kr.y + 1, 4):
		lo = Vector2(minf(lo.x, cl[k].x), minf(lo.y, cl[k].y))
		hi = Vector2(maxf(hi.x, cl[k].x), maxf(hi.y, cl[k].y))
	lo -= Vector2(3.5, 3.5)
	hi += Vector2(3.5, 3.5)
	var ps := cl[kr.x]
	var pe := cl[kr.y]
	var tsn := SA.tangent(cl, kr.x)
	var ten := SA.tangent(cl, kr.y)
	var guard := 8
	var keep := PackedInt32Array()
	var removed := 0
	for t in tri_n:
		var i0 := idx[t * 3] if idx.size() > 0 else t * 3
		var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
		var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
		var c3 := (vs[i0] + vs[i1] + vs[i2]) / 3.0
		var c := Vector2(c3.x, c3.z)
		var inside := false
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y:
			var best := INF
			var bk := 0
			for k in range(maxi(kr.x - 60, 0), mini(kr.y + 60, cl.size() - 1) + 1, 3):
				var dd := cl[k].distance_squared_to(c)
				if dd < best:
					best = dd
					bk = k
			if best < 9.0:
				if bk >= kr.x + guard and bk <= kr.y - guard:
					inside = true
				elif bk >= kr.x - guard and bk <= kr.y + guard:
					var after_start := (c - ps).dot(tsn) >= -0.002
					var before_end := (c - pe).dot(ten) <= 0.002
					inside = after_start and before_end
		if inside:
			removed += 1
		else:
			keep.append_array(PackedInt32Array([i0, i1, i2]))
	arr[Mesh.ARRAY_INDEX] = keep
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mesh.surface_get_material(0))
	m.set_meta("removed", removed)
	m.set_meta("total", tri_n)
	return m
