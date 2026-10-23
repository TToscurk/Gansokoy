extends SceneTree
## R4 候選玩家場景：繼承 player_yoriichi.tscn（原檔不動），只覆寫 R4 動畫資源、持刀掛點（Sword_Hand）與聚力凍結點。
##   godot --headless --path . -s res://tools/yoriichi_r4/make_r4_candidate.gd
const BASE := "res://characters/yoriichi/player_yoriichi.tscn"
const OUT := "res://characters/yoriichi/player_yoriichi_r4.tscn"
const R4 := "res://characters/yoriichi/v24/anims_r4/"
const GRIP := "D:/神社/shrine/work/yoriichi_r4/grip_solution.json"

func _initialize() -> void:
	var base: PackedScene = load(BASE)
	var inst := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	inst.set("drawn_idle_resource", load(R4 + "r4_idle.res"))
	inst.set("grip_pose_resource", load(R4 + "r4_idle.res"))
	inst.set("attack_combo_resource", load(R4 + "r4_light_combo.res"))
	inst.set("heavy_cut_resource", load(R4 + "r4_heavy_cut.res"))
	inst.set("heavy_charge_freeze_progress", 0.40)
	var f := FileAccess.open(GRIP, FileAccess.READ)
	var g: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Array = g.S_new_rows
	var basis := Basis(Vector3(r[0][0], r[1][0], r[2][0]), Vector3(r[0][1], r[1][1], r[2][1]), Vector3(r[0][2], r[1][2], r[2][2]))
	var t := Transform3D(basis, Vector3(r[0][3], r[1][3], r[2][3]))
	var sh := inst.find_child("Sword_Hand", true, false) as Node3D
	print("R3 Sword_Hand: ", sh.transform, " col_len=", [sh.transform.basis.x.length(), sh.transform.basis.y.length(), sh.transform.basis.z.length()], " owner=", sh.owner)
	sh.transform = t
	print("R4 Sword_Hand: ", sh.transform, " col_len=", [t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
	var ss := inst.find_child("Sword_Sheathed", true, false) as Node3D
	if ss:
		print("Sword_Sheathed col_len=", [ss.transform.basis.x.length(), ss.transform.basis.y.length(), ss.transform.basis.z.length()])
	var ps := PackedScene.new()
	var e := ps.pack(inst)
	var e2 := ResourceSaver.save(ps, OUT)
	print("R4_CANDIDATE pack=", e, " save=", e2)
	quit()
