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
const ART_REVISION := "P13 W4B r13 + W5B integration r1"
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
const W_TOP := [0.15, 0.26]                    # 笠石の幅（r8 の袖石 0.16–0.24 は規格のレールに見えた）
const BATTER := 0.03                           # 石垣の段ごとの張り出し
const COURSE := 0.30                           # 石垣 1 段の目安の高さ
const V_FRONT_MIN := -0.03                      # 踏面の前縁の v〔計画の境界 k0 からの距離〕の範囲。傾き・弧・nose が重なる極端でも石面が碰撞面から外れすぎない（P13 W4B：+11 cm 後退して中心線で −18.5 cm）
const V_FRONT_MAX := 0.03
const BURY := 0.28
const U_TERR := 1.5                            # 外側地形を測る横位置
const U_FAR := 1.95                            # もう一点（土の裾の外縁まで）

static var _vc := Color.WHITE
static var _uvo := Vector2.ZERO
static var uv_k := 0.9
## 検証用：build が置いた笠石／石垣ブロックの記録 {k, sd, u, p, ybot, top, off}（verify_w4_pilot.gd が地形と突き合わせる）
static var diag: Array = []
static var soil_n := 0
## 診断用の旗（既定は空＝挙動不変。旗は RNG の消費順序を変えない＝変種どうしで石の配置が同じ）：
##   no_decals＝苔・落葉・目地の貼り物を出さない／r_scale＝面取り幅の倍率／bed_off＝土の床の高さ加算／no_bed＝土の床を出さない
static var flags := {}
static var side_log: Array = []          # 側面の処理の記録：{sd, ka, kb, e_max, mode}
static var _w5 = null              # P13 W5A モジュール〔preload の循環を避けて実行時に load〕
static var side_lift := 0.0        # 0＝W4B のまま。1＝石の側壁の頂点色の漸暗をなくす〔P13 W5A：笠石の側壁が自己影と漸暗で黒い楔に見えた〕
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

static func w5():
	if _w5 == null:
		_w5 = load("res://tools/village_v2_sando_w5a_lib.gd")
	return _w5


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
	if bool(flags.get("no_decals", false)):
		return
	var p3: Array = []
	for q: Vector2 in q4:
		var w2: Vector2 = W.call(q)
		p3.append(Vector3(w2.x, float(top_fn.call(q)) + lift, w2.y))
	_vc = col
	_tri_up(st, p3[0], p3[1], p3[2])
	_tri_up(st, p3[0], p3[2], p3[3])


