extends SceneTree
## P11 R2C A（使用者 2026-10-11 APPROVED）：7 條道路 ribbon の浮いた頂点だけ地形＋0.10 へ下げる（下げるだけ）。
## 対象は明示の 7 本だけ（全 Roads を走査しない）。--check＝只讀（頂点・三角形内部・橋頭・坡度・網格格式）、--apply＝7 本の .res を上書き。
##   godot --headless --path . --script res://tools/p11r2c/drape_roads_r2c.gd -- --check|--apply
## 追加（B 調査）：水車 2 の竜骨車落とし桝（水面 0.28）→ N0 進水口の地面プロファイル（重力で N0 へ回せるか）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const LIFT := 0.10
const TOL := 0.15
## R2C：R2B の 76 頂点のうち 9 頂点は橋面の上（橋頭）＝支撐面は橋。地形まで下げると橋頭が落ち、
## P7 橋頭鋪石が 0.10 m 浮く（RBG grounding FAIL の原因）。→ 支撐面＝地形または橋面で判定、67 頂点。
const TARGETS := {
	"Roads/SecondaryRoads/HillFootStreet": 0, "Roads/SecondaryRoads/HillApproach": 1,
	"Roads/SecondaryRoads/RiverNorthPath": 19, "Roads/SecondaryRoads/DragonBridgeRoad": 0,
	"Roads/SecondaryRoads/CrossStreetMid": 8, "Roads/SecondaryRoads/RiversidePath": 39,
	"Roads/Alleys/WestLane": 0}

var sp: PhysicsDirectSpaceState3D
var terr: RID

func _init() -> void:
	_run.call_deferred()

var bridges: Array[RID] = []

## 支撐面＝頂点の真下で最初に当たる地形か橋面（橋頭で橋面に乗っている路面は浮いていない）。
## 頂点より上の橋面（橋の下に潜った路面）は対象外＝地形まで下げる。
func _ground(w: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 0.02, w - Vector3.UP * 20.0)
	var ex: Array[RID] = []
	for t in 8:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h.rid == terr or h.rid in bridges:
			return h.position.y
		ex.append(h.rid)
	return NAN

## 真上から最初に当たる橋（Roads/Bridges）の高さ。無ければ NAN
func _bridge_top(w: Vector3, bridges: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(w.x, w.y + 6.0, w.z), Vector3(w.x, w.y - 6.0, w.z))
	var ex: Array[RID] = []
	for t in 8:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h.rid in bridges:
			return h.position.y
		ex.append(h.rid)
	return NAN

