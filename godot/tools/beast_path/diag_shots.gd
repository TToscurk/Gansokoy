extends "res://tools/beast_path/tps_shots.gd"
## 獸道 S04 診斷擷取（V1.3）：同一鏡位、同一時刻，逐一套用「實驗」拍照，用來隔離畫面問題的來源。不改任何檔案（全部只改記憶體）。
##   godot --path godot --script res://tools/beast_path/diag_shots.gd -- --map=beast_path --out=<dir> [--hour=10] --only=a,b --exps="base|env:fog_sky_affect=0|gdbg=wv"
## 鏡位＝tps_shots.gd 的全部鏡位＋本檔追加（o*＝正交俯視、f1x／t2x＝V1.3 新增）。
## 實驗（一個變體可用 + 串多個；變體之間用 | 分隔；每個變體各拍一張 <鏡位>__<變體序>.png，拍完還原）：
##   base                         不改（對照）
##   env:<屬性>=<值>              main 的 Environment 屬性（值：true／false／數字），例 env:fog_sky_affect=0.2
##   sun:<屬性>=<值>              Main/Sun 的屬性，例 sun:shadow_enabled=false
##   gdbg=<模式>                  S04 地表 shader 診斷：wv 頂點權重色／wb 高度混合後權重色／leaf 落葉層灰階／dirt 壓實土灰階／
##                                tex2 全場強制壓實土貼圖／tex4 強制泥／tex6 強制林床落葉／flatalb 固定灰反照率（只剩法線＋光）／
##                                nonrm 只用幾何法線／nomacro 拿掉巨觀明暗
##   gpar:<uniform>=<值>          S04 地表材質 uniform（例 gpar:bump_amp=0）
##   hide=<子字串,子字串>         隱藏名稱含子字串的節點（或 meta:<鍵>）
##   budget=off                   S04 樹影預算全部還原（對照）

const GROUND_SHADER := "res://assets/beast_path/materials/bp_ground.gdshader"
## V1.2 的微起伏（前向差分，步長 0.30 m）——bumpfix 實驗要替換的原文
const BUMP_OLD := "\t\t\tvec2 e = vec2(0.30, 0.0);\n\t\t\tvec2 q0 = p / 4.6 + vec2(0.13, 0.41);\n\t\t\tvec2 q1 = p / 1.7 + vec2(0.71, 0.29);\n\t\t\tfloat h0 = texture(noise_tex, q0).r * 1.0 + texture(noise_tex, q1).g * 0.35;\n\t\t\tfloat hx = texture(noise_tex, q0 + e.xy / 4.6).r * 1.0 + texture(noise_tex, q1 + e.xy / 1.7).g * 0.35;\n\t\t\tfloat hz = texture(noise_tex, q0 + e.yx / 4.6).r * 1.0 + texture(noise_tex, q1 + e.yx / 1.7).g * 0.35;\n\t\t\tvec3 nbump = normalize(vec3((h0 - hx) / e.x * bump_amp * 3.2, 1.0, (h0 - hz) / e.x * bump_amp * 3.2));\n"
const BUMP_FIX := "\t\t\tconst mat2 BR = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));\n\t\t\tconst float BE = 1.5 / 512.0;\n\t\t\tvec2 q0 = p / 4.6 + vec2(0.13, 0.41);\n\t\t\tvec2 q1 = (BR * p) / 11.0 + vec2(0.71, 0.29);\n\t\t\tvec2 g0 = vec2(texture(noise_tex, q0 + vec2(BE, 0.0)).r - texture(noise_tex, q0 - vec2(BE, 0.0)).r, texture(noise_tex, q0 + vec2(0.0, BE)).r - texture(noise_tex, q0 - vec2(0.0, BE)).r) / (2.0 * BE * 4.6);\n\t\t\tvec2 g1 = vec2(texture(noise_tex, q1 + vec2(BE, 0.0)).r - texture(noise_tex, q1 - vec2(BE, 0.0)).r, texture(noise_tex, q1 + vec2(0.0, BE)).r - texture(noise_tex, q1 - vec2(0.0, BE)).r) / (2.0 * BE * 11.0);\n\t\t\tvec2 g = g0 + (g1 * BR) * 2.2;\n\t\t\tvec3 nbump = normalize(vec3(-g.x * bump_amp * 0.9, 1.0, -g.y * bump_amp * 0.9));\n"
const BUMP_FIX2 := "\t\t\tconst mat2 BRA = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866));\n\t\t\tconst mat2 BRB = mat2(vec2(0.5, -0.866), vec2(0.866, 0.5));\n\t\t\tconst float BE = 1.5 / 512.0;\n\t\t\tvec2 q0 = (BRA * p) / 4.6 + vec2(0.13, 0.41);\n\t\t\tvec2 q1 = (BRB * p) / 11.0 + vec2(0.71, 0.29);\n\t\t\tvec2 g0 = vec2(texture(noise_tex, q0 + vec2(BE, 0.0)).r - texture(noise_tex, q0 - vec2(BE, 0.0)).r, texture(noise_tex, q0 + vec2(0.0, BE)).r - texture(noise_tex, q0 - vec2(0.0, BE)).r) / (2.0 * BE * 4.6);\n\t\t\tvec2 g1 = vec2(texture(noise_tex, q1 + vec2(BE, 0.0)).r - texture(noise_tex, q1 - vec2(BE, 0.0)).r, texture(noise_tex, q1 + vec2(0.0, BE)).r - texture(noise_tex, q1 - vec2(0.0, BE)).r) / (2.0 * BE * 11.0);\n\t\t\tvec2 g = g0 * BRA + (g1 * BRB) * 2.2;\n\t\t\tvec3 nbump = normalize(vec3(-g.x * bump_amp * 0.9, 1.0, -g.y * bump_amp * 0.9));\n"

