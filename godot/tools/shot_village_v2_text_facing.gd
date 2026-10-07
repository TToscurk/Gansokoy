extends SceneTree
## 字の向き 表裏撮影（審圖・修正確認用）：各対象の「字の領域」の三角形の重心と法線を求め、表（+n）と裏（−n）から撮る。
## 使い方：godot --path godot --script res://tools/shot_village_v2_text_facing.gd -- <list.json> <outdir/>
##   list.json＝[[name, res_path, node_name or "", region], ...]（res_path は Mesh の .res か .scn；.scn は node_name の MeshInstance3D）
const A := preload("res://tools/village_v2_text_facing_lib.gd")

func region_faces(mesh: Mesh, region: Rect2, surfs: Array) -> Array:
	var out := []
	for si in mesh.get_surface_count():
		if not si in surfs: continue
		var arr := mesh.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		if UV.is_empty(): continue
		var I = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = I if I != null and (I as PackedInt32Array).size() > 0 else PackedInt32Array(range(V.size()))
		for t in range(0, idx.size(), 3):
			var a := idx[t]; var b := idx[t + 1]; var c := idx[t + 2]
			if not region.grow(0.0005).has_point((UV[a] + UV[b] + UV[c]) / 3.0): continue
			var area := (V[b] - V[a]).cross(V[c] - V[a]).length() * 0.5
			out.append([(V[a] + V[b] + V[c]) / 3.0, (N[a] + N[b] + N[c]).normalized(), area, V[a], V[b], V[c]])
	return out

func _initialize():
	go.call_deferred()

func go():
	var args := OS.get_cmdline_user_args()
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var outdir: String = args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	root.size = Vector2i(420, 420)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_energy = 0.9
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 35
	root.add_child(cam)
	var aud = A.new()
	for it in items:
		var name: String = it[0]; var path: String = it[1]; var node_name: String = it[2]; var reg: String = it[3]
		var holder := Node3D.new()
		root.add_child(holder)
		var mi: MeshInstance3D
		var res = load(path)
		if res is PackedScene:
			var inst: Node = res.instantiate()
			holder.add_child(inst)
			for n in inst.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).visible = String(n.name) == node_name
				if String(n.name) == node_name: mi = n
		else:
			mi = MeshInstance3D.new(); mi.mesh = res; holder.add_child(mi)
		var rect := Rect2()
		var surfs := []
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_surface_override_material(si) if mi.get_surface_override_material(si) else mi.mesh.surface_get_material(si)
			var tex = aud.mat_tex(mat) if mat else null
			if tex == null: continue
			var at: Dictionary = aud.atlas_for(tex.resource_path)
			if not at.is_empty() and (at.regions as Dictionary).has(reg): rect = at.regions[reg]; surfs.append(si)
		var faces := region_faces(mi.mesh, rect, surfs)
		if faces.is_empty():
			print("[SHOT] no faces ", name); holder.queue_free(); continue
		# 表＝面積の大きい向きの法線（字の板の両面なら最大の群の向き）
		var bins := {}
		for f in faces:
			var n: Vector3 = f[1]
			var k := "%d,%d,%d" % [roundi(n.x * 2), roundi(n.y * 2), roundi(n.z * 2)]
			bins[k] = float(bins.get(k, 0.0)) + float(f[2])
		var best := ""
		for k in bins: if best == "" or bins[k] > bins[best]: best = k
		var nsum := Vector3.ZERO; var lo := Vector3(1e9, 1e9, 1e9); var hi := -lo
		for f in faces:
			for v in [f[3], f[4], f[5]]: lo = lo.min(v); hi = hi.max(v)
			var n: Vector3 = f[1]
			if "%d,%d,%d" % [roundi(n.x * 2), roundi(n.y * 2), roundi(n.z * 2)] == best: nsum += n * float(f[2])
		var gt := mi.global_transform
		var c := gt * ((lo + hi) * 0.5)
		var n := (gt.basis * nsum).normalized()
		n.y = 0.0 if absf(n.y) < 0.9 else n.y
		n = n.normalized()
		var ext := (gt.basis * (hi - lo)).length()
		var d := maxf(ext * 1.7, 0.6)
		var sides := [["front", n], ["back", -n]]
		if it.size() > 4 and String(it[4]) == "orbit":
			sides = []
			for k in 4: sides.append(["o%d" % k, Vector3(sin(k * PI / 2), 0, cos(k * PI / 2))])
			d = maxf(ext * 0.9, 0.5)
		for side in sides:
			cam.global_position = c + (side[1] as Vector3) * d + Vector3(0, 0.001, 0)
			cam.look_at(c, Vector3.UP)
			for i in 4: await process_frame
			var img := root.get_texture().get_image()
			img.save_png(outdir + "/" + name + "_" + String(side[0]) + ".png")
		print("[SHOT] ", name, " faces ", faces.size())
		holder.queue_free()
		await process_frame
	quit(0)
