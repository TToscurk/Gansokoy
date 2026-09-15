extends Node3D
class_name Kedama
## 毛玉 —— 東方裡最基本的小妖怪。程序化造型：一顆毛球 + 兩顆眼睛，
## 沒有外部資產。做成通用小妖怪，逃跑妖怪與受傷妖怪都用它。
##
## 行為只有三種，由 mode 決定：
##   IDLE     原地飄浮呼吸
##   FLEE     看到玩家就往 flee_dir 跑，跑出 flee_distance 後消失（MQ03 不要追）
##   WOUNDED  縮在地上發抖，不動（受傷妖怪事件；離開由劇情腳本呼叫 flee_away()）
##
## 不認識任務、不認識對話；只發訊號。
##
## ══ 2026-09-15 修正（實測 tools/audit_kedama.gd）══
##  1. **逃跑時貼地**。舊版逃跑只改水平位置、y 完全不動，而獸道往東北爬升——
##     實測逃 18 m 地面升了 5.51 m，毛玉整隻埋進土裡（逃 6 m 就沉 2.15 m）。
##     現在每幀對地面射線取樣，讓飄浮高度跟著地形走。
##  2. **眼睛露出來**。毛尖在半徑 0.418–0.502 m、眼球外緣只有 0.358 m，
##     眼睛整個陷在毛層裡（差 0.060 m），正面根本看不到臉。
##     現在臉部留空（毛不長在正面錐角內），眼睛也往外移。
##  3. **逃跑不穿樹**。舊版寫死一個方向，實測那條線會穿過 1 根有碰撞的樹幹。
##     現在起跑時在扇形內挑一條沒有障礙的方向。
##  4. **不要像海膽**（使用者複檢兩次：「確實很像海膽」）。
##     第一次只把毛改短、改倒伏（sweep 70°）—— **沒用**，複檢還是說帶刺。
##     原因：不管怎麼倒，一根「末端收尖的細錐體」從輪廓看就是刺；
##     低模下靠毛髮線條做蓬鬆感是行不通的。
##     改用**重疊球團**（羊／雲的做法）：本體外圍鋪一圈半徑 0.10–0.15 m 的
##     小球，彼此重疊、埋進本體一半 —— 輪廓變成一連串圓弧凸起，
##     沒有任何尖端，這才是低模「蓬鬆」的標準解。
##     毛只留極短的絨毛當表面細節，不再參與輪廓。

enum Mode { IDLE, FLEE, WOUNDED }

signal fled          # 逃離完成（已消失）
signal noticed_player

@export var mode: Mode = Mode.IDLE
@export var radius := 0.32
@export var body_color := Color(0.93, 0.93, 0.95)
@export var eye_color := Color(0.12, 0.10, 0.14)
## 蓬鬆用的球團：數量與大小（相對本體半徑）。
## ⚠ 這是輪廓的來源，不是裝飾。球要夠大（≥30% 本體）且互相重疊，
##   輪廓才會是連續圓弧；太小會變成「長疣的球」。
@export var tuft_count := 26
@export var tuft_scale_min := 0.34
@export var tuft_scale_max := 0.50
## 球團中心埋進本體多深（0 = 貼在表面外，1 = 完全埋入）
@export_range(0.0, 1.0) var tuft_sink := 0.45
## 臉部淨空：正面這個角度（度）內不長球團，否則眼睛會被蓋住
@export var face_clear_deg := 34.0
## 飄浮高度（毛玉是飄的，不是站的）
@export var hover_height := 0.55
@export var bob_amount := 0.06
@export var bob_speed := 1.8

@export_group("Flee")
## 玩家進入這個距離就開始逃
@export var notice_range := 7.0
@export var flee_speed := 6.5
## 逃這麼遠就消失
@export var flee_distance := 18.0
## 逃跑方向（世界座標、水平）。留零則背對玩家跑
@export var flee_dir := Vector3.ZERO
## 起跑前在 ±這個角度（度）內找一條沒有樹擋住的路
@export var flee_search_deg := 55.0
## 逃跑末段淡出的距離（避免跑到一半「啪」地消失）
@export var fade_distance := 4.0

