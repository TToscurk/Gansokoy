extends RefCounted
## 人間之里 V2 P9 R5-3 — Upright Grass / Meadow Layer：全村擴張（2026-10-04 使用者裁定：Pilot p8＝ART_APPROVED_FOR_EXPANSION）。
## P9 の補完（P10 ではない）。既存の地面（base terrain → R5 Macro Ground Dressing、封存のまま）の上に載る第三層＝立ち草の叢。
##   - 叢 Kit：Pilot p8 と同一（立ち草 7＋羊歯＋笹、近級 20–80 三角形・中級は間引き＋幅広の低面）。
##   - 語意：封存 groundcover の規劃（GC.plan → VL.extend → ML.extend → MVL.extend）を讀み取り専用で再計算（村域 BB 內）、
##     村域 BB の外（村外の草地・林緣・斜面）は地形の塗り・林床層・水・田・路の距離場で判定（BB＋EXT_PAD）。
##   - 分布＝多尺度：Macro（8–30 m の群落區と大きな留白、domain warp）× Meso（2–8 m の次群落・缺口・突出）× Micro（縁を崩すだけ）。
##     語意密度 S が閾値を動かす（單一閾値の輪郭を作らない）；dense → medium → sparse → isolated → empty は不規則に移る。
##     群落（warp した cellular 14 m）ごとに dominant 1＋secondary 1–2＋accent；高さは局所の高さ群（short → medium → 時々 tall）。
##   - 禁止：等寬帶・完整な円／楕円の斑・規則的な點陣・樹ごとの草の輪・建物ごとの草の輪・道路の二本の草帯・小草で構圖を誤魔化す。
##   - 距離：近級 0–31 m（全株・影あり、24 m 分塊）→ 中級 23–54 m（間引き・幅広・影なし、48 m 分塊）→ 54 m 以遠は地面だけ。
##   - 高さ：可見最上面（地形・路面・P4 院子地面の max；MVL.top_h）に根元を 2 cm 沈める。
## Generator＝source of truth：verify_village_v2_meadow.gd -- --build（非 headless）→ gen/meadow_p9.scn → Vegetation/MeadowP9（GroundcoverP9 の後）。

