extends SceneTree
## P13 Wave 6 TASK A 診断（唯読・headless）：道路 ribbon の幾何を「実際に見える地形」と突き合わせる。
##   godot --headless --path . --script res://tools/p13/w6/w6_audit_roads.gd -- [out.json] [--pts=N]
## 計測（道路ごと、RoadBaseP10 差し替え後の runtime mesh）：
##   off   ：頂点／辺の中点／重心の「路面 y − 地形 y」（地形＝TerrainCollision の射線＝見える地形と同じ三角形）
##   lip   ：道路縁頂点（|UV.x|＝1）の外側 0／0.25／0.5／1.0 m の地形に対する路面の高さ（薄邊＝縁の段差）
##   thin  ：極端に細い三角形（最小高さ < 5 cm、面積 > 1e-3）の数
##   cover ：路面より上に地形が出ている点の割合（路が埋まる）／路面が 0.15 m 以上浮く点の割合
##   over  ：他の地面系 mesh（地被・院子・Props 床 …）との重なり：同高（|gap| < 2 cm）／上に被さる（gap < −2 cm）
const SCENE := "res://maps/village_v2/village_v2.tscn"
const GROUND_PREFIX := ["Vegetation/GroundcoverP9/Ground", "Vegetation/MeadowP9", "Props/EnvironmentP9", "Districts"]

var v: Node3D
var sp: PhysicsDirectSpaceState3D
var terr_rid: RID


func _init() -> void:
	_run.call_deferred()


