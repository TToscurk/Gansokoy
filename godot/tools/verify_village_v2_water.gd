extends SceneTree
## 人間之里 V2：P2 Water gate（headless）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_water.gd
##
## 三個水體（主河 MainRiver、水渠 Canal、西溪 WestStream）各自檢查：
##   水面邊外露   水面網格的外緣（圖框邊除外）每 0.5 m 取樣，底下地形低於水面 > EDGE_TOL ＝ 水面邊浮空、看得到側面
##   露底         與河道連通、低於水位的地面（河床／岸腳）卻沒有水面蓋住 ＝ 乾河床缺口
##   穿岸         水面網格在地面之上、但離河道濕區 > 2 m ＝ 水面蓋到岸上或漂在窪地上
##   負水深       沿中心線每 2 m 的橫剖面最深點（主槽）水深 ≤ MIN_DEPTH ＝ 河道斷水
##   形態         主河：主槽深度沿河要有變化、彎道比直段深、外岸比內岸深（P2 裁示 5）
##                西溪：深淺與寬度變化、潭與淺灘都要有（裁示 7）
##                水渠：工程深度穩定（裁示 6）
## 另查：每座橋面頂高出水面 ≥ BRIDGE_FREEBOARD（灰模箱底入水另列 INFO）。
## 水位取自水面網格本身（中心線每 1 m 一站），不依賴產生器 meta。

const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const WLib := preload("res://tools/village_v2_water_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")

const EDGE_TOL := 0.01
const WET_TOL := 0.01
const MIN_DEPTH := 0.10
const RASTER := 1.0
const REACH := 20.0
const BRIDGE_FREEBOARD := 0.30
# 主河形態門檻
const RIVER_RANGE_MIN := 0.8      # 主槽深度 p90 − p10
const RIVER_BEND_GAIN_MIN := 0.5  # 彎道（|b| ≥ 0.6）平均主槽深 − 直段（|b| ≤ 0.25）
const RIVER_OUTER_MIN := 0.4      # 彎道（|b| ≥ 0.5）外岸 ν=0.5 深 − 內岸 ν=0.5 深
# 西溪
const STREAM_RANGE_MIN := 0.4
const STREAM_SHALLOW := 0.30
const STREAM_POOL := 0.60
const STREAM_FRAC_MIN := 0.10
const STREAM_WIDTH_RANGE_MIN := 1.5
# 水渠
const CANAL_DEPTH_MIN := 0.5

var L: Dictionary
var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var fails := 0
var bodies: Array = []   # {name, node, pts, hw(PackedFloat32Array per pt), cells, lv}


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[WATER] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _run() -> void:
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var W: Dictionary = L["water"]
	var rhw := PackedFloat32Array()
	for x in W["MainRiver"]["half_w"]:
		rhw.append(float(x))
	_add_body("MainRiver", v.get_node("Water/MainRiver"), TLib.pts(W["MainRiver"]["pts"]), rhw)
	_add_body("Canal", v.get_node("Water/Canal"), TLib.pts(W["Canal"]["pts"]), _const_hw(W["Canal"]))
	for s in W["Streams"]:
		_add_body(String(s["name"]), v.get_node("Water/Streams/" + String(s["name"])), TLib.pts(s["pts"]), _const_hw(s))
	var tris := 0
	for b in bodies:
		tris += (b["faces"] as PackedVector3Array).size() / 3
	print("[WATER]   水面網格 %d 個、三角面 %d" % [bodies.size(), tris])
	for b in bodies:
		_check_body(b)
	_check_form()
	_check_bridges()
	print("[WATER] 結果：%d 項失敗" % fails)
	quit(fails)


func _const_hw(d: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for _p in d["pts"]:
		out.append(float(d["half_w"]))
	return out


func _add_body(name: String, node: Node, pts: PackedVector2Array, hw: PackedFloat32Array) -> void:
	var faces := PackedVector3Array()
	for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or m.mesh is PrimitiveMesh:
			continue
		for p in m.mesh.get_faces():
			faces.append(m.global_transform * p)
	var cells := {}
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var bb := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(faces[t + 1].x, faces[t + 1].z)).expand(Vector2(faces[t + 2].x, faces[t + 2].z))
		for cx in range(floori(bb.position.x / 4.0), floori(bb.end.x / 4.0) + 1):
			for cz in range(floori(bb.position.y / 4.0), floori(bb.end.y / 4.0) + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key):
					cells[key] = PackedInt32Array()
				var arr: PackedInt32Array = cells[key]
				arr.append(t)
				cells[key] = arr
	var b := {"name": name, "pts": pts, "hw": hw, "faces": faces, "cells": cells}
	# 水位剖面：中心線每 1 m 一站，取水面網格高度
	var cum := _cum(pts)
	var total := cum[cum.size() - 1]
	var lv := PackedFloat32Array()
	var last := NAN
	for i in int(ceil(total)) + 1:
		var p := _along(pts, cum, minf(float(i), total))
		var w := _wy(b, p)
		if is_nan(w):
			w = last
		lv.append(w)
		last = w
	# 開頭若 NaN，往後補
	for i in range(lv.size() - 2, -1, -1):
		if is_nan(lv[i]):
			lv[i] = lv[i + 1]
	b["cum"] = cum
	b["lv"] = lv
	bodies.append(b)


