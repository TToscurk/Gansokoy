extends SceneTree
## W9 R2 共面去重（2026-10-18 FIX_REVIEW，建築閃爍）。
##
## 實測根因（tools/diag_village_v2_w9_zfight.gd → diag_village_v2_w9_flicker_sweep.gd）：ArchW9R2P13 的新外形網格（<id>_L0／_L1.res）
##   有一部分三角形與「overlay 刻意保留、仍顯示中的 Kit 構件」完全共面（距離 0.0000–0.0001 m、同向）：
##   ① Kit base_0（基礎；overlay 規則本來就保留它）的頂面 ⟷ L0／L1 的地板・門檻（V2_Wood／V2_Plaster／V2_MachiyaKit）
##   ② 沒被 hide 前綴藏到的 Kit 構件（bk_plain／bk_win／post／sd／sdo …）⟷ L0 裡同位置的複本
##   兩個材質不同的面疊在同一平面 → 相機移動時深度比較來回翻轉＝閃爍（哨兵材質 2 mm 側移實測：MKT_020 前緣 153 px 區域 12 幀翻 249 次、overlay 隱藏時 0）。
## 修正（只刪重複的那一份，不偏移、不改比例／外形）：Kit 保留顯示的構件是該平面的權威 → 從 overlay 網格刪掉
##   「同向、≤4 mm 共面、且被（該 LOD 帶所有時段都顯示的）Kit 構件完整覆蓋」的三角形（平面上精確裁切判定，見 _clip_tri）。
##   L0 對 Kit LOD0（只部分重疊的三角形：在平面上減去重疊的 Kit 三角形後重新三角化，屬性依重心座標內插；Kit 三角形整個在內部時先對切再減）；L1（40–600 m）必須同時被 LOD1 與 LOD2 的保留構件覆蓋才刪（任一帶缺就保留，避免開洞）。
##   被刪的地方顯示 Kit 本來的面（原本就在下面、深度相同）→ 不會開洞。overlay 的啟用／停用、編輯器存檔還原流程不變（只改網格內容）。
##   寫回 assets/village_v2/w9r2_arch/mesh/<id>_L0.res／_L1.res（surface 結構與材質不變；三角形全刪光的 surface 保留空殼不會發生——至少留 1 個就不刪）。
## 用法：godot --headless --path godot --script res://tools/p13/w9/w9r2_dedup_coplanar.gd -- [--dry|--check] [--ids=A,B]
##   （無參數）＝反覆套用到收斂（某一輪 0 變動，最多 6 輪）。--check＝只檢查：還有可刪的重複三角形就印 FAIL 並 exit 1。
##   w9r2_prefab.gd 重產網格後會自動呼叫本工具（不需手動）；之後再用 --check 確認。

const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const EPS := 0.004   # 平行且 ≤4 mm：D24 深度在 60 m 的解析度約 4 mm（near 0.05），這個距離內的兩面會互搶
var dry := false
var check := false
var ids := PackedStringArray()


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--dry":
			dry = true
		elif a == "--check":
			dry = true
			check = true
		elif a.begins_with("--ids="):
			ids = a.get_slice("=", 1).split(",")
	_run.call_deferred()


func _kept(kit: Node, lod: int) -> Array:
	var out: Array = []
	var g := kit.get_node_or_null("LOD%d" % lod)
	if g:
		for mi in g.get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).visible and (mi as MeshInstance3D).mesh != null:
				out.append(mi)
	return out


## 保留 Kit 構件（某 LOD）的三角形（世界座標）＋平面
func _kit_tris(meshes: Array) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in meshes:
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var nt: int = (idx.size() if idx != null else vs.size()) / 3
			for t in nt:
				var a := xf * vs[idx[t * 3] if idx != null else t * 3]
				var b := xf * vs[idx[t * 3 + 1] if idx != null else t * 3 + 1]
				var c := xf * vs[idx[t * 3 + 2] if idx != null else t * 3 + 2]
				var n := (b - a).cross(c - a)
				if n.length() < 1e-7:
					continue
				n = n.normalized()
				out.append([a, b, c, n, n.dot(a)])
	return out


