extends Node
class_name WolfGatsugaFX
## 牙通牙旋鑽特效：不透明鑽體 + 速度線 + 地面塵土。
##
## ⚠ 這是第二版。第一版用 blend_add 半透明渦流「包住」本體 —— 失敗：
##   加法混合本質透明，條紋加密到 30、加底噪、加內層殼、前端收尖，
##   狼的頭尾照樣穿透出來。四輪都沒救回。
##   第二版改成**旋轉段隱藏狼的網格，用不透明鑽體取代**。
##   README 說「必須配旋風／殘影／速度線材質遮蔽」，正解不是遮，是換掉。
##
## 逐幀曲線讀 assets/enemies/wolf/gatsuga_fx.json：
##   cx/cy/cz  體心（Blender 座標）
##   r90       p90 半徑 —— 90% 頂點落在內，鑽體主半徑用這個
##   rmax      最大半徑 —— 甩出的四肢尖端；本體既然藏起來就不必再蓋到它
##   active    是否在旋轉段（f30–73）
##
## ⚠ Blender z-up → Godot y-up：Blender z（高度）→ Godot y；Blender y → Godot -z。

const FX_PATH := "res://assets/enemies/wolf/gatsuga_fx.json"
const SHADER := preload("res://characters/combat/wolf_gatsuga.gdshader")

static var _curve: Dictionary = {}


static func _load() -> Dictionary:
	if not _curve.is_empty():
		return _curve
	var txt := FileAccess.get_file_as_string(FX_PATH)
	if txt.is_empty():
		push_warning("[牙通牙] 讀不到 %s" % FX_PATH)
		return {}
	var d: Variant = JSON.parse_string(txt)
	if d is Dictionary:
		_curve = d
	return _curve


## 旋轉段的起訖秒數（本體動畫全長 4 s，旋轉只在 f30–73）
static func spin_window() -> Vector2:
	var c := _load()
	if c.is_empty():
		return Vector2(1.25, 3.04)
	var fps := float(c.get("fps", 24.0))
	return Vector2(float(c.get("spin_start", 30)) / fps, float(c.get("spin_end", 73)) / fps)


static func sample(t: float) -> Dictionary:
	var c := _load()
	var rows: Array = c.get("frames", [])
	if rows.is_empty():
		return {"centre": Vector3(0, 0.4, 0), "r90": 0.27, "rmax": 0.46, "active": false}
	var fps := float(c.get("fps", 24.0))
	var fpos := clampf(t * fps, 0.0, float(rows.size() - 1))
	var i0 := int(floor(fpos))
	var i1 := mini(i0 + 1, rows.size() - 1)
	var w := fpos - float(i0)
	var a: Dictionary = rows[i0]
	var b: Dictionary = rows[i1]
	return {
		# Blender (x, y, z) → Godot (x, z, -y)
		"centre": Vector3(
			lerpf(float(a.get("cx", 0.0)), float(b.get("cx", 0.0)), w),
			lerpf(float(a.get("cz", 0.4)), float(b.get("cz", 0.4)), w),
			-lerpf(float(a.get("cy", 0.0)), float(b.get("cy", 0.0)), w)),
		"r90": lerpf(float(a.get("r90", 0.27)), float(b.get("r90", 0.27)), w),
		"rmax": lerpf(float(a.get("rmax", 0.46)), float(b.get("rmax", 0.46)), w),
		"active": int(a.get("active", 0)) == 1,
	}


