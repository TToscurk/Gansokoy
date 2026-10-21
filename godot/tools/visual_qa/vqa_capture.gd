extends SceneTree
## P2 Visual QA 拍攝器（唯讀：不存場景、不匯入資產、不改正式檔案）。
## 由 tools/visual_qa/vqa.py 產生 job.json 後呼叫；需要顯示（不得 --headless：dummy renderer 拍不到）。
##   godot --path godot --resolution 1280x720 --script res://tools/visual_qa/vqa_capture.gd -- --job=<job.json>
## 每個視角拍三張：一般渲染、目標隱藏（遮擋量測）、純色 ID 遮罩（各構件一色、無光照、無霧、無 AA）。
## 影像分析在 Python 端做（numpy），這裡只負責固定條件拍攝＋相機資料。
##
## stage：
##   isolated  審查舞台（固定天空色、固定方向光、灰地面 y=0），GLB 以 GLTFDocument 執行期載入（不匯入）。
##   scene     載入正式場景到記憶體（不存檔），目標＝job.node；時刻固定 10:00。
##   map       正式場景區域俯視＋玩家視角＋地標可見率＋建築腳印/路面侵入事實（arch_spatial_lib）。

const ARCH := preload("res://tools/arch_spatial_lib.gd")
const L_FOCUS := 1 << 17   # 圖層 18：特寫構件
const L_GROUND := 1 << 18  # 圖層 19：審查地面
const L_TARGET := 1 << 19  # 圖層 20：目標建築
const VIEW_DIRS := ["front", "back", "left", "right", "top", "oblique"]

var job: Dictionary = {}
var out_dir := ""
var res := Vector2i(1280, 720)
var settle := 10
var manifest: Dictionary = {"images": [], "errors": [], "notes": []}
var cam: Camera3D
var flat_env: Environment
var flat_attr: CameraAttributesPractical
var target: Node3D
var ground: MeshInstance3D
var parts: Array = []          # [{name, node, color}]
var frame := {}                # O, R(building right), U, F(front)
var box_lo := Vector3.ZERO     # 建築座標 (right, up, front) 的緊貼盒
var box_hi := Vector3.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--job="):
			var txt := FileAccess.get_file_as_string(a.substr(6))
			var j: Variant = JSON.parse_string(txt)
			if j is Dictionary:
				job = j
	_run.call_deferred()


func _die(msg: String) -> void:
	manifest["errors"].append(msg)
	printerr("[VQA] ", msg)
	_save_manifest()
	quit(2)


func _save_manifest() -> void:
	if out_dir == "":
		return
	var f := FileAccess.open(out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(manifest, " "))
		f.close()


