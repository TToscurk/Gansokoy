extends SceneTree
## S04 地表權重探針（離線、秒級）：重算 bp_lib.ground_channels()，印戰鬥圓內的組成，輸出分類俯視圖。
##   godot --headless --path godot --script res://tools/beast_path/probe_ground.gd -- --out=<png>
## 需要先跑過一次 generate_beast_path.gd（它把 canopy／rock_d 場存在 user://beast_path_gctx.bin）。
const BP := preload("res://tools/beast_path/bp_lib.gd")


func _initialize() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var f := FileAccess.open("user://beast_path_gctx.bin", FileAccess.READ)
	if f == null:
		print("沒有 user://beast_path_gctx.bin：先跑 generate_beast_path.gd")
		quit(2)
		return
	var ctx := {}
	for key: String in ["canopy", "rock_d"]:
		var n := f.get_32()
		ctx[key] = f.get_buffer(n * 4).to_float32_array()
	f.close()
	var c0 := lib.arena_c()
	# --- 組成（r ≤ 20，1 m 格）
	var n_in := 0
	var acc := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])      # dirt(trodden+mud) grass leaf stone moss wet mud
	var rb := {}                                              # 每 2 m 環帶的泥土占比（看有沒有一圈一圈的人工感）
	for iz in range(int(lib._iz(c0.y - 21.0)), int(lib._iz(c0.y + 21.0)) + 1):
		for ix in range(int(lib._ix(c0.x - 21.0)), int(lib._ix(c0.x + 21.0)) + 1):
			var x := lib.lx0 + float(ix) * lib.cell
			var z := lib.lz0 + float(iz) * lib.cell
			var r := Vector2(x, z).distance_to(c0)
			if r > 20.0:
				continue
			var g := lib.ground_channels(ix, iz, ctx)
			var tot := g[0] + g[1] + g[2] + g[3] + g[4]
			n_in += 1
			acc[0] += g[0] + g[2]
			acc[1] += maxf(1.0 - tot, 0.0)
			acc[2] += g[4]
			acc[3] += g[1] + g[3]
			acc[4] += g[6]
			acc[5] += g[5]
			acc[6] += g[2]
			var band := int(r / 4.0)
			if not rb.has(band):
				rb[band] = [0, 0.0, 0.0]
			rb[band][0] += 1
			rb[band][1] += g[0] + g[2]
			rb[band][2] += maxf(1.0 - tot, 0.0)
	var inv := 1.0 / float(n_in)
	print("[GROUND] 戰鬥圓 %d 格：泥土(壓實+濕泥) %.1f%%（其中濕泥 %.1f%%）｜草 %.1f%%｜落葉 %.1f%%｜礫+岩 %.1f%%｜苔均值 %.3f｜濕度均值 %.3f" % [n_in, acc[0] * inv * 100, acc[6] * inv * 100, acc[1] * inv * 100, acc[2] * inv * 100, acc[3] * inv * 100, acc[4] * inv, acc[5] * inv])
	var ks := rb.keys()
	ks.sort()
	var line := "[GROUND] 泥土／草 隨半徑(每4m)："
	for k in ks:
		line += "  r%d-%d: %.0f%%/%.0f%%" % [int(k) * 4, int(k) * 4 + 4, float(rb[k][1]) / float(rb[k][0]) * 100.0, float(rb[k][2]) / float(rb[k][0]) * 100.0]
	print(line)
	if out == "":
		quit(0)
		return
	# --- 分類俯視圖：北上、5 px/m，x −55…55、z −466…−340
	var ppm := 5
	var x0 := -55.0
	var x1 := 55.0
	var z0 := -466.0
	var z1 := -340.0
	var W := int((x1 - x0) * ppm)
	var H := int((z1 - z0) * ppm)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var cols: Array[Color] = [Color("8c6b46"), Color("9d9a92"), Color("453626"), Color("56627a"), Color("b9772f")]    # trodden gravel mud rock leaf
	var grass_c := Color("6f9238")
	var moss_c := Color("2c8f3e")
	for py in H:
		for px in W:
			var x := x0 + (float(px) + 0.5) / float(ppm)
			var z := z0 + (float(py) + 0.5) / float(ppm)
			var fx := lib._ix(x)
			var fz := lib._iz(z)
			var ix := int(floor(fx))
			var iz := int(floor(fz))
			var u := fx - float(ix)
			var v := fz - float(iz)
			var ga := lib.ground_channels(ix, iz, ctx)
			var gb := lib.ground_channels(ix + 1, iz, ctx)
			var gc := lib.ground_channels(ix, iz + 1, ctx)
			var gd := lib.ground_channels(ix + 1, iz + 1, ctx)
			var gg := PackedFloat32Array()
			gg.resize(8)
			for k in 8:
				gg[k] = lerpf(lerpf(ga[k], gb[k], u), lerpf(gc[k], gd[k], u), v)
			var rem := maxf(1.0 - (gg[0] + gg[1] + gg[2] + gg[3] + gg[4]), 0.0)
			var col: Color = cols[0] * gg[0] + cols[1] * gg[1] + cols[2] * gg[2] + cols[3] * gg[3] + cols[4] * gg[4] + grass_c * rem
			col = col.lerp(moss_c, clampf(gg[6], 0.0, 1.0) * 0.55)
			col = col * (1.0 - 0.35 * gg[5])
			col.a = 1.0
			var r := Vector2(x, z).distance_to(c0)
			if absf(r - 20.0) < 0.12 or absf(r - 22.0) < 0.08:
				col = col.lerp(Color.WHITE, 0.55)
			img.set_pixel(px, py, col)
	img.save_png(out)
	print("[GROUND] → ", out)
	quit(0)
