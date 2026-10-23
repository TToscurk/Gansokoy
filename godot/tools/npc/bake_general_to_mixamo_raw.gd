extends SceneTree
## 把 GeneralSkeleton（重定向後）的動作烘成「未重定向的 mixamorig 骨架」角色可直接播的動作（目前給小鈴：kosuzu.glb 內建骨架）。
## 做法＝世界旋轉差量（保留 twist）：D = G_src(t)·G_src(rest)⁻¹，轉到目標骨架空間（C＝雙方「左・上・前」座標系），G_tgt(t) = C·D·C⁻¹·G_tgt(rest)；
## Hips 位移依髖高比例縮放；最後逐 key 依目標骨架腳骨接地（同 tools/build_npc_anim_grounded.gd）。
## godot --headless --path godot -s res://tools/npc/bake_general_to_mixamo_raw.gd -- --src=res://characters/marisa/marisa.tscn \
##     --dst=res://characters/kosuzu/kosuzu.tscn --map=res://characters/npc/_shared/npc_tripo_65_map.tres --out=res://characters/kosuzu/anim <clip.res> ...
## 輸出 <out>/<clip 檔名去掉 _grounded>_kz.res（軌道路徑 Armature/Skeleton3D:<骨名>，與 kosuzu.glb 內建動作相同）。
var src_path := "res://characters/marisa/marisa.tscn"
var dst_path := "res://characters/kosuzu/kosuzu.tscn"
var map_path := "res://characters/npc/_shared/npc_tripo_65_map.tres"
var out_dir := "res://characters/kosuzu/anim"
var clips := []
const FEET := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="): src_path = a.substr(6)
		elif a.begins_with("--dst="): dst_path = a.substr(6)
		elif a.begins_with("--map="): map_path = a.substr(6)
		elif a.begins_with("--out="): out_dir = a.substr(6)
		else: clips.append(a)
	_run.call_deferred()


