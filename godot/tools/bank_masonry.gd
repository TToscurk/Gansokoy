@tool
extends Node3D

## 護岸砌體細節 —— 壓頂石條、扶壁凸出、洩水孔。
##
## 為什麼存在：50m 審查連兩輪判定石岸是「一條沒有厚度的直線」。
## 對照 docs/reference/人間之里概念圖/新版水護岸概念圖.png，缺的是三樣東西：
##
##   1. 壓頂石條 —— 概念圖牆頂有一整排「比牆身更大更方正」的板石，
##      有 20–30cm 厚度、外挑 5–10cm，下緣一條連續的滴水陰影線。
##      那條陰影就是「厚度」的視覺證據；沒有它，牆頂在遠景就是一條線。
##      做成一顆顆獨立石條（帶接縫與 jitter），不是一根長條 —— 概念圖
##      的壓頂外緣是「磨圓、破損不齊」的。
##
##   2. 扶壁凸出 —— 概念圖牆面「每隔一段就往內縮或往外凸一塊，形成
##      鋸齒狀的凹凸灣」，階梯側牆整塊外凸。直牆在任何距離都是假的。
##
##   3. 洩水孔 —— 牆面中上段的深色矩形開口，概念圖有兩處在噴水，
##      孔口下方有長條深色水痕。這是護岸「有背後、有厚度」的敘事。
##
## 全部用程式生 BoxMesh + MultiMesh：這些是 blockout 級的量體，
## 尺寸還在校調，定案後才換成真正的砌石模型。
##
## 座標系與 take_fence.gd / bank_talus.gd / coping_grass.gd 共用同一組
## SEGMENTS 常數 —— 石岸段落改了，四支腳本要一起改。

const BANK_TOP := 2.955               # 石岸壓頂高度
const BANK_FACE_X := -5.0416          # 石岸臨水面外緣（實測 AABB）
const WATER_LEVEL := 0.09             # 下游水面

## 三段石岸的 z 範圍（與 take_fence / bank_talus / coping_grass 一致）
## 五段（2026-09-01 擴段）：原本只做 78m，但 B1 町家沿岸 158m，
## 有 79.7m 的建築臨著沒有護岸的裸河。新增南延／北延兩段補齊。
## 段落由「端+N牆+端」模組長度回推，餘量吸收在開口寬度裡。
const SEGMENTS: Array[Vector2] = [
	Vector2(-74.0, -43.14),    # 南延段（端+2牆+端 30.86m）
	Vector2(-38.0, -17.14),    # 南段
	Vector2(-2.5, 18.36),      # 中段
	Vector2(29.14, 40.0),      # 北段（端+端 10.86m）
	Vector2(45.14, 86.0),      # 北延段（端+3牆+端 40.86m）
]

const MAT_DRY := "res://assets/materials/river_ishigaki_dry.tres"
const MAT_WET := "res://assets/materials/river_ishigaki_wet.tres"

# ── 壓頂石條 ──────────────────────────────────────────
## 概念圖目測厚 20–30cm，取 0.25
@export var cap_thickness: float = 0.25:
	set(v):
		cap_thickness = maxf(v, 0.02)
		_rebuild()

## 往河心外挑多少 —— 概念圖 5–10cm，取 0.08。這是滴水陰影的來源
@export var cap_overhang: float = 0.08:
	set(v):
		cap_overhang = maxf(v, 0.0)
		_rebuild()

## 壓頂往岸內的進深
@export var cap_depth: float = 1.05:
	set(v):
		cap_depth = maxf(v, 0.1)
		_rebuild()

## 單顆石條沿 z 的長度
@export var cap_stone_len: float = 1.75:
	set(v):
		cap_stone_len = maxf(v, 0.2)
		_rebuild()

## 石條之間的接縫寬
@export var cap_joint: float = 0.045:
	set(v):
		cap_joint = maxf(v, 0.0)
		_rebuild()

# ── 扶壁 ────────────────────────────────────────────
## 每隔多遠來一個凸出的扶壁
@export var pier_spacing: float = 7.5:
	set(v):
		pier_spacing = maxf(v, 1.0)
		_rebuild()

## 扶壁往河心凸出多少（概念圖：半個到一個人身寬）
@export var pier_project: float = 0.42:
	set(v):
		pier_project = maxf(v, 0.0)
		_rebuild()

@export var pier_width: float = 1.6:
	set(v):
		pier_width = maxf(v, 0.2)
		_rebuild()

# ── 洩水孔 ──────────────────────────────────────────
## 每段石岸幾個洩水孔
@export var weeps_per_segment: int = 3:
	set(v):
		weeps_per_segment = maxi(v, 0)
		_rebuild()

## 孔口高程（常水位以上、牆的中上段）
@export var weep_y: float = 1.95:
	set(v):
		weep_y = v
		_rebuild()

@export var weep_size: float = 0.34:
	set(v):
		weep_size = maxf(v, 0.05)
		_rebuild()

@export var rng_seed: int = 5171:
	set(v):
		rng_seed = v
		_rebuild()

@export var rebuild: bool = false:
	set(_v):
		rebuild = false
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發。
	# typed float/int 不能與 null 比較，用哨兵值擋半成品狀態。
	if cap_thickness <= 0.0 or cap_depth <= 0.0 or cap_stone_len <= 0.0:
		return
	if pier_spacing <= 0.0 or pier_width <= 0.0:
		return

	for c in get_children():
		c.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var n_cap := _build_coping(rng)
	var n_pier := _build_piers(rng)
	var n_weep := _build_weeps(rng)

	print("[masonry] 壓頂石 %d 顆、扶壁 %d 座、洩水孔 %d 處"
			% [n_cap, n_pier, n_weep])


