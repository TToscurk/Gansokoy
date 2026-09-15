extends SceneTree
## 探針：指定樹節點的 position / 世界 AABB / 地形高（唯讀）
const SCENE := "res://maps/shrine/shrine.tscn"
const HALF := 75.0
const TARGETS := ["植被/外圍森林/針葉樹2glb/針葉樹2glb_0665", "植被/邊界遮蔽林/針葉樹2glb_0879",
	"植被/外圍森林/大衫/大衫_0298", "植被/外圍森林/普通樹/普通樹_0304", "植被/境內邊緣林",
	"主鳥居2", "參道石階/收頭石", "植被/外圍森林/普通樹/普通樹_0081"]
var _grid: PackedVector3Array
var _res := 0
var _step := 0.0
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var scn: Node3D = load(SCENE).instantiate()
	root.add_child(scn)
	await process_frame
	var mi: MeshInstance3D = scn.get_node("Terrain")
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(v.size()))))
	_step = 2.0 * HALF / float(_res - 1)
	_grid.resize(v.size())
	for p in v:
		_grid[int(round((p.z + HALF) / _step)) * _res + int(round((p.x + HALF) / _step))] = p
	for t in TARGETS:
		var n := scn.get_node_or_null(t)
		if n == null:
			print("[T] missing " + t); continue
		var list := [n] if n.get_child_count() == 0 or t.ends_with("收頭石") == false and not t.ends_with("境內邊緣林") else n.get_children()
		if t.ends_with("收頭石") or t.ends_with("境內邊緣林"):
			list = n.get_children()
		for c in list:
			if not (c is Node3D): continue
			var nd := c as Node3D
			var ms := _mesh_nodes(nd)
			if ms.is_empty(): continue
			var box: AABB = (ms[0] as MeshInstance3D).global_transform * (ms[0] as MeshInstance3D).get_aabb()
			var g := h_at(nd.global_position.x, nd.global_position.z)
			# 地形在 AABB 四角的高低差（坡度指標）
			var g4 := [h_at(box.position.x, box.position.z), h_at(box.end.x, box.position.z), h_at(box.position.x, box.end.z), h_at(box.end.x, box.end.z)]
			print("[T] %-46s pos=(%.2f, %.2f, %.2f) scale=%s aabb.y=[%.2f, %.2f] ground@origin=%.2f Δ=%+.2f  ground@corners=%s"
				% [String(scn.get_path_to(nd)), nd.global_position.x, nd.global_position.y, nd.global_position.z, nd.scale, box.position.y, box.end.y, g, box.position.y - g, g4])
	quit(0)
func h_at(x: float, z: float) -> float:
	var fx := (x + HALF) / _step; var fz := (z + HALF) / _step
	var i := clampi(int(floor(fx)), 0, _res - 2); var j := clampi(int(floor(fz)), 0, _res - 2)
	var tx := clampf(fx - i, 0.0, 1.0); var tz := clampf(fz - j, 0.0, 1.0)
	var a := _grid[j * _res + i].y; var b := _grid[j * _res + i + 1].y
	var c := _grid[(j + 1) * _res + i].y; var d := _grid[(j + 1) * _res + i + 1].y
	if tx + tz <= 1.0: return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)
func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_mesh_nodes(c))
	return o
