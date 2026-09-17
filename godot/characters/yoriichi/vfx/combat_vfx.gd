extends Node
class_name CombatVFX
## 緣一戰鬥／跳躍／命中的 VFX 工廠。
## 全程序生成：貼圖、材質、粒子都在執行期建，不依賴任何第三方素材。
##
## 分層原則（與 sword_trail.gd 的雙層刀光同一套語言）：
##   外層 blend_mix  —— 保住深赤實色輪廓，這是「火」的形狀辨識來源。
##   內核 blend_add  —— 推過 glow_hdr_threshold 進 bloom，這是「熱」。
## 舊版三個爆發全用 ADD，暗色被加成亮色、輪廓被沖掉，
## 結果是一團會發光的霧，不是有形狀的火。
##
## 色階沿用已核准的刀光：
##   白熱 #FFFBE8 → 金黃 #FFD84A → 橙琥珀 #FF9D1C → 朱紅 #E9361C → 暗紅褐 #3B1713
##
## ⚠ 六個 static 簽章不得更動：
##   enemy_samurai.gd / enemy_wolf.gd / training_dummy.gd / yoriichi_character.gd
##   共 17 個呼叫點依賴它們。

const C_CORE := Color(1.000, 0.984, 0.910)   # #FFFBE8 白熱
const C_GOLD := Color(1.000, 0.847, 0.290)   # #FFD84A 金黃
const C_AMBER := Color(1.000, 0.616, 0.110)  # #FF9D1C 橙琥珀
const C_CRIMSON := Color(0.914, 0.212, 0.110) # #E9361C 朱紅
const C_EMBER := Color(0.231, 0.090, 0.075)  # #3B1713 暗紅褐

static var _spark_tex: ImageTexture = null
static var _smoke_tex: ImageTexture = null
static var _streak_tex: ImageTexture = null


static func _get_spark_texture() -> ImageTexture:
	if _spark_tex != null:
		return _spark_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x, y).distance_to(center) / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a # Sharp glowing center
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func _get_smoke_texture() -> ImageTexture:
	if _smoke_tex != null:
		return _smoke_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x, y).distance_to(center) / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a # Soft puff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


## 細長火星貼圖：頭端亮、尾端拖細。
## 參考畫面裡的火星是「短橢圓帶微弱拖尾」，不是圓點 —— 圓點讀起來像光斑不像濺出的火。
## 搭配 GPUParticles3D.transform_align = Y_TO_VELOCITY，讓每顆沿自己的飛行方向拉長。
static func _get_streak_texture() -> ImageTexture:
	if _streak_tex != null:
		return _streak_tex
	var w := 16
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		# v=0 是頭（亮、寬），v=1 是尾（暗、細）
		var v := float(y) / float(h - 1)
		var head := 1.0 - v
		var width := maxf(0.06, pow(head, 0.7))     # 尾端收細
		var bright := pow(head, 1.6)                 # 尾端變暗
		for x in range(w):
			var u := (float(x) / float(w - 1)) * 2.0 - 1.0  # -1..1
			var across := clampf(1.0 - absf(u) / width, 0.0, 1.0)
			var a := across * across * bright
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


## 建一個 unshaded quad 材質。add=true 走加法（核心／發光），false 走混色（保實色輪廓）。
static func _make_draw_mat(tex: Texture2D, add: bool, align_velocity := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	# 沿速度拉長時由 GPUParticles3D.transform_align 決定朝向，
	# 材質再做 billboard 會蓋掉它，方向就散了。
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if align_velocity else BaseMaterial3D.BILLBOARD_PARTICLES
	return m


## 一次性粒子節點的共用組裝與自動回收。
static func _emit_once(root: Node, pos: Vector3, particles: GPUParticles3D) -> void:
	root.add_child(particles)
	particles.global_position = pos
	particles.restart()
	particles.emitting = true
	var t := root.get_tree().create_timer(particles.lifetime + 0.25)
	t.timeout.connect(particles.queue_free)


## 短命暖色補光。
## 參考畫面裡角色臉、髮緣、羽織上的暖色邊光是動畫感的一大塊，
## 粒子做不出來 —— 只有真的打一盞燈才會照到角色身上。
## ⚠ 能量壓在 glow_hdr_threshold（專案 1.05~1.25）之下，
##   否則被照亮的地面會整片進 bloom，變成一塊白斑。
static func _flash_light(root: Node, pos: Vector3, color: Color, energy: float, radius: float, time: float) -> void:
	var light := OmniLight3D.new()
	light.top_level = true
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	root.add_child(light)
	light.global_position = pos
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)