func _cum(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k - 1].distance_to(pts[k]))
	return cum


func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var seg := maxf(cum[k + 1] - cum[k], 1e-6)
			return pts[k].lerp(pts[k + 1], clampf((s - cum[k]) / seg, 0.0, 1.0))
	return pts[0]


func _near(pts: PackedVector2Array, p: Vector2) -> Vector3:
	var best := Vector3(INF, 0, 0)
	for k in pts.size() - 1:
		var a := pts[k]
		var ab := pts[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best.x:
			best = Vector3(d, k, t)
	return best


## 水面網格在 p 的高度（沒有水面 → NaN）。網格水面的頂點落在 2 m 格點上：取樣點剛好在頂點／邊上時
## point_is_inside_triangle 兩邊都判外，所以先偏移 1–2 cm（水面平順，高度誤差 < 1 mm）。
func _wy(b: Dictionary, p0: Vector2) -> float:
	var p := p0 + Vector2(0.013, 0.017)
	var key := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	if not (b["cells"] as Dictionary).has(key):
		return NAN
	var f: PackedVector3Array = b["faces"]
	var best := NAN
	for t in b["cells"][key]:
		var a := f[t]
		var c := f[t + 1]
		var d := f[t + 2]
		var bc := Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
		if bc:
			var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 500.0, p.y), Vector3.DOWN, a, c, d)
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 500.0, p.y), Vector3.DOWN, a, d, c)
			if hit != null:
				best = maxf(best, (hit as Vector3).y) if not is_nan(best) else (hit as Vector3).y
	return best


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
	var ex: Array[RID] = []
	for i in 8:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var col := hit["collider"] as CollisionObject3D
		if col.get_rid() == terrain_rid:
			return float(hit["position"].y)
		ex.append(col.get_rid())
	return NAN


func _level(b: Dictionary, r: Vector3) -> float:
	var s := WLib.station(b["cum"], r)
	var lv: PackedFloat32Array = b["lv"]
	var i := clampi(int(s), 0, lv.size() - 2)
	return lerpf(lv[i], lv[i + 1], clampf(s - i, 0.0, 1.0))


func _hw(b: Dictionary, r: Vector3) -> float:
	var hw: PackedFloat32Array = b["hw"]
	return lerpf(hw[int(r.y)], hw[int(r.y) + 1], r.z)


## 點 p 屬於哪個水體（離岸最近者）
func _owner(p: Vector2) -> int:
	var best := -1
	var be := INF
	for i in bodies.size():
		var r := _near(bodies[i]["pts"], p)
		var e := r.x - _hw(bodies[i], r)
		if e < be:
			be = e
			best = i
	return best


