extends SceneTree
## Measure the water wheel GLB so the spin axis and axle height are facts, not
## guesses.
##
## Why this matters: a water wheel must rotate about its axle. Pick the wrong
## axis and it tumbles like a coin; pick the wrong pivot and it wobbles off
## centre. Neither is obvious from the file — Meshy exports vary in origin and
## orientation, and this project has already been bitten by assuming one.
##
## The axle is the SHORT axis of the wheel disc: the two long axes span the
## wheel's face, the short one is its thickness.
##
## Run: godot --headless --path godot --script tools/probe_waterwheel.gd

const CANDIDATES := [
	"res://assets/riverbank/水車.glb",
	"res://assets/riverbank/水車(窄).glb",
	"res://assets/riverbank/水車小屋.glb",
]


func _init() -> void:
	for path in CANDIDATES:
		print("\n=== %s ===" % path.get_file())
		if not ResourceLoader.exists(path):
			print("  不存在")
			continue
		var packed = load(path)
		if packed == null:
			print("  載入失敗")
			continue
		var inst = packed.instantiate()

		var meshes := _meshes(inst)
		print("  節點結構:")
		_dump(inst, 2)

		var box := AABB()
		var first := true
		for mi in meshes:
			if mi.mesh == null:
				continue
			var b: AABB = mi.transform * mi.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
		if first:
			print("  無幾何")
			inst.free()
			continue

		var s := box.size
		print("  AABB 尺寸: X %.3f  Y %.3f  Z %.3f" % [s.x, s.y, s.z])
		print("  AABB 中心: (%.3f, %.3f, %.3f)" % [
			box.get_center().x, box.get_center().y, box.get_center().z])
		print("  AABB 底部 Y: %.3f   頂部 Y: %.3f" % [box.position.y, box.end.y])

		# The axle is the thinnest axis; the wheel face spans the other two.
		var axis := "X"
		var thin := s.x
		if s.y < thin:
			axis = "Y"
			thin = s.y
		if s.z < thin:
			axis = "Z"
			thin = s.z
		print("  >> 最薄軸 = %s (%.3f)，輪面在另外兩軸 → 轉軸應為 %s" % [axis, thin, axis])

		# Is the model centred on its own origin, or offset?
		var c := box.get_center()
		if abs(c.x) > 0.05 or abs(c.y) > 0.05 or abs(c.z) > 0.05:
			print("  >> 幾何中心偏離原點 (%.3f, %.3f, %.3f) — 直接旋轉節點會偏心" % [c.x, c.y, c.z])
		else:
			print("  >> 幾何中心就在原點，可直接旋轉節點")

		inst.free()
	quit(0)


func _dump(node: Node, indent: int) -> void:
	var pad := ""
	for i in indent:
		pad += " "
	var extra := ""
	if node is MeshInstance3D and node.mesh != null:
		extra = "  [mesh %d surface]" % node.mesh.get_surface_count()
	print("%s%s (%s)%s" % [pad, node.name, node.get_class(), extra])
	for c in node.get_children():
		_dump(c, indent + 2)


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