func _run() -> void:
	if job.is_empty():
		_die("缺少或讀不到 --job=<json>")
		return
	out_dir = String(job.get("out_dir", ""))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var r: Array = job.get("resolution", [1280, 720])
	res = Vector2i(int(r[0]), int(r[1]))
	settle = int(job.get("settle_frames", 10))
	root.size = res
	manifest["resolution"] = [res.x, res.y]
	manifest["godot"] = Engine.get_version_info()["string"]
	manifest["renderer"] = RenderingServer.get_current_rendering_method()
	manifest["adapter"] = RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name() == "headless":
		_die("headless 沒有真正的渲染器，Visual QA 拍不到（不得 --headless）")
		return
	_make_flat_env()
	# 固定渲染品質（B2）：專案開 TAA（project.godot use_taa=true），TAA 抖動讓同相機重拍像素不同 → 預設關 TAA、改 MSAA 4×。
	# 只改這次執行的 viewport，不改專案設定；job.taa=true 保留專案原設定。
	manifest["project_taa"] = root.use_taa
	if not bool(job.get("taa", false)):
		root.use_taa = false
		root.msaa_3d = Viewport.MSAA_4X
	manifest["aa"] = {"taa": root.use_taa, "msaa_3d": root.msaa_3d, "screen_space_aa": root.screen_space_aa}
	var stage := String(job.get("stage", "isolated"))
	manifest["stage"] = stage
	if stage == "map":
		await _run_map()
		_save_manifest()
		quit(0)
		return
	if stage == "scene":
		if not await _load_scene_target():
			return
	else:
		if not _build_isolated():
			return
	await process_frame
	await process_frame
	_collect_parts()
	if parts.is_empty():
		_die("目標底下沒有可見網格")
		return
	_compute_frame()
	cam = Camera3D.new()
	cam.name = "VQA_Camera"
	root.add_child(cam)
	cam.current = true
	# 暖機：Godot 4.4+ 先用 ubershader 畫、背景編譯專用管線；第一張若太早拍，和之後重拍會有像素差
	_fit_ortho("front")
	for f in int(job.get("warmup_frames", 30)):
		await process_frame
	var views: Array = job.get("views", VIEW_DIRS)
	for v: String in views:
		await _shoot_view(v)
	if bool(job.get("corners", false)):
		for k in 4:
			await _shoot_view("corner%d" % k)
	await _shoot_focus(job.get("focus", []), "")
	for vr: Dictionary in job.get("variants", []):
		await _shoot_variant(vr)
	if bool(job.get("repeat_check", true)) and "front" in views:
		await _shoot_view("front", "_repeat", true)
	_save_manifest()
	print("[VQA] 完成：%d 張影像 → %s" % [manifest["images"].size(), out_dir])
	quit(0)


# ─────────────────────────── 舞台 ───────────────────────────

func _make_flat_env() -> void:
	flat_env = Environment.new()
	flat_env.background_mode = Environment.BG_COLOR
	flat_env.background_color = Color.BLACK
	flat_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	flat_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	flat_env.glow_enabled = false
	flat_env.fog_enabled = false
	flat_env.volumetric_fog_enabled = false
	flat_env.ssao_enabled = false
	flat_env.ssil_enabled = false
	flat_env.ssr_enabled = false
	flat_env.sdfgi_enabled = false
	flat_env.adjustment_enabled = false
	flat_attr = CameraAttributesPractical.new()
	flat_attr.auto_exposure_enabled = false
	flat_attr.exposure_multiplier = 1.0


func _build_isolated() -> bool:
	var stage := Node3D.new()
	stage.name = "VQA_Stage"
	root.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.68, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.85)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = bool(job.get("sun_shadows", true))
	stage.add_child(sun)
	var gy := float(job.get("ground_y", 0.0))
	if bool(job.get("ground", true)):
		ground = MeshInstance3D.new()
		ground.name = "__ground"
		var pm := PlaneMesh.new()
		pm.size = Vector2(400, 400)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.42, 0.42, 0.40)
		gm.roughness = 1.0
		ground.material_override = gm
		ground.position = Vector3(0, gy, 0)
		stage.add_child(ground)
	target = Node3D.new()
	target.name = "Target"
	stage.add_child(target)
	for a: Dictionary in job.get("assets", []):
		var n := _load_asset(String(a["path"]))
		if n == null:
			_die("載入失敗：%s" % a["path"])
			return false
		target.add_child(n)
		if a.has("offset"):
			var o: Array = a["offset"]
			n.position = Vector3(float(o[0]), float(o[1]), float(o[2]))
	var t: Dictionary = job.get("transform", {})
	var s: Array = t.get("scale", [1, 1, 1])
	var p: Array = t.get("origin", [0, 0, 0])
	target.transform = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(float(t.get("yaw", 0.0))), 0))
		.scaled_local(Vector3(float(s[0]), float(s[1]), float(s[2]))), Vector3(float(p[0]), float(p[1]), float(p[2])))
	# 遮擋物（測遮擋偵測用）：灰色方塊，不屬於目標
	for oc: Dictionary in job.get("occluders", []):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz: Array = oc["size"]
		bm.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
		mi.mesh = bm
		var pp: Array = oc["pos"]
		mi.position = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		mi.name = "__occluder"
		stage.add_child(mi)
	manifest["assets"] = job.get("assets", [])
	return true


