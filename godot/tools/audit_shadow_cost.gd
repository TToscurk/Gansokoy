extends SceneTree
## What is actually casting shadows, and how expensive is the shadow pass?
##
## Why: the LOD pass reported "6952 casters before, 6944 after" and then
## "限制投影距離 0" — two different signals that the shadow work is not landing
## where I assumed. Before writing another pass, find out which nodes really
## carry SHADOW_CASTING_SETTING_ON and how many triangles they push through the
## shadow cascades, because that is the number that decides whether shadow
## culling is even the right lever.
##
## Run: godot --headless --path godot --script tools/audit_shadow_cost.gd

const SCENE := "res://maps/slice/slice.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate()

	var by_group := {}
	var total_cast := 0
	var total_tris := 0
	var off := 0

	for child in root.get_children():
		var s := {"cast": 0, "tris": 0, "off": 0}
		_walk(child, s)
		by_group[child.name] = s
		total_cast += s["cast"]
		total_tris += s["tris"]
		off += s["off"]

	var names := by_group.keys()
	names.sort_custom(func(a, b): return by_group[a]["tris"] > by_group[b]["tris"])

	print("=== 陰影投射成本（依投影三角面排序）===\n")
	print("%-28s %10s %12s %10s" % ["節點", "投影物件", "投影三角面", "已關閉"])
	for n in names:
		var g = by_group[n]
		if g["cast"] == 0 and g["off"] == 0:
			continue
		print("%-28s %10d %12s %10d" % [
			n.substr(0, 28), g["cast"], _fmt(g["tris"]), g["off"]])

	print("\n合計：投影物件 %d，投影三角面 %s，已關閉 %d" % [
		total_cast, _fmt(total_tris), off])
	print("\n註：定向光有 4 個 cascade，最壞情況下這些幾何要重繪 4 次。")
	print("    等效負擔約 %s 三角面。" % _fmt(total_tris * 4))

	root.free()
	quit(0)


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _walk(node: Node, s: Dictionary) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			s["off"] += 1
		else:
			s["cast"] += 1
			s["tris"] += _tris_of(gi)
	for c in node.get_children():
		_walk(c, s)


func _tris_of(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var mult := 1
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
			mult = mm.instance_count
	if mesh == null:
		return 0
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				t += v.size() / 3
	return t * mult
