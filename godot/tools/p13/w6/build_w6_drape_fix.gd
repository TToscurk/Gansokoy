extends SceneTree
## P13 Wave 6 DrapeFixP13 builder（headless 可）：地面 overlay 網格の頂点を「只往上」抬到可見地形面以上にした副本を作り、
## maps/village_v2/gen/drape_fix_p13.scn（DrapeFixP13 overlay）へ保存する。原 overlay の .scn／.res には一切触れない。
##   godot --headless --path . --script res://tools/p13/w6/build_w6_drape_fix.gd -- [--dry] [--report=<json>] [--eps=0.006] [--thresh=0.02]
## 手順：
##   1. village_v2.tscn を載せ（DrapeFixP13 があれば enabled=false で原網格に戻して）、Terrain/* の可視三角形から TriangleMesh を作る。
##   2. Vegetation/** の Ground 系 MeshInstance3D を前走査（頂点・辺中点・重心の 7 点）し、地形に対し THRESH 以上沈む標本を持つ網格だけ対象にする。
##   3. 対象網格を「位置で溶接」した頂点群にまとめ（分割頂点がひび割れないように）、三角形内の重心格子（N_SUB）標本ごとに
##      不足量 = 地形 + EPS − 現在の面高 を求め、不足の大きい標本から順に最小ノルム射影で頂点群を押し上げる（上げる一方なので
##      先に満たした標本は崩れない）。MAX_LIFT を超える頂点は頭打ち＋報告。
##   4. 検証：全標本で不足 ≤ 2 mm（頭打ち頂点がある三角形は除外して報告）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const SCRIPT := "res://maps/village_v2/scripts_p13/drape_fix.gd"
const OUT_SCENE := "res://maps/village_v2/gen/drape_fix_p13.scn"
const N_SUB := 6
const MAX_LIFT := 0.40
const VERIFY_TOL := 0.002

var eps := 0.006
var thresh := 0.02
var tm: TriangleMesh


func _init() -> void:
	_run.call_deferred()


func _terr(x: float, z: float) -> float:
	var h := tm.intersect_ray(Vector3(x, 400.0, z), Vector3.DOWN)
	if h.is_empty():
		return NAN
	return float((h["position"] as Vector3).y)


static func _is_ground_path(path: String) -> bool:
	if not path.begins_with("Vegetation/"):
		return false
	for comp: String in path.split("/"):
		if comp == "Ground" or comp.begins_with("Ground_"):
			return true
	return false


func _surface_tris(arr: Array) -> PackedInt32Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	if ix != null and (ix as PackedInt32Array).size() > 0:
		return ix
	var t := PackedInt32Array()
	t.resize(vs.size())
	for k in vs.size():
		t[k] = k
	return t