var _variants: Array = []
var _gmat: ShaderMaterial = null
var _gshader_orig: Shader = null
var _env: Environment = null
var _sun: DirectionalLight3D = null


func _views() -> Array:
	var v: Array = super._views()
	var c0 := lib.arena_c()
	v.append_array([
		# --- 正交俯視（地表條紋的方向性要在「世界座標」量，透視會把地面壓扁成假的橫向條紋）
		{"name": "o01_ground_top_center", "ortho": {"c": [c0.x - 2.0, c0.y + 4.0], "size": 14.0, "above": 30.0}},
		{"name": "o02_ground_top_arena", "ortho": {"c": [c0.x, c0.y], "size": 48.0, "above": 60.0}},
		{"name": "o03_falls_head_top", "ortho": {"c": [-6.0, -451.0], "size": 26.0, "above": 40.0}},
		# --- 瀑布上游：平台上人眼高度沿溪看崖口；側面看崖口；潭邊仰看崖口
		{"name": "f11_head_along_stream", "free": {"cam": [-1.5, 0.0, -462.5], "look": [-8.0, 0.0, -444.0], "cam_above": 2.6, "look_above": 0.0}},
		{"name": "f12_lip_side_east", "free": {"cam": [6.0, 0.0, -447.0], "look": [-8.0, 0.0, -443.5], "cam_above": 3.0, "look_above": 0.2}},
		{"name": "f13_lip_from_pool", "free": {"cam": [-5.0, 0.0, -426.5], "look": [-8.0, 0.0, -441.5], "cam_above": 1.7, "look_above": 20.0}},
		# --- 天空與遠景：戰場中央平視北崖上方／入口回望南方
		{"name": "t21_sky_north", "at": [c0.x, c0.y + 4.0], "face": 350.0, "pitch": 0.22, "dist": 6.0},
		{"name": "t22_sky_south", "at": [c0.x, c0.y - 6.0], "face": 175.0, "pitch": 0.16, "dist": 6.0},
	])
	return v


