extends SceneTree
## P13 Wave 4：神社參道の撮影ハーネス（正式 main.tscn → F5 経路〔ReviewStart〕→ village_v2、実際の玩家と TPS 相機、10:00、Forward+）。
##   godot --path . --script res://tools/p13/shot_w4.gd -- <outdir/> <mode> <views>
##   mode  ：r8＝現行（試作 overlay SandoPilotW4P13 があれば enabled=false）／w4＝試作 overlay を enabled=true
##   views ：カンマ区切り。下の VIEWS の名前（例 up_s47,up_s54,walk_down_s64,high_a）／all／debug（デバッグ疊層なしと有りの比較）
## 玩家視角：玩家を参道の中心線上（s＝出発点〔一の鳥居側 s0〕からの弧長 m）へ置き、向きを上り（+s）または下り（−s）に。
##   up：玩家は静止、相機は既定（pitch −0.18）で背後（下側）。walk：玩家が実際の入力（move_forward）で下りながら、目標 s に達した瞬間に撮影＝動的相機〔下り坂バイアス〕が効いた状態。
## 再現性：Input.mouse_mode＝VISIBLE（実機のマウス捕捉で pitch がずれない）、pitch＝既定 −0.18、動的相機〔_slope_bias〕には触れない。場景ファイルは書かない。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const W5 := preload("res://tools/village_v2_sando_w5a_lib.gd")
const OVR := "SandoPilotW4P13"
const DEF_PITCH := -0.18
const VIEWS := {
	# 名前：[種別, s, 追加]   種別 up／walk（s＝撮影する位置、追加＝歩き出し s）／free（pos, target, fov は別表）
	"up_s43": ["up", 43.0],
	"up_s53": ["up", 53.0],
	"up_s58": ["up", 58.0],
	"up_s47": ["up", 47.0],
	"up_s52": ["up", 52.0],
	"up_s56": ["up", 56.0],
	"up_s61": ["up", 61.0],
	"up_s66": ["up", 66.0],
	"walk_down_s64": ["walk", 64.0, 72.0],
	"walk_down_s56": ["walk", 56.0, 62.0],
	"walk_down_s46": ["walk", 46.0, 52.0],
	"top_s101": ["up", 100.0],
	"top_dn_s100": ["down", 100.0],
	"top_dn_s96": ["down", 96.0],
	"top_dn_s92": ["down", 92.0],
}

## 近接のフリーカメラ視点：名前 → [カメラ s, 横 lat, 地面からの高さ h, 注視 s, 注視 lat, 注視 h, fov]（lat＝中心線の左法線方向 m、s＝中心線の弧長 m）
## P13 W5A（s≈59–64.2 m の石垣と土坡）の鏡位
const W5_TPS := ["up_s53", "up_s56", "up_s58"]
const W5_CLOSE := ["w5_wallR", "w5_wallL", "w5_baseR", "w5_highR", "w5_highL", "w5_landR"]
const CLOSE := {
	"w5_wallR": [57.2, 4.4, 1.4, 61.0, 1.35, 0.5, 55.0],
	"w5_wallL": [57.2, -4.4, 1.4, 61.0, -1.35, 0.5, 55.0],
	"w5_baseR": [60.0, 3.1, 0.85, 61.2, 1.3, 0.35, 48.0],
	"w5_highR": [54.5, 6.8, 5.8, 60.8, 0.9, 0.4, 55.0],
	"w5_highL": [54.5, -6.8, 5.8, 60.8, -0.9, 0.4, 55.0],
	"w5_landR": [67.5, 3.6, 2.4, 63.6, 1.2, 0.6, 55.0],
	"cl_wallR_s60": [56.5, 4.5, 1.7, 60.0, 1.4, 0.4, 55.0],
	"cl_wallL_s46": [43.5, -4.0, 1.6, 46.5, -1.4, 0.2, 55.0],
	"cl_treads_s40": [36.0, 0.0, 2.4, 41.5, 0.0, 0.3, 50.0],
	"cl_land2": [66.5, 2.5, 3.5, 62.5, 0.0, 0.5, 55.0],
	"cl_toe_R_s56": [53.5, 3.4, 1.0, 56.5, 1.6, 0.1, 50.0],
}

