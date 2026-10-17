extends SceneTree
## P13 W9 FIX：作り直した建物の碰撞箱を『見た目』から導く（唯讀・場景ファイルは書かない）。
##   godot --headless --path godot --script res://tools/p13/w9/w9fix_colfit.gd -- --out=<json> [--ids=a,b,...]（省略＝SPECS 全棟）[--arch-off=1]
##   → w9fix_colfit_post.py が W9R2 で新しく出た不一致の棟だけを collision_fit.json に整形 → build_w9r2.gd が <id>/Shell に焼く。
##   --arch-off=1：overlay を切った Kit だけの外観で同じ判定（W9R2 以前からある理由＝PRE-EXISTING の判別用）。
## 規則（body 局部・外形 0.125 m／屋根 0.25 m 格子・壁は幅 0.24 m の扇 ray＝格子の隙間を素通りしない）：
##   1. 壁の外形（hull）＝局部 y 1.2 で 4 方向から当てた『見た目の壁』（外向き・法線が水平に近い面）の正射影の積。
##      前面は元の箱の前面から FRONT_SNAP 以内の凹み（入口）は元の面に揃える（Kit と同じ約束）。他の面は 0.2 m 以内なら元の面に揃える。
##   2. hull を長方形に分け、上面 t1 ＝ その範囲の屋根上面の 3 パーセンタイル − 0.10（軒。屋根の上に箱が出ない）。底面は元の箱の底面。
##   3. 二段目：t1 の上に、高さ 0.5 m 以上の鉛直な壁の外形（後退した二階・脇の高い棟）があれば足す（屋根の段差 ≥ 0.6 m か、0.6 m 上でも外形が 75% 残る）。
##   4. 低い物：y 0.6 の外形の外の物（縁台など）、および 4b. 元の箱の中で新しく歩けるようになる所の置き物・台（上面 ≥ 0.40＝Auto-Step 不可）。
##   6. 面の照合：上げた分の面・新しくできた面・二段目の面に見た目の壁が無ければ、その高さで削る（見えない壁を作らない）。
##   7. 開いた所の上の低い庇（裏面 2.0–3.5 m）：裏面から軒までの板（カメラが庇をくぐって屋根に入らない）。
##   8. 屋根の中の詰め物：元の箱のうち見える屋根の下にあった分は FILL_STEP（0.10 m）の段で残す（屋根の上に出ていた分だけを削る）。
##   apply（理由）：箱が屋根より上に出る／見える壁が箱より上／外形が複数の長方形／面が見た目とずれる／低い物／二段目の壁。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS_LAYER := 1 << 19
const G := 0.125          # 外形の格子
const RS := 0.25          # 屋根の高さの標本間隔
const FRONT_SNAP := 1.0   # Kit の慣例：入口の凹み（深さ ≤ 1.0 m・Kit は 0.9 m）は箱で塞ぐ（入れない扉）。arch-off で 17 棟が同じ形 → INTENTIONAL
const SIDE_SNAP := 0.2
const TOL := 0.15
const FILL_STEP := 0.10   # 8. 屋根の中の詰め物の段（v12 は 0.25：軒の下の壁の上端 0.2–0.3 m の隙間をカメラの ray が抜けた＝W9 FIX 最終驗收）
const STEP_H := 0.35
const FLOOR_MAX := 0.60   # 4b：地面から STEP_H〜これ＝床・縁（上面がほぼ平ら）。これより高い＝置き物（台・樽・金床）      # 玩家の step_height（characters/yoriichi/yoriichi_character.gd）。地面からこれより高い上面は登れない
var terrain_rid: RID


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for s in OS.get_cmdline_user_args():
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return d


var space: PhysicsDirectSpaceState3D
var dbg := false
var bxf: Transform3D
var inv: Transform3D


func _ray(lo: Vector3, ld: Vector3, length: float, back := true) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(bxf * lo, bxf * (lo + ld * length), VIS_LAYER)
	q.hit_back_faces = back
	var h := space.intersect_ray(q)
	if h.is_empty():
		return {}
	return {"p": inv * (h["position"] as Vector3), "n": inv.basis * (h["normal"] as Vector3)}


## 局部 (x, z) の真下の地面（地形の碰撞）の局部 y。建物・Shell の碰撞は除いて地形まで ray を通す。
func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(bxf * Vector3(x, 3.0, z), bxf * Vector3(x, -3.0, z), 0xFFFFFFFF & ~VIS_LAYER)
	var ex: Array[RID] = []
	for k in 12:
		q.exclude = ex
		var h := space.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["rid"] == terrain_rid:
			return (inv * (h["position"] as Vector3)).y
		ex.append(h["rid"])
	return NAN


