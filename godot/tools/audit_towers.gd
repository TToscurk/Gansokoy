extends SceneTree
## 一次性稽核：assets/models/tower_*.glb 是否為可用資產
## 檢查每個 GLB 的 mesh 數、頂點數、surface 數、材質數、貼圖數、實測 AABB。
## 動機：prop_*.glb 那批因 materials=0/images=0（純白塑膠）於 89e219b 整批刪除，
## tower_* 是同一天同一批匯入，必須先驗。

func _init() -> void:
	var names: Array = ["tower_fire", "tower_bell", "tower_bell_p", "tower_mill"]
	for nm in names:
		var path: String = "res://assets/models/%s.glb" % nm
		if not ResourceLoader.exists(path):
			print("%-14s MISSING" % nm)
			continue
		var scn: PackedScene = load(path)
		if scn == null:
			print("%-14s LOAD_FAIL" % nm)
			continue
		var root: Node = scn.instantiate()
		var meshes: int = 0
		var verts: int = 0
		var surfaces: int = 0
		var mats: Dictionary = {}
		var textured: int = 0
		var acc: AABB = AABB()
		var has: bool = false
		var stack: Array = [[root, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var pair: Array = stack.pop_back()
			var node: Node = pair[0]
			var xf: Transform3D = pair[1]
			if node is Node3D:
				xf = xf * (node as Node3D).transform
			if node is MeshInstance3D:
				var mi: MeshInstance3D = node
				if mi.mesh != null:
					meshes += 1
					var m: Mesh = mi.mesh
					surfaces += m.get_surface_count()
					for si in range(m.get_surface_count()):
						var arr: Array = m.surface_get_arrays(si)
						if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
							verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
						var mat: Material = m.surface_get_material(si)
						if mat != null:
							mats[mat.resource_name if mat.resource_name != "" else str(mat)] = true
							if mat is BaseMaterial3D:
								var bm: BaseMaterial3D = mat
								if bm.albedo_texture != null:
									textured += 1
					var a: AABB = xf * m.get_aabb()
					if has:
						acc = acc.merge(a)
					else:
						acc = a
						has = true
			for c in node.get_children():
				stack.push_back([c, xf])
		print("%-14s mesh=%-3d surf=%-3d verts=%-6d mats=%-2d albedo_tex=%-2d  size=(%.2f x %.2f x %.2f)" % [
			nm, meshes, surfaces, verts, mats.size(), textured,
			acc.size.x, acc.size.y, acc.size.z])
		root.free()
	quit()