var main: Node
var player: CharacterBody3D
var vil: Node3D
var adapter: Node
var cl: PackedVector2Array
var out := ""
var mode := "r8"


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, settle := 10) -> void:
	await _frames(settle)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("SHOT ", name)


func _ground(p: Vector2) -> float:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -30.0, p.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	return float((r["position"] as Vector3).y) if not r.is_empty() else NAN


func _s_of(pos: Vector3) -> float:
	var best := INF
	var bk := 0
	var p := Vector2(pos.x, pos.z)
	for k in range(0, cl.size(), 2):
		var d := p.distance_squared_to(cl[k])
		if d < best:
			best = d
			bk = k
	return bk * 0.05


func _fix_camera() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	adapter.set("_target_pitch", DEF_PITCH)
	adapter.set("_current_pitch", DEF_PITCH)


## 玩家を中心線 s に置き face 方向を向かせる。相機は pivot を瞬間移動（8 m 超の差は snap）→ 背後に回る
func _tp(s: float, up: bool, lateral := 0.0) -> void:
	Input.action_release("move_forward")
	var k := clampi(int(round(s / 0.05)), 0, cl.size() - 1)
	var t := SA.tangent(cl, k)
	var face := t if up else -t
	var nrm := Vector2(-t.y, t.x)
	var p := cl[k] + nrm * lateral
	var gy := _ground(p)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, gy + 0.1, p.y)
	player.call("snap_yaw", atan2(-face.x, -face.y))
	_fix_camera()
	await _frames(4)
	for i in 40:
		await physics_frame
	await _frames(20)


func _walk_capture(name: String, s_target: float, s_from: float) -> void:
	await _tp(s_from, false)
	_fix_camera()
	Input.action_press("move_forward")
	var t0 := Time.get_ticks_msec()
	var bias_max := 0.0
	while true:
		await physics_frame
		bias_max = minf(bias_max, float(adapter.call("slope_bias")) if adapter.has_method("slope_bias") else 0.0)
		var s := _s_of(player.global_position)
		if s <= s_target or Time.get_ticks_msec() - t0 > 40000:
			break
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("SHOT %s s=%.2f 下り坂バイアス %.3f 腕長 %.2f 玩家 %s" % [name, _s_of(player.global_position), float(adapter.call("slope_bias")) if adapter.has_method("slope_bias") else 0.0, (adapter.get("arm") as SpringArm3D).get_hit_length(), str(player.global_position)])
	Input.action_release("move_forward")
	await _frames(30)


var _fc: Camera3D


## 洋紅〜紫（色相 265–345°・彩度 > 0.35・明度 > 0.35）の画素数。受光後の洋紅は RGB≈(150,65,146) まで暗くなる（固定 RGB 門檻は漏れる）。
## 玩家の赤橙の外套〔色相 ≈ 10–25°〕とは区別できる。2 画素おきの標本 ×4 で概数
func _magenta_count() -> int:
	var img := root.get_texture().get_image()
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.s > 0.35 and c.v > 0.35 and c.h >= 265.0 / 360.0 and c.h <= 345.0 / 360.0:
				n += 1
	return n * 4


func _reload_trail() -> void:
	main.call("load_map", "village_v2", "")
	var fr := 0
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		fr += 1
		if fr > 3 and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 30000:
			break
	for i in 90:
		await physics_frame
	vil = main.get("map_root") as Node3D
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	print("[W4S] trail 経路で村を読み直した（ReviewStart の hide_debug は効いていない）：map_root=%s" % vil.name)


## base 画素の洋紅がどの節点に由来するかを二分的に掘る（直下の子を 1 つずつ隠す → 寄与のあった子だけさらに掘る、最大 4 階層）
func _mag_drill(node: Node, base: int, depth: int) -> void:
	for ch in node.get_children():
		if not (ch is Node3D):
			continue
		var n3 := ch as Node3D
		if not n3.visible:
			continue
		n3.visible = false
		await _frames(5)
		await RenderingServer.frame_post_draw
		var c2 := _magenta_count()
		n3.visible = true
		var contrib := base - c2
		if contrib > maxi(8, base / 20):
			print("[W4S]   %s%s を隠す → %d（寄与 %d）" % ["  ".repeat(depth), String(vil.get_path_to(n3)), c2, contrib])
			if depth < 4 and n3.get_child_count() > 0:
				await _mag_drill(n3, base, depth + 1)


