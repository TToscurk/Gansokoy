extends SceneTree
## 互動點體檢：列出每張圖的 WorldInteraction —— 位置、範圍、提示字、按 E 實際做什麼。
## 「顯示提示但按 E 沒作用」的空頭互動點會被標成 DEAD。
##   Godot --headless --path godot --script tools/audit_interactions.gd
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ground(x: float, z: float) -> float:
	var space := main.get_viewport().get_world_3d().direct_space_state
	var ex: Array[RID] = [main.player.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -100.0, z))
	for k in 8:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			return -INF
		var col: Object = hit.get("collider")
		var nm := String(col.name) if col else ""
		if not (nm.contains("Boundary") or nm.contains("邊界") or nm.contains("boundary")):
			return hit.position.y
		ex.append(hit.rid)
	return -INF


func _audit(map_id: String) -> void:
	main.load_map(map_id, "")
	await _settle(30)
	print("[AUDIT] ── %s ──" % map_id)
	var n := 0
	for wi in main.get_tree().get_nodes_in_group("world_interaction"):
		n += 1
		var a := wi as Area3D
		var p: Vector3 = a.global_position
		var size := Vector3.ZERO
		for c in a.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				size = ((c as CollisionShape3D).shape as BoxShape3D).size
		var prompt: String = wi.prompt_text()
		var dlg := String(wi.get("dialogue_id"))
		var qt := String(wi.get("quest_event_type"))
		var auto: bool = bool(wi.get("auto_trigger"))
		# 按 E 有沒有作用：有對話，或有非 REACH 的任務事件
		var payload: bool = not dlg.is_empty() or (qt != "NONE" and qt != "REACH")
		var dead: bool = not prompt.is_empty() and not payload
		var gy := _ground(p.x, p.z)
		print("[AUDIT] %s id=%s pos=(%.1f, %.1f, %.1f) 地面=%.2f box=%s auto=%s dlg=%s quest=%s/%s prompt=%s"
			% ["DEAD" if dead else "ok ", String(wi.get("interaction_id")), p.x, p.y, p.z,
			gy, str(size), auto, dlg if dlg != "" else "-", qt,
			String(wi.get("quest_target_id")) if String(wi.get("quest_target_id")) != "" else "-",
			("「%s」" % prompt.replace("\n", "／")) if prompt != "" else "（無）"])
	print("[AUDIT] %s 互動點 %d 個" % [map_id, n])


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	for m in ["trail", "shrine", "slice"]:
		await _audit(m)
	# 人里落點與候選觸發位置的地面高度
	print("[AUDIT] ── slice 里口地面 ──")
	for c in [[236.0, 112.0, "傳送點"], [232.4, 110.3, "落地點"], [234.0, 100.0, "里口內側 z=100"],
			[234.0, 90.0, "z=90"], [236.0, 80.0, "z=80"]]:
		print("[AUDIT] %s (%.1f, %.1f) 地面=%.2f" % [c[2], c[0], c[1], _ground(c[0], c[1])])
	quit(0)