func _load_asset(path: String) -> Node3D:
	if path.get_extension().to_lower() in ["glb", "gltf"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
		if doc.append_from_file(abs_path, st) != OK:
			return null
		return doc.generate_scene(st) as Node3D
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps else null


func _load_scene_target() -> bool:
	var ps := ResourceLoader.load(String(job["scene"]), "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if ps == null:
		_die("讀不到場景 %s" % job["scene"])
		return false
	var sc := ps.instantiate() as Node3D
	root.add_child(sc)
	target = sc.get_node_or_null(NodePath(String(job["node"]))) as Node3D
	if target == null:
		_die("場景裡沒有節點 %s" % job["node"])
		return false
	_fix_time(sc)
	for f in 4:
		await process_frame
	ground = null
	manifest["scene"] = job["scene"]
	manifest["node"] = job["node"]
	return true


func _fix_time(sc: Node) -> void:
	var sky: Node = sc.get_node_or_null("Lighting/天象系統")
	if sky != null:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", float(job.get("hour", 10.0)))
	var dn := root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
		if dn.has_method("set_hour"):
			dn.call("set_hour", float(job.get("hour", 10.0)))


# ─────────────────────────── 構件與建築座標 ───────────────────────────

func _collect_parts() -> void:
	parts.clear()
	var seen := {}
	var only: Array = job.get("target_parts", [])
	for mi: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if not only.is_empty() and not String(mi.name) in only:
			continue
		var nm := String(mi.name)
		if seen.has(nm):
			nm = String(target.get_path_to(mi))
		seen[nm] = true
		parts.append({"name": nm, "node": mi, "color": _id_color(parts.size() + 1)})
	var pl: Array = []
	for p: Dictionary in parts:
		pl.append({"name": p["name"], "color": _c8(p["color"]), "path": String(target.get_path_to(p["node"]))})
	manifest["parts"] = pl
	if ground != null:
		manifest["ground_color"] = _c8(Color(1, 1, 1))


func _id_color(i: int) -> Color:
	# 6×6×6 色階（避開黑色與白色；白色保留給審查地面）
	var k := i % 214 + 1
	return Color(float(k / 36 % 6) / 5.0, float(k / 6 % 6) / 5.0, float(k % 6) / 5.0)


func _c8(c: Color) -> Array:
	return [roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255)]


func _verts_world(mi: MeshInstance3D, cap := 60000) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var step := maxi(1, vs.size() / cap)
		for i in range(0, vs.size(), step):
			out.append(xf * vs[i])
	return out


func _compute_frame() -> void:
	var b := target.global_basis.orthonormalized()
	var fl: Array = job.get("front_local", [0, 0, 1])
	var ul: Array = job.get("up_local", [0, 1, 0])
	var U := (b * Vector3(float(ul[0]), float(ul[1]), float(ul[2]))).normalized()
	var F := b * Vector3(float(fl[0]), float(fl[1]), float(fl[2]))
	F = (F - U * F.dot(U)).normalized()
	var R := F.cross(U).normalized()   # 建築面朝 F 時自己的右手
	var O := target.global_position
	frame = {"O": O, "R": R, "U": U, "F": F}
	box_lo = Vector3.INF
	box_hi = -Vector3.INF
	var part_boxes := {}
	var inv := target.global_transform.affine_inverse()
	for p: Dictionary in parts:
		var vs := _verts_world(p["node"])
		var llo := Vector3.INF
		var lhi := -Vector3.INF
		for w in vs:
			var d := w - O
			var q := Vector3(d.dot(R), d.dot(U), d.dot(F))
			box_lo = box_lo.min(q)
			box_hi = box_hi.max(q)
			var t := inv * w
			llo = llo.min(t)
			lhi = lhi.max(t)
		part_boxes[p["name"]] = {"lo": llo, "hi": lhi}
		p["local_lo"] = llo
		p["local_hi"] = lhi
	manifest["frame"] = {"origin": _v(O), "right": _v(R), "up": _v(U), "front": _v(F),
		"box_rfu_min": _v(box_lo), "box_rfu_max": _v(box_hi), "size_rfu": _v(box_hi - box_lo),
		"target_scale": _v(target.global_basis.get_scale()), "target_yaw_deg": rad_to_deg(atan2(F.x, F.z))}
	var pb := {}
	for k: String in part_boxes:
		pb[k] = {"min": _v(part_boxes[k]["lo"]), "max": _v(part_boxes[k]["hi"])}
	manifest["part_local_bounds"] = pb


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001), snappedf(v.z, 0.00001)]


