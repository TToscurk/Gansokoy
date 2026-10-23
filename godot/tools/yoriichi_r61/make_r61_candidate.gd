extends SceneTree
## R6.1 候選玩家場景：以 player_yoriichi_r6.tscn 的文字為底（R6 場景本身不動、保留為對照），產生 player_yoriichi_r61.tscn：
##   1. 控制器腳本換成 yoriichi_character_r61.gd（extends R6）
##   2. BodyVisual 的 GLB 換成候選 v24_r61/yoriichi_v24_r61.glb（節點結構／骨名與正式相同，只改蒙皮權重；有建出才換）
##   3. 動畫資源：v24/anims_r61/ 有同名 r61_* 就換掉對應的 R6 資源，沒有就沿用 R6
##   4. 場景屬性覆寫（跳躍起跳時間等），值來自 work/yoriichi_r61/scene_overrides.json（存在時）
##   godot --headless --path . -s res://tools/yoriichi_r61/make_r61_candidate.gd
const BASE := "res://characters/yoriichi/player_yoriichi_r6.tscn"
const OUT := "res://characters/yoriichi/player_yoriichi_r61.tscn"
const SCRIPT_R6 := "res://characters/yoriichi/yoriichi_character_r6.gd"
const SCRIPT_R61 := "res://characters/yoriichi/yoriichi_character_r61.gd"
const GLB_OFF := "res://characters/yoriichi/v24/yoriichi_v24.glb"
const GLB_R61 := "res://characters/yoriichi/v24_r61/yoriichi_v24_r61.glb"
const A6 := "res://characters/yoriichi/v24/anims_r6/"
const A61 := "res://characters/yoriichi/v24/anims_r61/"
const OVR := "D:/神社/shrine/work/yoriichi_r61/scene_overrides.json"
## R6 資源檔名 -> R6.1 資源檔名
const SWAP := {
	"r6_jump_up.res": "r61_jump_up.res", "r6_fall.res": "r61_fall.res", "r6_land.res": "r61_land.res",
	"r6_quickdraw.res": "r61_quickdraw.res", "r6_grip_pose.res": "r61_grip_pose.res", "r6_idle_drawn.res": "r61_idle_drawn.res",
	"r6_heavy_cut.res": "r61_heavy_cut.res", "r6c_guard.res": "r61c_guard.res", "r6c_gs_spin_run.res": "r61c_gs_spin_run.res",
}

func _initialize() -> void:
	var txt := FileAccess.get_file_as_string(ProjectSettings.globalize_path(BASE))
	var used := {}
	txt = txt.replace("path=\"%s\"" % SCRIPT_R6, "path=\"%s\"" % SCRIPT_R61)
	if ResourceLoader.exists(GLB_R61):
		txt = txt.replace("path=\"%s\"" % GLB_OFF, "path=\"%s\"" % GLB_R61)
		used["glb"] = GLB_R61
	for k in SWAP:
		if ResourceLoader.exists(A61 + SWAP[k]):
			txt = txt.replace("path=\"%s%s\"" % [A6, k], "path=\"%s%s\"" % [A61, SWAP[k]])
			used[k] = SWAP[k]
	# 場景屬性覆寫：寫在根節點 [node name="Player" ...] 區塊（script = ... 下一行）
	if FileAccess.file_exists(OVR):
		var ov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OVR))
		var lines := txt.split("\n")
		var out := PackedStringArray()
		var in_root := false
		for ln in lines:
			if ln.begins_with("[node name=\"Player\""):
				in_root = true
			elif ln.begins_with("[node ") or ln.begins_with("[sub_resource") or ln.begins_with("[ext_resource"):
				in_root = false
			if in_root:
				var key := ln.get_slice(" = ", 0)
				if ov.has(key):
					continue
			out.append(ln)
			if in_root and ln.begins_with("script = "):
				for k in ov:
					out.append("%s = %s" % [k, var_to_str(ov[k])])
					used["ovr:" + k] = ov[k]
		txt = "\n".join(out)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	# 載入驗證：實例化、確認腳本／GLB／資源路徑
	var ps: PackedScene = load(OUT)
	var inst := ps.instantiate()
	var bv := inst.get_node("BodyVisual")
	print("R61_CANDIDATE script=", inst.get_script().resource_path, " glb=", bv.scene_file_path, " used=", used)
	inst.free()
	quit()