const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const MVL := preload("res://tools/village_v2_groundcover_mvillage.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/meadow_p9.scn"
const NODE_NAME := "MeadowP9"
const SHADER := "res://assets/village_v2/meadow/meadow_grass.gdshader"
const ART_REVISION := "P9 R5-3 Upright Grass / Meadow Layer 全村 r6c targeted rework（語意密度台地に 25–40 m の濃淡・林緣／水際の沿線切れ目・後場の帯抑制・空き地の縁漸減・叢の傾き／幅ばらつき；ART_REVIEW）"
const SEED := 9311
const STEP := 0.33
const MAXP := 0.8
const SINK := 0.02
const EXT_PAD := 40.0
const NEAR_CHUNK := 24.0
const MID_CHUNK := 48.0
## 近級が縮んで消える帯／中級が伸びて現れる帯（同じ帯）／中級が消える帯（m、主相機 → 株の根元）
const NEAR_OUT := Vector2(23.0, 31.0)
const MID_OUT := Vector2(44.0, 54.0)
const MID_KEEP := 0.3

enum { K_SHORT, K_MEDIUM, K_TALL, K_SEED, K_DRY, K_LEAN, K_SPARSE, K_FERN, K_SASA }
const KIND_NAMES := ["short", "medium", "tall", "seed", "dry", "lean", "sparse", "fern", "sasa"]
## 網格を作るときの葉の長さ（m）；實際の叢の高さ（傾き・垂れの後）は kit()[k]["h"]（規劃・gate はこちらを使う）
const KIND_H := [0.2, 0.42, 0.62, 0.52, 0.42, 0.38, 0.26, 0.5, 0.4]
const GRASS_KINDS := [K_SHORT, K_MEDIUM, K_TALL, K_SEED, K_DRY, K_LEAN, K_SPARSE]

## 語意タグ（gate・機位選定用）
enum { T_OPEN, T_WILD, T_MEADOW, T_WALK, T_WORK, T_LOT, T_YARD, T_WALL, T_CORNER, T_ROAD, T_PATH, T_FARM, T_FARM_TR, T_FOREST, T_WATER, T_OUTSIDE }
const TAG_NAMES := ["open", "wild", "meadow", "walk", "work", "lot", "yard", "wall", "corner", "road", "path", "farm", "farm_tr", "forest", "water", "outside"]
## 環境（群落の種の制約）
enum { E_MEADOW, E_LOT, E_WALK, E_YARD, E_FARM, E_FOREST, E_WATER }
## 群落の種は群落 id だけで決める（環境をまたいでも同じ dominant を保つ）：[dominant, secondary, secondary2]
const PALETTES := [
	[K_MEDIUM, K_TALL, K_SEED],
	[K_TALL, K_MEDIUM, K_LEAN],
	[K_LEAN, K_MEDIUM, K_TALL],
	[K_SEED, K_TALL, K_MEDIUM],
	[K_MEDIUM, K_LEAN, K_SHORT],
	[K_TALL, K_SEED, K_LEAN],
	[K_MEDIUM, K_SHORT, K_TALL],
]
## 環境ごとに許す種（許されない種は ENV_FALLBACK に置き換え）
const ENV_ALLOW := [
	[K_MEDIUM, K_TALL, K_LEAN, K_SEED, K_SHORT, K_DRY],
	[K_MEDIUM, K_SHORT, K_DRY, K_LEAN, K_TALL, K_SEED],
	[K_SHORT, K_SPARSE, K_MEDIUM],
	[K_MEDIUM, K_SHORT, K_TALL, K_LEAN],
	[K_TALL, K_SEED, K_MEDIUM, K_LEAN],
	[K_TALL, K_MEDIUM, K_LEAN, K_SEED],
	[K_TALL, K_MEDIUM, K_LEAN],
]
const ENV_FALLBACK := [K_MEDIUM, K_MEDIUM, K_SHORT, K_MEDIUM, K_TALL, K_TALL, K_TALL]
const ENV_ACCENT := [K_SEED, K_TALL, K_MEDIUM, K_TALL, K_SEED, K_SEED, K_SEED]

static var _kit: Array = []


# ─────────────────────────── Kit（叢の網格） ───────────────────────────

## 一枚の葉：根元から segs 段の湾曲した細長い帯（幅は葉先へ 0）。三角形＝2(segs−1)+1。
##   lean＝根元の傾き（rad）、bend＝葉先までの追加の曲がり（rad、垂れ）。UV.y＝葉の割合、UV2＝(位相, 剛さ)
static func _blade(t: SurfaceTool, base: Vector3, az: float, lean: float, bend: float, length: float, w: float, segs: int,
		cb: Color, ct: Color, phase: float, stiff := 0.0, wprof := 0) -> void:
	var dir := Vector3(cos(az), 0.0, sin(az))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var pts: Array = []
	var p := base
	pts.append(p)
	for i in segs:
		var s := (float(i) + 0.5) / segs
		var th := lean + bend * s * s
		p += (dir * sin(th) + Vector3.UP * cos(th)) * (length / segs)
		pts.append(p)
	var rows: Array = []
	for i in segs:
		var s := float(i) / segs
		var ww := w
		if wprof == 0:
			ww = w * pow(1.0 - s, 0.7)
		else:
			# 羊歯の羽片／笹の葉：根元も細く中ほどが太い
			ww = w * (0.25 + 0.75 * sin(PI * (0.15 + 0.85 * s))) * (1.0 - 0.35 * s)
		rows.append([pts[i] - side * ww, pts[i] + side * ww, s])
	var tip: Vector3 = pts[segs]
	var tng := (tip - base).normalized()
	var fn := side.cross(tng).normalized()
	if fn.y < 0.0:
		fn = -fn
	var nrm := (fn * 0.45 + Vector3.UP * 0.75).normalized()
	var put := func(v: Vector3, s: float, u: float) -> void:
		t.set_color(cb.lerp(ct, smoothstep(0.25, 1.0, s)))
		t.set_uv(Vector2(u, s))
		t.set_uv2(Vector2(phase, stiff))
		t.set_normal(nrm)
		t.add_vertex(v)
	for i in segs - 1:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		put.call(a[0], a[2], 0.0)
		put.call(a[1], a[2], 1.0)
		put.call(b[0], b[2], 0.0)
		put.call(a[1], a[2], 1.0)
		put.call(b[1], b[2], 1.0)
		put.call(b[0], b[2], 0.0)
	var l: Array = rows[segs - 1]
	put.call(l[0], l[2], 0.0)
	put.call(l[1], l[2], 1.0)
	put.call(tip, 1.0, 0.5)


## 穂（細長い紡錘を十字に 2 枚）：4 三角形
static func _head(t: SurfaceTool, c: Vector3, az: float, len_: float, w: float, col: Color, phase: float) -> void:
	for k in 2:
		var a := az + k * PI * 0.5
		var side := Vector3(cos(a), 0.0, sin(a)) * w
		var lo := c - Vector3.UP * len_ * 0.5
		var hi := c + Vector3.UP * len_ * 0.5
		var quad := [lo, c - side, hi, lo, hi, c + side]
		for v: Vector3 in quad:
			t.set_color(col)
			t.set_uv(Vector2(0.5, 0.92 + 0.08 * (v.y - lo.y) / len_))
			t.set_uv2(Vector2(phase, 0.3))
			t.set_normal((Vector3.UP * 0.8 + side.normalized() * 0.3).normalized())
			t.add_vertex(v)


## 地形の草（畫面上 #566A43–#748052）に寄せた落ち着いた色：葉先の明るさは上 2 割だけ、黄味は控えめ
const G_BASE := Color(0.17, 0.22, 0.10)
const G_TIP := Color(0.42, 0.48, 0.24)
const D_BASE := Color(0.30, 0.28, 0.18)
const D_TIP := Color(0.64, 0.58, 0.38)


## 叢の網格（近級・中級）：[near, mid]、高さは公稱高（KIND_H）
static func kind_mesh(kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + kind * 97
	var hi := SurfaceTool.new()
	hi.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := SurfaceTool.new()
	lo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H: float = KIND_H[kind]
	match kind:
		K_SHORT, K_MEDIUM, K_TALL, K_DRY, K_SPARSE:
			# 2–3 本の株立ち（tiller）に分かれた叢：葉はほぼ立ち、上半分だけ任意の向きへ垂れる（放射状の扇＝星形にしない）
			var n: int = {K_SHORT: 20, K_MEDIUM: 22, K_TALL: 20, K_DRY: 20, K_SPARSE: 9}[kind]
			var rad: float = {K_SHORT: 0.1, K_MEDIUM: 0.12, K_TALL: 0.13, K_DRY: 0.13, K_SPARSE: 0.08}[kind]
			var w: float = {K_SHORT: 0.016, K_MEDIUM: 0.017, K_TALL: 0.018, K_DRY: 0.017, K_SPARSE: 0.015}[kind]
			var cb := D_BASE if kind == K_DRY else G_BASE
			var ct := D_TIP if kind == K_DRY else G_TIP
			var subs: Array = []
			for j in rng.randi_range(2, 3):
				var a0 := rng.randf() * TAU
				subs.append(Vector3(cos(a0), 0.0, sin(a0)) * rad * rng.randf_range(0.15, 0.6))
			for i in n:
				var sc0: Vector3 = subs[i % subs.size()]
				var a := rng.randf() * TAU
				var base := sc0 + Vector3(cos(a), 0.0, sin(a)) * rad * 0.35 * sqrt(rng.randf())
				var spill := 0.3 if (rng.randf() < 0.12) else 0.0
				var lean := rng.randf_range(0.03, 0.36) + spill + (0.2 if kind == K_DRY else 0.0)
				var bend := rng.randf_range(0.1, 0.6) * (1.8 if kind == K_DRY else 1.0)
				var ln := H * rng.randf_range(0.6, 1.05)
				var az := rng.randf() * TAU
				var tint := rng.randf_range(0.88, 1.08)
				var cbi := Color(cb.r * tint, cb.g * tint, cb.b * tint)
				var cti := ct.lerp(Color(0.50, 0.50, 0.30) if kind != K_DRY else Color(0.66, 0.60, 0.44), rng.randf_range(0.0, 0.35))
				_blade(hi, base, az, lean, bend, ln, w * rng.randf_range(0.8, 1.25), 2, cbi, cti, rng.randf())
				if i % 4 == 0 or (kind == K_SPARSE and i % 2 == 0):
					var cm := cbi.lerp(cti, 0.5)
					_blade(lo, base, az, lean, bend * 0.8, ln, w * 1.6, 1, cbi.lerp(cm, 0.5), cm, rng.randf())
		K_LEAN:
			# 一方向（+X）へ倒れた株：風・踏まれ・雨で寝た草の流れ（instance の yaw で流れの向きを揃える）
			for i in 14:
				var rr := sqrt(rng.randf()) * 0.12
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				var az := rng.randf_range(-0.45, 0.45)
				var lean := rng.randf_range(0.35, 0.8)
				var ln := H * rng.randf_range(0.75, 1.15)
				_blade(hi, base, az, lean, rng.randf_range(0.4, 1.0), ln, 0.019 * rng.randf_range(0.85, 1.2), 3, G_BASE, G_TIP.lerp(Color(0.56, 0.56, 0.32), rng.randf_range(0.0, 0.35)), rng.randf())
				if i % 3 == 0:
					_blade(lo, base, az, lean, 0.6, ln, 0.032, 1, G_BASE, G_TIP, rng.randf())
		K_SEED:
			# 穂草：根葉 8＋穂茎 5（先に紡錘形の穂；狗尾草・チガヤ・カゼクサ系）
			for i in 8:
				var rr := sqrt(rng.randf()) * 0.1
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				_blade(hi, base, a, rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 1.0), H * rng.randf_range(0.45, 0.65), 0.02, 2, G_BASE, G_TIP, rng.randf())
				if i % 3 == 0:
					_blade(lo, base, a, 0.5, 0.6, H * 0.55, 0.034, 1, G_BASE, G_TIP, rng.randf())
			for i in 5:
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * 0.03, 0.0, sin(a) * 0.03)
				var lean := rng.randf_range(0.05, 0.3)
				var ln := H * rng.randf_range(0.85, 1.05)
				var dir := Vector3(cos(a), 0.0, sin(a))
				_blade(hi, base, a, lean, 0.15, ln, 0.0065, 2, Color(0.30, 0.34, 0.17), Color(0.62, 0.62, 0.36), rng.randf(), 0.7)
				var top := base + (dir * sin(lean + 0.05) + Vector3.UP * cos(lean + 0.05)) * ln
				var hc := Color(0.62, 0.56, 0.40) if i % 2 == 0 else Color(0.50, 0.42, 0.34)
				_head(hi, top, a, rng.randf_range(0.07, 0.1), 0.014, hc, rng.randf())
				if i % 2 == 0:
					_blade(lo, base, a, lean, 0.1, ln, 0.01, 1, Color(0.30, 0.34, 0.17), Color(0.62, 0.62, 0.36), rng.randf(), 0.7)
					_head(lo, top, a, 0.1, 0.022, hc, rng.randf())
		K_FERN:
			# 羊歯：外へ弓なりに垂れる羽状の葉 6 枚（葉軸は硬め）
			for i in 6:
				var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
				var base := Vector3(cos(a) * 0.03, 0.0, sin(a) * 0.03)
				var ln := H * rng.randf_range(1.05, 1.35)
				var col_b := Color(0.13, 0.20, 0.08)
				var col_t := Color(0.36, 0.48, 0.20).lerp(Color(0.44, 0.50, 0.22), rng.randf())
				_blade(hi, base, a, rng.randf_range(0.35, 0.6), rng.randf_range(0.9, 1.4), ln, 0.075, 4, col_b, col_t, rng.randf(), 0.35, 1)
				if i % 2 == 0:
					_blade(lo, base, a, 0.5, 1.1, ln, 0.1, 2, col_b, col_t, rng.randf(), 0.35, 1)
		K_SASA:
			# 笹：細い稈 5 本、それぞれ先に 2–3 枚の披針形の葉（水平〜やや垂れ）
			for i in 5:
				var a := rng.randf() * TAU
				var base := Vector3(cos(a) * rng.randf_range(0.02, 0.12), 0.0, sin(a) * rng.randf_range(0.02, 0.12))
				var lean := rng.randf_range(0.05, 0.3)
				var ln := H * rng.randf_range(0.7, 1.05)
				var dir := Vector3(cos(a), 0.0, sin(a))
				_blade(hi, base, a, lean, 0.1, ln, 0.005, 1, Color(0.30, 0.34, 0.16), Color(0.42, 0.46, 0.22), rng.randf(), 0.9)
				var top := base + (dir * sin(lean) + Vector3.UP * cos(lean)) * ln
				for j in 3:
					var la := a + rng.randf_range(-1.6, 1.6)
					var at := top - Vector3.UP * (0.03 * j)
					_blade(hi, at, la, rng.randf_range(1.15, 1.45), rng.randf_range(0.2, 0.5), rng.randf_range(0.11, 0.16), 0.022, 2,
						Color(0.16, 0.24, 0.09), Color(0.34, 0.46, 0.17), rng.randf(), 0.5, 1)
					if j == 0:
						_blade(lo, at, la, 1.3, 0.3, 0.15, 0.034, 1, Color(0.16, 0.24, 0.09), Color(0.34, 0.46, 0.17), rng.randf(), 0.5, 1)
	return [hi.commit(), lo.commit()]


