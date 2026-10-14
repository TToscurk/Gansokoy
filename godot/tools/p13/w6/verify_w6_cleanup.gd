extends SceneTree
## P13 Wave 6 gate：DrapeFixP13（地面 overlay 沈地修正）＋ RoadEdgeBlendP13（外圍道路外緣侵蝕）。
##   godot --headless --path . --script res://tools/p13/w6/verify_w6_cleanup.gd [-- --negatives]
## 區塊：
##   A mount        ：兩個 overlay 在 root 末尾、順序、enabled、套用數。
##   B topology     ：DrapeFix 對象網格——surface 數／頂點數／index／UV／色／法線與原網格逐一相同，只有 y 變、只往上、≤ MAX_LIFT。
##   C weld         ：同一原位置的頂點副本升高量相同（不出現裂縫）。
##   D no-dip       ：獨立格子（N=7，與 builder 的 N=6 不同位置）上 overlay 不低於可見地形 −4 mm。
##   E completeness ：未列入的 Ground 網格以 builder 同一規則（7 點、2 cm）再掃，應 0 件。
##   F road edge    ：RoadEdgeBlendP13 的 7 條道路 shader／參數／mesh 不變；村內道路（MainStreet、Alleys）與已有 pilot 的道路不被改。
##   G round-trip   ：兩個 overlay 關閉 → 原 mesh／原材質回來；再開 → 套用數回復。
##   I dependencies ：overlay は碰撞／導航／MultiMesh を持たず、開閉で場景の碰撞物・導航領域の数が不変。
##   H negatives    ：7 個反向案例（在記憶體中製造壞資料，檢查必須判 FAIL）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const PILOT_SHADER := "res://maps/village_v2/shaders_p10/ground_p10_pilot.gdshader"
const BASE_SHADER := "res://assets/village_v2/_matlib/ground/ground.gdshader"
const MAX_LIFT := 0.40
const NODIP_TOL := 0.004
const N_CHECK := 7
const N_QUICK := 3

## 期望（與 build_w6_road_edge.gd 的 ROADS 相同——這裡是獨立抄寫，改 builder 時 gate 會擋）
const EXPECT_ROADS := {
	"Roads/SecondaryRoads/CrossStreetMid": {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0},
	"Roads/SecondaryRoads/HillFootStreet": {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0},
	"Roads/SecondaryRoads/RiverNorthPath": {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0},
	"Roads/MainStreet/EntranceRoad": {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0},
	"Roads/FarmPaths/FarmPath_2": {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35},
	"Roads/FarmPaths/FarmPath_3": {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35},
	"Roads/FarmPaths/FarmPath_5": {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35},
}
## 絶対に触らない道路（村内）
const UNTOUCHED_ROADS := [
	"Roads/MainStreet/MainStreet", "Roads/Alleys/WestAlley", "Roads/Alleys/WestLane", "Roads/Alleys/Lanes/NWLane", "Roads/Alleys/Lanes/MidLane",
	"Roads/SecondaryRoads/DragonBridgeRoad",
]

var v: Node3D
var tm: TriangleMesh
var fails := 0
var passes := 0
var fx: Node
var re: Node


func _init() -> void:
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("[W6G] PASS ", msg)
	else:
		fails += 1
		print("[W6G] FAIL ", msg)


func _terr(x: float, z: float) -> float:
	var h := tm.intersect_ray(Vector3(x, 400.0, z), Vector3.DOWN)
	return NAN if h.is_empty() else float((h["position"] as Vector3).y)


func _tris(arr: Array) -> PackedInt32Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	if ix != null and (ix as PackedInt32Array).size() > 0:
		return ix
	var t := PackedInt32Array()
	t.resize(vs.size())
	for k in vs.size():
		t[k] = k
	return t


func _surfs(m: Mesh) -> Array:
	var out: Array = []
	for s in m.get_surface_count():
		out.append(m.surface_get_arrays(s))
	return out


