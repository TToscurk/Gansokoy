extends SceneTree
## 量測：畫面上的袴（CPU 重算蒙皮）有多少頂點陷進腿裡（腿＝reimu_colliders.json 的大腿／小腿膠囊，用原始半徑、不加 leg_margin）。
## 陷進腿裡的布＝腿從布穿出來。headless 可跑（只用骨架姿勢＋自己算蒙皮）。基準：--set=springs_enabled:false（裙擺骨固定在靜止姿勢）。
## godot --headless --path godot -s res://tools/reimu/probe_reimu_skirt_clip.gd -- --clip=walk --sec=8 [--set=屬性:值 ...] [--npc=res://characters/marisa/marisa.tscn] [--zmax=0.9]
##   --npc：預設靈夢（碰撞資料取自該角色 Skirt.data_prefix）。--zmax：只量骨架局部 y（公尺）低於此值的裙部頂點（魔理莎的裙與上身同一網格時用來排除上身/袖子）。
var npc: Node3D
var t := 0.0
var sec := 8.0
var clip := "walk"
var sets := {}
var npc_path := "res://characters/reimu/reimu.tscn"
var zmax := 1e9
var mi: MeshInstance3D
var verts := PackedVector3Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var bind_bone := PackedInt32Array()
var caps := []
var samples := []
var worst_frame := -1.0
var frame := 0
var _want := false   # 骨架修改器（彈簧骨）的結果只在 skeleton_updated 裡讀得到，在那裡量
var cage_gap_min := 9.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sec="): sec = float(a.substr(6))
		if a.begins_with("--clip="): clip = a.substr(7)
		if a.begins_with("--npc="): npc_path = a.substr(6)
		if a.begins_with("--zmax="): zmax = float(a.substr(7))
		if a.begins_with("--set="):
			var kv := a.substr(6).split(":"); sets[kv[0]] = str_to_var(kv[1])
	npc = (load(npc_path) as PackedScene).instantiate()
	for k in sets: npc.get_node("Skirt").set(k, sets[k])
	npc.set("animation", StringName(clip))
	root.add_child(npc)

func _setup() -> void:
	var sk = npc.get_node("Skirt")
	var skel: Skeleton3D = sk.skel
	for m in npc.find_children("*", "MeshInstance3D", true, false):
		if m.name == sk.skirt_mesh_name: mi = m
	for s in mi.mesh.get_surface_count():
		var A: Array = mi.mesh.surface_get_arrays(s)
		verts.append_array(A[Mesh.ARRAY_VERTEX]); bones.append_array(A[Mesh.ARRAY_BONES]); weights.append_array(A[Mesh.ARRAY_WEIGHTS])
	var skin: Skin = mi.skin
	for i in skin.get_bind_count():
		var bn := skin.get_bind_name(i)
		bind_bone.append(skel.find_bone(bn) if bn != "" else skin.get_bind_bone(i))
	var cj = JSON.parse_string(FileAccess.get_file_as_string(sk.data_prefix + "_colliders.json"))
	var sc := skel.global_transform.basis.get_scale().x
	for c in cj.capsules: caps.append([sk._bone(c.a), sk._bone(c.b), float(c.r) * sc])
	skel.skeleton_updated.connect(func(): if _want: _want = false; _measure())

func _physics_process(dt: float) -> bool:
	t += dt; frame += 1
	if mi == null and t > 0.1: _setup()
	if t > 2.0 and frame % 6 == 0: _want = true
	if t >= sec:
		samples.sort()
		var mean := 0.0
		for v in samples: mean += v
		mean /= maxf(samples.size(), 1)
		print("CLIP clip=%s sets=%s skirt verts %d ; inside-leg %% mean %.2f p90 %.2f max %.2f (t=%.2f)" % [clip, sets, verts.size(), mean, samples[int(samples.size() * 0.9)], samples[-1], worst_frame])
		quit(0); return true
	return false

func _measure() -> void:
	var skel: Skeleton3D = npc.get_node("Skirt").skel
	var mats := []
	var skin: Skin = mi.skin
	for i in skin.get_bind_count():
		mats.append(skel.global_transform * skel.get_bone_global_pose(bind_bone[i]) * skin.get_bind_pose(i))
	var segs := []
	for c in caps:
		segs.append([(skel.global_transform * skel.get_bone_global_pose(c[0])).origin, (skel.global_transform * skel.get_bone_global_pose(c[1])).origin, c[2]])
	var inside := 0
	var used := 0
	var nb := bones.size() / verts.size()
	for vi in range(0, verts.size(), 2):
		if verts[vi].y > zmax: continue
		used += 1
		var p := Vector3.ZERO
		for j in nb:
			var w := weights[vi * nb + j]
			if w <= 0.0: continue
			p += (mats[bones[vi * nb + j]] as Transform3D) * verts[vi] * w
		for sg in segs:
			var cp := Geometry3D.get_closest_point_to_segment(p, sg[0], sg[1])
			if p.distance_to(cp) < sg[2]: inside += 1; break
	var pct := 100.0 * inside / maxf(used, 1)

	if samples.is_empty() or pct > samples.max(): worst_frame = t
	samples.append(pct)
