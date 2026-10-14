extends "res://tools/p13/shot_w4.gd"
## P13 Wave 6 共通ハーネス（唯読）：正式 main.tscn → F5 経路〔ReviewStart〕→ village_v2、実際の玩家と TPS 相機、10:00、Forward+。
##   _tpw(pos, face)     ：玩家を世界座標 pos に置き face 方向を向かせる（相機は実際の SpringArm）
##   id_begin()/id_end()：ID パス——全 GeometryInstance3D の material_override を「一意な unshaded 色」に差し替えて撮り、
##                        どの節点がその画素を描いているかを確定する（撮影後に必ず元へ戻す）。
##   cam_record()        ：実際に使われた相機の位置・向き・fov（解析側が世界点を画面へ投影できるように）
## 場景ファイルは書かない。
const ROUTE := "res://tools/walk_p10_final_route.json"

var _idmap := {}
var _id_saved: Array = []
var _env_saved: Array = []
var _vp_saved := {}
var _cam_saved: Array = []
var _id_bits := 5


## 玩家を p に置き face 方向を向かせて落ち着かせる（shot_w4._tp の世界座標版）
func _tpw(p: Vector2, face: Vector2) -> void:
	Input.action_release("move_forward")
	var gy := _ground(p)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, gy + 0.1, p.y)
	player.call("snap_yaw", atan2(-face.x, -face.y))
	_fix_camera()
	await _frames(4)
	for i in 40:
		await physics_frame
	await _frames(20)


## 実際に描画に使われている相機の記録
func cam_record() -> Dictionary:
	var c := root.get_viewport().get_camera_3d()
	if c == null:
		return {}
	var o := c.global_transform.origin
	var e := c.global_transform.basis.get_euler()
	var f := -c.global_transform.basis.z
	return {"cam": [snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001)], "fwd": [snappedf(f.x, 0.0001), snappedf(f.y, 0.0001), snappedf(f.z, 0.0001)], "fov": c.fov, "near": c.near, "far": c.far,
		"proj": int(c.projection), "size": c.size, "player": [snappedf(player.global_position.x, 0.001), snappedf(player.global_position.y, 0.001), snappedf(player.global_position.z, 0.001)]}


## P10 final の歩行路線（wp／tp）を step m ごとに標本化。face＝その区間の進行方向
func route_samples(step: float, only: PackedStringArray = PackedStringArray()) -> Array:
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	var seg := ""
	var polys := {}
	var order: Array = []
	for st: Array in R["route"]:
		match String(st[0]):
			"seg":
				seg = String(st[1])
				polys[seg] = []
				order.append(seg)
			"wp", "tp":
				(polys[seg] as Array).append(Vector2(float(st[1]), float(st[2])))
	var res: Array = []
	for sg: String in order:
		if not only.is_empty() and not (sg in only):
			continue
		var pts: Array = polys[sg]
		var acc := 0.0
		var next_at := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ln := a.distance_to(b)
			if ln < 0.01:
				continue
			while next_at <= acc + ln:
				var t := (next_at - acc) / ln
				res.append({"seg": sg, "pos": a.lerp(b, t), "face": (b - a).normalized(), "s": next_at})
				next_at += step
			acc += ln
	return res


# ───────────────────────── ID パス ─────────────────────────
func _guess_cull(gi: GeometryInstance3D) -> BaseMaterial3D.CullMode:
	var m: Material = gi.material_override
	if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (gi as MeshInstance3D).get_active_material(0)
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		if (m as ShaderMaterial).shader.code.find("cull_disabled") >= 0:
			return BaseMaterial3D.CULL_DISABLED
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).cull_mode
	return BaseMaterial3D.CULL_BACK


func _id_color(n: int) -> Color:
	var sp := 8 if _id_bits == 5 else 4
	var mask := (1 << _id_bits) - 1
	return Color8(((n >> (2 * _id_bits)) & mask) * sp + sp / 2, ((n >> _id_bits) & mask) * sp + sp / 2, (n & mask) * sp + sp / 2)


## 全 GeometryInstance3D（vil 以下）を ID 色へ。戻り値＝節点数。id→パスの表は _idmap。
func id_begin() -> int:
	_idmap.clear()
	_id_saved.clear()
	var all := vil.find_children("*", "GeometryInstance3D", true, false)
	_id_bits = 5 if all.size() < 32000 else 6
	var n := 0
	for g in all:
		var gi := g as GeometryInstance3D
		if gi is GPUParticles3D or gi is CPUParticles3D:
			continue
		if not gi.is_visible_in_tree():
			continue
		if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		n += 1
		_idmap[n] = String(vil.get_path_to(gi))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _id_color(n)
		m.cull_mode = _guess_cull(gi)
		m.disable_fog = true
		_id_saved.append([gi, gi.material_override, gi.transparency])
		gi.material_override = m
		gi.transparency = 0.0
	# 環境：トーンマップ・露出・後処理を外す（unshaded でもトーンマップは掛かる）
	_env_saved.clear()
	for e in _envs():
		var env := e as Environment
		_env_saved.append([env, env.tonemap_mode, env.tonemap_exposure, env.adjustment_enabled, env.glow_enabled, env.ssao_enabled, env.ssil_enabled, env.sdfgi_enabled, env.fog_enabled, env.volumetric_fog_enabled])
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.adjustment_enabled = false
		env.glow_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	_cam_saved.clear()
	var cam := root.get_viewport().get_camera_3d()
	if cam != null:
		_cam_saved.append([cam, cam.attributes])
		cam.attributes = null
	_vp_saved = {"msaa": root.msaa_3d, "ssaa": root.screen_space_aa, "taa": root.use_taa, "dbg": root.use_debanding}
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false
	root.use_debanding = false
	return n


func id_end() -> void:
	for r: Array in _id_saved:
		if is_instance_valid(r[0]):
			(r[0] as GeometryInstance3D).material_override = r[1]
			(r[0] as GeometryInstance3D).transparency = r[2]
	_id_saved.clear()
	for r: Array in _env_saved:
		var env := r[0] as Environment
		env.tonemap_mode = r[1]
		env.tonemap_exposure = r[2]
		env.adjustment_enabled = r[3]
		env.glow_enabled = r[4]
		env.ssao_enabled = r[5]
		env.ssil_enabled = r[6]
		env.sdfgi_enabled = r[7]
		env.fog_enabled = r[8]
		env.volumetric_fog_enabled = r[9]
	_env_saved.clear()
	for r: Array in _cam_saved:
		if is_instance_valid(r[0]):
			(r[0] as Camera3D).attributes = r[1]
	_cam_saved.clear()
	if not _vp_saved.is_empty():
		root.msaa_3d = _vp_saved["msaa"]
		root.screen_space_aa = _vp_saved["ssaa"]
		root.use_taa = _vp_saved["taa"]
		root.use_debanding = _vp_saved["dbg"]
		_vp_saved = {}


func id_table_save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"bits": _id_bits, "map": _idmap}) + "\n")
	f.close()
