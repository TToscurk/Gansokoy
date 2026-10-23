extends SceneTree
## 一次性工具（候選）：把緣一骨架的 rest、父子關係、單手持刀插槽 Sword_Hand（＝two_hand_grip 的 sock_old）輸出成 JSON，
## 給研究目錄的 numpy 腳本做「左手握柄可達性」修正（notes/fix_twohand_reach.py）。
## 用法：godot --headless --path godot -s res://characters/yoriichi/v24_isshin/dump_rig_for_reach.gd -- OUT.json
func _xf(t: Transform3D) -> Array:
	# row-major 3x4（與 r62_grip.json 相同格式）
	var b := t.basis
	return [[b.x.x, b.y.x, b.z.x, t.origin.x], [b.x.y, b.y.y, b.z.y, t.origin.y], [b.x.z, b.y.z, b.z.z, t.origin.z]]

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var scn: PackedScene = load("res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn")
	var root := scn.instantiate()
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var sh := root.find_child("Sword_Hand", true, false) as Node3D
	var bones := []
	for i in sk.get_bone_count():
		bones.append({"name": sk.get_bone_name(i), "parent": sk.get_bone_parent(i), "rest": _xf(sk.get_bone_rest(i))})
	# Skeleton3D 相對 Actor 的累積 transform（確認骨架空間＝actor 空間）
	var acc := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n.name != "Actor":
		if n is Node3D:
			acc = (n as Node3D).transform * acc
		n = n.get_parent()
	var d := {"bones": bones, "sock_old": _xf(sh.transform), "skeleton_global": _xf(sk.transform), "skeleton_in_actor": _xf(acc)}
	# 鞘中刀（正式 R6.2 場景的 Sword_Sheathed，SheathSocket＝Hips 骨）：只讀場景狀態，不實例化、不修改
	var st := (load("res://characters/yoriichi/player_yoriichi_r62.tscn") as PackedScene).get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) == "Sword_Sheathed" or st.get_node_name(i) == "Sheath":
			for j in st.get_node_property_count(i):
				if st.get_node_property_name(i, j) == "transform":
					d["r62_" + str(st.get_node_name(i))] = _xf(st.get_node_property_value(i, j))
	var shn := root.find_child("Sheath", true, false) as Node3D
	if shn:
		d["demo_Sheath"] = _xf(shn.transform)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("dumped ", bones.size(), " bones -> ", out)
	root.free()
	quit()