## 配列の一致（法線・接線は再量子化の誤差 ≤ NRM_TOL を許す。他は完全一致）
const NRM_TOL := 0.001


func arr_close(ea, eb, tol: float) -> bool:
	if ea.size() != eb.size():
		return false
	if tol <= 0.0:
		return ea == eb
	for k in ea.size():
		match typeof(ea[k]):
			TYPE_VECTOR3, TYPE_VECTOR2:
				if (ea[k] - eb[k]).length() > tol:
					return false
			TYPE_FLOAT:
				if absf(float(ea[k]) - float(eb[k])) > tol:
					return false
			_:
				if ea[k] != eb[k]:
					return false
	return true


## 原網格 vs 修正網格（arrays 同士）の構造検査。戻り値＝{bad_topo,bad_xz,neg_dy,over_cap,weld,max_dy}
func check_topology(orig: Array, fixd: Array, xf: Transform3D) -> Dictionary:
	var r := {"bad_topo": 0, "bad_xz": 0, "neg_dy": 0, "over_cap": 0, "weld": 0, "max_dy": 0.0}
	if orig.size() != fixd.size():
		r["bad_topo"] += 1
		return r
	var weld := {}     # 量子化した原位置 → [min_dy, max_dy]
	for s in orig.size():
		var a: Array = orig[s]
		var b: Array = fixd[s]
		for slot in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
			var ea = a[slot]
			var eb = b[slot]
			if (ea == null) != (eb == null):
				r["bad_topo"] += 1
			elif ea != null and not arr_close(ea, eb, NRM_TOL if (slot == Mesh.ARRAY_NORMAL or slot == Mesh.ARRAY_TANGENT) else 0.0):
				r["bad_topo"] += 1
		var va: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var vb: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
		if va.size() != vb.size():
			r["bad_topo"] += 1
			continue
		for k in va.size():
			if absf(va[k].x - vb[k].x) > 1e-6 or absf(va[k].z - vb[k].z) > 1e-6:
				r["bad_xz"] += 1
			var dy := vb[k].y - va[k].y
			if dy < -1e-6:
				r["neg_dy"] += 1
			if dy > MAX_LIFT + 1e-4:
				r["over_cap"] += 1
			r["max_dy"] = maxf(r["max_dy"], dy)
			var w := xf * va[k]
			var key := Vector3i(roundi(w.x * 1000.0), roundi(w.y * 1000.0), roundi(w.z * 1000.0))
			if not weld.has(key):
				weld[key] = [dy, dy]
			else:
				var e: Array = weld[key]
				e[0] = minf(e[0], dy)
				e[1] = maxf(e[1], dy)
	for key in weld.keys():
		var e2: Array = weld[key]
		if e2[1] - e2[0] > 1e-5:
			r["weld"] += 1
	return r


## 修正網格の最悪「地形 − overlay」（正＝沈み）。N×N 格子標本。
func worst_dip(fixd: Array, xf: Transform3D, n: int) -> float:
	var worst := -INF
	for s in fixd.size():
		var arr: Array = fixd[s]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var tri := _tris(arr)
		for t in range(0, tri.size(), 3):
			var a := xf * vs[tri[t]]
			var b := xf * vs[tri[t + 1]]
			var c := xf * vs[tri[t + 2]]
			for i in range(n + 1):
				for j in range(n + 1 - i):
					var w1 := float(i) / n
					var w2 := float(j) / n
					var w0 := 1.0 - w1 - w2
					var p := a * w0 + b * w1 + c * w2
					var ty := _terr(p.x, p.z)
					if is_nan(ty):
						continue
					worst = maxf(worst, ty - p.y)
	return worst


