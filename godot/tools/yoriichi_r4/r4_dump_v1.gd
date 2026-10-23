extends SceneTree
## R4：從復原的 v1 Meshy 身體（暫存匯入）讀 RightHand 全域 rest 與 v1 Sword_Hand 掛點，輸出刀在 v1 骨架空間的姿態。
## 唯讀；暫存檔在 res://tools/yoriichi_r4/tmp_v1/（R4 自建，用完可刪）。
const BODY := "res://tools/yoriichi_r4/tmp_v1/yoriichi_body.fbx"
# HEAD:godot/characters/yoriichi/player_yoriichi.tscn 的 v1 Sword_Hand（row-major 文字）
const SOCKET_V1 := "Transform3D(-0.14443, 0.844425, 0.515836, -0.9884, -0.0983786, -0.115699, -0.0469521, -0.526563, 0.848839, 0.126589, 0.0809044, -0.0618592)"
var _done := false
var body: Node3D

func _xf(t: Transform3D) -> Array:
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

func _initialize() -> void:
	body = (load(BODY) as PackedScene).instantiate()
	root.add_child(body)

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var sk := _find_skel(body)
	var out := {"skeleton_global": _xf(sk.global_transform), "bones": {}}
	for i in sk.get_bone_count():
		out["bones"][sk.get_bone_name(i)] = _xf(sk.get_bone_global_rest(i))
	var S: Transform3D = str_to_var(SOCKET_V1)
	out["socket_v1"] = _xf(S)
	var hi := sk.find_bone("RightHand")
	out["sword_rest_skeleton_space"] = _xf(sk.get_bone_global_rest(hi) * S)
	var f := FileAccess.open("user://r4_v1_ref.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("R4_V1_OK bones=", sk.get_bone_count(), " skel_global=", sk.global_transform)
	quit()
	return true
