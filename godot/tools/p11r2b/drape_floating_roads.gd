extends SceneTree
## P11 R2B TASK02：浮いた道路 ribbon の頂点を地形（TerrainCollision 射線）＋LIFT まで下げる（下げるだけ、上げない）。
## 根因：gen_village_v2.gd _roads() の ribbon は横断面が中心線の縦坡（_level＋0.10）で水平。河／水渠の下切り
## （_carved）や岸坡の上では外側の縁が地形から最大 1.46 m 浮く。_grade は下切り前に効くので縁を拾えない。
## 封存 P10 R5a の 3 本（FarmPath_1／FarmPath_4／CrossStreetSouth＝RoadBaseP10 が runtime 差し替え）は対象外。
##   godot --headless --path . --script res://tools/p11r2b/drape_floating_roads.gd -- [--apply]
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LIFT := 0.10
const TOL := 0.15   # これを超えて浮いている頂点だけ直す（通常の +0.10 は不変）
const SEALED := ["Roads/FarmPaths/FarmPath_1", "Roads/FarmPaths/FarmPath_4", "Roads/SecondaryRoads/CrossStreetSouth"]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var apply := "--apply" in OS.get_cmdline_user_args()
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr_rid: RID = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var total := 0
	for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var path := String(v.get_path_to(mi))
		if path.begins_with("Roads/Bridges") or path in SEALED:
			continue
		var m := mi.mesh as ArrayMesh
		if m == null or m.resource_path.is_empty():
			continue
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		var inv := xf.affine_inverse()
		var n := 0
		var maxd := 0.0
		for k in vs.size():
			var w := xf * vs[k]
			var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 5.0, w - Vector3.UP * 20.0)
			var ex: Array[RID] = []
			var g := -INF
			for t in 6:
				q.exclude = ex
				var h := sp.intersect_ray(q)
				if h.is_empty():
					break
				if h.rid == terr_rid:
					g = h.position.y
					break
				ex.append(h.rid)
			if g == -INF or w.y - g <= TOL:
				continue
			maxd = maxf(maxd, w.y - g)
			vs[k] = inv * Vector3(w.x, g + LIFT, w.z)
			n += 1
		if n == 0:
			continue
		total += n
		print("[DRAPE] %-42s %s  %d/%d 頂点  最大浮き %.3f m" % [path, m.resource_path, n, vs.size(), maxd])
		if apply:
			arr[Mesh.ARRAY_VERTEX] = vs
			var mat := m.surface_get_material(0)
			var nm := ArrayMesh.new()
			nm.add_surface_from_arrays(m.surface_get_primitive_type(0), arr)
			if mat:
				nm.surface_set_material(0, mat)
			var err := ResourceSaver.save(nm, m.resource_path)
			print("[DRAPE]   保存 ", m.resource_path, " err=", err)
	print("[DRAPE] 合計 %d 頂点（apply=%s）" % [total, apply])
	quit(0)
