extends SceneTree
## R6 候選玩家場景「Yoriichi R6 Animation Integration」：繼承 player_yoriichi.tscn（原檔不動），
## 換成 R6 子類控制器、R6 握刀掛點（Sword_Hand，等比 0.68，實際刀柄網格解）與 R6 動畫資源（v24/anims_r6/）。
## 沒有建出的 R6 資源就沿用正式值（不會指到不存在的檔）。
##   godot --headless --path . -s res://tools/yoriichi_r6/make_r6_candidate.gd
const BASE := "res://characters/yoriichi/player_yoriichi.tscn"
const OUT := "res://characters/yoriichi/player_yoriichi_r6.tscn"
const SCRIPT := "res://characters/yoriichi/yoriichi_character_r6.gd"
const GRIP := "D:/神社/shrine/work/yoriichi_r6/grip_solution_r6.json"
const A6 := "res://characters/yoriichi/v24/anims_r6/"
const RES := {
	"idle_grounded_resource": "r6_idle_sheathed.res",
	"drawn_idle_resource": "r6_idle_drawn.res",
	"jump_anim_resource": "r6_jump_up.res",
	"fall_resource": "r6_fall.res",
	"land_resource": "r6_land.res",
	"heavy_cut_resource": "r6_heavy_cut.res",
	"grip_pose_resource": "r6_grip_pose.res",
	"r5_quickdraw_resource": "r6_quickdraw.res",
	# 相容修補：雙手大刀系片段（型／架勢／格擋／持刀側移後退）左手重新貼回 R6 刀柄（正式 anims/ 原檔不動）
	"attack_spin_jump_resource": "r6c_gs_jump_atk.res",
	"attack_thrust_resource": "r6c_gs_slide.res",
	"attack_form05_resource": "r6c_gs_power.res",
	"attack_form06_resource": "r6c_gs_crouch_slash.res",
	"iai_slash_resource": "r6c_gs_crouch_slash.res",
	"attack_form12_resource": "r6c_th_combo.res",
	"attack_spin_resource": "r6c_gs_spin_run.res",
	"iai_stance_resource": "r6c_iai_stance.res",
	"guard_anim_resource": "r6c_guard.res",
	"block_anim_resource": "r6c_gs_block_hit.res",
	"deflect_anim_resource": "r6c_gs_block_hit.res",
	"drawn_strafe_l_resource": "r6c_gs_strafe_l.res",
	"drawn_strafe_r_resource": "r6c_gs_strafe_r.res",
	"drawn_back_resource": "r6c_gs_walk_back.res",
	"drawn_strafe_l_run_resource": "r6c_gs_strafe_l_run.res",
	"drawn_strafe_r_run_resource": "r6c_gs_strafe_r_run.res",
	"drawn_run_back_resource": "r6c_gs_run_back.res",
}

func _initialize() -> void:
	var base: PackedScene = load(BASE)
	var inst := base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	var keep := {}
	for p in inst.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			keep[p.name] = inst.get(p.name)
	inst.set_script(load(SCRIPT))
	for k in keep:
		inst.set(k, keep[k])
	var used := {}
	for prop in RES:
		var path: String = A6 + RES[prop]
		if ResourceLoader.exists(path):
			inst.set(prop, load(path))
			used[prop] = RES[prop]
	# 緣一專屬待機：不播 NPC 式張望／呼吸小動作
	inst.set("idle_break_enabled", false)
	# R6 重斬：操作鎖定只到 f46（meta r6_ctrl_end，之後是可被移動／下一招接掉的視覺收尾），
	#   f24 舉刀頂點＝蓄力切架勢點 → 24/46；速度 1.15 讓整招鎖定 ≈1.33 s、落刀 ≈0.72 s（R3 重斬鎖定 ≈1.1 s）
	if used.has("heavy_cut_resource"):
		inst.set("heavy_charge_freeze_progress", 0.52)
		inst.set("heavy_cut_speed", 1.15)
	var f := FileAccess.open(GRIP, FileAccess.READ)
	var g: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Array = g.S_new_rows
	var basis := Basis(Vector3(r[0][0], r[1][0], r[2][0]), Vector3(r[0][1], r[1][1], r[2][1]), Vector3(r[0][2], r[1][2], r[2][2]))
	var t := Transform3D(basis, Vector3(r[0][3], r[1][3], r[2][3]))
	var sh := inst.find_child("Sword_Hand", true, false) as Node3D
	sh.transform = t
	print("R6 Sword_Hand: ", sh.transform, " col_len=", [t.basis.x.length(), t.basis.y.length(), t.basis.z.length()])
	print("R6 resources: ", used)
	var ps := PackedScene.new()
	var e := ps.pack(inst)
	var e2 := ResourceSaver.save(ps, OUT)
	print("R6_CANDIDATE pack=", e, " save=", e2, " script=", inst.get_script().resource_path)
	quit()