func _rfu(q: Vector3) -> Vector3:
	return frame["O"] + frame["R"] * q.x + frame["U"] * q.y + frame["F"] * q.z


# ─────────────────────────── 相機 ───────────────────────────

## 視角方向（從建築中心指向相機）與影像上方向量
func _view_axes(v: String) -> Array:
	var R: Vector3 = frame["R"]
	var U: Vector3 = frame["U"]
	var F: Vector3 = frame["F"]
	match v:
		"front": return [F, U]
		"back": return [-F, U]
		"right": return [R, U]
		"left": return [-R, U]
		"top": return [U, -F]   # 正面在影像下方
	if v == "oblique":
		return [(F * cos(deg_to_rad(35.0)) + R * sin(deg_to_rad(35.0))) * cos(deg_to_rad(30.0)) + U * sin(deg_to_rad(30.0)), U]
	if v.begins_with("corner"):
		var az := deg_to_rad(45.0 + 90.0 * int(v.substr(6)))
		return [(F * cos(az) + R * sin(az)) * cos(deg_to_rad(25.0)) + U * sin(deg_to_rad(25.0)), U]
	return [F, U]


func _place_ortho(dir: Vector3, up: Vector3, center: Vector3, size_v: float) -> void:
	var z := dir.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var diag := (box_hi - box_lo).length()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = size_v
	cam.near = 0.05
	cam.far = diag * 4.0 + 50.0
	cam.global_transform = Transform3D(Basis(x, y, z), center + z * (diag + 10.0))


func _fit_ortho(v: String) -> Dictionary:
	var ax := _view_axes(v)
	var z: Vector3 = (ax[0] as Vector3).normalized()
	var x: Vector3 = (ax[1] as Vector3).cross(z).normalized()
	var y := z.cross(x)
	var xs := []
	var ys := []
	for i in 8:
		var q := Vector3(box_hi.x if i & 1 else box_lo.x, box_hi.y if i & 2 else box_lo.y, box_hi.z if i & 4 else box_lo.z)
		var w := _rfu(q)
		xs.append(w.dot(x))
		ys.append(w.dot(y))
	var cx := (float(xs.min()) + float(xs.max())) * 0.5
	var cy := (float(ys.min()) + float(ys.max())) * 0.5
	var aspect := float(res.x) / float(res.y)
	var margin := float(job.get("margin", 0.12))
	var sz := maxf(float(ys.max()) - float(ys.min()), (float(xs.max()) - float(xs.min())) / aspect) * (1.0 + margin)
	var c3 := _rfu((box_lo + box_hi) * 0.5)
	var center := c3 + x * (cx - c3.dot(x)) + y * (cy - c3.dot(y))
	_place_ortho(z, ax[1], center, sz)
	return {"projection": "ortho", "size": sz, "m_per_px": sz / res.y}


func _fit_persp(v: String, fov := 35.0) -> Dictionary:
	var ax := _view_axes(v)
	var c := _rfu((box_lo + box_hi) * 0.5)
	var r := (box_hi - box_lo).length() * 0.5
	var d := r / sin(deg_to_rad(fov * 0.5)) * 1.05
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = fov
	cam.near = 0.05
	cam.far = d + r * 4.0 + 50.0
	var pos := c + (ax[0] as Vector3).normalized() * d
	cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(c, ax[1])
	return {"projection": "perspective", "fov": fov, "distance": d}