func _run() -> void:
	var dry := false
	var report_path := ""
	for a: String in OS.get_cmdline_user_args():
		if a == "--dry":
			dry = true
		elif a.begins_with("--report="):
			report_path = a.trim_prefix("--report=")
		elif a.begins_with("--eps="):
			eps = float(a.trim_prefix("--eps="))
		elif a.begins_with("--thresh="):
			thresh = float(a.trim_prefix("--thresh="))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	var existing := v.get_node_or_null("DrapeFixP13")
	if existing != null:
		existing.set("enabled", false)
		await process_frame
		await process_frame
	# ── 1. 可見地形の TriangleMesh
	var faces := PackedVector3Array()
	for mi in v.get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in _surface_tris(arr):
				faces.append(xf * vs[k])
	tm = TriangleMesh.new()
	tm.create_from_faces(faces)
	print("[W6D] terrain triangles ", faces.size() / 3)
	# ── 2. 前走査
	var cands: Array = []
	var n_scanned := 0
	var seen_mesh := {}
	for mi in v.get_node("Vegetation").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var path := String(v.get_path_to(m))
		if not _is_ground_path(path) or m.mesh == null or not m.is_visible_in_tree():
			continue
		n_scanned += 1
		var xf := m.global_transform
		var worst := 0.0
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var tri := _surface_tris(arr)
			for t in range(0, tri.size(), 3):
				var a := xf * vs[tri[t]]
				var b := xf * vs[tri[t + 1]]
				var c := xf * vs[tri[t + 2]]
				for w: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0.5, 0.5, 0), Vector3(0, 0.5, 0.5), Vector3(0.5, 0, 0.5), Vector3(1.0 / 3, 1.0 / 3, 1.0 / 3)]:
					var p := a * w.x + b * w.y + c * w.z
					var ty := _terr(p.x, p.z)
					if is_nan(ty):
						continue
					worst = maxf(worst, ty - p.y)
		if worst > thresh:
			var rid := m.mesh.get_rid()
			if seen_mesh.has(rid):
				print("[W6D] SKIP shared mesh ", path)
				continue
			seen_mesh[rid] = true
			cands.append([path, worst])
	print("[W6D] ground meshes scanned ", n_scanned, " candidates ", cands.size())
	# ── 3. 各候補を解く
	var out_paths := PackedStringArray()
	var out_meshes: Array[Mesh] = []
	var report := {"eps": eps, "thresh": thresh, "n_sub": N_SUB, "max_lift": MAX_LIFT, "meshes": {}}
	for cd: Array in cands:
		var path: String = cd[0]
		var mi := v.get_node(NodePath(path)) as MeshInstance3D
		var xf := mi.global_transform
		var bas := xf.basis
		if absf(bas.y.x) > 1e-5 or absf(bas.y.z) > 1e-5 or absf(bas.x.y) > 1e-5 or absf(bas.z.y) > 1e-5 or absf(bas.y.y - 1.0) > 1e-4:
			print("[W6D] SKIP non-yaw-only transform ", path)
			continue
		var res := _solve_mesh(mi, xf)
		res["pre_worst"] = snappedf(cd[1], 0.0001)
		report["meshes"][path] = res
		print("[W6D] ", path, " tri=", res["tri"], " groups=", res["groups"], " lifted_groups=", res["lifted_groups"], " max_lift=", res["max_lift"], " mean_lift=", res["mean_lift"], " verify_worst=", res["verify_worst"], " capped=", res["capped"])
		if res.has("mesh") and not dry:
			out_paths.append(path)
			out_meshes.append(res["mesh"])
		res.erase("mesh")
	if not dry:
		var node := Node3D.new()
		node.name = "DrapeFixP13"
		node.set_script(load(SCRIPT))
		node.set("paths", out_paths)
		node.set("meshes", out_meshes)
		var ps := PackedScene.new()
		ps.pack(node)
		var err := ResourceSaver.save(ps, OUT_SCENE)
		print("[W6D] saved ", OUT_SCENE, " err=", err, " meshes=", out_meshes.size())
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t") + "\n")
		f.close()
	quit(0)