## ── 診断（exp）：同じ鏡位で「黒の出どころ」の候補を 1 つずつ外して撮る。lib の旗〔W4.flags〕と実行時の設定だけで変える（場景は書かない）──
var _ov: Node3D
var _exp_in := {}


func _exp_prepare() -> void:
	_ov = vil.get_node_or_null(OVR) as Node3D
	var sp := vil.get_world_3d().direct_space_state
	var H := SA.ramp_profile(vil, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var kr := W4.pilot_k_range(st)
	W5.setup(vil, sp, cl)
	var lanterns := []
	for ls in SA.lantern_specs(cl, H, st, sp):
		var s_l := float(ls["s"])
		if s_l >= kr.x * 0.05 - 2.0 and s_l <= kr.y * 0.05 + 2.0 and not lanterns.has(s_l):
			lanterns.append(s_l)
	_exp_in = {"H": H, "plan": W4.replan(cl, H, st, rp),
		"touts": [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)],
		"tfars": [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)], "lanterns": lanterns}


func _exp_apply(vname: String) -> void:
	var f := {}
	var vcol := true
	var shadow := true
	var self_shadow := true
	var ssao := true
	var soil_red := false
	var diag := false
	var soil_hide := false
	var ssao_k := 1.0
	var on := true
	match vname:
		"r8":
			on = false
		"no_decals":
			f = {"no_decals": true}
		"r0":
			f = {"r_scale": 0.05}
		"bed_up":
			f = {"bed_off": 0.012}
		"no_vcol":
			vcol = false
		"no_shadow":
			shadow = false
		"no_selfshadow":
			self_shadow = false
		"w4b":
			f = {"w5a": false}
		"w5a":
			f = {}
		"diag":
			f = {"diag_color": true}
			diag = true
		"soil_red":
			soil_red = true
		"no_soil":
			soil_hide = true
		"no_ssao":
			ssao = false
		"ssao_half":
			ssao_k = 0.5
		"all_off_ssao":
			f = {"no_decals": true, "r_scale": 0.05, "bed_off": 0.012}
			vcol = false
			ssao = false
		"all_off":
			f = {"no_decals": true, "r_scale": 0.05, "bed_off": 0.012}
			vcol = false
	W4.flags = f
	_ov.set("enabled", on)
	if on:
		var ms := W4.build_meshes(cl, _exp_in["H"], _exp_in["plan"], _exp_in["touts"], _exp_in["tfars"], _exp_in["lanterns"])
		var mi := _ov.get_node("W4Steps") as MeshInstance3D
		if _steps_mat0 == null:
			_steps_mat0 = mi.material_override
		mi.mesh = ms["steps"]
		(mi.material_override as StandardMaterial3D).vertex_color_use_as_albedo = vcol
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if self_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if diag:
			var dm := StandardMaterial3D.new()
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dm.vertex_color_use_as_albedo = true
			dm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = dm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _steps_mat0 != null:
			mi.material_override = _steps_mat0
		var so := _ov.get_node_or_null("W4Soil") as MeshInstance3D
		if so != null and _soil_mat0 == null:
			_soil_mat0 = so.material_override
		if so != null and ms["soil"] != null:
			so.mesh = ms["soil"]
			so.visible = not soil_hide
			so.material_override = _soil_mat0
			if soil_red or diag:
				var rm := StandardMaterial3D.new()
				rm.albedo_color = Color(1.0, 0.0, 0.0) if soil_red else Color(1.0, 1.0, 0.0)
				rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				so.material_override = rm
	for l in vil.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = shadow
	W4.flags = {}
	var pn := _ov.get_node_or_null("W5Plants") as Node3D
	if pn != null:
		pn.visible = on and vname != "w4b"                 # W5A の草叢は W4B 比較では隠す
	# 環境光遮蔽：エンジンが生きている環境〔Camera3D の environment か WorldEnvironment〕へ。診断だけ（場景は書かない）
	for env in _envs():
		if not _ssao0.has(env):
			_ssao0[env] = [env.ssao_enabled, env.ssao_intensity]
		var o: Array = _ssao0[env]
		env.ssao_enabled = ssao and bool(o[0])
		env.ssao_intensity = float(o[1]) * ssao_k


