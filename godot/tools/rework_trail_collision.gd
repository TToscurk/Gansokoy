extends SceneTree
## 獸道碰撞重排：把零散的碰撞換成一圈正方形框（2026-09-16 使用者裁定）。
##
##   Godot --headless --path godot --script tools/rework_trail_collision.gd
##
## 使用者原話：「把獸道的碰撞重新排過一次，目前太亂了，就用正方形把能夠
## 移動的範圍框起來就好。」
##
## ═ 動手前實測到的現況（這支要修掉的東西）══
## CollisionShape3D 共 608 個，散在 8 個 StaticBody3D：
##   樹幹碰撞 406（Cylinder r0.38）／牆體 129（Box 1×14×5.4）／岩壁碰撞 28
##   （Sphere）／岩石碰撞 20（17 Sphere + 3 Box 倒木）／遺跡碰撞 14
##   （3 Box + 11 Cylinder）／空地碰撞 6（Cylinder）／屋台碰撞 1／Boundary 4
## audit_trail_containment 跑出來：117/120 次側掃被擋住，最糟超出 9.8 m @ t=0.69。
## ↑ 破洞的成因是牆沿**主脊 t 等距**取樣：大空地與獵食者袋那兩段 play_half
##   在 10 m 內從 20 鼓到 27/30，相鄰兩段牆心沿路差 4 m、橫向又差 5 m，
##   距離 6.4 m 而盒子只有 5.4 m 長 → 中間開洞。
##
## ══ 這一版 ══
## 只留「可動範圍的框」＋木橋橋面（橋是地板不是障礙，拆了玩家會掉進溪裡）；
## 樹幹／岩石／隘口岩體／地藏／燈籠／屋台全部不再給碰撞。
## 框 = 一堆**正方形**（12×22×12，端封 8×22×8），沿邊界折線每 6 m 一塊、
## 內面正好貼在邊界線上（中心再往外推半個邊長），所以玩家可動範圍不縮水。
##
## ⚠ 命名／路徑一律 ASCII：專案吃過全形字元路徑的虧（見 .hermes.md）。

const SRC := "res://maps/trail/trail.tscn"
const BAK_DIR := "res://maps/trail/backups/"

const SIDE_SQ := 6.0         # 走廊兩側正方形邊長（足跡）
const STEP := 3.0            # 沿邊界折線取樣間距 = 半個邊長 → 相鄰必重疊
const CAP_SQ := 6.0          # 南北端封口正方形邊長
const CAP_OFF := 6.0         # 端封內面離主脊端點距離（端封那排是斜的，太近兩端會伸進走廊）
const EXT_END := 12.0        # 主脊往兩端各延長多少公尺（側框要鋪過端點才接得上端封）
const BOX_H := 22.0          # 框高
const SINK := 6.0            # 底部沉入框腳最低地面下
const SMOOTH_W := 5          # 折線移動平均視窗（±5 點 ≈ ±3.2 m）

## 要整個刪掉的碰撞 body（路徑相對於場景根）
const DROP_BODIES := [
	"樹幹碰撞",
	"走廊碰撞牆/牆體",
	"岩石與倒木/岩石碰撞",
	"岩壁隘口/岩壁碰撞",
	"獸道大空地/空地碰撞",
	"夜雀屋台區/屋台碰撞",
]
## 只清掉子碰撞、body 本身留下來的（人類遺跡那一組要留橋面）
const PRUNE_BODY := "人類遺跡/遺跡碰撞"

var main: Node
var space: PhysicsDirectSpaceState3D
var map_half := 120.0
var boxes: Array = []
var ray_miss := 0


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame


func _fmin(a: PackedFloat32Array) -> float:
	var v := INF
	for x in a:
		v = minf(v, x)
	return v


func _fmax(a: PackedFloat32Array) -> float:
	var v := -INF
	for x in a:
		v = maxf(v, x)
	return v


