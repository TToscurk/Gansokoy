extends SceneTree
## 量測 v3：收刀可視網格（Sword_Sheathed / Sheath 刀鞘本體）的世界 AABB ＋ 對骨架空間換算，
## 並用 30 點取樣 mesh 局部 bbox 的旋轉後範圍，確認柄端/鞘尖兩極端點。
## 執行：godot --headless --path godot -s res://tools/probe_sheath_transform.gd

var _skel: Skeleton3D

func _to_skel(v: Vector3) -> Vector3:
	return _skel.global_transform.affine_inverse() * v

func _init() -> void:
	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var p := ps.instantiate()
	root.add_child(p)
	for i in 30:
		await physics_frame
	p.sword_state = p.SwordState.SHEATHED
	p._apply_sword_visibility()
	for i in 10:
		await physics_frame
	_skel = p.find_children("*", "Skeleton3D", true, false)[0]
	for inst_name in ["Sword_Sheathed", "Sheath"]:
		var n: Node3D = null
		var stack: Array[Node] = [p]
		while not stack.is_empty() and n == null:
			var c: Node = stack.pop_back()
			if c.name == inst_name:
				n = c as Node3D
			else:
				for ch in c.get_children():
					stack.append(ch)
		if n == null:
			print("[", inst_name, "] NOT FOUND")
			continue
		# 取所有 MeshInstance3D 的世界 AABB
		var aabb := AABB()
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		for mi in mis:
			var m: MeshInstance3D = mi
			var wa := m.global_transform * m.get_aabb()
			aabb = aabb.merge(wa) if not aabb.has_point(aabb.position) and aabb.size != Vector3.ZERO else wa
		print("[", inst_name, "] world_aabb pos ", aabb.position, " size ", aabb.size)
		print("   skel-space: min ", _to_skel(aabb.position), " max ", _to_skel(aabb.position + aabb.size))
	quit(0)
