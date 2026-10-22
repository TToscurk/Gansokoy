extends SceneTree
## 博麗神社 v3 植被光照診斷（非 headless）。同一棵櫻（sakura_yama_v3_c_000）、固定時刻（--hour）、固定攝影機、風關閉。
##   godot --path godot --resolution 1600x900 --script <本檔> -- --hour=10.5 --out=<資料夾> [--mode=draft|full] [--variants=a,b]
## 每個視角輸出：
##   final_<v>_<view>.png   正常畫面（變體 v：base 或單一因素關閉）
##   light_<v>_<view>.png   線性畫面（線性 tonemap、曝光 0.25、無霧無 glow；DEBUG_DRAW_LIGHTING 會丟掉葉卡 alpha，不能用）
##                          分析時 光照係數＝線性亮度×4／反照率
##   albedo_<view>.png      只看反照率（DEBUG_DRAW_UNSHADED、線性 tonemap、曝光 1）
##   mask_<view>.png        分類（無光照純色）：目標櫻葉 紅／目標樹幹 綠／其他樹葉 黃／其他樹幹 青／下層植被與地被 橘／
##                          岩石 洋紅／建築與道具 白／地形 藍／參道石段 紫
##   ndl_<view>.png         目標櫻葉：R＝N·L×0.5＋0.5（匯出的樹冠法線）、G＝頂點 AO（COLOR.r）
## 另寫 views.json：攝影機、太陽方向、樹的位置與樹冠半徑、樹下地面圓在畫面上的投影點。

const S3 := preload("res://tools/shrine_v3/s3lib.gd")
const TARGET := "sakura_yama_v3_c_000"

const SH_MASK := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 mcol = vec3(1.0);
void fragment() {
	ALBEDO = mcol;
}
"""
const SH_MASK_A := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 mcol = vec3(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut = 0.45;
void fragment() {
	ALBEDO = mcol;
	ALPHA = texture(albedo_tex, UV).a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
"""
const SH_NDL := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut = 0.45;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
varying vec3 wn;
void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float ndl = dot(normalize(wn), normalize(sun_dir));
	ALBEDO = vec3(ndl * 0.5 + 0.5, COLOR.r, 1.0);
	ALPHA = texture(albedo_tex, UV).a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
