extends RefCounted
## P13 W4：見える石の上面と歩ける面（斜坡碰撞 RampCollision）のずれの測定。probe_w4_visual_vs_collision.gd と verify_w4_pilot.gd が共用。
## d = 見える石の上面 − 斜坡碰撞（足の高さ）。正＝足が石に沈む／負＝足が石から浮く。
## 斜坡碰撞は実際の物理射線（RampCollision だけを拾う）、見える面は上向きの三角形の最大高さ（頂＝苔・落葉の貼り物を含む）。
## 既存の SWALK W1 は generator の計画〔LIB.steps〕と斜坡の差を見る＝overlay が差し替えた見える面は対象外。ここがその穴を埋める。


class TopGrid:
	var tri := PackedVector3Array()
	var grid := {}
	var cell := 0.25

	func add_mesh(m: Mesh) -> void:
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var has_idx: bool = idx != null and (idx as PackedInt32Array).size() > 0
			var n: int = ((idx as PackedInt32Array).size() if has_idx else vs.size()) / 3
			for t in n:
				var i0: int = idx[t * 3] if has_idx else t * 3
				var i1: int = idx[t * 3 + 1] if has_idx else t * 3 + 1
				var i2: int = idx[t * 3 + 2] if has_idx else t * 3 + 2
				var a := vs[i0]
				var b := vs[i1]
				var c := vs[i2]
				var nr := (c - a).cross(b - a)
				if nr.length_squared() < 1e-12:
					continue
				if nr.normalized().y < 0.3:
					continue
				var tid: int = tri.size() / 3
				tri.append(a)
				tri.append(b)
				tri.append(c)
				var x0 := minf(a.x, minf(b.x, c.x))
				var x1 := maxf(a.x, maxf(b.x, c.x))
				var z0 := minf(a.z, minf(b.z, c.z))
				var z1 := maxf(a.z, maxf(b.z, c.z))
				for gx in range(floori(x0 / cell), floori(x1 / cell) + 1):
					for gz in range(floori(z0 / cell), floori(z1 / cell) + 1):
						var key := Vector2i(gx, gz)
						var ids: PackedInt32Array = grid.get(key, PackedInt32Array())
						ids.append(tid)
						grid[key] = ids

	func top_at(x: float, z: float) -> float:
		var key := Vector2i(floori(x / cell), floori(z / cell))
		if not grid.has(key):
			return NAN
		var best := NAN
		for tid: int in grid[key]:
			var a := tri[tid * 3]
			var b := tri[tid * 3 + 1]
			var c := tri[tid * 3 + 2]
			var v0 := Vector2(c.x - a.x, c.z - a.z)
			var v1 := Vector2(b.x - a.x, b.z - a.z)
			var v2 := Vector2(x - a.x, z - a.z)
			var d00 := v0.dot(v0)
			var d01 := v0.dot(v1)
			var d11 := v1.dot(v1)
			var d20 := v2.dot(v0)
			var d21 := v2.dot(v1)
			var den := d00 * d11 - d01 * d01
			if absf(den) < 1e-12:
				continue
			var u := (d11 * d20 - d01 * d21) / den
			var w := (d00 * d21 - d01 * d20) / den
			if u < -1e-6 or w < -1e-6 or u + w > 1.000001:
				continue
			var y := a.y + u * (c.y - a.y) + w * (b.y - a.y)
			if is_nan(best) or y > best:
				best = y
		return best


## 斜坡碰撞（RampCollision）の (x,z) での高さ。見つからなければ NAN
static func ramp_y(sp: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
	var ex: Array[RID] = []
	for t in 16:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h["collider"] as Node).name) == "RampCollision":
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


## 中心線 k ∈ [k0, k1) を 0.05 m ごと、横位置 lats（m、左法線が正）で測る。
## 戻り＝grids と同じ順の Array。各要素は Dictionary（横位置 → d の Array）。ramp が見つからない点・面が無い点は数えない
static func measure(sp: PhysicsDirectSpaceState3D, cl: PackedVector2Array, k0: int, k1: int, lats: Array, grids: Array) -> Array:
	var out := []
	for g in grids:
		var dct := {}
		for u in lats:
			dct[u] = []
		out.append(dct)
	for k in range(k0, k1):
		var t := cl[mini(k + 6, cl.size() - 1)] - cl[maxi(k - 6, 0)]
		t = t.normalized()
		var nn := Vector2(-t.y, t.x)
		for u in lats:
			var p: Vector2 = cl[k] + nn * float(u)
			var yr := ramp_y(sp, p)
			if is_nan(yr):
				continue
			for gi in grids.size():
				var yv: float = (grids[gi] as TopGrid).top_at(p.x, p.y)
				if not is_nan(yv):
					((out[gi] as Dictionary)[u] as Array).append(yv - yr)
	return out


static func summarize(d_in: Array) -> Dictionary:
	var d := d_in.duplicate()
	d.sort()
	var n := d.size()
	if n == 0:
		return {"n": 0, "mean": 0.0, "p5": 0.0, "p95": 0.0, "min": 0.0, "max": 0.0, "absmax": 0.0, "f10": 0.0, "f15": 0.0}
	var s := 0.0
	var o10 := 0
	var o15 := 0
	for v in d:
		s += float(v)
		if absf(float(v)) > 0.10:
			o10 += 1
		if absf(float(v)) > 0.15:
			o15 += 1
	return {"n": n, "mean": s / n, "p5": float(d[int(n * 0.05)]), "p95": float(d[int(n * 0.95)]), "min": float(d[0]), "max": float(d[n - 1]),
		"absmax": maxf(absf(float(d[0])), absf(float(d[n - 1]))), "f10": float(o10) / n, "f15": float(o15) / n}


static func fmt(label: String, sm: Dictionary) -> String:
	return "%s n=%d｜平均 %+.1f cm・p5 %+.1f・p95 %+.1f・最小 %+.1f・最大 %+.1f｜|d|>10 cm %.1f %%・>15 cm %.1f %%" % [label, sm["n"], float(sm["mean"]) * 100.0,
		float(sm["p5"]) * 100.0, float(sm["p95"]) * 100.0, float(sm["min"]) * 100.0, float(sm["max"]) * 100.0, float(sm["f10"]) * 100.0, float(sm["f15"]) * 100.0]


## gate：After が Before（r8）と同じ水準か。同じ run の Before を基準にする（r8 側が変わっても壊れない）
##   最大偏差 ≤ Before + 2 cm／10 cm 超えの割合 ≤ Before + 4 ポイント／15 cm 超え 0／平均の絶対値 ≤ 3 cm
static func gate_ok(sa: Dictionary, sb: Dictionary) -> bool:
	return float(sa["absmax"]) <= float(sb["absmax"]) + 0.02 and float(sa["f10"]) <= float(sb["f10"]) + 0.04 and float(sa["f15"]) <= 0.0 and absf(float(sa["mean"])) <= 0.03
