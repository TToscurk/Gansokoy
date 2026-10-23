extends SceneTree
## R4（Blender 重做）資料基準：輸出 v2.4 骨架 rest／內建 idle 第 0 格的骨骼全域姿勢、
## Sword_Hand 掛點與刀 GLB 內部節點，供 Blender 端驗證座標換算（唯讀，不改任何資源）。
## 用法：godot --headless --path . -s res://tools/yoriichi_r4/r4_dump_ref.gd
const GLB := "res://characters/yoriichi/v24/yoriichi_v24.glb"
const SWORD := "res://characters/yoriichi/yoriichi_sword.glb"
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"

func _xf(t: Transform3D) -> Array:
	# 欄向量（basis.x, basis.y, basis.z）+ origin
	return [[t.basis.x.x, t.basis.x.y, t.basis.x.z], [t.basis.y.x, t.basis.y.y, t.basis.y.z],
		[t.basis.z.x, t.basis.z.y, t.basis.z.z], [t.origin.x, t.origin.y, t.origin.z]]

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s:
			return s
	return null

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var s := _find_anim(c)
		if s:
			return s
	return null

var _done := false
var body: Node3D
var sw: Node3D

func _initialize() -> void:
	body = (load(GLB) as PackedScene).instantiate()
	root.add_child(body)
	sw = (load(SWORD) as PackedScene).instantiate()
	root.add_child(sw)

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var out := {}
	var sk := _find_skel(body)
	var ap := _find_anim(body)
	out["skeleton_path_from_root"] = str(body.get_path_to(sk))
	out["skeleton_global_from_body"] = _xf(sk.global_transform)
	var rest := {}
	for i in sk.get_bone_count():
		rest[sk.get_bone_name(i)] = {"parent": sk.get_bone_parent(i), "global_rest": _xf(sk.get_bone_global_rest(i)), "local_rest": _xf(sk.get_bone_rest(i))}
	out["bones"] = rest
	out["anims"] = ap.get_animation_list() if ap else []
	if ap and ap.has_animation("idle"):
		ap.play("idle")
		ap.seek(0.0, true)
		ap.advance(0.0)
		var pose := {}
		for i in sk.get_bone_count():
			pose[sk.get_bone_name(i)] = _xf(sk.get_bone_global_pose(i))
		out["idle_t0_global_pose"] = pose
	# Sword_Hand / Sword_Sheathed / Sheath 掛點（tscn 文字，row-major → str_to_var）
	var txt := FileAccess.get_file_as_string(PLAYER).replace("\r\n", "\n")
	for nm in ["Sword_Hand", "Sword_Sheathed", "Sheath"]:
		var re := RegEx.new()
		re.compile("\\[node name=\"" + nm + "\"[^\\n]*\\]\\ntransform = (Transform3D\\([^)]*\\))")
		var m := re.search(txt)
		if m:
			out["socket_" + nm] = _xf(str_to_var(m.get_string(1)))
	# 刀 GLB 內部節點與網格 AABB（刀本地）
	var nodes := []
	var stack: Array = [sw]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D:
			var e := {"path": str(sw.get_path_to(n)), "type": n.get_class(), "xf_rel_root": _xf(sw.global_transform.affine_inverse() * (n as Node3D).global_transform)}
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				var ab: AABB = (n as MeshInstance3D).mesh.get_aabb()
				e["aabb"] = [[ab.position.x, ab.position.y, ab.position.z], [ab.size.x, ab.size.y, ab.size.z]]
			nodes.append(e)
		for c in n.get_children():
			stack.push_back(c)
	out["sword_nodes"] = nodes
	var f := FileAccess.open("user://r4_ref.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("R4_DUMP_OK ", ProjectSettings.globalize_path("user://r4_ref.json"), " bones=", sk.get_bone_count(), " anims=", out["anims"])
	quit()
	return true