var _ssao0 := {}
var _soil_mat0: Material = null
var _steps_mat0: Material = null


func _envs() -> Array:
	var out := []
	for we in vil.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var e := (we as WorldEnvironment).environment
		if e != null and not out.has(e):
			out.append(e)
	var cam := vil.get_viewport().get_camera_3d()
	if cam != null and cam.environment != null and not out.has(cam.environment):
		out.append(cam.environment)
	return out


func _rel(s: float, lat: float, h: float) -> Vector3:
	var k := clampi(int(round(s / 0.05)), 0, cl.size() - 1)
	var t := SA.tangent(cl, k)
	var p := cl[k] + Vector2(-t.y, t.x) * lat
	return Vector3(p.x, _ground(p) + h, p.y)


func _free_begin() -> void:
	_fc = Camera3D.new()
	_fc.far = 1200.0
	root.add_child(_fc)
	_fc.make_current()
	player.visible = false


func _free(name: String, pos: Vector3, target: Vector3, fov := 55.0) -> void:
	_fc.fov = fov
	_fc.global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3(0, 0, -1))
	await _shot(name, 12)


func _free_end() -> void:
	player.visible = true
	_fc.queue_free()
	await _frames(2)
	var pc := player.find_child("Camera3D", true, false) as Camera3D
	if pc:
		pc.make_current()


