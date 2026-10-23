extends SceneTree
## R5 候選玩家場景：繼承 player_yoriichi.tscn（原檔不動），換成 R5 子類控制器、R5 握刀掛點（Sword_Hand）。
## 其餘（R3 待機／走跑／連段／重斬／型、SpringBone、指定新鞘）全部沿用正式場景。
##   godot --headless --path . -s res://tools/yoriichi_r5/make_r5_candidate.gd
const BASE := "res://characters/yoriichi/player_yoriichi.tscn"
const OUT := "res://characters/yoriichi/player_yoriichi_r5.tscn"
const SCRIPT := "res://characters/yoriichi/yoriichi_character_r5.gd"
const GRIP := "D:/神社/shrine/work/yoriichi_r5/grip_solution_r5.json"

func _initialize() -> void:
	var base: PackedScene = load(BASE)
	var inst := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	# 換腳本時保留父場景已設的 export 值
	var keep := {}
	for p in inst.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			keep[p.name] = inst.get(p.name)
	inst.set_script(load(SCRIPT))
	for k in keep:
		inst.set(k, keep[k])
	var f := FileAccess.open(GRIP, FileAccess.READ)
	var g: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Array = g.S_new_rows
	var basis := Basis(Vector3(r[0][0], r[1][0], r[2][0]), Vector3(r[0][1], r[1][1], r[2][1]), Vector3(r[0][2], r[1][2], r[2][2]))
	var t := Transform3D(basis, Vector3(r[0][3], r[1][3], r[2][3]))
	var sh := inst.find_child("Sword_Hand", true, false) as Node3D
	print("R3 Sword_Hand: ", sh.transform)
	sh.transform = t
	print("R5 Sword_Hand: ", sh.transform, " col_len=", [t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
	print("kept exports: ", keep.size(), " script=", inst.get_script().resource_path)
	var ps := PackedScene.new()
	var e := ps.pack(inst)
	var e2 := ResourceSaver.save(ps, OUT)
	print("R5_CANDIDATE pack=", e, " save=", e2)
	quit()