## 戻り値：統計 dict（"mesh" に修正済み ArrayMesh）
func _solve_mesh(mi: MeshInstance3D, xf: Transform3D) -> Dictionary:
	var src := mi.mesh
	var nS := src.get_surface_count()
	var arrs: Array = []
	var gid_of: Array = []        # surface → PackedInt32Array（頂点 → 群 id）
	var gidx := {}                # 量子化位置 → 群 id
	var gy := PackedFloat32Array()    # 群の現在 y（world）
	var gy0 := PackedFloat32Array()
	var tris_all: Array = []      # [surface, PackedInt32Array(tri indices), world positions packed]
	var n_tri := 0
	for s in nS:
		var arr := src.surface_get_arrays(s)
		arrs.append(arr)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ids := PackedInt32Array()
		ids.resize(vs.size())
		for k in vs.size():
			var w := xf * vs[k]
			var key := Vector3i(roundi(w.x * 1000.0), roundi(w.y * 1000.0), roundi(w.z * 1000.0))
			if not gidx.has(key):
				gidx[key] = gy.size()
				gy.append(w.y)
				gy0.append(w.y)
			ids[k] = gidx[key]
		gid_of.append(ids)
		n_tri += _surface_tris(arr).size() / 3
	# 溶接した群ごとの world x,z
	var gx := PackedFloat32Array()
	var gz := PackedFloat32Array()
	gx.resize(gy.size())
	gz.resize(gy.size())
	for s in nS:
		var vs: PackedVector3Array = arrs[s][Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = gid_of[s]
		for k in vs.size():
			var w := xf * vs[k]
			gx[ids[k]] = w.x
			gz[ids[k]] = w.z
	# 標本
	var samples: Array = []     # [def0, g0, g1, g2, w0, w1, w2, ty]
	var all_samples := 0
	for s in nS:
		var tri := _surface_tris(arrs[s])
		var ids: PackedInt32Array = gid_of[s]
		for t in range(0, tri.size(), 3):
			var g0 := ids[tri[t]]
			var g1 := ids[tri[t + 1]]
			var g2 := ids[tri[t + 2]]
			if g0 == g1 or g1 == g2 or g0 == g2:
				continue
			for a in range(N_SUB + 1):
				for b in range(N_SUB + 1 - a):
					var w1 := float(a) / N_SUB
					var w2 := float(b) / N_SUB
					var w0 := 1.0 - w1 - w2
					var px := gx[g0] * w0 + gx[g1] * w1 + gx[g2] * w2
					var pz := gz[g0] * w0 + gz[g1] * w1 + gz[g2] * w2
					var ty := _terr(px, pz)
					if is_nan(ty):
						continue
					all_samples += 1
					var cur := gy[g0] * w0 + gy[g1] * w1 + gy[g2] * w2
					var d := ty + eps - cur
					if d > 0.0:
						samples.append([d, g0, g1, g2, w0, w1, w2, ty])
	samples.sort_custom(func(p, q): return p[0] > q[0])
	var capped := 0
	for sm: Array in samples:
		var g0: int = sm[1]
		var g1: int = sm[2]
		var g2: int = sm[3]
		var w0: float = sm[4]
		var w1: float = sm[5]
		var w2: float = sm[6]
		var d: float = float(sm[7]) + eps - (gy[g0] * w0 + gy[g1] * w1 + gy[g2] * w2)
		if d <= 1e-5:
			continue
		var ss := w0 * w0 + w1 * w1 + w2 * w2
		var gs := [g0, g1, g2]
		var ws := [w0, w1, w2]
		for q in 3:
			var g: int = gs[q]
			var up: float = d * float(ws[q]) / ss
			var room := gy0[g] + MAX_LIFT - gy[g]
			if up > room:
				up = maxf(room, 0.0)
				capped += 1
			gy[g] += up
	# 検証（全標本）
	var verify_worst := 0.0
	for s in nS:
		var tri := _surface_tris(arrs[s])
		var ids: PackedInt32Array = gid_of[s]
		for t in range(0, tri.size(), 3):
			var g0 := ids[tri[t]]
			var g1 := ids[tri[t + 1]]
			var g2 := ids[tri[t + 2]]
			if g0 == g1 or g1 == g2 or g0 == g2:
				continue
			for a in range(N_SUB + 1):
				for b in range(N_SUB + 1 - a):
					var w1 := float(a) / N_SUB
					var w2 := float(b) / N_SUB
					var w0 := 1.0 - w1 - w2
					var px := gx[g0] * w0 + gx[g1] * w1 + gx[g2] * w2
					var pz := gz[g0] * w0 + gz[g1] * w1 + gz[g2] * w2
					var ty := _terr(px, pz)
					if is_nan(ty):
						continue
					var cur := gy[g0] * w0 + gy[g1] * w1 + gy[g2] * w2
					verify_worst = maxf(verify_worst, ty + eps - cur)
	# 統計
	var lifted := 0
	var max_lift := 0.0
	var sum_lift := 0.0
	for g in gy.size():
		var dl := gy[g] - gy0[g]
		if dl > 1e-5:
			lifted += 1
			sum_lift += dl
			max_lift = maxf(max_lift, dl)
	# 新しい ArrayMesh
	var nm := ArrayMesh.new()
	nm.resource_name = src.resource_name
	for s in nS:
		var arr: Array = (arrs[s] as Array).duplicate()
		var vs: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var ids: PackedInt32Array = gid_of[s]
		for k in vs.size():
			var w := xf * vs[k]
			var dl := gy[ids[k]] - w.y
			if absf(dl) > 1e-7:
				vs[k].y += dl      # yaw のみの変換なので world の Δy = local の Δy
		arr[Mesh.ARRAY_VERTEX] = vs
		var prim: Mesh.PrimitiveType = src.surface_get_primitive_type(s) as Mesh.PrimitiveType
		nm.add_surface_from_arrays(prim, arr, [], {}, src.surface_get_format(s))
		var mat := src.surface_get_material(s)
		if mat != null:
			nm.surface_set_material(s, mat)
	return {"mesh": nm, "tri": n_tri, "groups": gy.size(), "lifted_groups": lifted, "max_lift": snappedf(max_lift, 0.0001), "mean_lift": snappedf(sum_lift / maxf(lifted, 1), 0.0001),
		"deficit_samples": samples.size(), "all_samples": all_samples, "verify_worst": snappedf(verify_worst, 0.0001), "capped": capped}