## 高さ y の水平断面で、4 方向の『壁』の正射影の積。戻り値：bool の 2 次元配列 [ix][iz]
func _hull(y: float, x0: float, x1: float, z0: float, z1: float, box: Dictionary, snap: bool, confirm := false) -> Array:
	var nx := int(ceil((x1 - x0) / G))
	var nz := int(ceil((z1 - z0) / G))
	var front: Array = []   # 各 x の前面 z
	var back: Array = []
	for ix in nx:
		var x := x0 + (ix + 0.5) * G
		var hf := _wall_hit_c(Vector3(x, y, z1 + 2.0), Vector3(0, 0, -1), (z1 - z0) + 4.0, confirm)
		var hb := _wall_hit_c(Vector3(x, y, z0 - 2.0), Vector3(0, 0, 1), (z1 - z0) + 4.0, confirm)
		var zf: float = hf.z if hf != Vector3.INF else -INF
		var zb: float = hb.z if hb != Vector3.INF else INF
		if snap and zf != -INF:
			if zf < box["z1"] and box["z1"] - zf <= FRONT_SNAP:
				zf = box["z1"]
			elif absf(zf - box["z1"]) <= SIDE_SNAP:
				zf = box["z1"]
		if snap and zb != INF and absf(zb - box["z0"]) <= SIDE_SNAP:
			zb = box["z0"]
		front.append(zf)
		back.append(zb)
	var left: Array = []
	var right: Array = []
	for iz in nz:
		var z := z0 + (iz + 0.5) * G
		var hl := _wall_hit_c(Vector3(x0 - 2.0, y, z), Vector3(1, 0, 0), (x1 - x0) + 4.0, confirm)
		var hr := _wall_hit_c(Vector3(x1 + 2.0, y, z), Vector3(-1, 0, 0), (x1 - x0) + 4.0, confirm)
		var xl: float = hl.x if hl != Vector3.INF else INF
		var xr: float = hr.x if hr != Vector3.INF else -INF
		if snap and xl != INF and absf(xl - box["x0"]) <= SIDE_SNAP:
			xl = box["x0"]
		if snap and xr != -INF and absf(xr - box["x1"]) <= SIDE_SNAP:
			xr = box["x1"]
		left.append(xl)
		right.append(xr)
	if dbg:
		var fm := func(a: Array) -> String:
			var s := ""
			for v in a:
				s += ("  ---" if is_inf(v) else "%5.2f" % v) + " "
			return s
		print("[W9DBG] y=%.2f x0=%.2f z0=%.2f\n front %s\n back  %s\n left  %s\n right %s" % [y, x0, z0, fm.call(front), fm.call(back), fm.call(left), fm.call(right)])
	# 1 本の柱・格子の隙間・戸の隙間で外形が欠けないよう、各面の輪郭を窓 5（1.25 m）の中央値でならす
	front = _median5(front)
	back = _median5(back)
	left = _median5(left)
	right = _median5(right)
	var m: Array = []
	for ix in nx:
		var col: Array = []
		var x := x0 + (ix + 0.5) * G
		var col_def: bool = not is_inf(front[ix]) and not is_inf(back[ix])
		for iz in nz:
			var z := z0 + (iz + 0.5) * G
			var row_def: bool = not is_inf(left[iz]) and not is_inf(right[iz])
			var in_b: bool = z <= front[ix] + 1e-4 and z >= back[ix] - 1e-4
			var in_a: bool = x >= left[iz] - 1e-4 and x <= right[iz] + 1e-4
			if confirm and row_def != col_def:
				# 二段目：二階の正面が格子窓・軒の陰で前後から拾えない（左右だけ）こと、またはその逆がある → 拾えた方の 2 面だけで外形とする
				col.append(in_a if row_def else in_b)
			else:
				col.append(in_a and in_b)
		m.append(col)
	return m


static func _median5(a: Array) -> Array:
	var out: Array = []
	for i in a.size():
		var w: Array = []
		for k in range(i - 2, i + 3):
			if k >= 0 and k < a.size():
				w.append(a[k])
		w.sort()
		out.append(w[w.size() / 2])
	return out


func _wall_hit_c(lo: Vector3, ld: Vector3, length: float, confirm: bool) -> Vector3:
	## confirm：二段目用。同じ壁が上下 ±0.25 m でも同じ位置（±0.15 m）に立っていること＝高さ 0.5 m 以上の鉛直面だけを壁とする
	## （屋根の上の置き石・棟・鬼瓦・破風の小さな鉛直面を『二階の壁』と取り違えない）
	var p := _wall_hit(lo, ld, length)
	if not confirm or p == Vector3.INF:
		return p
	for dy in [-0.25, 0.25]:
		var q := _wall_hit(lo + Vector3(0, dy, 0), ld, length)
		if q == Vector3.INF or absf((q - p).dot(ld)) > 0.15:
			return Vector3.INF
	return p


func _wall_hit(lo: Vector3, ld: Vector3, length: float) -> Vector3:
	## 幅 0.24 m の『扇』（横に 0.03 m 間隔の平行 ray 9 本）で最初の壁を探し、いちばん手前の当たりを返す。
	## 細い ray 1 本だと格子（出格子・虫籠窓・竹垣）の隙間を素通りして奥の壁に当たり、格子の正面を『開いている』と誤認する。
	## 0.24 m より狭い隙間は壁扱い（プレイヤーのカプセル直径 0.6 m）。
	var perp := Vector3(-ld.z, 0, ld.x)
	var best := Vector3.INF
	var best_d := INF
	for k in 9:
		var off := (k - 4) * 0.03
		var p := _wall_hit1(lo + perp * off, ld, length)
		if p != Vector3.INF:
			var d := (p - lo).dot(ld)
			if d < best_d:
				best_d = d
				best = p - perp * off
	return best


func _wall_hit1(lo: Vector3, ld: Vector3, length: float) -> Vector3:
	## 最初の『壁』（外向きの表面で法線が水平に近い面）までたどる。裏面（軒裏・屋根の内側・反対側の妻壁の内側）は当てない（hit_back_faces=false）。
	## 屋根の斜面・地面は通り抜けて次を探す（最大 6 回）
	var o := lo
	var remain := length
	for k in 6:
		var h := _ray(o, ld, remain, false)
		if h.is_empty():
			return Vector3.INF
		var p: Vector3 = h["p"]
		if absf((h["n"] as Vector3).normalized().y) < 0.35:
			return p
		var adv := (p - o).length() + 0.02
		o = o + ld * adv
		remain -= adv
		if remain <= 0.0:
			break
	return Vector3.INF