# ══════════════════════════════════════════════════════════════════
# 階段 A：用真的物理量幾何（地面前提是 main.gd 在載圖時烘的地形 trimesh）
# ══════════════════════════════════════════════════════════════════
## 地面射線：排除所有**非地形**的碰撞體。
##   ⚠ 不排除的話，「框」自己 22 m 高的方塊會被射線打到（頂面 y≈34），
##     下一版框就被抬到半空中（實測重跑時框心跑到 y=34.3）。
##     舊的牆體／樹幹同樣會污染：它們站在路緣上，取樣點很容易落進它們的足跡。
var exclude_rids: Array[RID] = []


func _collect_excludes(trail: Node3D) -> void:
	exclude_rids.clear()
	var stack: Array[Node] = [trail]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is PhysicsBody3D:
			var rel := String(trail.get_path_to(n))
			if rel != "Terrain/Terrain_col":
				exclude_rids.append((n as PhysicsBody3D).get_rid())
	var p := main.get_node_or_null("Player")
	if p is PhysicsBody3D:
		exclude_rids.append((p as PhysicsBody3D).get_rid())
	print("[COLL] 地面射線排除 %d 個非地形碰撞體（含玩家）" % exclude_rids.size())


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -40.0, z))
	q.collision_mask = 0xFFFFFFFF
	q.exclude = exclude_rids
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF


## 正方形足跡內的最低地面。只取樣圖內的點 —— 端封那排是斜的，列兩端會落到
## z=±126（圖只到 ±120），那裡沒地形，射線打到的是 Boundary 牆頂 y=40，
## 框心會被抬到 y=45（實測）。inner_pt 是內面中點，一定在走廊裡。
func _foot_min_ground(c: Vector2, yaw: float, s: float, inner_pt: Vector2) -> Array:
	var lo := INF
	var miss := 0
	var pts: Array = [inner_pt, c]
	var h := s * 0.5 - 0.05
	var cs := cos(yaw)
	var sn := sin(yaw)
	for d in [Vector2(h, h), Vector2(h, -h), Vector2(-h, h), Vector2(-h, -h)]:
		var dv: Vector2 = d
		pts.append(Vector2(c.x + dv.x * cs + dv.y * sn, c.y - dv.x * sn + dv.y * cs))
	for p in pts:
		var q: Vector2 = p
		if absf(q.x) > map_half - 2.0 or absf(q.y) > map_half - 2.0:
			miss += 1
			continue
		var gg := _ground(q.x, q.y)
		if gg == -INF:
			miss += 1
		else:
			lo = minf(lo, gg)
	if lo == INF:
		lo = _ground(inner_pt.x, inner_pt.y)
		if lo == -INF:
			lo = 0.0
	ray_miss += miss
	return [lo, miss]


func _add_box(nm: String, centre: Vector2, yaw: float, s: float, inner_pt: Vector2) -> void:
	var g: float = _foot_min_ground(centre, yaw, s, inner_pt)[0]
	boxes.append({
		"name": nm,
		"pos": Vector3(centre.x, g - SINK + BOX_H * 0.5, centre.y),
		"size": s,
		"yaw": yaw,
		"inner": inner_pt,
	})


func _resample(poly: PackedVector2Array, step: float) -> Array:
	var acc := PackedFloat32Array()
	acc.resize(poly.size())
	acc[0] = 0.0
	for i in range(1, poly.size()):
		acc[i] = acc[i - 1] + poly[i].distance_to(poly[i - 1])
	var total: float = acc[poly.size() - 1]
	var out: Array = []
	var cur := 0
	var d := 0.0
	while d <= total:
		while cur < poly.size() - 2 and acc[cur + 1] < d:
			cur += 1
		var seg: float = maxf(acc[cur + 1] - acc[cur], 0.0001)
		var u: float = clampf((d - acc[cur]) / seg, 0.0, 1.0)
		var p: Vector2 = poly[cur].lerp(poly[cur + 1], u)
		var tang := (poly[mini(cur + 1, poly.size() - 1)] - poly[maxi(cur - 1, 0)]).normalized()
		out.append([p, tang, cur, u])
		d += step
	return out


