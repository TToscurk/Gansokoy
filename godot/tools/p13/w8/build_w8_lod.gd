extends SceneTree
## P13 Wave 8 TASK B：gen/lod_cal_batch1_p13.scn（root 直下 overlay `LodCalBatch1P13`）を書く。
##   godot --headless --path . --script res://tools/p13/w8/build_w8_lod.gd
## 入力＝data/village_v2_p13w8_lod.json（名簿・割り当て）＋ maps/village_v2/lod_cal_p13/lod_material_variants.json（登記材質）。どちらも w8_lod_fit_build.py が書く。
const SCRIPT := "res://maps/village_v2/scripts_p13/lod_cal_batch.gd"
const MAN := "res://data/village_v2_p13w8_lod.json"
const REG := "res://maps/village_v2/lod_cal_p13/lod_material_variants.json"
const OUT_SCENE := "res://maps/village_v2/gen/lod_cal_batch1_p13.scn"


func _init() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAN))
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REG))
	var mats: Array[Material] = []
	var index := {}
	for v: Dictionary in reg["variants"]:
		var m := load(String(v["file"])) as Material
		if m == null:
			push_error("材質が読めない：" + String(v["file"]))
			quit(1)
			return
		index[String(v["id"])] = mats.size()
		mats.append(m)
	var paths := PackedStringArray()
	var asg: Array = []
	for b: Dictionary in man["buildings"]:
		paths.append(String(b["path"]))
		asg.append({"l1": int(index[String(b["l1"])]), "l2": int(index[String(b["l2"])]), "roof": int(index[String(b["roof"])])})
	var node := Node3D.new()
	node.name = String(man["node"])
	node.set_script(load(SCRIPT))
	node.set("targets", paths)
	node.set("mats", mats)
	node.set("assign", asg)
	node.set_meta("phase", "P13 W8 TASK B")
	var ps := PackedScene.new()
	ps.pack(node)
	var err := ResourceSaver.save(ps, OUT_SCENE)
	print("[W8B] saved ", OUT_SCENE, " err=", err, " targets=", paths.size(), " mats=", mats.size())
	quit(0)
