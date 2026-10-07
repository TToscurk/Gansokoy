extends RefCounted
## 人間之里 V2 P9 R3：竹 Kit（bamboo_kit）組裝 lib。
##   由 tools/village_v2_machiya_kit_prefab.gd -- --kit=bamboo_kit 呼叫（與町家／河岸／植被庫同一支 prefab，不另立 pipeline）：
##     make_materials()  ← 讀 tex/bamboo_tex.json，寫 mat/BK_*.tres（竹稈 2 種＋葉叢 atlas 1 張）
##     make_prefabs()    ← 讀 src/modules_blender.json，寫 trees/<id>.tscn
## shader 與 LOD 換檔／碰撞／色彩變體一律重用 R1 植被庫（veg_kit 的 veg_bark／veg_leaf shader、village_v2_veg_lib.gd tree_node()），
## 只讀不改（P9 R1 已封存）。竹的差異只在網格與貼圖。

const VegLib := preload("res://tools/village_v2_veg_lib.gd")
const KIT := "res://assets/village_v2/bamboo_kit"
const MAT_DIR := KIT + "/mat"
const TREE_DIR := KIT + "/trees"
## 竹稈：比樹皮略亮、略有光澤（竹稈表面蠟質）；葉：比闊葉略透
## 竹的獨立 sway（§31.2 Wind 基礎）：同一套 veg shader 參數，竹材質自帶較快擺頻＋較強葉抖；wind_strength 仍 0（靜止），
## 之後 Global Wind Manager 只設 wind_dir／wind_strength，竹與樹的擺動差由這裡的 wind_speed／flutter 與網格 UV2 風權重決定。
const CULM_PARAMS := {"roughness": 0.62, "specular": 0.34, "normal_depth": 0.9, "albedo_mul": 1.0, "wind_speed": 1.35}
const LEAF_PARAMS := {"roughness": 0.78, "specular": 0.25, "alpha_cut": 0.5, "alpha_mip_boost": 0.2,
	"translucency": 0.42, "normal_depth": 0.7, "albedo_mul": 1.0, "wind_speed": 1.35, "flutter": 0.1}
## 竹林色彩變體（instance uniform leaf_tint／leaf_sat；竹稈 shader 不讀）
const GROUP_COLORS := {"bamboo": ["mature", "young", "yellow", "deep"], "bamboo_under": ["mature"]}


static func tex_meta() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT + "/tex/bamboo_tex.json"))
	return m if m is Dictionary else {}


static func material_paths() -> Dictionary:
	var out := {}
	var tm := tex_meta()
	for c: String in tm.get("culm", {}):
		out["BK_Culm_" + c] = MAT_DIR + "/BK_Culm_%s.tres" % c
	for a: String in tm.get("atlas", {}):
		out["BK_Leaf_" + a] = MAT_DIR + "/BK_Leaf_%s.tres" % a
	return out


static func make_materials() -> PackedStringArray:
	var errs := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var tm := tex_meta()
	if tm.is_empty():
		errs.append("讀不到 tex/bamboo_tex.json")
		return errs
	var leaf_sh: Shader = load(VegLib.LEAF_SHADER)
	var bark_sh: Shader = load(VegLib.BARK_SHADER)
	for c: String in tm["culm"]:
		var e: Dictionary = tm["culm"][c]
		errs.append_array(VegLib._save_mat(bark_sh, MAT_DIR + "/BK_Culm_%s.tres" % c, String(e["files"]["albedo"]),
			String(e["files"]["normal"]), CULM_PARAMS))
	for a: String in tm["atlas"]:
		var e: Dictionary = tm["atlas"][a]
		errs.append_array(VegLib._save_mat(leaf_sh, MAT_DIR + "/BK_Leaf_%s.tres" % a, String(e["file"]), String(e["normal"]),
			LEAF_PARAMS))
	return errs


static func make_prefabs(man: Dictionary, mesh_dir: String) -> Dictionary:
	var paths: Array = []
	var errs := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TREE_DIR))
	var trees: Dictionary = man["trees"]
	for old in DirAccess.get_files_at(TREE_DIR):
		if old.ends_with(".tscn") and not trees.has(old.get_basename()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TREE_DIR + "/" + old))
	for tid: String in trees:
		var node := VegLib.tree_node(tid, trees[tid], mesh_dir)
		# 落葉地被不投影（貼地 2 cm 的卡片投影只會變髒）；筍保留
		if String(trees[tid]["cls"]) == "litter":
			for mi in node.find_children("*", "MeshInstance3D", false, false):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		VegLib._own(node, node)
		var ps := PackedScene.new()
		var e := ps.pack(node)
		if e != OK:
			errs.append("pack %s：%s" % [tid, error_string(e)])
		var p := TREE_DIR + "/%s.tscn" % tid
		e = ResourceSaver.save(ps, p)
		if e != OK:
			errs.append("存 %s：%s" % [p, error_string(e)])
		paths.append(p)
		node.free()
	return {"paths": paths, "errs": errs}
