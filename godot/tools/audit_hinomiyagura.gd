extends SceneTree
## 火見櫓資產實測：AABB、頂點/面數、材質與貼圖、正面軸判定。
## 依 .claude/rules/godot.md：量產出物不信參數；prop_* 曾因 albedo_tex=0 全數報廢，必驗。

func _init() -> void:
	var path: String = "res://assets/landmark/火見櫓.glb"
	if not ResourceLoader.exists(path):
		print("MISSING %s" % path)
		quit()
		return
	var scn: PackedScene = load(path)
	var root: Node = scn.instantiate()
	var meshes: int = 0
	var surfaces: int = 0
	var verts: int = 0
	var tris: int = 0
	var mats: Dictionary = {}
	var tex_albedo: int = 0
	var tex_normal: int = 0
	var tex_orm: int = 0
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = node
			var m: Mesh = mi.mesh
			meshes += 1
			surfaces += m.get_surface_count()
			for si in range(m.get_surface_count()):
				var arr: Array = m.surface_get_arrays(si)
				var v = arr[Mesh.ARRAY_VERTEX]
				if v != null:
					verts += (v as PackedVector3Array).size()
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx != null:
					tris += (idx as PackedInt32Array).size() / 3
				var mat: Material = m.surface_get_material(si)
				if mat != null:
					mats[str(mat.resource_name)] = true
					if mat is BaseMaterial3D:
						var bm: BaseMaterial3D = mat
						if bm.albedo_texture != null:
							tex_albedo += 1
						if bm.normal_texture != null:
							tex_normal += 1
						if bm.roughness_texture != null or bm.metallic_texture != null:
							tex_orm += 1
			var a: AABB = xf * m.get_aabb()
			if has:
				acc = acc.merge(a)
			else:
				acc = a
				has = true
		for c in node.get_children():
			stack.push_back([c, xf])

	print("=== 火見櫓.glb ===")
	print("mesh=%d  surfaces=%d  verts=%d  tris=%d  materials=%d" % [
		meshes, surfaces, verts, tris, mats.size()])
	print("貼圖: albedo=%d  normal=%d  orm=%d" % [tex_albedo, tex_normal, tex_orm])
	print("AABB pos=(%.3f, %.3f, %.3f)  size=(%.3f, %.3f, %.3f)" % [
		acc.position.x, acc.position.y, acc.position.z,
		acc.size.x, acc.size.y, acc.size.z])
	var c: Vector3 = acc.position + acc.size * 0.5
	print("中心=(%.3f, %.3f, %.3f)   底面 y=%.3f" % [c.x, c.y, c.z, acc.position.y])
	print("原點是否在底面中心：dx=%.3f dz=%.3f dy_bottom=%.3f （越接近 0 越好）" % [
		c.x, c.z, acc.position.y])
	# 長寬比：判斷細高程度
	var foot: float = maxf(acc.size.x, acc.size.z)
	print("高寬比 = %.2f （高 %.2f / 底 %.2f）" % [acc.size.y / maxf(foot, 0.001), acc.size.y, foot])
	# 目標 15m 需要的縮放
	print("縮放到 15m 高需 scale = %.4f" % (15.0 / maxf(acc.size.y, 0.001)))
	root.free()
	quit()
