extends SceneTree

# PHASE 3.2 Art Review 診断：本通の中核ギャップに何が建っているかを
# 「見えているか」まで含めて実測して JSON に吐く使い捨てプローブ。
#   ・町家 MultiMesh を全部展開（module 名 + 位置 + yaw + AABB）
#   ・地標／塔／橋などの Node3D も拾う
#   ・shots の各カメラから可視判定（frustum ∩ 遮蔽レイ）

func _init() -> void:
	var scn: PackedScene = load("res://maps/village/village.tscn")
	var root := scn.instantiate()
	get_root().add_child(root)
	await process_frame

	var out := {"buildings": [], "landmarks": []}
	_walk(root, root, out)
	var f := FileAccess.open("res://../village_audit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("buildings=%d landmarks=%d" % [out.buildings.size(), out.landmarks.size()])
	quit()

func _walk(n: Node, root: Node, out: Dictionary) -> void:
	for c in n.get_children():
		_walk(c, root, out)
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return
		var nm := String(n.name)
		if not nm.begins_with("MM_machiya"):
			return
		nm = nm.substr(3)
		var ab := mm.mesh.get_aabb()
		var gx := (n as Node3D).global_transform
		# ⚠ シーンから読み込んだ MultiMesh は get_instance_transform() が
		#   全部ゼロを返す（既知）。buffer を stride 12 で直接読む。
		var buf: PackedFloat32Array = mm.buffer
		var stride := 12
		for i in mm.instance_count:
			var o := i * stride
			var t: Transform3D = gx * Transform3D(
				Vector3(buf[o + 0], buf[o + 4], buf[o + 8]),
				Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
				Vector3(buf[o + 2], buf[o + 6], buf[o + 10]),
				Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
			out.buildings.append({
				"mod": nm, "i": i,
				"x": t.origin.x, "y": t.origin.y, "z": t.origin.z,
				"yaw": t.basis.get_euler().y,
				"aw": ab.size.x, "ah": ab.size.y, "ad": ab.size.z,
				"ac": [ab.position.x + ab.size.x * 0.5,
					ab.position.y + ab.size.y * 0.5,
					ab.position.z + ab.size.z * 0.5],
			})
	elif n is Node3D and (n.get_parent() == root
			or String(n.get_parent().name) in ["地標佔位", "地標塔", "橋", "門樓",
				"火の番の辻", "本通の節"]):
		var nn := String(n.name)
		var ab2 := AABB()
		var got := false
		var st := [n]
		while not st.is_empty():
			var q: Node = st.pop_back()
			for c2 in q.get_children():
				st.append(c2)
			if q is VisualInstance3D:
				var a: AABB = (q as VisualInstance3D).global_transform * (q as VisualInstance3D).get_aabb()
				ab2 = a if not got else ab2.merge(a)
				got = true
		if got and ab2.size.y > 1.5:
			out.landmarks.append({
				"name": nn,
				"cx": ab2.position.x + ab2.size.x * 0.5,
				"cz": ab2.position.z + ab2.size.z * 0.5,
				"w": ab2.size.x, "h": ab2.size.y, "d": ab2.size.z,
				"y0": ab2.position.y,
			})
