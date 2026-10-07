extends SceneTree
## NPC basket rigidity probe (read-only).
## Compares the pre-fix GLB (copy outside the project, loaded with GLTFDocument) with the current imported NPC
## on the basket set = vertices whose weights changed AND now sit ≥ 0.999 on the roster basket_fix bone.
## Vertices are matched by rest position (weights changed only), bones by name.
## For idle + walk, every 30 fps frame: CPU-skin the set with old and new weights, fit the best rigid transform
## to the rest shape (Kabsch / polar), report RMS / max residual (= bending / twisting / stretching of the basket).
## Usage: godot --headless --path godot --script res://tools/probe_npc_basket_rigidity.gd -- --old=<dir with old <id>.glb> [--out=<json>]
func _initialize():
	run.call_deferred()

func body_of(root_node: Node) -> MeshInstance3D:
	for mi in root_node.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "NPC_Body": return mi
	return null

func weight_maps(mi: MeshInstance3D) -> Dictionary:
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo = arr[Mesh.ARRAY_BONES]; var we = arr[Mesh.ARRAY_WEIGHTS]
	var st: int = bo.size() / v.size()
	var names := []
	for b in mi.skin.get_bind_count(): names.append(b)   # keyed by bind index: the old (raw glTF) and new (retargeted) skins share the joint order
	var maps := []
	for i in v.size():
		var d := {}
		for k in st:
			var w: float = we[i * st + k]
			if w > 1e-4: d[names[int(bo[i * st + k])]] = float(d.get(names[int(bo[i * st + k])], 0.0)) + w
		maps.append(d)
	return {"verts": v, "maps": maps}

func key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 20000.0), roundi(p.y * 20000.0), roundi(p.z * 20000.0)]

func skin_pts(sk: Skeleton3D, mi: MeshInstance3D, verts: PackedVector3Array, idx: Array, maps: Array) -> PackedVector3Array:
	var bind := {}
	for b in mi.skin.get_bind_count():
		var bi := mi.skin.get_bind_bone(b)
		if bi < 0: bi = sk.find_bone(mi.skin.get_bind_name(b))
		bind[b] = sk.get_bone_global_pose(bi) * mi.skin.get_bind_pose(b)
	var out := PackedVector3Array(); out.resize(idx.size())
	for j in idx.size():
		var i: int = idx[j]
		var p := Vector3.ZERO
		var m: Dictionary = maps[j]
		for nm in m: p += float(m[nm]) * (bind[nm] * verts[i])
		out[j] = p
	return out

func rigid_residual(a: PackedVector3Array, b: PackedVector3Array) -> Vector2:
	var ca := Vector3.ZERO; var cb := Vector3.ZERO
	for i in a.size(): ca += a[i]; cb += b[i]
	ca /= a.size(); cb /= b.size()
	var m := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for i in a.size():
		var p := a[i] - ca; var q := b[i] - cb
		m.x += q * p.x; m.y += q * p.y; m.z += q * p.z
	var r := m
	for it in 40:
		if absf(r.determinant()) < 1e-14: break
		var it_ := r.inverse().transposed()
		r = Basis((r.x + it_.x) * 0.5, (r.y + it_.y) * 0.5, (r.z + it_.z) * 0.5)
	var ss := 0.0; var mx := 0.0
	for i in a.size():
		var d := (r * (a[i] - ca) + cb).distance_to(b[i])
		ss += d * d; mx = maxf(mx, d)
	return Vector2(sqrt(ss / a.size()), mx)

func run():
	var old_dir := ""; var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--old="): old_dir = a.trim_prefix("--old=")
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://characters/npc/npc_roster.json"))
	var res := {}
	for n in roster.npcs:
		if not n.has("basket_fix"): continue
		var cid: String = n.id
		var bone: String = n.basket_fix.get("bone", "Spine2")
		var doc := GLTFDocument.new(); var stt := GLTFState.new()
		if doc.append_from_file(old_dir + "/" + cid + ".glb", stt) != OK: res[cid] = {"error": "old glb"}; continue
		var old_scene := doc.generate_scene(stt)
		var old_w := weight_maps(body_of(old_scene))
		var omap := {}
		for i in old_w.verts.size(): omap[key(old_w.verts[i])] = i
		var npc: Node3D = load("res://characters/npc/%s/%s.tscn" % [cid, cid]).instantiate()
		root.add_child(npc)
		await process_frame
		var sk: Skeleton3D = npc.find_child("GeneralSkeleton", true, false)
		var mi := body_of(npc)
		var new_w := weight_maps(mi)
		var idx := []; var om := []; var nm := []; var unmatched := 0
		for i in new_w.verts.size():
			var d: Dictionary = new_w.maps[i]
			var tgt := -1
			for b in d: if float(d[b]) >= 0.999: tgt = b
			if tgt < 0: continue
			var k := key(new_w.verts[i])
			if not omap.has(k): unmatched += 1; continue
			var od: Dictionary = old_w.maps[omap[k]]
			if od.size() == 1 and od.has(tgt): continue   # already rigid before the fix: not part of the change
			idx.append(i); om.append(od); nm.append(d)
		var tb := {}
		for d in nm: for b in d: tb[String(mi.skin.get_bind_name(b))] = int(tb.get(String(mi.skin.get_bind_name(b)), 0)) + 1
		# keep only the basket bone (the bind most vertices were made rigid to); stray single-bone vertices elsewhere
		# (import weight pruning on head / legs) are not part of the basket
		var cnt := {}
		for d in nm: for b in d: cnt[b] = int(cnt.get(b, 0)) + 1
		var main_b = cnt.keys()[0]
		for b in cnt: if cnt[b] > cnt[main_b]: main_b = b
		var idx2 := []; var om2 := []; var nm2 := []
		for j in idx.size():
			if (nm[j] as Dictionary).has(main_b): idx2.append(idx[j]); om2.append(om[j]); nm2.append(nm[j])
		idx = idx2; om = om2; nm = nm2
		var row := {"bone": bone, "rigid_to": tb, "basket_verts": idx.size(), "unmatched": unmatched}
		var ap: AnimationPlayer = npc.player
		for slot in ["idle", "walk"]:
			ap.play(StringName(slot)); ap.speed_scale = 0.0
			var an := ap.get_animation(StringName(slot))
			sk.reset_bone_poses()
			var rest := skin_pts(sk, mi, new_w.verts, idx, nm)
			var st := {"old_rms_cm": 0.0, "old_max_cm": 0.0, "new_rms_cm": 0.0, "new_max_cm": 0.0, "frames": 0}
			for f in int(an.length * 30.0):
				ap.seek(f / 30.0, true)
				var ro := rigid_residual(rest, skin_pts(sk, mi, new_w.verts, idx, om))
				var rn := rigid_residual(rest, skin_pts(sk, mi, new_w.verts, idx, nm))
				st.old_rms_cm = maxf(st.old_rms_cm, ro.x * 100); st.old_max_cm = maxf(st.old_max_cm, ro.y * 100)
				st.new_rms_cm = maxf(st.new_rms_cm, rn.x * 100); st.new_max_cm = maxf(st.new_max_cm, rn.y * 100)
				st.frames += 1
			row[slot] = st
		res[cid] = row
		print("[BASKET] ", cid, " ", JSON.stringify(row))
		npc.queue_free(); old_scene.free(); await process_frame
	if out != "": FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(res, "  "))
	quit(0)
