extends SceneTree
## 人間之里「有做東西的範圍」量測：邊界牆要圈住內容，不是圈住地面
## （UnifiedGround 是 2500 m 見方的大地面，到處都站得住，所以地面範圍沒有參考價值）。
##   Godot --headless --path godot --script tools/audit_slice_content.gd
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	var mr: Node = main.map_root
	# 這些是「鋪滿全場的底」，不算內容
	var GROUND := ["UnifiedGround", "Terrain", "BasinHills", "GroundUnderlay",
		"場景效能裁剪", "天象系統", "地面碰撞_刷筆用", "建物碰撞", "路燈碰撞", "手動碰撞"]
	var total := AABB()
	var first := true
	var rows := []
	for top in mr.get_children():
		var nm := String(top.name)
		if nm in GROUND or nm.begins_with("Portal_"):
			continue
		var wb := AABB()
		var f := true
		var stack: Array[Node] = [top]
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.push_back(c)
			var b := AABB()
			if n is MultiMeshInstance3D:
				var mm := (n as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null or not (n as Node3D).is_visible_in_tree():
					continue
				# MultiMesh 的 AABB 要逐實例算，節點 AABB 只涵蓋來源網格
				var mmi := n as MultiMeshInstance3D
				var mb := mm.mesh.get_aabb()
				var f2 := true
				for i in mm.instance_count:
					var t: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
					var ib: AABB = t * mb
					if f2:
						b = ib
						f2 = false
					else:
						b = b.merge(ib)
				if f2:
					continue
			elif n is MeshInstance3D:
				if not (n as Node3D).is_visible_in_tree():
					continue
				b = (n as Node3D).global_transform * (n as MeshInstance3D).get_aabb()
			else:
				continue
			if f:
				wb = b
				f = false
			else:
				wb = wb.merge(b)
		if f:
			continue
		# 遠景山、天空盒之類超大件不納入遊玩範圍
		if wb.size.x > 300.0 or wb.size.z > 300.0:
			print("[CONT] （略過超大件 %s：%.0f × %.0f m）" % [nm, wb.size.x, wb.size.z])
			continue
		rows.append([nm, wb])
		if first:
			total = wb
			first = false
		else:
			total = total.merge(wb)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	for r in rows:
		var wb: AABB = r[1]
		print("[CONT] %-22s x[%7.1f, %7.1f] z[%7.1f, %7.1f]"
			% [r[0], wb.position.x, wb.end.x, wb.position.z, wb.end.z])
	print("[CONT] ══ 內容總範圍 x[%.1f, %.1f] z[%.1f, %.1f]（%.0f × %.0f m）══"
		% [total.position.x, total.end.x, total.position.z, total.end.z,
		total.size.x, total.size.z])
	print("[CONT] 傳送點：")
	for p in main.current_portals():
		print("[CONT]   %-10s (%.0f, %.0f)" % [String(p.get("target", "保留")), float(p.x), float(p.z)])
	quit(0)