func _cam_info() -> Dictionary:
	var b := cam.global_basis
	return {"origin": _v(cam.global_position), "x": _v(b.x), "y": _v(b.y), "z": _v(b.z),
		"projection": "ortho" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
		"size": cam.size, "fov": cam.fov, "near": cam.near, "far": cam.far, "keep_aspect": "height"}


func _px(w: Vector3) -> Variant:
	if cam.is_position_behind(w):
		return null
	var p := cam.unproject_position(w)
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


# ─────────────────────────── 拍攝 ───────────────────────────

func _grab(path: String) -> void:
	for f in settle:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)


func _set_target_visible(on: bool) -> void:
	for p: Dictionary in parts:
		(p["node"] as MeshInstance3D).visible = on


## 純色 ID 遮罩：只畫 mask_layers 上的東西，每個構件一個 unshaded 顏色；無霧、無 AA、線性色調
func _grab_id(path: String, focus_names: Array, with_ground: bool) -> void:
	var saved := []
	var msaa := root.msaa_3d
	var ssaa := root.screen_space_aa
	var taa := root.use_taa
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false
	var mask := L_TARGET
	for p: Dictionary in parts:
		var mi: MeshInstance3D = p["node"]
		saved.append([mi, mi.material_override, mi.layers, mi.cast_shadow])
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = p["color"]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.set("disable_fog", true)
		mi.material_override = m
		var use := focus_names.is_empty() or String(p["name"]) in focus_names
		mi.layers = (L_FOCUS if not focus_names.is_empty() else L_TARGET) if use else 0
	if not focus_names.is_empty():
		mask = L_FOCUS
	if ground != null:
		saved.append([ground, ground.material_override, ground.layers, ground.cast_shadow])
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color.WHITE
		gm.set("disable_fog", true)
		ground.material_override = gm
		ground.layers = L_GROUND
		if with_ground:
			mask |= L_GROUND
	var cull := cam.cull_mask
	cam.cull_mask = mask
	cam.environment = flat_env
	cam.attributes = flat_attr
	await _grab(path)
	cam.cull_mask = cull
	cam.environment = null
	cam.attributes = null
	for s: Array in saved:
		var gi: GeometryInstance3D = s[0]
		gi.material_override = s[1]
		gi.layers = s[2]
		gi.cast_shadow = s[3]
	root.msaa_3d = msaa
	root.screen_space_aa = ssaa
	root.use_taa = taa


## 深度正確的可見遮罩：目標＝ID 色，其他所有幾何＝純黑 unshaded（照樣參與深度測試、擋住目標）。
## 補「一般 − 隱藏」色差法的盲點：目標顏色和背後東西相近時，色差法會少算可見像素。
func _grab_vis(path: String) -> void:
	var saved := []
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	black.set("disable_fog", true)
	var mine := {}
	for p: Dictionary in parts:
		mine[p["node"]] = true
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if mine.has(gi) or not gi.is_visible_in_tree():
			continue
		saved.append([gi, gi.material_override])
		gi.material_override = black
	for p: Dictionary in parts:
		var mi: MeshInstance3D = p["node"]
		saved.append([mi, mi.material_override])
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = p["color"]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.set("disable_fog", true)
		mi.material_override = m
	var msaa := root.msaa_3d
	var ssaa := root.screen_space_aa
	var taa := root.use_taa
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false
	cam.environment = flat_env
	cam.attributes = flat_attr
	await _grab(path)
	cam.environment = null
	cam.attributes = null
	for s: Array in saved:
		(s[0] as GeometryInstance3D).material_override = s[1]
	root.msaa_3d = msaa
	root.screen_space_aa = ssaa
	root.use_taa = taa


func _record(entry: Dictionary) -> void:
	entry["camera"] = _cam_info()
	var O: Vector3 = frame["O"]
	var U: Vector3 = frame["U"]
	entry["px_origin"] = _px(O)
	entry["px_origin_up"] = _px(O + U * maxf(1.0, box_hi.y))
	if ground != null:
		entry["px_ground_origin"] = _px(Vector3(O.x, ground.global_position.y, O.z))
	manifest["images"].append(entry)


