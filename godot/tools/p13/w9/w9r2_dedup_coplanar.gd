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


## polys（同向多邊形）減去 kp → 剩下的多邊形；null＝無法處理（減出帶洞且對切後仍有洞）。
## Kit 三角形整個落在內部時減出來會有洞：先沿通過 kp 重心的直線把多邊形切成兩半，各自再減（兩半都碰到 kp 邊界）。
static func _subtract(polys: Array, kp: PackedVector2Array, orient: float):
	var nxt: Array = []
	for pg: PackedVector2Array in polys:
		var res := Geometry2D.clip_polygons(pg, kp)
		var holed := false
		for r: PackedVector2Array in res:
			if signf(_area2(r)) != orient and absf(_area2(r)) > 1e-8:
				holed = true
		if holed:
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
	return nxt


static func _total(polys: Array) -> float:
	var t := 0.0
	for pg: PackedVector2Array in polys:
		t += absf(_area2(pg))
	return t


## 部分共面：三角形 abc（世界）減去同平面 Kit 三角形 → 剩餘多邊形的三角化（以原三角形的重心座標表示）。
## 回傳 null＝不需要／無法處理（保留原三角形）；[]＝全被覆蓋；否則 [[w0,w1,w2]×3 …]
## 全覆蓋與否用 Kit 三角形原形判定；部分覆蓋時減去「內縮 inset」的 Kit 三角形——overlay 留一條 inset 寬的邊塞到 Kit 面下。
##   原因：Kit 面離 overlay 平面 h（≤ EPS），斜看時 Kit 邊的實際位置相對於投影偏 h·tanθ → 精確裁切會露出髮絲縫
##   （背後沒東西時是會閃的 1 px 亮點；2026-10-18 MKT_024 實測 h≈0.2 mm、縫 0.1–0.2 mm）。inset＝0.5 mm＋3h（≤12 mm），
##   重疊帶寬遠小於 1 px，不會閃。
func _clip_tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, kt: Array):
	var u := (b - a).normalized()
	var v := n.cross(u)
	var P := func(x: Vector3) -> Vector2: return Vector2((x - a).dot(u), (x - a).dot(v))
	var tri := PackedVector2Array([P.call(a), P.call(b), P.call(c)])
	var orient := signf(_area2(tri))
	var a0 := absf(_area2(tri))
	var lo := Vector2(minf(tri[0].x, minf(tri[1].x, tri[2].x)), minf(tri[0].y, minf(tri[1].y, tri[2].y))) - Vector2(0.002, 0.002)
	var hi := Vector2(maxf(tri[0].x, maxf(tri[1].x, tri[2].x)), maxf(tri[0].y, maxf(tri[1].y, tri[2].y))) + Vector2(0.002, 0.002)
	var exact: Array = [tri]   # 減原形（判定全覆蓋）
	var polys: Array = [tri]   # 減內縮（實際輸出）
	var hit := false
	for k: Array in kt:
		# 平面距離要在局部量：Kit 三角形三個頂點到 overlay 平面的距離。不可比世界座標的平面常數 n·p——
		#   村子離原點約 280 m，法線差 4e-5（dot 印出來仍是 1.000000）就讓常數差 1 cm（2026-10-18 實測 MKT_012
		#   L0 s1 t159 ⟷ Kit sdo_d1092_e54_c2_25 t206：常數差 10.8 mm、實際頂點距離 0.07–0.23 mm → 被漏掉、照樣閃）。
		if (k[3] as Vector3).dot(n) < 0.999:
			continue
		var hmax := maxf(absf(n.dot(k[0] - a)), maxf(absf(n.dot(k[1] - a)), absf(n.dot(k[2] - a))))
		if hmax > EPS:
			continue
		var kp := PackedVector2Array([P.call(k[0]), P.call(k[1]), P.call(k[2])])
		var klo := Vector2(minf(kp[0].x, minf(kp[1].x, kp[2].x)), minf(kp[0].y, minf(kp[1].y, kp[2].y)))
		var khi := Vector2(maxf(kp[0].x, maxf(kp[1].x, kp[2].x)), maxf(kp[0].y, maxf(kp[1].y, kp[2].y)))
		if klo.x > hi.x or klo.y > hi.y or khi.x < lo.x or khi.y < lo.y:
			continue
		var inset := clampf(0.0005 + 3.0 * hmax, 0.0005, 0.012)
		# 只處理「有寬度」的重疊（以目前剩下的部分量）：平均寬（2×面積／周長）≤ 1.5×inset 的細條略過——
		#   那正是上一輪刻意留下的塞邊；不略過的話每一輪都會重新裁切、永遠不收斂（2026-10-18 實測）。
		var real := false
		for pg: PackedVector2Array in polys:
			for op: PackedVector2Array in Geometry2D.intersect_polygons(pg, kp):
				var oa := absf(_area2(op))
				var per := 0.0
				for i in op.size():
					per += op[i].distance_to(op[(i + 1) % op.size()])
				if oa > 1e-6 and 2.0 * oa / maxf(per, 1e-9) > inset * 1.5 + SLIVER:
					real = true
		if not real:
			continue
		var ex2 = _subtract(exact, kp, orient)
		if ex2 == null:
			return null
		exact = ex2
		if exact.is_empty():
			return []
		var kin := Geometry2D.offset_polygon(kp, -inset)
		if kin.size() != 1:
			continue   # 比 2×inset 還窄的 Kit 三角形：不裁（重疊寬度 < 1 px）
		var kpi: PackedVector2Array = kin[0]
		if signf(_area2(kpi)) != signf(_area2(kp)):
			kpi.reverse()
		var nxt = _subtract(polys, kpi, orient)
		if nxt == null:
			return null
		if _total(polys) - _total(nxt) > 1e-4:
			hit = true
		polys = nxt
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
				ws.append(_snap_w(Vector3(w0, w1, 1.0 - w0 - w1), tri))
			outw.append(ws)
	if _total(polys) > a0 - 1e-6:
		return null
	return outw