## 不規則な石 1 個。P＝plan 外形（xz、ほぼ凸）、ht＝外形の各点の頂面高さ、hc＝頂の中心高、ybot＝底、
## r＝面取りの水平幅（辺ごとに垂直に測る。隣り合う辺の面取りは連立で解く＝全部の辺で同じ幅になる。r10 までは重心方向へ一律に縮めていたので、
## 横長の石の継ぎ目だけが太い V 溝になっていた）、r_front＝先頭 fronts 辺〔鼻先〕の幅（足で磨り減って大きい）、base＝基調色、fronts＝前縁の辺の数（P[0] から始まる連続 fronts 辺）。
## 側面の色：面取り下端 0.90 → 0.28 m 下で 0.76 → 底 0.58（P13 W4B の診断：黒の主因は影と頂点色の暗化だったので r10 の 0.82／0.66／0.45 から明るく）
static func stone(st: SurfaceTool, P: Array, ht: Array, hc: float, ybot: float, r: float, base: Color, fronts := 0, top_col := Color(-1.0, 0.0, 0.0, 1.0), r_front := -1.0) -> void:
	var rs := float(flags.get("r_scale", 1.0))
	var r_e := r * rs
	var r_f := (r if r_front < 0.0 else r_front) * rs
	var n := P.size()
	var c := Vector2.ZERO
	for p: Vector2 in P:
		c += p
	c /= float(n)
	var area := 0.0
	for i in n:
		var pa: Vector2 = P[i]
		var pb2: Vector2 = P[(i + 1) % n]
		area += pa.x * pb2.y - pb2.x * pa.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var nrm: Array = []
	var re: Array = []
	for i in n:
		var e: Vector2 = (P[(i + 1) % n] as Vector2) - (P[i] as Vector2)
		var l := maxf(e.length(), 1e-6)
		nrm.append(Vector2(-e.y, e.x) / l * sgn)
		re.append(r_f if i < fronts else r_e)
	var cen3 := Vector3(c.x, hc, c.y)
	var low := Vector3(c.x, ybot - 0.5, c.y)
	var Pin: Array = []
	var Pe: Array = []
	var Pm: Array = []
	var Pb: Array = []
	for i in n:
		var ia := (i - 1 + n) % n
		var na: Vector2 = nrm[ia]
		var nb: Vector2 = nrm[i]
		var ra: float = re[ia]
		var rb: float = re[i]
		var det := na.x * nb.y - na.y * nb.x
		var dlt: Vector2
		if absf(det) < 0.25:
			dlt = (na * ra + nb * rb) * 0.5
		else:
			dlt = Vector2((ra * nb.y - na.y * rb) / det, (na.x * rb - ra * nb.x) / det)
		var cap := 2.5 * maxf(maxf(ra, rb), 0.002)
		if dlt.length() > cap:
			dlt = dlt.normalized() * cap
		var pin: Vector2 = (P[i] as Vector2) + dlt
		var drop := 0.75 * 0.5 * (ra + rb)
		var d: Vector2 = c - (P[i] as Vector2)
		var dl := maxf(d.length(), 1e-5)
		var pb: Vector2 = (P[i] as Vector2) + d / dl * 0.03
		var ye := float(ht[i]) - drop
		var ym := maxf(ybot + 0.01, ye - 0.28)
		var t := clampf((ye - ym) / maxf(ye - ybot, 1e-4), 0.0, 1.0)
		var pm: Vector2 = (P[i] as Vector2).lerp(pb, t)
		Pin.append(Vector3(pin.x, float(ht[i]), pin.y))
		Pe.append(Vector3((P[i] as Vector2).x, ye, (P[i] as Vector2).y))
		Pm.append(Vector3(pm.x, ym, pm.y))
		Pb.append(Vector3(pb.x, ybot, pb.y))
	var topc := base if top_col.r < 0.0 else top_col       # 苔色は上面〔と面取り〕だけ。側面は石の色
	var dg := bool(flags.get("diag_color", false))        # 診断：面の種類ごとの純色〔頂面＝白／面取り＝緑／壁上半＝赤／壁下半＝青／底＝桃〕
	_vc = Color(1, 1, 1) if dg else topc
	for i in n:
		_tri_up(st, cen3, Pin[i], Pin[(i + 1) % n])
	for i in n:
		var j := (i + 1) % n
		var k := 1.10 if i < fronts else 0.97
		var cb := _mul(topc, k)
		var cw := _mul(base, 0.90)
		if dg:
			cb = Color(0, 1, 0)
			cw = cb
		_quad_out(st, Pin[i], Pin[j], Pe[j], Pe[i], low, cb, cb, cw, cw)
		var cw0 := _mul(base, 0.90 if i >= fronts else 0.94)
		var cm := _mul(base, 0.76).lerp(cw0, side_lift)
		var cd := _mul(base, 0.58).lerp(cw0, side_lift)
		if dg:
			cw0 = Color(1, 0, 0)
			cm = cw0
			cd = Color(0, 0, 1)
		_quad_out(st, Pe[i], Pe[j], Pm[j], Pm[i], low, cw0, cw0, cm, cm)
		var cmm := cm if not dg else Color(0, 0, 1)
		_quad_out(st, Pm[i], Pm[j], Pb[j], Pb[i], low, cmm, cmm, cd, cd)
	# 底（地中だが、側面から覗く隙間に備えて閉じる）
	var cb3 := Vector3(c.x, ybot, c.y)
	_vc = (_mul(base, 0.35).lerp(_mul(base, 0.80), side_lift) if not dg else Color(1, 0, 1))      # 底面〔笠石の下面は下から見える〕。side_lift で明るく
	for i in n:
		_tri_out(st, cb3, Pb[i], Pb[(i + 1) % n], Vector3(c.x, ybot + 5.0, c.y))


# ───────────────────────────── 踏石の列 ─────────────────────────────

static func _cuts(rng: RandomNumberGenerator, uL: float, uR: float, prev: Array) -> Array:
	for attempt in 40:
		var rr := rng.randf()
		var n := 1 if rr < 0.28 else (2 if rr < 0.72 else 3)      # 1 枚石〔28 %〕／2 枚〔44 %〕／3 枚〔28 %〕。r11 初版は 2–4 枚で、短い黒縫が反覆した
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
			u = clampf(mean + rng.randf_range(-0.28, 0.28), lo, minf(hi, u + 1.55))
			cuts.append(u)
		if not ok:
			continue
		cuts.append(uR)
		var wmax := 2.9 if n == 1 else 1.55
		if float(cuts[cuts.size() - 1]) - float(cuts[cuts.size() - 2]) > wmax or float(cuts[1]) - float(cuts[0]) > wmax:
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


## 地面〔地形シェーダー〕と同じ材質で描く面のウェイト：[COLOR(trodden,gravel,mud,rock), UV(forest,farm), UV2(wet,street)]
## r10 までの石の隙間の底は暗褐色の単色〔頂点色〕だった。砂利まじりの土を地形と同じシェーダーで描き、暗い線にならないようにする。
static func _fill_w(kind: String) -> Array:
	if kind == "joint":      # 継ぎ目に詰まった細かい砂利まじりの土
		return [Color(0.40, 0.50, 0.04, 0.03), Vector2(0.12, 0.0), Vector2(0.0, 0.0)]
	return [Color(0.55, 0.20, 0.25, 0.0), Vector2(0.20, 0.0), Vector2(0.04, 0.0)]      # bed＝石の下の安全な床（ほとんど見えない）


static func _fill_quad(hm: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, w: Array) -> void:
	_soil_tri(hm, a, b, c, w, w, w)
	_soil_tri(hm, a, c, d, w, w, w)