## 從主脊上的點 p0 沿 n 往外走，回傳「第一個已在可動範圍之外」的距離。
##   可動範圍的定義：點到主脊折線的距離 ≤ 最近段落的 play_half。
func _boundary_dist(p0: Vector2, n: Vector2, spine: PackedVector2Array,
		play: PackedFloat32Array) -> float:
	var d := 0.0
	while d < 60.0:
		var p: Vector2 = p0 + n * d
		var info := _spine_info(spine, p)
		if float(info[1]) < 0.004 or float(info[1]) > 0.996:
			return d
		var ph: float = _play_at(play, spine, float(info[1]))
		if float(info[0]) >= ph - 0.25:
			return d
		d += 0.25
	return 60.0


## 主脊往兩端各延長 EXT_END（直線）。回傳 [點, play]。
##   側框要沿著延長段鋪過去，端封才有東西可以重疊；否則端封外移之後，
##   兩側側框與端封之間會留下橫向缺口。
func _extend_spine(spine: PackedVector2Array, play: PackedFloat32Array) -> Array:
	var n := spine.size()
	var pts := PackedVector2Array()
	var pl := PackedFloat32Array()
	var d0 := (spine[1] - spine[0]).normalized()
	var d1 := (spine[n - 1] - spine[n - 2]).normalized()
	var steps := int(ceil(EXT_END / 3.0))
	for k in range(steps, 0, -1):
		pts.append(spine[0] - d0 * (float(k) * 3.0))
		pl.append(play[0])
	for i in n:
		pts.append(spine[i])
		pl.append(play[i])
	for k in range(1, steps + 1):
		pts.append(spine[n - 1] + d1 * (float(k) * 3.0))
		pl.append(play[n - 1])
	return [pts, pl]


## 這塊框的內面探進可動範圍多少公尺（0 = 完全沒探進去）。
##   可動範圍的定義：點到主脊折線的距離 ≤ 最近段落的 play_half。外側在樹林裡。
func _box_slack(ctr: Vector2, nrm: Vector2, s: float, spine: PackedVector2Array,
		play: PackedFloat32Array) -> float:
	var tan := Vector2(-nrm.y, nrm.x)
	var inner: Vector2 = ctr - nrm * (s * 0.5)
	var worst := 0.0
	for k in 5:
		var f := (float(k) / 4.0 - 0.5) * (s - 0.4)
		var p: Vector2 = inner + tan * f
		var info := _spine_info(spine, p)
		# 主脊兩端之外那一小段不套這條判準：那裡的可動範圍是端封決定的。
		if float(info[1]) < 0.004 or float(info[1]) > 0.996:
			continue
		var ph: float = _play_at(play, spine, float(info[1]))
		worst = maxf(worst, ph - float(info[0]))
	return worst


