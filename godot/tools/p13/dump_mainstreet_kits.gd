extends SceneTree
## P13 W2：主街 39 棟の新 Kit（＋住居化した棟の Frontage）を組み、.tscn 差し替え用のノード記述 JSON を出す（場景は書かない）。
##   godot --headless --path . --script res://tools/p13/dump_mainstreet_kits.gd -- <out.json>
## 地形高（Frontage）＝TerrainCollision 三角形（RLib.terrain_sampler）——Kit gate と同じ来源。
const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")
const ML := preload("res://tools/village_v2_p13_mainstreet_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _props(n: Node) -> Array:
	var out: Array = []
	if n is Node3D and (n as Node3D).transform != Transform3D.IDENTITY:
		out.append(["transform", var_to_str((n as Node3D).transform)])
	if n is Node3D and not (n as Node3D).visible:
		out.append(["visible", "false"])
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		if m.visibility_range_begin != 0.0:
			out.append(["visibility_range_begin", var_to_str(m.visibility_range_begin)])
		if m.visibility_range_begin_margin != 0.0:
			out.append(["visibility_range_begin_margin", var_to_str(m.visibility_range_begin_margin)])
		if m.visibility_range_end != 0.0:
			out.append(["visibility_range_end", var_to_str(m.visibility_range_end)])
		if m.visibility_range_end_margin != 0.0:
			out.append(["visibility_range_end_margin", var_to_str(m.visibility_range_end_margin)])
		if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			out.append(["cast_shadow", str(int(m.cast_shadow))])
		out.append(["mesh", "@MESH:" + m.mesh.resource_path])
	for k in n.get_meta_list():
		out.append(["metadata/" + String(k), var_to_str(n.get_meta(k))])
	return out


func _walk(n: Node, parent_path: String, out: Array) -> void:
	out.append({"name": String(n.name), "type": n.get_class(), "parent": parent_path, "props": _props(n)})
	var me := parent_path + "/" + String(n.name)
	for c in n.get_children():
		_walk(c, me, out)


func _run() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var embed := float(L["greybox"]["embed"])
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/gen/greybox.json"))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	var S := RLib.terrain_sampler(v)
	var hf := func(p: Vector2) -> float: return S.h(p.x, p.y)
	var lib := KLib.load_lib()
	var res := {"buildings": {}}
	var n := 0
	for b: Dictionary in G["buildings"]:
		var id := String(b["id"])
		if String(b["kind"]) != "machiya" or not ML.has(id):
			continue
		var path := "Districts/%s/Buildings/%s" % [b["district"], id]
		var body := v.get_node(path) as Node3D
		var old := body.get_node("Kit")
		body.remove_child(old)
		old.free()
		var kit := ML.apply(body, b, lib, embed)
		var ent := {"kit": [], "frontage": [], "eave": float(ML.effective_rec(b)["eave_m"]), "role": String(kit.get_meta("p13_role")),
			"lod0_tris": KLib.lod_tris(kit, 0), "mi": kit.find_children("*", "MeshInstance3D", true, false).size()}
		_walk(kit, path, ent["kit"])
		if String(ML.design()[id]["role"]) == "residence" and float(b.get("hisashi_m", 0.0)) > 0.0:
			var of := body.get_node("Frontage")
			body.remove_child(of)
			of.free()
			var fr := KLib.frontage(body, ML.effective_rec(b), lib, kit, hf)
			_walk(fr, path, ent["frontage"])
		res["buildings"][id] = ent
		n += 1
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("[DUMP] 棟 %d" % n)
	quit(0 if n == 39 else 1)
