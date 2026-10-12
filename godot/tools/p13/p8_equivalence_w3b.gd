extends SceneTree
## P13 W3B：farmland_p8.scn の再烘焙前後を逐ノード比較（old＝.godot/w3b_backup/farmland_p8_before.scn、new＝gen/farmland_p8.scn）。
##   godot --headless --path . --script res://tools/p13/p8_equivalence_w3b.gd
## 比較：クラス・変換・visible・meta・メッシュ配列（頂点／法線／色／UV／UV2／index の SHA-256）・材質（クラス・shader・全 shader 引数・StandardMaterial の主要値）・
##       可視範囲・影・MultiMesh（instance_count・buffer の SHA-256）・碰撞形（クラス・寸法）・碰撞層。
## 期待される差分は Branches 配下の 土渠メッシュ（頂点色／UV2＋木槽の台の増加）と 水面メッシュ（材質）だけ。それ以外のノードは差分 0。
## 土渠／水面メッシュは「合併の順序が変わる」ため、三角形の位置集合（量子化 1e-4 m）で old ⊂ new（失われた三角形 0）を別途確認する。
const OLD := "res://.godot/w3b_backup/farmland_p8_before.scn"
const NEW := "res://maps/village_v2/gen/farmland_p8.scn"
const BR := "ZoneWorks/ZoneIrrigation/Branches"      # 単体 farmland_p8.scn の root＝FarmlandP8

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _h(v: Variant) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(var_to_bytes(v))
	return hc.finish().hex_encode().substr(0, 16)


func _mat_sig(m: Material) -> String:
	if m == null:
		return "null"
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var d := {}
		if sm.shader:
			for u in sm.shader.get_shader_uniform_list():
				d[u["name"]] = str(sm.get_shader_parameter(u["name"]))
		return "SM|%s|%s" % [sm.shader.resource_path if sm.shader else "-", _h(d)]
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		return "STD|%s|%s|%s|%s|%s|%s" % [s.albedo_color, s.roughness, s.metallic, s.vertex_color_use_as_albedo, s.uv1_triplanar, s.albedo_texture.resource_path if s.albedo_texture else "-"]
	return m.get_class()


func _mesh_sig(mesh: Mesh) -> Dictionary:
	var out := {}
	if mesh == null:
		return out
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		for t in arr.size():
			if arr[t] != null:
				out["s%d.a%d" % [si, t]] = _h(arr[t])
		var m := mesh.surface_get_material(si)
		out["s%d.mat" % si] = _mat_sig(m)
	return out


func _tris(mesh: Mesh) -> Dictionary:
	var d := {}
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		var n: int = (idx as PackedInt32Array).size() if idx != null else vs.size()
		for t in range(0, n, 3):
			var q: Array = []
			for k in 3:
				var v: Vector3 = vs[(idx as PackedInt32Array)[t + k]] if idx != null else vs[t + k]
				q.append("%d,%d,%d" % [roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0)])
			q.sort()
			var key := "|".join(q)
			d[key] = int(d.get(key, 0)) + 1
	return d


func _desc(n: Node) -> Dictionary:
	var d := {"class": n.get_class()}
	var metas := {}
	for k in n.get_meta_list():
		metas[str(k)] = str(n.get_meta(k))
	d["meta"] = _h(metas)
	if n is Node3D:
		d["xf"] = str((n as Node3D).transform)
		d["vis"] = str((n as Node3D).visible)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		d["mesh"] = _mesh_sig(mi.mesh)
		d["mat"] = _mat_sig(mi.material_override)
		d["shadow"] = str(mi.cast_shadow)
		d["vr"] = "%s|%s|%s|%s|%s" % [mi.visibility_range_begin, mi.visibility_range_end, mi.visibility_range_begin_margin, mi.visibility_range_end_margin, mi.visibility_range_fade_mode]
	if n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		d["mm"] = "%d|%s" % [mm.instance_count, _h(mm.buffer)]
		d["mmmesh"] = _mesh_sig(mm.mesh)
		d["vr"] = "%s|%s" % [(n as MultiMeshInstance3D).visibility_range_begin, (n as MultiMeshInstance3D).visibility_range_end]
	if n is CollisionShape3D:
		var sh := (n as CollisionShape3D).shape
		d["shape"] = "%s|%s" % [sh.get_class() if sh else "-", str(sh.get("size")) if sh and sh.get("size") != null else (str(sh.get("radius")) if sh else "-")]
		d["disabled"] = str((n as CollisionShape3D).disabled)
	if n is CollisionObject3D:
		d["layer"] = "%d|%d" % [(n as CollisionObject3D).collision_layer, (n as CollisionObject3D).collision_mask]
	return d


func _collect(root_n: Node) -> Dictionary:
	var out := {}
	var stack: Array = [root_n]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out["." if n == root_n else String(root_n.get_path_to(n))] = n
		for c in n.get_children():
			stack.append(c)
	return out