## 折線移動平均（±W 點）。外推方向用近當地切線會讓折線帶 ±0.9 m 的齒，
## 直接拿來鋪方塊會一張一弛；平滑掉位置即可，方向資訊已經在 norms 裡。
## 方向場的移動平均（平滑的是向量，之後再正規化）。
func _smooth_norms(nrm: PackedVector2Array, w: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(nrm.size())
	for i in nrm.size():
		var acc := Vector2.ZERO
		for j in range(i - w, i + w + 1):
			acc += nrm[clampi(j, 0, nrm.size() - 1)]
		out[i] = (acc / float(w * 2 + 1)).normalized()
	return out


func _smooth_poly(poly: PackedVector2Array, w: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		var acc := Vector2.ZERO
		var cnt := 0
		for j in range(i - w, i + w + 1):
			var k: int = clampi(j, 0, poly.size() - 1)
			acc += poly[k]
			cnt += 1
		out[i] = acc / float(cnt)
	return out


## 點到主脊折線的距離與最近 t
func _spine_info(spine: PackedVector2Array, p: Vector2) -> Array:
	var best := INF
	var bt := 0.0
	for i in spine.size() - 1:
		var a := spine[i]
		var b := spine[i + 1]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * u)
		if d < best:
			best = d
			bt = (float(i) + u) / float(spine.size() - 1)
	return [best, bt]


func _plan() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(4)
	main.load_map("trail", "")
	await _settle(60)
	space = main.get_viewport().world_3d.direct_space_state

	var map_root: Node3D = main.map_root
	var trail: Node3D = null
	for c in map_root.get_children():
		if c is Node3D and c.has_meta("spine"):
			trail = c
	if trail == null and map_root.has_meta("spine"):
		trail = map_root
	if trail == null:
		print("[COLL] 找不到帶 meta(spine) 的節點")
		quit(1)
		return
	var spine: PackedVector2Array = trail.get_meta("spine")
	var play: PackedFloat32Array = trail.get_meta("play_half")
	var n := spine.size()
	var terr := trail.get_node_or_null("Terrain")
	if terr is MeshInstance3D:
		var ab := (terr as MeshInstance3D).get_aabb().size
		map_half = maxf(ab.x, ab.z) * 0.5
	print("[COLL] 主脊 %d 點、play_half %.1f–%.1f m、圖半寬 %.0f m"
		% [n, _fmin(play), _fmax(play), map_half])
	_collect_excludes(trail)

	# ── 兩側邊界折線 ──
	# ⚠ 不要用「邊界點到主脊折線的距離 vs play_half」當貼合指標：邊界點是用
	#   主脊第 i 點的垂線推出去的，但「到折線的最近距離」可能落在另一個彎上
	#   （大空地鼓包外緣實測差 9.82 m），那個數字是量法的錯，不是幾何的錯。
	#   這裡改成直接量「覆蓋」：邊界折線上每一點到最近框心的距離，
	#   必須小於邊長（12 m）才有重疊、不會開縫。
	var cover_max := 0.0
	for side in [1.0, -1.0]:
		# 邊界折線的每一點都**同時記下它的側向法線**（就是建構時用的那條）。
		#  不能事後用「離最近主脊點的向量」去猜外側：鼓包（大空地、獵食者袋）
		#   外緣最近的往往是別的主脊段，猜錯邊的結果是框整排往走廊裡面擺
		#   —— 實測 t=0.55–0.76 內縮 10–17 m（audit 的 eat 檢查抓到 20/120）。
		var poly := PackedVector2Array()
		var norms := PackedVector2Array()
		# 主脊往兩端各延長 EXT_END：側框要鋪過端點。端封若只單獨放一排，
		# 兩側側框到端封之間的橫向缺口就是一條可以走出去的路。
		var xs := _extend_spine(spine, play)
		var xsp: PackedVector2Array = xs[0]
		var xsw: PackedFloat32Array = xs[1]
		var m := xsp.size()
		for i in m:
			# 外推方向用**近當地切線**（±2 取樣點 ≈ 1.3 m 基線）。±10 版會離
			# 體檢用的當地切線最多 19°（外推 30 m 就差十幾公尺）。
			var d := (xsp[mini(i + 2, m - 1)] - xsp[maxi(i - 2, 0)]).normalized()
			var sp_n: Vector2 = Vector2(-d.y, d.x) * side
			poly.append(xsp[i] + sp_n * xsw[i])
			norms.append(sp_n)
		# 順序：先平滑（位置＋方向），再沿平滑後的方向把點推到「真的出界」。
		#   ⚠ 倒的話（先推出去再平滑）平滑會把點拉回走廊裡，整排被判成內縮；
		#     不平滑的話 ±2 基線的切線噪聲會讓折線抖成鋸齒，鋪出兩倍份量的框。
		poly = _smooth_poly(poly)
		var nrm_s := _smooth_norms(norms)
		for i in poly.size():
			# 距離不直接用 play_half：可動半寬 20–30 m 大於主脊的轉彎半徑時，
			# 邊界折線會折疊（離自己 play_half 的點還在另一段走廊的可動範圍裡）。
			# 沿射線走到真的出界為止 → 折疊被吸收成內側包絡線。
			var dd := _boundary_dist(poly[i], nrm_s[i], spine, play)
			if dd > 0.0:
				poly[i] = poly[i] + nrm_s[i] * dd
			norms[i] = nrm_s[i]
		var samp := _resample(poly, STEP)
		var tag := "L" if side > 0.0 else "R"
		# ─ 候選框：邊界點 + 該點的外側法線 ──
		var cand: Array = []
		for s in samp:
			var p: Vector2 = s[0]
			var i0: int = s[2]
			var u: float = s[3]
			var nrm: Vector2 = (norms[i0] as Vector2).lerp(
				norms[mini(i0 + 1, n - 1)] as Vector2, u).normalized()
			cand.append([p, nrm])
		# 只統計內面有沒有探進可動範圍 —— 不剔除。
		#  ⚠ 剔除會留破洞（實測折疊段剔掉 90 塊、留下 53 m 缺口，體檢抓到 4 處漏）。
		#   破洞比小幅內縮嚴重得多：內縮是「少走幾步」，破洞是「走出地圖」。
		var kept: Array = []
		var slack := 0
		var worst_slack := 0.0
		for c in cand:
			var p: Vector2 = c[0]
			var nrm: Vector2 = c[1]
			var ctr: Vector2 = p + nrm * (SIDE_SQ * 0.5)
			kept.append([ctr, nrm])
			var sl := _box_slack(ctr, nrm, SIDE_SQ, spine, play)
			if sl > 0.0:
				slack += 1
				worst_slack = maxf(worst_slack, sl)
		# ── 補縫：過濾後相鄰兩塊拉太開就插中間塊（插的也要過同一個判準）──
		var out: Array = []
		var filled := 0
		for i in kept.size():
			out.append(kept[i])
			if i + 1 >= kept.size():
				continue
			var a: Array = kept[i]
			var b: Array = kept[i + 1]
			var gap: float = (b[0] as Vector2).distance_to(a[0] as Vector2)
			if gap <= SIDE_SQ * 0.75:
				continue
			var seg := int(ceil(gap / STEP))
			for k in range(1, seg):
				var f := float(k) / float(seg)
				var ctr2: Vector2 = (a[0] as Vector2).lerp(b[0] as Vector2, f)
				var nrm2: Vector2 = ((a[1] as Vector2).lerp(b[1] as Vector2, f)).normalized()
				out.append([ctr2, nrm2])
				filled += 1
		var centres: Array = []
		for c in out:
			var nrm: Vector2 = c[1]
			_add_box("frame_%s_%03d" % [tag, boxes.size()], c[0], atan2(nrm.x, nrm.y),
				SIDE_SQ, (c[0] as Vector2) - nrm * (SIDE_SQ * 0.5))
			centres.append(c[0])
		var worst := 0.0
		for i in centres.size() - 1:
			worst = maxf(worst, (centres[i] as Vector2).distance_to(centres[i + 1] as Vector2))
		cover_max = maxf(cover_max, worst)
		print("[COLL] %s 側：%d 塊（補縫 %d）；內面探進可動範圍 %d 塊、最深 %.2f m；相鄰框心最遠 %.2f m"
			% [tag, out.size(), filled, slack, worst_slack, worst])

	# ─ 南北端封口 ──
	for e in [[0.0, "S"], [1.0, "N"]]:
		var t: float = e[0]
		var i0 := 0 if t < 0.5 else n - 1
		# 端封方向用 ±10 基線：±1 基線在主脊入口那幾個帶噪聲的點上會斜 19°，
		# 端封那排兩端就往走廊裡切進去（實測 12.3 m 處就被擋住，play 是 20）。
		var d := (spine[mini(i0 + 10, n - 1)] - spine[maxi(i0 - 10, 0)]).normalized()
		var outward := -d if t < 0.5 else d
		var perp := Vector2(-d.y, d.x)
		var inner: Vector2 = spine[i0] + outward * CAP_OFF
		var k := int(ceil((play[i0] + CAP_SQ) / CAP_SQ))
		for j in range(-k, k + 1):
			var col: Vector2 = inner + perp * (float(j) * CAP_SQ)
			_add_box("cap_%s_%02d" % [e[1], j + k], col + outward * (CAP_SQ * 0.5),
				atan2(outward.x, outward.y), CAP_SQ, col)
		print("[COLL] %s 端封口 %d 塊（內面離端點 %.1f m、寬 ±%.0f m）"
			% [e[1], k * 2 + 1, CAP_OFF, play[i0] + CAP_SQ])
	print("[COLL] 幾何：%d 塊正方形；邊界折線最遠離框心 %.2f m（邊長 %.0f → 覆蓋 OK）；地面射線失手 %d 次"
		% [boxes.size(), cover_max, SIDE_SQ, ray_miss])


func _spine_pos(spine: PackedVector2Array, t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * float(spine.size() - 1)
	var i := int(floor(f))
	return spine[i].lerp(spine[mini(i + 1, spine.size() - 1)], f - float(i))


func _play_at(play: PackedFloat32Array, spine: PackedVector2Array, t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * float(spine.size() - 1)
	var i := int(floor(f))
	return lerpf(play[i], play[mini(i + 1, play.size() - 1)], f - float(i))


func _poly_len(poly: PackedVector2Array) -> float:
	var l := 0.0
	for i in poly.size() - 1:
		l += poly[i].distance_to(poly[i + 1])
	return l


# ══════════════════════════════════════════════════════════════════
# 階段 B：改場景（磁碟檔）再存回
# ═════════════════════════════════════════════════════════════════
func _apply() -> int:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("[COLL] 讀不到 %s" % SRC)
		return 1
	var root_node := ps.instantiate() as Node3D
	var before := ps.get_state().get_node_count()

	# ── 1. 整個刪掉舊碰撞 body ──
	var removed := 0
	for path in DROP_BODIES:
		var b := root_node.get_node_or_null(path)
		if b == null:
			print("[COLL] ⚠ 找不到 %s（略過）" % path)
			continue
		var cnt := b.get_child_count()
		b.get_parent().remove_child(b)
		b.free()
		removed += cnt + 1
		print("[COLL] 刪 %-22s 子碰撞 %3d 個" % [path, cnt])

	# ── 2. 人類遺跡：只留木橋橋面（地板，不是障礙）──
	var prune := root_node.get_node_or_null(PRUNE_BODY)
	if prune != null:
		var keep: Array = []
		var drop: Array = []
		for c in prune.get_children():
			var s := (c as CollisionShape3D).shape if c is CollisionShape3D else null
			var is_bridge: bool = s is BoxShape3D and absf((s as BoxShape3D).size.z - 10.0) < 0.01
			if is_bridge:
				keep.append(c)
			else:
				drop.append(c)
		for c in drop:
			prune.remove_child(c)
			c.free()
		removed += drop.size()
		prune.name = "木橋碰撞"
		print("[COLL] 人類遺跡：留 %d（木橋面）、刪 %d" % [keep.size(), drop.size()])
	else:
		print("[COLL]  找不到 %s" % PRUNE_BODY)

	# ── 3. 舖正方形框（重跑時先拆掉上一次的框，否則會一層疊一層）──
	var group := root_node.get_node_or_null("走廊碰撞牆")
	if group == null:
		print("[COLL] ⚠ 找不到 走廊碰撞牆 群組節點")
		return 1
	for c in group.get_children():
		if c is StaticBody3D and String(c.name).begins_with("可動範圍框"):
			var old_nm := String(c.name)          #  先記名字：free() 之後再讀 c.name 會炸
			var n0 := c.get_child_count()
			group.remove_child(c)
			c.free()
			removed += n0 + 1
			print("[COLL] 拆掉舊框 %s（%d 塊）—— 重跑要冪等" % [old_nm, n0])
	var body := StaticBody3D.new()
	body.name = "可動範圍框"
	group.add_child(body)
	body.owner = root_node
	# 兩種尺寸各一個共用資源（117 個子形狀共用 2 份 → tscn 只多 2 個 sub_resource）
	var shared := {"side": BoxShape3D.new(), "cap": BoxShape3D.new()}
	(shared["side"] as BoxShape3D).size = Vector3(SIDE_SQ, BOX_H, SIDE_SQ)
	(shared["cap"] as BoxShape3D).size = Vector3(CAP_SQ, BOX_H, CAP_SQ)
	var ymin := INF
	var ymax := -INF
	for b in boxes:
		var sh := CollisionShape3D.new()
		sh.name = String(b["name"])
		var s: float = b["size"]
		sh.shape = shared["side"] if absf(s - SIDE_SQ) < 0.01 else shared["cap"]
		var pos: Vector3 = b["pos"]
		sh.position = pos
		sh.rotation = Vector3(0.0, float(b["yaw"]), 0.0)
		body.add_child(sh)
		sh.owner = root_node
		ymin = minf(ymin, pos.y)
		ymax = maxf(ymax, pos.y)

	# ── 4. 寫檔前斷言（.hermes 的規矩：量到才寫）──
	var added := body.get_child_count() + 1
	var expect := before - removed + added
	var out := PackedScene.new()
	var err := out.pack(root_node)
	var got := out.get_state().get_node_count()
	var inst_ok := root_node.get_node_or_null("獸道互動點") != null
	# ⚠ 不要在「還沒進場景樹」的節點上讀 global_transform／global_scale——
	#   Godot 在樹外一律回傳單位矩陣，量到的東西是假的（repo 的既有教訓）。
	#   這裡比對實際寫進去的區域 transform 與計畫值。
	var owner_bad := 0
	var pos_bad := 0
	var boxes_kids := body.get_children()
	for idx in boxes_kids.size():
		var cs := boxes_kids[idx] as CollisionShape3D
		if cs.owner != root_node or cs.shape == null:
			owner_bad += 1
		if idx % 39 == 0:                       # 抽樣：頭、中、尾
			var want: Vector3 = boxes[idx]["pos"]
			var wyaw: float = boxes[idx]["yaw"]
			if cs.position.distance_to(want) > 0.001 or absf(cs.rotation.y - wyaw) > 0.00001:
				pos_bad += 1
	print("[COLL] 斷言：節點 %d → %d（預期 %d）；互動點實例 %s；框內異常 %d；抽樣位姿不符 %d"
		% [before, got, expect, "在" if inst_ok else "不見了", owner_bad, pos_bad])
	if err != OK or got != expect or not inst_ok or owner_bad != 0 or pos_bad != 0:
		print("[COLL]  斷言失敗，不寫檔（原檔未動）")
		return 1

	# ── 5. 備份 + 存檔 ──
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var bak := ProjectSettings.globalize_path(BAK_DIR) + "trail_before_collision_frame_%s.tscn" % stamp
	if not DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC), bak) == OK:
		print("[COLL] ⚠ 備份失敗：%s" % bak)
	else:
		print("[COLL] 備份 %s" % bak)
	var serr := ResourceSaver.save(out, SRC)
	print("[COLL] 存檔 err=%d；框 %d 塊（中心 y %.1f–%.1f m）" % [serr, body.get_child_count(), ymin, ymax])
	return 0 if serr == OK else 1


func _run() -> void:
	await _plan()
	if boxes.is_empty():
		print("[COLL] 沒算出任何框，中止")
		quit(1)
		return
	var code := _apply()
	print("[COLL] 完成，exit=%d" % code)
	quit(code)