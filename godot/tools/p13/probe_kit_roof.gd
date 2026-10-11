extends SceneTree
## P13 W1（只讀）：町家 Kit 屋根／牆構件的材質、AABB、UV 範圍；_mi 的 LOD 可見距離設定。
const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")

func _init() -> void:
	var lib := KLib.load_lib()
	for nm in ["rf_550_4_p38_t1", "rf_550_4", "vg_550_p38_t1", "gbh_550_p38_c2", "rg_u_t1", "oni_b_t1", "l_rh_t1", "l_roof", "kemu_t1", "dmr_p45", "his_4_t1", "hisw_4", "f1_shop_o_182_h29", "f1_door_182_h29", "f1_amado_182_h29", "u_plain_182_29", "base", "l_box"]:
		var m: Mesh = lib.get(nm)
		if m == null:
			print("[KR] 無 ", nm)
			continue
		var s := ""
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			var a := m.surface_get_arrays(i)
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for u in uv:
				mn = mn.min(u)
				mx = mx.max(u)
			s += " | s%d %s tris %d uv %s..%s" % [i, mat.resource_path if mat else "null", (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else -1, mn, mx]
		print("[KR] %s aabb %s%s" % [nm, m.get_aabb(), s])
	var shop := 0
	for k: String in lib:
		if k.begins_with("f1_") and k.ends_with("_h29") and not k.contains("_c"):
			shop += 1
	print("[KR] f1_*_h29 基本變體 %d：%s" % [shop, ", ".join(lib.keys().filter(func(k: String) -> bool: return k.begins_with("f1_") and k.contains("_182_h29") and not k.contains("_c")))])
	var g := Node3D.new()
	var mi := KLib._mi(g, lib, "rf_550_4", Transform3D.IDENTITY, 1)
	print("[KR] _mi lod1 vis %s–%s margin %s mode %s" % [mi.visibility_range_begin, mi.visibility_range_end, mi.visibility_range_end_margin, mi.visibility_range_fade_mode])
	g.free()
	quit(0)