"""

var cam: Camera3D
var map: Node
var out := ""
var sky: Node
var env: Environment
var sun: DirectionalLight3D
var target: MeshInstance3D
var env_snap := {}
var frames := 40
var geoms: Array = []
var saved := {}
var sh_mask: Shader
var sh_mask_a: Shader
var sh_ndl: Shader
var leaf_mats: Array = []


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _walk(n: Node, acc: Array) -> void:
	if n is GeometryInstance3D:
		acc.append(n)
	for c in n.get_children():
		_walk(c, acc)


func _snap_env() -> void:
	for k in ["tonemap_mode", "tonemap_exposure", "glow_enabled", "fog_enabled", "volumetric_fog_enabled", "adjustment_enabled",
			"ssao_enabled", "ambient_light_energy"]:
		env_snap[k] = env.get(k)


func _restore_env() -> void:
	for k in env_snap:
		env.set(k, env_snap[k])
	sun.visible = true
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED


## 只還原後製（tonemap／曝光／glow／霧／調色）與除錯模式；不碰環境光、太陽、SSAO（變體正在用）
func _post_restore() -> void:
	for k in ["tonemap_mode", "tonemap_exposure", "glow_enabled", "fog_enabled", "volumetric_fog_enabled", "adjustment_enabled"]:
		env.set(k, env_snap[k])
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED


func _neutral(exposure: float) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = exposure
	env.glow_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false


func _shot(path: String) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _group(g: GeometryInstance3D) -> String:
	if g == target:
		return "target"
	var p := String(map.get_path_to(g))
	var top := p.split("/")[0]
	if top == "樹木" or p.begins_with("石段兩側/小樹"):
		return "tree"
	if top in ["下層植栽", "石段兩側", "境內周邊"] or g is MultiMeshInstance3D:
		return "under"
	if top == "岩石":
		return "rock"
	if top in ["建築", "境內物件"]:
		return "bld"
	if top == "地形":
		return "terrain"
	if top == "參道石段":
		return "paving"
	return ""


const COLS := {
	"target": [Color(1, 0, 0), Color(0, 1, 0)],
	"tree": [Color(1, 1, 0), Color(0, 1, 1)],
	"under": [Color(1, 0.5, 0), Color(1, 0.5, 0)],
	"rock": [Color(1, 0, 1), Color(1, 0, 1)],
	"bld": [Color(1, 1, 1), Color(1, 1, 1)],
	"terrain": [Color(0, 0, 1), Color(0, 0, 1)],
	"paving": [Color(0.5, 0, 1), Color(0.5, 0, 1)],
}


func _orig_mat(g: GeometryInstance3D, i: int) -> Material:
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		var m := mi.get_surface_override_material(i)
		if m == null and mi.mesh != null:
			m = mi.mesh.surface_get_material(i)
		return m
	return null


func _is_leaf(m: Material) -> bool:
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		if sm.shader != null and (sm.shader.resource_path.contains("leaf") or sm.shader.resource_path.contains("meadow")):
			return sm.get_shader_parameter("albedo_tex") != null
	return false


func _mk(col: Color, leaf_src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if leaf_src != null:
		m.shader = sh_mask_a
		m.set_shader_parameter("albedo_tex", (leaf_src as ShaderMaterial).get_shader_parameter("albedo_tex"))
		var ac: Variant = (leaf_src as ShaderMaterial).get_shader_parameter("alpha_cut")
		m.set_shader_parameter("alpha_cut", 0.45 if ac == null else float(ac))
	else:
		m.shader = sh_mask
	m.set_shader_parameter("mcol", Vector3(col.r, col.g, col.b))
	return m


func _apply_masks(ndl_only: bool) -> void:
	saved.clear()
	for g: GeometryInstance3D in geoms:
		var grp := _group(g)
		if grp == "" or (ndl_only and grp != "target"):
			continue
		var rec := {"mo": g.material_override, "so": []}
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null and g.material_override == null:
			var mi := g as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				rec["so"].append(mi.get_surface_override_material(i))
				var om := _orig_mat(g, i)
				var leaf := _is_leaf(om)
				var m: ShaderMaterial
				if ndl_only:
					if not leaf:
						continue
					m = ShaderMaterial.new()
					m.shader = sh_ndl
					m.set_shader_parameter("albedo_tex", (om as ShaderMaterial).get_shader_parameter("albedo_tex"))
					m.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
				else:
					m = _mk(COLS[grp][0] if leaf else COLS[grp][1], om if leaf else null)
				mi.set_surface_override_material(i, m)
		elif not ndl_only:
			g.material_override = _mk(COLS[grp][0], null)
		saved[g] = rec


func _clear_masks() -> void:
	for g: GeometryInstance3D in saved:
		var rec: Dictionary = saved[g]
		g.material_override = rec["mo"]
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			var so: Array = rec["so"]
			for i in so.size():
				mi.set_surface_override_material(i, so[i])
	saved.clear()


func _place(v: Dictionary) -> void:
	cam.fov = float(v["fov"])
	cam.global_position = v["pos"]
	cam.look_at(v["at"], Vector3.UP)


func _variant(name: String, on: bool) -> void:
	# on=true 套用（關掉該因素）、false 還原
	match name:
		"bl0":
			for m: ShaderMaterial in leaf_mats:
				if on:
					m.set_meta("bl", m.get_shader_parameter("translucency"))
					m.set_shader_parameter("translucency", 0.0)
				else:
					m.set_shader_parameter("translucency", m.get_meta("bl"))
		"cn0":
			for m: ShaderMaterial in leaf_mats:
				if on:
					m.set_meta("cn", m.get_shader_parameter("crown_normal"))
					m.set_shader_parameter("crown_normal", 0.0)
				else:
					m.set_shader_parameter("crown_normal", m.get_meta("cn"))
		"spec0":
			for m: ShaderMaterial in leaf_mats:
				if on:
					m.set_meta("sp", m.get_shader_parameter("specular"))
					m.set_shader_parameter("specular", 0.0)
				else:
					m.set_shader_parameter("specular", m.get_meta("sp"))
		"mb0":
			for m: ShaderMaterial in leaf_mats:
				if on:
					m.set_meta("mb", m.get_shader_parameter("alpha_mip_boost"))
					m.set_shader_parameter("alpha_mip_boost", 0.0)
				else:
					m.set_shader_parameter("alpha_mip_boost", m.get_meta("mb"))
		"shlod_old":
			# 葉卡陰影 pass 回到共用版行為（同相機 pass 做 mip alpha 補償 → 陰影圖裡樹冠實心）＝修正前的陰影
			for m: ShaderMaterial in leaf_mats:
				m.set_shader_parameter("shadow_alpha_lod", -1.0 if on else 0.0)
		"fill0":
			# 拿掉本圖的天空補光（maps/shrine_v3/s3_light_profile.gd）＝修正前的環境光
			var fl := root.find_child("天空補光", true, false)
			if fl:
				fl.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
			if on:
				env.ambient_light_sky_contribution = 1.0
		"amb0":
			env.ambient_light_energy = 0.0 if on else float(env_snap["ambient_light_energy"])
		"sun0":
			sun.visible = not on
		"glow0":
			env.glow_enabled = not on and bool(env_snap["glow_enabled"])
		"ssao0":
			env.ssao_enabled = not on and bool(env_snap["ssao_enabled"])
		"vfog0":
			env.volumetric_fog_enabled = not on and bool(env_snap["volumetric_fog_enabled"])
		"shd0":
			target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"tm_lin":
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if on else int(env_snap["tonemap_mode"])


func _run() -> void:
	out = _arg("out", ProjectSettings.globalize_path("user://probe_light"))
	var mode := _arg("mode", "draft")
	frames = int(_arg("frames", "40"))
	DirAccess.make_dir_recursive_absolute(out)
	sh_mask = Shader.new()
	sh_mask.code = SH_MASK
	sh_mask_a = Shader.new()
	sh_mask_a.code = SH_MASK_A
	sh_ndl = Shader.new()
	sh_ndl.code = SH_NDL
	map = (load("res://maps/shrine_v3/shrine_v3.tscn") as PackedScene).instantiate()
	root.add_child(map)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.near = 0.1
	root.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	var wind := root.get_node_or_null("/root/Wind")
	if wind != null:
		wind.call("set_enabled", false)
	for i in 90:
		await process_frame
	sky = map.get_node("天象系統")
	for c in sky.get_children():
		if c is WorldEnvironment:
			env = (c as WorldEnvironment).environment
		if c is DirectionalLight3D and String(c.name) == "太陽":
			sun = c
	sky.process_mode = Node.PROCESS_MODE_DISABLED
	_snap_env()
	target = map.find_child(TARGET, true, false) as MeshInstance3D
	_walk(map, geoms)
	var seen := {}
	for g: GeometryInstance3D in geoms:
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var om := _orig_mat(g, i)
				if _is_leaf(om) and om is ShaderMaterial and (om as ShaderMaterial).shader.resource_path.contains("veg_leaf") and not seen.has(om):
					seen[om] = true
					leaf_mats.append(om)
	# 幾何：樹冠中心、半徑、樹高
	var ab: AABB = target.global_transform * target.mesh.get_aabb()
	var c := ab.get_center()
	var gy := S3.height_at(c.x, c.z)
	var cr := maxf(ab.size.x, ab.size.z) * 0.5
	var H := ab.size.y
	var sd := sun.global_transform.basis.z
	var hs := Vector3(sd.x, 0, sd.z).normalized()
	var pp := Vector3(-hs.z, 0, hs.x)
	var D := maxf(13.0, H * 1.5)
	var at := Vector3(c.x, gy + H * 0.42, c.z)
	var views := {}
	var cand := {"front": [hs, D, 62.0], "back": [-hs, 9.5, 72.0], "side": [-pp, 10.0, 70.0]}
	for k in cand:
		var d: Vector3 = cand[k][0]
		var p := Vector3(c.x, 0, c.z) + d * float(cand[k][1])
		p.y = S3.height_at(p.x, p.z) + 1.7
		views[k] = {"pos": p, "at": at, "fov": float(cand[k][2])}
	var dclose := (hs + pp * 0.8).normalized()
	var pc := Vector3(c.x, 0, c.z) + dclose * (cr + 3.5)
	pc.y = S3.height_at(pc.x, pc.z) + 1.6
	views["close"] = {"pos": pc, "at": Vector3(c.x, gy + H * 0.33, c.z), "fov": 60.0}
	var info := {"tree": [c.x, gy, c.z], "crown_r": cr, "H": H, "sun_dir": [sd.x, sd.y, sd.z],
		"sun_energy": sun.light_energy, "sun_color": [sun.light_color.r, sun.light_color.g, sun.light_color.b],
		"env": {}, "views": {}, "leaf_mats": leaf_mats.size()}
	for k in env_snap:
		info["env"][k] = env_snap[k]
	info["env"]["ambient_source"] = env.ambient_light_source
	info["env"]["ambient_sky_contribution"] = env.ambient_light_sky_contribution
	info["env"]["glow_intensity"] = env.glow_intensity
	info["env"]["glow_hdr_threshold"] = env.glow_hdr_threshold
	info["env"]["glow_bloom"] = env.glow_bloom
	info["env"]["ssao_intensity"] = env.ssao_intensity
	info["env"]["adjustment_saturation"] = env.adjustment_saturation
	info["env"]["fog_density"] = env.fog_density
	info["env"]["volumetric_fog_density"] = env.volumetric_fog_density
	var only := _arg("views", "")
	for k in views:
		if only != "" and not (k in only.split(",")):
			continue
		var v: Dictionary = views[k]
		_place(v)
		await process_frame
		var ring: Array = []
		for j in 24:
			var a := TAU * j / 24.0
			var wp := Vector3(c.x + cos(a) * cr, 0, c.z + sin(a) * cr)
			wp.y = S3.height_at(wp.x, wp.z)
			var sp := cam.unproject_position(wp)
			ring.append([sp.x, sp.y, 1 if cam.is_position_behind(wp) else 0])
		var vp: Vector3 = v["pos"]
		info["views"][k] = {"pos": [vp.x, vp.y, vp.z], "at": [v["at"].x, v["at"].y, v["at"].z], "fov": v["fov"], "ground_ring": ring,
			"root_px": [cam.unproject_position(Vector3(c.x, gy, c.z)).x, cam.unproject_position(Vector3(c.x, gy, c.z)).y]}
	var f := FileAccess.open(out.path_join("views.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	print("[LIGHT] tree=%s crown_r=%.2f H=%.2f sun_dir=%s energy=%.3f amb=%.3f exp=%.3f" % [c, cr, H, sd, sun.light_energy, env.ambient_light_energy, env.tonemap_exposure])
	for k in info["views"]:
		print("[LIGHT] view %s pos=%s" % [k, info["views"][k]["pos"]])
	var vlist: Array = info["views"].keys()
	# 1) 正常畫面
	for k in vlist:
		_place(views[k])
		await _shot(out.path_join("final_base_%s.png" % k))
	if mode == "draft":
		quit()
		return
	# 2) 只看光照／反照率
	for k in vlist:
		_place(views[k])
		_neutral(0.25)
		await _shot(out.path_join("light_base_%s.png" % k))
		_neutral(1.0)
		root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
		await _shot(out.path_join("albedo_%s.png" % k))
		_restore_env()
	# 3) 分類遮罩與葉片 N·L
	for k in vlist:
		_place(views[k])
		_neutral(1.0)
		env.ssao_enabled = false
		_apply_masks(false)
		await _shot(out.path_join("mask_%s.png" % k))
		_clear_masks()
		_apply_masks(true)
		await _shot(out.path_join("ndl_%s.png" % k))
		_clear_masks()
		_restore_env()
	# 4) 單一因素隔離（每次只關一個，從 base 出發）
	var variants := _arg("variants", "bl0,cn0,spec0,amb0,sun0,glow0,ssao0,vfog0,shd0,tm_lin").split(",")
	for vn in variants:
		_variant(vn, true)
		for k in vlist:
			_place(views[k])
			await _shot(out.path_join("final_%s_%s.png" % [vn, k]))
			if vn in ["bl0", "cn0", "sun0", "shd0", "amb0", "mb0", "shlod_old", "fill0"]:
				_neutral(0.25)
				await _shot(out.path_join("light_%s_%s.png" % [vn, k]))
				_post_restore()
		_variant(vn, false)
		_restore_env()
		print("[LIGHT] variant %s done" % vn)
	print("[LIGHT] done")
	quit()