func _terr(x: float, z: float, y0: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y0 + 6.0, z), Vector3(x, y0 - 30.0, z))
	var ex: Array[RID] = []
	for t in 8:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h.rid == terr_rid:
			return float(h.position.y)
		ex.append(h.rid)
	return NAN


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return NAN
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(float(s.size() - 1) * p), 0, s.size() - 1)])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := ""
	for a: String in args:
		if not a.begins_with("--"):
			out_path = a
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await physics_frame
	sp = v.get_world_3d().direct_space_state
	terr_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	# 他の地面系 mesh を 1 つの TriangleMesh に（道路自身は除く）
	var gfaces := PackedVector3Array()
	var gcount := 0
	var granges: Array = []     # [end_face_index_exclusive, path]
	for pre: String in GROUND_PREFIX:
		var base := v.get_node_or_null(pre)
		if base == null:
			continue
		for mi in base.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var path := String(v.get_path_to(m))
			# 地面らしい名前だけ（建物 Kit は除く）
			if path.contains("/Kit/") or path.contains("/Buildings/") or path.contains("Hero"):
				continue
			if pre == "Districts" and not (path.contains("Yard") or path.contains("Ground")):
				continue
			if pre == "Vegetation/MeadowP9" or pre == "Props/EnvironmentP9":
				continue
			var xf := m.global_transform
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ix = arr[Mesh.ARRAY_INDEX]
				if ix != null and (ix as PackedInt32Array).size() > 0:
					for k in (ix as PackedInt32Array):
						gfaces.append(xf * vs[k])
				else:
					for k in vs.size():
						gfaces.append(xf * vs[k])
			gcount += 1
			granges.append([gfaces.size() / 3, path])
	var gtm := TriangleMesh.new()
	if gfaces.size() >= 3:
		gtm.create_from_faces(gfaces)
	print("[AUDIT] 他の地面系 mesh ", gcount, " 個・三角形 ", gfaces.size() / 3)
	var result := {}
	var roads_root := v.get_node("Roads")
	for mi in roads_root.find_children("*", "MeshInstance3D", true, false):
		var path := String(v.get_path_to(mi))
		if path.begins_with("Roads/Bridges"):
			continue
		var m := (mi as MeshInstance3D).mesh
		if m == null or m.get_surface_count() == 0:
			continue
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ix = arr[Mesh.ARRAY_INDEX]
		var tris: PackedInt32Array = PackedInt32Array()
		if ix != null and (ix as PackedInt32Array).size() > 0:
			tris = ix
		else:
			tris.resize(vs.size())
			for k in vs.size():
				tris[k] = k
		var xf: Transform3D = (mi as Node3D).global_transform
		var off_all: Array = []
		var off_edge: Array = []
		var lip0: Array = []
		var lip25: Array = []
		var lip50: Array = []
		var lip100: Array = []
		var thin := 0
		var buried := 0
		var floating := 0
		var n_pts := 0
		var cov_over := 0
		var cov_same := 0
		var cov_n := 0
		var gap_bins := [0, 0, 0, 0, 0, 0, 0]      # < -0.05 | -0.05..-0.02 | -0.02..-0.005 | ±0.005 | 0.005..0.02 | 0.02..0.05 | > 0.05
		var by_path := {}
		var worst_f := -INF
		var worst_f_at := Vector3.ZERO
		var worst_b := INF
		var worst_b_at := Vector3.ZERO
		var tn := tris.size() / 3
		var step := maxi(1, tn / 1500)
		var seen_edge := {}
		for t in range(0, tn, step):
			var a := xf * vs[tris[t * 3]]
			var b := xf * vs[tris[t * 3 + 1]]
			var c := xf * vs[tris[t * 3 + 2]]
			var e1 := b - a
			var e2 := c - a
			var area := e1.cross(e2).length() * 0.5
			var lm := maxf(e1.length(), maxf(e2.length(), (c - b).length()))
			if area > 1e-3 and lm > 0.0 and 2.0 * area / lm < 0.05:
				thin += 1
			var pts := [a, b, c, (a + b + c) / 3.0, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5]
			for pi in pts.size():
				var p: Vector3 = pts[pi]
				var ty := _terr(p.x, p.z, p.y)
				if is_nan(ty):
					continue
				var d := p.y - ty
				off_all.append(d)
				n_pts += 1
				if d < -0.01:
					buried += 1
					if d < worst_b:
						worst_b = d
						worst_b_at = p
				if d > 0.15:
					floating += 1
					if d > worst_f:
						worst_f = d
						worst_f_at = p
				if pi < 3:
					off_edge.append(d)
				# 他の地面系 mesh との関係
				if gfaces.size() >= 3:
					var h := gtm.intersect_ray(p + Vector3.UP * 0.5, Vector3.DOWN)
					cov_n += 1
					if not h.is_empty():
						var gy: float = (h["position"] as Vector3).y
						var gap := p.y - gy
						if gap > -0.5 and gap < -0.02:
							cov_over += 1
						elif absf(gap) <= 0.02:
							cov_same += 1
						var bi := 0
						if gap < -0.05:
							bi = 0
						elif gap < -0.02:
							bi = 1
						elif gap < -0.005:
							bi = 2
						elif gap <= 0.005:
							bi = 3
						elif gap <= 0.02:
							bi = 4
						elif gap <= 0.05:
							bi = 5
						else:
							bi = 6
						gap_bins[bi] += 1
						if bi >= 1 and bi <= 4:
							var fi := int(h["face_index"])
							var pn := "?"
							for gr: Array in granges:
								if fi < int(gr[0]):
									pn = String(gr[1])
									break
							var key := "%s|%d" % [pn.get_slice("/", 0) + "/" + pn.get_slice("/", 1) + "/" + pn.get_slice("/", 2) + "/" + pn.get_slice("/", 3), bi]
							by_path[key] = int(by_path.get(key, 0)) + 1
			# 縁頂点の外側プロファイル（頂点ごとに 1 回）
			for vi in 3:
				var idx := tris[t * 3 + vi]
				if seen_edge.has(idx):
					continue
				seen_edge[idx] = true
				var uvx := absf(uvs[idx].x) if idx < uvs.size() else 1.0
				if uvx < 0.99:
					continue
				var p0 := xf * vs[idx]
				# 外向き＝この縁頂点から、同じ断面のもう一方の縁へ向かう方向の逆。近傍で最も近い「反対側」頂点で近似
				var best := INF
				var opp := Vector3.ZERO
				for k2 in range(maxi(0, idx - 4), mini(vs.size(), idx + 5)):
					if k2 == idx:
						continue
					var q2 := xf * vs[k2]
					var dist := Vector2(q2.x - p0.x, q2.z - p0.z).length()
					if dist > 0.5 and dist < best and (uvs[k2].x * uvs[idx].x) < 0.0:
						best = dist
						opp = q2
				if best == INF:
					continue
				var dirv := Vector2(p0.x - opp.x, p0.z - opp.z).normalized()
				var rows := [[0.0, lip0], [0.25, lip25], [0.5, lip50], [1.0, lip100]]
				for rw: Array in rows:
					var ty2 := _terr(p0.x + dirv.x * float(rw[0]), p0.z + dirv.y * float(rw[0]), p0.y)
					if not is_nan(ty2):
						(rw[1] as Array).append(p0.y - ty2)
		result[path] = {"n": n_pts, "tri": tn,
			"off_p05": _pct(off_all, 0.05), "off_p50": _pct(off_all, 0.5), "off_p95": _pct(off_all, 0.95), "off_min": _pct(off_all, 0.0), "off_max": _pct(off_all, 1.0),
			"buried_pct": 100.0 * buried / maxi(n_pts, 1), "float_pct": 100.0 * floating / maxi(n_pts, 1),
			"worst_float": [snappedf(worst_f, 0.001), snappedf(worst_f_at.x, 0.1), snappedf(worst_f_at.y, 0.01), snappedf(worst_f_at.z, 0.1)] if worst_f > -INF else [],
			"worst_buried": [snappedf(worst_b, 0.001), snappedf(worst_b_at.x, 0.1), snappedf(worst_b_at.y, 0.01), snappedf(worst_b_at.z, 0.1)] if worst_b < INF else [],
			"lip0_p50": _pct(lip0, 0.5), "lip0_p95": _pct(lip0, 0.95), "lip25_p50": _pct(lip25, 0.5), "lip50_p50": _pct(lip50, 0.5), "lip50_p95": _pct(lip50, 0.95), "lip100_p50": _pct(lip100, 0.5), "lip100_p95": _pct(lip100, 0.95),
			"lip_n": lip0.size(),
			"lip_gt15_pct": 100.0 * lip0.filter(func(x): return x > 0.15).size() / maxi(lip0.size(), 1),
			"lip50_gt30_pct": 100.0 * lip50.filter(func(x): return x > 0.30).size() / maxi(lip50.size(), 1),
			"thin_tri": thin,
			"overlay_above_pct": 100.0 * cov_over / maxi(cov_n, 1), "overlay_coplanar_pct": 100.0 * cov_same / maxi(cov_n, 1), "overlay_n": cov_n,
			"gap_bins": gap_bins, "gap_by_path": by_path}
		var r: Dictionary = result[path]
		print("%-44s n=%5d off[p05 %+.3f p50 %+.3f p95 %+.3f min %+.3f max %+.3f] buried %4.1f%% float>0.15 %4.1f%% | lip0 p50 %+.3f p95 %+.3f  lip.5 p50 %+.3f p95 %+.3f lip1 p95 %+.3f (edge>0.15 %4.1f%%, lip.5>0.3 %4.1f%%) | thin %d | overlay above %4.1f%% coplanar %4.1f%% bins%s" % [
			path, r.n, r.off_p05, r.off_p50, r.off_p95, r.off_min, r.off_max, r.buried_pct, r.float_pct, r.lip0_p50, r.lip0_p95, r.lip50_p50, r.lip50_p95, r.lip100_p95, r.lip_gt15_pct, r.lip50_gt30_pct, r.thin_tri, r.overlay_above_pct, r.overlay_coplanar_pct, str(r.gap_bins)])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "\t") + "\n")
		f.close()
	quit(0)
