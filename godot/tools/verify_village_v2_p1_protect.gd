extends SceneTree
## 人間之里 V2：P1 Approved Terrain Protection Gate（P2 起每次產生後都要跑；headless）。
##
##   驗證：Godot --headless --path godot --script res://tools/verify_village_v2_p1_protect.gd
##   烘基準（只在 P1 ART_APPROVED 版本上做一次，已做：59cedbc）：
##         Godot --headless --path godot --script res://tools/verify_village_v2_p1_protect.gd -- --bake
##
## 基準 BASE：P1 核准版的地形碰撞面在每個 2 m 網格頂點的高度 h0，與每點的分類 cls（烘基準時決定，之後固定）：
##   2 水下   h0 < 鄰近水面高 lv0，且從 P1 水面網格底下的點（4 鄰接）一路低於水面連過來
##            ——河道本體（含水面網格太窄沒蓋到的岸腳）。P2 可改（河床、主槽、淺灘），不設限。
##            低於水位但與河道不連通的窪地（例：西溪旁 5.7 m 谷地）不算水下，受保護。
##   1 岸線縫 不是水下、但與水下點 4 鄰接（水平 2 m 內）：P2 為消除水面邊外露可微調，|Δh| ≤ SEAM_MAX。
##   0 受保護 其餘全部（P1 核准的水線以上 macro terrain、北丘、平台、主街、農田、龍神橋東岸坡頂）：|Δh| ≤ PROTECT_TOL。
## lv0＝WATER_REACH 內最近的水面網格頂點高度。
## 每項印一行 [PROTECT] PASS/FAIL；結尾 quit(失敗項數)。

const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const BASE := "res://maps/village_v2/p1_approved_terrain.bin"
const PROTECT_TOL := 0.03
const SEAM_DZ := 0.30
const SEAM_MAX := 0.30
const WATER_REACH := 25.0

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print("[PROTECT] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func _run() -> void:
	var bake := OS.get_cmdline_user_args().has("--bake")
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var F: Dictionary = L["frame"]
	var x0 := float(F["x0"])
	var z0 := float(F["z0"])
	var step := float(F["grid_step"])
	var nx := int(round((float(F["x1"]) - x0) / step)) + 1
	var nz := int(round((float(F["z1"]) - z0) / step)) + 1
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var tc := v.get_node_or_null("Collision/TerrainCollision") as StaticBody3D
	if tc == null:
		_check(false, "場景沒有 Collision/TerrainCollision")
		quit(fails)
		return
	var space := v.get_world_3d().direct_space_state
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	var miss := 0
	for j in nz:
		for i in nx:
			var y := _ground(space, tc.get_rid(), x0 + i * step, z0 + j * step)
			if is_nan(y):
				miss += 1
			h[j * nx + i] = y
	if bake:
		var lv := _levels(v, x0, z0, step, nx, nz)
		var cov := _covered(v, x0, z0, step, nx, nz)
		var cls := PackedByteArray()
		cls.resize(nx * nz)
		# 水下：從水面網格底下、低於水面的點出發，4 鄰接洪水填充（只走低於水面的點）
		var queue: Array[int] = []
		for k in nx * nz:
			if cov[k] and not is_nan(lv[k]) and h[k] < lv[k]:
				cls[k] = 2
				queue.append(k)
		var qi := 0
		while qi < queue.size():
			var k: int = queue[qi]
			qi += 1
			var i := k % nx
			var j := k / nx
			for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ii: int = i + o[0]
				var jj: int = j + o[1]
				if ii < 0 or jj < 0 or ii >= nx or jj >= nz:
					continue
				var kk := jj * nx + ii
				if cls[kk] == 0 and not is_nan(lv[kk]) and h[kk] < lv[kk]:
					cls[kk] = 2
					queue.append(kk)
		var n_seam := 0
		for k in nx * nz:
			if cls[k] != 0:
				continue
			var i := k % nx
			var j := k / nx
			for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ii: int = i + o[0]
				var jj: int = j + o[1]
				if ii >= 0 and jj >= 0 and ii < nx and jj < nz and cls[jj * nx + ii] == 2:
					cls[k] = 1
					n_seam += 1
					break
		var f := FileAccess.open(BASE, FileAccess.WRITE)
		f.store_var({"x0": x0, "z0": z0, "step": step, "nx": nx, "nz": nz, "h": h, "cls": cls,
			"note": "P1 Terrain ART_APPROVED（2026-09-24，59cedbc）地形碰撞面網格頂點高度與分類（0 受保護／1 岸線縫／2 水下）"}, false)
		f.close()
		print("[PROTECT] 已烘基準 %s：%d×%d 頂點；水下 %d、岸線縫 %d、受保護 %d；射線未命中 %d" % [
			BASE, nx, nz, queue.size(), n_seam, nx * nz - queue.size() - n_seam, miss])
		quit(0)
		return
	if not FileAccess.file_exists(BASE):
		_check(false, "找不到基準 %s" % BASE)
		quit(fails)
		return
	var fb := FileAccess.open(BASE, FileAccess.READ)
	var B: Dictionary = fb.get_var(false)
	fb.close()
	_check(int(B["nx"]) == nx and int(B["nz"]) == nz and is_equal_approx(float(B["x0"]), x0)
		and is_equal_approx(float(B["z0"]), z0) and is_equal_approx(float(B["step"]), step),
		"網格與基準相同（%d×%d、%.0f m）" % [nx, nz, step])
	_check(miss == 0, "每個網格頂點都打到地形（未命中 %d）" % miss)
	var h0: PackedFloat32Array = B["h"]
	var cls0: PackedByteArray = B["cls"]
	var n_prot := 0
	var n_seam := 0
	var n_wet := 0
	var bad_prot := 0
	var bad_seam := 0
	var max_prot := 0.0
	var max_seam := 0.0
	var max_wet := 0.0
	var at_prot := Vector2.ZERO
	var at_seam := Vector2.ZERO
	var worst: Array = []
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var d := absf(h[k] - h0[k])
			var kind := int(cls0[k])
			var p := Vector2(x0 + i * step, z0 + j * step)
			match kind:
				0:
					n_prot += 1
					if d > max_prot:
						max_prot = d
						at_prot = p
					if d > PROTECT_TOL:
						bad_prot += 1
						if worst.size() < 12:
							worst.append("(%.0f, %.0f) %+.2f" % [p.x, p.y, h[k] - h0[k]])
				1:
					n_seam += 1
					if d > max_seam:
						max_seam = d
						at_seam = p
					if d > SEAM_MAX:
						bad_seam += 1
				2:
					n_wet += 1
					max_wet = maxf(max_wet, d)
	_check(bad_prot == 0, "受保護（水線以上 P1 核准地形）%d 點：|Δh| > %.2f m 的 %d 點，最大 %.3f m @ (%.0f, %.0f)%s" % [
		n_prot, PROTECT_TOL, bad_prot, max_prot, at_prot.x, at_prot.y, ("；例：" + "、".join(worst)) if bad_prot > 0 else ""])
	_check(bad_seam == 0, "岸線縫 %d 點：|Δh| > %.2f m 的 %d 點，最大 %.3f m @ (%.0f, %.0f)" % [
		n_seam, SEAM_MAX, bad_seam, max_seam, at_seam.x, at_seam.y])
	print("[PROTECT]   水下 %d 點（P2 可改，不設限）：最大變化 %.2f m" % [n_wet, max_wet])
	print("[PROTECT] 結果：%d 項失敗" % fails)
	quit(fails)


## 只打地形碰撞體（橋、地標、邊界牆排除）
func _ground(space: PhysicsDirectSpaceState3D, rid: RID, x: float, z: float) -> float:
	var ex: Array[RID] = []
	for n in 8:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -60.0, z))
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			return NAN
		if r["rid"] == rid:
			return float(r["position"].y)
		ex.append(r["rid"])
	return NAN