func _shoot_view(v: String, suffix := "", normal_only := false) -> void:
	var info := _fit_persp(v) if (v == "oblique" or v.begins_with("corner")) else _fit_ortho(v)
	var base := out_dir.path_join(v + suffix)
	await _grab(base + ".png")
	var e := {"kind": "view", "view": v, "file": v + suffix + ".png"}
	e.merge(info)
	if not normal_only:
		_set_target_visible(false)
		await _grab(base + "_hidden.png")
		_set_target_visible(true)
		await _grab_id(base + "_id.png", [], false)
		await _grab_vis(base + "_vis.png")
		e["hidden"] = v + suffix + "_hidden.png"
		e["id"] = v + suffix + "_id.png"
		e["vis"] = v + suffix + "_vis.png"
		# 逐構件單獨遮罩（不被其他構件遮住）：俯視時梁被屋頂整個蓋住，重心偏移只能這樣量
		if v in job.get("part_solo_views", ["top", "front"]) and parts.size() <= int(job.get("part_solo_max", 24)):
			var ps := {}
			for i in parts.size():
				var nm := String(parts[i]["name"])
				var fn := "%s%s_part%02d.png" % [v, suffix, i]
				await _grab_id(out_dir.path_join(fn), [nm], false)
				ps[nm] = fn
			e["part_solo"] = ps
	_record(e)


## 特寫：錨點＝結果列錨點物件 AABB 內的 uvw（Blender (u,v,w) → Godot (u, w, 1−v)）
func _focus_point(t: Dictionary) -> Variant:
	var an := String(t.get("anchor_object", ""))
	var part: Dictionary = {}
	for p: Dictionary in parts:
		if String(p["name"]) == an or String(p["name"]) == an.validate_node_name():
			part = p
	if part.is_empty():
		return null
	var u: Array = t["uvw"]
	var lo: Vector3 = part["local_lo"]
	var hi: Vector3 = part["local_hi"]
	var q := Vector3(float(u[0]), float(u[2]), 1.0 - float(u[1]))
	return target.global_transform * (lo + (hi - lo) * q)


func _shoot_focus(targets: Array, suffix: String) -> void:
	for i in targets.size():
		var t: Dictionary = targets[i]
		var fid := String(t.get("id", "f%02d" % i))
		var pw: Variant = _focus_point(t)
		if pw == null:
			manifest["images"].append({"kind": "focus", "focus": fid, "rule_id": t.get("rule_id"), "status": "UNKNOWN",
				"reason": "錨點物件 %s 不在目標構件中（GLB 與 .blend 名稱不一致？）" % t.get("anchor_object")})
			continue
		var radius := maxf(float(t.get("radius", 0.3)), 0.2)
		var names: Array = []
		for n: String in t.get("object_ids", []):
			names.append(n)
			names.append(n.validate_node_name())
		for v: String in t.get("views", ["front", "right"]):
			var ax := _view_axes(v)
			var sz := maxf(radius * 2.6, float(job.get("focus_min_size", 0.5)))
			_place_ortho(ax[0], ax[1], pw, sz)
			var stem := "%s_%s%s" % [fid, v, suffix]
			await _grab(out_dir.path_join(stem + ".png"))
			await _grab_id(out_dir.path_join(stem + "_id.png"), names, true)
			var e := {"kind": "focus", "focus": fid, "rule_id": t.get("rule_id"), "view": v, "file": stem + ".png",
				"id": stem + "_id.png", "projection": "ortho", "size": sz, "m_per_px": sz / res.y,
				"point": _v(pw), "objects": t.get("object_ids", []), "variant": suffix.trim_prefix("_")}
			e["px_point"] = _px(pw)
			_record(e)


