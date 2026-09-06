extends SceneTree
## 西北展望走廊的空缺量測：沿走廊軸線取樣，看每段距離有多少樹。
## 用來決定「補一點點樹」該補在哪個距離帶、補多少才不會遮到妖怪之山。
##
##   Godot --headless --path godot --script tools/audit_vista_corridor.gd

const SCENE := "res://maps/shrine/shrine.tscn"
const DIR := Vector2(-0.92, -0.39)     # 與 gen_shrine_blockout.VISTA_DIR 同
const HALF_ANGLE := 17.0
const ORIGIN := Vector2(0.0, -20.5)    # 境內中央
const EYE_Y := 4.9


func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	# 收集所有樹（植被群組下的實例根）
	var trees: Array = []
	var veg := root.find_child("植被", true, false)
	if veg != null:
		_collect(veg, root, trees)
	print("[COR] 場上樹木 %d 棵" % trees.size())
	# 分距離帶統計走廊內的樹
	var bands := [[0.0, 20.0], [20.0, 40.0], [40.0, 60.0], [60.0, 80.0], [80.0, 120.0]]
	for b in bands:
		var n := 0
		var max_top := 0.0
		for t in trees:
			var p: Vector2 = t[0]
			var rel := p - ORIGIN
			var d := rel.length()
			if d < float(b[0]) or d >= float(b[1]):
				continue
			if rel.normalized().dot(DIR) < cos(deg_to_rad(HALF_ANGLE)):
				continue
			n += 1
			var top: float = t[1] + t[2]     # 底 y + 高
			var deg := rad_to_deg(atan2(top - EYE_Y, d))
			max_top = maxf(max_top, deg)
		print("[COR] 走廊 %3.0f-%3.0f m：%3d 棵，最高樹冠仰角 %.1f°" % [b[0], b[1], n, max_top])
	# 妖怪之山在走廊裡的仰角範圍（山底 1.0°、山高 380 m、距 850 m）
	var m_base := rad_to_deg(atan2(20.0 - EYE_Y, 850.0))
	var m_top := rad_to_deg(atan2(20.0 + 380.0 - EYE_Y, 850.0))
	print("[COR] 妖怪之山佔據仰角 %.1f° ~ %.1f°" % [m_base, m_top])
	print("[COR] → 補樹的樹冠仰角要 < %.1f° 才不會壓到山體" % m_top)
	root.free()
	quit(0)


func _collect(n: Node, root: Node3D, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D and c.get_child_count() > 0 and not (c is MeshInstance3D):
			_collect(c, root, out)
		var box: Variant = null
		for m in _meshes(c):
			var mi := m as MeshInstance3D
			var b := _rel(mi, root) * mi.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		if box != null:
			var bb: AABB = box
			if bb.size.y > 4.0:      # 只算樹，不算地被
				out.append([Vector2(bb.position.x + bb.size.x * 0.5,
					bb.position.z + bb.size.z * 0.5), bb.position.y, bb.size.y])


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