func _check_body(b: Dictionary) -> void:
	var name: String = b["name"]
	var bi := bodies.find(b)
	var F: Dictionary = L["frame"]
	var fx0 := float(F["x0"])
	var fx1 := float(F["x1"])
	var fz0 := float(F["z0"])
	var fz1 := float(F["z1"])
	# 1) 水面網格外緣
	var f: PackedVector3Array = b["faces"]
	var cnt := {}
	for t in range(0, f.size(), 3):
		for e in 3:
			var a := f[t + e]
			var c := f[t + (e + 1) % 3]
			var ka := Vector3i(roundi(a.x * 100.0), roundi(a.y * 100.0), roundi(a.z * 100.0))
			var kc := Vector3i(roundi(c.x * 100.0), roundi(c.y * 100.0), roundi(c.z * 100.0))
			var key := [ka, kc] if (ka.x < kc.x or (ka.x == kc.x and ka.z <= kc.z)) else [kc, ka]
			var ks := str(key)
			if cnt.has(ks):
				cnt[ks][0] += 1
			else:
				cnt[ks] = [1, a, c]
	var n_edge := 0
	var bad_edge := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for ks in cnt:
		var e: Array = cnt[ks]
		if int(e[0]) != 1:
			continue
		var a: Vector3 = e[1]
		var c: Vector3 = e[2]
		var on_frame := (absf(a.x - fx0) < 0.6 and absf(c.x - fx0) < 0.6) or (absf(a.x - fx1) < 0.6 and absf(c.x - fx1) < 0.6) \
			or (absf(a.z - fz0) < 0.6 and absf(c.z - fz0) < 0.6) or (absf(a.z - fz1) < 0.6 and absf(c.z - fz1) < 0.6)
		if on_frame:
			continue
		var ln := Vector2(a.x, a.z).distance_to(Vector2(c.x, c.z))
		var ns := maxi(1, int(ceil(ln / 0.5)))
		for s in ns + 1:
			var q := a.lerp(c, float(s) / ns)
			if q.x < fx0 + 0.5 or q.x > fx1 - 0.5 or q.z < fz0 + 0.5 or q.z > fz1 - 0.5:
				continue
			var g := _ground(q.x, q.z)
			if is_nan(g):
				continue
			n_edge += 1
			if g < q.y - EDGE_TOL:
				bad_edge += 1
				if q.y - g > worst:
					worst = q.y - g
					worst_at = Vector2(q.x, q.z)
	check("%s 水面邊外露：外緣 %d 取樣點中 %d 點浮空（地形低於水面 > %.2f m），最大 %.2f m @ (%.0f, %.0f)" % [
		name, n_edge, bad_edge, EDGE_TOL, worst, worst_at.x, worst_at.y], n_edge > 0 and bad_edge == 0)
	# 2) 1 m 網格：濕區（與中心線連通、低於水位）、露底、穿岸
	var pts: PackedVector2Array = b["pts"]
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	bb = bb.grow(REACH + 16.0)
	var ox := floorf(maxf(bb.position.x, fx0))
	var oz := floorf(maxf(bb.position.y, fz0))
	var gw := int((minf(bb.end.x, fx1) - ox) / RASTER) + 1
	var gh := int((minf(bb.end.y, fz1) - oz) / RASTER) + 1
	var G := PackedFloat32Array()
	G.resize(gw * gh)
	var WY := PackedFloat32Array()
	WY.resize(gw * gh)
	var LV := PackedFloat32Array()
	LV.resize(gw * gh)
	var mine := PackedByteArray()
	mine.resize(gw * gh)
	var wet := PackedByteArray()
	wet.resize(gw * gh)
	var queue: Array[int] = []
	for j in gh:
		for i in gw:
			var k := j * gw + i
			var p := Vector2(ox + i * RASTER, oz + j * RASTER)
			var r := _near(pts, p)
			var hw := _hw(b, r)
			if r.x - hw > REACH or _owner(p) != bi:
				G[k] = NAN
				continue
			mine[k] = 1
			G[k] = _ground(p.x, p.y)
			WY[k] = _wy(b, p)
			LV[k] = _level(b, r)
			if r.x < hw * 0.3 and G[k] < LV[k] - WET_TOL:
				wet[k] = 1
				queue.append(k)
	var qi := 0
	while qi < queue.size():
		var k: int = queue[qi]
		qi += 1
		var i := k % gw
		var j := k / gw
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ii: int = i + o.x
			var jj: int = j + o.y
			if ii < 0 or jj < 0 or ii >= gw or jj >= gh:
				continue
			var kk := jj * gw + ii
			if mine[kk] == 1 and wet[kk] == 0 and not is_nan(G[kk]) and G[kk] < LV[kk] - WET_TOL:
				wet[kk] = 1
				queue.append(kk)
	var n_wet := 0
	var bare := 0
	var bare_d := 0.0
	var bare_at := Vector2.ZERO
	var over := 0
	var over_d := 0.0
	var over_at := Vector2.ZERO
	for j in gh:
		for i in gw:
			var k := j * gw + i
			if mine[k] == 0 or is_nan(G[k]):
				continue
			var p := Vector2(ox + i * RASTER, oz + j * RASTER)
			if wet[k] == 1:
				# 圖框邊上的點：水面到圖框為止（外面是邊界牆），取樣偏移會落到框外
				if p.x > fx1 - 0.5 or p.y > fz1 - 0.5 or p.x < fx0 + 0.5 or p.y < fz0 + 0.5:
					continue
				n_wet += 1
				if is_nan(WY[k]):
					bare += 1
					if LV[k] - G[k] > bare_d:
						bare_d = LV[k] - G[k]
						bare_at = p
			elif not is_nan(WY[k]) and WY[k] > G[k] + 0.02:
				var near_wet := false
				for dj in range(-2, 3):
					for di in range(-2, 3):
						var ii := i + di
						var jj := j + dj
						if ii >= 0 and jj >= 0 and ii < gw and jj < gh and wet[jj * gw + ii] == 1:
							near_wet = true
				if not near_wet:
					over += 1
					if WY[k] - G[k] > over_d:
						over_d = WY[k] - G[k]
						over_at = p
	check("%s 露底：與河道連通、低於水位的 %d 點中 %d 點沒有水面（最深 %.2f m @ (%.0f, %.0f)）" % [
		name, n_wet, bare, bare_d, bare_at.x, bare_at.y], n_wet > 0 and bare == 0)
	check("%s 穿岸：水面在地面上、離濕區 > 2 m 的點 %d（最大 %.2f m @ (%.0f, %.0f)）" % [
		name, over, over_d, over_at.x, over_at.y], over == 0)
	# 3) 橫剖面：每 2 m 一站
	var cum: PackedFloat32Array = b["cum"]
	var total := cum[cum.size() - 1]
	var secs: Array = []
	var s := 1.0
	while s < total - 1.0:
		var c := _along(pts, cum, s)
		var tg := (_along(pts, cum, minf(s + 1.0, total)) - _along(pts, cum, maxf(s - 1.0, 0.0))).normalized()
		var nrm := Vector2(-tg.y, tg.x)
		var r := _near(pts, c)
		var hw := _hw(b, r)
		var lvl := _level(b, r)
		var dmax := -INF
		var ws := 0
		var dl := NAN
		var dr := NAN
		var d0 := NAN
		var t := -(hw + 6.0)
		while t <= hw + 6.0:
			var q := c + nrm * t
			if q.x >= fx0 and q.x <= fx1 and q.y >= fz0 and q.y <= fz1 and _owner(q) == bi:
				var g := _ground(q.x, q.y)
				if not is_nan(g):
					var d := lvl - g
					if absf(t) <= hw:
						dmax = maxf(dmax, d)
					if d > WET_TOL:
						ws += 1
					if absf(t) < 0.26:
						d0 = d
					if absf(t - hw * 0.5) < 0.26:
						dl = d
					if absf(t + hw * 0.5) < 0.26:
						dr = d
			t += 0.5
		secs.append({"s": s, "c": c, "dmax": dmax, "wet_w": ws * 0.5, "d_pos": dl, "d_neg": dr, "d0": d0})
		s += 2.0
	b["secs"] = secs
	var dry := 0
	var dry_at := Vector2.ZERO
	var dmin := INF
	var ds := PackedFloat32Array()
	for sc in secs:
		var dm := float(sc["dmax"])
		ds.append(dm)
		dmin = minf(dmin, dm)
		if dm < MIN_DEPTH:
			dry += 1
			dry_at = sc["c"]
	ds.sort()
	b["depths_sorted"] = ds
	check("%s 負水深：%d 站主槽最深點中 %d 站 < %.2f m（最淺 %.2f m @ (%.0f, %.0f)）；主槽深 p10/p50/p90 %.2f/%.2f/%.2f m" % [
		name, secs.size(), dry, MIN_DEPTH, dmin, dry_at.x, dry_at.y, _pct(ds, 0.1), _pct(ds, 0.5), _pct(ds, 0.9)],
		secs.size() > 0 and dry == 0)