## 修正預覽的視覺前後比較：只在記憶體內平移，拍完還原
func _shoot_variant(vr: Dictionary) -> void:
	var saved := []
	var tb := target.global_basis
	for mv: Dictionary in vr.get("moves", []):
		var t: Array = mv["translate_blender"]
		var d := tb * Vector3(float(t[0]), float(t[2]), -float(t[1]))
		for p: Dictionary in parts:
			if String(p["name"]) == String(mv["node"]) or String(p["name"]) == String(mv["node"]).validate_node_name():
				var n: Node3D = p["node"]
				saved.append([n, n.global_position])
				n.global_position += d
	await _shoot_focus(vr.get("focus", []), "_" + String(vr.get("name", "after")))
	for s: Array in saved:
		(s[0] as Node3D).global_position = s[1]
	manifest["notes"].append("variant %s：移動 %d 個節點，拍完已還原" % [vr.get("name"), saved.size()])


# ─────────────────────────── 地圖 ───────────────────────────

func _run_map() -> void:
	var ps := ResourceLoader.load(String(job["scene"]), "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if ps == null:
		_die("讀不到場景 %s" % job["scene"])
		return
	var sc := ps.instantiate() as Node3D
	root.add_child(sc)
	_fix_time(sc)
	for f in 6:
		await process_frame
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var rg: Array = job["region"]   # [x0, z0, x1, z1]
	var x0 := float(rg[0])
	var z0 := float(rg[1])
	var x1 := float(rg[2])
	var z1 := float(rg[3])
	var top := float(job.get("top_y", 300.0))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = z1 - z0
	cam.near = 1.0
	cam.far = top + 400.0
	var aspect := (x1 - x0) / (z1 - z0)
	root.size = Vector2i(roundi(res.y * aspect), res.y)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3((x0 + x1) * 0.5, top, (z0 + z1) * 0.5))
	await _grab(out_dir.path_join("map_top.png"))
	manifest["images"].append({"kind": "map_top", "file": "map_top.png", "camera": _cam_info(), "region": rg,
		"resolution": [root.size.x, root.size.y], "m_per_px": (z1 - z0) / res.y})
	# 建築事實：腳印（碰撞形狀凸包）＋路面侵入（arch_spatial_lib，與快速通道第 4 項同一份）
	var lines := ARCH.road_lines(String(job.get("layout", "res://maps/village_v2/layout_v2.json")))
	var bl: Array = []
	var cands: Array = []
	for grp in ["FastLane", "Landmarks", "Districts"]:
		var g := sc.get_node_or_null(grp)
		if g == null:
			continue
		for n: Node in g.find_children("*", "Node3D", true, false):
			var nm := String(n.name)
			if (grp == "FastLane" and n.get_parent() == g) or (grp == "Landmarks" and nm == "Hero") or (grp == "Districts" and nm.begins_with("B_")):
				cands.append(n)
	for n: Node3D in cands:
		var c := n.global_position
		if c.x < x0 or c.x > x1 or c.z < z0 or c.z > z1:
			continue
		# 逐碰撞形狀各自取腳印（鳥居兩柱之間不是腳印；整體凸包會把跨路的門當成佔路）
		var polys := _shape_footprints(n)
		var method := "collision_shapes"
		if polys.is_empty():
			polys = _mesh_footprints(n)   # 沒有碰撞（市場灰盒）：退回可見網格 AABB
			method = "mesh_aabb"
		var e := {"path": String(sc.get_path_to(n)), "pos": _v(c), "footprint": [], "parts": [], "method": method}
		var hull := ARCH.footprint_xz(n)
		for q in hull:
			e["footprint"].append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
		var worst := INF
		for poly: PackedVector2Array in polys:
			var pp: Array = []
			for q in poly:
				pp.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
			e["parts"].append(pp)
			if e["footprint"].is_empty():
				e["footprint"] = pp
			if lines.is_empty():
				continue
			var ri := ARCH.road_intrusion(lines, poly)
			if ri.has("edge_dist") and float(ri["edge_dist"]) < worst:
				worst = float(ri["edge_dist"])
				e["road_edge_dist"] = snappedf(worst, 0.001)
				e["road"] = String(ri.get("name", ""))
				var at: Vector2 = ri.get("at", Vector2.ZERO)
				e["road_at"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01)]
		if polys.is_empty():
			e["note"] = "沒有碰撞形狀也沒有可見網格，腳印未知"
		bl.append(e)
	manifest["buildings"] = bl
	# 玩家視角＋地標可見率
	var terrain := sc.get_node_or_null("Collision/TerrainCollision") as CollisionObject3D
	var space := sc.get_world_3d().direct_space_state
	root.size = res
	for pv: Dictionary in job.get("player_views", []):
		var p2: Array = pv["pos"]
		var l2: Array = pv["look"]
		var gy: Variant = _ground_y(space, terrain, Vector3(float(p2[0]), 500, float(p2[1])))
		var lg: Variant = _ground_y(space, terrain, Vector3(float(l2[0]), 500, float(l2[1])))
		if gy == null:
			manifest["images"].append({"kind": "player", "name": pv["name"], "status": "UNKNOWN", "reason": "地形射線打不到"})
			continue
		var eye := Vector3(float(p2[0]), float(gy) + 1.7, float(p2[1]))
		var look := Vector3(float(l2[0]), (float(lg) if lg != null else float(gy)) + 1.7, float(l2[1]))
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 60
		cam.near = 0.1
		cam.far = 1500
		cam.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
		var stem := "player_%s" % pv["name"]
		await _grab(out_dir.path_join(stem + ".png"))
		var e := {"kind": "player", "name": pv["name"], "file": stem + ".png", "eye": _v(eye), "look": _v(look), "landmarks": []}
		for lp: String in job.get("landmarks", []):
			var ln := sc.get_node_or_null(NodePath(lp)) as Node3D
			if ln == null:
				e["landmarks"].append({"path": lp, "status": "UNKNOWN", "reason": "節點不存在"})
				continue
			target = ln
			_collect_parts()
			if parts.is_empty():
				continue
			var lstem := "%s__%s" % [stem, lp.replace("/", "_")]
			_set_target_visible(false)
			await _grab(out_dir.path_join(lstem + "_hidden.png"))
			_set_target_visible(true)
			ground = null
			await _grab_id(out_dir.path_join(lstem + "_id.png"), [], false)
			await _grab_vis(out_dir.path_join(lstem + "_vis.png"))
			e["landmarks"].append({"path": lp, "hidden": lstem + "_hidden.png", "id": lstem + "_id.png", "vis": lstem + "_vis.png",
				"in_frustum": cam.is_position_in_frustum(ln.global_position), "px": _px(ln.global_position)})
		e["camera"] = _cam_info()
		manifest["images"].append(e)