static func _area2(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## 部分共面：三角形 abc（世界）減去同平面 Kit 三角形 → 剩餘多邊形的三角化（以原三角形的重心座標表示）。
## 回傳 null＝不需要／無法處理（保留原三角形）；[]＝全被覆蓋；否則 [[w0,w1,w2]×3 …]
func _clip_tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, kt: Array):
	var d := n.dot(a)
	var u := (b - a).normalized()
	var v := n.cross(u)
	var P := func(x: Vector3) -> Vector2: return Vector2((x - a).dot(u), (x - a).dot(v))
	var tri := PackedVector2Array([P.call(a), P.call(b), P.call(c)])
	var orient := signf(_area2(tri))
	var a0 := absf(_area2(tri))
	var lo := Vector2(minf(tri[0].x, minf(tri[1].x, tri[2].x)), minf(tri[0].y, minf(tri[1].y, tri[2].y))) - Vector2(0.002, 0.002)
	var hi := Vector2(maxf(tri[0].x, maxf(tri[1].x, tri[2].x)), maxf(tri[0].y, maxf(tri[1].y, tri[2].y))) + Vector2(0.002, 0.002)
	var polys: Array = [tri]
	var hit := false
	for k: Array in kt:
		if (k[3] as Vector3).dot(n) < 0.999 or absf(float(k[4]) - d) > EPS:
			continue
		var kp := PackedVector2Array([P.call(k[0]), P.call(k[1]), P.call(k[2])])
		var klo := Vector2(minf(kp[0].x, minf(kp[1].x, kp[2].x)), minf(kp[0].y, minf(kp[1].y, kp[2].y)))
		var khi := Vector2(maxf(kp[0].x, maxf(kp[1].x, kp[2].x)), maxf(kp[0].y, maxf(kp[1].y, kp[2].y)))
		if klo.x > hi.x or klo.y > hi.y or khi.x < lo.x or khi.y < lo.y:
			continue
		var nxt: Array = []
		for pg: PackedVector2Array in polys:
			var res := Geometry2D.clip_polygons(pg, kp)
			var holed := false
			for r: PackedVector2Array in res:
				if signf(_area2(r)) != orient and absf(_area2(r)) > 1e-8:
					holed = true
			if holed:
				# Kit 三角形整個落在內部 → 減出來會有洞：先沿通過 Kit 三角形重心的直線把多邊形切成兩半，各自再減（兩半都碰到 kp 邊界，不會再有洞）
				var cx := (kp[0].x + kp[1].x + kp[2].x) / 3.0
				var big := 1000.0
				var left := PackedVector2Array([Vector2(cx - big, -big), Vector2(cx, -big), Vector2(cx, big), Vector2(cx - big, big)])
				if signf(_area2(left)) != orient:
					left.reverse()
				res = []
				for half: PackedVector2Array in Geometry2D.intersect_polygons(pg, left) + Geometry2D.clip_polygons(pg, left):
					if signf(_area2(half)) != orient:
						return null
					for r: PackedVector2Array in Geometry2D.clip_polygons(half, kp):
						if signf(_area2(r)) != orient and absf(_area2(r)) > 1e-8:
							return null
						res.append(r)
			for r: PackedVector2Array in res:
				if absf(_area2(r)) > 1e-5:
					nxt.append(r)
		var before := 0.0
		for pg: PackedVector2Array in polys:
			before += absf(_area2(pg))
		var after := 0.0
		for pg: PackedVector2Array in nxt:
			after += absf(_area2(pg))
		if before - after > 1e-4:
			hit = true
		polys = nxt
		if polys.is_empty():
			return []
	if not hit:
		return null
	var outw: Array = []
	for pg: PackedVector2Array in polys:
		var ti := Geometry2D.triangulate_polygon(pg)
		for j in ti.size() / 3:
			var q := [pg[ti[j * 3]], pg[ti[j * 3 + 1]], pg[ti[j * 3 + 2]]]
			var ar := _area2(PackedVector2Array(q))
			if absf(ar) < 1e-7:
				continue
			if signf(ar) != orient:
				q = [q[0], q[2], q[1]]
			var ws := []
			for x: Vector2 in q:
				# 重心座標（tri 的 2D）
				var den := (tri[1].y - tri[2].y) * (tri[0].x - tri[2].x) + (tri[2].x - tri[1].x) * (tri[0].y - tri[2].y)
				var w0 := ((tri[1].y - tri[2].y) * (x.x - tri[2].x) + (tri[2].x - tri[1].x) * (x.y - tri[2].y)) / den
				var w1 := ((tri[2].y - tri[0].y) * (x.x - tri[2].x) + (tri[0].x - tri[2].x) * (x.y - tri[2].y)) / den
				ws.append(Vector3(w0, w1, 1.0 - w0 - w1))
			outw.append(ws)
	var rem := 0.0
	for pg: PackedVector2Array in polys:
		rem += absf(_area2(pg))
	if rem > a0 - 1e-6:
		return null
	return outw