func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return NAN
	return a[clampi(int(round(q * (a.size() - 1))), 0, a.size() - 1)]


func _body(name: String) -> Dictionary:
	for b in bodies:
		if b["name"] == name:
			return b
	return {}


func _check_form() -> void:
	var WF: Dictionary = L.get("water_form", {})
	# 主河
	var rb := _body("MainRiver")
	var rf: Dictionary = WF.get("MainRiver", {"curv_win": 12.0, "bend_r_full": 60.0})
	var kap := WLib.curvature(rb["pts"], float(rf["curv_win"]))
	var ds: PackedFloat32Array = rb["depths_sorted"]
	var rng := _pct(ds, 0.9) - _pct(ds, 0.1)
	check("主河主槽深度沿河變化 p90−p10 %.2f m（≥ %.1f；P1 為固定 2.40 m）" % [rng, RIVER_RANGE_MIN], rng >= RIVER_RANGE_MIN)
	var bend_d := 0.0
	var bend_n := 0
	var str_d := 0.0
	var str_n := 0
	var asym := 0.0
	var asym_n := 0
	for sc in rb["secs"]:
		var bb := WLib.bend(rf, kap, float(sc["s"]))
		if absf(bb) >= 0.6:
			bend_d += float(sc["dmax"])
			bend_n += 1
		elif absf(bb) <= 0.25:
			str_d += float(sc["dmax"])
			str_n += 1
		if absf(bb) >= 0.5 and not is_nan(float(sc["d_pos"])) and not is_nan(float(sc["d_neg"])):
			# b > 0 → 往 +ν 側轉，彎心在 +ν，外岸在 −ν
			var outer := float(sc["d_neg"]) if bb > 0.0 else float(sc["d_pos"])
			var inner := float(sc["d_pos"]) if bb > 0.0 else float(sc["d_neg"])
			asym += outer - inner
			asym_n += 1
	var gain := (bend_d / maxf(bend_n, 1)) - (str_d / maxf(str_n, 1))
	check("主河彎道（%d 站）平均主槽深 − 直段（%d 站）＝ %.2f m（≥ %.1f）" % [bend_n, str_n, gain, RIVER_BEND_GAIN_MIN],
		bend_n > 3 and str_n > 3 and gain >= RIVER_BEND_GAIN_MIN)
	var am := asym / maxf(asym_n, 1)
	check("主河彎道（%d 站）外岸半寬處比內岸深 %.2f m（≥ %.1f）" % [asym_n, am, RIVER_OUTER_MIN], asym_n > 3 and am >= RIVER_OUTER_MIN)
	# 西溪
	var sb := _body("WestStream")
	if not sb.is_empty():
		var sd: PackedFloat32Array = sb["depths_sorted"]
		var srng := _pct(sd, 0.9) - _pct(sd, 0.1)
		var sh := 0
		var pl := 0
		var wmin := INF
		var wmax := -INF
		for x in sd:
			if x <= STREAM_SHALLOW:
				sh += 1
			if x >= STREAM_POOL:
				pl += 1
		for sc in sb["secs"]:
			wmin = minf(wmin, float(sc["wet_w"]))
			wmax = maxf(wmax, float(sc["wet_w"]))
		var n := maxf(sd.size(), 1)
		check("西溪主槽深 p90−p10 %.2f m（≥ %.1f）" % [srng, STREAM_RANGE_MIN], srng >= STREAM_RANGE_MIN)
		check("西溪淺灘（≤ %.2f m）%.0f%%、潭（≥ %.2f m）%.0f%%（各 ≥ %.0f%%）" % [
			STREAM_SHALLOW, 100.0 * sh / n, STREAM_POOL, 100.0 * pl / n, 100.0 * STREAM_FRAC_MIN],
			sh / n >= STREAM_FRAC_MIN and pl / n >= STREAM_FRAC_MIN)
		check("西溪濕寬 %.1f–%.1f m（變化 ≥ %.1f）" % [wmin, wmax, STREAM_WIDTH_RANGE_MIN], wmax - wmin >= STREAM_WIDTH_RANGE_MIN)
	# 水渠
	var cb := _body("Canal")
	var cd: PackedFloat32Array = cb["depths_sorted"]
	check("水渠工程深度：主槽深 p10/p50/p90 %.2f/%.2f/%.2f m（最淺 ≥ %.1f）" % [
		_pct(cd, 0.1), _pct(cd, 0.5), _pct(cd, 0.9), CANAL_DEPTH_MIN], cd.size() > 0 and cd[0] >= CANAL_DEPTH_MIN)