## 每個網格頂點：WATER_REACH 內最近的水面網格頂點高度（無則 NaN）
func _levels(v: Node3D, x0: float, z0: float, step: float, nx: int, nz: int) -> PackedFloat32Array:
	var cell := 8.0
	var buckets := {}
	for mi in v.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.mesh is PrimitiveMesh:
			continue
		var xf := m.global_transform
		for p in m.mesh.get_faces():
			var w := xf * p
			var key := Vector2i(floori(w.x / cell), floori(w.z / cell))
			# Packed 陣列是值型別：取出、append、再放回
			var arr: PackedVector3Array = buckets.get(key, PackedVector3Array())
			arr.append(w)
			buckets[key] = arr
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var rc := int(ceil(WATER_REACH / cell))
	for j in nz:
		for i in nx:
			var x := x0 + i * step
			var z := z0 + j * step
			var cx := floori(x / cell)
			var cz := floori(z / cell)
			var best := WATER_REACH * WATER_REACH
			var y := NAN
			for dz in range(-rc, rc + 1):
				for dx in range(-rc, rc + 1):
					var arr = buckets.get(Vector2i(cx + dx, cz + dz))
					if arr == null:
						continue
					for w in arr:
						var d2: float = (w.x - x) * (w.x - x) + (w.z - z) * (w.z - z)
						if d2 < best:
							best = d2
							y = w.y
			out[j * nx + i] = y
	return out


## 每個網格頂點是否在（P1 核准版的）水面網格正下方
func _covered(v: Node3D, x0: float, z0: float, step: float, nx: int, nz: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(nx * nz)
	for mi in v.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.mesh is PrimitiveMesh:
			continue
		var f := m.mesh.get_faces()
		var xf := m.global_transform
		for t in range(0, f.size(), 3):
			var a := xf * f[t]
			var b := xf * f[t + 1]
			var c := xf * f[t + 2]
			var i0 := clampi(floori((minf(a.x, minf(b.x, c.x)) - x0) / step), 0, nx - 1)
			var i1 := clampi(ceili((maxf(a.x, maxf(b.x, c.x)) - x0) / step), 0, nx - 1)
			var j0 := clampi(floori((minf(a.z, minf(b.z, c.z)) - z0) / step), 0, nz - 1)
			var j1 := clampi(ceili((maxf(a.z, maxf(b.z, c.z)) - z0) / step), 0, nz - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := Vector2(x0 + i * step, z0 + j * step)
					if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
						out[j * nx + i] = 1
	return out