func _shape_footprints(n: Node3D) -> Array:
	var out: Array = []
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.disabled or cs.shape == null:
			continue
		var bb := cs.shape.get_debug_mesh().get_aabb()
		var pts := PackedVector2Array()
		for x in [bb.position.x, bb.end.x]:
			for z in [bb.position.z, bb.end.z]:
				var w := cs.global_transform * Vector3(x, bb.position.y, z)
				pts.append(Vector2(w.x, w.z))
		var h := Geometry2D.convex_hull(pts)
		if h.size() >= 3:
			out.append(h)
	return out


func _mesh_footprints(n: Node3D) -> Array:
	var out: Array = []
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var bb := mi.get_aabb()
		var pts := PackedVector2Array()
		for x in [bb.position.x, bb.end.x]:
			for z in [bb.position.z, bb.end.z]:
				var w := mi.global_transform * Vector3(x, bb.position.y, z)
				pts.append(Vector2(w.x, w.z))
		var h := Geometry2D.convex_hull(pts)
		if h.size() >= 3:
			out.append(h)
	return out


func _ground_y(space: PhysicsDirectSpaceState3D, terrain: CollisionObject3D, p: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 600, p.z), Vector3(p.x, -200, p.z))
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		if terrain == null or hit["collider"] == terrain:
			return (hit["position"] as Vector3).y
		ex.append(hit["rid"])
	return null