func _frame(sk: Skeleton3D, hips: int, head: int, la: int, ra: int) -> Basis:
	var up := (sk.get_bone_global_rest(head).origin - sk.get_bone_global_rest(hips).origin).normalized()
	var left := sk.get_bone_global_rest(la).origin - sk.get_bone_global_rest(ra).origin
	left = (left - up * left.dot(up)).normalized()
	return Basis(left, up, left.cross(up))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var bm: BoneMap = load(map_path)
	var s_npc: Node3D = (load(src_path) as PackedScene).instantiate(); s_npc.set("frozen", true); root.add_child(s_npc)
	var d_npc: Node3D = (load(dst_path) as PackedScene).instantiate(); d_npc.set("frozen", true); root.add_child(d_npc)
	await process_frame
	await process_frame
	var ss := s_npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var ts: Skeleton3D = d_npc.find_children("*", "Skeleton3D", true, false)[0]
	var sap: AnimationPlayer = s_npc.get("player")
	var tap: AnimationPlayer = d_npc.get("player")
	var tpath := String(tap.get_node(tap.root_node).get_path_to(ts))
	# 對應：profile 骨名（= GeneralSkeleton 骨名）→ 目標骨架索引
	var pairs := []   # [src_idx, tgt_idx]
	var tmap := {}
	for i in bm.profile.bone_size:
		var pn := bm.profile.get_bone_name(i)
		var tn := bm.get_skeleton_bone_name(pn)
		var si := ss.find_bone(pn); var ti := ts.find_bone(tn)
		if si >= 0 and ti >= 0:
			pairs.append([si, ti]); tmap[ti] = si
	var C := _frame(ts, ts.find_bone(bm.get_skeleton_bone_name("Hips")), ts.find_bone(bm.get_skeleton_bone_name("Head")),
		ts.find_bone(bm.get_skeleton_bone_name("LeftUpperArm")), ts.find_bone(bm.get_skeleton_bone_name("RightUpperArm"))) \
		* _frame(ss, ss.find_bone("Hips"), ss.find_bone("Head"), ss.find_bone("LeftUpperArm"), ss.find_bone("RightUpperArm")).transposed()
	var s_hips := ss.find_bone("Hips"); var t_hips := ts.find_bone(bm.get_skeleton_bone_name("Hips"))
	var k_h := ts.get_bone_global_rest(t_hips).origin.y / ss.get_bone_global_rest(s_hips).origin.y
	var order := range(ts.get_bone_count())   # Godot 骨架索引父先子後
	var slib := sap.get_animation_library(&""); var tlib := tap.get_animation_library(&"")
	var frest := {}
	for f in FEET:
		var fi := ts.find_bone(bm.get_skeleton_bone_name(f))
		if fi >= 0: frest[fi] = ts.get_bone_global_rest(fi).origin.y
	var n := 0
	for c: String in clips:
		var src: Animation = load(c)
		slib.add_animation(&"__src", src)
		sap.play(&"__src"); sap.speed_scale = 0.0
		var L := src.length
		var nk := int(round(L * 30.0)) + 1
		var an := Animation.new(); an.length = L; an.loop_mode = Animation.LOOP_LINEAR
		var rt := {}
		for p in pairs:
			var tr := an.add_track(Animation.TYPE_ROTATION_3D); an.track_set_path(tr, NodePath("%s:%s" % [tpath, ts.get_bone_name(p[1])])); rt[p[1]] = tr
		var pt := an.add_track(Animation.TYPE_POSITION_3D); an.track_set_path(pt, NodePath("%s:%s" % [tpath, ts.get_bone_name(t_hips)]))
		var hips_rest_s := ss.get_bone_global_rest(s_hips).origin
		for k in nk:
			var t := minf(L * k / float(nk - 1), L)
			sap.seek(t, true)
			var G := {}
			for ti in order:
				var par := ts.get_bone_parent(ti)
				var gp: Basis = G[par] if par >= 0 else Basis()
				var g: Basis
				if tmap.has(ti):
					var si: int = tmap[ti]
					var D := ss.get_bone_global_pose(si).basis.orthonormalized() * ss.get_bone_global_rest(si).basis.orthonormalized().transposed()
					g = (C * D * C.transposed()) * ts.get_bone_global_rest(ti).basis.orthonormalized()
					an.rotation_track_insert_key(rt[ti], t, (gp.transposed() * g).get_rotation_quaternion())
				else:
					g = gp * ts.get_bone_rest(ti).basis.orthonormalized()
				G[ti] = g
			var dp := ss.get_bone_global_pose(s_hips).origin - hips_rest_s
			an.position_track_insert_key(pt, t, ts.get_bone_rest(t_hips).origin + C * dp * k_h)
		# 接地：在目標骨架上播，量最低腳骨相對 rest 的高度，逐 key 修 Hips 高
		tlib.add_animation(&"__bake", an)
		tap.play(&"__bake"); tap.speed_scale = 0.0
		var lo_b := [INF, -INF]; var fixes := []
		for k in an.track_get_key_count(pt):
			tap.seek(an.track_get_key_time(pt, k), true)
			var lo := INF
			for fi in frest: lo = minf(lo, ts.get_bone_global_pose(fi).origin.y - float(frest[fi]))
			fixes.append(lo); lo_b[0] = minf(lo_b[0], lo); lo_b[1] = maxf(lo_b[1], lo)
		for k in fixes.size():
			an.track_set_key_value(pt, k, an.track_get_key_value(pt, k) - Vector3(0, fixes[k], 0))
		tlib.remove_animation(&"__bake")
		slib.remove_animation(&"__src")
		var nm := c.get_file().get_basename().replace("_grounded", "")
		an.resource_name = nm
		var out := "%s/%s_kz.res" % [out_dir, nm]
		var err := ResourceSaver.save(an, out)
		print("[BAKE] %s %s keys %d tracks %d 接地修正 %.3f〜%.3f → %s" % ["PASS" if err == OK else "FAIL", nm, nk, an.get_track_count(), lo_b[0], lo_b[1], out])
		n += 1
	quit(0)
