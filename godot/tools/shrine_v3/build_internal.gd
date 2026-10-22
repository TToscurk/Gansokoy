extends SceneTree
## 博麗神社 v3：內部資產（樹以外；使用者 2026-10-22 同意）轉成本圖用的 mesh。
## 來源：獸道 S01 套件地被 assets/beast_path/s01_kit/glb/*.glb（Blender build_s01_kit.py；只讀）。
## 幾何沿用；材質沿用 tools/beast_path/s01_dress.gd 的 veg_mat（meadow_grass.gdshader → Wind 自動接成 grass 物種）。
## 輸出 assets/shrine_v3/mesh/int/<名>.res（LOD1 另存 <名>_lod1.res）。
##   godot --headless --path godot --script res://tools/shrine_v3/build_internal.gd

const S01 := preload("res://tools/beast_path/s01_dress.gd")
const DST := "res://assets/shrine_v3/mesh/int/"
## [GLB 名, veg_mat 類別, 淡出起, 淡出終, 有無 LOD1]
const ITEMS := [
	["s01_fern_a", "fern_big", 44.0, 56.0, true], ["s01_fern_b", "fern", 44.0, 56.0, true],
	["s01_fern_c", "fern_big", 44.0, 56.0, true], ["s01_fern_d", "fern_small", 40.0, 50.0, true],
	["s01_forb_a", "forb", 36.0, 46.0, true], ["s01_forb_b", "forb", 30.0, 40.0, false],
	["s01_fuki_a", "herb", 36.0, 46.0, true], ["s01_fuki_b", "herb", 36.0, 46.0, true],
	["s01_herb_broad_a", "herb", 36.0, 46.0, true],
	["s01_sasa_a", "sasa", 44.0, 56.0, true], ["s01_sasa_b", "sasa", 44.0, 56.0, true],
	["s01_sedge_a", "sedge", 40.0, 52.0, true], ["s01_shadegrass_a", "shadegrass", 32.0, 42.0, true],
	["s01_grass_tall_a", "grass_tall", 40.0, 52.0, true], ["s01_grass_tall_b", "grass_tall", 40.0, 52.0, true],
	["s01_grass_tall_c", "grass_tall", 40.0, 52.0, true], ["s01_grass_short_a", "grass_short", 32.0, 42.0, true],
	["s01_grass_short_b", "grass_short", 32.0, 42.0, true],
	["s01_litter_a", "litter", 30.0, 40.0, false], ["s01_litter_b", "litter", 30.0, 40.0, false],
	["s01_moss_a", "moss", 30.0, 40.0, false], ["s01_twigs_a", "twigs", 20.0, 28.0, false],
	["s01_shrub_a", "shrub", 60.0, 75.0, false], ["s01_shrub_b", "shrub", 60.0, 75.0, false],
]


func _init() -> void:
	_run.call_deferred()


func _mesh(glb_name: String, mat: Material) -> ArrayMesh:
	var a: Dictionary = S01.glb(glb_name)
	if a.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["V"]
	arr[Mesh.ARRAY_NORMAL] = a["N"]
	arr[Mesh.ARRAY_COLOR] = a["C"]
	arr[Mesh.ARRAY_TEX_UV] = a["UV"]
	arr[Mesh.ARRAY_TEX_UV2] = a["UV2"]
	arr[Mesh.ARRAY_INDEX] = a["I"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	m.resource_name = "shrine_v3_int_" + glb_name
	return m


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var fails := 0
	for it in ITEMS:
		var nm := String(it[0])
		var mat := S01.veg_mat(String(it[1]), [float(it[2]), float(it[3])])
		var names := [nm]
		if bool(it[4]):
			names.append(nm + "_lod1")
		for n2 in names:
			var m := _mesh(String(n2), mat)
			if m == null:
				push_error("[INT] 讀不到 %s" % n2)
				fails += 1
				continue
			var e := ResourceSaver.save(m, DST + String(n2) + ".res")
			var ab := m.get_aabb()
			print("[INT] %-22s save=%d tris=%d aabb.pos=%s size=%s" % [n2, e, m.surface_get_array_index_len(0) / 3, ab.position, ab.size])
			if e != OK:
				fails += 1
	print("[INT] done fails=%d" % fails)
	quit(1 if fails > 0 else 0)