## 依重心座標在 surface 陣列尾端加一個頂點，回傳索引
func _lerp_vert(arr: Array, ia: int, ib: int, ic: int, w: Vector3) -> int:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ni := vs.size()
	vs.append(vs[ia] * w.x + vs[ib] * w.y + vs[ic] * w.z)
	arr[Mesh.ARRAY_VERTEX] = vs
	if arr[Mesh.ARRAY_NORMAL] != null:
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		nn.append((nn[ia] * w.x + nn[ib] * w.y + nn[ic] * w.z).normalized())
		arr[Mesh.ARRAY_NORMAL] = nn
	if arr[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		var t3 := Vector3(tg[ia * 4], tg[ia * 4 + 1], tg[ia * 4 + 2]) * w.x + Vector3(tg[ib * 4], tg[ib * 4 + 1], tg[ib * 4 + 2]) * w.y + Vector3(tg[ic * 4], tg[ic * 4 + 1], tg[ic * 4 + 2]) * w.z
		t3 = t3.normalized()
		tg.append_array(PackedFloat32Array([t3.x, t3.y, t3.z, tg[ia * 4 + 3]]))
		arr[Mesh.ARRAY_TANGENT] = tg
	for key in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arr[key] != null:
			var uv: PackedVector2Array = arr[key]
			uv.append(uv[ia] * w.x + uv[ib] * w.y + uv[ic] * w.z)
			arr[key] = uv
	if arr[Mesh.ARRAY_COLOR] != null:
		var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		cc.append(cc[ia] * w.x + cc[ib] * w.y + cc[ic] * w.z)
		arr[Mesh.ARRAY_COLOR] = cc
	return ni


func _run() -> void:
	var scn: Node3D = (load(L.SCENE) as PackedScene).instantiate()
	root.add_child(scn)
	for i in 8:
		await process_frame   # ArchW9R2P13._boot：2 幀後才 _apply（藏 Kit 構件）
	var arch := scn.get_node(L.NODE_NAME)
	var grand := 0
	var files := {}
	for pass_i in (1 if dry else 6):
		var tot_tris := 0
		var tot_area := 0.0
		var written := 0
		for ov: Node3D in arch.get_children():
			var id := String(ov.name)
			if not ids.is_empty() and not ids.has(id):
				continue
			var body := scn.get_node(NodePath(String(ov.get_meta("body_path")))) as Node3D
			var kit := body.get_node_or_null("Kit")
			if kit == null:
				continue
			var kt0 := _kit_tris(_kept(kit, 0))
			var kt1 := _kit_tris(_kept(kit, 1))
			var kt2 := _kit_tris(_kept(kit, 2))
			for lod in 2:
				var mi := ov.get_node_or_null("L%d" % lod) as MeshInstance3D
				if mi == null:
					continue
				var src := mi.mesh as ArrayMesh
				var xf := mi.global_transform
				var out := ArrayMesh.new()
				var removed := 0
				var area := 0.0
				var per_mat := {}
				for s in src.get_surface_count():
					var arr := src.surface_get_arrays(s)
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					if idx.is_empty():
						for i in vs.size():
							idx.append(i)
					var keep := PackedInt32Array()
					var drop := 0
					var arr2 := arr.duplicate()
					var clipped := 0
					for t in idx.size() / 3:
						var a := xf * vs[idx[t * 3]]
						var b := xf * vs[idx[t * 3 + 1]]
						var c := xf * vs[idx[t * 3 + 2]]
						var n := (b - a).cross(c - a)
						var ar := n.length() * 0.5
						# 精確覆蓋（2026-10-18 修正）：在平面上把三角形減去同向 ≤EPS 的 Kit 三角形。
						#   舊版用「重心＋3 個內縮頂點」射線取樣判定整個覆蓋 → 跨兩塊 Kit 板、中間有縫的三角形會被誤刪（MKT_020／027 入口開洞）。
						#   L0：全被覆蓋才刪、部分覆蓋只留沒被蓋到的部分；L1（40–600 m）：LOD1 與 LOD2 兩帶都全覆蓋才刪，不做部分裁切。
						if ar > 1e-7:
							n = n.normalized()
							if lod == 0:
								var cl = _clip_tri(a, b, c, n, kt0)
								if cl != null and (cl as Array).is_empty():
									drop += 1
									area += ar
									continue
								if cl != null:
									clipped += 1
									area += ar
									for ws: Array in cl:
										for w: Vector3 in ws:
											keep.append(_lerp_vert(arr2, idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2], w))
									continue
							else:
								var c1 = _clip_tri(a, b, c, n, kt1)
								if c1 != null and (c1 as Array).is_empty():
									var c2 = _clip_tri(a, b, c, n, kt2)
									if c2 != null and (c2 as Array).is_empty():
										drop += 1
										area += ar
										continue
						keep.append(idx[t * 3])
						keep.append(idx[t * 3 + 1])
						keep.append(idx[t * 3 + 2])
					if keep.is_empty():
						# 整個 surface 都是重複 → 留下原樣（不讓 surface 結構改變；回報）
						keep = idx
						arr2 = arr.duplicate()
						print("[dedup] %s L%d s%d 全部共面（%d 三角形）→ 保留不刪" % [id, lod, s, drop])
						drop = 0
						clipped = 0
					removed += drop + clipped
					if drop + clipped > 0:
						per_mat[src.surface_get_name(s)] = "刪%d 裁%d" % [drop, clipped]
					arr2[Mesh.ARRAY_INDEX] = keep
					out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2, [], {}, src.surface_get_format(s))
					out.surface_set_name(s, src.surface_get_name(s))
					out.surface_set_material(s, src.surface_get_material(s))
				if removed == 0:
					continue
				tot_tris += removed
				tot_area += area
				print("[dedup] %-12s L%d 刪 %4d 三角形（%.2f m²）%s" % [id, lod, removed, area, per_mat])
				if not dry:
					out.resource_name = src.resource_name
					out.custom_aabb = src.custom_aabb
					var path := src.resource_path
					out.take_over_path(path)   # 第 2 輪起 src 是這個新物件 → 要有 resource_path
					var err := ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)   # 與 w9r2_prefab.gd 相同（不壓縮會變 5 倍大）
					print("[dedup]   寫 %s → %s" % [path, error_string(err)])
					written += 1
					files[path] = true
					mi.mesh = out   # 下一輪用新網格再檢查（收斂）
		grand += tot_tris
		print("[dedup] 第 %d 輪：刪／裁 %d 三角形（%.2f m²）" % [pass_i + 1, tot_tris, tot_area])
		if tot_tris == 0:
			break
	print("[dedup] 合計刪／裁 %d 三角形，寫 %d 個檔%s" % [grand, files.size(), "（--dry 不寫）" if dry else ""])
	print("[dedup] SUMMARY tris=%d files=%d mode=%s" % [grand, files.size(), "check" if check else ("dry" if dry else "apply")])   # ASCII：給 prefab 經 OS.execute 轉印
	if check and grand > 0:
		print("[dedup] FAIL 仍有 %d 個 overlay 三角形與保留的 Kit 構件共面（重產網格後沒跑去重？）" % grand)
		quit(1)
		return
	if check:
		print("[dedup] PASS 無共面重複")
	quit(0)
