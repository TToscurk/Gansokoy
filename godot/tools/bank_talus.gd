@tool
extends MultiMeshInstance3D

## 護岸腳部碎石帶 —— 修「無厚度硬切邊」。
##
## 為什麼存在：50m 審查判定石岸是「一條亮度均一、沒有厚度、沒有崩落
## 堆積的直線」，上下兩個平面直接以一條線相接。真實護岸的腳部一定有
## 崩落的石塊堆積（talus），那圈碎石就是把「線」變成「帶」的東西。
##
## 沿石岸臨水面外緣鋪一條碎石，段落跟著石岸走 —— 開口處不鋪，
## 那裡是人下水的地方，堆滿石頭反而擋路。
##
## 標高／原點（實測自 tools/asset_probe.py）：
##   Quaternius nature 資產原點在【底部】，與 Meshy 資產（幾何中心）相反。
##   放置算式：y = 地面 - local_bottom * scale
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

## 卵石與中型岩石；index 由 variant 選
const ROCK_PATHS: Array[String] = [
	"res://assets/nature/Pebble_Round_1.gltf",
	"res://assets/nature/Pebble_Round_3.gltf",
	"res://assets/nature/Pebble_Square_2.gltf",
	"res://assets/nature/Rock_Medium_1.gltf",
]

## 每種石頭的目標【高度】（公尺）—— 石頭在牆腳露出多高。
##
## 為什麼是陣列而不是單一 scale_base：這四件的本地尺寸差 24 倍
## （Pebble_Round_1 高 0.0955m、Rock_Medium_1 高 2.26m），共用一個
## 縮放倍率的結果是 Rock_Medium_1 × 2.2 = 4.97m —— 比房子還高的
## 巨石杵在牆腳，而卵石只有 21cm。5m 審查判定「沒有看到碎石堆，
## 只有幾顆單獨的大圓卵石」就是這麼來的。
##
## 為什麼用高度不用長邊：卵石是扁的（Pebble_Round_1 長/高 = 5.7），
## 拿長邊當基準的話高度只剩目標的 1/5，遠看就是地上一層薄砂。
## 牆腳碎石讀起來有沒有量體，看的是「露出多高」。
##
## 概念圖《新版水護岸概念圖.png》的護腳拋石：「石塊尺寸從半個人頭
## 到比人腰還大」。半個人頭 ≈ 0.12m 高，人腰 ≈ 0.9m 高。
const ROCK_TARGET: Array[float] = [0.16, 0.22, 0.30, 0.70]

const WATER_LEVEL := 0.09             # 下游水面
const BANK_FACE_X := -5.0416          # 石岸臨水面外緣（實測 AABB）

## 三段石岸的 z 範圍（與 take_fence.gd / 石岸節點一致）
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

@export var variant: int = 0:
	set(v):
		variant = clampi(v, 0, ROCK_PATHS.size() - 1)
		_build()

@export var count_per_metre: float = 1.2:
	set(v):
		count_per_metre = maxf(v, 0.0)
		_build()

## 碎石帶寬度：從臨水面往河心散開多遠
@export var band_width: float = 1.6:
	set(v):
		band_width = maxf(v, 0.05)
		_build()

## 目標尺寸的整體倍率 —— 個別石種的基準值在 ROCK_TARGET，
## 這裡只做全域微調（想整排石頭大一點／小一點時動這個）。
@export var size_mult: float = 1.0:
	set(v):
		size_mult = maxf(v, 0.05)
		_build()

@export var scale_jitter: float = 0.45:
	set(v):
		scale_jitter = clampf(v, 0.0, 0.9)
		_build()

## 沉入水面的比例 —— 腳部碎石有一半在水下才自然
@export var sink: float = 0.35:
	set(v):
		sink = clampf(v, 0.0, 0.9)
		_build()

@export var rng_seed: int = 8823:
	set(v):
		rng_seed = v
		_build()

func _ready() -> void:
	_build()

func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if count_per_metre <= 0.0 or band_width <= 0.0 or size_mult <= 0.0:
		return

	var mesh := _first_mesh(ROCK_PATHS[variant])
	if mesh == null:
		push_error("[talus] 取不到 mesh：%s" % ROCK_PATHS[variant])
		return

	var aabb := mesh.get_aabb()
	var local_bottom := aabb.position.y
	# 用【高度】當基準 —— 見 ROCK_TARGET 註解：卵石是扁的，
	# 拿長邊算會讓露出高度只剩目標的 1/5。
	var local_size: float = aabb.size.y
	if local_size <= 0.001:
		push_error("[talus] mesh 高度為 0：%s" % ROCK_PATHS[variant])
		return

	# 目標尺寸 → 縮放倍率。每個石種有自己的基準，不再共用 scale_base。
	var base_scale: float = ROCK_TARGET[variant] * size_mult / local_size

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + variant * 613

	var spots: Array[Vector2] = []      # (x, z)
	for seg in SEGMENTS:
		# count_per_metre 是「每公尺石頭數」，四個節點分攤。
		# 用 roundi 不用 int()（無條件捨去會讓短段落顆數偏少）。
		var n := maxi(1, roundi((seg.y - seg.x) * count_per_metre
				/ float(ROCK_PATHS.size())))
		for k in n:
			var z := rng.randf_range(seg.x, seg.y)
			# 越靠臨水面越密：用 sqrt 偏壓分布
			var t := rng.randf()
			var x := BANK_FACE_X + band_width * (t * t)
			spots.append(Vector2(x, z))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()

	for i in spots.size():
		var s: float = base_scale * rng.randf_range(
				1.0 - scale_jitter, 1.0 + scale_jitter)
		# 底部落在水面，再往下沉一部分。
		# sink 是絕對深度（公尺），不乘 scale —— 乘了的話大石頭沉得比
		# 小石頭深，堆積面會歪掉。
		var y: float = WATER_LEVEL - local_bottom * s - sink
		# 三軸隨機旋轉 —— 卵石不該全部同一個朝向
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		b = b.rotated(Vector3.FORWARD, rng.randf_range(-0.35, 0.35))
		mm.set_instance_transform(i,
				Transform3D(b.scaled(Vector3(s, s, s)),
						Vector3(spots[i].x, y, spots[i].y)))

	multimesh = mm
	print("[talus] %s：%d 顆，帶寬 %.2fm"
			% [ROCK_PATHS[variant].get_file(), spots.size(), band_width])


## 從 GLB/glTF 場景取第一個 Mesh —— 不寫死 ::ArrayMesh_xxxx 的內部 id，
## 重新匯入資產時那個 id 會變，寫死會在某次 reimport 後靜默失效。
func _first_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found := _find_mesh_recursive(inst)
	inst.queue_free()
	return found


func _find_mesh_recursive(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh != null:
		return node.mesh
	for child in node.get_children():
		var m := _find_mesh_recursive(child)
		if m != null:
			return m
	return null