func _rects(m: Array, x0: float, z0: float) -> Array:
	## 同じ x 区間（ix 範囲）が続く iz 行を 1 つの長方形にまとめる。戻り値 [ [ix0, ix1, iz0, iz1], ... ]（含む）
	var nx := m.size()
	var nz := (m[0] as Array).size() if nx > 0 else 0
	var runs: Array = []
	for iz in nz:
		var row_runs: Array = []
		var ix := 0
		while ix < nx:
			if m[ix][iz]:
				var s := ix
				while ix < nx and m[ix][iz]:
					ix += 1
				row_runs.append([s, ix - 1])
			else:
				ix += 1
		runs.append(row_runs)
	var out: Array = []
	var open: Dictionary = {}   # "s,e" → iz0
	for iz in nz + 1:
		var cur: Array = runs[iz] if iz < nz else []
		var keys := {}
		for r in cur:
			keys["%d,%d" % [r[0], r[1]]] = true
		for k in open.keys():
			if not keys.has(k):
				var se: PackedStringArray = (k as String).split(",")
				out.append([int(se[0]), int(se[1]), int(open[k]), iz - 1])
				open.erase(k)
		for k in keys:
			if not open.has(k):
				open[k] = iz
	return out


## 二段目の箱の『内側の辺』（一段目の長方形の縁でない辺）で、屋根の高さの段差（内側 0.35 m − 外側 0.35 m の中央値）の最大。
## 本当の二階・脇の高い棟＝低い屋根の上に壁が立つ → 段差 ≥ 0.6 m。切妻の妻壁（三角）を拾っただけ＝屋根は辺をまたいで連続 → 段差は小さい
## （Kit と同じく屋根の中には碰撞を入れない）。
func _roof_step(sx0: float, sx1: float, sz0: float, sz1: float, rx0: float, rx1: float, rz0: float, rz1: float, ytop: float) -> float:
	var best := -INF
	var sides := []
	if sx0 > rx0 + 0.3:
		sides.append([Vector3(sx0, 0, 0), Vector3(1, 0, 0), true])
	if sx1 < rx1 - 0.3:
		sides.append([Vector3(sx1, 0, 0), Vector3(-1, 0, 0), true])
	if sz0 > rz0 + 0.3:
		sides.append([Vector3(0, 0, sz0), Vector3(0, 0, 1), false])
	if sz1 < rz1 - 0.3:
		sides.append([Vector3(0, 0, sz1), Vector3(0, 0, -1), false])
	for s in sides:
		var steps: Array = []
		var along_x: bool = not s[2]
		var a0 := sx0 if along_x else sz0
		var a1 := sx1 if along_x else sz1
		var a := a0 + 0.25
		while a < a1 - 0.25:
			var base: Vector3 = s[0]
			var inward: Vector3 = s[1]
			var pt := Vector3(a, 0, base.z) if along_x else Vector3(base.x, 0, a)
			var hi := _roof_at((pt + inward * 0.35).x, (pt + inward * 0.35).z, ytop)
			var lo := _roof_at((pt - inward * 0.35).x, (pt - inward * 0.35).z, ytop)
			if not is_nan(hi) and not is_nan(lo):
				steps.append(hi - lo)
			a += RS
		if not steps.is_empty():
			best = maxf(best, _pct(steps, 0.5))
	return best


## 6. 面の照合：一段目・二段目の箱の外向きの面を見た目の壁と照合する（見えない壁を作らない）。
##    面の上に 0.5 m（横）× 0.25 m（高さ）の点を取り、外 0.8 m から扇の ray で壁を探す。壁が面から ±0.35 m 以内なら『覆われている』。
##    他の箱の中に入る点（内側の面）は数えない。一番下の行が覆われていない面（開口・入口の凹みを Kit の慣例で塞いだ面）は使わない。
##    下から見て、覆い率 < COVER の行が 2 行（0.5 m）続いた所の下端をその面の上限とし、箱の上面＝外向きの面の上限の最小。
const COVER := 0.4


func _face_cap(b: Dictionary, others: Array, orig: Dictionary) -> float:
	var y_lo0 := maxf(float(b["y0"]), 0.0) + 0.3
	var y_lo := y_lo0
	var y_hi := float(b["y1"]) - 0.1
	if y_hi <= y_lo + 0.25:
		return float(b["y1"])
	var cap := float(b["y1"])
	for f in [[Vector3(0, 0, 1), "z1", "x"], [Vector3(0, 0, -1), "z0", "x"], [Vector3(1, 0, 0), "x1", "z"], [Vector3(-1, 0, 0), "x0", "z"]]:
		var n: Vector3 = f[0]
		var plane: float = float(b[f[1]])
		var ax: String = f[2]
		# 元の箱の面と同じ面（Kit の慣例で決まった面）は、元の箱より上（この修正で上げた分）だけを照合する。
		# 元の箱の中に新しくできた面（開いた正面・庭の境）と二段目の箱は、下から全部照合する。
		var on_orig := absf(plane - float(orig[f[1]])) <= 0.25
		y_lo = y_lo0
		if on_orig and int(b["tier"]) == 1:
			y_lo = maxf(y_lo0, float(orig["y1"]) + 0.1)
		if y_lo > y_hi:
			continue
		var a0: float = float(b[ax + "0"]) + 0.15
		var a1: float = float(b[ax + "1"]) - 0.15
		var rows: Array = []   # [h, covered, total]
		var h := y_lo
		while h <= y_hi + 1e-4:
			var cov := 0
			var tot := 0
			var a := a0
			while a <= a1 + 1e-4:
				var pf := Vector3(a, h, plane) if ax == "x" else Vector3(plane, h, a)
				var pr := pf + n * 0.05
				var interior := false
				for o in others:
					if o != b and int(o["tier"]) >= 1 and pr.x > float(o["x0"]) and pr.x < float(o["x1"]) and pr.z > float(o["z0"]) and pr.z < float(o["z1"]) and h > float(o["y0"]) and h < float(o["y1"]):
						interior = true
						break
				if not interior:
					tot += 1
					var hp := _wall_hit(pf + n * 0.8, -n, 1.6)
					if hp != Vector3.INF and absf((hp - pf).dot(n)) <= 0.35:
						cov += 1
				a += 0.5
			rows.append([h, cov, tot])
			h += 0.25
		if rows.is_empty():
			continue
		if y_lo == y_lo0 and (int(rows[0][2]) == 0 or float(rows[0][1]) / int(rows[0][2]) < COVER):
			continue   # 一番下から壁が無い面＝開口を塞いだ面（使わない）
		for i in range(0 if y_lo != y_lo0 else 1, rows.size() - 1):
			var r0: Array = rows[i]
			var r1: Array = rows[i + 1]
			var bad0 := int(r0[2]) > 0 and float(r0[1]) / int(r0[2]) < COVER
			var bad1 := int(r1[2]) > 0 and float(r1[1]) / int(r1[2]) < COVER
			if bad0 and bad1:
				cap = minf(cap, float(r0[0]) - 0.125)
				break
	return cap