func _go() -> void:
	var out := ""
	var hour := 10.0
	var only: PackedStringArray = []
	var win := Vector2i(1600, 900)
	var exps := "base"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--exps="):
			exps = a.trim_prefix("--exps=")
		elif a.begins_with("--w="):
			win.x = int(a.trim_prefix("--w="))
		elif a.begins_with("--h="):
			win.y = int(a.trim_prefix("--h="))
	if out == "":
		push_error("需要 --out=<dir>")
		quit(2)
		return
	for vs in exps.split("|"):
		_variants.append(vs.split("+"))
	DirAccess.make_dir_recursive_absolute(out)
	lib = BP.new()
	lib.setup(true, true)
	get_root().size = win
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[DIAG] ✗ 120 秒內沒進到 beast_path")
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var dn := root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
	for _i in 12:
		await process_frame
	var sbn := main.find_child("ShadowBudget", true, false)
	if sbn != null:
		sbn.call("apply", true)
	_env = _active_env()
	_sun = main.get_node_or_null("Sun") as DirectionalLight3D
	var tm := main.find_child("S04_BossClearing", true, false)
	if tm != null:
		var mi := tm.get_node_or_null("TerrainMesh") as MeshInstance3D
		if mi != null and mi.mesh != null:
			_gmat = mi.mesh.surface_get_material(0) as ShaderMaterial
	if _gmat != null:
		_gshader_orig = _gmat.shader
	print("[DIAG] 進圖 OK；hour=%.2f；env=%s（fog=%s density=%.4f sky_affect=%s aerial=%s）；地表材質=%s" % [hour, str(_env != null),
		str(_env.fog_enabled) if _env else "?", _env.fog_density if _env else -1.0, str(_env.get("fog_sky_affect")) if _env else "?",
		str(_env.get("fog_aerial_perspective")) if _env else "?", str(_gmat != null)])
	var gp_cam: Camera3D = player.get_viewport().get_camera_3d()
	var free_cam := Camera3D.new()
	free_cam.fov = 62.0
	free_cam.far = 900.0
	root.add_child(free_cam)
	var n_ok := 0
	for v: Dictionary in _views():
		var nm := String(v["name"])
		if not only.is_empty() and not only.has(nm):
			continue
		_hide_hud()
		free_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		if v.has("ortho"):
			var o: Dictionary = v["ortho"]
			var oc: Array = o["c"]
			var gy := lib.h_at(float(oc[0]), float(oc[1]))
			free_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			free_cam.size = float(o["size"])
			free_cam.global_position = Vector3(float(oc[0]), gy + float(o.get("above", 30.0)), float(oc[1]))
			free_cam.look_at(Vector3(float(oc[0]), gy, float(oc[1])), Vector3(0.0, 0.0, -1.0))
			free_cam.make_current()
			player.visible = false
		elif v.has("free"):
			var fr: Dictionary = v["free"]
			var cm: Array = fr["cam"]
			var lk: Array = fr["look"]
			var cy := lib.h_at(float(cm[0]), float(cm[2])) + float(fr.get("cam_above", 2.0))
			var ly := lib.h_at(float(lk[0]), float(lk[2])) + float(fr.get("look_above", 1.0))
			free_cam.global_position = Vector3(float(cm[0]), cy, float(cm[2]))
			free_cam.look_at(Vector3(float(lk[0]), ly, float(lk[2])))
			free_cam.make_current()
			player.visible = false
		else:
			var q: Vector2
			if v.has("arena"):
				q = lib.arena_pos(float(v["arena"][0]), float(v["arena"][1]))
			else:
				q = Vector2(float(v["at"][0]), float(v["at"][1]))
			await _put(q, -deg_to_rad(float(v["face"])), float(v.get("pitch", -0.18)), float(v.get("dist", 8.5)))
			if gp_cam != null:
				gp_cam.make_current()
			player.visible = true
		var vi := 0
		for parts: PackedStringArray in _variants:
			var undo: Array = []
			var desc := _apply(parts, undo)
			var settle := 70 if vi == 0 else 24
			for i in settle:
				await process_frame
			var img := get_root().get_texture().get_image()
			img.save_png("%s/%s__%d.png" % [out, nm, vi])
			print("  ✓ %-28s v%d [%s]" % [nm, vi, desc])
			for u: Callable in undo:
				u.call()
			vi += 1
			n_ok += 1
	print("[DIAG] 完成 %d 張 → %s" % [n_ok, out])
	quit(0)


func _active_env() -> Environment:
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		return we.environment
	for n in main.find_children("*", "WorldEnvironment", true, false):
		var w2 := n as WorldEnvironment
		if w2.environment != null:
			return w2.environment
	return null


func _val(s: String) -> Variant:
	if s == "true":
		return true
	if s == "false":
		return false
	return float(s)


func _apply(parts: PackedStringArray, undo: Array) -> String:
	var desc: PackedStringArray = []
	for p0 in parts:
		var p := p0.strip_edges()
		if p == "" or p == "base":
			desc.append("base")
			continue
		if p.begins_with("env:") or p.begins_with("sun:") or p.begins_with("gpar:"):
			var kv := p.substr(p.find(":") + 1).split("=")
			var obj: Object = _env if p.begins_with("env:") else (_sun if p.begins_with("sun:") else _gmat)
			if obj == null:
				desc.append("%s(無對象)" % p)
				continue
			if p.begins_with("gpar:"):
				var mat := obj as ShaderMaterial
				var old_g: Variant = mat.get_shader_parameter(kv[0])
				mat.set_shader_parameter(kv[0], _val(kv[1]))
				undo.append(func() -> void: mat.set_shader_parameter(kv[0], old_g))
				desc.append("%s(%s→%s)" % [p, str(old_g), str(mat.get_shader_parameter(kv[0]))])
			else:
				var old: Variant = obj.get(kv[0])
				obj.set(kv[0], _val(kv[1]))
				undo.append(func() -> void: obj.set(kv[0], old))
				desc.append("%s(%s→%s)" % [p, str(old), str(obj.get(kv[0]))])
		elif p.begins_with("gdbg="):
			var mode := p.trim_prefix("gdbg=")
			var sh := _ground_debug(mode)
			if sh == null or _gmat == null:
				desc.append("%s(失敗)" % p)
				continue
			_gmat.shader = sh
			var mref := _gmat
			var orig := _gshader_orig
			undo.append(func() -> void: mref.shader = orig)
			desc.append(p)
		elif p.begins_with("hide="):
			var hidden := _hide_matching(p.trim_prefix("hide=").split(","))
			undo.append(_show_all.bind(hidden))
			desc.append("%s(%d 節點)" % [p, hidden.size()])
		elif p == "budget=off":
			var sbn := main.find_child("ShadowBudget", true, false)
			if sbn != null:
				sbn.call("restore_all")
				undo.append(_rebudget.bind(sbn))
			desc.append(p)
		else:
			desc.append("%s(不認得)" % p)
	return " + ".join(desc)


