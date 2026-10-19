extends SceneTree
## Wind V2 效能版：共用風場貼圖（gw_field）正確性驗證——需要真實視窗（headless 不跑 GPU）。
##   Godot_v4.7.2-stable_win64_console.exe --path godot --resolution 640x360 --script res://tools/wind/wind_field_verify.gd
## 用與植被頂點著色器相同的 wf_tex() 取樣路徑（在 canvas shader 裡）讀回 GPU 值，對照 CPU 解析式：
##   F1 方向／m（方塊 0）  F2 闊葉高木 trunk／crown（方塊 1，含行進陣風與樹冠彈簧）  F3 竹子（方塊 3）
##   F4 方向沒有上下顛倒（翻轉 y 的誤差必須遠大於正確方向）  F5 範圍外夾邊、不是 0
##   F6 關風後停止重算  F7 生成成本（貼圖開／關 GPU 時間差）
## 容許誤差：雙線性內插（格距 2 m）＋RGBA16F。任何 FAIL → quit(1)。

const N_IMG := 96
var fails := 0


func _init() -> void:
	_run.call_deferred()


func _ok(c: bool, m: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + m)
	if not c:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _probe_vp() -> Array:
	var vp := SubViewport.new()
	vp.size = Vector2i(N_IMG, N_IMG)
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.size = Vector2(N_IMG, N_IMG)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://assets/shaders/wind_field.gdshaderinc"
uniform vec4 region;
void fragment() {
	vec2 p = region.xy + SCREEN_UV * region.z;
	COLOR = wf_tex(region.w, p);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	vp.add_child(r)
	root.add_child(vp)
	return [vp, mat]


func _read(vp: SubViewport, mat: ShaderMaterial, region: Vector4) -> Image:
	mat.set_shader_parameter("region", region)
	await _frames(3)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func _cpu_m(w: Node, p: Vector2) -> float:
	var t: float = w.get("_time")
	var lv: float = w.get_local_variation()
	var n1 := 0.5 + 0.5 * sin(p.dot(w.FIELD_K1) + t * 0.11)
	var n2 := 0.5 + 0.5 * sin(p.dot(w.FIELD_K2) + t * 0.07)
	return (1.0 + lv * w.FIELD_STR_A1 * (n1 - 0.5)) * (1.0 + lv * w.FIELD_STR_A2 * (n2 - 0.5))


func _cmp_tree(w: Node, img: Image, region: Vector4, sp: String, comp: int, flip := false) -> Array:
	# env＝1：根部 y＝海拔參考、樹高讓 0.7·h＝z0（剖面 ×1）、沒有遮蔽
	var vp: Vector4 = w.get_vertical_profile()
	var h := vp.y / 0.7
	var errs := PackedFloat32Array()
	var mags := PackedFloat32Array()
	for j in range(2, N_IMG, 5):
		for i in range(2, N_IMG, 5):
			var p := Vector2(region.x + (i + 0.5) / N_IMG * region.z, region.y + (j + 0.5) / N_IMG * region.z)
			var c := img.get_pixel(i, N_IMG - 1 - j if flip else j)
			var cpu: Dictionary = w.sample_vegetation(Vector3(p.x, vp.z, p.y), sp, h)
			var gpu_t := c.b
			var gpu_c := c.a
			errs.append(absf(gpu_t - float(cpu["trunk"])))
			errs.append(absf(gpu_c - float(cpu["crown"])))
			mags.append(absf(float(cpu["crown"])))
	errs.sort()
	mags.sort()
	return [errs[int(errs.size() * 0.95)], errs[errs.size() - 1], mags[mags.size() - 1]]


func _run() -> void:
	var w := root.get_node("Wind")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(37.0, 20.0, -21.0)
	cam.make_current()
	w.set_preset(3)
	await _frames(30)
	# 一道正在通過探測區的行進陣風（前緣、尾流、樹冠過衝都在區內）
	w.trigger_gust(1.0, 4.0, Vector3(10.0, 0.0, -40.0))
	for i in 150:
		await process_frame
	w.set_frozen(true)
	await _frames(4)
	var fi: Dictionary = w.field_info()
	print("field ", fi)
	var pv := _probe_vp()
	var vp: SubViewport = pv[0]
	var mat: ShaderMaterial = pv[1]
	# 探測區：相機周圍 80 m（場的有效範圍內）
	var region := Vector4(cam.global_position.x - 40.0, cam.global_position.z - 40.0, 80.0, 0.0)

	print("\n[F1] 方塊 0：風向／m")
	var img0 := await _read(vp, mat, region)
	var bd: Vector3 = w.wind_direction()
	var base_ang := atan2(bd.z, bd.x)
	var e_ang := 0.0
	var e_m := 0.0
	for j in range(2, N_IMG, 5):
		for i in range(2, N_IMG, 5):
			var p := Vector2(region.x + (i + 0.5) / N_IMG * region.z, region.y + (j + 0.5) / N_IMG * region.z)
			var c := img0.get_pixel(i, j)
			var f: Dictionary = w.sample_field(Vector3(p.x, 0.0, p.y))
			var a_cpu := float(f["angle"])
			# 方塊 0＝(aoff, m, trunk, crown)：風向＝主風向＋aoff
			e_ang = maxf(e_ang, absf(wrapf(base_ang + c.r - a_cpu, -PI, PI)))
			e_m = maxf(e_m, absf(c.g - _cpu_m(w, p)))
	_ok(rad_to_deg(e_ang) < 1.0 and e_m < 0.01, "GPU 貼圖 vs CPU 解析式：風向最大誤差 %.3f°、m 最大誤差 %.4f" % [rad_to_deg(e_ang), e_m])

	print("\n[F2] 方塊 0：闊葉高木 trunk／crown（行進陣風通過中）")
	var img1 := img0
	var r1 := _cmp_tree(w, img1, region, "broad_tall", 0)
	_ok(float(r1[2]) > 0.3 and float(r1[0]) < 0.03 and float(r1[1]) < 0.08,
		"驅動力誤差 p95 %.4f、最大 %.4f（驅動力最大 %.2f）" % [r1[0], r1[1], r1[2]])

	print("\n[F3] 方塊 4：竹子（陣風＋較軟的彈簧）")
	region.w = 4.0
	var img3 := await _read(vp, mat, region)
	var r3 := _cmp_tree(w, img3, region, "bamboo", 0)
	_ok(float(r3[0]) < 0.03 and float(r3[1]) < 0.08, "驅動力誤差 p95 %.4f、最大 %.4f" % [r3[0], r3[1]])

	print("\n[F4] 上下方向")
	var r1f := _cmp_tree(w, img1, region, "broad_tall", 0, true)
	_ok(float(r1f[0]) > 4.0 * float(r1[0]) + 0.01, "y 翻轉後誤差 p95 %.4f ≫ 正確方向 %.4f（貼圖沒有上下顛倒）" % [r1f[0], r1[0]])

	print("\n[F5] 範圍外夾邊")
	var span: float = fi["span"]
	var far_region := Vector4(cam.global_position.x + span, cam.global_position.z - 40.0, 80.0, 0.0)
	var imgf := await _read(vp, mat, far_region)
	var c_far := imgf.get_pixel(N_IMG / 2, N_IMG / 2)
	_ok(absf(c_far.r) < 0.6 and c_far.g > 0.5,
		"相機外 %.0f m：aoff %.3f、m %.3f（夾到邊緣格，遠樹不會吃到 0 而靜止）" % [span, c_far.r, c_far.g])

	print("\n[F6] 關風停止重算")
	w.set_frozen(false)
	w.set_enabled(false)
	for i in 600:
		await process_frame
		if not bool(w.field_info()["active"]):
			break
	_ok(not bool(w.field_info()["active"]), "關風淡出後 SubViewport 停止更新（active=%s）" % str(w.field_info()["active"]))
	w.set_enabled(true)
	await _frames(10)
	_ok(bool(w.field_info()["active"]), "開風後恢復更新")

	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
