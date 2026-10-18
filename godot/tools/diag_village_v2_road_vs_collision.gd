extends SceneTree
## 道路可見面 vs 地形可見面 vs 物理碰撞面（village_v2）。
## 載入 village_v2.tscn（overlay 的 _ready 換 mesh 會先跑），對 Roads/**（不含 Bridges）每條路的三角形
## 取重心＋三頂點，量：road_y（三角形本身）、terrain_vis_y（Terrain/* 可見網格，臨時 trimesh 放在 layer 20 射線）、
## col_y（真正的碰撞，原本的 mask，排除臨時體）。headless 可用（ArrayMesh／碰撞都不受 dummy renderer 影響）。
## 用法：godot --headless --path godot --script res://tools/diag_village_v2_road_vs_collision.gd [-- --stride=N --csv=path]

const TMP_LAYER := 1 << 19
var stride := 7
var csv_path := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stride="):
			stride = int(a.get_slice("=", 1))
		elif a.begins_with("--csv="):
			csv_path = a.get_slice("=", 1)
	_run.call_deferred()


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _run() -> void:
	var scn: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 4:
		await process_frame
	# 臨時：地形可見網格 → trimesh（layer 20）
	var tmp := StaticBody3D.new()
	tmp.collision_layer = TMP_LAYER
	tmp.collision_mask = 0
	scn.add_child(tmp)
	var terr: Array = []
	_meshes(scn.get_node("Terrain"), terr)
	for mi: MeshInstance3D in terr:
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		tmp.add_child(cs)
		cs.global_transform = mi.global_transform
	for i in 3:
		await physics_frame
	var space := scn.get_world_3d().direct_space_state
	var roads: Array = []
	for g in ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]:
		var n := scn.get_node_or_null("Roads/" + g)
		if n:
			_meshes(n, roads)
	var lines := PackedStringArray(["road,x,z,road_y,terr_y,col_y,col_name,kind"])
	print("[rvc] %-28s %6s  %8s %8s %8s  %8s %8s  %8s %8s" % ["road", "n", "r-col平均", "r-col最小", "r-col最大", "t-col平均", "t-col最大", "r-t平均", "r-t最小"])
	var all_rc: Array = []
	for mi: MeshInstance3D in roads:
		var xf := mi.global_transform
		var rc := PackedFloat32Array()
		var tc := PackedFloat32Array()
		var rt := PackedFloat32Array()
		for s in 1:   # surface 0＝路面 ribbon（surface 1＝edge_skirt 裙邊，垂直面不算路面）
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var ntri := (idx.size() if idx.size() > 0 else v.size()) / 3
			var t := 0
			while t < ntri:
				var ia := idx[t * 3] if idx.size() > 0 else t * 3
				var ib := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var ic := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var a := xf * v[ia]
				var b := xf * v[ib]
				var c := xf * v[ic]
				for k in 2:
					var p: Vector3 = (a + b + c) / 3.0 if k == 0 else a
					var kind := "centroid" if k == 0 else "vertex"
					var top := Vector3(p.x, p.y + 30.0, p.z)
					var bot := Vector3(p.x, p.y - 30.0, p.z)
					var q1 := PhysicsRayQueryParameters3D.create(top, bot, TMP_LAYER)
					var h1 := space.intersect_ray(q1)
					var q2 := PhysicsRayQueryParameters3D.create(top, bot, 0xFFFFFFFF & ~TMP_LAYER)
					var h2 := space.intersect_ray(q2)
					if h1.is_empty() or h2.is_empty():
						continue
					var ty: float = h1.position.y
					var cy: float = h2.position.y
					var cname := String((h2.collider as Node).get_path()).get_slice("VillageV2/", 1)
					if cname.begins_with("Collision/TerrainCollision") or cname.begins_with("Collision/DirtRoadCollision"):
						rc.append(p.y - cy)
						tc.append(ty - cy)
						rt.append(p.y - ty)
						all_rc.append(p.y - cy)
					if csv_path != "":
						lines.append("%s,%.2f,%.2f,%.4f,%.4f,%.4f,%s,%s" % [mi.name, p.x, p.z, p.y, ty, cy, cname, kind])
				t += stride
		if rc.is_empty():
			print("[rvc] %-28s no samples" % mi.name)
			continue
		print("[rvc] %-28s %6d  %8.3f %8.3f %8.3f  %8.3f %8.3f  %8.3f %8.3f" % [String(mi.get_path()).get_slice("Roads/", 1), rc.size(), _avg(rc), _min(rc), _max(rc), _avg(tc), _max(tc), _avg(rt), _min(rt)])
	all_rc.sort()
	var n := all_rc.size()
	print("[rvc] ALL n=%d  road-col p05=%.3f p50=%.3f p95=%.3f max=%.3f" % [n, all_rc[int(n * 0.05)], all_rc[n / 2], all_rc[int(n * 0.95)], all_rc[n - 1]])
	if csv_path != "":
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		f.store_string("\n".join(lines))
		f.close()
	quit(0)


func _avg(a: PackedFloat32Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / a.size()


func _min(a: PackedFloat32Array) -> float:
	var m := 1e9
	for x in a:
		m = minf(m, x)
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := -1e9
	for x in a:
		m = maxf(m, x)
	return m