## 普通命中。
## 舊版：32 顆圓點、全 ADD、方向混入隨機上飄 —— 讀起來是一球光暈。
## 現在：少量細長 streak 沿受擊法線濺出（外層 mix 保朱紅實邊）＋ 幾顆白熱核心（add）＋ 一盞暖光。
static func spawn_hit_spark(parent: Node, hit_pos: Vector3, normal: Vector3 = Vector3.UP, heavy := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root
	var dir := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP

	# --- 外層：細長火舌，沿命中方向濺開 ---
	var streaks := GPUParticles3D.new()
	streaks.top_level = true
	streaks.emitting = false
	streaks.one_shot = true
	streaks.explosiveness = 1.0
	streaks.lifetime = 0.30 if heavy else 0.22
	# 參考畫面是「中等偏少」。舊版 32/20 太密，火星糊成一片。
	streaks.amount = 12 if heavy else 8
	# 每顆沿自己的速度方向拉長 —— 這才是「濺出去」而不是「浮在那裡」。
	streaks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.06
	sm.direction = dir
	# 收窄擴散：火星要沿刀勢噴成一束，不是四面開花。
	sm.spread = 42.0
	sm.initial_velocity_min = 5.0 if heavy else 3.6
	sm.initial_velocity_max = 10.0 if heavy else 7.0
	sm.gravity = Vector3(0, -11.0, 0)
	sm.damping_min = 2.0
	sm.damping_max = 5.0
	sm.scale_min = 0.7
	sm.scale_max = 1.25 if heavy else 1.0
	var sg := Gradient.new()
	sg.set_color(0, C_GOLD)
	sg.add_point(0.45, C_AMBER)
	sg.add_point(0.78, C_CRIMSON)
	sg.set_color(1, Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sm.color_ramp = sgt

	var squad := QuadMesh.new()
	# 長寬比 1:5 —— 短橢圓帶尾，不是圓點。
	squad.size = Vector2(0.055, 0.28) if not heavy else Vector2(0.07, 0.36)
	squad.material = _make_draw_mat(_get_streak_texture(), false, true)
	streaks.draw_pass_1 = squad
	streaks.process_material = sm
	_emit_once(root, hit_pos, streaks)

	# --- 內核：撞擊點的白熱爆閃 ---
	var core := GPUParticles3D.new()
	core.top_level = true
	core.emitting = false
	core.one_shot = true
	core.explosiveness = 1.0
	core.lifetime = 0.16 if heavy else 0.12
	core.amount = 5 if heavy else 3

	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = 0.05
	cm.direction = dir
	cm.spread = 60.0
	cm.initial_velocity_min = 0.6
	cm.initial_velocity_max = 2.0
	cm.gravity = Vector3.ZERO
	cm.damping_min = 6.0
	cm.damping_max = 10.0
	cm.scale_min = 0.5
	cm.scale_max = 1.0
	var cg := Gradient.new()
	cg.set_color(0, C_CORE)
	cg.set_color(1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.0))
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	cm.color_ramp = cgt

	var cquad := QuadMesh.new()
	cquad.size = Vector2(0.30, 0.30) if heavy else Vector2(0.22, 0.22)
	cquad.material = _make_draw_mat(_get_spark_texture(), true)
	core.draw_pass_1 = cquad
	core.process_material = cm
	_emit_once(root, hit_pos, core)

	# --- 命中補光：讓受擊者身上真的被火照到 ---
	_flash_light(root, hit_pos, Color(1.0, 0.62, 0.24), 2.8 if heavy else 1.8, 3.4, 0.12)


## 忍殺的爆發。與 spawn_hit_spark 同一條管線（不新增資產），差別在
## 白金色、量多、更亮、外加一圈水平衝擊環 —— 處決必須在 0.1 秒內被認出來。
static func spawn_deathblow_burst(parent: Node, hit_pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root
	var dir := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP

	# --- 1. 白金核心爆閃（add）---
	var core := GPUParticles3D.new()
	core.top_level = true
	core.emitting = false
	core.one_shot = true
	core.explosiveness = 1.0
	core.lifetime = 0.26
	core.amount = 10

	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = 0.12
	cm.direction = dir
	cm.spread = 90.0
	cm.initial_velocity_min = 1.0
	cm.initial_velocity_max = 3.5
	cm.gravity = Vector3.ZERO
	cm.damping_min = 5.0
	cm.damping_max = 9.0
	cm.scale_min = 0.8
	cm.scale_max = 1.6
	var cg := Gradient.new()
	cg.set_color(0, Color(1.0, 1.0, 0.97))
	cg.add_point(0.4, C_CORE)
	cg.set_color(1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.0))
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	cm.color_ramp = cgt

	var cquad := QuadMesh.new()
	cquad.size = Vector2(0.55, 0.55)
	cquad.material = _make_draw_mat(_get_spark_texture(), true)
	core.draw_pass_1 = cquad
	core.process_material = cm
	_emit_once(root, hit_pos, core)

	# --- 2. 放射火舌（mix，保暗赤邊）---
	var shards := GPUParticles3D.new()
	shards.top_level = true
	shards.emitting = false
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.lifetime = 0.48
	shards.amount = 22
	shards.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.14
	sm.direction = dir
	sm.spread = 85.0
	sm.initial_velocity_min = 6.0
	sm.initial_velocity_max = 13.0
	sm.gravity = Vector3(0, -8.0, 0)
	sm.damping_min = 1.5
	sm.damping_max = 4.0
	sm.scale_min = 0.9
	sm.scale_max = 1.7
	var sg := Gradient.new()
	sg.set_color(0, C_CORE)
	sg.add_point(0.35, C_GOLD)
	sg.add_point(0.70, C_CRIMSON)
	sg.set_color(1, Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sm.color_ramp = sgt

	var squad := QuadMesh.new()
	squad.size = Vector2(0.085, 0.46)
	squad.material = _make_draw_mat(_get_streak_texture(), false, true)
	shards.draw_pass_1 = squad
	shards.process_material = sm
	_emit_once(root, hit_pos, shards)

	# --- 3. 補光：忍殺是全場最亮的一下 ---
	_flash_light(root, hit_pos + Vector3(0, 0.2, 0), Color(1.0, 0.82, 0.55), 6.5, 7.0, 0.28)


## 日之呼吸起手火光：型發動的瞬間，刀根爆出一圈金紅火焰（環狀往外＋往上），
## 加一盞暖色點光，讓角色與地面被火照亮。
## 這是「型」與「普通斬」的視覺分野 —— 玩家在 0.1 s 內要認得出自己剛按出型。
## 外層改 mix 之後火冠才有實色輪廓，不再是一圈糊掉的光暈。
static func spawn_form_ignite(parent: Node, origin: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root
	var fwd := forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

	# --- 1. 刀根白熱核心（add，進 bloom）---
	var core := GPUParticles3D.new()
	core.top_level = true
	core.emitting = false
	core.one_shot = true
	core.explosiveness = 1.0
	core.lifetime = 0.20
	core.amount = 6

	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = 0.10
	cm.direction = Vector3.UP
	cm.spread = 80.0
	cm.initial_velocity_min = 0.4
	cm.initial_velocity_max = 1.6
	cm.gravity = Vector3(0, 1.0, 0)
	cm.damping_min = 5.0
	cm.damping_max = 9.0
	cm.scale_min = 0.7
	cm.scale_max = 1.4
	var cg := Gradient.new()
	cg.set_color(0, C_CORE)
	cg.add_point(0.5, C_GOLD)
	cg.set_color(1, Color(C_AMBER.r, C_AMBER.g, C_AMBER.b, 0.0))
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	cm.color_ramp = cgt

	var cquad := QuadMesh.new()
	cquad.size = Vector2(0.40, 0.40)
	cquad.material = _make_draw_mat(_get_spark_texture(), true)
	core.draw_pass_1 = cquad
	core.process_material = cm
	_emit_once(root, origin, core)

	# --- 2. 火星噴流（沿刀身方向）---
	var jet := GPUParticles3D.new()
	jet.top_level = true
	jet.emitting = false
	jet.one_shot = true
	jet.explosiveness = 0.9
	jet.lifetime = 0.34
	jet.amount = 14
	jet.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY

	var jm := ParticleProcessMaterial.new()
	jm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	jm.emission_sphere_radius = 0.08
	jm.direction = fwd
	jm.spread = 24.0
	jm.initial_velocity_min = 5.5
	jm.initial_velocity_max = 9.5
	jm.gravity = Vector3(0, -6.0, 0)
	jm.damping_min = 1.5
	jm.damping_max = 4.0
	jm.scale_min = 0.7
	jm.scale_max = 1.2
	var jg := Gradient.new()
	jg.set_color(0, C_GOLD)
	jg.add_point(0.6, C_AMBER)
	jg.set_color(1, Color(C_CRIMSON.r, C_CRIMSON.g, C_CRIMSON.b, 0.0))
	var jgt := GradientTexture1D.new()
	jgt.gradient = jg
	jm.color_ramp = jgt

	var jquad := QuadMesh.new()
	jquad.size = Vector2(0.05, 0.26)
	jquad.material = _make_draw_mat(_get_streak_texture(), false, true)
	jet.draw_pass_1 = jquad
	jet.process_material = jm
	_emit_once(root, origin, jet)

	# --- 3. 暖色閃光燈（短、小，打在地上也不能讀成一圈光）---
	_flash_light(root, origin + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.18), 3.8, 3.6, 0.14)


# ---------------------------------------------------------------------------
# 移動塵土：刻意保持中性灰褐，不染火色。
#
# 視覺層級必須讀得出來：移動回饋 < 普通斬 < 型 < 忍殺／日暈龍。
# 如果跳躍落地也噴金紅火，玩家就分不出哪一下是「型」，
# 日之呼吸的份量會被日常動作稀釋掉。這三個維持原樣。
# ---------------------------------------------------------------------------


static func spawn_jump_dust(parent: Node, foot_pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.90
	particles.lifetime = 0.40
	particles.amount = 16

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 0.35
	mat.emission_ring_inner_radius = 0.15
	mat.emission_ring_axis = Vector3.UP
	mat.direction = Vector3(0, 0.4, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.4
	mat.gravity = Vector3(0, -1.0, 0)
	mat.scale_min = 0.25
	mat.scale_max = 0.55
	mat.color = Color(0.92, 0.88, 0.80, 0.45)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = _make_draw_mat(_get_smoke_texture(), false)
	particles.draw_pass_1 = quad
	particles.process_material = mat
	_emit_once(root, foot_pos + Vector3(0, 0.05, 0), particles)


static func spawn_land_dust(parent: Node, foot_pos: Vector3, heavy := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.50
	particles.amount = 24 if heavy else 18

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 0.5 if heavy else 0.35
	mat.emission_ring_inner_radius = 0.2
	mat.emission_ring_axis = Vector3.UP
	mat.direction = Vector3(0, 0.2, 0)
	mat.spread = 100.0
	mat.initial_velocity_min = 2.0 if heavy else 1.5
	mat.initial_velocity_max = 3.5 if heavy else 2.5
	mat.gravity = Vector3(0, -1.2, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.7 if heavy else 0.5
	mat.color = Color(0.90, 0.86, 0.78, 0.55 if heavy else 0.40)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = _make_draw_mat(_get_smoke_texture(), false)
	particles.draw_pass_1 = quad
	particles.process_material = mat
	_emit_once(root, foot_pos + Vector3(0, 0.05, 0), particles)


static func spawn_roll_dust(parent: Node, foot_pos: Vector3, dir: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var root := parent.get_tree().root

	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.lifetime = 0.35
	particles.amount = 12

	var mat := ParticleProcessMaterial.new()
	mat.direction = -dir + Vector3(0, 0.3, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3(0, -0.5, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.45
	mat.color = Color(0.92, 0.88, 0.82, 0.35)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.material = _make_draw_mat(_get_smoke_texture(), false)
	particles.draw_pass_1 = quad
	particles.process_material = mat
	_emit_once(root, foot_pos + Vector3(0, 0.05, 0), particles)
