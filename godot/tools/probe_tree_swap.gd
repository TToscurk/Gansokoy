extends SceneTree
## 換樹驗收：量 assets/landscape 與 assets/_lod 每棵樹的 AABB / 原點 / 面數 / 材質貼圖。
##   Godot --headless --path godot --script tools/probe_tree_swap.gd

const DIRS := ["res://assets/landscape/", "res://assets/_lod/"]
const TREES := ["大衫", "2大衫", "普通樹", "針葉樹1", "針葉樹2glb",
	"針葉林樹3", "針葉林樹4", "盆樹", "櫻花樹", "楓樹", "松樹", "竹垣", "鎮守之杜"]


func _init() -> void:
	for d in DIRS:
		print("── ", d)
		for name in TREES:
			var path: String = d + name + ".glb"
			if not ResourceLoader.exists(path):
				continue
			var ps := load(path) as PackedScene
			if ps == null:
				print("  %-10s 載入失敗" % name)
				continue
			var inst := ps.instantiate() as Node3D
			var box: AABB = AABB()
			var first := true
			var tris := 0
			var mats := 0
			var tex_ok := true
			for m in _all_mesh(inst):
				var mi: MeshInstance3D = m
				var b: AABB = mi.transform * mi.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
				for s in mi.mesh.get_surface_count():
					mats += 1
					var arr: Array = mi.mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					tris += idx.size() / 3
					var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
					if mat == null or mat.albedo_texture == null:
						tex_ok = false
			print("  %-10s %.3f x %.3f x %.3f  min.y %+.4f  %5d tris  %d surf  albedo %s"
				% [name, box.size.x, box.size.y, box.size.z, box.position.y,
					tris, mats, "OK" if tex_ok else "缺"])
			inst.free()
	quit()


func _all_mesh(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