## 橋與水面：P2 管的是水面高度 → 驗「橋面頂高出水面」≥ BRIDGE_FREEBOARD（水不淹橋面）。
## 灰模橋是 0.6 m 厚的整塊箱（P4 Greybox／P5 換正式橋），箱底是否入水另列 INFO，不在 P2 修。
func _check_bridges() -> void:
	for br in v.get_node("Roads/Bridges").get_children():
		var n3 := br as Node3D
		var c := Vector2(n3.global_position.x, n3.global_position.z)
		# _box：holder 位置＝箱底，箱高 0.6 m
		var under := n3.global_position.y
		var top := under + 0.6
		var wy := NAN
		for b in bodies:
			var w := _wy(b, c)
			if not is_nan(w):
				wy = w if is_nan(wy) else maxf(wy, w)
		check("%s 橋面頂 %.2f − 水面 %.2f ＝ 出水高 %.2f m（≥ %.2f）" % [br.name, top, wy, top - wy, BRIDGE_FREEBOARD],
			not is_nan(wy) and top - wy >= BRIDGE_FREEBOARD)
		print("[WATER]   INFO %s 灰模箱底 %.2f − 水面 %.2f ＝ %.2f m%s" % [br.name, under, wy, under - wy,
			"（箱底入水：P4 灰模橋厚度問題）" if under < wy else ""])