static func kit() -> Array:
	if _kit.is_empty():
		for k in KIND_NAMES.size():
			var m: Array = kind_mesh(k)
			var tn: int = (m[0] as ArrayMesh).surface_get_array_len(0) / 3
			var tm: int = (m[1] as ArrayMesh).surface_get_array_len(0) / 3
			var ab := (m[0] as ArrayMesh).get_aabb()
			_kit.append({"name": KIND_NAMES[k], "near": m[0], "mid": m[1], "tris": tn, "tris_mid": tm, "h": ab.end.y, "r": maxf(ab.size.x, ab.size.z) * 0.5})
	return _kit


# ─────────────────────────── 文脈 ───────────────────────────

static func ext_rect() -> Rect2:
	return VL.BB.grow(EXT_PAD)


static func _noise(seed: int, ntype: int, freq: float, oct: int, warp: float = 0.0, wfreq: float = 0.0) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = ntype
	n.frequency = freq
	if oct > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = oct
		n.fractal_gain = 0.5
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	if warp > 0.0:
		n.domain_warp_enabled = true
		n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		n.domain_warp_amplitude = warp
		n.domain_warp_frequency = wfreq
	return n


## 封存 groundcover の規劃 P に meadow 用の索引を足す：Props と NPC 立ち位置、植物節點、村域 BB の外の距離場・樹・封存 rect・P7 構件
static func context(P: Dictionary, v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var CV: Dictionary = P["CV"]
	var EXT := ext_rect()
	var MC := {"EXT": EXT}
	# Props（P10 の市集など）：足元と NPC activity anchors の周り 0.8 m には立てない（P10 の作業空間を壊さない）
	var PB := MVL.Bucket.new()
	PB.cs = 8.0
	var n_props := 0
	var pr := v.get_node_or_null("Props")
	if pr != null:
		for mi in pr.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or not g.is_visible_in_tree():
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.4)
			PB.add(r, r)
			n_props += 1
		for m in pr.find_children("*", "Marker3D", true, false):
			var q := Vector2((m as Node3D).global_position.x, (m as Node3D).global_position.z)
			var r2 := Rect2(q, Vector2.ZERO).grow(0.8)
			PB.add(r2, r2)
			n_props += 1
	MC["PB"] = PB
	MC["n_props"] = n_props
	# 植物節點（封存 groundcover の蕨・笹・低木・蘆・菅…、ForestP9 下層）
	var NB := MVL.Bucket.new()
	NB.cs = 4.0
	for it: Dictionary in P["nodes"]:
		var q: Vector2 = it["p"]
		var scv: Variant = it.get("sc", 1.0)
		var scf: float = (scv as Vector3).x if scv is Vector3 else float(scv)
		NB.add([q, 0.45 * scf + 0.25], Rect2(q, Vector2.ZERO).grow(1.2))
	# 樹（村外も含む）：ForestP9 の實ノード
	var th := {}
	var trees: Array = []
	var fnear := v.get_node_or_null("Vegetation/ForestP9/Near")
	if fnear != null:
		for ch in fnear.get_children():
			for t in ch.get_children():
				var nm := String(t.name)
				if not (t is Node3D) or nm.length() < 6 or nm[4] != "_":
					continue
				var tn := t as Node3D
				var p := Vector2(tn.global_position.x, tn.global_position.z)
				if not EXT.grow(8.0).has_point(p):
					continue
				var id := nm.substr(5)
				if GC.UNDER_IDS.any(func(u: String) -> bool: return id.begins_with(u)):
					NB.add([p, 0.6], Rect2(p, Vector2.ZERO).grow(1.2))
					continue
				var cr := 2.5 * tn.global_transform.basis.get_scale().x
				for mi in tn.find_children("LOD0", "MeshInstance3D", true, false):
					var ab := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					cr = 0.4 * maxf(ab.size.x, ab.size.z)
					break
				cr = clampf(cr, 1.2, 4.5)
				trees.append([p, cr])
				var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
				if not th.has(k):
					th[k] = []
				th[k].append([p, cr])
	MC["NB"] = NB
	MC["XT"] = {"tree_hash": th}
	MC["trees"] = trees
	# 村外の封存 rect（R4 Hero overlay・竹林）・障礙物（Landmarks／Districts）・P7 構件
	var SHX := VL.RectHash.new()
	for nm: String in GC.SEALED_OVERLAYS:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if EXT.intersects(r.grow(1.0)):
				SHX.add(r.grow(1.0) if String(g.name) != "Ground" else r.grow(0.5), "sealed")
	var bam := v.get_node_or_null("Vegetation/BambooP9/Near")
	if bam != null:
		for mi in bam.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if r.size.x < 20.0 and r.size.y < 20.0 and EXT.intersects(r.grow(VL.BAMBOO_PAD)):
				SHX.add(r.grow(VL.BAMBOO_PAD), "sealed")
	MC["SHX"] = SHX
	var OBX := VL.RectHash.new()
	for root_name in ["Districts", "Landmarks"]:
		for mi in v.get_node(root_name).find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or not g.is_visible_in_tree():
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if r.size.x > 30.0 or r.size.y > 30.0 or not EXT.intersects(r) or a.size.y < 0.08 or VL.BB.encloses(r):
				continue
			OBX.add(r, "obstacle")
	MC["OBX"] = OBX
	var RBX := VL.RectHash.new()
	var RBSX := RLib.TriSampler.new()
	for mi in v.get_node("Riverbank").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null:
			continue
		var a := g.global_transform * g.get_aabb()
		var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		if not EXT.intersects(r.grow(1.5)) or VL.BB.grow(-2.0).encloses(r):
			continue
		RBX.add(r.grow(1.0), "rb")
		if g.visibility_range_begin <= 0.001:
			RBSX.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	var bridges := v.get_node_or_null("Roads/Bridges")
	if bridges != null:
		for mi in bridges.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var a := g.global_transform * g.get_aabb()
			if EXT.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(1.0)) and not VL.BB.grow(-2.0).encloses(Rect2(a.position.x, a.position.z, a.size.x, a.size.z)):
				RBSX.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	MC["RBX"] = RBX
	MC["RBSX"] = RBSX
	# 村外の地形の塗り（草・林床）と距離場（1 m）
	var TWX := GC.TerrainW.new()
	for nm in ["Terrain/MainTerrain", "Terrain/NorthHill", "Terrain/RiverTerrain"]:
		var tm := v.get_node_or_null(nm) as MeshInstance3D
		if tm != null:
			TWX.add(tm, RLib.rel_xf(tm, v), EXT.grow(2.0))
	MC["TWX"] = TWX
	var S: RLib.TriSampler = CV["S"]
	var WS: RLib.TriSampler = CV["WS"]
	var R: RLib.TriSampler = CV["R"]
	var FS: RLib.TriSampler = CV["FS"]
	var sx := GC.DGrid.new()
	sx.build(EXT, 1.0, func(q: Vector2) -> bool:
		var w := TWX.weights(q)
		return not w.is_empty() and w[4] >= 0.5)
	MC["seamX"] = sx
	var wx := GC.DGrid.new()
	wx.build(EXT, 1.0, func(q: Vector2) -> bool:
		var wh := WS.h(q.x, q.y)
		return not is_nan(wh) and wh > S.h(q.x, q.y) + 0.02)
	MC["waterX"] = wx
	var rx := GC.DGrid.new()
	rx.build(EXT, 1.0, func(q: Vector2) -> bool: return not is_nan(R.h(q.x, q.y)))
	MC["roadX"] = rx
	var fx := GC.DGrid.new()
	fx.build(EXT, 1.0, func(q: Vector2) -> bool: return not is_nan(FS.h(q.x, q.y)))
	MC["farmX"] = fx
	# 多尺度 noise（決定的）
	MC["nMacro"] = _noise(SEED + 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 20.0, 3, 13.0, 1.0 / 45.0)
	MC["nMeso"] = _noise(SEED + 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 4.5, 2, 2.5, 1.0 / 9.0)
	MC["nMicro"] = _noise(SEED + 3, FastNoiseLite.TYPE_VALUE, 1.0 / 0.9, 1)
	MC["nHeight"] = _noise(SEED + 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 5.0, 2)
	var nc := _noise(SEED + 5, FastNoiseLite.TYPE_CELLULAR, 1.0 / 14.0, 1, 7.0, 1.0 / 30.0)
	nc.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	nc.cellular_jitter = 1.0
	MC["nComm"] = nc
	MC["nReach"] = _noise(SEED + 6, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 9.0, 2)
	MC["nLean"] = _noise(SEED + 7, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 9.0, 1)
	MC["ms"] = Time.get_ticks_msec() - t0
	return MC


