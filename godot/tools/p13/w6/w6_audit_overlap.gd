extends SceneTree
## P13 Wave 6 診断（唯読・headless）：DrapeFixP13 の Before／After で「地面 overlay が道路 ribbon の上に出る」標本数を比較する。
##   godot --headless --path . --script res://tools/p13/w6/w6_audit_overlap.gd -- [out.json]
## 道路 ribbon（Roads/**、橋を除く）の TriangleMesh に対し、DrapeFixP13 の対象 overlay 網格の三角形格子標本が
##   gap = overlay_y − road_y（同じ XZ に路面がある点だけ）
## を測る。gap > −0.002 ＝ overlay が路面と同高か上（路面を覆う／ z-fight する）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const N_SUB := 4

var tm_road: TriangleMesh


func _init() -> void:
	_run.call_deferred()


func _road_y(x: float, z: float) -> float:
	var h := tm_road.intersect_ray(Vector3(x, 400.0, z), Vector3.DOWN)
	if h.is_empty():
		return NAN
	return float((h["position"] as Vector3).y)


func _measure(v: Node3D, paths: PackedStringArray) -> Dictionary:
	var res := {}
	for p in paths:
		var mi := v.get_node_or_null(NodePath(p)) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := mi.global_transform
		var n_over := 0
		var n_on_road := 0
		var worst := -INF
		var worst_at := Vector3.ZERO
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array
			if ix != null and (ix as PackedInt32Array).size() > 0:
				tri = ix
			else:
				tri = PackedInt32Array()
				tri.resize(vs.size())
				for k in vs.size():
					tri[k] = k
			for t in range(0, tri.size(), 3):
				var a := xf * vs[tri[t]]
				var b := xf * vs[tri[t + 1]]
				var c := xf * vs[tri[t + 2]]
				for i in range(N_SUB + 1):
					for j in range(N_SUB + 1 - i):
						var w1 := float(i) / N_SUB
						var w2 := float(j) / N_SUB
						var w0 := 1.0 - w1 - w2
						var q := a * w0 + b * w1 + c * w2
						var ry := _road_y(q.x, q.z)
						if is_nan(ry):
							continue
						n_on_road += 1
						var gap := q.y - ry
						if gap > -0.002:
							n_over += 1
							if gap > worst:
								worst = gap
								worst_at = q
		res[p] = {"on_road": n_on_road, "over": n_over, "worst_gap": snappedf(worst, 0.001) if worst > -INF else null, "at": [snappedf(worst_at.x, 0.1), snappedf(worst_at.z, 0.1)]}
	return res


func _run() -> void:
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out_path = a
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var fx := v.get_node("DrapeFixP13")
	var paths: PackedStringArray = fx.get("paths")
	var faces := PackedVector3Array()
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var path := String(v.get_path_to(m))
		if path.begins_with("Roads/Bridges") or m.mesh == null:
			continue
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix != null and (ix as PackedInt32Array).size() > 0:
				for k in (ix as PackedInt32Array):
					faces.append(xf * vs[k])
			else:
				for k in vs.size():
					faces.append(xf * vs[k])
	tm_road = TriangleMesh.new()
	tm_road.create_from_faces(faces)
	print("[OVL] road triangles ", faces.size() / 3)
	fx.set("enabled", false)
	await process_frame
	var before := _measure(v, paths)
	fx.set("enabled", true)
	await process_frame
	var after := _measure(v, paths)
	var rows := []
	var tb := 0
	var ta := 0
	for p in paths:
		if not before.has(p):
			continue
		var b: Dictionary = before[p]
		var a: Dictionary = after[p]
		tb += int(b["over"])
		ta += int(a["over"])
		if int(a["over"]) > 0 or int(b["over"]) > 0:
			rows.append([p, b["on_road"], b["over"], a["over"], b["worst_gap"], a["worst_gap"], a["at"]])
			print("[OVL] ", p, " on_road=", b["on_road"], " over before=", b["over"], " after=", a["over"], " worst_gap before=", b["worst_gap"], " after=", a["worst_gap"], " at=", a["at"])
	print("[OVL] TOTAL over before=", tb, " after=", ta)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"before": before, "after": after, "total_before": tb, "total_after": ta}, "\t") + "\n")
		f.close()
	quit(0)