func _boot() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		vil = root.find_child("VillageV2", true, false) as Node3D
		if player and vil and player.is_on_floor() and vil.get_node_or_null("Collision/TerrainCollision") != null:
			break
		if Time.get_ticks_msec() - t0 > 120000:
			push_error("boot timeout")
			quit(2)
			return
	for i in 120:
		await physics_frame
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	print("[W4S] boot %d ms・玩家 %s・hour %s・renderer %s" % [Time.get_ticks_msec() - t0, str(player.global_position), str(dn.get("hour")) if dn else "?", RenderingServer.get_current_rendering_method()])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	mode = args[1] if args.size() > 1 else "r8"
	var want: PackedStringArray = (args[2] if args.size() > 2 else "all").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	var ov := vil.get_node_or_null(OVR)
	if ov != null:
		ov.set("enabled", mode == "w4")
		await _frames(8)
	print("[W4S] mode=%s overlay=%s" % [mode, ("あり enabled=%s" % ov.get("enabled")) if ov else "なし"])
	for nm: String in VIEWS:
		if not ("all" in want or nm in want):
			continue
		var v: Array = VIEWS[nm]
		match String(v[0]):
			"up":
				await _tp(float(v[1]), true)
				await _shot(nm)
			"down":
				await _tp(float(v[1]), false)
				await _shot(nm)
				print("[W4S]   %s 洋紅画素 %d" % [nm, _magenta_count()])
			"walk":
				await _walk_capture(nm, float(v[1]), float(v[2]))
	var cnames: Array = []
	for nm: String in CLOSE:
		if "close" in want or nm in want:
			cnames.append(nm)
	if not cnames.is_empty():
		await _free_begin()
		for nm: String in cnames:
			var c: Array = CLOSE[nm]
			await _free(nm, _rel(float(c[0]), float(c[1]), float(c[2])), _rel(float(c[3]), float(c[4]), float(c[5])), float(c[6]))
		await _free_end()
	if "high_a" in want or "all" in want:
		# 参道全体の高視角：村側（下）から斜め上空で山頂を見る
		await _free_begin()
		var k1 := int(round(38.0 / 0.05))
		var k2 := int(round(68.0 / 0.05))
		var mid := (cl[k1] + cl[k2]) * 0.5
		var tg := Vector3(mid.x, _ground(mid) + 1.0, mid.y)
		var tt := SA.tangent(cl, int(round(53.0 / 0.05)))
		var nn := Vector2(-tt.y, tt.x)
		var base := mid - tt * 24.0 + nn * 6.0
		await _free("high_a", Vector3(base.x, _ground(base) + 26.0, base.y), tg, 50.0)
		var side := mid + nn * 34.0
		await _free("high_b", Vector3(side.x, _ground(side) + 30.0, side.y), tg, 50.0)
		await _free_end()
	if "debug" in want:
		# 洋紅の帯の調査用：頂上の玩家視角をデバッグ疊層の有無で比較（ReviewStart の隠し対象を一時的に戻す／隠す）
		await _tp(99.0, false)
		await _shot("top_default")
	if "mag_scan" in want:
		# 洋紅の帯の来歴（P11 R2 の経路〔--start=trail：load_map で村を読み直す＝ReviewStart の hide_debug が効かない〕を再現）：
		# 当時の位置（s≈97.6、下り向き）で洋紅画素を数え、vil の直下の子を 1 つずつ隠して寄与を測り、寄与のあった節点は子へ掘り下げる
		await _reload_trail()
		var lm0 := vil.get_node_or_null("Districts/LandmarkParcelLines") as Node3D
		print("[W4S] 正式ロード後の Districts/LandmarkParcelLines：%s・visible=%s・is_visible_in_tree=%s" % ["あり" if lm0 != null else "なし", str(lm0.visible) if lm0 != null else "-", str(lm0.is_visible_in_tree()) if lm0 != null else "-"])
		for spot: float in [97.6, 99.0]:
			await _tp(spot, false)
			await _shot("mag_trail_s%d" % int(round(spot)))
			var base2 := _magenta_count()
			print("[W4S] trail 経路 s=%.1f：洋紅画素 %d" % [spot, base2])
			if base2 > 0:
				await _mag_drill(vil, base2, 0)
	if "w5" in want:
		await _exp_prepare()
		var wvars: PackedStringArray = (args[3] if args.size() > 3 else "w4b,w5a").split(",")
		for vn: String in wvars:
			_exp_apply(vn)
			await _frames(8)
			for tv: String in W5_TPS:
				await _tp(float(VIEWS[tv][1]), true)
				await _shot("w5_%s__%s" % [vn, tv])
			await _free_begin()
			for cn: String in W5_CLOSE:
				var c: Array = CLOSE[cn]
				await _free("w5_%s__%s" % [vn, cn], _rel(float(c[0]), float(c[1]), float(c[2])), _rel(float(c[3]), float(c[4]), float(c[5])), float(c[6]))
			await _free_end()
			print("[W4S] w5 %s 撮影完了" % vn)
	if "exp" in want:
		await _exp_prepare()
		var variants: PackedStringArray = (args[3] if args.size() > 3 else "base,r8,no_decals,r0,bed_up,no_vcol,no_shadow,all_off").split(",")
		for vn: String in variants:
			_exp_apply(vn)
			await _frames(8)
			for tv: String in ["up_s43", "up_s61"]:
				await _tp(float(VIEWS[tv][1]), true)
				await _shot("exp_%s__%s" % [vn, tv])
			await _free_begin()
			for cn: String in ["cl_treads_s40", "cl_land2"]:
				var c: Array = CLOSE[cn]
				await _free("exp_%s__%s" % [vn, cn], _rel(float(c[0]), float(c[1]), float(c[2])), _rel(float(c[3]), float(c[4]), float(c[5])), float(c[6]))
			await _free_end()
			print("[W4S] exp %s 撮影完了" % vn)
	if "traj" in want:
		# 実入力（move_forward）で試作区間を上り→下りに歩き、全物理フレームの位置を積算：r8（overlay OFF）と w4（ON）で同じなら
		# 歩行・Auto-Step 0.35 m・碰撞・通行は何も変わっていない
		for dir: String in ["up", "down"]:
			var s0 := 34.0 if dir == "up" else 67.0
			var s1 := 66.0 if dir == "up" else 35.0
			await _tp(s0, dir == "up")
			Input.action_press("move_forward")
			var n := 0
			var chk := 0.0
			var max_dy := 0.0
			var prev_y := player.global_position.y
			var lost := 0
			var t0 := Time.get_ticks_msec()
			while true:
				await physics_frame
				n += 1
				var pp := player.global_position
				if n % 4 == 1:
					# 経路追従：前方 2 m の中心線の点へ向きを合わせる（相機補間の描画負荷依存＝非決定性が長い歩行で増幅するのを防ぐ）
					var kc := clampi(int(round(_s_of(pp) / 0.05)), 0, cl.size() - 1)
					var kt := clampi(kc + (40 if dir == "up" else -40), 0, cl.size() - 1)
					var dv := cl[kt] - Vector2(pp.x, pp.z)
					if dv.length() > 0.2:
						dv = dv.normalized()
						player.call("snap_yaw", atan2(-dv.x, -dv.y))
						adapter.set("_target_pitch", DEF_PITCH)
						adapter.set("_current_pitch", DEF_PITCH)
				chk += pp.x * 1.0 + pp.y * 3.0 + pp.z * 7.0
				max_dy = maxf(max_dy, absf(pp.y - prev_y))
				prev_y = pp.y
				if not player.is_on_floor():
					lost += 1
				var sx := _s_of(pp)
				if (dir == "up" and sx >= s1) or (dir == "down" and sx <= s1) or Time.get_ticks_msec() - t0 > 45000:
					break
			Input.action_release("move_forward")
			print("[W4S] traj %s mode=%s：%d フレーム・最大 |Δy|/フレーム %.4f m・接地を失ったフレーム %d・位置の積算 %.4f・終点 %s" % [dir, mode, n, max_dy, lost, chk, str(player.global_position)])
			await _frames(20)
	if "mag_ab" in want:
		# 洋紅の帯：ReviewStart 経路のまま、同じ位置〔通常経路で 5 万 px だった s=97.6／99.0 と、その前後〕で Districts/LandmarkParcelLines を OFF／ON して直接比較
		var lm := vil.get_node_or_null("Districts/LandmarkParcelLines") as Node3D
		var was_vis := lm.visible
		for spot: float in [92.0, 96.0, 97.6, 99.0, 100.0]:
			await _tp(spot, false)
			lm.visible = false
			await _frames(8)
			await RenderingServer.frame_post_draw
			var c_off := _magenta_count()
			lm.visible = true
			await _frames(8)
			await RenderingServer.frame_post_draw
			var c_on := _magenta_count()
			await _shot("mag_ab_on_s%s" % str(spot).replace(".", "_"), 2)
			print("[W4S] mag_ab s=%.1f 玩家 %s：LandmarkParcelLines OFF → %d px／ON → %d px" % [spot, str(player.global_position), c_off, c_on])
		lm.visible = was_vis
	if "mag_bisect" in want:
		# 洋紅の帯の来歴：ReviewStart が隠す疊層（Debug／QuestAnchors／各 ParcelLines）を戻して頂上の下り視点で洋紅を数え、1 つずつ隠して寄与を測る
		var cands: Array = []
		for pth: String in ["Debug", "QuestAnchors", "Portals", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines"]:
			var nd := vil.get_node_or_null(pth) as Node3D
			if nd:
				cands.append(nd)
		var dd := vil.get_node_or_null("Districts")
		if dd:
			for n in dd.find_children("*ParcelLines*", "", true, false):
				if not cands.has(n):
					cands.append(n)
		var was: Array = []
		for n: Node3D in cands:
			was.append(n.visible)
			n.visible = true
		print("[W4S] mag_bisect 候補 %d 個：%s" % [cands.size(), ", ".join(cands.map(func(n: Node) -> String: return String(vil.get_path_to(n))))])
		for spot: float in [100.0, 96.0, 92.0]:
			await _tp(spot, false)
			await _shot("mag_on_s%d" % int(spot))
			var base := _magenta_count()
			print("[W4S]   s=%.0f 疊層すべて表示：洋紅画素 %d" % [spot, base])
			if base > 0:
				for n: Node3D in cands:
					n.visible = false
					await _frames(6)
					await RenderingServer.frame_post_draw
					var c2 := _magenta_count()
					print("[W4S]     %s を隠す → %d（寄与 %d）" % [String(vil.get_path_to(n)), c2, base - c2])
					n.visible = true
		for i in cands.size():
			(cands[i] as Node3D).visible = was[i]
	print("[DONE]")
	quit(0)