static func n01(n: FastNoiseLite, p: Vector2) -> float:
	return clampf(0.5 + 0.5 * n.get_noise_2d(p.x, p.y), 0.0, 1.0)


## 多尺度の群落値（0–1）：Macro 0.62＋Meso 0.28＋Micro 0.10（境界は單一閾値の滑らかな輪郭にならない）
static func comm_v(MC: Dictionary, p: Vector2) -> float:
	return 0.62 * n01(MC["nMacro"], p) + 0.28 * n01(MC["nMeso"], p) + 0.1 * n01(MC["nMicro"], p)


## 群落 id（warp した cellular の cell 値、−1..1 を 0..4095 に量子化）と 0–1 値
static func comm_id(MC: Dictionary, p: Vector2) -> int:
	return clampi(int((0.5 + 0.5 * (MC["nComm"] as FastNoiseLite).get_noise_2d(p.x, p.y)) * 4095.0), 0, 4095)


static func near_plant(MC: Dictionary, p: Vector2) -> bool:
	for e: Array in (MC["NB"] as MVL.Bucket).at(p):
		if (e[0] as Vector2).distance_to(p) < float(e[1]):
			return true
	return false


static func on_prop(MC: Dictionary, p: Vector2) -> bool:
	for r: Rect2 in (MC["PB"] as MVL.Bucket).at(p):
		if r.has_point(p):
			return true
	return false


static func inside(p: Vector2) -> bool:
	return VL.BB.has_point(p)


