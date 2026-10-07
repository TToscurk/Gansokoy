extends SceneTree
## P10 NPC Asset Library 技術 gate（npc_roster.json の全 NPC）——「壊れていない」ことだけを証明する（美術判定ではない）。
##   godot --headless --path . --script res://tools/verify_npc_library.gd                 全 NPC × 11 項
##   godot --headless --path . --script res://tools/verify_npc_library.gd -- --negatives  反向 7 案（各案で狙った項目が FAIL）
##   … -- --only=kozo_m01,chaya_f01
##   godot --headless --path . --script res://tools/verify_npc_library.gd -- --seal       封存（ART_APPROVED 2026-10-06）：雜湊・原素材・正式パラメータ・竄改反向
## 真の FAIL は exit code ≠ 0。反向は「狙った項目が落ちる」なら PASS。

const ROSTER := "res://characters/npc/npc_roster.json"
const MAPS := "res://characters/npc/_shared/npc_skeleton_maps.json"
const PART_NAMES := ["NPC_Body", "NPC_Hair"]
const FEET := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]
const TRI_MIN := 5000
const TRI_MAX := 60000

var fails := 0
var roster: Dictionary
var maps: Dictionary


func check(label: String, ok: bool) -> bool:
	print("[NPCLIB] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
	return ok


func _c(label: String, ok: bool, quiet: bool) -> bool:
	return ok if quiet else check(label, ok)


func _family(id: String) -> Dictionary:
	for k: String in maps["families"]:
		if id in maps["families"][k]["members"]:
			var f: Dictionary = maps["families"][k].duplicate()
			f["key"] = k
			return f
	return {}


func run(n: Dictionary, w: Node3D, quiet := false) -> PackedStringArray:
	var id: String = n["id"]
	var bad := PackedStringArray()
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var mis: Array = w.find_children("NPC_*", "MeshInstance3D", true, false)
	var names := mis.map(func(m: Node) -> String: return String(m.name))
	var parts_ok := sk != null and "NPC_Body" in names and names.all(func(p: String) -> bool: return p in PART_NAMES) \
		and mis.all(func(m: MeshInstance3D) -> bool: return m.skin != null and m.get_node_or_null(m.skeleton) == sk)
	if not _c("%s 部位 %s が同じ GeneralSkeleton に skin" % [id, str(names)], parts_ok, quiet):
		bad.append("parts")
	# 骨格 mapping：family の BoneMap の全割当が GeneralSkeleton に存在し、profile の親子（間の非 profile 骨は飛ばす）と一致
	var fam := _family(id)
	var bm := load("res://characters/npc/_shared/%s.tres" % fam.get("bone_map", "?")) as BoneMap if fam else null
	var prof := SkeletonProfileHumanoid.new()
	var miss := []
	var wrong_parent := []
	var mapped := 0
	if sk != null and bm != null:
		for i in prof.bone_size:
			var pb := prof.get_bone_name(i)
			if bm.get_skeleton_bone_name(pb) == &"":
				continue
			mapped += 1
			var bi := sk.find_bone(pb)
			if bi < 0:
				miss.append(pb)
				continue
			var want := prof.get_bone_parent(i)
			if want == &"" or bm.get_skeleton_bone_name(want) == &"":
				continue
			var p := sk.get_bone_parent(bi)
			while p >= 0 and prof.find_bone(sk.get_bone_name(p)) < 0:
				p = sk.get_bone_parent(p)
			if p < 0 or sk.get_bone_name(p) != want:
				wrong_parent.append("%s→%s" % [pb, sk.get_bone_name(p) if p >= 0 else "-"])
	var map_ok := sk != null and bm != null and mapped >= 50 and miss.is_empty() and wrong_parent.is_empty()
	if not _c("%s skeleton mapping：family %s／%s・割当 %d・欠 %s・親違い %s" % [id, fam.get("key", "?"), fam.get("bone_map", "?"), mapped, str(miss), str(wrong_parent)], map_ok, quiet):
		bad.append("mapping")
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips := ap.get_animation_list() if ap else PackedStringArray()
	var loop_ok := ap != null and clips.size() == 2 and "idle" in clips and "walk" in clips \
		and ap.get_animation("idle").loop_mode == Animation.LOOP_LINEAR and ap.get_animation("walk").loop_mode == Animation.LOOP_LINEAR
	var want_idle: String = n.get("idle_clip", "")
	var want_walk: String = n.get("walk_clip", "")
	var sel_ok := want_idle != "" and want_walk != "" and String(w.get("idle_clip")) == want_idle and String(w.get("walk_clip")) == want_walk
	if not _c("%s clip＝idle・walk の 2 本・ループ・roster の選定（%s／%s）と一致" % [id, want_idle.get_file(), want_walk.get_file()], loop_ok and sel_ok, quiet):
		bad.append("clips")
	var tris := 0
	var mats := {}
	var albedo_ok := true
	var emis := false
	for m: MeshInstance3D in mis:
		var am := m.mesh as ArrayMesh
		for i in am.get_surface_count():
			tris += am.surface_get_array_index_len(i) / 3
			var mt := am.surface_get_material(i) as StandardMaterial3D
			mats[mt.resource_path if mt else "null"] = true
			albedo_ok = albedo_ok and mt != null and mt.albedo_texture != null
			emis = emis or (mt != null and mt.emission_enabled)
	if not _c("%s 三角 %d（%d–%d）" % [id, tris, TRI_MIN, TRI_MAX], tris >= TRI_MIN and tris <= TRI_MAX, quiet):
		bad.append("tris")
	var mat_ok := albedo_ok and not emis and mats.keys().all(func(k: String) -> bool: return k.begins_with("res://characters/npc/%s/m_" % id) and k.ends_with(".tres"))
	if not _c("%s 材質＝外部 m_*.tres・albedo あり・emission なし（%s）" % [id, str(mats.keys().map(func(k: String) -> String: return k.get_file()))], mat_ok, quiet):
		bad.append("materials")
	var top := -INF
	var bottom := INF
	for m: MeshInstance3D in mis:
		var ab: AABB = m.global_transform * m.get_aabb()
		top = maxf(top, ab.end.y)
		bottom = minf(bottom, ab.position.y)
	var h: float = n["height"]
	if not _c("%s 身長（rest、頂点まで）%.3f m（指定 %.2f ±0.005）・足裏 %.4f" % [id, top - bottom, h, bottom], absf(top - bottom - h) <= 0.005 and absf(bottom) < 0.005, quiet):
		bad.append("height")
	var g_err := 0.0
	var stretch := -INF
	var shrink := INF
	var drift := {"idle": 0.0, "walk": 0.0}
	if sk != null and loop_ok:
		var rest := {}
		for b in FEET + ["Head"]:
			rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin.y
		ap.speed_scale = 0.0
		for c in ["idle", "walk"]:
			ap.play(c)
			var t := 0.0
			var xz := []
			while t < ap.get_animation(c).length:
				ap.seek(t, true)
				var lo := INF
				for b in FEET:
					lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
				g_err = maxf(g_err, absf(lo))
				var hy := sk.get_bone_global_pose(sk.find_bone("Head")).origin.y - float(rest["Head"])
				stretch = maxf(stretch, hy)
				shrink = minf(shrink, hy)
				var hp := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
				xz.append(Vector2(hp.x, hp.z))
				t += 0.2
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for p: Vector2 in xz:
				mn = mn.min(p)
				mx = mx.max(p)
			drift[c] = (mx - mn).length()
	if not _c("%s idle／walk 全フレーム接地：最も低い足骨の rest 差 最大 %.3f m（≤ 0.015）" % [id, g_err], loop_ok and g_err <= 0.015, quiet):
		bad.append("ground")
	var s_hi := 0.03 * h / 1.68
	var s_lo := -0.08 * h / 1.68
	if not _c("%s 首・胴が伸びない：Head 骨の rest 差 %.3f〜%.3f m（%.3f〜+%.3f）" % [id, shrink, stretch, s_lo, s_hi], loop_ok and stretch <= s_hi and shrink >= s_lo, quiet):
		bad.append("stretch")
	if not _c("%s root motion なし（in place）：Hips 水平移動幅 idle %.3f m（≤ 0.15）・walk %.3f m（≤ 0.10）" % [id, drift["idle"], drift["walk"]], loop_ok and drift["idle"] <= 0.15 and drift["walk"] <= 0.10, quiet):
		bad.append("rootmotion")
	return bad


func _fresh(id: String) -> Node3D:
	var w: Node3D = (load("res://characters/npc/%s/%s.tscn" % [id, id]) as PackedScene).instantiate()
	w.set("frozen", true)
	w.set("start_time", 0.0)
	root.add_child(w)
	return w


func _own_clip(w: Node3D, clip: String) -> Animation:
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	var an := lib.get_animation(clip).duplicate(true) as Animation
	lib.add_animation(clip, an)
	return an


func _init() -> void:
	roster = JSON.parse_string(FileAccess.get_file_as_string(ROSTER))
	maps = JSON.parse_string(FileAccess.get_file_as_string(MAPS))
	if "--seal" in OS.get_cmdline_user_args():
		quit(_seal())
		return
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = Array(a.trim_prefix("--only=").split(","))
	var npcs: Array = roster["npcs"].filter(func(n: Dictionary) -> bool: return only.is_empty() or n["id"] in only)
	if "--negatives" in OS.get_cmdline_user_args():
		var n0: Dictionary = npcs[0]
		var cases := {
			"part_missing": ["parts", func(w: Node3D) -> void: w.find_child("NPC_Body", true, false).free()],
			"scaled_105": ["height", func(w: Node3D) -> void: w.scale = Vector3.ONE * 1.05],
			"neck_stretch": ["stretch", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				for c in ["idle", "walk"]:
					var an := _own_clip(w, c)
					var tr := an.add_track(Animation.TYPE_POSITION_3D)
					an.track_set_path(tr, NodePath("%GeneralSkeleton:Neck"))
					an.position_track_insert_key(tr, 0.0, sk.get_bone_rest(sk.find_bone("Neck")).origin + Vector3(0, 0.15, 0))],
			"float_10cm": ["ground", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				var an := _own_clip(w, "walk")
				var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
				for k in an.track_get_key_count(tr):
					an.track_set_key_value(tr, k, (an.track_get_key_value(tr, k) as Vector3) + Vector3(0, 0.1 / sk.motion_scale, 0))],
			"root_drift": ["rootmotion", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				var an := _own_clip(w, "walk")
				var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
				for k in an.track_get_key_count(tr):
					var tt := an.track_get_key_time(tr, k) / an.length
					an.track_set_key_value(tr, k, (an.track_get_key_value(tr, k) as Vector3) + Vector3(0, 0, 1.0 * tt / sk.motion_scale))],
			"wrong_clip": ["clips", func(w: Node3D) -> void: w.set("walk_clip", "res://characters/npc/_shared/anim/mixamo/walk_standard_a030_grounded.res")],
			"bone_unmapped": ["mapping", func(w: Node3D) -> void:
				var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
				sk.set_bone_name(sk.find_bone("LeftLowerArm"), "mixamorig_LeftForeArm")],
		}
		for nm: String in cases:
			var w := _fresh(n0["id"])
			await process_frame
			(cases[nm][1] as Callable).call(w)
			await process_frame
			var bad := run(n0, w, true)
			check("反向 %s（%s）→ 「%s」が FAIL（落ちた項目 %s）" % [nm, n0["id"], cases[nm][0], str(bad)], cases[nm][0] in bad)
			w.queue_free()
			await process_frame
		print("[NPCLIB] 結果：%d 項失敗（negatives）" % fails)
		quit(fails)
		return
	for n: Dictionary in npcs:
		var w := _fresh(n["id"])
		await process_frame
		run(n, w)
		w.queue_free()
		var w2: Node3D = (load("res://characters/npc/%s/%s.tscn" % [n["id"], n["id"]]) as PackedScene).instantiate()
		root.add_child(w2)
		await process_frame
		var ap := w2.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check("%s.tscn（npc_visual.gd）が既定で idle を再生" % n["id"], ap != null and ap.current_animation == "idle" and ap.is_playing())
		w2.queue_free()
		await process_frame
	print("[NPCLIB] 結果：%d 項失敗（%d NPC）" % [fails, npcs.size()])
	quit(fails)


## ---- 封存（P10 NPC Asset Library ART_APPROVED 2026-10-06）----
const SEAL := "res://data/village_v2_p10_npclib_seal.json"


func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p10_npc/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence", "sources"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = k if grp == "sources" else ((repo + k) if grp == "frozen" else (docs + k))
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	# characters/npc/ に封存外のファイルが増えていない（.uid・Godot の自動生成は除く）
	var listed := {}
	for k: String in seal["frozen"]:
		listed[k] = true
	for f in _walk(repo + "godot/characters/npc"):
		var k := f.trim_prefix(repo)
		if not listed.has(k) and not k.ends_with(".uid"):
			bad.append("%s は封存外の新しいファイル" % k)
	return bad


func _walk(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.include_hidden = true
	for f in da.get_files():
		out.append(dir + "/" + f)
	for sd in da.get_directories():
		out.append_array(_walk(dir + "/" + sd))
	return out


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	check("封存 status＝ART_APPROVED（%s、%s）" % [seal.get("approved_by", "?"), seal.get("approved_at", "?")], seal.get("status", "") == "ART_APPROVED")
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size() + seal["sources"].size()
	check("P10 NPC Asset Library 封存 %d 檔雜湊一致（凍結 %d、原素材 %d、ART_REVIEW %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(), seal["sources"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	# 正式パラメータ：roster と封存の値が一致（身長・clip・arm-space・UV 復元・前掛け）
	var by := {}
	for e: Dictionary in seal["npcs"]:
		by[e["id"]] = e
	var pbad := []
	for nn: Dictionary in roster["npcs"]:
		var e: Dictionary = by.get(nn["id"], {})
		if e.is_empty() or absf(float(e["height_m"]) - float(nn["height"])) > 1e-6 or String(e["walk"]["clip"]) != String(nn["walk_clip"]) \
				or String(e["idle"]["clip"]) != String(nn["idle_clip"]) or absf(float(e["walk"]["arm_space"]) - float(nn["walk_arm_space"])) > 1e-6:
			pbad.append(nn["id"])
	var nunoya: Dictionary = by.get("nunoya_f01", {})
	var shufu: Dictionary = by.get("shufu_f01", {})
	var params_ok: bool = pbad.is_empty() and nunoya.has("uv_restoration") and int(nunoya.get("texture_max_size", 0)) == 2048 \
		and shufu.has("apron_fix") and absf(float(shufu["apron_fix"]["params"]["offset_m"]) - 0.04) < 1e-9
	check("正式パラメータ：roster＝封存（身長・idle／walk clip・arm-space %d 体、布料老闆娘 UV 復元＋runtime 2048、主婦 apron +4.0 cm；違い %s）" % [roster["npcs"].size(), str(pbad)], params_ok)
	# 貼圖 import＝正式 runtime 状態（VRAM 圧縮＋mipmap；reseal 2026-10-06）。上限は roster の texture_max_size
	var ibad := []
	var n_imp := 0
	for nn: Dictionary in roster["npcs"] + [{"id": "chonin_m01"}]:
		var lim := int(nn.get("texture_max_size", 0))
		var td := "res://characters/npc/%s/tex/" % nn["id"]
		for f in DirAccess.get_files_at(td):
			if not f.ends_with(".import"):
				continue
			n_imp += 1
			var s := FileAccess.get_file_as_string(td + f)
			if not ("compress/mode=2" in s and "mipmaps/generate=true" in s and ("process/size_limit=%d" % lim) in s):
				ibad.append(f)
	check("貼圖 import＝VRAM 圧縮＋mipmap、上限＝roster（%d 件；布料老闆娘 2048；違い %s）" % [n_imp, str(ibad)], ibad.is_empty() and n_imp >= 13)
	# 竄改反向：凍結の 1 件を書き換えた封存なら不一致が出る
	var neg := seal.duplicate(true)
	var k0: String = neg["frozen"].keys()[0]
	neg["frozen"][k0] = "0".repeat(64)
	check("反向：凍結ファイル 1 件の雜湊を偽ると封存不一致になる（%s）" % k0, not _seal_mismatch(neg).is_empty())
	print("[NPCLIB] 結果：%d 項失敗（seal）" % fails)
	return fails