@export_group("Wounded")
## 發抖幅度
@export var tremble := 0.025

var _t := 0.0
var _noticed := false
var _fled_dist := 0.0
var _base_y := 0.0
var _body: MeshInstance3D = null
var _target: Node3D = null


func _ready() -> void:
	add_to_group("kedama")
	_build()
	_base_y = position.y


func _build() -> void:
	# 本體
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 12
	_body.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.95
	_body.material_override = mat
	_body.position.y = hover_height
	add_child(_body)

	# 蓬鬆：本體外圍鋪一圈重疊的小球（羊／雲的做法）。
	#
	# ⚠ 不要用毛髮線條。試過「短而密 + 倒伏 70°」的細錐體，複檢仍然說是海膽 ——
	#   末端收尖的東西在輪廓上就是刺，跟長度、角度無關。
	#   蓬鬆感來自**輪廓的連續圓弧**：每顆球埋進本體 45%、彼此重疊，
	#   剪影變成一串圓凸起，完全沒有尖端。
	#
	# ⚠ 臉部（+z 正面錐角內）不放球 —— 眼球外緣 0.36 m，
	#   球團會把整張臉蓋掉（實測 audit_kedama.gd）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var fur_mat := StandardMaterial3D.new()
	fur_mat.albedo_color = body_color
	fur_mat.roughness = 1.0
	var face := Vector3(0.0, 0.10, 1.0).normalized()
	var cos_clear := cos(deg_to_rad(face_clear_deg))
	for i in tuft_count:
		# 均勻分佈在球面上（黃金螺旋）
		var phi := acos(1.0 - 2.0 * (float(i) + 0.5) / float(tuft_count))
		var theta := PI * (1.0 + sqrt(5.0)) * float(i)
		var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
		if dir.dot(face) > cos_clear:
			continue          # 臉部留空
		var tr := radius * rng.randf_range(tuft_scale_min, tuft_scale_max)
		var t := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = tr
		sp.height = tr * 2.0
		sp.radial_segments = 8
		sp.rings = 5
		t.mesh = sp
		t.material_override = fur_mat
		# 球心落在「本體表面往內縮 sink×球半徑」處 → 露出約一半，彼此重疊
		t.position = dir * (radius + tr * (1.0 - tuft_sink * 2.0))
		# 稍微壓扁並隨機轉，避免看出是同一顆球複製的
		t.scale = Vector3(rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.05),
			rng.randf_range(0.85, 1.15))
		t.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU))
		_body.add_child(t)

	# 眼睛：兩顆黑珠，在正面（+z）。
	# 稍微放大並往外移到毛層之外，遠看才認得出這是一隻有臉的生物。
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = radius * 0.22
		em.height = em.radius * 2.0
		em.radial_segments = 12
		em.rings = 8
		e.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = eye_color
		emat.roughness = 0.25
		e.material_override = emat
		var ed := Vector3(sx * 0.32, 0.18, 0.92).normalized()
		e.position = ed * (radius * 1.02)
		_body.add_child(e)


## 地面高度（射線，打不到就回傳 -INF）。毛玉是飄的，但得飄在**地面上方**。
func _ground_y(x: float, z: float) -> float:
	if not is_inside_tree():
		return -INF
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, global_position.y + 30.0, z),
		Vector3(x, global_position.y - 60.0, z))
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF


## 這個水平方向 dist 公尺內有沒有東西擋著（樹幹、岩石、牆）
func _path_clear(dir: Vector3, dist: float) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, hover_height, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * dist)
	q.collision_mask = 0xFFFFFFFF
	return space.intersect_ray(q).is_empty()