## 凸多角形 poly を半平面 nrm·x ≤ c で切る（Sutherland–Hodgman）
static func _clip_half(poly: PackedVector2Array, nrm: Vector2, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var pa := poly[i]
		var pb := poly[(i + 1) % n]
		var da := nrm.dot(pa) - c
		var db := nrm.dot(pb) - c
		if da <= 0.0:
			out.append(pa)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			out.append(pa + (pb - pa) * (da / (da - db)))
	return out


## 矩形 rect を seeds のボロノイ領域に分ける（不規則な敷石の割り）
static func _voronoi(rect: Rect2, seeds: Array) -> Array:
	var cells := []
	for i in seeds.size():
		var poly := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
		var si: Vector2 = seeds[i]
		for j in seeds.size():
			if j == i:
				continue
			var sj: Vector2 = seeds[j]
			poly = _clip_half(poly, sj - si, (sj.length_squared() - si.length_squared()) * 0.5)
			if poly.size() < 3:
				break
		cells.append(poly)
	return cells


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


static func _largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var ba := -1.0
	for p in polys:
		var pa := _poly_area(p)
		if pa > ba:
			ba = pa
			best = p
	return best


## 踏面 1 段：継ぎ目の通らない 2–4 枚の不規則な石。継ぎ目は斜め・幅が不均一〔楔形〕・中ほどでずれ、詰め物〔砂利まじりの土、地形と同じ材質〕が入る（P13 W4B）。
## state＝{uL,uR,cuts}（区間連続のゆらぎ）。a に eL／eR（踏面端 |u|）を書き戻す
static func tread(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, a: Dictionary, y_prev: float, H: PackedFloat32Array, state: Dictionary, rng: RandomNumberGenerator) -> void:
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
	if a.has("cap_l") or a.has("cap_r"):
		# P13 W5C（要素に cap_l／cap_r がある時だけ＝承認済みの下段は 1 ビットも変わらない）：地形が踏面頂より高い側は、その手前で石を止める。state（乱数の歩み）は触らない
		uL = -minf(-uL, float(a.get("cap_l", 9.0)))
		uR = minf(uR, float(a.get("cap_r", 9.0)))
	a["eL"] = -uL
	a["eR"] = uR
	var cuts := _cuts(rng, uL, uR, state["cuts"])
	state["cuts"] = cuts.slice(1, cuts.size() - 1)
	var ns := cuts.size() - 1
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
	var bow := rng.randf_range(0.02, 0.05) if rng.randf() < 0.4 else 0.0      # 段の前縁が弧を描く（中央が前、端が後ろ。全幅の平均が 0 になるよう 0.667 bow を差し引く）
	var half_w := maxf(absf(uL), absf(uR))
	# ── 継ぎ目（内部の切れ目 1..ns-1）：斜め〔前後で u がずれる〕・半幅が前後で違う〔楔形〕・中ほどで横にずれる
	var jt: Array = []
	for j in cuts.size():
		if j == 0 or j == cuts.size() - 1:
			jt.append({})
			continue
		var roll := rng.randf()
		var hwf := rng.randf_range(0.001, 0.0025) if roll < 0.55 else (rng.randf_range(0.003, 0.006) if roll < 0.92 else rng.randf_range(0.007, 0.010))     # 半幅：緊貼 55 %／普通 37 %／開き 8 %（r11 初版は開き 15 % で半幅 18 mm＝黒い切り欠き）
		var hwb := clampf(hwf * rng.randf_range(0.5, 2.0), 0.001, 0.012)
		var vmf := rng.randf_range(0.35, 0.65)
		var sh := rng.randf_range(0.02, 0.075) * (1.0 if rng.randf() < 0.5 else -1.0)
		var cj := float(cuts[j])
		jt.append({"cf": cj - sh * 0.5, "cb": cj + sh * 0.5, "cm": cj + sh * (vmf - 0.5) + rng.randf_range(-0.02, 0.02),
			"hwf": hwf, "hwb": hwb, "hwm": lerpf(hwf, hwb, vmf), "vm": vmf * back})
	var min_top := INF
	var infos: Array = []
	# 前縁は接縫ごとに 1 つの共用オフセット〔両端もそれぞれ 1 つ〕：隣り合う 2 石の前縁が接縫で必ず同じ v になる＝段差〔側面の露出〕が生じない。
	# 前縁は接縫で折れる線になるので不規則さは残る（P13 W4B：側面の露出が『太い黒縦帯』の正体だった）
	var joff: Array = []
	for j in cuts.size():
		joff.append(rng.randf_range(-0.012, 0.014))
	for j in ns:
		var uc := (float(cuts[j]) + float(cuts[j + 1])) * 0.5
		var bow0 := bow * (1.0 - pow(float(cuts[j]) / half_w, 2.0))
		var bow1 := bow * (1.0 - pow(float(cuts[j + 1]) / half_w, 2.0))
		# 石ごとに前縁が前後する（蹴上の線が波打つ）。差は ±1.2 cm 以内：r11 初版は ±5.5 cm で、相鄰の石の側面〔高さ 18 cm〕が丸ごと露出し、
		# 背光で『30–40 px 幅の黒い縦帯』に見えていた（縫ではなく側面。P13 W4B 診断）
		var nj := nose + 0.5 * (float(joff[j]) + float(joff[j + 1]))
		var vf0 := -nose - float(joff[j]) - (bow0 - 0.667 * bow)
		var vf1 := -nose - float(joff[j + 1]) - (bow1 - 0.667 * bow)
		var vb0 := back + rng.randf_range(-0.01, 0.015)
		var vb1 := back + rng.randf_range(-0.01, 0.015)
		var left_int := j > 0
		var right_int := j + 1 < ns
		var jl: Dictionary = jt[j]
		var jr: Dictionary = jt[j + 1]
		var ufl: float = (float(jl["cf"]) + float(jl["hwf"])) if left_int else uL
		var ubl: float = (float(jl["cb"]) + float(jl["hwb"])) if left_int else uL
		var ufr: float = (float(jr["cf"]) - float(jr["hwf"])) if right_int else uR
		var ubr: float = (float(jr["cb"]) - float(jr["hwb"])) if right_int else uR
		# 石ごとの傾き：前縁・後縁の v を u に比例してずらす（u は動かさない＝継ぎ目が崩れない）
		var yaw_j := 0.0
		var pf0 := Vector2(ufl, clampf(vf0 + yaw_j * (ufl - uc), V_FRONT_MIN, V_FRONT_MAX))
		var pf1 := Vector2(ufr, clampf(vf1 + yaw_j * (ufr - uc), V_FRONT_MIN, V_FRONT_MAX))
		var pb1 := Vector2(ubr, vb1 + yaw_j * (ubr - uc))
		var pb0 := Vector2(ubl, vb0 + yaw_j * (ubl - uc))
		# 不整形の足し頂点：前縁の中ほどが前へ膨らむ（丸みのある鼻先）／前の角の欠け／外側の側面が外へ膨らむ（継ぎ目の側は膨らませない）
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
			var mf := (fl_start + fr_end) * 0.5 + Vector2(0.0, -rng.randf_range(0.008, 0.03))
			mf.y = maxf(mf.y, V_FRONT_MIN)
			poly.append(mf)
			fronts = 2
		poly.append(fr_end)
		for q in fr_side:
			poly.append(q)
		var right_start: Vector2 = fr_side[0] if not fr_side.is_empty() else pf1
		if right_int:
			poly.append(Vector2(float(jr["cm"]) - float(jr["hwm"]), float(jr["vm"]) + yaw_j * (float(jr["cm"]) - uc)))
		elif rng.randf() < 0.35:
			poly.append((right_start + pb1) * 0.5 + Vector2(rng.randf_range(0.0, 0.03), 0.0))
		poly.append(pb1)
		poly.append(pb0)
		var left_end: Vector2 = tail[0] if not tail.is_empty() else pf0
		if left_int:
			poly.append(Vector2(float(jl["cm"]) + float(jl["hwm"]), float(jl["vm"]) + yaw_j * (float(jl["cm"]) - uc)))
		elif rng.randf() < 0.35:
			poly.append((pb0 + left_end) * 0.5 + Vector2(-rng.randf_range(0.0, 0.03), 0.0))
		for q in tail:
			poly.append(q)
		var dy := clampf(rng.randfn(0.0, 0.0025), -0.005, 0.005)      # 石ごとの高低差〔隣り合う石の側面が背光で暗い縦帯に見えた〕
		var tilt_f := rng.randf_range(0.015, 0.035)       # 前下がり（摩耗）
		var tilt_u := rng.randf_range(-0.012, 0.012)
		var top_fn := func(q: Vector2) -> float:
			return y + dy - tilt_f * (d - clampf(q.y, 0.0, d)) + tilt_u * (q.x - uc)
		var P: Array = []
		var ht: Array = []
		var s_ht := 0.0
		for q: Vector2 in poly:
			P.append(W.call(q))
			var hh: float = float(top_fn.call(q)) + rng.randf_range(-0.002, 0.002)
			ht.append(hh)
			s_ht += hh
			min_top = minf(min_top, hh)
		var hc := s_ht / float(poly.size()) + rng.randf_range(0.002, 0.007)
		var base := _tone(rng, j == 0 or j == ns - 1)
		if absf(uc) < 0.5:
			base = _mul(base, 1.05)                      # 人が踏む筋
		_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		var rj := rng.randf_range(0.004, 0.007)           # 継ぎ目側の面取り＝浅い（r10 は 2.2–4 cm で、横長の石の継ぎ目が太い V 溝だった）
		stone(sm, P, ht, hc, ybot, rj, base, fronts, Color(-1.0, 0.0, 0.0, 1.0), rng.randf_range(0.022, 0.04))
		infos.append({"u0": float(cuts[j]), "u1": float(cuts[j + 1]), "top": top_fn, "nj": nj, "rj": rj, "vfl": pf0.y, "vfr": pf1.y})
	# ── 石の下の床（地形と同じ材質、ほとんど見えない）＋継ぎ目の詰め物（砂利まじりの土）
	if not bool(flags.get("no_bed", false)):
		var by := min_top - 0.03 + float(flags.get("bed_off", 0.0))
		var bp := [W.call(Vector2(uL, 0.03)), W.call(Vector2(uR, 0.03)), W.call(Vector2(uR, back)), W.call(Vector2(uL, back))]
		_fill_quad(hm, Vector3(bp[0].x, by, bp[0].y), Vector3(bp[1].x, by, bp[1].y), Vector3(bp[2].x, by, bp[2].y), Vector3(bp[3].x, by, bp[3].y), _fill_w("bed"))
	var moss_jobs: Array = []
	for j in range(1, ns):
		var jp: Dictionary = jt[j]
		var il: Dictionary = infos[j - 1]
		var ir: Dictionary = infos[j]
		var tfl: Callable = il["top"]
		var tfr: Callable = ir["top"]
		var vfront := maxf(float(il["vfr"]), float(ir["vfl"])) + 0.004
		var vback := d + 0.02
		var segs := [[float(jp["cf"]), float(jp["hwf"]), vfront], [float(jp["cm"]), float(jp["hwm"]), float(jp["vm"])], [float(jp["cb"]), float(jp["hwb"]), vback]]
		var pl: Array = []     # 左右の縁の世界座標と詰め物の高さ
		for sgm in segs:
			var cu: float = sgm[0]
			var hw: float = sgm[1]
			var vv: float = sgm[2]
			var hl: float = float(tfl.call(Vector2(cu - hw, vv))) - 0.75 * float(il["rj"])
			var hr: float = float(tfr.call(Vector2(cu + hw, vv))) - 0.75 * float(ir["rj"])
			var fy := minf(hl, hr) - 0.002
			var wl: Vector2 = W.call(Vector2(cu - hw - 0.008, vv))
			var wr: Vector2 = W.call(Vector2(cu + hw + 0.008, vv))
			pl.append([Vector3(wl.x, fy, wl.y), Vector3(wr.x, fy, wr.y)])
		_fill_quad(hm, pl[0][0], pl[0][1], pl[1][1], pl[1][0], _fill_w("joint"))
		_fill_quad(hm, pl[1][0], pl[1][1], pl[2][1], pl[2][0], _fill_w("joint"))
		# 継ぎ目の苔：全体の 3 割の継ぎ目の、前半か後半だけ（連続した線にしない）
		if rng.randf() < 0.3:
			var sg := 0 if rng.randf() < 0.5 else 1
			var mt := rng.randf_range(0.8, 1.1)
			var qa: Vector3 = pl[sg][0]
			var qb: Vector3 = pl[sg][1]
			var qc: Vector3 = pl[sg + 1][1]
			var qd: Vector3 = pl[sg + 1][0]
			var lift := Vector3(0.0, 0.0028, 0.0)
			_vc = Color(0.34 * mt, 0.44 * mt, 0.22 * mt)
			_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
			_tri_up(sm, qa + lift, qb + lift, qc + lift)
			_tri_up(sm, qa + lift, qc + lift, qd + lift)
	# ── 風化の細部（r8 ROUND 3 の語彙を継ぐ）：踏面奥の落葉・土、端の苔。石の上面の +数 mm に貼る
	_uvo = Vector2.ZERO
	for j in infos.size():
		var info: Dictionary = infos[j]
		var tf: Callable = info["top"]
		var u0 := float(info["u0"]) + 0.05
		var u1 := float(info["u1"]) - 0.05
		if u1 - u0 > 0.15 and rng.randf() < 0.75:
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
			var mt2 := rng.randf_range(0.8, 1.1)
			_uvo = Vector2(rng.randf_range(0.0, 7.0), 0.0)
			_decal(sm, W, tf, [Vector2(minf(ua, ub), v0), Vector2(maxf(ua, ub), v0), Vector2(maxf(ua, ub), v1), Vector2(minf(ua, ub), v1)], Color(mt2 * 0.36, mt2 * 0.46, mt2 * 0.22), 0.004)
	_uvo = Vector2.ZERO


## 踊り場：框石（前縁、2–3 枚・継ぎ目は斜めで幅が不揃い）＋ボロノイの不規則な敷石。敷石は框石の下へ 6 cm 潜る＝框石の後ろに隙間を作らない
## （r10 までは框石と敷石の間に最大 80 cm 幅の本物の隙間〔横縫〕があり、暗褐色の床で隠れていた＝黒い横縫の正体）。
static func landing(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, a: Dictionary, y_prev: float, H: PackedFloat32Array, state: Dictionary, rng: RandomNumberGenerator) -> void:
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
	# 框石：2–3 枚（幅不揃い）、厚み（奥行 v）0.30–0.38、後縁はまっすぐ、鼻先の丸み大
	var nk := 2 if rng.randf() < 0.45 else 3
	var kc := [uL]
	for j in range(1, nk):
		kc.append(lerpf(uL, uR, float(j) / nk + rng.randf_range(-0.09, 0.09)))
	kc.append(uR)
	var kdepth := rng.randf_range(0.30, 0.38)
	var foff: Array = []
	for j in nk + 1:
		foff.append(rng.randf_range(0.02, 0.05))          # 框石の前縁〔鼻先〕の突出。接縫ごとに共用＝隣の石の側面を露出させない
	var fj: Array = []
	for j in nk + 1:
		if j == 0 or j == nk:
			fj.append({})
		else:
			var sh := rng.randf_range(-0.05, 0.05)
			fj.append({"cf": float(kc[j]) - sh * 0.5, "cb": float(kc[j]) + sh * 0.5, "hw": rng.randf_range(0.002, 0.007)})
	for j in nk:
		var ufl: float = (float(fj[j]["cf"]) + float(fj[j]["hw"])) if j > 0 else uL
		var ubl: float = (float(fj[j]["cb"]) + float(fj[j]["hw"])) if j > 0 else uL
		var ufr: float = (float(fj[j + 1]["cf"]) - float(fj[j + 1]["hw"])) if j + 1 < nk else uR
		var ubr: float = (float(fj[j + 1]["cb"]) - float(fj[j + 1]["hw"])) if j + 1 < nk else uR
		var nl := float(foff[j])
		var nr_ := float(foff[j + 1])
		var P := [W.call(Vector2(ufl, -nl)), W.call(Vector2(ufr, -nr_)), W.call(Vector2(ubr, kdepth)), W.call(Vector2(ubl, kdepth))]
		var yk := y + rng.randf_range(0.014, 0.024)            # 敷石より必ず高い（敷石は y+0.007 以下）＝重なる所で框石が上に出る
		var ht := [yk - 0.012, yk - 0.012, yk, yk]
		_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		stone(sm, P, ht, yk + 0.005, ybot, rng.randf_range(0.006, 0.011), _mul(_tone(rng, false), 0.97), 1, Color(-1.0, 0.0, 0.0, 1.0), rng.randf_range(0.03, 0.05))
	# 敷石：ボロノイ（不規則な多角形）。領域は框石の下へ 6 cm 潜り、奥は次の段の蹴上の下へ 4 cm 潜る
	var vf := kdepth - 0.06
	var v1 := d + 0.04
	var cols := 3
	var rows := maxi(1, int(round((v1 - vf) / rng.randf_range(0.70, 0.95))))
	var cw_ := (uR - uL) / float(cols)
	var rh_ := (v1 - vf) / float(rows)
	var seeds: Array = []
	for r in rows:
		for c in cols:
			seeds.append(Vector2(uL + (float(c) + 0.5) * cw_ + rng.randf_range(-0.3, 0.3) * cw_, vf + (float(r) + 0.5) * rh_ + rng.randf_range(-0.3, 0.3) * rh_))
		if rng.randf() < 0.3:         # 小さな割り石〔楔になる石〕
			seeds.append(Vector2(rng.randf_range(uL + 0.2, uR - 0.2), vf + (float(r) + 0.5) * rh_ + rng.randf_range(-0.4, 0.4) * rh_))
	var dom := Rect2(Vector2(uL, vf), Vector2(uR - uL, v1 - vf))
	var cells := _voronoi(dom, seeds)
	for it in 8:
		# 小さすぎる割り石〔0.04 m² 未満〕は種ごと捨てて再計算＝そこに穴を残さない（r11 初版は面積で跳ばして最大 20 cm の穴を作った）
		var worst_i := -1
		var worst_a := 0.04
		for ci in cells.size():
			var ar := _poly_area(cells[ci])
			if ar < worst_a:
				worst_a = ar
				worst_i = ci
		if worst_i < 0 or seeds.size() <= 4:
			break
		seeds.remove_at(worst_i)
		cells = _voronoi(dom, seeds)
	var min_top := INF
	for ci in cells.size():
		var cell: PackedVector2Array = cells[ci]
		if cell.size() < 3:
			continue
		var groll := rng.randf()
		var gap := rng.randf_range(0.001, 0.002) if groll < 0.40 else (rng.randf_range(0.003, 0.006) if groll < 0.88 else rng.randf_range(0.007, 0.010))     # 石ごとの縮め量＝継ぎ目は隣り合う 2 石の和：緊貼〔35 %〕／普通〔45 %〕／開き〔20 %〕
		var inner := Geometry2D.offset_polygon(cell, -gap, Geometry2D.JOIN_MITER)
		if inner.is_empty():
			continue
		var pc := _largest(inner)
		var rc := rng.randf_range(0.012, 0.03)           # 角を丸める
		var shr := Geometry2D.offset_polygon(pc, -rc, Geometry2D.JOIN_MITER)
		if not shr.is_empty():
			var rnd := Geometry2D.offset_polygon(_largest(shr), rc, Geometry2D.JOIN_ROUND)
			if not rnd.is_empty():
				pc = _largest(rnd)
		if pc.size() < 3:
			continue
		var cen := Vector2.ZERO
		for q in pc:
			cen += q
		cen /= float(pc.size())
		var yy := y + rng.randf_range(-0.008, 0.002)
		var tu := rng.randf_range(-0.008, 0.008)
		var tv := rng.randf_range(-0.008, 0.008)
		var P: Array = []
		var ht: Array = []
		var s_ht := 0.0
		for q in pc:
			P.append(W.call(q))
			var hh2 := yy + tu * (q.x - cen.x) + tv * (q.y - cen.y) + rng.randf_range(-0.002, 0.002)
			ht.append(hh2)
			s_ht += hh2
			min_top = minf(min_top, hh2)
		var edge_c := cen.x < uL + 0.35 or cen.x > uR - 0.35
		_uvo = Vector2(rng.randf_range(0.0, 7.0), rng.randf_range(0.0, 7.0))
		var rch := rng.randf_range(0.004, 0.008)
		stone(sm, P, ht, s_ht / float(pc.size()) + rng.randf_range(0.002, 0.006), ybot, rch, _tone(rng, edge_c))
		# 土板：石の外形を gap＋4 mm 外へ広げた板を、面取りの下端より 4 mm 下に敷く＝石の下に隠れ、継ぎ目だけに見える。
		# 継ぎ目の側壁〔窄い縫の中は照らされず真っ黒になる〕を、砂利まじりの土で埋めて浅くする
		if not bool(flags.get("no_bed", false)):
			var plate := Geometry2D.offset_polygon(pc, gap + 0.004, Geometry2D.JOIN_MITER)
			if not plate.is_empty():
				var pl := _largest(plate)
				var drop := 0.75 * rch + 0.002 + float(flags.get("bed_off", 0.0)) * -1.0
				var pw: Array = []
				for q in pl:
					var w3: Vector2 = W.call(q)
					pw.append(Vector3(w3.x, yy + tu * (q.x - cen.x) + tv * (q.y - cen.y) - drop, w3.y))
				var cw3: Vector2 = W.call(cen)
				var cv := Vector3(cw3.x, yy - drop, cw3.y)
				var jw := _fill_w("joint")
				for qi in pl.size():
					_soil_tri(hm, cv, pw[qi], pw[(qi + 1) % pl.size()], jw, jw, jw)
	# 隙間の底：砂利まじりの土（地形と同じ材質）。石の面より 1.2 cm 下＝溝の底が浅く、暗い線にならない
	if not bool(flags.get("no_bed", false)) and min_top < INF:
		var by := min_top - 0.035 + float(flags.get("bed_off", 0.0))
		var bp := [W.call(Vector2(uL, 0.02)), W.call(Vector2(uR, 0.02)), W.call(Vector2(uR, d + 0.04)), W.call(Vector2(uL, d + 0.04))]
		_fill_quad(hm, Vector3(bp[0].x, by, bp[0].y), Vector3(bp[1].x, by, bp[1].y), Vector3(bp[2].x, by, bp[2].y), Vector3(bp[3].x, by, bp[3].y), _fill_w("joint"))
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


## 石階の外縁に被さる土坡〔笠石を置かない所、または笠石の外側〕：石階の端〔頂 −1.2 cm〕から外側地形へ、地形と同じ材質で緩く降りる。
## 外縁は地形の −3 cm に潜り接地線が出ない。外側地形が石階の端より高い所は、地形そのものが端に当たる＝何もしない（P13 W4B：笠石を全長に連ねて『石の枠』にしない）
static func _bank(hm: SurfaceTool, cl: PackedVector2Array, ka: int, kb: int, sd: float, edge: float, ta: float, tb: float, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array) -> int:
	var rows: Array = []
	var n_rows := 0
	for k in range(ka, kb + 2, 2):
		var kk := mini(k, kb)
		var t_k := tout[kk]
		var t_f := tfar[kk]
		var skip := is_nan(t_k) or is_nan(t_f)
		for ls in lanterns:
			if absf(float(kk) * 0.05 - float(ls)) < 1.1:
				skip = true
		var h0 := _line(kk, ka, kb, ta, tb) - 0.012
		if skip or t_k >= h0 - 0.015:
			rows.append(null)
			continue
		var t := SA.tangent(cl, kk)
		var nn := Vector2(-t.y, t.x) * sd
		var p0: Vector2 = cl[kk] + nn * (edge - 0.01)
		var p1: Vector2 = cl[kk] + nn * U_TERR
		var p2: Vector2 = cl[kk] + nn * U_FAR
		var pm: Vector2 = p0.lerp(p1, 0.5)
		rows.append([Vector3(p0.x, h0, p0.y),
			Vector3(pm.x, lerpf(h0, t_k + 0.008, 0.62), pm.y),
			Vector3(p1.x, t_k + 0.008, p1.y),
			Vector3(p2.x, t_f - 0.03, p2.y)])
		n_rows += 1
	var w_in := [Color(0.80, 0.0, 0.32, 0.04), Vector2(0.55, 0.0), Vector2(0.10, 0.0)]
	var w_mid := [Color(0.85, 0.0, 0.14, 0.04), Vector2(0.30, 0.0), Vector2(0.03, 0.0)]
	var w_out := [Color(0.85, 0.0, 0.0, 0.04), Vector2(0.06, 0.0), Vector2(0.0, 0.0)]
	var ws := [w_in, w_in, w_mid, w_out]
	for r in rows.size() - 1:
		if rows[r] == null or rows[r + 1] == null:
			continue
		var a: Array = rows[r]
		var b: Array = rows[r + 1]
		for q in 3:
			_soil_tri(hm, a[q], b[q], b[q + 1], ws[q], ws[q], ws[q + 1])
			_soil_tri(hm, a[q], b[q + 1], a[q + 1], ws[q], ws[q + 1], ws[q + 1])
	return n_rows


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
static func _wall_run_old(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, plan: Array, i: int, j: int, sd: float, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array, rng: RandomNumberGenerator) -> void:
	var ka := int(plan[i]["k0"])
	var kb := int(plan[j]["k1"])
	var key := "eR" if sd > 0.0 else "eL"
	var edge := 0.0
	for q in range(i, j + 1):
		edge = maxf(edge, float(plan[q][key]))
	# 笠石の頂線は踏面の頂より 1–4 cm 高い程度〔r12 まで 2.5–7 cm＝石階の両脇に連なる高い縁に見え、その内側の垂直面が黒い縦帯になっていた〕
	var ta := float(plan[i]["y0"]) + rng.randf_range(0.012, 0.04)
	var tb := float(plan[j]["y1"]) + rng.randf_range(0.012, 0.04)
	for q in range(i, j + 1):          # 各踏面の前縁で 頂線 ≥ 踏面頂 + 1 cm
		var kq := int(plan[q]["k0"])
		var deficit := float(plan[q]["y0"]) + 0.01 - _line(kq, ka, kb, ta, tb)
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
	# 外側の露出〔e_max＝笠石の頂線 − 外側地形の最大〕で処理を分ける：低＝笠石なし〔石階の端が土坡に埋もれる〕を多め／中＝薄い笠石〔欠けあり〕／高＝石垣。
	# 左右の側は別々に抽選する＝非対称。笠石を全長に連ねた『石の枠』を作らない
	var mode := "wall"
	if e_max < 0.10:
		mode = "bank" if rng.randf() < 0.62 else "cap"
	elif e_max < 0.30:
		mode = "cap"
	var n_lo := 0
	var n_mid := 0
	var n_hi := 0
	for k in range(ka, kb + 1):
		var tv2 := tout[k]
		if is_nan(tv2):
			continue
		var ex_k := _line(k, ka, kb, ta, tb) - tv2
		if ex_k < 0.12:
			n_lo += 1
		elif ex_k < 0.30:
			n_mid += 1
		else:
			n_hi += 1
	side_log.append({"sd": sd, "ka": ka, "kb": kb, "e_max": e_max, "mode": mode, "n_lo": n_lo, "n_mid": n_mid, "n_hi": n_hi,
		"i": i, "j": j, "edge": edge, "ta": ta, "tb": tb, "kind": String(plan[i]["kind"])})
	if mode != "wall":
		_bank(hm, cl, ka, kb, sd, edge, ta, tb, tout, tfar, lanterns)
	if mode == "bank":
		return
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
	var w_top := rng.randf_range(float(W_TOP[0]), float(W_TOP[1])) * (0.78 if mode == "cap" else 1.0)
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
			if c == 0 and n_c == 1 and rng.randf() < 0.20:
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
			var uf := u_face + (0.03 if big else 0.0) + rng.randf_range(-0.035, 0.03)
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


## P13 W5A の入口。Wave 5A の局所サンプル〔s=58.95–64.20〕に完全に入る run は、旧経路を scratch へ出力して乱数列だけ進め〔区間外の幾何を 1 ビットも変えない〕、
## run のパラメータを記録して W5A が連続した 1 枚の壁として作り直す。flags["w5a"]=false で W4B そのまま。
static func _wall_run(sm: SurfaceTool, hm: SurfaceTool, cl: PackedVector2Array, plan: Array, i: int, j: int, sd: float, tout: PackedFloat32Array, tfar: PackedFloat32Array, lanterns: Array, rng: RandomNumberGenerator) -> void:
	var ka := int(plan[i]["k0"])
	var kb := int(plan[j]["k1"])
	var W5 = w5()
	if W5.enabled and W5.in_sample(ka, kb):
		var dn := diag.size()
		var sn := soil_n
		var sc := SurfaceTool.new()
		sc.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hc := SurfaceTool.new()
		hc.begin(Mesh.PRIMITIVE_TRIANGLES)
		_wall_run_old(sc, hc, cl, plan, i, j, sd, tout, tfar, lanterns, rng)
		diag.resize(dn)
		soil_n = sn
		W5.record_run(sd, side_log[side_log.size() - 1])
		return
	_wall_run_old(sm, hm, cl, plan, i, j, sd, tout, tfar, lanterns, rng)


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
				# P13 W5C：踏面の端に cap_l／cap_r がある run は、端が変わる所で run を切る（壁が最も広い踏面に合わせて外に立たない）。乱数の消費は変えない
				var ckey := "cap_r" if sd > 0.0 else "cap_l"
				for q in range(i + 1, j + 1):
					if absf(float(plan[q].get(ckey, 9.0)) - float(plan[i].get(ckey, 9.0))) > 0.05:
						j = q - 1
						break
			_wall_run(sm, hm, cl, plan, i, j, sd, touts[si], tfars[si], lanterns, rng)
			i = j + 1


# ───────────────────────────── 組み立て ─────────────────────────────

## 石の mesh と土の裾の mesh。lanterns＝区間内の燈籠の s〔m〕（その近くには土を盛らない）
static func build_meshes(cl: PackedVector2Array, H: PackedFloat32Array, plan: Array, touts: Array, tfars: Array, lanterns: Array) -> Dictionary:
	diag.clear()
	side_log.clear()
	soil_n = 0
	var W5 = w5()
	W5.enabled = bool(flags.get("w5a", true))
	W5.integrated = bool(flags.get("w5b", true))
	W5.reset()
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hm := SurfaceTool.new()
	hm.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(flags.get("mesh_seed", SEED)) + 7
	# 前処理：各段の鼻先（次の段の蹴上までの見える奥行きを決める）
	var rp := RandomNumberGenerator.new()
	rp.seed = int(flags.get("mesh_seed", SEED)) + 3
	for a: Dictionary in plan:
		a["nose"] = rp.randf_range(-0.01, 0.02)      # 段ごとの前縁の前後（平均 +0.5 cm＝ほぼ零均値。突出は斜坡碰撞に対して石が早く立ち上がる〔足が沈む〕原因になる）
	var state := {"uL": -1.09, "uR": 1.09, "cuts": []}
	var y_prev := NAN
	for a: Dictionary in plan:
		if is_nan(y_prev):
			y_prev = float(flags.get("initial_y", H[int(a["k0"])]))
		if String(a["kind"]) == "landing":
			landing(sm, hm, cl, a, y_prev, H, state, rng)
		else:
			tread(sm, hm, cl, a, y_prev, H, state, rng)
		y_prev = float(a["y1"])
	build_sides(sm, hm, cl, plan, touts, tfars, lanterns, rng)
	if W5.enabled:
		W5.finish(sm, hm, cl, touts, tfars, lanterns)
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
	root.set_meta("phase", "P13 W5B integrated")
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
	w5().add_plants(root)          # P13 W5A：土坡の上の少量の草叢〔既存 veg_kit の instance〕
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
