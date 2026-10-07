extends RefCounted
## 人間之里 V2 P9 R1：植被庫（Gensokyo Vegetation Library）組裝 lib。
##   由 tools/village_v2_machiya_kit_prefab.gd -- --kit=veg_kit 呼叫（與町家／河岸 Kit 同一支 prefab，不另立 pipeline）：
##     make_materials()  ← 讀 tex/veg_tex.json，寫 mat/VK_*.tres（樹皮 9 種＋葉叢 atlas 2 張；shader 共用 2 支）
##     make_prefabs()    ← 讀 src/modules_blender.json，寫 trees/<id>.tscn（LOD 節點＋抖動換檔參數＋簡化碰撞）
##   review 場景（tools/village_v2_veg_review.gd）與之後 P9 R2 林帶都只 instance trees/<id>.tscn。
##
## LOD：每級一個 MeshInstance3D（mesh/<id>_LOD<k>.res）。換檔用 shader 逐像素抖動交叉（veg_common.gdshaderinc），
##   instance uniform lod_band＝(begin, end, begin 交叉寬, end 交叉寬)、lod_ref＝LOD0 AABB 中心（各級共用 → 閾值互補）。
##   visibility_range 只當粗剔除：比交叉帶寬 SLACK，margin 0、fade 關（不用引擎 alpha 淡出）。
## 碰撞：普通樹＝樹幹 1 根 CylinderShape3D（地面下 0.2 m 到第一分枝／≤ 3.2 m）；Hero 加低枝圓柱（≤ 6 個）；
##   灌木／蕨／地被不給碰撞。不為枝葉做碰撞。

const KIT := "res://assets/village_v2/veg_kit"
const MAT_DIR := KIT + "/mat"
const TREE_DIR := KIT + "/trees"
const LEAF_SHADER := KIT + "/veg_leaf.gdshader"
const BARK_SHADER := KIT + "/veg_bark.gdshader"
const SLACK := 4.0            # 粗剔除比交叉帶多留（m）
const XFADE_FRAC := 0.12      # 交叉寬＝換檔距離 × 此比例（最少 3 m）

## 材質參數（之後 ART_REVIEW 調整只改這裡）
const LEAF_PARAMS := {"roughness": 0.82, "specular": 0.22, "alpha_cut": 0.5, "alpha_mip_boost": 0.18,
	"translucency": 0.35, "normal_depth": 0.8, "albedo_mul": 1.0}
const BARK_PARAMS := {"roughness": 0.92, "specular": 0.18, "normal_depth": 1.0, "albedo_mul": 1.0}
## 色彩變體（規格：young／mature／slightly yellow／deep green／shaded green；櫻／楓要有非極端飽和版）。
##   [leaf_tint, leaf_sat]；差異刻意克制（±8–20 %），整片林子用 R2 依 instance 分配，不做逐葉 RGB 亂數。
const COLOR_PRESETS := {
	"mature": [Vector3(1.0, 1.0, 1.0), 1.0],
	"young": [Vector3(1.07, 1.09, 0.86), 1.0],
	"yellow": [Vector3(1.1, 1.04, 0.78), 0.95],
	"deep": [Vector3(0.8, 0.87, 0.84), 1.0],
	"shade": [Vector3(0.84, 0.9, 0.9), 0.9],
	"muted": [Vector3(0.97, 0.96, 0.95), 0.68],
}
## 各群組在審圖場景展示的色彩變體（櫻／楓：預設＋克制版）
const GROUP_COLORS := {
	"conifer": ["mature", "young", "yellow", "deep", "shade"],
	"broad": ["mature", "young", "yellow", "deep", "shade"],
	"matsu": ["mature", "young", "deep", "shade"],
	"yanagi": ["mature", "young", "yellow", "shade"],
	"sakura": ["mature", "muted"],
	"momiji": ["mature", "muted", "deep"],
	"hero": ["mature", "deep"],
	"young": ["mature", "young", "yellow"],
	"under": ["mature", "young", "deep"],
}


## 套色彩變體到一棵樹（所有 LOD 的 MeshInstance3D；樹皮 shader 不讀這兩個參數）
static func apply_color(tree: Node, preset: String) -> void:
	var p: Array = COLOR_PRESETS.get(preset, COLOR_PRESETS["mature"])
	for mi in tree.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_instance_shader_parameter("leaf_tint", p[0])
		(mi as MeshInstance3D).set_instance_shader_parameter("leaf_sat", p[1])
	tree.set_meta("veg_color", preset)


static func tex_meta() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT + "/tex/veg_tex.json"))
	return m if m is Dictionary else {}


## 名稱 → .tres 路徑（prefab 白名單用；名稱＝Blender 佔位材質名）
static func material_paths() -> Dictionary:
	var out := {}
	var tm := tex_meta()
	for b: String in tm.get("bark", {}):
		out["VK_Bark_" + b] = MAT_DIR + "/VK_Bark_%s.tres" % b
	for a: String in tm.get("atlas", {}):
		out["VK_Leaf_" + a] = MAT_DIR + "/VK_Leaf_%s.tres" % a
	return out