func _show_all(nodes: Array) -> void:
	for n3: Node3D in nodes:
		n3.visible = true


func _rebudget(sbn: Node) -> void:
	sbn.set_process(true)
	sbn.call("apply", true)


## 由正式 shader 原始碼做出診斷版（字串替換；任何一處替換沒命中就回 null，不拍錯圖）。modes 可用 / 串多個（依序套用）
func _ground_debug(modes: String) -> Shader:
	var code := (load(GROUND_SHADER) as Shader).code
	for mode in modes.split("/"):
		var reps := _dbg_reps(mode)
		if reps.is_empty():
			push_error("gdbg 不認得的模式：" + mode)
			return null
		for r: Array in reps:
			if not code.contains(String(r[0])):
				push_error("gdbg %s：替換目標不在 shader 原始碼裡：%s" % [mode, String(r[0])])
				return null
			code = code.replace(String(r[0]), String(r[1]))
	var sh := Shader.new()
	sh.code = code
	return sh


func _dbg_reps(mode: String) -> Array:
	var reps: Array = []
	const OUT := "	ALBEDO = mix(fb_lin, tex_lin, dk);"
	const WEND := "	w[0] = max(1.0 - s, 0.0);"
	var col_w := "vec3 dc = w[0]*vec3(0.15,0.75,0.15) + w[2]*vec3(1.0,0.55,0.15) + w[3]*vec3(0.55) + w[4]*vec3(0.15,0.30,1.0) + w[5]*vec3(1.0) + w[6]*vec3(0.95,0.05,0.05);"
	var col_b := "vec3 dc = (bw[0]*vec3(0.15,0.75,0.15) + bw[2]*vec3(1.0,0.55,0.15) + bw[3]*vec3(0.55) + bw[4]*vec3(0.15,0.30,1.0) + bw[5]*vec3(1.0) + bw[6]*vec3(0.95,0.05,0.05)) / bsum;"
	var unlit := "	ALBEDO = vec3(0.0); EMISSION = dc * 0.55; ROUGHNESS = 1.0; SPECULAR = 0.0; NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);"
	match mode:
		"wv":
			reps = [[OUT, "	" + col_w + "\n" + unlit]]
		"wb":
			reps = [[OUT, "	" + col_b + "\n" + unlit]]
		"leaf":
			reps = [[OUT, "	vec3 dc = vec3(bw[6] / bsum);\n" + unlit]]
		"dirt":
			reps = [[OUT, "	vec3 dc = vec3(bw[2] / bsum);\n" + unlit]]
		"tex2", "tex4", "tex6", "tex0":
			var li := int(mode.substr(3))
			reps = [[WEND, WEND + "\n	for (int k = 0; k < 7; k++) { w[k] = 0.0; }\n	w[%d] = 1.0;" % li]]
		"flatalb":
			reps = [[OUT, "	ALBEDO = vec3(0.18);"]]
		"nonrm":
			reps = [["	vec3 Nf = normalize(mix(N, nw, dk));", "	vec3 Nf = N;"]]
		"nomacro":
			reps = [["	float macro = mix(0.84, 1.14, nb.r) * mix(0.93, 1.07, nm.r);", "	float macro = 1.0;"]]
		"nrmoff":
			# 關掉各層的法線貼圖（只留微起伏 bump）：配 flatalb 看 bump 自己的光影
			reps = [["	nw = normalize(nw);\n", "	nw = N;\n"]]
		"bumpfix":
			# V1.3 候選修正：中心差分＋1.5 texel 步長、第二層改 R 通道 11 m 尺度並旋轉 37°
			reps = [[BUMP_OLD, BUMP_FIX]]
		"bumpfix2":
			# 候選 2：兩層各自旋轉、相差 90°（R 通道的雲塊略呈橫向拉長，兩層正交相加把殘餘方向性抵掉）
			reps = [[BUMP_OLD, BUMP_FIX2]]
	return reps