static func _snap(v: float, face: float) -> float:
	return face if absf(v - face) <= SIDE_SNAP else v


func _pct(a: Array, f: float) -> float:
	if a.is_empty():
		return NAN
	a.sort()
	return a[clampi(int(f * a.size()), 0, a.size() - 1)]


func _roof_at(x: float, z: float, ytop: float) -> float:
	var h := _ray(Vector3(x, ytop, z), Vector3.DOWN, ytop + 2.0)
	return (h["p"] as Vector3).y if not h.is_empty() else NAN


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	space = (v as Node3D).get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var ov := v.get_node("ArchW9R2P13")
	if _arg("--arch-off", "") == "1":
		# 比較基準：overlay を切った Kit だけの外観（W9R2 以前）。ここで出る理由は W9R2 前からある（PRE-EXISTING）
		ov.set("enabled", false)
		for i in 3:
			await physics_frame
	var ids: Array = []
	if _arg("--ids", "") != "":
		ids = Array(_arg("--ids", "").split(","))
	else:
		ids = L.SPECS.keys()
		ids.sort()
	var out := {}
	for id: String in ids:
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		bxf = body.global_transform
		inv = bxf.affine_inverse()
		var faces := PackedVector3Array()
		var la := AABB()
		var first := true
		var meshes: Array = []
		var kit := body.get_node_or_null("Kit/LOD0")
		if kit:
			for mi in kit.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
					meshes.append(mi)
		for c in ov.get_node(id).get_children():
			if c is MeshInstance3D and String(c.name) == "L0" and (c as MeshInstance3D).is_visible_in_tree():
				meshes.append(c)
		for mi: MeshInstance3D in meshes:
			for p in mi.mesh.get_faces():
				var wp := mi.global_transform * p
				faces.append(wp)
				var lp := inv * wp
				la = AABB(lp, Vector3.ZERO) if first else la.expand(lp)
				first = false
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS_LAYER
		vb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cp := ConcavePolygonShape3D.new()
		cp.backface_collision = true
		cp.set_faces(faces)
		cs.shape = cp
		vb.add_child(cs)
		root.add_child(vb)
		await physics_frame
		var box := {}
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var o := (c as CollisionShape3D).transform.origin
				var s := ((c as CollisionShape3D).shape as BoxShape3D).size
				box = {"x0": o.x - s.x / 2, "x1": o.x + s.x / 2, "y0": o.y - s.y / 2, "y1": o.y + s.y / 2, "z0": o.z - s.z / 2, "z1": o.z + s.z / 2}
		# 格子は元の箱の面に揃える（箱の面＝格子の境界）
		var x0: float = box["x0"] - ceilf((box["x0"] - la.position.x + 0.5) / G) * G
		var x1: float = box["x1"] + ceilf((la.end.x - box["x1"] + 0.5) / G) * G
		var z0: float = box["z0"] - ceilf((box["z0"] - la.position.z + 0.5) / G) * G
		var z1: float = box["z1"] + ceilf((la.end.z - box["z1"] + 0.5) / G) * G
		var ytop := la.end.y + 2.0
		# 1. 外形
		var m := _hull(1.2, x0, x1, z0, z1, box, true)
		var rects := _rects(m, x0, z0)
		var boxes: Array = []
		var notes: Array = []
		for r in rects:
			var rx0: float = _snap(x0 + r[0] * G, box["x0"])
			var rx1: float = _snap(x0 + (r[1] + 1) * G, box["x1"])
			var rz0: float = _snap(z0 + r[2] * G, box["z0"])
			var rz1: float = _snap(z0 + (r[3] + 1) * G, box["z1"])
			if (rx1 - rx0) * (rz1 - rz0) < 0.5 or minf(rx1 - rx0, rz1 - rz0) < 0.2:
				notes.append("小さい長方形を捨てた %.2f m²" % ((rx1 - rx0) * (rz1 - rz0)))
				continue
			var roofs: Array = []
			var x := rx0 + minf(RS, rx1 - rx0) * 0.5
			while x < rx1:
				var z := rz0 + minf(RS, rz1 - rz0) * 0.5
				while z < rz1:
					var ry := _roof_at(x, z, ytop)
					if not is_nan(ry):
						roofs.append(ry)
					z += RS
				x += RS
			var t1 := _pct(roofs, 0.03) - 0.10
			boxes.append({"x0": snappedf(rx0, 0.05), "x1": snappedf(rx1, 0.05), "z0": snappedf(rz0, 0.05), "z1": snappedf(rz1, 0.05), "y0": snappedf(box["y0"], 0.01), "y1": snappedf(t1, 0.05), "tier": 1})
			# 3. 二段目（t1 + 0.6／0.9／1.2 の順に試し、壁の外形が出た最初の高さを使う）
			var m2: Array = []
			var y2 := t1
			for dyt in [0.6, 0.9, 1.2]:
				dbg = _arg("--debug", "") == id
				y2 = t1 + dyt
				m2 = _hull(y2, rx0 - 0.5, rx1 + 0.5, rz0 - 0.5, rz1 + 0.5, box, false, true)
				dbg = false
				if not _rects(m2, rx0 - 0.5, rz0 - 0.5).is_empty():
					break
			for r2 in _rects(m2, rx0 - 0.5, rz0 - 0.5):
				var sx0: float = rx0 - 0.5 + r2[0] * G
				var sx1: float = rx0 - 0.5 + (r2[1] + 1) * G
				var sz0: float = rz0 - 0.5 + r2[2] * G
				var sz1: float = rz0 - 0.5 + (r2[3] + 1) * G
				sx0 = maxf(sx0, rx0)
				sx1 = minf(sx1, rx1)
				sz0 = maxf(sz0, rz0)
				sz1 = minf(sz1, rz1)
				if (sx1 - sx0) * (sz1 - sz0) < 3.0:
					continue
				var roofs2: Array = []
				var xx := sx0 + RS * 0.5
				while xx < sx1:
					var zz := sz0 + RS * 0.5
					while zz < sz1:
						var ry2 := _roof_at(xx, zz, ytop)
						if not is_nan(ry2):
							roofs2.append(ry2)
						zz += RS
					xx += RS
				var t2 := _pct(roofs2, 0.03) - 0.10
				# 本当の二階・高い棟か（切妻の妻壁の三角を拾っただけではないか）：
				#   (a) 内側の辺で屋根に 0.6 m 以上の段差がある、または
				#   (b) 0.6 m 上でも壁の外形がほぼ同じ（面積 75% 以上）＝鉛直の壁。三角は上ほど細る。
				var real := false
				if t2 - t1 >= 0.8 and minf(sx1 - sx0, sz1 - sz0) >= 1.0:
					if _roof_step(sx0, sx1, sz0, sz1, rx0, rx1, rz0, rz1, ytop) >= 0.6:
						real = true
					elif y2 + 0.6 < t2:
						var mh := _hull(y2 + 0.6, rx0 - 0.5, rx1 + 0.5, rz0 - 0.5, rz1 + 0.5, box, false, true)
						var cnt := 0
						var tot := 0
						for ix in mh.size():
							var cx := rx0 - 0.5 + (ix + 0.5) * G
							if cx < sx0 or cx > sx1:
								continue
							for iz in (mh[ix] as Array).size():
								var cz := rz0 - 0.5 + (iz + 0.5) * G
								if cz < sz0 or cz > sz1:
									continue
								tot += 1
								if mh[ix][iz]:
									cnt += 1
						real = tot > 0 and float(cnt) / tot >= 0.75
				if real:
					boxes.append({"x0": snappedf(sx0, 0.05), "x1": snappedf(sx1, 0.05), "z0": snappedf(sz0, 0.05), "z1": snappedf(sz1, 0.05), "y0": snappedf(t1 - 0.05, 0.05), "y1": snappedf(t2, 0.05), "tier": 2})
		# 4. 低い物（縁台・棚・腰掛け）：y 0.6 の外形が 1. の外形より外に出ている所。上面 ≥ 0.40 m（Auto-Step 0.35 で登れない）なら低い箱を足す
		var mlow := _hull(0.6, x0, x1, z0, z1, box, true)
		for ix in mlow.size():
			for iz in (mlow[ix] as Array).size():
				if m[ix][iz]:
					mlow[ix][iz] = false
		for r3 in _rects(mlow, x0, z0):
			var lx0: float = _snap(x0 + r3[0] * G, box["x0"])
			var lx1: float = _snap(x0 + (r3[1] + 1) * G, box["x1"])
			var lz0: float = _snap(z0 + r3[2] * G, box["z0"])
			var lz1: float = _snap(z0 + (r3[3] + 1) * G, box["z1"])
			if (lx1 - lx0) * (lz1 - lz0) < 0.3 or minf(lx1 - lx0, lz1 - lz0) < 0.2:
				continue
			var tops: Array = []
			var xl := lx0 + minf(RS, lx1 - lx0) * 0.5
			while xl < lx1:
				var zl := lz0 + minf(RS, lz1 - lz0) * 0.5
				while zl < lz1:
					var hl := _ray(Vector3(xl, 1.15, zl), Vector3.DOWN, 1.6)
					if not hl.is_empty():
						tops.append((hl["p"] as Vector3).y)
					zl += RS
				xl += RS
			var lt := _pct(tops, 0.5)
			if not is_nan(lt) and lt >= 0.40:
				boxes.append({"x0": snappedf(lx0, 0.05), "x1": snappedf(lx1, 0.05), "z0": snappedf(lz0, 0.05), "z1": snappedf(lz1, 0.05), "y0": snappedf(box["y0"], 0.01), "y1": snappedf(lt, 0.05), "tier": 0})
			else:
				notes.append("低い物 %.2f×%.2f m（上面 %.2f）は Auto-Step で登れる高さ → 碰撞なし" % [lx1 - lx0, lz1 - lz0, lt])
		# 4b. 元の箱の中で、新しい一段目の箱に入らない（＝この修正で歩けるようになる）所の置き物・床・台：
		#     0.125 m 格子で y 1.15 から下へ ray（表面のみ）。上面が地面から STEP_H（0.35）より高い（登れない）格子を長方形にまとめ、
		#     上面＝その長方形の 90 パーセンタイル（1.15 で頭打ち＝玩家 1.7 m は止まる）。吊り物（暖簾・提灯・看板）は 1.15 より上なので拾わない。
		#     4 方向の外形では、横が開いた土間・見世の置き物（左右に壁が無い）を拾えないための補い。
		var nxo := int(round((box["x1"] - box["x0"]) / G))
		var nzo := int(round((box["z1"] - box["z0"]) / G))
		var omask: Array = []
		var fmask: Array = []
		var otop: Array = []
		for ix in nxo:
			var mcol: Array = []
			var fcol: Array = []
			var tcol: Array = []
			var cx: float = box["x0"] + (ix + 0.5) * G
			for iz in nzo:
				var cz: float = box["z0"] + (iz + 0.5) * G
				var covered := false
				for b in boxes:
					if int(b["tier"]) == 1 and cx >= float(b["x0"]) and cx <= float(b["x1"]) and cz >= float(b["z0"]) and cz <= float(b["z1"]):
						covered = true
						break
				var t := NAN
				if not covered:
					var hd := _ray(Vector3(cx, 1.15, cz), Vector3.DOWN, 1.6, false)
					if not hd.is_empty():
						t = (hd["p"] as Vector3).y
				# 判定は『地面からの高さ > STEP_H』（以前は局部 y ≥ 0.40：局部の地面は −0.04〜−0.07 なので、地面から 0.38〜0.42 m の
				# 見世・戸口の床（MXC_004／MXC_007／MKT_030／RSW_014）を取りこぼし、玩家が床に 0.4 m 沈んでいた＝W9 FIX 最終驗收で確認）
				var gl := _ground(cx, cz) if not is_nan(t) else NAN
				var hh := t - gl if not (is_nan(t) or is_nan(gl)) else NAN
				mcol.append(not is_nan(hh) and hh > STEP_H and hh <= FLOOR_MAX)
				fcol.append(not is_nan(hh) and hh > FLOOR_MAX)
				tcol.append(t)
			omask.append(mcol)
			fmask.append(fcol)
			otop.append(tcol)
		# 床（地面から STEP_H〜FLOOR_MAX）と置き物（それより高い）は別々に長方形にする（v14 試行：床で全部が 1 つに繋がり、
		# 上面＝置き物の 90 パーセンタイル 1.1 m の箱が見世の前一面を塞いだ——MKT_025／RSW_014）
		for r4 in _rects(omask, box["x0"], box["z0"]) + _rects(fmask, box["x0"], box["z0"]):
			var ox0: float = box["x0"] + r4[0] * G
			var ox1: float = box["x0"] + (r4[1] + 1) * G
			var oz0: float = box["z0"] + r4[2] * G
			var oz1: float = box["z0"] + (r4[3] + 1) * G
			if (ox1 - ox0) * (oz1 - oz0) < 0.06:
				continue
			var ts: Array = []
			for ix in range(r4[0], r4[1] + 1):
				for iz in range(r4[2], r4[3] + 1):
					ts.append(otop[ix][iz])
			var ot := minf(_pct(ts, 0.9), 1.15)
			boxes.append({"x0": snappedf(ox0, 0.05), "x1": snappedf(ox1, 0.05), "z0": snappedf(oz0, 0.05), "z1": snappedf(oz1, 0.05), "y0": snappedf(box["y0"], 0.01), "y1": snappedf(ot, 0.05), "tier": 0})
		# 6. 面の照合（見えない壁を作らない）。上を削った箱が元の箱より高かったなら、削った高さの上の外形（後退した二階）を足して照合し直す
		var added: Array = []
		for b in boxes:
			if int(b["tier"]) < 1:
				continue
			var cap := _face_cap(b, boxes, box)
			if cap < float(b["y1"]) - 0.3:
				notes.append("面の照合：t%d x %.2f..%.2f z %.2f..%.2f の上面 %.2f → %.2f（その上は見た目の壁が面に無い）" % [b["tier"], b["x0"], b["x1"], b["z0"], b["z1"], b["y1"], cap])
				var old_top := float(b["y1"])
				b["y1"] = snappedf(cap, 0.05)
				if old_top > float(box["y1"]) + TOL:
					var bx0: float = b["x0"]
					var bx1: float = b["x1"]
					var bz0: float = b["z0"]
					var bz1: float = b["z1"]
					var mu := _hull(cap + 0.4, bx0 - 0.5, bx1 + 0.5, bz0 - 0.5, bz1 + 0.5, box, false, true)
					for ru in _rects(mu, bx0 - 0.5, bz0 - 0.5):
						var ux0: float = maxf(bx0 - 0.5 + ru[0] * G, bx0)
						var ux1: float = minf(bx0 - 0.5 + (ru[1] + 1) * G, bx1)
						var uz0: float = maxf(bz0 - 0.5 + ru[2] * G, bz0)
						var uz1: float = minf(bz0 - 0.5 + (ru[3] + 1) * G, bz1)
						if (ux1 - ux0) * (uz1 - uz0) < 2.0 or minf(ux1 - ux0, uz1 - uz0) < 1.0:
							continue
						var rr: Array = []
						var xu := ux0 + RS * 0.5
						while xu < ux1:
							var zu := uz0 + RS * 0.5
							while zu < uz1:
								var ryu := _roof_at(xu, zu, ytop)
								if not is_nan(ryu):
									rr.append(ryu)
								zu += RS
							xu += RS
						var tu := minf(_pct(rr, 0.03) - 0.10, old_top)
						if tu - cap < 0.5:
							continue
						var ub := {"x0": snappedf(ux0, 0.05), "x1": snappedf(ux1, 0.05), "z0": snappedf(uz0, 0.05), "z1": snappedf(uz1, 0.05), "y0": snappedf(cap - 0.05, 0.05), "y1": snappedf(tu, 0.05), "tier": 2}
						var ucap := _face_cap(ub, boxes + [ub], box)
						if ucap < float(ub["y1"]) - 0.3:
							ub["y1"] = snappedf(ucap, 0.05)
						if float(ub["y1"]) - float(ub["y0"]) >= 0.5:
							added.append(ub)
							notes.append("面の照合：上の外形 x %.2f..%.2f z %.2f..%.2f y %.2f..%.2f を足した" % [ub["x0"], ub["x1"], ub["z0"], ub["z1"], ub["y0"], ub["y1"]])
		boxes += added
		boxes = boxes.filter(func(b): return int(b["tier"]) != 2 or float(b["y1"]) - float(b["y0"]) >= 0.5)
		# 7. 開いた所の上に低い屋根（庇・見世の下屋・門の通路の天井）がある：その裏面から軒までの薄い板（tier 3）。
		#    カメラが低い庇を下からくぐって屋根の中・上に出ないため（修正前は元の箱の正面＝軒の線で止まっていた）。
		#    板の下面＝上向き ray が最初に当たる見た目（庇の裏・梁）の 10 パーセンタイル（≥ 2.0 m：玩家 1.7 m の頭上は空ける）、
		#    上面＝その範囲の屋根の 3 パーセンタイル − 0.10（軒の慣例）。厚さ < 0.15 m なら 0.15 m。下面が 3.5 m より高い所（高い屋根）は作らない。
		var cmask: Array = []
		var cceil: Array = []
		var croof: Array = []
		for ix in nxo:
			var mc: Array = []
			var cc: Array = []
			var rc: Array = []
			var cx: float = box["x0"] + (ix + 0.5) * G
			for iz in nzo:
				var cz: float = box["z0"] + (iz + 0.5) * G
				var covered := false
				for b in boxes:
					if int(b["tier"]) == 1 and cx >= float(b["x0"]) and cx <= float(b["x1"]) and cz >= float(b["z0"]) and cz <= float(b["z1"]):
						covered = true
						break
				var ce := NAN
				var rf := NAN
				if not covered:
					var hu := _ray(Vector3(cx, 1.2, cz), Vector3.UP, ytop)
					if not hu.is_empty():
						ce = (hu["p"] as Vector3).y
						rf = _roof_at(cx, cz, ytop)
				mc.append(not is_nan(ce) and ce >= 2.0 and ce <= 3.5 and not is_nan(rf))
				cc.append(ce)
				rc.append(rf)
			cmask.append(mc)
			cceil.append(cc)
			croof.append(rc)
		for r5 in _rects(cmask, box["x0"], box["z0"]):
			var cx0: float = box["x0"] + r5[0] * G
			var cx1: float = box["x0"] + (r5[1] + 1) * G
			var cz0: float = box["z0"] + r5[2] * G
			var cz1: float = box["z0"] + (r5[3] + 1) * G
			if (cx1 - cx0) * (cz1 - cz0) < 1.0 or minf(cx1 - cx0, cz1 - cz0) < 0.5:
				continue
			var ces: Array = []
			var rfs: Array = []
			for ix in range(r5[0], r5[1] + 1):
				for iz in range(r5[2], r5[3] + 1):
					ces.append(cceil[ix][iz])
					rfs.append(croof[ix][iz])
			var cb := maxf(_pct(ces, 0.1), 2.0)
			var ct := maxf(_pct(rfs, 0.03) - 0.10, cb + 0.15)
			boxes.append({"x0": snappedf(cx0, 0.05), "x1": snappedf(cx1, 0.05), "z0": snappedf(cz0, 0.05), "z1": snappedf(cz1, 0.05), "y0": snappedf(cb, 0.05), "y1": snappedf(ct, 0.05), "tier": 3})
			notes.append("庇の板 x %.2f..%.2f z %.2f..%.2f y %.2f..%.2f" % [cx0, cx1, cz0, cz1, cb, ct])
		# 8. 屋根の中の詰め物（tier 4）：元の箱のうち『見える屋根の下』にあった分は残す（カメラが屋根の中へ入らない＝修正前と同じ。
		#    屋根の上に出ていた分だけを削る）。一段目の各長方形の上で、格子（0.25 m）ごとに 上限＝min(元の箱の上面, 屋根の上面 − 0.05)、
		#    FILL_STEP の段で積む（段 L の長方形＝上限 ≥ L の格子・面積 ≥ 0.5 m²・箱は一段目の上面から L まで）。
		var fills: Array = []
		for b in boxes:
			if int(b["tier"]) != 1:
				continue
			var bt: float = float(b["y1"])
			if float(box["y1"]) < bt + FILL_STEP:
				continue
			var fx0: float = float(b["x0"])
			var fz0: float = float(b["z0"])
			var nfx := int(round((float(b["x1"]) - fx0) / 0.25))
			var nfz := int(round((float(b["z1"]) - fz0) / 0.25))
			if nfx <= 0 or nfz <= 0:
				continue
			var ft: Array = []
			for ix in nfx:
				var col: Array = []
				for iz in nfz:
					var rf := _roof_at(fx0 + (ix + 0.5) * 0.25, fz0 + (iz + 0.5) * 0.25, ytop)
					col.append(minf(float(box["y1"]), rf - 0.05) if not is_nan(rf) else -INF)
				ft.append(col)
			var lv := bt + FILL_STEP
			while lv <= float(box["y1"]) + 1e-3:
				var fm: Array = []
				for ix in nfx:
					var col: Array = []
					for iz in nfz:
						col.append(float(ft[ix][iz]) >= lv)
					fm.append(col)
				for rr in _rects(fm, fx0, fz0):
					var rx0: float = fx0 + rr[0] * 0.25
					var rx1: float = fx0 + (rr[1] + 1) * 0.25
					var rz0: float = fz0 + rr[2] * 0.25
					var rz1: float = fz0 + (rr[3] + 1) * 0.25
					if (rx1 - rx0) * (rz1 - rz0) < 0.5:
						continue
					fills.append({"x0": snappedf(rx0, 0.05), "x1": snappedf(rx1, 0.05), "z0": snappedf(rz0, 0.05), "z1": snappedf(rz1, 0.05), "y0": snappedf(bt - 0.05, 0.05), "y1": snappedf(lv, 0.05), "tier": 4})
				lv += FILL_STEP
		# 同じ xz の長方形が続く段は一番上だけ残す（下の段はその中に入る）
		var keep: Array = []
		for f in fills:
			var dominated := false
			for g in fills:
				if g != f and float(g["y1"]) > float(f["y1"]) and absf(float(g["x0"]) - float(f["x0"])) < 0.01 and absf(float(g["x1"]) - float(f["x1"])) < 0.01 and absf(float(g["z0"]) - float(f["z0"])) < 0.01 and absf(float(g["z1"]) - float(f["z1"])) < 0.01:
					dominated = true
					break
			if not dominated:
				keep.append(f)
		if not keep.is_empty():
			notes.append("屋根の中の詰め物 %d 個（元の箱の上面 %.2f まで・屋根の下だけ）" % [keep.size(), box["y1"]])
		boxes += keep
		# 屋根の高さ（元の箱の範囲・内側 0.3 m）
		var roofs_box: Array = []
		var xb: float = box["x0"] + 0.3
		while xb <= box["x1"] - 0.3:
			var zb: float = box["z0"] + 0.3
			while zb <= box["z1"] - 0.3:
				var ry3 := _roof_at(xb, zb, ytop)
				if not is_nan(ry3):
					roofs_box.append(ry3)
				zb += G
			xb += G
		# 5. 適用の判定（明示の閾値）
		var reasons: Array = []
		var rp03: float = _pct(roofs_box, 0.03)
		if box["y1"] - rp03 > TOL:
			reasons.append("箱が屋根より %.2f m 上に出る（カメラの見えない天井）" % (box["y1"] - rp03))
		if rp03 - 0.10 - box["y1"] >= 0.6:
			reasons.append("見える壁が箱の上に %.2f m（カメラが壁に入る）" % (rp03 - 0.10 - box["y1"]))
		var fx0 := INF
		var fx1 := -INF
		var fz0 := INF
		var fz1 := -INF
		for b in boxes:
			if int(b["tier"]) == 1:
				fx0 = minf(fx0, b["x0"])
				fx1 = maxf(fx1, b["x1"])
				fz0 = minf(fz0, b["z0"])
				fz1 = maxf(fz1, b["z1"])
		var tier1 := boxes.filter(func(b): return int(b["tier"]) == 1)
		if tier1.size() > 1:
			reasons.append("外形が %d 個の長方形（L 字・後退・細り）" % tier1.size())
		for pair in [["前", box["z1"] - fz1], ["後", fz0 - box["z0"]], ["左", fx0 - box["x0"]], ["右", box["x1"] - fx1]]:
			if pair[1] > 0.5:
				reasons.append("%s面が見た目より %.2f m 外（見えない壁）" % pair)
			elif pair[1] < -0.2:
				reasons.append("%s面の見た目が箱より %.2f m 外（碰撞なし）" % [pair[0], -pair[1]])
		if boxes.any(func(b): return int(b["tier"]) == 0):
			reasons.append("低い物の箱")
		for b in boxes:
			if int(b["tier"]) == 2 and float(b["y1"]) - float(box["y1"]) > TOL:
				reasons.append("二段目の壁 %.2f m（箱の上）" % (float(b["y1"]) - float(box["y1"])))
				break
		out[id] = {"apply": not reasons.is_empty(), "reasons": reasons, "orig": box, "fit": boxes, "notes": notes, "roof_min_in_orig": _pct(roofs_box, 0.0), "roof_p03_in_orig": _pct(roofs_box, 0.03), "vis_aabb": [[la.position.x, la.position.y, la.position.z], [la.end.x, la.end.y, la.end.z]]}
		var desc := ""
		for b in boxes:
			desc += " [t%d x %.2f..%.2f z %.2f..%.2f y %.2f..%.2f]" % [b["tier"], b["x0"], b["x1"], b["z0"], b["z1"], b["y0"], b["y1"]]
		print("[W9FIT] %s %s orig x %.2f..%.2f z %.2f..%.2f top %.2f | roof p03 %.2f |%s %s %s" % [id, "APPLY" if out[id]["apply"] else "keep ", box["x0"], box["x1"], box["z0"], box["z1"], box["y1"], out[id]["roof_p03_in_orig"], desc, str(reasons), str(notes) if not notes.is_empty() else ""])
		vb.queue_free()
		await physics_frame
	var f := FileAccess.open(_arg("--out", "user://colfit.json"), FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + _arg("--out", ""))
		quit(1)
		return
	f.store_string(JSON.stringify(out, " "))
	f.close()
	quit(0)