## 鑽體：前端收尖的錐柱。單層、不透明。
static func make_drill(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "GatsugaDrill"
	var cyl := CylinderMesh.new()
	# ⚠ tick() 把圓柱 +y 對齊突進方向，錐尖必須在**前進側**。
	#   實測第一版把尖端放 top，結果尖朝後（尖在右、卻往左衝）。
	#   bottom 才是前進側。
	cyl.top_radius = 1.0
	cyl.bottom_radius = 0.14
	cyl.height = 1.0
	cyl.radial_segments = 20
	cyl.rings = 4
	cyl.cap_top = true
	cyl.cap_bottom = false
	mi.mesh = cyl
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	sm.set_shader_parameter("intensity", 0.0)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visible = false
	parent.add_child(mi)
	return mi


## 速度線：鑽體後方拖出的白色殘影條
static func make_streaks(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "GatsugaStreaks"
	p.amount = 70
	p.lifetime = 0.28
	p.emitting = false
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.5
	m.direction = Vector3(0, 0, -1)
	m.spread = 12.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3.ZERO
	m.scale_min = 0.6
	m.scale_max = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.88, 0.94, 1.0, 0.85))
	grad.set_color(1, Color(0.6, 0.75, 0.95, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var qm := QuadMesh.new()
	# 細長的條，不是圓點 —— 這才讀得出是速度線
	qm.size = Vector2(0.7, 0.055)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _streak_texture()
	qm.material = mat
	p.draw_pass_1 = qm
	parent.add_child(p)
	return p


## 地面塵土：突進時掃起的碎屑
static func make_dust(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "GatsugaDust"
	p.amount = 110
	p.lifetime = 0.85
	p.emitting = false
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.45
	m.direction = Vector3(0, 1, 0)
	m.spread = 60.0
	m.initial_velocity_min = 1.4
	m.initial_velocity_max = 3.8
	m.gravity = Vector3(0, -3.4, 0)
	m.damping_min = 1.5
	m.damping_max = 3.5
	m.scale_min = 0.6
	m.scale_max = 1.6
	var grad := Gradient.new()
	grad.set_color(0, Color(0.66, 0.60, 0.50, 0.85))
	grad.set_color(1, Color(0.54, 0.49, 0.43, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	p.process_material = m
	var qm := QuadMesh.new()
	qm.size = Vector2(0.26, 0.26)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	qm.material = mat
	p.draw_pass_1 = qm
	parent.add_child(p)
	return p


static var _puff: ImageTexture = null
static var _streak: ImageTexture = null


static func _puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var c := Vector2(15.5, 15.5)
	for y in 32:
		for x in 32:
			var d := Vector2(x, y).distance_to(c) / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_puff = ImageTexture.create_from_image(img)
	return _puff


## 細長條：兩端尖、中間亮
static func _streak_texture() -> ImageTexture:
	if _streak != null:
		return _streak
	var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 64:
			var fx := absf(float(x) - 31.5) / 31.5
			var fy := absf(float(y) - 3.5) / 3.5
			var a := clampf(1.0 - fx, 0.0, 1.0) * clampf(1.0 - fy, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_streak = ImageTexture.create_from_image(img)
	return _streak


## 每幀更新。t = Gatsuga 動畫經過秒數，forward = 突進方向（世界、水平）。
## wolf_mesh 是狼的視覺根 —— 旋轉段會被隱藏，由鑽體取代。
static func tick(drill: MeshInstance3D, dust: GPUParticles3D, streaks: GPUParticles3D,
		owner_node: Node3D, wolf_mesh: Node3D, t: float, forward: Vector3,
		scale_mult: float) -> void:
	var s: Dictionary = sample(t)
	var active: bool = s["active"]

	# ★ 核心：旋轉段藏起本體。半透明遮罩救不了「側翻不是鑽頭」，換掉才行。
	if wolf_mesh != null:
		wolf_mesh.visible = not active

	if drill != null:
		drill.visible = active
		if active:
			var win := spin_window()
			var fade_in := clampf((t - win.x) / 0.12, 0.0, 1.0)
			var fade_out := clampf((win.y - t) / 0.18, 0.0, 1.0)
			var sm := drill.material_override as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("intensity", minf(fade_in, fade_out))
			# 本體已藏，半徑用 r90 即可（rmax 是甩出的四肢尖端，不必再蓋）
			var r: float = float(s["r90"]) * scale_mult * 1.35
			var length := r * 4.6
			drill.scale = Vector3(r, length, r)
			var c: Vector3 = s["centre"]
			# ⚠ 曲線的 cz 是體心高度，但鑽體是沿突進方向躺著的圓柱，
			#   中心必須落在體心上；直接用 c.y 會讓鑽浮在體心之上半個身長
			#   （實測第一版離地約 0.5 m）。下限是半徑，避免埋進地裡。
			drill.position = Vector3(c.x * scale_mult,
				maxf(c.y * scale_mult * 0.72, r),
				c.z * scale_mult)
			var fwd := forward
			fwd.y = 0.0
			if fwd.length() > 0.01:
				fwd = fwd.normalized()
				var axis := Vector3.UP.cross(fwd)
				if axis.length() > 0.001:
					drill.rotation = Basis(axis.normalized(),
						Vector3.UP.angle_to(fwd)).get_euler()
	if dust != null:
		dust.emitting = active
		if active and owner_node != null:
			dust.global_position = owner_node.global_position
	if streaks != null:
		streaks.emitting = active
		if active and owner_node != null:
			streaks.global_position = owner_node.global_position + Vector3(0, 0.6 * scale_mult, 0)


## 收招：把狼的網格放回來，關掉所有特效。
static func stop(drill: MeshInstance3D, dust: GPUParticles3D, streaks: GPUParticles3D,
		wolf_mesh: Node3D) -> void:
	if wolf_mesh != null:
		wolf_mesh.visible = true
	if drill != null:
		drill.visible = false
	if dust != null:
		dust.emitting = false
	if streaks != null:
		streaks.emitting = false
