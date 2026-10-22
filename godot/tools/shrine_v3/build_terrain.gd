extends SceneTree
## 由 gen_terrain.py 的輸出建出 Godot 資源（maps/shrine_v3/gen/）：
##   terrain_near.res / terrain_mid.res / terrain_far.res   ArrayMesh
##   terrain_near_col.res                                   ConcavePolygonShape3D（與近景網格同一組三角形）
##   mask_a.res / mask_b.res                                地表混合遮罩 ImageTexture（*.rgba → 含 mipmap、不壓縮）
## godot --headless --path godot --script res://tools/shrine_v3/build_terrain.gd
## 任何輸入缺檔一律 quit(1)（不讓 headless 卡在錯誤上）。

const S3 := preload("res://tools/shrine_v3/s3lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for nm in ["terrain_near", "terrain_mid", "terrain_far"]:
		if not FileAccess.file_exists(S3.GEN + nm + ".bin"):
			push_error("缺 %s.bin（先跑 gen_terrain.py）" % nm)
			quit(1)
			return
		var m := S3.load_grid_mesh(S3.GEN + nm + ".bin")
		m.resource_name = "shrine_v3_" + nm
		var e := S3.save_retry(m, S3.GEN + nm + ".res")
		print("[TERRAIN] %s.res err=%d aabb=%s verts=%d" % [nm, e, m.get_aabb(), m.surface_get_array_len(0)])
		if nm == "terrain_near":
			var sh := m.create_trimesh_shape()
			sh.resource_name = "shrine_v3_terrain_near_col"
			var e2 := S3.save_retry(sh, S3.GEN + "terrain_near_col.res")
			print("[TERRAIN] terrain_near_col.res err=%d faces=%d" % [e2, sh.get_faces().size() / 3])
	for nm in ["mask_a", "mask_b", "mask_c"]:
		if not FileAccess.file_exists(S3.GEN + nm + ".rgba"):
			push_error("缺 %s.rgba（先跑 gen_terrain.py）" % nm)
			quit(1)
			return
		var mf := FileAccess.open(S3.GEN + nm + ".rgba", FileAccess.READ)
		var wh := mf.get_buffer(8).to_int32_array()
		var img := Image.create_from_data(wh[0], wh[1], false, Image.FORMAT_RGBA8, mf.get_buffer(wh[0] * wh[1] * 4))
		mf.close()
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		tex.resource_name = "shrine_v3_" + nm
		var e3 := S3.save_retry(tex, S3.GEN + nm + ".res")
		print("[TERRAIN] %s.res err=%d size=%s" % [nm, e3, img.get_size()])
	print("[TERRAIN] done (%d ms)" % (Time.get_ticks_msec() - t0))
	quit()