func _diff_keys(a: Dictionary, b: Dictionary) -> Array:
	var ks: Array = []
	for k in a:
		if not b.has(k) or str(a[k]) != str(b[k]):
			ks.append(k)
	for k in b:
		if not a.has(k):
			ks.append(k)
	return ks


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var po := ResourceLoader.load(OLD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pn := ResourceLoader.load(NEW, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if po == null or pn == null:
		print("[EQ] FAIL 読めない old=%s new=%s" % [po, pn])
		quit(2)
		return
	var ro := po.instantiate()
	var rn := pn.instantiate()
	root.add_child(ro)
	root.add_child(rn)
	await process_frame
	var mo := _collect(ro)
	var mn := _collect(rn)
	var only_old: Array = []
	var only_new: Array = []
	var changed: Array = []
	var same := 0
	var mm_n := 0
	for k in mo:
		if not mn.has(k):
			only_old.append(k)
			continue
		var da := _desc(mo[k])
		var db := _desc(mn[k])
		if (mo[k] is MultiMeshInstance3D):
			mm_n += 1
		var dk := _diff_keys(da, db)
		if dk.is_empty():
			same += 1
		else:
			changed.append({"path": k, "keys": dk, "a": da, "b": db})
	for k in mn:
		if not mo.has(k):
			only_new.append(k)
	print("[EQ] old nodes %d new nodes %d；一致 %d（MultiMesh %d）；差分 %d；old のみ %d；new のみ %d（%.1fs）" % [mo.size(), mn.size(), same, mm_n, changed.size(), only_old.size(), only_new.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	# 差分の分類：期待＝Branches 配下の earth／water のメッシュだけ
	var unexpected := 0
	for c: Dictionary in changed:
		var p: String = c["path"]
		var inbr := p.begins_with(BR + "/")
		var is_mesh := mo[p] is MeshInstance3D
		var sp := String((c["a"].get("mat", "") as String))
		var expected: bool = inbr and is_mesh and (sp.contains("ground.gdshader") or sp.contains("p8_paddy_water.gdshader"))
		print("[EQ]   %s %s keys=%s" % ["期待" if expected else "想定外", p.trim_prefix(BR + "/") if inbr else p, str(c["keys"])])
		if not expected:
			unexpected += 1
	for p: String in only_old:
		print("[EQ]   old のみ（想定外）", p)
	for p: String in only_new:
		print("[EQ]   new のみ（想定外）", p)
	# 土渠／水面メッシュ：土渠＝三角形の位置集合で old ⊂ new（失われた三角形 0）、水面＝頂点 index ごとに y 不変（絞りは x/z だけ動く）
	var tri_fail := 0
	for c: Dictionary in changed:
		var p: String = c["path"]
		if not (p.begins_with(BR + "/") and mo[p] is MeshInstance3D):
			continue
		if String(c["a"].get("mat", "")).contains("p8_paddy_water.gdshader"):
			var va: PackedVector3Array = (mo[p] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var vb: PackedVector3Array = (mn[p] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var ia: PackedInt32Array = (mo[p] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			var ib: PackedInt32Array = (mn[p] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			var same_n := va.size() == vb.size() and ia == ib
			var dy_max := 0.0
			var moved := 0
			var dxz_max := 0.0
			if same_n:
				for i in va.size():
					dy_max = maxf(dy_max, absf(va[i].y - vb[i].y))
					var dxz := Vector2(va[i].x - vb[i].x, va[i].z - vb[i].z).length()
					if dxz > 1e-6:
						moved += 1
						dxz_max = maxf(dxz_max, dxz)
			print("[EQ]   水面 %s：頂点 %d→%d・index 同一 %s；y の最大差 %s m；x/z が動いた頂点 %d（最大 %.3f m）" % [p.trim_prefix(BR + "/"), va.size(), vb.size(), same_n, str(dy_max), moved, dxz_max])
			# 絞りで横にずれた頂点は「水面高程を引く位置（中心線への射影）」がわずかに変わる（実測 0.3 mm）。許容は 1 mm
			if not same_n or dy_max > 1e-3:
				tri_fail += 1
			continue
		var ta := _tris((mo[p] as MeshInstance3D).mesh)
		var tb := _tris((mn[p] as MeshInstance3D).mesh)
		var lost := 0
		var extra := 0
		for k in ta:
			if int(tb.get(k, 0)) < int(ta[k]):
				lost += int(ta[k]) - int(tb.get(k, 0))
		for k in tb:
			if int(ta.get(k, 0)) < int(tb[k]):
				extra += int(tb[k]) - int(ta.get(k, 0))
		var na := 0
		for k in ta:
			na += int(ta[k])
		var nb := 0
		for k in tb:
			nb += int(tb[k])
		print("[EQ]   三角形 %s：old %d → new %d；失われた位置 %d；増えた位置 %d" % [p.trim_prefix(BR + "/"), na, nb, lost, extra])
		if lost > 0:
			tri_fail += 1
	var ok := unexpected == 0 and only_old.is_empty() and only_new.is_empty() and tri_fail == 0
	print("[EQ] RESULT %s（想定外の差分 %d、old のみ %d、new のみ %d、三角形を失ったメッシュ %d）" % ["PASS" if ok else "FAIL", unexpected, only_old.size(), only_new.size(), tri_fail])
	quit(0 if ok else 1)