## VL.blocked_v の Pilot 區（r10f）判定を飛ばした版（Pilot 區の中でも建物・路・水などは同じ規則で除く）
static func _blocked_core(CV: Dictionary, p: Vector2) -> String:
	if not is_nan((CV["FS"] as RLib.TriSampler).h(p.x, p.y)):
		return "farm"
	if VL.wall_d(CV, p) < 0.05:
		return "building"
	if GC.trunk_d(CV, p) < 0.4:
		return "trunk"
	var ob := (CV["OB"] as VL.RectHash).hit(p)
	if ob != "":
		return ob
	var sh := (CV["SH"] as VL.RectHash).hit(p)
	if sh != "":
		return sh
	if (CV["RB"] as VL.RectHash).hit(p) != "" and GC.wdist(CV, p) <= GC.RB_CORE:
		return "riverbank"
	if VL.p7_covered(CV, p):
		return "p7piece"
	if VL.on_road(CV, p):
		return "road"
	var wh := (CV["WS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(wh) and wh > (CV["S"] as RLib.TriSampler).h(p.x, p.y) - 0.02:
		return "water"
	return ""


## 置けない理由（空＝可）
static func blocked(P: Dictionary, MC: Dictionary, p: Vector2) -> String:
	var CV: Dictionary = P["CV"]
	if not (MC["EXT"] as Rect2).has_point(p):
		return "ext"
	if on_prop(MC, p):
		return "props"
	if near_plant(MC, p):
		return "plant"
	if GC.trunk_d(MC["XT"], p) < 0.55:
		return "trunk"
	if inside(p):
		var br := VL.blocked_v(CV, p, false, 0.35, true)
		if br == "pilot":
			br = _blocked_core(CV, p)
		if br != "":
			return br.get_slice(":", 0)
		if MVL.sealed(CV, p):
			return "sealed"
		if VL.wall_d(CV, p) < 0.75:
			return "eave"
		if VL.road_sd(CV, p) < 0.2:
			return "road"
		if _path_x(P, p) < 0.0:
			return "path"
		return ""
	# 村域 BB の外
	var S: RLib.TriSampler = CV["S"]
	var hs := S.h(p.x, p.y)
	if is_nan(hs):
		return "terrain"
	if not is_nan((CV["FS"] as RLib.TriSampler).h(p.x, p.y)):
		return "farm"
	if (MC["SHX"] as VL.RectHash).hit(p) != "":
		return "sealed"
	if (MC["OBX"] as VL.RectHash).hit(p) != "":
		return "obstacle"
	var wd := maxf((MC["waterX"] as GC.DGrid).at(p), 0.0)
	if (MC["RBX"] as VL.RectHash).hit(p) != "" and wd <= GC.RB_CORE:
		return "riverbank"
	var rh := (MC["RBSX"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(rh) and rh > hs - 0.03:
		return "p7piece"
	if not is_nan((CV["R"] as RLib.TriSampler).h(p.x, p.y)) or (MC["roadX"] as GC.DGrid).at(p) < 0.2:
		return "road"
	var wh := (CV["WS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(wh) and wh > hs - 0.02:
		return "water"
	return ""


## 小径までの距離（m、芯の外＝＋）：Macro Pilot 區の中は m9 の小径、外は全村 Macro の小径
static func _path_x(P: Dictionary, p: Vector2) -> float:
	var d: float = MVL.path_d(P["MV"], p).x
	var zn := ML.zone_of(p)
	if zn != "":
		d = minf(d, ML.path_d((P["M"] as Dictionary)["zones"][zn], p).x)
	return d


static func _spot(P: Dictionary, p: Vector2) -> float:
	var k: float = MVL.spot_k(P["MV"], p)[0]
	var zn := ML.zone_of(p)
	if zn != "":
		k = maxf(k, float(ML.spot_k((P["M"] as Dictionary)["zones"][zn], p)[0]))
	return k


## 路縁・小径からの立ち上がり（等寬の帯にしない：始まりと幅を沿線 noise で揺らす；縁に峰を作らない單調増加）
## 縁の距離を Meso（~9 m 波長）で歪める：林緣・水際・田の縁の帯を 2–8 m の舌・湾・缺口に崩す（一本の等寬帯にしない）
static func _warp_d(MC: Dictionary, p: Vector2, d: float, amp: float, off: Vector2) -> float:
	return d + amp * (2.0 * n01(MC["nMeso"], p * 0.5 + off) - 1.0) + 0.5 * amp * (2.0 * n01(MC["nMacro"], p * 1.6 + off * 0.3) - 1.0)


static func _edge_ramp(MC: Dictionary, p: Vector2, d: float, r0: float, r1: float, w0: float, w1: float) -> float:
	var a := n01(MC["nReach"], p)
	var b := n01(MC["nReach"], p * 1.7 + Vector2(311.0, 97.0))
	var start := lerpf(r0, r1, a)
	return smoothstep(start, start + lerpf(w0, w1, b), d)


## 地點の語意（村域 BB 內）→ [S 語意密度 0–1, H 目標丈 m, dry, lush, fern, sasa, corner, tag, env]
static func site_in(P: Dictionary, MC: Dictionary, p: Vector2) -> Array:
	var CV: Dictionary = P["CV"]
	var MV: Dictionary = P["MV"]
	var S := 0.6
	var H := 0.4
	var tag := T_OPEN
	var env := E_MEADOW
	var dry := 0.0
	var lush := 0.0
	var fern := 0.0
	var sasa := 0.0
	# ① 小區の語意：常走・半荒・村邊草地・臨時作業・未使用留白（＝空き地：草が伸びる）
	var bi := MVL.block_at(MV, p)
	if bi >= 0:
		var sa := MVL.sub_at(MV, p, bi)
		var seeds: Array = MV["seeds"]
		var c1: int = MVL.eff_cls(P, seeds[int(sa[0])])
		var c2: int = MVL.eff_cls(P, seeds[int(sa[1])])
		var t: float = sa[2]
		const SC := [0.34, 0.84, 0.94, 0.3, 0.66]
		const HCL := [0.2, 0.44, 0.5, 0.24, 0.38]
		S = SC[c1] * t + SC[c2] * (1.0 - t)
		H = HCL[c1] * t + HCL[c2] * (1.0 - t)
		tag = [T_WALK, T_WILD, T_MEADOW, T_WORK, T_LOT][c1]
		env = [E_WALK, E_MEADOW, E_MEADOW, E_WALK, E_LOT][c1]
	elif ML.zone_of(p) != "":
		# Macro Pilot 區（m9）：後場・作業の多い區。開けた草は建物から離れるほど
		S = 0.5 * smoothstep(6.0, 18.0, MVL.bdist(CV, MV, p))
		H = 0.34
		env = E_LOT
		tag = T_LOT
	# ② 建物：軒下〜跳ね返りの帯は角・路地・北面（陰）・排水の外だけ、後場（〜12 m）の芯は空ける、村はずれは徐々に野へ
	var bw := MVL.bdist(CV, MV, p)
	var corner := 0.0
	if bw < 12.0:
		var ek := MVL.edge_k_mv(P, p)
		var zm := ML.zone_of(p)
		if zm != "":
			ek = maxf(ek, ML.edge_k(P, zm, p))
		# 北向きの壁（陰）・雨落ちの外（1.35–2.6 m、跳ね返りの濕った土）：壁沿いの noise で斷續（一周させない）
		var wn := MVL.wall_near(MV, p)
		if wn[1] != null and float(wn[0]) > 1.35 and float(wn[0]) < 2.8:
			var w: ML.Wall = wn[1]
			var shade := smoothstep(0.2, 0.8, -w.n.y)
			var seg := smoothstep(0.55, 0.72, n01(MC["nReach"], Vector2(float(wn[2]) * 0.35, float(w.bld.hash() % 211))))
			ek = maxf(ek, 0.75 * shade * seg)
		corner = ek
		if bw < 2.2:
			S = 0.8 * ek
			H = lerpf(0.2, 0.42, ek)
			tag = T_WALL
		else:
			var yk := smoothstep(2.2, 12.0, bw)
			S = maxf(S * lerpf(0.06, 1.0, yk * yk), 0.75 * ek)
			H = maxf(H * lerpf(0.65, 1.0, yk), lerpf(0.26, 0.42, ek))
			if yk < 0.45:
				tag = T_YARD
		if bw < 12.0:
			env = E_YARD
		if ek > 0.35:
			tag = T_CORNER
	else:
		# 人工空間 → 野：12–45 m で徐々に（0 → 100 % を急に変えない）
		var ok := smoothstep(12.0, 45.0, bw)
		S = minf(1.0, S * lerpf(0.85, 1.06, ok))
		H += 0.08 * ok
	# ④ 農田の外緣：田の縁から 1.2–6 m（2 オクターブで揺らぐ）、住宅側へ疎らに（建物の 4–10 m 手前で消える）
	var fd := MVL.fdist(MV, p)
	var farm := _farm_band(MC, p, fd, bw) * smoothstep(1.5, 4.0, bw)
	if farm.x > 0.0 or farm.y > 0.0:
		S = maxf(S, maxf(0.95 * farm.x, S + (0.6 - S) * farm.y))
		H = lerpf(H, 0.56, maxf(farm.x, 0.6 * farm.y))
		if farm.x > 0.4:
			tag = T_FARM
			env = E_FARM
		elif farm.y > 0.3 and tag != T_WALL and tag != T_CORNER:
			tag = T_FARM_TR
		dry = maxf(dry, 0.3 * farm.x * n01(MC["nHeight"], p * 0.4))
	# ⑤ 林緣・⑥ 溪岸
	var ew := GC.wdist(CV, p) - GC.RB_CORE
	var fr := _forest_water(P, MC, p, GC.seam_d(CV, p), ew, VL.bank_nat(CV, p) if ew < 6.5 else 0.5)
	var ret := _merge_fw(fr, S, H, smoothstep(2.2, 12.0, bw))
	if int(ret[0]) == 1:
		S = ret[1]
		H = ret[2]
		fern = ret[3]
		sasa = ret[4]
		lush = maxf(lush, ret[5])
		if int(ret[6]) >= 0 and tag != T_CORNER:
			tag = int(ret[6])
			env = E_FOREST if tag == T_FOREST else E_WATER
	# ③ 路・小径・作業地面・路口の扇（最後に掛ける＝農路・作業面は常に空く；二本の帯を作らない單調な立ち上がり）
	var rsd := VL.road_sd(CV, p)
	var rr := _edge_ramp(MC, p, rsd, 0.25, 1.8, 1.6, 5.5)
	S *= rr
	H *= lerpf(0.55, 1.0, rr)
	if rsd < 1.3:
		tag = T_ROAD
		env = E_WALK
	var pdx := _path_x(P, p)
	var pr := _edge_ramp(MC, p + Vector2(57.0, 13.0), pdx, 0.15, 0.9, 1.0, 3.2)
	S *= pr
	H *= lerpf(0.55, 1.0, pr)
	if pdx < 0.9:
		tag = T_PATH
		env = E_WALK
	S *= 1.0 - 0.95 * _spot(P, p)
	S *= 1.0 - 0.9 * MVL.apron_k(MV, p).x
	return [S, H, dry, lush, fern, sasa, corner, tag, env]


## 林緣・溪岸の結果を合成：[変更あり, S, H, fern, sasa, lush, tag]；yk＝後場からの離れ（後場の芯には林緣・水際の草も入れない）
static func _merge_fw(fr: Array, S: float, H: float, yk: float) -> Array:
	var fS: float = fr[0]
	if fS < 0.0:
		return [0, S, H, 0.0, 0.0, 0.0, -1]
	# r6：後場（建物 12 m 内）では水際・林緣の帯を yk² で抑える（G_yard_2：水渠沿いの帯が作業地面を斜めに横切った）
	var S2 := fS if float(fr[6]) > 0.5 else maxf(S, fS * yk * yk)
	var H2 := maxf(H, float(fr[1])) if float(fr[1]) > 0.0 else H
	return [1, S2, H2, fr[2], fr[3], fr[4], fr[5]]


## 村域 BB の外：地形が草として塗られた所＝村外の自然草地（林緣・溪岸・田・路は同じ規則）
static func site_out(P: Dictionary, MC: Dictionary, p: Vector2) -> Array:
	var S := 0.92
	var H := 0.52
	var tag := T_OUTSIDE
	var env := E_MEADOW
	var lush := 0.0
	var fern := 0.0
	var sasa := 0.0
	var rd := (MC["roadX"] as GC.DGrid).at(p)
	var rr := _edge_ramp(MC, p, rd, 0.25, 1.8, 1.6, 5.5)
	H *= lerpf(0.55, 1.0, rr)
	if rd < 1.3:
		tag = T_ROAD
		env = E_WALK
	var fd := (MC["farmX"] as GC.DGrid).at(p)
	var farm := _farm_band(MC, p, fd, 99.0)
	var dry := 0.0
	if farm.x > 0.0 or farm.y > 0.0:
		S = maxf(S, 0.95 * farm.x)
		H = lerpf(H, 0.56, farm.x)
		if farm.x > 0.4:
			tag = T_FARM
			env = E_FARM
		dry = 0.3 * farm.x * n01(MC["nHeight"], p * 0.4)
	var e := maxf((MC["waterX"] as GC.DGrid).at(p), 0.0) - GC.RB_CORE
	var fr := _forest_water(P, MC, p, -(MC["seamX"] as GC.DGrid).at(p), e, 0.7)
	var ret := _merge_fw(fr, S, H, 1.0)
	if int(ret[0]) == 1:
		S = ret[1]
		H = ret[2]
		fern = ret[3]
		sasa = ret[4]
		lush = maxf(lush, ret[5])
		if int(ret[6]) >= 0:
			tag = int(ret[6])
			env = E_FOREST if tag == T_FOREST else E_WATER
	S *= rr
	return [S, H, dry, lush, fern, sasa, 0.0, tag, env]


## 農田の外緣：Vector2(帯 0–1, 住宅側への漸減 0–1)
static func _farm_band(MC: Dictionary, p: Vector2, fd: float, bw: float) -> Vector2:
	if fd <= 0.25 or fd > 18.0:
		return Vector2.ZERO
	var reach := 1.2 + 4.8 * n01(MC["nReach"], p * 0.6 + Vector2(17.0, 3.0))
	var fw := _warp_d(MC, p, fd, 1.6, Vector2(7.0, 61.0))
	var band := smoothstep(0.25, 0.7, fd) * (1.0 - smoothstep(reach - 1.5, reach + 2.0, fw))
	# 帯の途切れ（6–15 m 波長）：固定幅の帯にしない
	band *= smoothstep(0.4, 0.6, n01(MC["nMacro"], p * 1.3 + Vector2(91.0, 7.0)))
	var tr := (1.0 - smoothstep(reach, reach + 10.0, fd)) * smoothstep(0.25, 0.7, fd) * smoothstep(4.0, 10.0, bw)
	return Vector2(band, tr)


## 林緣（seam：林床側＋、草側−）と溪岸（e：P7 核心の外の水際距離）
##   → [S（−1＝変更なし）, H（0＝変更なし）, fern, sasa, lush, tag（−1＝なし）, 林床で上書きか(1/0)]
static func _forest_water(_P: Dictionary, MC: Dictionary, p: Vector2, sd: float, e: float, nat: float) -> Array:
	var S := -1.0
	var H := 0.0
	var fern := 0.0
	var sasa := 0.0
	var lush := 0.0
	var tag := -1
	var over := 0.0
	sd = _warp_d(MC, p, sd, 3.2, Vector2(41.0, 9.0))
	if sd > -16.0:
		if sd > 3.0:
			# 林床（落葉）：羊歯が少し入るだけ、草は立てない
			S = 0.3 * (1.0 - smoothstep(3.0, 5.0, sd))
			over = 1.0
			fern = 0.7
			tag = T_FOREST
		elif sd > -1.5:
			# 林縁の芯も一様に埋めない（Meso で 0.55–0.92）。r6：沿線 ~36 m 波長の大きな切れ目（芯でも 0.12 まで下がる）
			#   ＝林に沿う連続した一本の帯にしない（v5c 審圖：B_edge_2・C_forest_2 の「帯」）
			var gapF := smoothstep(0.3, 0.62, n01(MC["nMacro"], p * 0.55 + Vector2(17.0, 203.0)))
			S = lerpf(0.12, 0.55 + 0.37 * n01(MC["nMeso"], p * 0.8 + Vector2(3.0, 77.0)), gapF)
			H = 0.48
			fern = 0.3 + 0.25 * n01(MC["nMeso"], p * 0.5)
			sasa = 0.4 * smoothstep(0.45, 0.7, n01(MC["nComm"], p * 0.7))
			tag = T_FOREST
		else:
			var reach := 3.0 + 12.0 * n01(MC["nReach"], p * 0.7 + Vector2(5.0, 41.0))
			# 林緣の草帯も沿線で途切れる（林に沿う一本の帯にしない）
			var kf := (1.0 - smoothstep(1.5, reach, -sd)) * smoothstep(0.3, 0.55, n01(MC["nMacro"], p * 1.1 + Vector2(33.0, 71.0))) 				* lerpf(0.25, 1.0, smoothstep(0.3, 0.62, n01(MC["nMacro"], p * 0.55 + Vector2(17.0, 203.0))))
			if kf > 0.0:
				S = 0.35 + 0.5 * kf
				H = lerpf(0.0, 0.52, kf)
				fern = 0.1 * (1.0 - smoothstep(1.5, 4.0, -sd))
				if kf > 0.45:
					tag = T_FOREST
	var ew := _warp_d(MC, p, e, 2.0, Vector2(83.0, 29.0)) if e > 0.9 else e
	if ew < 10.0:
		# 内陸側は 3–4 m かけて疎らへ（切り抜いた帯の縁にしない）
		var wk := smoothstep(0.3, 0.9, e) * (1.0 - smoothstep(lerpf(1.2, 3.5, nat), lerpf(4.5, 8.5, nat), ew))
		# r6：水際の帯も沿線 ~36 m 波長で切れる（洗い場・石の岸・踏み跡の間は低い草だけ；E_stream_2 の「帯」）
		wk *= lerpf(0.15, 1.0, smoothstep(0.3, 0.62, n01(MC["nMacro"], p * 0.55 + Vector2(131.0, 59.0))))
		if wk > 0.0:
			S = maxf(S, 0.85 * wk)
			H = maxf(H, 0.5 * wk)
			lush = wk
			if wk > 0.4:
				tag = T_WATER
				over = 0.0
	return [S, H, fern, sasa, lush, tag, over]


## Macro 地面・林緣／溪岸の地面重み・Pilot r10f 地面：Vector4(立てない量, 枯れ, 濃い草, 踏まれ)
static func ground_k(P: Dictionary, p: Vector2) -> Vector4:
	var bare := 0.0
	var dry := 0.0
	var lush := 0.0
	var worn := 0.0
	for src in 2:
		var w: Variant = MVL.ground_mv(P, p) if src == 0 else ML.ground_m(P, p)
		if w == null:
			continue
		var f: float = (w[1] as Vector2).y
		var c: Color = w[0]
		var u: Vector2 = w[2]
		var d: Vector2 = w[3]
		bare += (c.r * 0.9 + c.b + c.a + u.y + (float(w[4]) if src == 0 else 0.0) + u.x * 0.5) * f
		dry += d.x * f
		worn += d.y * f
		lush += c.g * f
	var mm := VL.memb(P["CV"], p)
	for cls: String in ["forest", "stream"]:
		if (mm.y if cls == "forest" else mm.z) < 0.02:
			continue
		var g: Variant = VL.ground_w_v(P, p, cls)
		if g == null:
			continue
		var c2: Color = g[0]
		var u2: Vector2 = g[2]
		var f2: float = (g[1] as Vector2).y
		bare += (c2.r * 0.8 + c2.b * 0.8 + c2.a * 0.75 + u2.x * 0.6 + u2.y) * f2
		lush = maxf(lush, c2.g * 0.6 * f2)
	if GC.zone_of(p) != "":
		var g3: Variant = GC.ground_w(P, p)
		if g3 != null:
			var c3: Color = g3[0]
			var u3: Vector2 = g3[2]
			var f3: float = (g3[1] as Vector2).y
			bare += (c3.r * 0.8 + c3.b + c3.a * 0.75 + u3.x * 0.6 + u3.y) * f3
			lush = maxf(lush, c3.g * 0.6 * f3)
	return Vector4(bare, dry, lush, worn)


# ─────────────────────────── 1 m 場（語意密度・丈・種の環境を先に計算） ───────────────────────────

## F＝{nx, nz, o, blk, S, H, DRY, LUSH, FERN, SASA, CORN, TAG, ENV}；blk＝1 は禁區
static func fields(P: Dictionary, MC: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var CV: Dictionary = P["CV"]
	var EXT: Rect2 = MC["EXT"]
	var nx := int(ceil(EXT.size.x))
	var nz := int(ceil(EXT.size.y))
	var n := nx * nz
	var F := {"nx": nx, "nz": nz, "o": EXT.position}
	var blk := PackedByteArray()
	blk.resize(n)
	var aS := PackedFloat32Array()
	aS.resize(n)
	var aH := PackedFloat32Array()
	aH.resize(n)
	var aD := PackedFloat32Array()
	aD.resize(n)
	var aL := PackedFloat32Array()
	aL.resize(n)
	var aF := PackedFloat32Array()
	aF.resize(n)
	var aA := PackedFloat32Array()
	aA.resize(n)
	var aC := PackedFloat32Array()
	aC.resize(n)
	var aT := PackedByteArray()
	aT.resize(n)
	var aE := PackedByteArray()
	aE.resize(n)
	var TWX: GC.TerrainW = MC["TWX"]
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var c := EXT.position + Vector2(i + 0.5, j + 0.5)
			if blocked(P, MC, c) != "":
				blk[k] = 1
				continue
			var s: Array
			var G := 0.0
			var gk := Vector4.ZERO
			if inside(c):
				G = maxf(smoothstep(0.3, 0.58, GC.grass_w(CV, c)), 0.3 * VL.dirt_inv(CV, c))
				if G < 0.005 and VL.wall_d(CV, c) > 3.0:
					continue
				s = site_in(P, MC, c)
				gk = ground_k(P, c)
			else:
				G = smoothstep(0.3, 0.58, TWX.grass(c))
				if G < 0.005:
					continue
				s = site_out(P, MC, c)
			var corner: float = s[6]
			# 地形が草として塗られた所（または後院の荒れた隅）だけ；地面語言（踏み固め・砂利・木屑・路の色・雨落ち）の上には立てない
			var Sx: float = float(s[0]) * maxf(G, corner)
			Sx *= 1.0 - smoothstep(0.18, 0.55, gk.x * (1.0 - 0.5 * corner))
			Sx *= 1.0 - 0.6 * gk.w
			# r6b：語意密度の台地（村外草地 S＝0.92 一定・村內の半荒／村邊草地 0.84–0.94）に 25–40 m の大きな濃淡を掛ける
			#   （transect 實測：塗りが草の所では株數が 0 → 13 本／m² に 2 m で跳ね、そのまま一様＝「帯」「島」の正体）。
			#   下限 0.68 倍（r6b の 0.55 は斜面・田の岬・草地近景で痩せすぎ＝r6c）＝疎らになるが平坦な芝にはしない（留白比例を目標にしない裁定）
			Sx *= lerpf(0.68, 1.0, smoothstep(0.25, 0.7, n01(MC["nMacro"], c * 0.45 + Vector2(271.0, 113.0))))
			aS[k] = clampf(Sx, 0.0, 1.0)
			aH[k] = float(s[1]) * lerpf(0.65, 1.0, maxf(G, corner)) * (1.0 - 0.45 * gk.w)
			aD[k] = maxf(float(s[2]), gk.y)
			aL[k] = maxf(float(s[3]), gk.z)
			aF[k] = s[4]
			aA[k] = s[5]
			aC[k] = corner
			aT[k] = s[7]
			aE[k] = s[8]
	# Packed 配列の値渡しに依存しない：戻り値で受け直す
	var sp := _spill(P, MC, F, blk, aS, aH, aT, aE, aD, nx, nz)
	aS = sp[0]
	aH = sp[1]
	aT = sp[2]
	aE = sp[3]
	aD = sp[4]
	F["blk"] = blk
	F["S"] = aS
	F["H"] = aH
	F["DRY"] = aD
	F["LUSH"] = aL
	F["FERN"] = aF
	F["SASA"] = aA
	F["CORN"] = aC
	F["TAG"] = aT
	F["ENV"] = aE
	F["ms"] = Time.get_ticks_msec() - t0
	return F


## 縁のこぼれ（v5b）：草の塗りが終わった先の裸地へ 0–4 m、疎らな先駆け株を侵食 noise で斷續的に出す
##   （草帯の前縁を「切り抜いた縁」にしない：dense → sparse → isolated tufts → empty）。
##   後場（建物 12 m 内）・路の 3 m 内・作業地面の芯・踏まれた地面・apron には出さない（Macro Ground の留白を守る）
static func _spill(P: Dictionary, MC: Dictionary, F: Dictionary, blk: PackedByteArray, aS: PackedFloat32Array, aH: PackedFloat32Array,
		aT: PackedByteArray, aE: PackedByteArray, aD: PackedFloat32Array, nx: int, nz: int) -> Array:
	const R := 4
	var n := nx * nz
	var EXT: Rect2 = MC["EXT"]
	# 分離可能な減衰付き最大値フィルタ（横 → 縦）：src＝最大値を与えたセル
	var hS := PackedFloat32Array()
	hS.resize(n)
	var hI := PackedInt32Array()
	hI.resize(n)
	for j in nz:
		for i in nx:
			var best := 0.0
			var bi := -1
			for d in range(-R, R + 1):
				var ii := i + d
				if ii < 0 or ii >= nx:
					continue
				var v := aS[j * nx + ii] * (1.0 - absf(d) / (R + 1.0))
				if v > best:
					best = v
					bi = j * nx + ii
			hS[j * nx + i] = best
			hI[j * nx + i] = bi
	var cnt := 0
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if blk[k] == 1 or aS[k] > 0.02:
				continue
			var best := 0.0
			var bi := -1
			for d in range(-R, R + 1):
				var jj := j + d
				if jj < 0 or jj >= nz:
					continue
				var v := hS[jj * nx + i] * (1.0 - absf(d) / (R + 1.0))
				if v > best:
					best = v
					bi = hI[jj * nx + i]
			if best < 0.12 or bi < 0:
				continue
			var c := EXT.position + Vector2(i + 0.5, j + 0.5)
			var er := smoothstep(0.4, 0.68, n01(MC["nMeso"], c * 0.6 + Vector2(17.0, 131.0)))
			if er <= 0.0:
				continue
			if inside(c):
				var CV: Dictionary = P["CV"]
				if MVL.bdist(CV, P["MV"], c) < 12.0 or VL.road_sd(CV, c) < 3.0 or _path_x(P, c) < 2.0 or _spot(P, c) > 0.3 or MVL.apron_k(P["MV"], c).x > 0.2:
					continue
				var gk := ground_k(P, c)
				if gk.w > 0.35:
					continue
			elif (MC["roadX"] as GC.DGrid).at(c) < 3.0:
				continue
			aS[k] = 0.42 * best * er
			aH[k] = aH[bi] * 0.8
			aT[k] = aT[bi]
			aE[k] = aE[bi]
			aD[k] = aD[bi]
			cnt += 1
	F["spill"] = cnt
	return [aS, aH, aT, aE, aD]


static func f_idx(F: Dictionary, p: Vector2) -> int:
	var o: Vector2 = F["o"]
	var i := floori(p.x - o.x)
	var j := floori(p.y - o.y)
	if i < 0 or j < 0 or i >= int(F["nx"]) or j >= int(F["nz"]):
		return -1
	return j * int(F["nx"]) + i


## 1 m 場の雙線形補間（禁區のセルは 0 として扱う＝縁へ向かって自然に疎らになる）
static func f_bilerp(F: Dictionary, arr: PackedFloat32Array, p: Vector2) -> float:
	var o: Vector2 = F["o"]
	var nx: int = F["nx"]
	var nz: int = F["nz"]
	var fx := p.x - o.x - 0.5
	var fz := p.y - o.y - 0.5
	var i := clampi(floori(fx), 0, nx - 2)
	var j := clampi(floori(fz), 0, nz - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var k := j * nx + i
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + nx], arr[k + nx + 1], tx), tz)


# ─────────────────────────── 規劃 ───────────────────────────

## 立ち草の規劃（全村）：STEP の揺らした格子で走査、語意密度 S が多尺度の群落値 v の閾値を動かす。
##   返り値 M＝構造体配列（p, y, s, w, yaw, h, k, tag, comm, tier, col）＋F
static func plan(P: Dictionary, MC: Dictionary, F: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var EXT: Rect2 = MC["EXT"]
	var K := kit()
	# Packed 配列は値型：ローカルに積んで最後に M へ入れる（M["k"] as PackedByteArray への append は複製に入る）
	var aP := PackedVector2Array()
	var aY := PackedFloat32Array()
	var aSc := PackedFloat32Array()
	var aW := PackedFloat32Array()
	var aYaw := PackedFloat32Array()
	var aH := PackedFloat32Array()
	var aK := PackedByteArray()
	var aTg := PackedByteArray()
	var aCm := PackedInt32Array()
	var aTi := PackedByteArray()
	var aCol := PackedColorArray()
	var M := {}
	var uniform := P.has("_neg_uniform")
	var evenmix := P.has("_neg_evenmix")
	var tiny := P.has("_neg_tiny")
	var blk: PackedByteArray = F["blk"]
	var nx: int = F["nx"]
	var nz: int = F["nz"]
	var gx := EXT.position.x
	while gx < EXT.end.x:
		var gz := EXT.position.y
		while gz < EXT.end.y:
			var p := Vector2(gx + rng.randf_range(0.0, STEP), gz + rng.randf_range(0.0, STEP))
			gz += STEP
			var r0 := rng.randf()
			var r1 := rng.randf()
			var r2 := rng.randf()
			var r3 := rng.randf()
			var ci := f_idx(F, p)
			if ci < 0 or blk[ci] == 1:
				continue
			var Sv := f_bilerp(F, F["S"], p)
			if Sv < 0.02 and not uniform:
				continue
			# 多尺度の群落値と語意閾値
			var v := comm_v(MC, p)
			var thr := lerpf(0.84, 0.28, clampf(Sv, 0.0, 1.0))
			# 境界の侵食：閾値そのものを Meso（~3 m）で揺らし、斑の縁に缺口・突出を作る（單一閾値の輪郭にしない）
			thr += 0.2 * (n01(MC["nMeso"], p * 1.4 + Vector2(211.0, 5.0)) - 0.5)
			# r6：空き地（E_LOT）は縁の漸減を広く（斑が「島」に見えない：H_open_2）；常走（E_WALK）は広げない（r6 で後場に散点が出た）
			var soft := 0.32 if (F["ENV"] as PackedByteArray)[ci] == E_LOT else 0.2
			var a := smoothstep(thr - soft, thr + soft * 0.9, v)
			var prob := MAXP * pow(a, 1.3)
			var tier := 0 if a > 0.7 else (1 if a > 0.4 else (2 if a > 0.15 else 3))
			if tier >= 2:
				# 疎ら・孤立の段は微小 noise の峰に小さな群れで（規則的な點陣・似た間隔にしない）
				prob *= clampf(1.7 * smoothstep(0.4, 0.62, n01(MC["nMicro"], p * 0.55 + Vector2(19.0, 7.0))), 0.0, 1.0)
			if uniform:
				prob = 0.4
				tier = 1
			if r0 >= prob:
				continue
			# 樹幹・植物節點・P7 構件は 1 m セルより細かい → 採用した株は必ず正確に判定
			if blocked(P, MC, p) != "":
				continue
			var H := f_bilerp(F, F["H"], p)
			var hn := n01(MC["nHeight"], p)
			var th := H * lerpf(0.62, 1.05, a) * (0.6 + 0.8 * hn)
			var tg: int = (F["TAG"] as PackedByteArray)[ci]
			var env: int = (F["ENV"] as PackedByteArray)[ci]
			if tg == T_ROAD or tg == T_PATH:
				th = minf(th, 0.2)
			var dry: float = (F["DRY"] as PackedFloat32Array)[ci]
			var lush: float = (F["LUSH"] as PackedFloat32Array)[ci]
			var fern: float = (F["FERN"] as PackedFloat32Array)[ci]
			var sasa: float = (F["SASA"] as PackedFloat32Array)[ci]
			# 群落：dominant 1＋secondary 1–2＋accent（同じ區に全種を平均に混ぜない）
			var cid := comm_id(MC, p)
			var pal: Array = PALETTES[cid % PALETTES.size()]
			var dom: int = pal[0]
			var sec: int = pal[1]
			var sec2: int = pal[2]
			if dry > 0.3 and ((cid / 13) % 3) != 0:
				sec = dom
				dom = K_DRY
			var k := dom
			if r1 < fern:
				k = K_FERN
			elif r1 < fern + sasa:
				k = K_SASA
			elif evenmix:
				k = rng.randi_range(0, 6)
			elif r2 < 0.64:
				k = dom
			elif r2 < 0.84:
				k = sec
			elif r2 < 0.93:
				k = sec2
			else:
				k = ENV_ACCENT[env]
				th *= 1.2
			if k < K_FERN and not (k in ENV_ALLOW[env]):
				k = ENV_FALLBACK[env]
			if tg == T_ROAD or tg == T_PATH:
				k = K_SHORT if k != K_SPARSE else k
			if tiny:
				k = K_SHORT
			var kh: float = K[k]["h"]
			var sc: float = clampf(th / kh, 0.65, 1.35) if k < K_FERN else lerpf(0.8, 1.15, r3)
			if tiny:
				sc = 0.4
			var yaw := rng.randf() * TAU
			if k == K_LEAN:
				yaw = TAU * n01(MC["nLean"], p) * 1.3 + rng.randf_range(-0.3, 0.3)
			aP.append(p)
			aY.append(MVL.top_h(P, p) - SINK)
			aSc.append(sc)
			aW.append(rng.randf_range(0.9, 1.25))
			aYaw.append(yaw)
			aH.append(kh * sc)
			aK.append(k)
			aTg.append(tg)
			aCm.append(cid)
			aTi.append(tier)
			aCol.append(_tint(rng, k, dry, lush))
		gx += STEP
	M = {"p": aP, "y": aY, "s": aSc, "w": aW, "yaw": aYaw, "h": aH, "k": aK, "tag": aTg, "comm": aCm, "tier": aTi, "col": aCol}
	M["n"] = aP.size()
	M["F"] = F
	M["ms"] = Time.get_ticks_msec() - t0
	return M


## instance color（網格の頂點色への乘數）：濃い草は青緑寄り・枯れは黄土寄り・個体差
static func _tint(rng: RandomNumberGenerator, k: int, dry: float, lush: float) -> Color:
	var b := rng.randf_range(0.86, 1.06)
	var c := Color(b, b, b)
	if k in GRASS_KINDS and k != K_DRY:
		c = c * Color(1.0, 1.0, 1.0).lerp(Color(0.88, 1.04, 0.86), lush)
		c = c * Color(1.0, 1.0, 1.0).lerp(Color(1.12, 1.04, 0.8), clampf(dry * 0.8 + rng.randf_range(0.0, 0.08), 0.0, 1.0))
	# 畫面實測（Pilot p4：草の画素 (83,96,60) vs 同じ画素の地形 (72,82,58)）→ 地形の明るさ・色相へ寄せる
	c = c * Color(0.88, 0.86, 0.98)
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


# ─────────────────────────── 烘焙 ───────────────────────────

static func material(level: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	if level == "near":
		m.set_shader_parameter("fade_in", Vector2(0.0, 0.0))
		m.set_shader_parameter("fade_out", NEAR_OUT)
	else:
		m.set_shader_parameter("fade_in", NEAR_OUT)
		m.set_shader_parameter("fade_out", MID_OUT)
	return m


static func xf_of(M: Dictionary, i: int, origin: Vector3) -> Transform3D:
	var sc: float = (M["s"] as PackedFloat32Array)[i]
	var w: float = (M["w"] as PackedFloat32Array)[i]
	var p: Vector2 = (M["p"] as PackedVector2Array)[i]
	# r6：同形の叢が並んで見えないよう、決定的な傾き（≤ 9°、任意の方向）と x／z 別々の幅（0.8–1.2 の比）
	var h1 := fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)
	var h2 := fposmod(sin(p.x * 39.346 + p.y * 11.135) * 24634.6345, 1.0)
	var h3 := fposmod(sin(p.x * 73.156 + p.y * 52.235) * 13758.5453, 1.0)
	var tilt := Basis(Vector3(cos(h1 * TAU), 0.0, sin(h1 * TAU)), deg_to_rad(9.0) * h2)
	var wz := lerpf(0.8, 1.2, h3)
	var b := tilt * Basis(Vector3.UP, (M["yaw"] as PackedFloat32Array)[i]) * Basis.from_scale(Vector3(sc * w, sc, sc * w * wz))
	return Transform3D(b, Vector3(p.x, (M["y"] as PackedFloat32Array)[i], p.y) - origin)


## 中級に残すか（決定的：丈の高い株・羊歯・笹を優先）
static func mid_keep(M: Dictionary, i: int) -> bool:
	var k: int = (M["k"] as PackedByteArray)[i]
	var pref := 0.18 if k in [K_TALL, K_SEED, K_FERN, K_SASA] else (0.08 if k in [K_MEDIUM, K_LEAN, K_DRY] else -0.2)
	var p: Vector2 = (M["p"] as PackedVector2Array)[i]
	return GC._n(p * 3.7, 1.0, 587.0) * 0.5 + fposmod(float(i) * 0.618034, 1.0) * 0.5 < MID_KEEP + pref


static func bake(M: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_meta("art_revision", ART_REVISION)
	var near := Node3D.new()
	near.name = "Near"
	root.add_child(near)
	var mid := Node3D.new()
	mid.name = "Mid"
	root.add_child(mid)
	var K := kit()
	var mat_n := material("near")
	var mat_m := material("mid")
	var buckets := {}
	var n: int = M["n"]
	var aP: PackedVector2Array = M["p"]
	var aK: PackedByteArray = M["k"]
	for i in n:
		var p := aP[i]
		var kn := Vector3i(floori(p.x / NEAR_CHUNK), floori(p.y / NEAR_CHUNK), aK[i])
		# Packed 配列は値型（as で取り出して append すると複製に入る）→ Array に積む
		if not buckets.has(kn):
			buckets[kn] = [[], []]
		(buckets[kn][0] as Array).append(i)
		if mid_keep(M, i):
			var km := Vector3i(floori(p.x / MID_CHUNK) + 100000, floori(p.y / MID_CHUNK), aK[i])
			if not buckets.has(km):
				buckets[km] = [[], []]
			(buckets[km][1] as Array).append(i)
	var keys := buckets.keys()
	keys.sort()
	var n_near := 0
	var n_mid := 0
	var n_inst := 0
	var n_mid_inst := 0
	var aY: PackedFloat32Array = M["y"]
	var aCol: PackedColorArray = M["col"]
	for key: Vector3i in keys:
		var is_mid := key.x >= 50000
		var lst: Array = buckets[key][1] if is_mid else buckets[key][0]
		if lst.is_empty():
			continue
		var cs := MID_CHUNK if is_mid else NEAR_CHUNK
		var cx := key.x - 100000 if is_mid else key.x
		var ys := 0.0
		for i: int in lst:
			ys += aY[i]
		var origin := Vector3((cx + 0.5) * cs, ys / lst.size(), (key.y + 0.5) * cs)
		var mesh: ArrayMesh = K[key.z]["mid" if is_mid else "near"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = lst.size()
		var mab := mesh.get_aabb()
		var ab := AABB()
		for j in lst.size():
			var xf := xf_of(M, lst[j], origin)
			mm.set_instance_transform(j, xf)
			mm.set_instance_color(j, aCol[lst[j]])
			var ib := xf * mab
			ab = ib if j == 0 else ab.merge(ib)
		# 緊 AABB（instance 變換後の網格框の聯集＋風の揺れ・遠方の横広げ 20 cm）
		mm.custom_aabb = ab.grow(0.2)
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d_%s" % ["M" if is_mid else "N", cx, key.y, KIND_NAMES[key.z]]
		node.multimesh = mm
		node.position = origin
		node.material_override = mat_m if is_mid else mat_n
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_mid else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# 粗い剔除：分塊中心からの距離＋半対角（shader の縮小が実際の出入りを担う）
		var half := cs * 0.7072 + 2.0
		if is_mid:
			node.visibility_range_begin = maxf(0.0, NEAR_OUT.x - half)
			node.visibility_range_end = MID_OUT.y + half
			mid.add_child(node)
			n_mid += 1
			n_mid_inst += lst.size()
		else:
			node.visibility_range_end = NEAR_OUT.y + half
			near.add_child(node)
			n_near += 1
			n_inst += lst.size()
	root.set_meta("items", n_inst)
	root.set_meta("mid_items", n_mid_inst)
	root.set_meta("near_nodes", n_near)
	root.set_meta("mid_nodes", n_mid)
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		own(c, owner)


## 封存 groundcover の規劃を讀み取り専用で再計算（verify_village_v2_groundcover.gd と同じ順序）。
##   場景から GroundcoverP9／MeadowP9 を外してから（自分自身を禁區・植物として読まない）。
static func base_plan(v: Node3D) -> Dictionary:
	var P: Dictionary = GC.plan(v)
	VL.extend(P, v)
	ML.extend(P, v)
	MVL.extend(P, v)
	return P
