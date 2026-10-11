extends SceneTree
## P11 R2C A（只讀、headless）：道路修正後の河岸 Kit 重排 vs 場景に烘焙済みの Riverbank を区塊ごとに比較。
## 変わる区塊・件数・碰撞 shape だけを列挙（書き込みなし）。--apply で変わった区塊の mesh .res だけ上書きし、
## 変わった区塊の Collision と meta を tscn 用に JSON 出力（tscn の編集は別手順）。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

func _init() -> void:
	_run.call_deferred()

func _arr_sig(m: Mesh) -> String:
	if m == null:
		return "null"
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		h.update(var_to_bytes(a[Mesh.ARRAY_VERTEX]))
		h.update(var_to_bytes(a[Mesh.ARRAY_INDEX]))
		h.update(var_to_bytes(a[Mesh.ARRAY_COLOR]))
	return h.finish().hex_encode().left(16)

func _shapes(cn: Node) -> Array:
	var out := []
	var sb := cn.get_node_or_null("Collision")
	if sb == null:
		return out
	for c in sb.get_children():
		var cs := c as CollisionShape3D
		var o := cs.transform.origin
		out.append("%s|%.3f,%.3f,%.3f|%s" % [cs.name, o.x, o.y, o.z, str((cs.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.001))])
	return out

func _run() -> void:
	var apply := "--apply" in OS.get_cmdline_user_args()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var old := v.get_node("Riverbank")
	var oldc := {}
	for cn in old.get_children():
		oldc[String(cn.name)] = {"n": int(cn.get_meta("items", 0)), "l0": _arr_sig((cn.get_node("LOD0") as MeshInstance3D).mesh),
			"l1": _arr_sig((cn.get_node("LOD1") as MeshInstance3D).mesh), "sh": _shapes(cn),
			"p0": (cn.get_node("LOD0") as MeshInstance3D).mesh.resource_path, "p1": (cn.get_node("LOD1") as MeshInstance3D).mesh.resource_path}
	v.remove_child(old)
	var P: Dictionary = RLib.plan(v, L)
	var rb := RLib.bake(v, P["items"], RLib.load_lib())
	var changed := []
	var out := {"chunks": {}, "items": int(rb.get_meta("items")), "lod0_tris": int(rb.get_meta("lod0_tris")), "lod1_tris": int(rb.get_meta("lod1_tris"))}
	for cn in rb.get_children():
		var k := String(cn.name)
		var nw := {"n": int(cn.get_meta("items", 0)), "l0": _arr_sig((cn.get_node("LOD0") as MeshInstance3D).mesh),
			"l1": _arr_sig((cn.get_node("LOD1") as MeshInstance3D).mesh), "sh": _shapes(cn)}
		if not oldc.has(k):
			print("[RBD] 新区塊 %s n %d" % [k, nw.n])
			changed.append(k)
			continue
		var o: Dictionary = oldc[k]
		var dm: bool = o.l0 != nw.l0 or o.l1 != nw.l1
		var ds: bool = o.sh != nw.sh
		if o.n != nw.n or dm or ds:
			changed.append(k)
			print("[RBD] 変化 %s  件 %d→%d  mesh %s  shape %s（%d→%d）" % [k, o.n, nw.n, dm, ds, (o.sh as Array).size(), (nw.sh as Array).size()])
			if ds:
				for s in nw.sh:
					if not s in o.sh:
						print("[RBD]    + ", s)
				for s in o.sh:
					if not s in nw.sh:
						print("[RBD]    - ", s)
			out["chunks"][k] = {"items": nw.n, "shapes_changed": ds}
			if apply and dm:
				for lod in 2:
					var mi := cn.get_node("LOD%d" % lod) as MeshInstance3D
					var path: String = o["p%d" % lod]
					var err := ResourceSaver.save(mi.mesh, path)
					print("[RBD]    保存 %s err=%d" % [path, err])
	for k in oldc:
		if rb.get_node_or_null(k) == null:
			print("[RBD] 消えた区塊 ", k)
			changed.append(k)
	print("[RBD] 件数 %d（場景 %d）LOD0 %d LOD1 %d  変化区塊 %d/%d：%s" % [out.items, int(old.get_meta("items")), out.lod0_tris, out.lod1_tris, changed.size(), oldc.size(), str(changed)])
	var f := FileAccess.open("user://p11r2c_riverbank_diff.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	old.free()
	quit(0)
