extends SceneTree
## Verify the sakura tree mesh and its material actually render.
##
## Why check before re-placing: the user says undo did not bring the trees back,
## so re-adding 17 instances of a broken mesh would just produce 17 more
## invisible trees. The MultiMesh settings are identical to the tree types that
## still show, so if anything is wrong it is in the mesh resource or its
## material — most likely an alpha/transparency or albedo change, since those
## are the settings a user is most likely to have been adjusting on a foliage
## asset when it "suddenly disappeared".
##
## Compares the sakura mesh against a tree type the user can still see.
##
## Run: godot --headless --path godot --script tools/check_sakura_mesh.gd

const DIR := "res://maps/slice/gen"
const SUBJECTS := ["櫻花樹", "普通樹"]  # broken?, known-good control


func _init() -> void:
	for name in SUBJECTS:
		print("\n=== %s ===" % name)
		var mm_path := "%s/treemm_%s.res" % [DIR, name]
		var mm = load(mm_path)
		if mm == null:
			print("  MultiMesh 載入失敗: %s" % mm_path)
			continue

		var mesh: Mesh = mm.mesh
		if mesh == null:
			print("  << MultiMesh 沒有 mesh")
			continue

		print("  mesh: %s" % mesh.resource_path)
		var box: AABB = mesh.get_aabb()
		print("  mesh AABB: 高 %.2fm  寬 %.2f x %.2f" % [
			box.size.y, box.size.x, box.size.z])
		if box.size == Vector3.ZERO:
			print("  << mesh 本身沒有幾何！")

		print("  surface 數: %d" % mesh.get_surface_count())
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if mat == null:
				print("  surface %d: 沒有材質  << 會用預設白色" % s)
				continue
			print("  surface %d: %s" % [s, mat.get_class()])
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				print("    albedo 色: %s" % sm.albedo_color)
				print("    albedo 貼圖: %s" % (
					sm.albedo_texture.resource_path if sm.albedo_texture else "<無>"))
				print("    透明模式: %d  (0=不透明 1=alpha 2=scissor 3=hash)" % sm.transparency)
				print("    scissor 閾值: %.2f" % sm.alpha_scissor_threshold)
				print("    剔除模式: %d  (0=背面 1=正面 2=不剔除)" % sm.cull_mode)
				print("    著色模式: %d  (0=lambert...)" % sm.shading_mode)
				print("    no_depth_test: %s" % sm.no_depth_test)
				print("    grow: %s (%.2f)" % [sm.grow, sm.grow_amount])
				# The two that most often make foliage vanish outright.
				if sm.albedo_color.a <= 0.01:
					print("    << albedo alpha 為 0，完全透明")
				if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
						and sm.alpha_scissor_threshold >= 0.99:
					print("    << scissor 閾值 1.0，整棵樹被裁掉")
			elif mat is ShaderMaterial:
				var shm := mat as ShaderMaterial
				print("    shader: %s" % (
					shm.shader.resource_path if shm.shader else "<無>"))
	quit(0)
