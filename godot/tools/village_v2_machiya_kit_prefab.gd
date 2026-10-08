extends SceneTree
## 人間之里 V2 P6 R1：模組化町家 Kit 構件庫 prefab。
##   godot --headless --path . --script res://tools/village_v2_machiya_kit_prefab.gd
## 讀 Blender 匯出的 assets/village_v2/machiya_kit/src/machiya_kit.glb（build_machiya_kit.py），
## 依 src/modules_blender.json 逐一轉成 ArrayMesh（材質＝共享材質庫 _matlib／Kit atlas），每個構件存一個外部檔：
##   assets/village_v2/machiya_kit/mesh/<構件名>.res（構件只存一次；village_v2.tscn 只存 ext_resource 路徑＋transform）
## 並寫 machiya_kit_manifest.json（Kit 的 gate entry）：構件庫、組裝腳本、材質、atlas 的 sha256。
##   任何一檔改動 → manifest 雜湊變 → gate.json／registry 失效 → 產生器維持灰盒（與 Hero .scn 雜湊同一規則）。
## 同時比對 Blender 端三角面數，任何構件缺漏、材質不在白名單、transform 不是 identity → 失敗。

## P7 R2 起同一支 prefab 也處理河岸 Kit：-- --kit=riverbank_kit（build_riverbank_kit.py；組裝＝village_v2_riverbank_lib.gd）。
##   不帶 --kit＝machiya_kit，行為與 P6 完全相同。
## P9 R4 起也處理稗田邸庭園 Kit：-- --kit=garden_kit（build_garden_kit.py；石＝V2_KitStoneTri、木＝V2_Wood、竹＝bamboo_kit BK_Culm_dead、
##   水＝garden_kit/GK_Water；擺放＝village_v2_hieda_garden_lib.gd）。
## P9 R4-3 起也處理寺子屋周邊小物 Kit：-- --kit=school_kit（build_school_kit.py；擺放＝village_v2_school_yard_lib.gd）。
## P9 R4-4 起也處理水車／龍神像周邊 水邊 Kit：-- --kit=waterside_kit（build_waterside_kit.py；擺放＝village_v2_waterside_lib.gd）。
## P9 R4-5 起也處理火見櫓周邊 消防・瞭望 Kit：-- --kit=tower_kit（build_tower_kit.py；擺放＝village_v2_tower_yard_lib.gd）。
## P9 R4-6 起也處理鈴奈庵周邊 書店・貸本 Kit：-- --kit=suzu_kit（build_suzu_kit.py；擺放＝village_v2_suzunaan_yard_lib.gd；
##   V2_Suzunaan＝鈴奈庵 Hero atlas 只讀重用）。
## P9 R4-7 起也處理鯢吞亭周邊 居酒屋 Kit：-- --kit=geidon_kit（build_geidon_kit.py；擺放＝village_v2_geidontei_yard_lib.gd；
##   V2_Geidontei＝鯢吞亭 Hero atlas 的非發光色票只讀重用）。
## P9 R4-8 起也處理霧雨店周邊 奇物雜貨店＋魔法材料工作坊 Kit：-- --kit=kiri_kit（build_kiri_kit.py；擺放＝village_v2_kirisame_yard_lib.gd；
##   V2_Kirisame＝霧雨店 Hero atlas 的非發光色票只讀重用）。
## P10 R1 起也處理市集廣場 Kit：-- --kit=market_kit（build_market_kit.py；擺放＝village_v2_market_lib.gd；MK_Market＝market_kit atlas）。
## P10 R4b Human-Use Expansion 起也處理 humanuse_exp_kit（build_humanuse_exp_kit.py；擺放＝village_v2_human_use_exp_lib.gd；缺件 3＝hx_hatake・hx_daikon_kake・hx_doroage、材質 V2_Wood／ST_Street）。
## P10 R4 Human-Use Pilot 起也處理生活痕跡 Kit：-- --kit=humanuse_kit（build_humanuse_kit.py；擺放＝village_v2_human_use_lib.gd；材質只用 V2_Wood／ST_Street，新 atlas なし；既存に無い生活語彙 6 だけ）。
## P10 R1b Market West Rework 起也處理見世 Kit：-- --kit=mise_kit（build_mise_kit.py；擺放＝village_v2_market_west_lib.gd；材質只用町で使用中の V2_Wood／V2_Kawara／MK_Market／ST_Street，新 atlas なし）。
## P10 R2 起也處理主街 Street Life Kit：-- --kit=street_kit（build_street_kit.py；擺放＝village_v2_street_lib.gd；ST_Street＝street_kit atlas）。
## P9 R3 起也處理竹 Kit：-- --kit=bamboo_kit（build_bamboo_kit.py；材質＋竹 prefab＝village_v2_bamboo_lib.gd，shader／LOD 重用 veg_kit）。
## P9 R1 起也處理植被庫：-- --kit=veg_kit（build_veg_kit.py；材質＋樹 prefab＝village_v2_veg_lib.gd）。
##   材質白名單由 veg lib 依 tex/veg_tex.json 產生（mat/VK_*.tres，先寫再讀）；另寫 trees/<id>.tscn
##   （LOD 節點＋抖動換檔＋簡化碰撞），manifest 依賴加上 shader、貼圖、樹 prefab。
const KITS := {
	"machiya_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Plaster": "res://assets/village_v2/_matlib/V2_Plaster.tres",
			"V2_Kawara": "res://assets/village_v2/_matlib/V2_Kawara.tres",
			"V2_KitStoneTri": "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
			"V2_MachiyaKit": "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres",
		},
		"assembler": "res://tools/village_v2_machiya_kit_lib.gd",
		"extra": ["/machiya_kit_atlas.png", "/machiya_kit_emit.png", "/atlas.json"],
	},
	"riverbank_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_KitStoneTri": "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
		},
		"assembler": "res://tools/village_v2_riverbank_lib.gd",
		"extra": [],
	},
	"veg_kit": {
		"mats": {},   # 由 village_v2_veg_lib.gd material_paths() 填
		"assembler": "res://tools/village_v2_veg_lib.gd",
		"extra": ["/veg_common.gdshaderinc", "/veg_leaf.gdshader", "/veg_bark.gdshader", "/tex/veg_tex.json"],
	},
	"garden_kit": {
		"mats": {
			"V2_KitStoneTri": "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"BK_Culm_dead": "res://assets/village_v2/bamboo_kit/mat/BK_Culm_dead.tres",
			"GK_Water": "res://assets/village_v2/garden_kit/GK_Water.tres",
			"GK_Falls": "res://assets/village_v2/garden_kit/GK_Falls.tres",
		},
		"assembler": "res://tools/village_v2_hieda_garden_lib.gd",
		"extra": ["/GK_Water.tres", "/GK_Falls.tres", "/hg_ground.gdshader", "/GK_PondWater.tres", "/hg_water.gdshader", "/GK_FallSheet.tres", "/hg_falls.gdshader"],
	},
	"school_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"BK_Culm_dead": "res://assets/village_v2/bamboo_kit/mat/BK_Culm_dead.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_school_yard_lib.gd",
		"extra": ["/school_kit_atlas.png", "/atlas.json"],
	},
	"waterside_kit": {
		"mats": {
			"WK_Plant": "res://assets/village_v2/waterside_kit/WK_Plant.tres",
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_KitStoneTri": "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_waterside_lib.gd",
		"extra": ["/WK_Plant.tres"],
	},
	"tower_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Metal": "res://assets/village_v2/_matlib/V2_Metal.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_tower_yard_lib.gd",
		"extra": [],
	},
	"suzu_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Suzunaan": "res://assets/village_v2/suzunaan/V2_Suzunaan.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_suzunaan_yard_lib.gd",
		"extra": [],
	},
	"geidon_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Geidontei": "res://assets/village_v2/geidontei/V2_Geidontei.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_geidontei_yard_lib.gd",
		"extra": [],
	},
	"kiri_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Stone": "res://assets/village_v2/_matlib/V2_Stone.tres",
			"V2_Kirisame": "res://assets/village_v2/kirisame/V2_Kirisame.tres",
			"SK_School": "res://assets/village_v2/school_kit/SK_School.tres",
		},
		"assembler": "res://tools/village_v2_kirisame_yard_lib.gd",
		"extra": [],
	},
	"market_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"MK_Market": "res://assets/village_v2/market_kit/MK_Market.tres",
		},
		"assembler": "res://tools/village_v2_market_lib.gd",
		"extra": ["/market_kit_atlas.png", "/atlas.json"],
	},
	"street_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"ST_Street": "res://assets/village_v2/street_kit/ST_Street.tres",
		},
		"assembler": "res://tools/village_v2_street_lib.gd",
		"extra": ["/street_kit_atlas.png", "/atlas.json"],
	},
	"humanuse_exp_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"ST_Street": "res://assets/village_v2/street_kit/ST_Street.tres",
		},
		"assembler": "res://tools/village_v2_human_use_exp_lib.gd",
		"extra": [],
	},
	"humanuse_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"ST_Street": "res://assets/village_v2/street_kit/ST_Street.tres",
		},
		"assembler": "res://tools/village_v2_human_use_lib.gd",
		"extra": [],
	},
	"mise_kit": {
		"mats": {
			"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres",
			"V2_Kawara": "res://assets/village_v2/_matlib/V2_Kawara.tres",
			"MK_Market": "res://assets/village_v2/market_kit/MK_Market.tres",
			"ST_Street": "res://assets/village_v2/street_kit/ST_Street.tres",
		},
		"assembler": "res://tools/village_v2_market_west_lib.gd",
		"extra": [],
	},
	"bamboo_kit": {
		"mats": {},   # 由 village_v2_bamboo_lib.gd material_paths() 填
		"assembler": "res://tools/village_v2_bamboo_lib.gd",
		"extra": ["/tex/bamboo_tex.json"],
	},
}
const VegLib := preload("res://tools/village_v2_veg_lib.gd")
const BambooLib := preload("res://tools/village_v2_bamboo_lib.gd")

