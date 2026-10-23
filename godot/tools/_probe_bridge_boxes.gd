extends SceneTree
## 暫用探針（不進版控）：印出 Roads/Bridges、Landmarks、Districts 底下每個 CollisionShape3D
## 的世界 AABB（中心、尺寸）與所屬節點，用來判定「護岸石被誰擋掉」。
## 只讀場景，不呼叫 plan()，所以很快。
## 用法：godot --headless --path . --script res://tools/_probe_bridge_boxes.gd
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for gp: String in ["Roads/Bridges", "Landmarks", "Districts"]:
		var g := v.get_node_or_null(gp)
		if g == null:
			print("[BB] (no %s)" % gp)
			continue
		print("\n[BB] ===== %s =====" % gp)
		for cs in g.find_children("*", "CollisionShape3D", true, false):
			var c := cs as CollisionShape3D
			if c.shape == null or c.disabled:
				continue
			var ab: AABB = c.shape.get_debug_mesh().get_aabb()
			var xf := _rel_xf(c, v) * Transform3D(Basis.from_scale(ab.size * 0.5), ab.get_center())
			var o := xf.origin
			var sz := (xf.basis * Vector3.ONE).abs()
			var path := String(v.get_path_to(c))
			# 只印與河有關的（MainRiver 401,-197 附近；Canal 335,-29 附近）
			print("[BB] %-58s c=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [
				path, o.x, o.y, o.z, sz.x, sz.y, sz.z])
	quit(0)


static func _rel_xf(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