## 壓頂石條：一顆顆排過去，帶接縫、高程與外挑的隨機擾動。
## 外緣不齊才像被水磨過幾十年的石頭。
func _build_coping(rng: RandomNumberGenerator) -> int:
	var box := BoxMesh.new()
	box.size = Vector3(cap_depth, cap_thickness, 1.0)

	var xfs: Array[Transform3D] = []
	for seg in SEGMENTS:
		var span: float = seg.y - seg.x
		# 石條數按段長取整，實際長度由段長均分 —— 用固定長度會在每段
		# 尾端留 1.6m 裸露，遠景就是一截斷掉的壓頂。
		# 三段長度不同（20.86/20.86/10.86），每段的 actual 也不同，
		# 所以 mesh 的 z 做成 1.0 單位長，實際長度靠 instance 縮放給。
		# 直接改 box.size.z 會被最後一段覆蓋掉前兩段。
		var n := int(round(span / cap_stone_len))
		if n <= 0:
			continue
		var actual: float = span / float(n)
		var stone_z: float = actual - cap_joint
		for k in n:
			# 石條中心：外緣 = BANK_FACE_X + overhang，往岸內 cap_depth
			var jitter_x: float = rng.randf_range(-0.035, 0.02)
			var cx: float = BANK_FACE_X + cap_overhang + jitter_x - cap_depth * 0.5
			# 頂面齊岸頂：中心 = 岸頂 - 半厚
			var cy: float = BANK_TOP - cap_thickness * 0.5 + rng.randf_range(-0.012, 0.012)
			var cz: float = seg.x + actual * (float(k) + 0.5)
			# 極小的 Y 轉，讓接縫不完全平行
			var b := Basis(Vector3.UP, rng.randf_range(-0.012, 0.012))
			b = b.scaled(Vector3(1.0, 1.0, stone_z))
			xfs.append(Transform3D(b, Vector3(cx, cy, cz)))

	_add_mm("CopingStones", box, xfs, MAT_DRY)
	return xfs.size()


## 扶壁：從牆面往河心凸出的方塊，打斷直牆的連續感。
## 概念圖裡階梯側牆是最明顯的一處外凸，這裡做通則版。
func _build_piers(rng: RandomNumberGenerator) -> int:
	# 從水面下一點起，到壓頂底為止
	var top: float = BANK_TOP - cap_thickness
	var bottom: float = WATER_LEVEL - 0.25
	var h: float = top - bottom

	var box := BoxMesh.new()
	box.size = Vector3(pier_project + 0.35, h, pier_width)

	var xfs: Array[Transform3D] = []
	for seg in SEGMENTS:
		var span: float = seg.y - seg.x
		var n := int(span / pier_spacing)
		if n <= 0:
			continue
		# 均分段落，兩端各留半個間距
		var step: float = span / float(n)
		for k in n:
			var cz: float = seg.x + step * (float(k) + 0.5)
			cz += rng.randf_range(-0.5, 0.5)
			# 外緣 = 牆面 + 凸出量；方塊有一部分埋進牆體
			var cx: float = BANK_FACE_X + pier_project - (pier_project + 0.35) * 0.5
			var cy: float = bottom + h * 0.5
			xfs.append(Transform3D(Basis(), Vector3(cx, cy, cz)))

	_add_mm("Piers", box, xfs, MAT_DRY)
	return xfs.size()


## 洩水孔：牆面上的深色矩形開口，加一條往下的水痕。
## 孔本身用一個往牆內縮的暗色方塊假裝凹陷 —— blockout 階段夠用，
## 真正的凹孔要在模型上開。
func _build_weeps(rng: RandomNumberGenerator) -> int:
	var hole := BoxMesh.new()
	hole.size = Vector3(0.22, weep_size, weep_size)

	var streak := BoxMesh.new()
	# 水痕：從孔口往下拖到水面
	var streak_h: float = weep_y - WATER_LEVEL
	streak.size = Vector3(0.02, streak_h, weep_size * 0.8)

	var hole_xfs: Array[Transform3D] = []
	var streak_xfs: Array[Transform3D] = []

	for seg in SEGMENTS:
		var span: float = seg.y - seg.x
		if weeps_per_segment <= 0:
			continue
		var step: float = span / float(weeps_per_segment)
		for k in weeps_per_segment:
			var cz: float = seg.x + step * (float(k) + 0.5)
			cz += rng.randf_range(-1.2, 1.2)
			var y: float = weep_y + rng.randf_range(-0.15, 0.15)
			# 孔口略縮進牆面
			hole_xfs.append(Transform3D(Basis(),
					Vector3(BANK_FACE_X - 0.09, y, cz)))
			# 水痕貼在牆面上，往下拖到水面
			var sh: float = y - WATER_LEVEL
			var sb := Basis().scaled(Vector3(1.0, sh / streak_h, 1.0))
			streak_xfs.append(Transform3D(sb,
					Vector3(BANK_FACE_X + 0.012, WATER_LEVEL + sh * 0.5, cz)))

	_add_mm("WeepHoles", hole, hole_xfs, MAT_WET)
	_add_mm("WeepStreaks", streak, streak_xfs, MAT_WET)
	return hole_xfs.size()


func _add_mm(nm: String, mesh: Mesh, xfs: Array[Transform3D],
		mat_path: String) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])

	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	var mat := load(mat_path)
	if mat != null:
		mi.material_override = mat
	add_child(mi)
	if Engine.is_editor_hint() and get_tree() != null:
		mi.owner = get_tree().edited_scene_root
