extends SceneTree
## 探針：沿地圖邊緣印 terrain / vista 網格頂點實際高度（唯讀）
const SCENE := "res://maps/shrine/shrine.tscn"
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var scn: Node3D = load(SCENE).instantiate()
	root.add_child(scn)
	await process_frame
	for nm in ["Terrain", "Vista"]:
		var mi: MeshInstance3D = scn.get_node(nm)
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		print("[P] %s xf=%s verts=%d aabb=%s" % [nm, xf, v.size(), xf * mi.get_aabb()])
		# 印 x≈75 附近、z=-75..75 的頂點
		var rows := {}
		for p0 in v:
			var p := xf * p0
			if absf(p.x - 72.0) < 0.5 or absf(p.x - 75.0) < 0.5 or absf(p.x - 90.0) < 0.5 or absf(p.x + 75.0) < 0.5 or absf(p.x + 72.0) < 0.5 or absf(p.x + 90.0) < 0.5:
				if absf(p.z) <= 90.0:
					var k := "%d" % int(round(p.x))
					if not rows.has(k): rows[k] = []
					rows[k].append("%d:%.1f" % [int(round(p.z)), p.y])
		for k in rows.keys():
			print("[P] %s x=%s  %s" % [nm, k, " ".join(rows[k])])
	quit(0)
