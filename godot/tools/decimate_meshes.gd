extends SceneTree
## 網格減面：讀 .res / ArrayMesh，用 Godot 內建的 ImporterMesh.generate_lods()
## （meshoptimizer 簡化器）產生低模，覆寫存回原路徑。
##
## 為什麼用 ImporterMesh 而不是 gltfpack：這些網格是 gen_river_vegetation.gd
## 從 photoscan 烤出來的 Godot 資源（材質已調過 ALPHA_SCISSOR 0.22、雙面），
## 不是 glTF。走 gltfpack 要重跑整條產生器，會覆蓋掉調過的場景。
## 直接減面 .res 則場景檔一行都不用動。
##
## 原檔備份到 <name>.orig.res（已存在就不覆蓋，可重複執行）。
##
##   Godot --headless --path godot --script tools/decimate_meshes.gd -- <target> [--dry]
##     target: river | trees | all
const TARGETS := {
	# 路徑 → 目標保留比例（越小越省）
	"river": [
		["res://maps/slice/gen/ph_shrub_0.res", 0.06],
		["res://maps/slice/gen/ph_nettle_0.res", 0.25],
		["res://maps/slice/gen/ph_nettle_1.res", 0.25],
		["res://maps/slice/gen/ph_periwinkle_0.res", 0.30],
		["res://maps/slice/gen/ph_periwinkle_1.res", 0.30],
		["res://maps/slice/gen/ph_periwinkle_2.res", 0.30],
		["res://maps/slice/gen/ph_periwinkle_3.res", 0.30],
		["res://maps/slice/gen/ph_periwinkle_4.res", 0.30],
		["res://maps/slice/gen/ph_periwinkle_5.res", 0.30],
		["res://maps/slice/gen/ph_rock_0.res", 0.25],
		["res://maps/slice/gen/ph_rock_1.res", 0.25],
		["res://maps/slice/gen/ph_rock_2.res", 0.25],
		["res://maps/slice/gen/ph_rock_3.res", 0.25],
		["res://maps/slice/gen/ph_rock_4.res", 0.25],
		["res://maps/slice/gen/ph_rock_5.res", 0.25],
		["res://maps/slice/gen/ph_fern_0.res", 0.40],
		["res://maps/slice/gen/ph_fern_1.res", 0.40],
	],
	"trees": [
		["res://maps/slice/gen/tree_普通樹.res", 0.22],
		["res://maps/slice/gen/tree_大衫.res", 0.22],
		["res://maps/slice/gen/tree_2大衫.res", 0.22],
		["res://maps/slice/gen/tree_針葉樹1.res", 0.22],
		["res://maps/slice/gen/tree_針葉樹2glb.res", 0.22],
		["res://maps/slice/gen/tree_針葉林樹3.res", 0.22],
		["res://maps/slice/gen/tree_針葉林樹4.res", 0.22],
		["res://maps/slice/gen/tree_盆樹.res", 0.22],
		["res://maps/slice/gen/tree_櫻花樹.res", 0.22],
	],
}

var dry := false


func _init() -> void:
	_run.call_deferred()


func _tris(m: ArrayMesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var il := m.surface_get_array_index_len(s)
		t += (il / 3) if il > 0 else (m.surface_get_array_len(s) / 3)
	return t


## 用 ImporterMesh 產生 LOD 鏈，挑「三角形數最接近目標比例」的那一階，
## 拿它的 index 陣列（指向同一份頂點）當新的主網格。
func _decimate(src: ArrayMesh, ratio: float) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in src.get_surface_count():
		if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s), [], {},
			src.surface_get_material(s), src.surface_get_name(s), src.surface_get_format(s))
	# generate_lods(normal_merge_angle, normal_split_angle, bone_transform_array)
	# ⚠ 4.7 是三參數版；只給兩個會 parse error。
	# photoscan 葉片法線雜亂，合併角度放小會拒絕簡化、減面幾乎沒效果。
	im.generate_lods(60.0, 60.0, [])
	var out := ArrayMesh.new()
	for s in im.get_surface_count():
		var arrays := im.get_surface_arrays(s)
		var base_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var want := int(base_idx.size() * ratio)
		var best := base_idx
		var lods := im.get_surface_lod_count(s)
		for l in lods:
			var li := im.get_surface_lod_indices(s, l)
			if li.size() >= want and li.size() < best.size():
				best = li
			elif best.size() == base_idx.size() and li.size() < base_idx.size():
				best = li
		# 全部 LOD 都比 want 小時，取最大的那個（別減過頭）
		if best.size() < want:
			for l in lods:
				var li2 := im.get_surface_lod_indices(s, l)
				if li2.size() >= want:
					best = li2
					break
		arrays[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, im.get_surface_material(s))
		out.surface_set_name(out.get_surface_count() - 1, im.get_surface_name(s))
	return out


func _run() -> void:
	var target := "all"
	for a in OS.get_cmdline_user_args():
		if a == "--dry":
			dry = true
		else:
			target = a
	var jobs: Array = []
	for k in TARGETS.keys():
		if target == "all" or target == k:
			jobs.append_array(TARGETS[k])
	var before := 0
	var after := 0
	for j in jobs:
		var path: String = j[0]
		var ratio: float = j[1]
		if not ResourceLoader.exists(path):
			print("[DEC] 缺檔 %s" % path)
			continue
		# 一律從備份讀（第一次執行時先建），可重複跑而不會越減越爛
		var orig_path := path.replace(".res", ".orig.res")
		if not FileAccess.file_exists(ProjectSettings.globalize_path(orig_path)) \
				and not ResourceLoader.exists(orig_path):
			var cur := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
			if not dry:
				ResourceSaver.save(cur, orig_path, ResourceSaver.FLAG_COMPRESS)
		var src := ResourceLoader.load(orig_path if ResourceLoader.exists(orig_path) else path,
			"", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if src == null:
			print("[DEC] 讀不到 %s" % path)
			continue
		var t0 := _tris(src)
		var dst := _decimate(src, ratio)
		var t1 := _tris(dst)
		before += t0
		after += t1
		print("[DEC] %-44s %7d → %-7d (%4.1f%%) 目標%.0f%%%s"
			% [path.replace("res://maps/slice/gen/", ""), t0, t1,
			100.0 * float(t1) / maxf(1.0, float(t0)), ratio * 100.0, "  [dry]" if dry else ""])
		if not dry:
			var err := ResourceSaver.save(dst, path, ResourceSaver.FLAG_COMPRESS)
			if err != OK:
				print("[DEC] ✗ 存檔失敗 %s (%d)" % [path, err])
	print("[DEC] 合計（單株）%d → %d，減少 %.1f%%"
		% [before, after, 100.0 * (1.0 - float(after) / maxf(1.0, float(before)))])
	quit(0)
