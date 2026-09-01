extends SceneTree
## 火見櫓落位稽核：驗證世界 AABB、落地高度、與街廓建築的實際淨空。
## 量產出物（載入存檔後的 slice.tscn），不看放置腳本的參數。

const STREET_X: float = 235.0
const TORII_Z: float = 101.0
const EYE: float = 1.6

func _wbox(n: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[n, (n as Node3D).transform]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			if has:
				acc = acc.merge(a)
			else:
				acc = a
				has = true
		for c in node.get_children():
			if c is Node3D:
				stack.push_back([c, xf * (c as Node3D).transform])
	return acc

func _init() -> void:
	var scn: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node3D = scn.instantiate() as Node3D

	var t: Node3D = root.get_node_or_null("火見櫓") as Node3D
	if t == null:
		print("FAIL 火見櫓 不在場景中")
		quit()
		return
	var bb: AABB = _wbox(t)
	print("=== 火見櫓 落位實測 ===")
	print("世界 AABB  pos=(%.2f, %.3f, %.2f)  size=(%.2f, %.2f, %.2f)" % [
		bb.position.x, bb.position.y, bb.position.z,
		bb.size.x, bb.size.y, bb.size.z])
	print("底面 y = %.3f   （街廓建築 SINK 基準 -0.15，本體 -0.12）" % bb.position.y)
	print("頂端 y = %.3f" % (bb.position.y + bb.size.y))
	var cx: float = bb.position.x + bb.size.x * 0.5
	var cz: float = bb.position.z + bb.size.z * 0.5
	print("平面中心 = (%.2f, %.2f)  目標 (224.00, -67.00)  偏差 %.3f m" % [
		cx, cz, Vector2(cx - 224.0, cz + 67.0).length()])

	# 與 B1_Street 每棟的實際淨空
	var worst: float = 1e9
	var who: String = "-"
	var street: Node = root.get_node_or_null("B1_Street")
	var n: int = 0
	if street != null:
		for c in street.get_children():
			if not (c is Node3D):
				continue
			var nm: String = String(c.name)
			if nm in ["StreetPaving", "PlazaMarket"]:
				continue
			var ob: AABB = _wbox(c as Node3D)
			var dx: float = maxf(maxf(ob.position.x - (bb.position.x + bb.size.x),
				bb.position.x - (ob.position.x + ob.size.x)), 0.0)
			var dz: float = maxf(maxf(ob.position.z - (bb.position.z + bb.size.z),
				bb.position.z - (ob.position.z + ob.size.z)), 0.0)
			var d: float = Vector2(dx, dz).length()
			n += 1
			if d < worst:
				worst = d
				who = nm
	print("最近建築淨空 = %.2f m (%s)   檢查 %d 棟   %s" % [
		worst, who, n, "OK" if worst > 0.5 else "!! 重疊"])

	# 從大鳥居的視線關係
	var eye_y: float = EYE
	var d_h: float = Vector2(cx - STREET_X, cz - (TORII_Z - 4.0)).length()
	var ang: float = rad_to_deg(atan2(absf(cx - STREET_X), absf(cz - (TORII_Z - 4.0))))
	var elev: float = rad_to_deg(atan2((bb.position.y + bb.size.y) - eye_y, d_h))
	print("自大鳥居：視距 %.1f m   水平偏角 %.2f°   塔頂仰角 %.2f°" % [d_h, ang, elev])

	# 其他地標的高度對照
	print("")
	print("=== 天際線對照 ===")
	for nm2 in ["寺子屋", "鈴奈庵", "霧雨店", "鯢吞亭", "稗田底新版"]:
		var o: Node3D = root.get_node_or_null(nm2) as Node3D
		if o == null:
			continue
		var ob2: AABB = _wbox(o)
		print("%-10s 高 %6.2f m   頂端 y=%.2f" % [nm2, ob2.size.y, ob2.position.y + ob2.size.y])
	print("%-10s 高 %6.2f m   頂端 y=%.2f  <-- 新增" % ["火見櫓", bb.size.y, bb.position.y + bb.size.y])
	root.free()
	quit()