## 起跑時挑一條不會撞樹的逃跑方向。
##
## ⚠ 舊版直接用寫死的 flee_dir 衝出去，實測那條線會穿過 1 根有碰撞的樹幹
##   （audit_kedama.gd）。毛玉穿過樹幹跑掉，玩家看得出來。
##   這裡以原方向為中心，在 ±flee_search_deg 內左右交錯試，取第一條淨空的。
func _pick_flee_dir(want: Vector3) -> Vector3:
	var base := want.normalized()
	if _path_clear(base, minf(flee_distance, 12.0)):
		return base
	var steps := 7
	for i in range(1, steps + 1):
		var a := deg_to_rad(flee_search_deg) * float(i) / float(steps)
		for s in [1.0, -1.0]:
			var cand := base.rotated(Vector3.UP, a * s)
			if _path_clear(cand, minf(flee_distance, 12.0)):
				return cand
	return base      # 都被擋住就照原方向（總比卡在原地好）


func _process(delta: float) -> void:
	_t += delta
	if _target == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			_target = ps[0]
	match mode:
		Mode.IDLE:
			_body.position.y = hover_height + sin(_t * bob_speed) * bob_amount
		Mode.WOUNDED:
			# 縮在地上、細微發抖
			_body.position.y = radius * 0.85 + sin(_t * 23.0) * tremble
			_body.position.x = sin(_t * 31.0) * tremble * 0.6
			# 縮小一點，看起來蜷著
			_body.scale = Vector3.ONE * 0.88
			if _target != null:
				var to := _target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.01:
					# 面向玩家（害怕地盯著）
					var want := atan2(to.x, to.z)
					rotation.y = lerp_angle(rotation.y, want, 4.0 * delta)
		Mode.FLEE:
			_body.position.y = hover_height + sin(_t * bob_speed * 2.5) * bob_amount * 1.5
			if not _noticed:
				if _target != null and global_position.distance_to(_target.global_position) <= notice_range:
					_noticed = true
					noticed_player.emit()
					var want_dir := flee_dir
					if want_dir.length() < 0.01:
						var away := global_position - _target.global_position
						away.y = 0.0
						want_dir = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
					flee_dir = _pick_flee_dir(want_dir)
				return
			var step: Vector3 = flee_dir.normalized() * flee_speed * delta
			position += step
			_fled_dist += step.length()
			# ⚠ 跟著地形走。獸道往東北爬升，實測逃 18 m 地面升 5.51 m；
			#   只改水平位置的話毛玉會整隻沉進土裡（逃 6 m 就沉 2.15 m）。
			#   追隨係數不能太小：9.0 時陡坡上實測落後 0.49 m（毛玉半徑才 0.32，
			#   等於整顆浮在坡面上）。18.0 把落後壓到 0.25 m 以內，
			#   仍保有平滑、不會在地形台階上瞬移。
			var gy := _ground_y(global_position.x, global_position.z)
			if gy != -INF:
				global_position.y = lerpf(global_position.y, gy, clampf(18.0 * delta, 0.0, 1.0))
			# 面向逃跑方向
			var want := atan2(flee_dir.x, flee_dir.z)
			rotation.y = lerp_angle(rotation.y, want, 8.0 * delta)
			# 途中遇到擋路的（樹、牆）就換一條，不要卡著或穿過去
			if not _path_clear(flee_dir, 1.4):
				flee_dir = _pick_flee_dir(flee_dir)
			# 末段淡出：直接 queue_free 會「啪」地消失，玩家看得到
			var remain := flee_distance - _fled_dist
			if remain <= fade_distance:
				var a := clampf(remain / maxf(fade_distance, 0.01), 0.0, 1.0)
				_set_alpha(a)
			if _fled_dist >= flee_distance:
				fled.emit()
				queue_free()


## 整隻淡出（本體與所有毛、眼睛）
func _set_alpha(a: float) -> void:
	if _body == null:
		return
	for n in [_body] + _body.get_children():
		var mi := n as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		if a < 0.999 and m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = a


## 劇情呼叫：受傷妖怪被放走 → 慢慢退後再逃
func flee_away(dir: Vector3 = Vector3.ZERO) -> void:
	if dir.length() > 0.01:
		flee_dir = dir
	elif _target != null:
		var away := global_position - _target.global_position
		away.y = 0.0
		flee_dir = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	mode = Mode.FLEE
	_noticed = true
	_fled_dist = 0.0
	_body.scale = Vector3.ONE