func prescan_deficit(mi: MeshInstance3D) -> float:
	var worst := 0.0
	var xf := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var tri := _tris(arr)
		for t in range(0, tri.size(), 3):
			var a := xf * vs[tri[t]]
			var b := xf * vs[tri[t + 1]]
			var c := xf * vs[tri[t + 2]]
			for w: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0.5, 0.5, 0), Vector3(0, 0.5, 0.5), Vector3(0.5, 0, 0.5), Vector3(1.0 / 3, 1.0 / 3, 1.0 / 3)]:
				var p := a * w.x + b * w.y + c * w.z
				var ty := _terr(p.x, p.z)
				if not is_nan(ty):
					worst = maxf(worst, ty - p.y)
	return worst


static func is_ground_path(path: String) -> bool:
	if not path.begins_with("Vegetation/"):
		return false
	for comp: String in path.split("/"):
		if comp == "Ground" or comp.begins_with("Ground_"):
			return true
	return false


func road_param_ok(mi: MeshInstance3D, want: Dictionary) -> bool:
	var m := mi.material_override as ShaderMaterial
	if m == null or m.shader == null or m.shader.resource_path != PILOT_SHADER:
		return false
	for k in want:
		var got = m.get_shader_parameter(String(k))
		if got == null or absf(float(got) - float(want[k])) > 1e-6:
			return false
	return true