func _run() -> void:
	var apply := "--apply" in OS.get_cmdline_user_args()
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	sp = v.get_world_3d().direct_space_state
	terr = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var bnodes: Array = []
	for b in v.get_node("Roads/Bridges").find_children("*", "CollisionObject3D", true, false):
		bridges.append((b as CollisionObject3D).get_rid())
		bnodes.append(b)
	var total := 0
	var bad := 0
	for path: String in TARGETS:
		var mi := v.get_node(path) as MeshInstance3D
		var m := mi.mesh as ArrayMesh
		var xf := mi.global_transform
		var inv := xf.affine_inverse()
		var nm := ArrayMesh.new()
		var n := 0
		var maxd := 0.0
		var tri_after_gap := 0.0
		var max_slope := 0.0
		var bridge_rep := []
		var fmt_txt := ""
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var has_n: bool = arr[Mesh.ARRAY_NORMAL] != null
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			fmt_txt = "surf %d verts %d normals %s index %s uv2 %s color %s" % [s, vs.size(), has_n, idx != null, arr[Mesh.ARRAY_TEX_UV2] != null, arr[Mesh.ARRAY_COLOR] != null]
			var moved := {}
			for k in vs.size():
				var w := xf * vs[k]
				var g := _ground(w)
				if is_nan(g) or w.y - g <= TOL:
					continue
				maxd = maxf(maxd, w.y - g)
				var nw := Vector3(w.x, g + LIFT, w.z)
				# 橋頭：真下に橋があれば、橋面との段差を記録（下げた結果が橋面より低く段になるか）
				var bt := _bridge_top(nw, bridges)
				if not is_nan(bt):
					bridge_rep.append("(%.1f,%.1f) 新 %.2f／橋面 %.2f" % [w.x, w.z, nw.y, bt])
				vs[k] = inv * nw
				moved[k] = true
				n += 1
			# 影響三角形：重心・辺中点の地形との差（三角形内部が浮いていないか）と横断勾配
			var ntri := vs.size() / 3 if idx == null else (idx as PackedInt32Array).size() / 3
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if has_n else PackedVector3Array()
			for t in ntri:
				var ii := [t * 3, t * 3 + 1, t * 3 + 2] if idx == null else [(idx as PackedInt32Array)[t * 3], (idx as PackedInt32Array)[t * 3 + 1], (idx as PackedInt32Array)[t * 3 + 2]]
				if not (moved.has(ii[0]) or moved.has(ii[1]) or moved.has(ii[2])):
					continue
				var a := xf * vs[ii[0]]
				var b := xf * vs[ii[1]]
				var c := xf * vs[ii[2]]
				for p in [(a + b + c) / 3.0, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5]:
					var g2 := _ground(p)
					if not is_nan(g2):
						tri_after_gap = maxf(tri_after_gap, p.y - g2)
				var fn := (c - a).cross(b - a).normalized()
				if fn.y < 0.0:
					fn = -fn
				max_slope = maxf(max_slope, rad_to_deg(fn.angle_to(Vector3.UP)))
				# 法線：動かした三角形は面法線に（古い法線のままだと陰影が平らなまま残る）
				if has_n:
					var ln := (inv.basis * fn).normalized()
					for j in ii:
						nrm[j] = ln
			if has_n:
				arr[Mesh.ARRAY_NORMAL] = nrm
			arr[Mesh.ARRAY_VERTEX] = vs
			nm.add_surface_from_arrays(m.surface_get_primitive_type(s), arr, [], {}, m.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			if m.surface_get_material(s):
				nm.surface_set_material(s, m.surface_get_material(s))
			nm.surface_set_name(s, m.surface_get_name(s))
		total += n
		var ok := n == int(TARGETS[path]) and tri_after_gap <= 0.25 and max_slope < 40.0
		bad += int(not ok)
		print("[DRAPE2] %-38s 頂点 %d（期待 %d）最大浮き %.3f → 修正後 三角形内部の最大浮き %.3f・最大傾斜 %.1f°  橋の上の頂点 %d %s  %s" % [path, n, TARGETS[path], maxd, tri_after_gap, max_slope, bridge_rep.size(), str(bridge_rep.slice(0, 3)), "OK" if ok else "NG"])
		print("[DRAPE2]   format: ", fmt_txt)
		if apply and n > 0:
			var err := ResourceSaver.save(nm, m.resource_path)
			var back := ResourceLoader.load(m.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
			var same := back != null and back.get_surface_count() == m.get_surface_count()
			for s in m.get_surface_count():
				same = same and back.surface_get_array_len(s) == m.surface_get_array_len(s)
			print("[DRAPE2]   保存 %s err=%d 回讀（surface／頂点数一致）=%s" % [m.resource_path, err, same])
			bad += int(err != OK or not same)
	print("[DRAPE2] 合計 %d 頂点（期待 67）apply=%s NG %d" % [total, apply, bad])
	# ── B：竜骨車の落とし桝（水面 0.28）から N0 進水口への重力ルート（直線）の地面
	var a2 := Vector2(338.9, 4.85)
	var b2 := Vector2(352.35, -45.2)
	var prof := []
	var hi := -INF
	for k in 21:
		var p := a2.lerp(b2, k / 20.0)
		var gh := FZ.ground_h(p)
		hi = maxf(hi, gh)
		prof.append(snappedf(gh, 0.01))
	print("[HYD2] 落とし桝(0.28)→N0 進水口(要求 0.168) 直線 %.1f m 地面 %s 最高 %.2f" % [a2.distance_to(b2), str(prof), hi])
	quit(bad)