static func make_materials() -> PackedStringArray:
	var errs := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var tm := tex_meta()
	if tm.is_empty():
		errs.append("讀不到 tex/veg_tex.json")
		return errs
	var leaf_sh: Shader = load(LEAF_SHADER)
	var bark_sh: Shader = load(BARK_SHADER)
	if leaf_sh == null or bark_sh == null:
		errs.append("shader 讀不到")
		return errs
	for b: String in tm["bark"]:
		var e: Dictionary = tm["bark"][b]
		errs.append_array(_save_mat(bark_sh, MAT_DIR + "/VK_Bark_%s.tres" % b, String(e["files"]["albedo"]),
			String(e["files"]["normal"]), BARK_PARAMS))
	for a: String in tm["atlas"]:
		var e: Dictionary = tm["atlas"][a]
		errs.append_array(_save_mat(leaf_sh, MAT_DIR + "/VK_Leaf_%s.tres" % a, String(e["file"]), String(e["normal"]),
			LEAF_PARAMS))
	return errs


static func _save_mat(sh: Shader, path: String, alb: String, nor: String, params: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var m: ShaderMaterial = load(path) if ResourceLoader.exists(path) else ShaderMaterial.new()
	m.shader = sh
	var ta: Texture2D = load(alb)
	var tn: Texture2D = load(nor)
	if ta == null or tn == null:
		errs.append("%s 貼圖讀不到（%s／%s）" % [path.get_file(), alb, nor])
	m.set_shader_parameter("albedo_tex", ta)
	m.set_shader_parameter("normal_tex", tn)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	m.resource_name = path.get_file().get_basename()
	var e := ResourceSaver.save(m, path)
	if e != OK:
		errs.append("存 %s：%s" % [path, error_string(e)])
	return errs


## 一棵樹的節點（未設 owner；呼叫端 pack 前設）
static func tree_node(tid: String, info: Dictionary, mesh_dir: String) -> Node3D:
	var root := Node3D.new()
	root.name = tid
	root.set_meta("veg_id", tid)
	root.set_meta("veg_group", info.get("group", ""))
	var lods: Array = info["lods"]
	var dist: Array = info["lod_dist"]
	var a0: Array = lods[0]["aabb"]
	var ref := (_v(a0[0]) + _v(a0[1])) * 0.5
	# 各級 AABB 中心離 ref 的最大差＝粗剔除（量 AABB 中心）與 shader（量 ref）的距離誤差上限
	var dc := 0.0
	for L: Dictionary in lods:
		var aa: Array = L["aabb"]
		dc = maxf(dc, ((_v(aa[0]) + _v(aa[1])) * 0.5).distance_to(ref))
	var n := lods.size()
	for k in n:
		var mi := MeshInstance3D.new()
		mi.name = "LOD%d" % k
		mi.mesh = load(mesh_dir + "/%s_LOD%d.res" % [tid, k])
		var b := float(dist[k]) if k > 0 else 0.0
		var e := float(dist[k + 1]) if k < n - 1 else 0.0
		var wb := xfade_w(b)
		var we := xfade_w(e)
		mi.set_instance_shader_parameter("lod_band", Vector4(b, e, wb, we))
		mi.set_instance_shader_parameter("lod_ref", ref)
		mi.visibility_range_begin = maxf(0.0, b - wb * 0.5 - SLACK - dc) if k > 0 else 0.0
		# 最後一級：lod_dist 最後一個值＝整體最遠可見距離（之後 P12 依實測再收）
		mi.visibility_range_end = (e + we * 0.5 + SLACK + dc) if k < n - 1 else float(dist[n])
		mi.visibility_range_begin_margin = 0.0
		mi.visibility_range_end_margin = 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	# 碰撞（普通樹＝樹幹 1 根；Hero 加低枝；灌木／地被沒有）
	var col: Array = info.get("collision", [])
	if not col.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "Collision"
		root.add_child(sb)
		var i := 0
		for c: Dictionary in col:
			var pa := _v(c["a"])
			var pb := _v(c["b"])
			var cs := CollisionShape3D.new()
			cs.name = "Trunk" if i == 0 else "Limb%d" % i
			var sh := CylinderShape3D.new()
			sh.radius = float(c["r"])
			sh.height = pa.distance_to(pb)
			cs.shape = sh
			var up := (pb - pa).normalized()
			var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(up).normalized()
			cs.transform = Transform3D(Basis(x, up, z), (pa + pb) * 0.5)
			sb.add_child(cs)
			i += 1
	return root


## 換檔距離 d 的交叉寬（同一 d 兩側的級共用 → 閾值互補）
static func xfade_w(d: float) -> float:
	return maxf(3.0, d * XFADE_FRAC) if d > 0.0 else 0.0


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)


static func make_prefabs(man: Dictionary, mesh_dir: String) -> Dictionary:
	## 回傳 {"paths": [...], "errs": [...]}
	var paths: Array = []
	var errs := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TREE_DIR))
	var trees: Dictionary = man["trees"]
	for old in DirAccess.get_files_at(TREE_DIR):
		if old.ends_with(".tscn") and not trees.has(old.get_basename()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TREE_DIR + "/" + old))
	for tid: String in trees:
		var node := tree_node(tid, trees[tid], mesh_dir)
		_own(node, node)
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
