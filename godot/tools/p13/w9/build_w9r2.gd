extends SceneTree
## P13 W9 R2：bake（overlay 場景を作る）→ 保存 → 掛載（attach）。生成器が source of truth。
##   godot --headless --path godot --script res://tools/p13/w9/build_w9r2.gd              （bake）
##   godot --headless --path godot --script res://tools/p13/w9/build_w9r2.gd -- --attach  （village_v2.tscn へ掛載・重複なし）
## MultiMesh なし → headless 可。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--attach" in OS.get_cmdline_user_args():
		quit(_attach())
		return
	var v: Node3D = (load(L.SCENE) as PackedScene).instantiate()
	var own := v.get_node_or_null(L.NODE_NAME)
	if own:
		v.remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var ov := Node3D.new()
	ov.name = L.NODE_NAME
	ov.set_script(load(L.SCRIPT))
	var vinv := v.global_transform.affine_inverse()
	var meta := JSON.parse_string(FileAccess.get_file_as_string(L.META)) as Dictionary
	var nposts := 0
	var fails := 0
	var tris := 0
	for id: String in L.SPECS:
		var sp: Dictionary = L.SPECS[id]
		var body := v.get_node_or_null(NodePath(sp["path"])) as Node3D
		if body == null:
			printerr("[W9R2B] FAIL 找不到 body %s" % sp["path"])
			fails += 1
			continue
		var n := Node3D.new()
		n.name = id
		n.transform = vinv * body.global_transform
		n.set_meta("body_path", sp["path"])
		n.set_meta("hide0", L.hide_prefixes(id, 0))
		n.set_meta("hide12", L.hide_prefixes(id, 1))
		ov.add_child(n)
		var posts: Array = (meta.get("posts", {}) as Dictionary).get(id, [])
		if not posts.is_empty():
			# 庇柱・玄関柱の碰撞：building body と同じ layer／mask の StaticBody3D（Posts）＋柱ごとの BoxShape3D
			var sb := StaticBody3D.new()
			sb.name = "Posts"
			sb.collision_layer = int((body as CollisionObject3D).collision_layer)
			sb.collision_mask = int((body as CollisionObject3D).collision_mask)
			for i in posts.size():
				var pd: Dictionary = posts[i]
				var half := maxf(float(pd["w"]) / 2.0 + L.POST_PAD, 0.125)       # 礎石（±0.12）まで覆う
				var bs := BoxShape3D.new()
				bs.size = Vector3(2.0 * half, float(pd["top"]), 2.0 * half)
				var cs := CollisionShape3D.new()
				cs.name = "Post%d" % i
				cs.shape = bs
				cs.position = Vector3(float(pd["x"]), float(pd["top"]) / 2.0, float(pd["z"]))
				sb.add_child(cs)
				nposts += 1
			n.add_child(sb)
		for lod in 2:
			var mp: String = L.MESH_DIR + "%s_L%d.res" % [id, lod]
			var mesh := load(mp) as Mesh
			if mesh == null:
				printerr("[W9R2B] FAIL メッシュ無し %s" % mp)
				fails += 1
				continue
			var mi := MeshInstance3D.new()
			mi.name = "L%d" % lod
			mi.mesh = mesh
			var b := float(L.LOD_RANGES[lod])
			var e := float(L.LOD_RANGES[lod + 1])
			mi.visibility_range_begin = b
			mi.visibility_range_begin_margin = L.LOD_MARGIN if b > 0.0 else 0.0
			mi.visibility_range_end = e
			mi.visibility_range_end_margin = L.LOD_MARGIN
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			n.add_child(mi)
			if lod == 0:
				for si in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(si)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					tris += idx.size() / 3
		print("[W9R2B] %s  origin=%s" % [id, n.position])
	for c in ov.get_children():
		_own(c, ov)
	var ps := PackedScene.new()
	ps.pack(ov)
	var err := ResourceSaver.save(ps, L.OUTPUT)
	print("[W9R2B] 保存 %s：%s・建築 %d・LOD0 三角面 %d・庇柱碰撞 %d・失敗 %d" % [L.OUTPUT, error_string(err), ov.get_child_count(), tris, nposts, fails])
	quit(0 if (err == OK and fails == 0) else 1)


func _own(n: Node, owner_: Node) -> void:
	n.owner = owner_
	for c in n.get_children():
		_own(c, owner_)


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(L.SCENE)
	if not FileAccess.file_exists(L.OUTPUT):
		printerr("[W9R2B] 找不到 %s（先に bake）" % L.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9r2_arch\")]" % L.NODE_NAME
	if txt.contains(line):
		print("[W9R2B] attach：已掛 root/%s（不重複、不寫場景）" % L.NODE_NAME)
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var after := ""
	for l: String in txt.split(nl):
		if l.begins_with("[node name=\"%s\" parent=\".\"" % L.AFTER):
			after = l
	if after == "":
		printerr("[W9R2B] 找不到 root/%s" % L.AFTER)
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(after)
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9r2_arch\"]" % L.OUTPUT)
	var f := FileAccess.open(L.SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[W9R2B] attach：加 root/%s（%s の次）→ %s（+%d 行）" % [L.NODE_NAME, L.AFTER, L.SCENE, out.size() - lines.size()])
	return 0
