extends SceneTree
## R6.2 候選玩家場景：以 player_yoriichi_r61.tscn 的文字為底（R6.1 場景本身不動、保留為對照），產生 player_yoriichi_r62.tscn：
##   1. 控制器腳本換成 yoriichi_character_r62.gd（extends R6.1；握刀 IK、居合出鞘段水平化都在執行期）
##   2. BodyVisual 的 GLB 換成候選 v24_r62/yoriichi_v24_r62.glb（節點結構／骨名與正式相同，只改蒙皮權重）
##   3. 動畫資源、場景屬性沿用 R6.1（不新增片段）
##   godot --headless --path . -s res://tools/yoriichi_r62/make_r62_candidate.gd
const BASE := "res://characters/yoriichi/player_yoriichi_r61.tscn"
const OUT := "res://characters/yoriichi/player_yoriichi_r62.tscn"
const SCRIPT_R61 := "res://characters/yoriichi/yoriichi_character_r61.gd"
const SCRIPT_R62 := "res://characters/yoriichi/yoriichi_character_r62.gd"
const GLB_R61 := "res://characters/yoriichi/v24_r61/yoriichi_v24_r61.glb"
const GLB_R62 := "res://characters/yoriichi/v24_r62/yoriichi_v24_r62.glb"


func _initialize() -> void:
	var txt := FileAccess.get_file_as_string(ProjectSettings.globalize_path(BASE))
	var n0 := txt.length()
	txt = txt.replace("path=\"%s\"" % SCRIPT_R61, "path=\"%s\"" % SCRIPT_R62)
	if not ResourceLoader.exists(GLB_R62):
		push_error("R62 GLB not imported: " + GLB_R62)
		quit(1)
		return
	txt = txt.replace("path=\"%s\"" % GLB_R61, "path=\"%s\"" % GLB_R62)
	# 外部資源的 uid 屬性會讓 Godot 優先用 uid 找到 R6.1 的資源 → 換路徑時一併拿掉這兩個資源的 uid
	var lines := txt.split("\n")
	for i in lines.size():
		var ln := lines[i]
		if ln.begins_with("[ext_resource") and (ln.contains(SCRIPT_R62) or ln.contains(GLB_R62)) and ln.contains(" uid=\""):
			var a := ln.find(" uid=\"")
			var b := ln.find("\"", a + 6)
			lines[i] = ln.substr(0, a) + ln.substr(b + 1)
	txt = "\n".join(lines)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	var ps: PackedScene = load(OUT)
	var inst := ps.instantiate()
	var scr: Script = inst.get_script()
	var glb_ok := false
	for n in inst.find_children("*", "Skeleton3D", true, false):
		glb_ok = true
	print("OUT ", OUT, " chars ", n0, "->", txt.length(), " script ", scr.resource_path if scr else "none", " skeleton ", glb_ok)
	inst.free()
	quit(0)