var KIT := "machiya_kit"
var DIR := "res://assets/village_v2/machiya_kit"
var MATS: Dictionary = {}
var fails := 0


func _fail(s: String) -> void:
	fails += 1
	printerr("[kit-prefab] FAIL ", s)


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--kit="):
			KIT = a.substr(6)
	if not KITS.has(KIT):
		_fail("未知 Kit %s" % KIT)
		quit(1)
		return
	DIR = "res://assets/village_v2/" + KIT
	MATS = KITS[KIT]["mats"]
	if KIT == "veg_kit":
		for e: String in VegLib.make_materials():
			_fail(e)
		MATS = VegLib.material_paths()
	elif KIT == "bamboo_kit":
		for e: String in BambooLib.make_materials():
			_fail(e)
		MATS = BambooLib.material_paths()
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/src/modules_blender.json"))
	if not man is Dictionary:
		_fail("讀不到 modules_blender.json")
		quit(1)
		return
	var mods: Dictionary = man["modules"]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + "/src/%s.glb" % KIT), st)
	if err != OK:
		_fail("GLTF 讀取失敗：%s" % error_string(err))
		quit(1)
		return
	var gl_root: Node = doc.generate_scene(st)
	var found := {}
	for n in gl_root.find_children("*", "", true, false):
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is ImporterMeshInstance3D:
			m = (n as ImporterMeshInstance3D).mesh.get_mesh()
		if m != null:
			found[String(n.name)] = [m, (n as Node3D).transform]
	var mats := {}
	for k: String in MATS:
		mats[k] = load(MATS[k])
		if mats[k] == null:
			_fail("材質讀不到 %s" % MATS[k])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/mesh"))
	for old in DirAccess.get_files_at(DIR + "/mesh"):
		if old.ends_with(".res") and not mods.has(old.get_basename()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/mesh/" + old))
	var mesh_paths: Array = []
	var total := 0
	var id := 0
	for name: String in mods:
		if not found.has(name):
			_fail("GLB 缺構件 %s" % name)
			continue
		var src: Mesh = found[name][0]
		if not (found[name][1] as Transform3D).is_equal_approx(Transform3D.IDENTITY):
			_fail("%s transform 不是 identity" % name)
		var am := ArrayMesh.new()
		var tris := 0
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var mat: Material = src.surface_get_material(si)
			var mname := mat.resource_name if mat != null else ""
			if not mats.has(mname):
				_fail("%s surface %d 材質「%s」不在白名單" % [name, si, mname])
				continue
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			am.surface_set_name(am.get_surface_count() - 1, mname)
			am.surface_set_material(am.get_surface_count() - 1, mats[mname])
		am.resource_name = {"machiya_kit": "kit_", "riverbank_kit": "rb_kit_", "veg_kit": "veg_", "bamboo_kit": "bk_", "garden_kit": "gk_kit_", "school_kit": "sk_kit_", "waterside_kit": "wk_kit_", "tower_kit": "tk_kit_", "suzu_kit": "sz_kit_", "geidon_kit": "gd_kit_", "kiri_kit": "kr_kit_", "market_kit": "mk_kit_", "street_kit": "st_kit_", "mise_kit": "ms_kit_", "humanuse_kit": "hu_kit_", "humanuse_exp_kit": "hx_kit_"}[KIT] + name
		var bt := int(mods[name]["tris"])
		if tris != bt:
			_fail("%s 三角面 Godot %d ≠ Blender %d" % [name, tris, bt])
		total += tris
		var mp := DIR + "/mesh/%s.res" % name
		var e2 := ResourceSaver.save(am, mp, ResourceSaver.FLAG_COMPRESS)
		if e2 != OK:
			_fail("存 %s：%s" % [mp, error_string(e2)])
		mesh_paths.append(mp)
		id += 1
	for extra: String in found:
		if not mods.has(extra):
			_fail("GLB 多出未登記構件 %s" % extra)
	print("[kit-prefab] %d 構件、%d 三角面（Blender %d）→ %s/mesh/" % [id, total, int(man["total_tris"]), DIR])
	var deps := mesh_paths + [String(KITS[KIT]["assembler"])]
	if KIT == "veg_kit":
		var r: Dictionary = VegLib.make_prefabs(man, DIR + "/mesh")
		for e: String in r["errs"]:
			_fail(e)
		deps += r["paths"]
		print("[kit-prefab] 樹 prefab %d 棵 → %s" % [(r["paths"] as Array).size(), VegLib.TREE_DIR])
		var tm := VegLib.tex_meta()
		for f: String in tm.get("files_sha256", {}):
			deps.append(f)
	elif KIT == "bamboo_kit":
		var r: Dictionary = BambooLib.make_prefabs(man, DIR + "/mesh")
		for e: String in r["errs"]:
			_fail(e)
		deps += r["paths"]
		print("[kit-prefab] 竹 prefab %d 種 → %s" % [(r["paths"] as Array).size(), BambooLib.TREE_DIR])
		for f: String in BambooLib.tex_meta().get("files_sha256", {}):
			deps.append(f)
		# shader 重用 veg_kit（只讀）：也進依賴雜湊，veg shader 若被改動 → 竹 gate 失效
		for f: String in ["/veg_common.gdshaderinc", "/veg_leaf.gdshader", "/veg_bark.gdshader"]:
			deps.append("res://assets/village_v2/veg_kit" + f)
		deps.append("res://tools/village_v2_veg_lib.gd")
	for ex: String in KITS[KIT]["extra"]:
		deps.append(DIR + ex)
	deps.append(DIR + "/src/modules_blender.json")
	for k: String in MATS:
		deps.append(MATS[k])
	var dsha := {}
	for dp: String in deps:
		dsha[dp] = FileAccess.get_sha256(dp)
		if String(dsha[dp]) == "":
			_fail("manifest 依賴讀不到 %s" % dp)
	var mf := FileAccess.open(DIR + "/%s_manifest.json" % KIT, FileAccess.WRITE)
	mf.store_string(JSON.stringify({"asset": KIT, "modules": id, "tris_total": total,
		"assembler": KITS[KIT]["assembler"], "mesh_dir": DIR + "/mesh", "deps": dsha}, " ", true) + "\n")
	mf.close()
	print("[kit-prefab] manifest %d 依賴 → %s/%s_manifest.json" % [deps.size(), DIR, KIT])
	gl_root.free()
	print("[kit-prefab] 結果：%d 項失敗" % fails)
	quit(fails)