func _run() -> void:
	var neg := "--negatives" in OS.get_cmdline_user_args()
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	fx = v.get_node_or_null("DrapeFixP13")
	re = v.get_node_or_null("RoadEdgeBlendP13")
	# ── A mount
	ok(fx != null and re != null, "A1 DrapeFixP13／RoadEdgeBlendP13 が root 直下に存在")
	var names := []
	for c in v.get_children():
		names.append(String(c.name))
	var i_sando := names.find("SandoPilotW4P13")
	ok(names.find("DrapeFixP13") > i_sando and names.find("RoadEdgeBlendP13") > names.find("DrapeFixP13") and names.count("DrapeFixP13") == 1 and names.count("RoadEdgeBlendP13") == 1, "A2 掛載順 SandoPilotW4P13 → DrapeFixP13 → RoadEdgeBlendP13（重複なし）")
	ok(bool(fx.get("enabled")) and bool(re.get("enabled")), "A3 両方 enabled=true")
	var paths: PackedStringArray = fx.get("paths")
	var meshes: Array = fx.get("meshes")
	ok(paths.size() > 0 and paths.size() == meshes.size() and int(fx.get("applied")) == paths.size(), "A4 DrapeFix 套用 %d／%d 件" % [int(fx.get("applied")), paths.size()])
	ok(int(re.get("applied")) == EXPECT_ROADS.size(), "A5 RoadEdgeBlend 套用 %d／%d 件" % [int(re.get("applied")), EXPECT_ROADS.size()])
	# 可見地形 TriangleMesh
	var faces := PackedVector3Array()
	for mi in v.get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in _tris(arr):
				faces.append(xf * vs[k])
	tm = TriangleMesh.new()
	tm.create_from_faces(faces)
	# 原網格を取り出す（enabled=false にして取得 → 戻す）
	fx.set("enabled", false)
	await process_frame
	var origs := {}
	for p in paths:
		var mi := v.get_node(NodePath(p)) as MeshInstance3D
		origs[p] = _surfs(mi.mesh)
	var orig_prescan := {}
	for p in paths:
		orig_prescan[p] = prescan_deficit(v.get_node(NodePath(p)) as MeshInstance3D)
	fx.set("enabled", true)
	await process_frame
	# ── B/C/D
	var tot_topo := 0
	var tot_xz := 0
	var tot_neg := 0
	var tot_cap := 0
	var tot_weld := 0
	var max_dy := 0.0
	var worst_dip_all := -INF
	var big_checked := 0
	var worst_by := {}
	for p in paths:
		var mi := v.get_node(NodePath(p)) as MeshInstance3D
		var fixd := _surfs(mi.mesh)
		var r := check_topology(origs[p], fixd, mi.global_transform)
		tot_topo += int(r["bad_topo"])
		tot_xz += int(r["bad_xz"])
		tot_neg += int(r["neg_dy"])
		tot_cap += int(r["over_cap"])
		tot_weld += int(r["weld"])
		max_dy = maxf(max_dy, float(r["max_dy"]))
		var big := p.contains("ShrineGroveP9") or p.contains("WatersideP9")
		var wd := worst_dip(fixd, mi.global_transform, N_CHECK if big else N_QUICK)
		worst_by[p] = wd
		worst_dip_all = maxf(worst_dip_all, wd)
		if big:
			big_checked += 1
	ok(tot_topo == 0, "B1 拓樸（surface／頂點数／index／法線／色／UV／UV2）原網格と一致（不一致 %d）" % tot_topo)
	ok(tot_xz == 0, "B2 x／z 不変（不一致 %d）" % tot_xz)
	ok(tot_neg == 0, "B3 只往上（下がった頂点 %d）" % tot_neg)
	ok(tot_cap == 0 and max_dy <= MAX_LIFT + 1e-4, "B4 抬高 ≤ %.2f m（最大 %.3f m・超過 %d）" % [MAX_LIFT, max_dy, tot_cap])
	ok(tot_weld == 0, "C1 溶接位置ごとの抬高が一致（ひび割れ候補 %d）" % tot_weld)
	ok(worst_dip_all <= NODIP_TOL, "D1 独立格子（主要 %d 網格 N=%d／その他 N=%d）で overlay が地形より %.0f mm 以上沈む点 0（最悪 %+.1f mm）" % [big_checked, N_CHECK, N_QUICK, NODIP_TOL * 1000.0, worst_dip_all * 1000.0])
	var n_improved := 0
	for p in paths:
		if float(orig_prescan[p]) > 0.02:
			n_improved += 1
	ok(n_improved == paths.size(), "D2 対象 %d 網格すべて元は 2 cm 以上沈んでいた（%d）——不要な網格を含めていない" % [paths.size(), n_improved])
	# ── E completeness
	var listed := {}
	for p in paths:
		listed[p] = true
	var unlisted_bad := 0
	var scanned := 0
	for mi in v.get_node("Vegetation").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var path := String(v.get_path_to(m))
		if not is_ground_path(path) or listed.has(path) or m.mesh == null or not m.is_visible_in_tree():
			continue
		scanned += 1
		if prescan_deficit(m) > 0.02:
			unlisted_bad += 1
			print("[W6G]   unlisted dip: ", path)
	ok(unlisted_bad == 0, "E1 未列入の Ground 網格 %d 個に 2 cm 以上沈む標本 0（%d）" % [scanned, unlisted_bad])
	# ── F road edge
	var f_bad := 0
	for rp in EXPECT_ROADS.keys():
		var mi := v.get_node(NodePath(rp)) as MeshInstance3D
		if not road_param_ok(mi, EXPECT_ROADS[rp]):
			f_bad += 1
			print("[W6G]   road param mismatch: ", rp)
	ok(f_bad == 0, "F1 外緣侵蝕 7 道路の shader＝pilot・参数一致（不一致 %d）" % f_bad)
	var f_mesh_bad := 0
	for rp in EXPECT_ROADS.keys():
		var mi := v.get_node(NodePath(rp)) as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() != 1:
			f_mesh_bad += 1
	ok(f_mesh_bad == 0, "F2 道路 mesh は差し替えていない（surface 数 1・RoadBaseP10 の対象外）")
	var f_untouched := 0
	for up in UNTOUCHED_ROADS:
		var mi := v.get_node(NodePath(up)) as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		if m == null or m.shader == null or m.shader.resource_path != BASE_SHADER:
			f_untouched += 1
			print("[W6G]   untouched road changed: ", up)
	ok(f_untouched == 0, "F3 村内道路（MainStreet／Alleys／橋道）は元の ground.gdshader のまま（変更 %d）" % f_untouched)
	var pilots_ok := true
	for rp in ["Roads/FarmPaths/FarmPath_1", "Roads/FarmPaths/FarmPath_4", "Roads/SecondaryRoads/CrossStreetSouth", "Roads/SecondaryRoads/RiversidePath"]:
		var mi := v.get_node(NodePath(rp)) as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		pilots_ok = pilots_ok and m != null and m.shader != null and m.shader.resource_path == PILOT_SHADER
	ok(pilots_ok, "F4 既存 pilot 道路（R5a 封存）はそのまま pilot shader")
	# ── G round-trip
	fx.set("enabled", false)
	re.set("enabled", false)
	await process_frame
	await process_frame
	var g_mesh := 0
	for p in paths:
		var mi := v.get_node(NodePath(p)) as MeshInstance3D
		if mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != origs[p][0][Mesh.ARRAY_VERTEX]:
			g_mesh += 1
	var g_mat := 0
	for rp in EXPECT_ROADS.keys():
		var mi := v.get_node(NodePath(rp)) as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		if m == null or m.shader == null or m.shader.resource_path != BASE_SHADER:
			g_mat += 1
	ok(g_mesh == 0 and g_mat == 0, "G1 disable → 原 mesh／原 ground.gdshader に完全復帰（mesh %d・材質 %d）" % [g_mesh, g_mat])
	fx.set("enabled", true)
	re.set("enabled", true)
	await process_frame
	await process_frame
	ok(int(fx.get("applied")) == paths.size() and int(re.get("applied")) == EXPECT_ROADS.size(), "G2 再 enable → 套用数が回復")
	# ── I 依存（碰撞／導航／MultiMesh は触らない）
	var i_bad := 0
	for ov: Node in [fx, re]:
		for d in ov.find_children("*", "", true, false):
			if d is CollisionObject3D or d is CollisionShape3D or d is NavigationRegion3D or d is MultiMeshInstance3D:
				i_bad += 1
	ok(i_bad == 0, "I1 DrapeFixP13／RoadEdgeBlendP13 の子孫に CollisionObject3D／CollisionShape3D／NavigationRegion3D／MultiMeshInstance3D が 0（実得 %d）" % i_bad)
	var n_col_on := v.find_children("*", "CollisionObject3D", true, false).size()
	var n_nav_on := v.find_children("*", "NavigationRegion3D", true, false).size()
	fx.set("enabled", false)
	re.set("enabled", false)
	await process_frame
	var n_col_off := v.find_children("*", "CollisionObject3D", true, false).size()
	var n_nav_off := v.find_children("*", "NavigationRegion3D", true, false).size()
	fx.set("enabled", true)
	re.set("enabled", true)
	await process_frame
	ok(n_col_on == n_col_off and n_nav_on == n_nav_off, "I2 overlay の開閉で CollisionObject3D %d＝%d・NavigationRegion3D %d＝%d（不変）" % [n_col_on, n_col_off, n_nav_on, n_nav_off])
	# ── H negatives
	if neg:
		var shrine_p := "Vegetation/ShrineGroveP9/Ground"
		var mi_s := v.get_node(NodePath(shrine_p)) as MeshInstance3D
		var good := _surfs(mi_s.mesh)
		# H1 沈んだ網格（全体 −0.12 m）→ 沈み検査が FAIL すること
		var sunk: Array = good.duplicate(true)
		for s in sunk.size():
			var vs: PackedVector3Array = (sunk[s] as Array)[Mesh.ARRAY_VERTEX]
			for k in vs.size():
				vs[k].y -= 0.12
			(sunk[s] as Array)[Mesh.ARRAY_VERTEX] = vs
		ok(worst_dip(sunk, mi_s.global_transform, N_QUICK) > NODIP_TOL, "H1 反向：全体を 12 cm 沈めた網格を沈み検査が検出")
		# H2 x をずらす → 拓樸検査
		var moved: Array = good.duplicate(true)
		var vm: PackedVector3Array = (moved[0] as Array)[Mesh.ARRAY_VERTEX]
		vm[10].x += 0.05
		(moved[0] as Array)[Mesh.ARRAY_VERTEX] = vm
		ok(int(check_topology(origs[shrine_p], moved, mi_s.global_transform)["bad_xz"]) > 0, "H2 反向：x を 5 cm ずらした網格を xz 検査が検出")
		# H3 1 頂点を 0.5 m 抬高 → 上限検査
		var spike: Array = good.duplicate(true)
		var vsp: PackedVector3Array = (spike[0] as Array)[Mesh.ARRAY_VERTEX]
		vsp[20].y += 0.5
		(spike[0] as Array)[Mesh.ARRAY_VERTEX] = vsp
		ok(int(check_topology(origs[shrine_p], spike, mi_s.global_transform)["over_cap"]) > 0, "H3 反向：1 頂点を 50 cm 抬高した網格を上限検査が検出")
		# H4 溶接を壊す：同位置の頂点 2 つ（別 index）のうち片方だけ抬高した合成メッシュ → 溶接検査が検出
		var syn_o: Array = []
		syn_o.resize(Mesh.ARRAY_MAX)
		syn_o[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(1, 0, 0)])
		var syn_f: Array = syn_o.duplicate(true)
		var vs_f: PackedVector3Array = syn_f[Mesh.ARRAY_VERTEX]
		vs_f[0].y += 0.03          # index 0 だけ（index 3 は同位置なのに不変）→ ひび割れ
		syn_f[Mesh.ARRAY_VERTEX] = vs_f
		ok(int(check_topology([syn_o], [syn_f], Transform3D.IDENTITY)["weld"]) > 0, "H4 反向：同位置頂点の片方だけ抬高した合成網格を溶接検査が検出")
		var syn_g: Array = syn_o.duplicate(true)
		var vs_g: PackedVector3Array = syn_g[Mesh.ARRAY_VERTEX]
		vs_g[0].y += 0.03
		vs_g[3].y += 0.03
		syn_g[Mesh.ARRAY_VERTEX] = vs_g
		ok(int(check_topology([syn_o], [syn_g], Transform3D.IDENTITY)["weld"]) == 0, "H4b 正例：同位置頂点を両方同量抬高した合成網格は溶接検査を通る")
		# H5 下げた頂点
		var down: Array = good.duplicate(true)
		var vd: PackedVector3Array = (down[0] as Array)[Mesh.ARRAY_VERTEX]
		vd[30].y -= 0.05
		(down[0] as Array)[Mesh.ARRAY_VERTEX] = vd
		ok(int(check_topology(origs[shrine_p], down, mi_s.global_transform)["neg_dy"]) > 0, "H5 反向：頂点を下げた網格を「只往上」検査が検出")
		# H6 completeness：原網格（未修正）の ShrineGrove を「未列入」として扱うと検出されること
		fx.set("enabled", false)
		await process_frame
		ok(prescan_deficit(mi_s) > 0.02, "H6 反向：修正前の ShrineGrove Ground は 2 cm 以上沈む（完全性検査が検出できる）")
		fx.set("enabled", true)
		await process_frame
		# H7 road param：パラメータ欠落
		var want: Dictionary = EXPECT_ROADS["Roads/SecondaryRoads/CrossStreetMid"].duplicate()
		want["edge_w"] = 0.99
		var mi_r := v.get_node(NodePath("Roads/SecondaryRoads/CrossStreetMid")) as MeshInstance3D
		ok(not road_param_ok(mi_r, want), "H7 反向：edge_w を食い違わせた期待値を道路パラメータ検査が検出")
	print("[W6G] ==== passes=", passes, " fails=", fails, " ====")
	print("[W6G] 結果：%d 項失敗" % fails)
	quit(1 if fails > 0 else 0)