## Clipper 以 1e-5 量化座標：本該落在原三角形邊上／頂點上的點會偏 ~0.01–0.2 mm → 與鄰接三角形之間留髮絲縫
## （背後沒東西時是會閃的 1 px 亮點；2026-10-18 MKT_024 實測）。離邊 ≤ SNAP 的權重歸零後重新正規化，點就精確在邊上。
const SNAP := 0.00005
const SLIVER := 0.0001
static func _snap_w(w: Vector3, tri: PackedVector2Array) -> Vector3:
	var ar2 := absf((tri[1] - tri[0]).cross(tri[2] - tri[0]))
	var out := w
	for i in 3:
		var opp := tri[(i + 1) % 3].distance_to(tri[(i + 2) % 3])
		if opp > 1e-9 and absf(w[i]) * ar2 / opp < SNAP:
			out[i] = 0.0
	var sm := out.x + out.y + out.z
	return out / sm if sm > 1e-9 else w


## T 型接點修補：裁切新增的頂點若落在同一網格（任一 surface）某三角形的邊內部，把那個三角形在該點切開
## （邊上插點＋重心扇形，不產生退化三角形）→ 鄰接三角形共用頂點、不留縫。只看本工具新增的頂點，原網格拓樸不動。
const TJ_EPS := 0.0002
const TJ_CELL := 0.25
func _fix_tjunctions(surfs: Array) -> int:
	var pts := PackedVector3Array()
	for S: Dictionary in surfs:
		var vs: PackedVector3Array = (S["arr"] as Array)[Mesh.ARRAY_VERTEX]
		for i in range(int(S["n0"]), vs.size()):
			pts.append(vs[i])
	if pts.is_empty():
		return 0
	var grid := {}
	for i in pts.size():
		var k := Vector3i((pts[i] / TJ_CELL).floor())
		if not grid.has(k):
			grid[k] = []
		(grid[k] as Array).append(i)
	var nsplit := 0
	for S: Dictionary in surfs:
		var arr: Array = S["arr"]
		var keep: PackedInt32Array = S["keep"]
		var out := PackedInt32Array()
		for t in keep.size() / 3:
			var tv := [keep[t * 3], keep[t * 3 + 1], keep[t * 3 + 2]]
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var P3 := [vs[tv[0]], vs[tv[1]], vs[tv[2]]]
			var lo: Vector3 = (P3[0] as Vector3).min(P3[1]).min(P3[2]) - Vector3.ONE * TJ_EPS
			var hi: Vector3 = (P3[0] as Vector3).max(P3[1]).max(P3[2]) + Vector3.ONE * TJ_EPS
			var on_edge := [[], [], []]   # 每條邊：[參數 s, 位置]
			var c0 := Vector3i((lo / TJ_CELL).floor())
			var c1 := Vector3i((hi / TJ_CELL).floor())
			for gx in range(c0.x, c1.x + 1):
				for gy in range(c0.y, c1.y + 1):
					for gz in range(c0.z, c1.z + 1):
						var cell = grid.get(Vector3i(gx, gy, gz))
						if cell == null:
							continue
						for pi: int in cell:
							var q := pts[pi]
							for e in 3:
								var A: Vector3 = P3[e]
								var B: Vector3 = P3[(e + 1) % 3]
								var L2 := A.distance_squared_to(B)
								if L2 < 1e-10 or q.distance_to(A) < TJ_EPS or q.distance_to(B) < TJ_EPS:
									continue
								var sp := (q - A).dot(B - A) / L2
								if sp <= 0.0 or sp >= 1.0 or q.distance_to(A + (B - A) * sp) > TJ_EPS:
									continue
								var dup := false
								for ex: Array in on_edge[e]:
									if absf(float(ex[0]) - sp) * sqrt(L2) < TJ_EPS:
										dup = true
								if not dup:
									(on_edge[e] as Array).append([sp, q])
			if (on_edge[0] as Array).is_empty() and (on_edge[1] as Array).is_empty() and (on_edge[2] as Array).is_empty():
				out.append_array(PackedInt32Array(tv))
				continue
			nsplit += 1
			var ring := PackedInt32Array()
			for e in 3:
				ring.append(tv[e])
				var lst: Array = on_edge[e]
				lst.sort_custom(func(x, y): return x[0] < y[0])
				for ex: Array in lst:
					var sp: float = ex[0]
					var w := Vector3.ZERO
					w[e] = 1.0 - sp
					w[(e + 1) % 3] = sp
					ring.append(_lerp_vert(arr, tv[0], tv[1], tv[2], w))
			var cen := _lerp_vert(arr, tv[0], tv[1], tv[2], Vector3.ONE / 3.0)
			for i in ring.size():
				out.append_array(PackedInt32Array([ring[i], ring[(i + 1) % ring.size()], cen]))
		S["keep"] = out
	return nsplit


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
				var surfs: Array = []
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
					surfs.append({"arr": arr2, "keep": keep, "n0": vs.size(), "s": s})
				if removed == 0:
					continue
				var nsplit := _fix_tjunctions(surfs)
				for S: Dictionary in surfs:
					var a3: Array = S["arr"]
					a3[Mesh.ARRAY_INDEX] = S["keep"]
					out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a3, [], {}, src.surface_get_format(int(S["s"])))
					out.surface_set_name(int(S["s"]), src.surface_get_name(int(S["s"])))
					out.surface_set_material(int(S["s"]), src.surface_get_material(int(S["s"])))
				if nsplit > 0:
					per_mat["T型接點切開"] = nsplit
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
